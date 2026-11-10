-- MIAPK · Fase 1 · H1 · Esquema de laboratorio (E03) con RLS (E05)
-- Solo datos ficticios. Proyecto: miapk-laboratorio (Supabase Free).
-- Regla: todo cerrado por defecto; Dirección lee con sesión de doble factor (aal2);
-- la escritura llega solo por funciones del servidor (H3), nunca desde la APK.

create schema if not exists miapk;
revoke all on schema miapk from public, anon, authenticated;
grant usage on schema miapk to authenticated;

-- ---------- Transversal ----------
create table miapk.actores (
  id uuid primary key default gen_random_uuid(),
  auth_uid uuid unique,                 -- usuario de Supabase Auth (solo personas)
  nombre text not null,
  tipo text not null check (tipo in ('persona','agente','sistema')),
  hat text not null check (hat in ('direccion','magda','magid','mia_web','mia_apk','operador','sistema')),
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);

create table miapk.fuentes (
  id text primary key,                  -- p. ej. 'laboratorio', 'jetpost', 'pasarela'
  nombre text not null,
  nivel_confianza smallint not null check (nivel_confianza between 1 and 4),
  metodo_autenticidad text not null,
  plazo_esperado interval,
  estado text not null default 'pendiente' check (estado in ('activa','desactualizada','con_error','pendiente'))
);

create table miapk.eventos (
  event_id uuid primary key,
  type text not null check (type ~ '^[a-z_]+\.[a-z_]+\.[a-z_]+$'),
  schema_version smallint not null default 1,
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  fuente_id text not null references miapk.fuentes(id),
  external_id text not null,
  actor_id uuid references miapk.actores(id),
  subject_entity text not null,
  subject_id text not null,
  correlation_id uuid,
  causation_id uuid,
  data jsonb not null default '{}'::jsonb,
  firma_verificada boolean not null default false,
  hash_cuerpo text not null,
  unique (fuente_id, external_id, type)   -- idempotencia (E03)
);

create table miapk.eventos_errores (
  id bigint generated always as identity primary key,
  recibido_en timestamptz not null default now(),
  fuente_id text,
  motivo text not null,
  cuerpo jsonb not null
);

create table miapk.bitacora (
  id bigint generated always as identity primary key,
  en timestamptz not null default now(),
  actor_id uuid references miapk.actores(id),
  accion text not null,
  objeto text not null,
  detalle jsonb not null default '{}'::jsonb,
  hash_anterior text,
  hash text not null
);

-- ---------- Zona Dirección ----------
create table miapk.programas (
  id text primary key,                  -- 'P-1' … 'P-8'
  nombre text not null
);

create table miapk.proyectos (
  id text primary key,                  -- 'P01' … 'P10'
  programa_id text references miapk.programas(id),
  nombre text not null
);

create table miapk.csw (
  id text primary key,                  -- 'CSW-003'
  titulo text not null,
  estado text not null check (estado in ('borrador','presentado','aprobado','rechazado','aprobado_alcance_limitado')),
  creado_en timestamptz not null default now()
);

create table miapk.ordenes (
  id text primary key,                  -- 'OE-MIAPK-002'
  titulo text not null,
  proyecto_id text references miapk.proyectos(id),
  csw_id text references miapk.csw(id),
  estado text not null check (estado in ('borrador','emitida','en_ejecucion','entregada','aceptada','rechazada','suspendida')),
  vence_en date,
  creado_en timestamptz not null default now()
);

create table miapk.decisiones (
  id uuid primary key default gen_random_uuid(),
  en timestamptz not null default now(),
  actor_id uuid not null references miapk.actores(id),
  objeto_tipo text not null,
  objeto_id text not null,
  decision text not null,
  texto_literal text not null
);

create table miapk.evidencias (
  id uuid primary key default gen_random_uuid(),
  orden_id text references miapk.ordenes(id),
  descripcion text not null,
  enlace text,
  hash text,
  creado_en timestamptz not null default now()
);

-- ---------- Zona Operación (solo datos ficticios en laboratorio) ----------
create table miapk.clientes (
  id uuid primary key default gen_random_uuid(),
  alias_ficticio text not null,
  creado_en timestamptz not null default now()
);

create table miapk.conversaciones (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid references miapk.clientes(id),
  iniciada_en timestamptz not null default now(),
  necesidad_confirmada boolean not null default false
);

create table miapk.propuestas (
  id uuid primary key default gen_random_uuid(),
  conversacion_id uuid references miapk.conversaciones(id),
  estado text not null check (estado in ('borrador','emitida','aceptada','rechazada','vencida')),
  emitida_en timestamptz
);

create table miapk.pagos (
  id uuid primary key default gen_random_uuid(),
  propuesta_id uuid references miapk.propuestas(id),
  estado text not null check (estado in ('pendiente','confirmado','fallido','reembolsado')),
  monto numeric(14,2),
  moneda char(3),
  confirmado_en timestamptz
);

