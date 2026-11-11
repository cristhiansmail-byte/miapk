--
-- PostgreSQL database dump
--

\restrict hFLFctOMgk6bCbkLfp97L9MXZWkQKBml9t5rRMhegEtW0n00bnB0SGTYbp7LI8M

-- Dumped from database version 17.11
-- Dumped by pg_dump version 17.11 (Ubuntu 17.11-1.pgdg26.04+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: miapk; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA miapk;


--
-- Name: bitacora_agregar(uuid, text, text, jsonb); Type: FUNCTION; Schema: miapk; Owner: -
--

CREATE FUNCTION miapk.bitacora_agregar(p_actor uuid, p_accion text, p_objeto text, p_detalle jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_prev text;
begin
  select b.hash into v_prev from miapk.bitacora b order by b.id desc limit 1;
  insert into miapk.bitacora (actor_id, accion, objeto, detalle, hash_anterior, hash)
  values (p_actor, p_accion, p_objeto, p_detalle, v_prev,
          encode(sha256(convert_to(coalesce(v_prev, '') || p_detalle::text, 'UTF8')), 'hex'));
end $$;


--
-- Name: cerrar_mis_sesiones(); Type: FUNCTION; Schema: miapk; Owner: -
--

CREATE FUNCTION miapk.cerrar_mis_sesiones() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare n int;
begin
  if auth.uid() is null then return jsonb_build_object('estado','rechazado','motivo','sin sesión'); end if;
  delete from auth.sessions where user_id = auth.uid();
  get diagnostics n = row_count;
  perform miapk.bitacora_agregar((select id from miapk.actores where auth_uid = auth.uid() limit 1), 'sesion.cerrar_todas', 'auth.sessions',
          jsonb_build_object('uid', auth.uid(), 'sesiones_cerradas', n));
  return jsonb_build_object('estado','cerradas','sesiones', n);
end $$;


--
-- Name: es_direccion_mfa(); Type: FUNCTION; Schema: miapk; Owner: -
--

CREATE FUNCTION miapk.es_direccion_mfa() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce((auth.jwt() ->> 'aal') = 'aal2', false)
     and exists (select 1 from miapk.actores a
                 where a.auth_uid = auth.uid() and a.hat = 'direccion' and a.activo);
$$;


--
-- Name: etiquetar_error(); Type: FUNCTION; Schema: miapk; Owner: -
--

CREATE FUNCTION miapk.etiquetar_error() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  new.origen := coalesce(nullif(new.cuerpo ->> 'origen', ''),
                         case when new.fuente_id is null then 'sin fuente identificable' else 'sin etiqueta' end);
  return new;
end $$;


--
-- Name: fuente_integrada(text); Type: FUNCTION; Schema: miapk; Owner: -
--

CREATE FUNCTION miapk.fuente_integrada(p_fuente text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (select 1 from miapk.credenciales_fuente c where c.fuente_id = p_fuente and c.activa);
$$;


--
-- Name: osi_aprobar(uuid, text); Type: FUNCTION; Schema: miapk; Owner: -
--

CREATE FUNCTION miapk.osi_aprobar(p_version_id uuid, p_texto_literal text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_dir uuid; v miapk.osi_versiones; v_actual text; v_dec uuid;
begin
  if not miapk.es_direccion_mfa() then
    perform miapk.bitacora_agregar(null, 'osi.rechazo', p_version_id::text, jsonb_build_object('intento', 'aprobar', 'uid', auth.uid(), 'aal', auth.jwt() ->> 'aal', 'motivo', 'no es Dirección con aal2'));
    return jsonb_build_object('estado', 'rechazado', 'motivo', 'solo Dirección con doble verificación puede aprobar');
  end if;
  if coalesce(trim(p_texto_literal), '') = '' then raise exception 'OSI: falta el texto literal de la aprobación'; end if;
  select id into v_dir from miapk.actores where auth_uid = auth.uid() and hat = 'direccion' and activo;
  select * into v from miapk.osi_versiones where id = p_version_id for update;
  if v.id is null or v.estado <> 'en_revision' then raise exception 'OSI: solo se aprueba una versión en revisión'; end if;
  v_actual := encode(sha256(convert_to(coalesce(v.contenido, ''), 'UTF8')), 'hex');
  if v_actual <> v.sha256 then raise exception 'OSI: el contenido no coincide con su hash; no se puede aprobar'; end if;
  insert into miapk.decisiones (actor_id, objeto_tipo, objeto_id, decision, texto_literal)
  values (v_dir, 'osi_version', p_version_id::text, 'aprobar', p_texto_literal) returning id into v_dec;
  insert into miapk.osi_aprobaciones (version_id, decision_id, sha256_aprobado) values (p_version_id, v_dec, v_actual);
  update miapk.osi_versiones set estado = 'aprobado' where id = p_version_id;
  insert into miapk.osi_transiciones (version_id, de, a, actor_id, sha256) values (p_version_id, 'en_revision', 'aprobado', v_dir, v_actual);
  perform miapk.bitacora_agregar(v_dir, 'osi.aprobado', p_version_id::text, jsonb_build_object('sha256', v_actual, 'decision_id', v_dec));
  return jsonb_build_object('estado', 'aprobado', 'sha256', v_actual);
end $$;


--
-- Name: osi_enviar_a_revision(uuid); Type: FUNCTION; Schema: miapk; Owner: -
--

CREATE FUNCTION miapk.osi_enviar_a_revision(p_version_id uuid) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_magda uuid; v_sha text;
begin
  select id into v_magda from miapk.actores where hat = 'magda' limit 1;
  update miapk.osi_versiones set estado = 'en_revision' where id = p_version_id and estado = 'borrador'
  returning sha256 into v_sha;
  if v_sha is null then raise exception 'OSI: la versión no está en borrador'; end if;
  insert into miapk.osi_transiciones (version_id, de, a, actor_id, sha256) values (p_version_id, 'borrador', 'en_revision', v_magda, v_sha);
  perform miapk.bitacora_agregar(v_magda, 'osi.en_revision', p_version_id::text, jsonb_build_object('sha256', v_sha));
  return v_sha;
end $$;


--
-- Name: osi_poner_vigente(uuid); Type: FUNCTION; Schema: miapk; Owner: -
--

CREATE FUNCTION miapk.osi_poner_vigente(p_version_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_dir uuid; v miapk.osi_versiones; v_actual text; v_aprob text;
begin
  if not miapk.es_direccion_mfa() then
    perform miapk.bitacora_agregar(null, 'osi.rechazo', p_version_id::text, jsonb_build_object('intento', 'poner_vigente', 'uid', auth.uid(), 'aal', auth.jwt() ->> 'aal', 'motivo', 'no es Dirección con aal2'));
    return jsonb_build_object('estado', 'rechazado', 'motivo', 'solo Dirección con doble verificación puede poner vigente');
  end if;
  select id into v_dir from miapk.actores where auth_uid = auth.uid() and hat = 'direccion' and activo;
  select * into v from miapk.osi_versiones where id = p_version_id for update;
  if v.id is null or v.estado <> 'aprobado' then raise exception 'OSI: solo se pone vigente una versión aprobada'; end if;
  v_actual := encode(sha256(convert_to(coalesce(v.contenido, ''), 'UTF8')), 'hex');
  select a.sha256_aprobado into v_aprob from miapk.osi_aprobaciones a where a.version_id = p_version_id order by a.en desc limit 1;
  if v_actual <> v_aprob then raise exception 'OSI: ALERTA, el contenido cambió después de aprobado; no se puede poner vigente'; end if;
  update miapk.osi_versiones set estado = 'sustituido' where codigo = v.codigo and estado = 'vigente';
  update miapk.osi_versiones set estado = 'vigente' where id = p_version_id;
  insert into miapk.osi_transiciones (version_id, de, a, actor_id, sha256) values (p_version_id, 'aprobado', 'vigente', v_dir, v_actual);
  perform miapk.bitacora_agregar(v_dir, 'osi.vigente', p_version_id::text, jsonb_build_object('sha256', v_actual));
  return jsonb_build_object('estado', 'vigente', 'sha256', v_actual);
end $$;


--
-- Name: osi_proteger(); Type: FUNCTION; Schema: miapk; Owner: -
--

CREATE FUNCTION miapk.osi_proteger() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  if tg_op = 'DELETE' then raise exception 'OSI: las versiones no se borran'; end if;
  if tg_op = 'UPDATE' and old.estado <> 'borrador'
     and (new.contenido is distinct from old.contenido or new.sha256 is distinct from old.sha256
          or new.version is distinct from old.version or new.codigo is distinct from old.codigo) then
    raise exception 'OSI: % v% está en estado % y su contenido no se puede modificar', old.codigo, old.version, old.estado;
  end if;
  if tg_op = 'INSERT' or old.estado = 'borrador' then
    new.sha256 := encode(sha256(convert_to(coalesce(new.contenido, ''), 'UTF8')), 'hex');
  end if;
  return new;
end $$;


--
-- Name: osi_redactar(text, text, text, text, text); Type: FUNCTION; Schema: miapk; Owner: -
--

CREATE FUNCTION miapk.osi_redactar(p_codigo text, p_titulo text, p_tipo text, p_version text, p_contenido text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare v_id uuid; v_magda uuid;
begin
  select id into v_magda from miapk.actores where hat = 'magda' limit 1;
  insert into miapk.osi_documentos (codigo, titulo, tipo, nivel_acceso)
  values (p_codigo, p_titulo, p_tipo, 'direccion') on conflict (codigo) do nothing;
  insert into miapk.osi_versiones (codigo, version, estado, contenido, autor_id)
  values (p_codigo, p_version, 'borrador', p_contenido, v_magda) returning id into v_id;
  insert into miapk.osi_transiciones (version_id, de, a, actor_id, sha256)
  select v_id, null, 'borrador', v_magda, sha256 from miapk.osi_versiones where id = v_id;
  perform miapk.bitacora_agregar(v_magda, 'osi.borrador', p_codigo || ' v' || p_version, jsonb_build_object('version_id', v_id));
  return v_id;
end $$;


--
-- Name: prohibir_cambios(); Type: FUNCTION; Schema: miapk; Owner: -
--

CREATE FUNCTION miapk.prohibir_cambios() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  raise exception 'MIAPK: % es de solo agregar; no se permite %', tg_table_name, tg_op;
end $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: actores; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.actores (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    auth_uid uuid,
    nombre text NOT NULL,
    tipo text NOT NULL,
    hat text NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT actores_hat_check CHECK ((hat = ANY (ARRAY['direccion'::text, 'magda'::text, 'magid'::text, 'mia_web'::text, 'mia_apk'::text, 'operador'::text, 'sistema'::text]))),
    CONSTRAINT actores_tipo_check CHECK ((tipo = ANY (ARRAY['persona'::text, 'agente'::text, 'sistema'::text])))
);

ALTER TABLE ONLY miapk.actores FORCE ROW LEVEL SECURITY;


--
-- Name: bitacora; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.bitacora (
    id bigint NOT NULL,
    en timestamp with time zone DEFAULT now() NOT NULL,
    actor_id uuid,
    accion text NOT NULL,
    objeto text NOT NULL,
    detalle jsonb DEFAULT '{}'::jsonb NOT NULL,
    hash_anterior text,
    hash text NOT NULL
);

ALTER TABLE ONLY miapk.bitacora FORCE ROW LEVEL SECURITY;


--
-- Name: bitacora_id_seq; Type: SEQUENCE; Schema: miapk; Owner: -
--

ALTER TABLE miapk.bitacora ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME miapk.bitacora_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: casos_soporte; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.casos_soporte (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cliente_id uuid,
    entrega_id uuid,
    estado text NOT NULL,
    abierto_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT casos_soporte_estado_check CHECK ((estado = ANY (ARRAY['abierto'::text, 'cerrado'::text])))
);

ALTER TABLE ONLY miapk.casos_soporte FORCE ROW LEVEL SECURITY;


--
-- Name: clientes; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.clientes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    alias_ficticio text NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY miapk.clientes FORCE ROW LEVEL SECURITY;


--
-- Name: conversaciones; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.conversaciones (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cliente_id uuid,
    iniciada_en timestamp with time zone DEFAULT now() NOT NULL,
    necesidad_confirmada boolean DEFAULT false NOT NULL
);

ALTER TABLE ONLY miapk.conversaciones FORCE ROW LEVEL SECURITY;


--
-- Name: credenciales_fuente; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.credenciales_fuente (
    fuente_id text NOT NULL,
    hash_credencial text NOT NULL,
    activa boolean DEFAULT true NOT NULL,
    creada_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT credenciales_fuente_hash_credencial_check CHECK ((hash_credencial ~ '^[0-9a-f]{64}$'::text))
);

ALTER TABLE ONLY miapk.credenciales_fuente FORCE ROW LEVEL SECURITY;


--
-- Name: csw; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.csw (
    id text NOT NULL,
    titulo text NOT NULL,
    estado text NOT NULL,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT csw_estado_check CHECK ((estado = ANY (ARRAY['borrador'::text, 'presentado'::text, 'aprobado'::text, 'rechazado'::text, 'aprobado_alcance_limitado'::text])))
);

ALTER TABLE ONLY miapk.csw FORCE ROW LEVEL SECURITY;


--
-- Name: decisiones; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.decisiones (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    en timestamp with time zone DEFAULT now() NOT NULL,
    actor_id uuid NOT NULL,
    objeto_tipo text NOT NULL,
    objeto_id text NOT NULL,
    decision text NOT NULL,
    texto_literal text NOT NULL
);

ALTER TABLE ONLY miapk.decisiones FORCE ROW LEVEL SECURITY;


--
-- Name: entregas; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.entregas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    propuesta_id uuid,
    estado text NOT NULL,
    publicada_en timestamp with time zone,
    CONSTRAINT entregas_estado_check CHECK ((estado = ANY (ARRAY['en_produccion'::text, 'en_qa'::text, 'publicada'::text, 'aceptada'::text, 'con_incidencias'::text])))
);

ALTER TABLE ONLY miapk.entregas FORCE ROW LEVEL SECURITY;


--
-- Name: eventos; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.eventos (
    event_id uuid NOT NULL,
    type text NOT NULL,
    schema_version smallint DEFAULT 1 NOT NULL,
    occurred_at timestamp with time zone NOT NULL,
    received_at timestamp with time zone DEFAULT now() NOT NULL,
    fuente_id text NOT NULL,
    external_id text NOT NULL,
    actor_id uuid,
    subject_entity text NOT NULL,
    subject_id text NOT NULL,
    correlation_id uuid,
    causation_id uuid,
    data jsonb DEFAULT '{}'::jsonb NOT NULL,
    firma_verificada boolean DEFAULT false NOT NULL,
    hash_cuerpo text NOT NULL,
    CONSTRAINT eventos_type_check CHECK ((type ~ '^[a-z_]+\.[a-z_]+\.[a-z_]+$'::text))
);

ALTER TABLE ONLY miapk.eventos FORCE ROW LEVEL SECURITY;


--
-- Name: COLUMN eventos.firma_verificada; Type: COMMENT; Schema: miapk; Owner: -
--

COMMENT ON COLUMN miapk.eventos.firma_verificada IS 'true = la credencial de la fuente fue validada contra su hash. NO es una firma digital del origen; la firma criptográfica (p. ej. webhook firmado) llega con fuentes reales.';


--
-- Name: eventos_errores; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.eventos_errores (
    id bigint NOT NULL,
    recibido_en timestamp with time zone DEFAULT now() NOT NULL,
    fuente_id text,
    motivo text NOT NULL,
    cuerpo jsonb NOT NULL,
    origen text
);

ALTER TABLE ONLY miapk.eventos_errores FORCE ROW LEVEL SECURITY;


--
-- Name: eventos_errores_id_seq; Type: SEQUENCE; Schema: miapk; Owner: -
--

ALTER TABLE miapk.eventos_errores ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME miapk.eventos_errores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: evidencias; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.evidencias (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    orden_id text,
    descripcion text NOT NULL,
    enlace text,
    hash text,
    creado_en timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY miapk.evidencias FORCE ROW LEVEL SECURITY;


--
-- Name: fuentes; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.fuentes (
    id text NOT NULL,
    nombre text NOT NULL,
    nivel_confianza smallint NOT NULL,
    metodo_autenticidad text NOT NULL,
    plazo_esperado interval,
    estado text DEFAULT 'pendiente'::text NOT NULL,
    CONSTRAINT fuentes_estado_check CHECK ((estado = ANY (ARRAY['activa'::text, 'desactualizada'::text, 'con_error'::text, 'pendiente'::text]))),
    CONSTRAINT fuentes_nivel_confianza_check CHECK (((nivel_confianza >= 1) AND (nivel_confianza <= 4)))
);

ALTER TABLE ONLY miapk.fuentes FORCE ROW LEVEL SECURITY;


--
-- Name: ordenes; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.ordenes (
    id text NOT NULL,
    titulo text NOT NULL,
    proyecto_id text,
    csw_id text,
    estado text NOT NULL,
    vence_en date,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ordenes_estado_check CHECK ((estado = ANY (ARRAY['borrador'::text, 'emitida'::text, 'en_ejecucion'::text, 'entregada'::text, 'aceptada'::text, 'rechazada'::text, 'suspendida'::text])))
);

ALTER TABLE ONLY miapk.ordenes FORCE ROW LEVEL SECURITY;


--
-- Name: osi_aprobaciones; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.osi_aprobaciones (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    version_id uuid NOT NULL,
    decision_id uuid NOT NULL,
    sha256_aprobado text NOT NULL,
    en timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY miapk.osi_aprobaciones FORCE ROW LEVEL SECURITY;


--
-- Name: osi_documentos; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.osi_documentos (
    codigo text NOT NULL,
    titulo text NOT NULL,
    tipo text NOT NULL,
    nivel_acceso text NOT NULL,
    ficticio boolean DEFAULT true NOT NULL,
    CONSTRAINT osi_documentos_codigo_check CHECK ((codigo ~ '^OSI-[A-Z]{2,3}-[0-9]{3}$'::text)),
    CONSTRAINT osi_documentos_ficticio_check CHECK (ficticio),
    CONSTRAINT osi_documentos_nivel_acceso_check CHECK ((nivel_acceso = ANY (ARRAY['publico_interno'::text, 'direccion'::text, 'restringido'::text])))
);

ALTER TABLE ONLY miapk.osi_documentos FORCE ROW LEVEL SECURITY;


--
-- Name: osi_transiciones; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.osi_transiciones (
    id bigint NOT NULL,
    version_id uuid NOT NULL,
    de text,
    a text NOT NULL,
    actor_id uuid,
    sha256 text,
    en timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY miapk.osi_transiciones FORCE ROW LEVEL SECURITY;


--
-- Name: osi_transiciones_id_seq; Type: SEQUENCE; Schema: miapk; Owner: -
--

ALTER TABLE miapk.osi_transiciones ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME miapk.osi_transiciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: osi_versiones; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.osi_versiones (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    codigo text NOT NULL,
    version text NOT NULL,
    estado text NOT NULL,
    archivo_ruta text,
    sha256 text,
    autor_id uuid,
    creado_en timestamp with time zone DEFAULT now() NOT NULL,
    contenido text,
    CONSTRAINT osi_versiones_estado_check CHECK ((estado = ANY (ARRAY['borrador'::text, 'en_revision'::text, 'aprobado'::text, 'vigente'::text, 'sustituido'::text, 'archivado'::text])))
);

ALTER TABLE ONLY miapk.osi_versiones FORCE ROW LEVEL SECURITY;


--
-- Name: pagos; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.pagos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    propuesta_id uuid,
    estado text NOT NULL,
    monto numeric(14,2),
    moneda character(3),
    confirmado_en timestamp with time zone,
    CONSTRAINT pagos_estado_check CHECK ((estado = ANY (ARRAY['pendiente'::text, 'confirmado'::text, 'fallido'::text, 'reembolsado'::text])))
);

ALTER TABLE ONLY miapk.pagos FORCE ROW LEVEL SECURITY;


--
-- Name: pfv; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.pfv (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    entrega_id uuid,
    aceptado boolean NOT NULL,
    calificacion smallint,
    en timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pfv_calificacion_check CHECK (((calificacion >= 1) AND (calificacion <= 5)))
);

ALTER TABLE ONLY miapk.pfv FORCE ROW LEVEL SECURITY;


--
-- Name: programas; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.programas (
    id text NOT NULL,
    nombre text NOT NULL
);

ALTER TABLE ONLY miapk.programas FORCE ROW LEVEL SECURITY;


--
-- Name: propuestas; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.propuestas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    conversacion_id uuid,
    estado text NOT NULL,
    emitida_en timestamp with time zone,
    CONSTRAINT propuestas_estado_check CHECK ((estado = ANY (ARRAY['borrador'::text, 'emitida'::text, 'aceptada'::text, 'rechazada'::text, 'vencida'::text])))
);

ALTER TABLE ONLY miapk.propuestas FORCE ROW LEVEL SECURITY;


--
-- Name: proyectos; Type: TABLE; Schema: miapk; Owner: -
--

CREATE TABLE miapk.proyectos (
    id text NOT NULL,
    programa_id text,
    nombre text NOT NULL
);

ALTER TABLE ONLY miapk.proyectos FORCE ROW LEVEL SECURITY;


--
-- Name: v_indicadores; Type: VIEW; Schema: miapk; Owner: -
--

CREATE VIEW miapk.v_indicadores WITH (security_invoker='true') AS
 WITH acep AS (
         SELECT e.event_id,
            e.occurred_at,
            e.received_at,
            1 AS signo
           FROM miapk.eventos e
          WHERE ((e.type = 'entrega.pfv.aceptado'::text) AND (e.fuente_id = 'laboratorio'::text))
        ), rev AS (
         SELECT DISTINCT ON (e.causation_id) e.event_id,
            e.occurred_at,
            e.received_at,
            '-1'::integer AS signo
           FROM miapk.eventos e
          WHERE ((e.type = 'entrega.pfv.revertido'::text) AND (e.fuente_id = 'laboratorio'::text) AND (e.causation_id IN ( SELECT acep.event_id
                   FROM acep)))
          ORDER BY e.causation_id, e.received_at
        ), ev AS (
         SELECT acep.event_id,
            acep.occurred_at,
            acep.received_at,
            acep.signo
           FROM acep
        UNION ALL
         SELECT rev.event_id,
            rev.occurred_at,
            rev.received_at,
            rev.signo
           FROM rev
        ), ult AS (
         SELECT ev.event_id,
            ev.occurred_at,
            ev.received_at,
            ev.signo
           FROM ev
          ORDER BY ev.received_at DESC, ev.event_id
         LIMIT 1
        ), fu AS (
         SELECT f.plazo_esperado,
            miapk.fuente_integrada(f.id) AS integrada,
            ( SELECT max(e.received_at) AS max
                   FROM miapk.eventos e
                  WHERE (e.fuente_id = f.id)) AS ultimo_fuente
           FROM miapk.fuentes f
          WHERE (f.id = 'laboratorio'::text)
        ), er AS (
         SELECT max(x.recibido_en) AS ultimo_error
           FROM miapk.eventos_errores x
          WHERE ((x.fuente_id = 'laboratorio'::text) AND ((x.cuerpo ->> 'type'::text) ~~ 'entrega.pfv.%'::text))
        )
 SELECT 'pfv_aceptados'::text AS indicador_id,
    'PFV aceptados'::text AS nombre,
    'laboratorio'::text AS fuente_id,
    ( SELECT COALESCE(sum(ev.signo), (0)::bigint) AS "coalesce"
           FROM ev) AS valor,
        CASE
            WHEN (( SELECT count(*) AS count
               FROM ev) > 0) THEN (( SELECT COALESCE(sum(ev.signo), (0)::bigint) AS "coalesce"
               FROM ev) - ( SELECT ult.signo
               FROM ult))
            ELSE NULL::bigint
        END AS valor_anterior,
    ( SELECT ult.event_id
           FROM ult) AS ultimo_event_id,
    ( SELECT ult.occurred_at
           FROM ult) AS ultimo_occurred_at,
    ( SELECT ult.received_at
           FROM ult) AS ultimo_received_at,
    ( SELECT er.ultimo_error
           FROM er) AS ultimo_error_at,
        CASE
            WHEN (NOT COALESCE(( SELECT fu.integrada
               FROM fu), false)) THEN 'Pendiente'::text
            WHEN (( SELECT er.ultimo_error
               FROM er) > COALESCE(( SELECT ult.received_at
               FROM ult), '-infinity'::timestamp with time zone)) THEN 'Error'::text
            WHEN ((( SELECT fu.ultimo_fuente
               FROM fu) IS NULL) OR (( SELECT fu.ultimo_fuente
               FROM fu) < (now() - COALESCE(( SELECT fu.plazo_esperado
               FROM fu), '100 years'::interval)))) THEN 'Desactualizado'::text
            WHEN (( SELECT count(*) AS count
               FROM ev) = 0) THEN 'Sin datos'::text
            ELSE 'Confirmado'::text
        END AS estado,
    ( SELECT count(*) AS count
           FROM rev) AS correcciones,
    now() AS calculado_en;


--
-- Name: v_osi_integridad; Type: VIEW; Schema: miapk; Owner: -
--

CREATE VIEW miapk.v_osi_integridad WITH (security_invoker='true') AS
 SELECT v.id AS version_id,
    v.codigo,
    d.titulo,
    v.version,
    v.estado,
    v.sha256 AS sha256_registrado,
    encode(sha256(convert_to(COALESCE(v.contenido, ''::text), 'UTF8'::name)), 'hex'::text) AS sha256_actual,
    ( SELECT a.sha256_aprobado
           FROM miapk.osi_aprobaciones a
          WHERE (a.version_id = v.id)
          ORDER BY a.en DESC
         LIMIT 1) AS sha256_aprobado,
        CASE
            WHEN (encode(sha256(convert_to(COALESCE(v.contenido, ''::text), 'UTF8'::name)), 'hex'::text) <> v.sha256) THEN 'ALTERADO'::text
            WHEN ((( SELECT a.sha256_aprobado
               FROM miapk.osi_aprobaciones a
              WHERE (a.version_id = v.id)
              ORDER BY a.en DESC
             LIMIT 1) IS NOT NULL) AND (( SELECT a.sha256_aprobado
               FROM miapk.osi_aprobaciones a
              WHERE (a.version_id = v.id)
              ORDER BY a.en DESC
             LIMIT 1) <> encode(sha256(convert_to(COALESCE(v.contenido, ''::text), 'UTF8'::name)), 'hex'::text))) THEN 'ALTERADO'::text
            ELSE 'Íntegro'::text
        END AS integridad,
    d.ficticio,
    ( SELECT max(t.en) AS max
           FROM miapk.osi_transiciones t
          WHERE (t.version_id = v.id)) AS ultima_transicion,
    now() AS verificado_en
   FROM (miapk.osi_versiones v
     JOIN miapk.osi_documentos d ON ((d.codigo = v.codigo)));


--
-- Name: v_resumen_fuentes; Type: VIEW; Schema: miapk; Owner: -
--

CREATE VIEW miapk.v_resumen_fuentes WITH (security_invoker='true') AS
 SELECT id AS fuente_id,
    nivel_confianza,
    estado,
    ( SELECT count(*) AS count
           FROM miapk.eventos e
          WHERE (e.fuente_id = f.id)) AS eventos,
    ( SELECT max(e.received_at) AS max
           FROM miapk.eventos e
          WHERE (e.fuente_id = f.id)) AS ultimo_evento,
    ( SELECT count(*) AS count
           FROM miapk.eventos_errores x
          WHERE (x.fuente_id = f.id)) AS errores,
        CASE
            WHEN (( SELECT max(e.received_at) AS max
               FROM miapk.eventos e
              WHERE (e.fuente_id = f.id)) IS NULL) THEN 'Sin datos'::text
            WHEN ((plazo_esperado IS NOT NULL) AND (( SELECT max(e.received_at) AS max
               FROM miapk.eventos e
              WHERE (e.fuente_id = f.id)) < (now() - plazo_esperado))) THEN 'Desactualizado'::text
            WHEN (EXISTS ( SELECT 1
               FROM miapk.eventos_errores x
              WHERE ((x.fuente_id = f.id) AND (x.recibido_en > (now() - '1 day'::interval))))) THEN 'Con errores recientes'::text
            ELSE 'Al día'::text
        END AS semaforo
   FROM miapk.fuentes f;


--
-- Data for Name: actores; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.actores (id, auth_uid, nombre, tipo, hat, activo, creado_en) FROM stdin;
871a1199-1b70-4749-a976-4785272ed2f9	670323a1-83e0-4acf-9cc2-d264c9207465	Dirección (Nóah)	persona	direccion	t	2026-11-10 16:46:43.990596+00
f94d2428-99f2-4baf-8099-2fe6255bda35	\N	Magda (Claude)	agente	magda	t	2026-11-11 13:23:56.721623+00
\.


--
-- Data for Name: bitacora; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.bitacora (id, en, actor_id, accion, objeto, detalle, hash_anterior, hash) FROM stdin;
3	2026-11-10 17:22:55.966969+00	\N	evento.recibido	eventos/2df73faa-6d77-46ab-96ae-d52af16e707e	{"type": "laboratorio.prueba.registrada", "fuente": "laboratorio", "event_id": "2df73faa-6d77-46ab-96ae-d52af16e707e", "hash_cuerpo": "2ad88bfa57d1021682d2c26f8501b5cc767df613b678081f63ae8b4e35eb83e2"}	\N	bd9d2c82bd442b6db3e37056cfda2aa4f97c607b087de34d3fd8bb5dcd72a772
6	2026-11-10 19:29:39.316234+00	\N	evento.recibido	eventos/210ea27d-7f1f-4133-8b95-eb482610efc2	{"type": "entrega.pfv.aceptado", "fuente": "laboratorio", "event_id": "210ea27d-7f1f-4133-8b95-eb482610efc2", "hash_cuerpo": "c34e12b4df35202f1496a6817508e2471f65b909bba90dbd85810f7bb4444851"}	bd9d2c82bd442b6db3e37056cfda2aa4f97c607b087de34d3fd8bb5dcd72a772	53624984ec45eec79884fee2f0735bc700c409f3e7b2844ba922cb61fbd74696
7	2026-11-11 12:39:35.906146+00	\N	evento.recibido	eventos/fe5feacf-5efe-468f-bd9a-9a01949e4c21	{"type": "entrega.pfv.aceptado", "fuente": "laboratorio", "event_id": "fe5feacf-5efe-468f-bd9a-9a01949e4c21", "hash_cuerpo": "4d2ba87dca1ec84d4c3255a7f910869ddfe4f7a322b9ec69e8a6e3acf635304d"}	53624984ec45eec79884fee2f0735bc700c409f3e7b2844ba922cb61fbd74696	e121848fe9a953011b96268c563eae971c486d6b5e9e93c15cc92b68431f9f5f
8	2026-11-11 13:24:14.422791+00	f94d2428-99f2-4baf-8099-2fe6255bda35	osi.borrador	OSI-LAB-001 v1.0	{"version_id": "87dce131-20de-4171-bf4c-795c85cb0972"}	e121848fe9a953011b96268c563eae971c486d6b5e9e93c15cc92b68431f9f5f	970aa6b393f695c5252dab5044b9b8b49aae403a89d8c1582f6164591e6022a2
9	2026-11-11 13:24:14.422791+00	f94d2428-99f2-4baf-8099-2fe6255bda35	osi.en_revision	87dce131-20de-4171-bf4c-795c85cb0972	{"sha256": "41d0e4c37de933906a06fee23ddba8c57823ba51d6d1c06a1dadd24c6bd070cc"}	970aa6b393f695c5252dab5044b9b8b49aae403a89d8c1582f6164591e6022a2	a65339afd8d4c0d765a1dee5b09721b7ebfe2b06a4760113b52699d05cb1c523
10	2026-11-11 13:35:14.984575+00	871a1199-1b70-4749-a976-4785272ed2f9	osi.aprobado	87dce131-20de-4171-bf4c-795c85cb0972	{"sha256": "41d0e4c37de933906a06fee23ddba8c57823ba51d6d1c06a1dadd24c6bd070cc", "decision_id": "978d3fa6-2521-4ab6-a1de-5a518ee21d49"}	a65339afd8d4c0d765a1dee5b09721b7ebfe2b06a4760113b52699d05cb1c523	0b8c8747edfeba4542ae54f69e1d158d3a38bb4773d59576617cddca8392373c
11	2026-11-11 13:35:17.176592+00	871a1199-1b70-4749-a976-4785272ed2f9	osi.vigente	87dce131-20de-4171-bf4c-795c85cb0972	{"sha256": "41d0e4c37de933906a06fee23ddba8c57823ba51d6d1c06a1dadd24c6bd070cc"}	0b8c8747edfeba4542ae54f69e1d158d3a38bb4773d59576617cddca8392373c	47fd6be15678ca2a3382c901fded5b60d360ba2a442474b6b6d510536d9021b5
12	2026-11-11 15:22:08.192597+00	\N	osi.rechazo	87dce131-20de-4171-bf4c-795c85cb0972	{"aal": "aal2", "uid": "d5f99d83-d4b8-495d-abd6-25323556bb34", "motivo": "no es Dirección con aal2", "intento": "aprobar"}	47fd6be15678ca2a3382c901fded5b60d360ba2a442474b6b6d510536d9021b5	37a489c2423d0c136b3797bb3bd2601659e409ae90e110033dff368b6249952b
13	2026-11-11 15:22:08.192597+00	\N	osi.rechazo	87dce131-20de-4171-bf4c-795c85cb0972	{"aal": "aal2", "uid": "d5f99d83-d4b8-495d-abd6-25323556bb34", "motivo": "no es Dirección con aal2", "intento": "poner_vigente"}	37a489c2423d0c136b3797bb3bd2601659e409ae90e110033dff368b6249952b	aaf6ad1d009a56df7758e08141cf12352b9b18708f5b55184b3a33e8934fd2d0
14	2026-11-11 15:22:08.192597+00	\N	osi.rechazo	87dce131-20de-4171-bf4c-795c85cb0972	{"aal": "aal1", "uid": "670323a1-83e0-4acf-9cc2-d264c9207465", "motivo": "no es Dirección con aal2", "intento": "aprobar"}	aaf6ad1d009a56df7758e08141cf12352b9b18708f5b55184b3a33e8934fd2d0	82a6e2f2f3df77dc1b0f6600e40fae3856967445aa7da459d09d4fd1d8784ad2
15	2026-11-11 15:23:30.268271+00	f94d2428-99f2-4baf-8099-2fe6255bda35	osi.borrador	OSI-LAB-001 v1.1	{"version_id": "0b994adc-4124-4148-8f32-9234ae206493"}	82a6e2f2f3df77dc1b0f6600e40fae3856967445aa7da459d09d4fd1d8784ad2	47c3b7dc3cde280d5d1869f6e55f16a0dc96ed7a244bd229c2c5de4e73926d03
16	2026-11-11 15:23:30.268271+00	f94d2428-99f2-4baf-8099-2fe6255bda35	osi.en_revision	0b994adc-4124-4148-8f32-9234ae206493	{"sha256": "d551b093acae3fa3199d074880395330b063c06b3d42acdc23ef4dc5bc6d54c9"}	47c3b7dc3cde280d5d1869f6e55f16a0dc96ed7a244bd229c2c5de4e73926d03	c9f32a3b6823e0a3ed1f627951f12db4fe0678e2c277c7cb5fd92b2e2ccf4c1e
17	2026-11-11 15:30:40.951385+00	871a1199-1b70-4749-a976-4785272ed2f9	osi.aprobado	0b994adc-4124-4148-8f32-9234ae206493	{"sha256": "d551b093acae3fa3199d074880395330b063c06b3d42acdc23ef4dc5bc6d54c9", "decision_id": "aef97404-e104-478a-b97c-4bd38e076e80"}	c9f32a3b6823e0a3ed1f627951f12db4fe0678e2c277c7cb5fd92b2e2ccf4c1e	bc52ad64da46671c4b609ef53e4e43ff0add3fbe40aa48c4d67e47abd93d0027
18	2026-11-11 15:30:56.869458+00	871a1199-1b70-4749-a976-4785272ed2f9	osi.vigente	0b994adc-4124-4148-8f32-9234ae206493	{"sha256": "d551b093acae3fa3199d074880395330b063c06b3d42acdc23ef4dc5bc6d54c9"}	bc52ad64da46671c4b609ef53e4e43ff0add3fbe40aa48c4d67e47abd93d0027	0de60137ab6fa12882e4912e4d7efc98d79d7626b3fd3b4d04b3b32f19e3a6b8
19	2026-11-11 15:32:03.39364+00	\N	evento.recibido	eventos/7954627e-3a3b-45d0-b35e-387b283bc217	{"type": "entrega.pfv.revertido", "fuente": "laboratorio", "event_id": "7954627e-3a3b-45d0-b35e-387b283bc217", "hash_cuerpo": "f15734cefd51cff3c6166f6c41093d99c32e6fc8bd1af6876017bdb002535d00"}	0de60137ab6fa12882e4912e4d7efc98d79d7626b3fd3b4d04b3b32f19e3a6b8	11345ada46f4ae80fb2f043742b58aa59b1cd8bb45b867072d1c7f50140f34d8
20	2026-11-11 15:50:45.863803+00	871a1199-1b70-4749-a976-4785272ed2f9	sesion.cerrar_todas	auth.sessions	{"uid": "670323a1-83e0-4acf-9cc2-d264c9207465", "sesiones_cerradas": 1}	11345ada46f4ae80fb2f043742b58aa59b1cd8bb45b867072d1c7f50140f34d8	79fbc7dba60816212c5c158ccdaad28ef133489d1d7e3b45450ddfd4f4a2d02d
\.


--
-- Data for Name: casos_soporte; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.casos_soporte (id, cliente_id, entrega_id, estado, abierto_en) FROM stdin;
\.


--
-- Data for Name: clientes; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.clientes (id, alias_ficticio, creado_en) FROM stdin;
\.


--
-- Data for Name: conversaciones; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.conversaciones (id, cliente_id, iniciada_en, necesidad_confirmada) FROM stdin;
\.


--
-- Data for Name: credenciales_fuente; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.credenciales_fuente (fuente_id, hash_credencial, activa, creada_en) FROM stdin;
laboratorio	b57faf79be4ae60ec71894f513ffcacd7d0750a46d2ddca9000c2f02d7451a43	t	2026-11-10 17:22:32.241874+00
\.


--
-- Data for Name: csw; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.csw (id, titulo, estado, creado_en) FROM stdin;
\.


--
-- Data for Name: decisiones; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.decisiones (id, en, actor_id, objeto_tipo, objeto_id, decision, texto_literal) FROM stdin;
978d3fa6-2521-4ab6-a1de-5a518ee21d49	2026-11-11 13:35:14.984575+00	871a1199-1b70-4749-a976-4785272ed2f9	osi_version	87dce131-20de-4171-bf4c-795c85cb0972	aprobar	Apruebo OSI-LAB-001 versión 1.0.
aef97404-e104-478a-b97c-4bd38e076e80	2026-11-11 15:30:40.951385+00	871a1199-1b70-4749-a976-4785272ed2f9	osi_version	0b994adc-4124-4148-8f32-9234ae206493	aprobar	Apruebo OSI-LAB-001 versión 1.1.
\.


--
-- Data for Name: entregas; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.entregas (id, propuesta_id, estado, publicada_en) FROM stdin;
\.


--
-- Data for Name: eventos; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.eventos (event_id, type, schema_version, occurred_at, received_at, fuente_id, external_id, actor_id, subject_entity, subject_id, correlation_id, causation_id, data, firma_verificada, hash_cuerpo) FROM stdin;
2df73faa-6d77-46ab-96ae-d52af16e707e	laboratorio.prueba.registrada	1	2026-11-10 17:22:55.594149+00	2026-11-10 17:22:55.966969+00	laboratorio	lab-H3-2	\N	prueba	lab-H3-2	\N	\N	{"nota": "evento de prueba H3", "ficticio": true}	t	2ad88bfa57d1021682d2c26f8501b5cc767df613b678081f63ae8b4e35eb83e2
210ea27d-7f1f-4133-8b95-eb482610efc2	entrega.pfv.aceptado	1	2026-11-10 19:29:39.001999+00	2026-11-10 19:29:39.316234+00	laboratorio	lab-H4-1	\N	entrega	ENT-FICTICIA-lab-H4-1	\N	\N	{"nota": "PFV aceptado de prueba H4", "cliente": "Cliente Ficticio S.A.S.", "ficticio": true}	t	c34e12b4df35202f1496a6817508e2471f65b909bba90dbd85810f7bb4444851
fe5feacf-5efe-468f-bd9a-9a01949e4c21	entrega.pfv.aceptado	1	2026-11-11 12:39:35.705115+00	2026-11-11 12:39:35.906146+00	laboratorio	lab-H4-3	\N	entrega	ENT-FICTICIA-lab-H4-3	\N	\N	{"nota": "PFV aceptado de prueba H4", "cliente": "Cliente Ficticio S.A.S.", "ficticio": true}	t	4d2ba87dca1ec84d4c3255a7f910869ddfe4f7a322b9ec69e8a6e3acf635304d
7954627e-3a3b-45d0-b35e-387b283bc217	entrega.pfv.revertido	1	2026-11-11 15:32:03.141704+00	2026-11-11 15:32:03.39364+00	laboratorio	lab-H4-3-corr	\N	entrega	ENT-FICTICIA-lab-H4-3-corr	\N	fe5feacf-5efe-468f-bd9a-9a01949e4c21	{"nota": "Corrección: se revierte el PFV fe5feacf-5efe-468f-bd9a-9a01949e4c21", "cliente": "Cliente Ficticio S.A.S.", "ficticio": true}	t	f15734cefd51cff3c6166f6c41093d99c32e6fc8bd1af6876017bdb002535d00
\.


--
-- Data for Name: eventos_errores; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.eventos_errores (id, recibido_en, fuente_id, motivo, cuerpo, origen) FROM stdin;
3	2026-11-10 17:21:38.312653+00	\N	credencial inválida	{"type": "laboratorio.prueba.registrada", "external_id": "lab-H3-1"}	prueba negativa H3
4	2026-11-10 17:21:38.652933+00	\N	credencial inválida	{"type": "laboratorio.prueba.registrada", "external_id": "lab-H3-1"}	prueba negativa H3
5	2026-11-10 17:21:38.787307+00	\N	credencial inválida	{"type": "laboratorio.prueba.registrada", "external_id": "lab-H3-1"}	prueba negativa H3
6	2026-11-10 17:21:38.982216+00	\N	credencial inválida	{"type": "TipoMalo", "external_id": "lab-H3-1-x"}	prueba negativa H3
7	2026-11-10 17:21:39.142829+00	\N	credencial inválida	{"type": "laboratorio.prueba.registrada", "external_id": "lab-H3-1-y"}	prueba negativa H3
8	2026-11-10 17:21:39.33699+00	\N	credencial inválida	{"type": "laboratorio.prueba.registrada", "external_id": "lab-H3-1-z"}	prueba negativa H3
9	2026-11-10 17:21:39.458504+00	\N	credencial inválida	{"type": "laboratorio.prueba.registrada", "external_id": "lab-H3-1-w"}	prueba negativa H3
10	2026-11-10 17:22:56.739887+00	laboratorio	type inválido (formato dominio.entidad.accion)	{"data": {"nota": "evento de prueba H3", "ficticio": true}, "type": "TipoMalo", "event_id": "8419b853-276b-4d49-86ea-82fc599a0790", "subject_id": "lab-H3-2-x", "external_id": "lab-H3-2-x", "occurred_at": "2026-11-10T17:22:56.505442+00:00", "subject_entity": "prueba"}	prueba negativa H3
11	2026-11-10 17:22:56.895082+00	laboratorio	laboratorio: solo se aceptan datos marcados ficticio=true	{"data": {"cliente": "real"}, "type": "laboratorio.prueba.registrada", "event_id": "35b4c001-3b98-44f3-9bd1-f33873c9a606", "subject_id": "lab-H3-2-y", "external_id": "lab-H3-2-y", "occurred_at": "2026-11-10T17:22:56.764026+00:00", "subject_entity": "prueba"}	prueba negativa H3
12	2026-11-10 17:22:57.047697+00	\N	credencial inválida	{"type": "laboratorio.prueba.registrada", "external_id": "lab-H3-2-z"}	prueba negativa H3
13	2026-11-10 17:22:57.267898+00	laboratorio	la fuente declarada no coincide con la credencial	{"data": {"nota": "evento de prueba H3", "ficticio": true}, "type": "laboratorio.prueba.registrada", "event_id": "feae5ac2-4f7c-4a3f-bd74-a6bcdb82bd07", "fuente_id": "pasarela", "subject_id": "lab-H3-2-w", "external_id": "lab-H3-2-w", "occurred_at": "2026-11-10T17:22:57.071674+00:00", "subject_entity": "prueba"}	prueba negativa H3
16	2026-11-10 19:31:00.212813+00	laboratorio	subject_entity o subject_id ausente	{"data": {"nota": "PFV aceptado de prueba H4", "cliente": "Cliente Ficticio S.A.S.", "ficticio": true}, "type": "entrega.pfv.aceptado", "origen": "prueba H4", "event_id": "0aace1f4-8286-48d7-8952-3ac1809b8699", "external_id": "lab-H4-2", "occurred_at": "2026-11-10T19:31:00.087801+00:00", "subject_entity": "entrega"}	prueba H4
\.


--
-- Data for Name: evidencias; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.evidencias (id, orden_id, descripcion, enlace, hash, creado_en) FROM stdin;
\.


--
-- Data for Name: fuentes; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.fuentes (id, nombre, nivel_confianza, metodo_autenticidad, plazo_esperado, estado) FROM stdin;
jetpost	JetPost (importación asistida)	4	revisión humana + hash del contenido	\N	activa
mia_web	MÍA Web	1	credencial de servicio	\N	pendiente
pasarela	Pasarela de pagos	1	webhook firmado del proveedor	\N	pendiente
laboratorio	Generador de eventos de prueba	1	credencial de servidor (secreto de GitHub)	1 day	activa
\.


--
-- Data for Name: ordenes; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.ordenes (id, titulo, proyecto_id, csw_id, estado, vence_en, creado_en) FROM stdin;
\.


--
-- Data for Name: osi_aprobaciones; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.osi_aprobaciones (id, version_id, decision_id, sha256_aprobado, en) FROM stdin;
ca153ea1-21db-4da7-88ef-52d36d6631d3	87dce131-20de-4171-bf4c-795c85cb0972	978d3fa6-2521-4ab6-a1de-5a518ee21d49	41d0e4c37de933906a06fee23ddba8c57823ba51d6d1c06a1dadd24c6bd070cc	2026-11-11 13:35:14.984575+00
dfd43713-965d-4e5d-88bf-90b5cf15603a	0b994adc-4124-4148-8f32-9234ae206493	aef97404-e104-478a-b97c-4bd38e076e80	d551b093acae3fa3199d074880395330b063c06b3d42acdc23ef4dc5bc6d54c9	2026-11-11 15:30:40.951385+00
\.


--
-- Data for Name: osi_documentos; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.osi_documentos (codigo, titulo, tipo, nivel_acceso, ficticio) FROM stdin;
OSI-LAB-001	Política ficticia de escritorio limpio (PRUEBA DE LABORATORIO)	politica	direccion	t
\.


--
-- Data for Name: osi_transiciones; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.osi_transiciones (id, version_id, de, a, actor_id, sha256, en) FROM stdin;
1	87dce131-20de-4171-bf4c-795c85cb0972	\N	borrador	f94d2428-99f2-4baf-8099-2fe6255bda35	41d0e4c37de933906a06fee23ddba8c57823ba51d6d1c06a1dadd24c6bd070cc	2026-11-11 13:24:14.422791+00
2	87dce131-20de-4171-bf4c-795c85cb0972	borrador	en_revision	f94d2428-99f2-4baf-8099-2fe6255bda35	41d0e4c37de933906a06fee23ddba8c57823ba51d6d1c06a1dadd24c6bd070cc	2026-11-11 13:24:14.422791+00
3	87dce131-20de-4171-bf4c-795c85cb0972	en_revision	aprobado	871a1199-1b70-4749-a976-4785272ed2f9	41d0e4c37de933906a06fee23ddba8c57823ba51d6d1c06a1dadd24c6bd070cc	2026-11-11 13:35:14.984575+00
4	87dce131-20de-4171-bf4c-795c85cb0972	aprobado	vigente	871a1199-1b70-4749-a976-4785272ed2f9	41d0e4c37de933906a06fee23ddba8c57823ba51d6d1c06a1dadd24c6bd070cc	2026-11-11 13:35:17.176592+00
5	0b994adc-4124-4148-8f32-9234ae206493	\N	borrador	f94d2428-99f2-4baf-8099-2fe6255bda35	d551b093acae3fa3199d074880395330b063c06b3d42acdc23ef4dc5bc6d54c9	2026-11-11 15:23:30.268271+00
6	0b994adc-4124-4148-8f32-9234ae206493	borrador	en_revision	f94d2428-99f2-4baf-8099-2fe6255bda35	d551b093acae3fa3199d074880395330b063c06b3d42acdc23ef4dc5bc6d54c9	2026-11-11 15:23:30.268271+00
7	0b994adc-4124-4148-8f32-9234ae206493	en_revision	aprobado	871a1199-1b70-4749-a976-4785272ed2f9	d551b093acae3fa3199d074880395330b063c06b3d42acdc23ef4dc5bc6d54c9	2026-11-11 15:30:40.951385+00
8	0b994adc-4124-4148-8f32-9234ae206493	aprobado	vigente	871a1199-1b70-4749-a976-4785272ed2f9	d551b093acae3fa3199d074880395330b063c06b3d42acdc23ef4dc5bc6d54c9	2026-11-11 15:30:56.869458+00
\.


--
-- Data for Name: osi_versiones; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.osi_versiones (id, codigo, version, estado, archivo_ruta, sha256, autor_id, creado_en, contenido) FROM stdin;
87dce131-20de-4171-bf4c-795c85cb0972	OSI-LAB-001	1.0	sustituido	\N	41d0e4c37de933906a06fee23ddba8c57823ba51d6d1c06a1dadd24c6bd070cc	f94d2428-99f2-4baf-8099-2fe6255bda35	2026-11-11 13:24:14.422791+00	DOCUMENTO FICTICIO · SOLO PARA PRUEBAS DE LABORATORIO DE MIAPK · SIN VALIDEZ.\n1. Al terminar la jornada, el escritorio de trabajo ficticio queda sin papeles visibles.\n2. Las pantallas se bloquean al ausentarse.\n3. Ningún documento real se usa en esta prueba.
0b994adc-4124-4148-8f32-9234ae206493	OSI-LAB-001	1.1	vigente	\N	d551b093acae3fa3199d074880395330b063c06b3d42acdc23ef4dc5bc6d54c9	f94d2428-99f2-4baf-8099-2fe6255bda35	2026-11-11 15:23:30.268271+00	DOCUMENTO FICTICIO · SOLO PARA PRUEBAS DE LABORATORIO DE MIAPK · SIN VALIDEZ.\n1. Al terminar la jornada, el escritorio de trabajo ficticio queda sin papeles visibles.\n2. Las pantallas se bloquean al ausentarse.\n3. Ningún documento real se usa en esta prueba.\n4. (Nuevo en v1.1) Los cajones ficticios se cierran con llave al final del día.
\.


--
-- Data for Name: pagos; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.pagos (id, propuesta_id, estado, monto, moneda, confirmado_en) FROM stdin;
\.


--
-- Data for Name: pfv; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.pfv (id, entrega_id, aceptado, calificacion, en) FROM stdin;
\.


--
-- Data for Name: programas; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.programas (id, nombre) FROM stdin;
P-1	Identidad corporativa
P-2	MÍA y comunicación
P-3	Experiencia de creación
P-4	Producción y entrega
P-5	Comercial y publicidad
P-6	Protección y confiabilidad
P-7	Medición y mejora
P-8	Internacionalización
\.


--
-- Data for Name: propuestas; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.propuestas (id, conversacion_id, estado, emitida_en) FROM stdin;
\.


--
-- Data for Name: proyectos; Type: TABLE DATA; Schema: miapk; Owner: -
--

COPY miapk.proyectos (id, programa_id, nombre) FROM stdin;
\.


--
-- Name: bitacora_id_seq; Type: SEQUENCE SET; Schema: miapk; Owner: -
--

SELECT pg_catalog.setval('miapk.bitacora_id_seq', 20, true);


--
-- Name: eventos_errores_id_seq; Type: SEQUENCE SET; Schema: miapk; Owner: -
--

SELECT pg_catalog.setval('miapk.eventos_errores_id_seq', 36, true);


--
-- Name: osi_transiciones_id_seq; Type: SEQUENCE SET; Schema: miapk; Owner: -
--

SELECT pg_catalog.setval('miapk.osi_transiciones_id_seq', 8, true);


--
-- Name: actores actores_auth_uid_key; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.actores
    ADD CONSTRAINT actores_auth_uid_key UNIQUE (auth_uid);


--
-- Name: actores actores_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.actores
    ADD CONSTRAINT actores_pkey PRIMARY KEY (id);


--
-- Name: bitacora bitacora_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.bitacora
    ADD CONSTRAINT bitacora_pkey PRIMARY KEY (id);


--
-- Name: casos_soporte casos_soporte_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.casos_soporte
    ADD CONSTRAINT casos_soporte_pkey PRIMARY KEY (id);


--
-- Name: clientes clientes_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.clientes
    ADD CONSTRAINT clientes_pkey PRIMARY KEY (id);


--
-- Name: conversaciones conversaciones_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.conversaciones
    ADD CONSTRAINT conversaciones_pkey PRIMARY KEY (id);


--
-- Name: credenciales_fuente credenciales_fuente_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.credenciales_fuente
    ADD CONSTRAINT credenciales_fuente_pkey PRIMARY KEY (fuente_id);


--
-- Name: csw csw_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.csw
    ADD CONSTRAINT csw_pkey PRIMARY KEY (id);


--
-- Name: decisiones decisiones_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.decisiones
    ADD CONSTRAINT decisiones_pkey PRIMARY KEY (id);


--
-- Name: entregas entregas_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.entregas
    ADD CONSTRAINT entregas_pkey PRIMARY KEY (id);


--
-- Name: eventos_errores eventos_errores_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.eventos_errores
    ADD CONSTRAINT eventos_errores_pkey PRIMARY KEY (id);


--
-- Name: eventos eventos_fuente_id_external_id_type_key; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.eventos
    ADD CONSTRAINT eventos_fuente_id_external_id_type_key UNIQUE (fuente_id, external_id, type);


--
-- Name: eventos eventos_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.eventos
    ADD CONSTRAINT eventos_pkey PRIMARY KEY (event_id);


--
-- Name: evidencias evidencias_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.evidencias
    ADD CONSTRAINT evidencias_pkey PRIMARY KEY (id);


--
-- Name: fuentes fuentes_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.fuentes
    ADD CONSTRAINT fuentes_pkey PRIMARY KEY (id);


--
-- Name: ordenes ordenes_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.ordenes
    ADD CONSTRAINT ordenes_pkey PRIMARY KEY (id);


--
-- Name: osi_aprobaciones osi_aprobaciones_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.osi_aprobaciones
    ADD CONSTRAINT osi_aprobaciones_pkey PRIMARY KEY (id);


--
-- Name: osi_documentos osi_documentos_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.osi_documentos
    ADD CONSTRAINT osi_documentos_pkey PRIMARY KEY (codigo);


--
-- Name: osi_transiciones osi_transiciones_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.osi_transiciones
    ADD CONSTRAINT osi_transiciones_pkey PRIMARY KEY (id);


--
-- Name: osi_versiones osi_versiones_codigo_version_key; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.osi_versiones
    ADD CONSTRAINT osi_versiones_codigo_version_key UNIQUE (codigo, version);


--
-- Name: osi_versiones osi_versiones_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.osi_versiones
    ADD CONSTRAINT osi_versiones_pkey PRIMARY KEY (id);


--
-- Name: pagos pagos_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.pagos
    ADD CONSTRAINT pagos_pkey PRIMARY KEY (id);


--
-- Name: pfv pfv_entrega_id_key; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.pfv
    ADD CONSTRAINT pfv_entrega_id_key UNIQUE (entrega_id);


--
-- Name: pfv pfv_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.pfv
    ADD CONSTRAINT pfv_pkey PRIMARY KEY (id);


--
-- Name: programas programas_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.programas
    ADD CONSTRAINT programas_pkey PRIMARY KEY (id);


--
-- Name: propuestas propuestas_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.propuestas
    ADD CONSTRAINT propuestas_pkey PRIMARY KEY (id);


--
-- Name: proyectos proyectos_pkey; Type: CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.proyectos
    ADD CONSTRAINT proyectos_pkey PRIMARY KEY (id);


--
-- Name: bitacora bitacora_solo_agregar; Type: TRIGGER; Schema: miapk; Owner: -
--

CREATE TRIGGER bitacora_solo_agregar BEFORE DELETE OR UPDATE ON miapk.bitacora FOR EACH ROW EXECUTE FUNCTION miapk.prohibir_cambios();


--
-- Name: decisiones decisiones_solo_agregar; Type: TRIGGER; Schema: miapk; Owner: -
--

CREATE TRIGGER decisiones_solo_agregar BEFORE DELETE OR UPDATE ON miapk.decisiones FOR EACH ROW EXECUTE FUNCTION miapk.prohibir_cambios();


--
-- Name: eventos_errores eventos_errores_origen; Type: TRIGGER; Schema: miapk; Owner: -
--

CREATE TRIGGER eventos_errores_origen BEFORE INSERT ON miapk.eventos_errores FOR EACH ROW EXECUTE FUNCTION miapk.etiquetar_error();


--
-- Name: eventos eventos_solo_agregar; Type: TRIGGER; Schema: miapk; Owner: -
--

CREATE TRIGGER eventos_solo_agregar BEFORE DELETE OR UPDATE ON miapk.eventos FOR EACH ROW EXECUTE FUNCTION miapk.prohibir_cambios();


--
-- Name: osi_aprobaciones osi_aprob_solo_agregar; Type: TRIGGER; Schema: miapk; Owner: -
--

CREATE TRIGGER osi_aprob_solo_agregar BEFORE DELETE OR UPDATE ON miapk.osi_aprobaciones FOR EACH ROW EXECUTE FUNCTION miapk.prohibir_cambios();


--
-- Name: osi_versiones osi_proteger_t; Type: TRIGGER; Schema: miapk; Owner: -
--

CREATE TRIGGER osi_proteger_t BEFORE INSERT OR DELETE OR UPDATE ON miapk.osi_versiones FOR EACH ROW EXECUTE FUNCTION miapk.osi_proteger();


--
-- Name: osi_transiciones osi_trans_solo_agregar; Type: TRIGGER; Schema: miapk; Owner: -
--

CREATE TRIGGER osi_trans_solo_agregar BEFORE DELETE OR UPDATE ON miapk.osi_transiciones FOR EACH ROW EXECUTE FUNCTION miapk.prohibir_cambios();


--
-- Name: bitacora bitacora_actor_id_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.bitacora
    ADD CONSTRAINT bitacora_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES miapk.actores(id);


--
-- Name: casos_soporte casos_soporte_cliente_id_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.casos_soporte
    ADD CONSTRAINT casos_soporte_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES miapk.clientes(id);


--
-- Name: casos_soporte casos_soporte_entrega_id_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.casos_soporte
    ADD CONSTRAINT casos_soporte_entrega_id_fkey FOREIGN KEY (entrega_id) REFERENCES miapk.entregas(id);


--
-- Name: conversaciones conversaciones_cliente_id_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.conversaciones
    ADD CONSTRAINT conversaciones_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES miapk.clientes(id);


--
-- Name: credenciales_fuente credenciales_fuente_fuente_id_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.credenciales_fuente
    ADD CONSTRAINT credenciales_fuente_fuente_id_fkey FOREIGN KEY (fuente_id) REFERENCES miapk.fuentes(id);


--
-- Name: decisiones decisiones_actor_id_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.decisiones
    ADD CONSTRAINT decisiones_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES miapk.actores(id);


--
-- Name: entregas entregas_propuesta_id_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.entregas
    ADD CONSTRAINT entregas_propuesta_id_fkey FOREIGN KEY (propuesta_id) REFERENCES miapk.propuestas(id);


--
-- Name: eventos eventos_actor_id_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.eventos
    ADD CONSTRAINT eventos_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES miapk.actores(id);


--
-- Name: eventos eventos_fuente_id_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.eventos
    ADD CONSTRAINT eventos_fuente_id_fkey FOREIGN KEY (fuente_id) REFERENCES miapk.fuentes(id);


--
-- Name: evidencias evidencias_orden_id_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.evidencias
    ADD CONSTRAINT evidencias_orden_id_fkey FOREIGN KEY (orden_id) REFERENCES miapk.ordenes(id);


--
-- Name: ordenes ordenes_csw_id_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.ordenes
    ADD CONSTRAINT ordenes_csw_id_fkey FOREIGN KEY (csw_id) REFERENCES miapk.csw(id);


--
-- Name: ordenes ordenes_proyecto_id_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.ordenes
    ADD CONSTRAINT ordenes_proyecto_id_fkey FOREIGN KEY (proyecto_id) REFERENCES miapk.proyectos(id);


--
-- Name: osi_aprobaciones osi_aprobaciones_decision_id_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.osi_aprobaciones
    ADD CONSTRAINT osi_aprobaciones_decision_id_fkey FOREIGN KEY (decision_id) REFERENCES miapk.decisiones(id);


--
-- Name: osi_aprobaciones osi_aprobaciones_version_id_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.osi_aprobaciones
    ADD CONSTRAINT osi_aprobaciones_version_id_fkey FOREIGN KEY (version_id) REFERENCES miapk.osi_versiones(id);


--
-- Name: osi_transiciones osi_transiciones_actor_id_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.osi_transiciones
    ADD CONSTRAINT osi_transiciones_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES miapk.actores(id);


--
-- Name: osi_transiciones osi_transiciones_version_id_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.osi_transiciones
    ADD CONSTRAINT osi_transiciones_version_id_fkey FOREIGN KEY (version_id) REFERENCES miapk.osi_versiones(id);


--
-- Name: osi_versiones osi_versiones_autor_id_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.osi_versiones
    ADD CONSTRAINT osi_versiones_autor_id_fkey FOREIGN KEY (autor_id) REFERENCES miapk.actores(id);


--
-- Name: osi_versiones osi_versiones_codigo_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.osi_versiones
    ADD CONSTRAINT osi_versiones_codigo_fkey FOREIGN KEY (codigo) REFERENCES miapk.osi_documentos(codigo);


--
-- Name: pagos pagos_propuesta_id_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.pagos
    ADD CONSTRAINT pagos_propuesta_id_fkey FOREIGN KEY (propuesta_id) REFERENCES miapk.propuestas(id);


--
-- Name: pfv pfv_entrega_id_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.pfv
    ADD CONSTRAINT pfv_entrega_id_fkey FOREIGN KEY (entrega_id) REFERENCES miapk.entregas(id);


--
-- Name: propuestas propuestas_conversacion_id_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.propuestas
    ADD CONSTRAINT propuestas_conversacion_id_fkey FOREIGN KEY (conversacion_id) REFERENCES miapk.conversaciones(id);


--
-- Name: proyectos proyectos_programa_id_fkey; Type: FK CONSTRAINT; Schema: miapk; Owner: -
--

ALTER TABLE ONLY miapk.proyectos
    ADD CONSTRAINT proyectos_programa_id_fkey FOREIGN KEY (programa_id) REFERENCES miapk.programas(id);


--
-- Name: actores; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.actores ENABLE ROW LEVEL SECURITY;

--
-- Name: bitacora; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.bitacora ENABLE ROW LEVEL SECURITY;

--
-- Name: casos_soporte; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.casos_soporte ENABLE ROW LEVEL SECURITY;

--
-- Name: clientes; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.clientes ENABLE ROW LEVEL SECURITY;

--
-- Name: conversaciones; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.conversaciones ENABLE ROW LEVEL SECURITY;

--
-- Name: credenciales_fuente; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.credenciales_fuente ENABLE ROW LEVEL SECURITY;

--
-- Name: csw; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.csw ENABLE ROW LEVEL SECURITY;

--
-- Name: decisiones; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.decisiones ENABLE ROW LEVEL SECURITY;

--
-- Name: actores direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.actores FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: bitacora direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.bitacora FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: casos_soporte direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.casos_soporte FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: clientes direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.clientes FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: conversaciones direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.conversaciones FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: csw direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.csw FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: decisiones direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.decisiones FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: entregas direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.entregas FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: eventos direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.eventos FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: eventos_errores direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.eventos_errores FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: evidencias direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.evidencias FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: fuentes direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.fuentes FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: ordenes direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.ordenes FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: osi_aprobaciones direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.osi_aprobaciones FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: osi_documentos direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.osi_documentos FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: osi_transiciones direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.osi_transiciones FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: osi_versiones direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.osi_versiones FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: pagos direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.pagos FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: pfv direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.pfv FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: programas direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.programas FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: propuestas direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.propuestas FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: proyectos direccion_lee; Type: POLICY; Schema: miapk; Owner: -
--

CREATE POLICY direccion_lee ON miapk.proyectos FOR SELECT TO authenticated USING (miapk.es_direccion_mfa());


--
-- Name: entregas; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.entregas ENABLE ROW LEVEL SECURITY;

--
-- Name: eventos; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.eventos ENABLE ROW LEVEL SECURITY;

--
-- Name: eventos_errores; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.eventos_errores ENABLE ROW LEVEL SECURITY;

--
-- Name: evidencias; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.evidencias ENABLE ROW LEVEL SECURITY;

--
-- Name: fuentes; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.fuentes ENABLE ROW LEVEL SECURITY;

--
-- Name: ordenes; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.ordenes ENABLE ROW LEVEL SECURITY;

--
-- Name: osi_aprobaciones; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.osi_aprobaciones ENABLE ROW LEVEL SECURITY;

--
-- Name: osi_documentos; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.osi_documentos ENABLE ROW LEVEL SECURITY;

--
-- Name: osi_transiciones; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.osi_transiciones ENABLE ROW LEVEL SECURITY;

--
-- Name: osi_versiones; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.osi_versiones ENABLE ROW LEVEL SECURITY;

--
-- Name: pagos; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.pagos ENABLE ROW LEVEL SECURITY;

--
-- Name: pfv; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.pfv ENABLE ROW LEVEL SECURITY;

--
-- Name: programas; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.programas ENABLE ROW LEVEL SECURITY;

--
-- Name: propuestas; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.propuestas ENABLE ROW LEVEL SECURITY;

--
-- Name: proyectos; Type: ROW SECURITY; Schema: miapk; Owner: -
--

ALTER TABLE miapk.proyectos ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

\unrestrict hFLFctOMgk6bCbkLfp97L9MXZWkQKBml9t5rRMhegEtW0n00bnB0SGTYbp7LI8M