create table miapk.entregas (
  id uuid primary key default gen_random_uuid(),
  propuesta_id uuid references miapk.propuestas(id),
  estado text not null check (estado in ('en_produccion','en_qa','publicada','aceptada','con_incidencias')),
  publicada_en timestamptz
);

create table miapk.pfv (
  id uuid primary key default gen_random_uuid(),
  entrega_id uuid unique references miapk.entregas(id),
  aceptado boolean not null,
  calificacion smallint check (calificacion between 1 and 5),
  en timestamptz not null default now()
);

create table miapk.casos_soporte (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid references miapk.clientes(id),
  entrega_id uuid references miapk.entregas(id),
  estado text not null check (estado in ('abierto','cerrado')),
  abierto_en timestamptz not null default now()
);

-- ---------- Zona OSI (experimental, sin WORM) ----------
create table miapk.osi_documentos (
  codigo text primary key check (codigo ~ '^OSI-[A-Z]{2,3}-[0-9]{3}$'),
  titulo text not null,
  tipo text not null,
  nivel_acceso text not null check (nivel_acceso in ('publico_interno','direccion','restringido')),
  ficticio boolean not null default true check (ficticio)   -- laboratorio: solo ficticios
);

create table miapk.osi_versiones (
  id uuid primary key default gen_random_uuid(),
  codigo text not null references miapk.osi_documentos(codigo),
  version text not null,
  estado text not null check (estado in ('borrador','en_revision','aprobado','vigente','sustituido','archivado')),
  archivo_ruta text,
  sha256 text,
  autor_id uuid references miapk.actores(id),
  creado_en timestamptz not null default now(),
  unique (codigo, version)
);

create table miapk.osi_aprobaciones (
  id uuid primary key default gen_random_uuid(),
  version_id uuid not null references miapk.osi_versiones(id),
  decision_id uuid not null references miapk.decisiones(id),
  sha256_aprobado text not null,
  en timestamptz not null default now()
);

-- ---------- Tablas de solo agregar ----------
create or replace function miapk.prohibir_cambios() returns trigger
language plpgsql as $$
begin
  raise exception 'MIAPK: % es de solo agregar; no se permite %', tg_table_name, tg_op;
end $$;

create trigger eventos_solo_agregar before update or delete on miapk.eventos
  for each row execute function miapk.prohibir_cambios();
create trigger bitacora_solo_agregar before update or delete on miapk.bitacora
  for each row execute function miapk.prohibir_cambios();
create trigger decisiones_solo_agregar before update or delete on miapk.decisiones
  for each row execute function miapk.prohibir_cambios();
create trigger osi_aprob_solo_agregar before update or delete on miapk.osi_aprobaciones
  for each row execute function miapk.prohibir_cambios();

-- ---------- Seguridad por fila ----------
-- Dirección = persona activa con hat 'direccion' y sesión con doble factor (aal2).
create or replace function miapk.es_direccion_mfa() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((auth.jwt() ->> 'aal') = 'aal2', false)
     and exists (select 1 from miapk.actores a
                 where a.auth_uid = auth.uid() and a.hat = 'direccion' and a.activo);
$$;
revoke all on function miapk.es_direccion_mfa() from public, anon;
grant execute on function miapk.es_direccion_mfa() to authenticated;

do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'miapk' loop
    execute format('alter table miapk.%I enable row level security', t);
    execute format('alter table miapk.%I force row level security', t);
    execute format('revoke all on miapk.%I from public, anon, authenticated', t);
    execute format('grant select on miapk.%I to authenticated', t);
    execute format('create policy direccion_lee on miapk.%I for select to authenticated using (miapk.es_direccion_mfa())', t);
  end loop;
end $$;

-- ---------- Datos base de laboratorio (no sensibles) ----------
insert into miapk.fuentes (id, nombre, nivel_confianza, metodo_autenticidad, plazo_esperado, estado) values
  ('laboratorio', 'Generador de eventos de prueba', 1, 'credencial de servidor (secreto de GitHub)', interval '1 day', 'pendiente'),
  ('jetpost', 'JetPost (importación asistida)', 4, 'revisión humana + hash del contenido', null, 'activa'),
  ('mia_web', 'MÍA Web', 1, 'credencial de servicio', null, 'pendiente'),
  ('pasarela', 'Pasarela de pagos', 1, 'webhook firmado del proveedor', null, 'pendiente');

insert into miapk.programas (id, nombre) values
  ('P-1','Identidad corporativa'), ('P-2','MÍA y comunicación'), ('P-3','Experiencia de creación'),
  ('P-4','Producción y entrega'), ('P-5','Comercial y publicidad'), ('P-6','Protección y confiabilidad'),
  ('P-7','Medición y mejora'), ('P-8','Internacionalización');
