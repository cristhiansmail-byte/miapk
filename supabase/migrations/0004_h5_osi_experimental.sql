-- MIAPK · Fase 1 · H5 · OSI experimental (solo documentos ficticios, USD 0)
-- Ciclo Borrador → En revisión → Aprobado → Vigente, con versión, SHA-256, aprobación humana de Dirección
-- (aal2) y alerta ante alteración. Sin custodia legal, sin WORM, sin inmutabilidad garantizada.

-- Actor de Magda (agente que redacta y envía a revisión; no aprueba).
insert into miapk.actores (nombre, tipo, hat)
select 'Magda (Claude)', 'agente', 'magda'
where not exists (select 1 from miapk.actores where hat = 'magda');

alter table miapk.osi_versiones add column if not exists contenido text;

-- Historial de transiciones (solo agregar).
create table if not exists miapk.osi_transiciones (
  id bigint generated always as identity primary key,
  version_id uuid not null references miapk.osi_versiones(id),
  de text,
  a text not null,
  actor_id uuid references miapk.actores(id),
  sha256 text,
  en timestamptz not null default now()
);
drop trigger if exists osi_trans_solo_agregar on miapk.osi_transiciones;
create trigger osi_trans_solo_agregar before update or delete on miapk.osi_transiciones
  for each row execute function miapk.prohibir_cambios();
alter table miapk.osi_transiciones enable row level security;
alter table miapk.osi_transiciones force row level security;
revoke all on miapk.osi_transiciones from public, anon, authenticated;
grant select on miapk.osi_transiciones to authenticated;
drop policy if exists direccion_lee on miapk.osi_transiciones;
create policy direccion_lee on miapk.osi_transiciones for select to authenticated using (miapk.es_direccion_mfa());

-- Protección de versiones: el hash se calcula en el servidor; fuera de borrador el contenido no cambia; no se borra.
create or replace function miapk.osi_proteger() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'OSI: las versiones no se borran';
  end if;
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
drop trigger if exists osi_proteger_t on miapk.osi_versiones;
create trigger osi_proteger_t before insert or update or delete on miapk.osi_versiones
  for each row execute function miapk.osi_proteger();

-- Bitácora encadenada (uso interno).
create or replace function miapk.bitacora_agregar(p_actor uuid, p_accion text, p_objeto text, p_detalle jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare v_prev text;
begin
  select b.hash into v_prev from miapk.bitacora b order by b.id desc limit 1;
  insert into miapk.bitacora (actor_id, accion, objeto, detalle, hash_anterior, hash)
  values (p_actor, p_accion, p_objeto, p_detalle, v_prev,
          encode(sha256(convert_to(coalesce(v_prev, '') || p_detalle::text, 'UTF8')), 'hex'));
end $$;
revoke all on function miapk.bitacora_agregar(uuid, text, text, jsonb) from public, anon, authenticated;

-- Magda redacta (solo desde el panel del servidor; sin permiso por la API).
create or replace function miapk.osi_redactar(p_codigo text, p_titulo text, p_tipo text, p_version text, p_contenido text)
returns uuid language plpgsql security definer set search_path = '' as $$
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

create or replace function miapk.osi_enviar_a_revision(p_version_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
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
revoke all on function miapk.osi_redactar(text, text, text, text, text) from public, anon, authenticated;
revoke all on function miapk.osi_enviar_a_revision(uuid) from public, anon, authenticated;

-- Dirección aprueba (desde la APK, con doble verificación).
create or replace function miapk.osi_aprobar(p_version_id uuid, p_texto_literal text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_dir uuid; v miapk.osi_versiones; v_actual text; v_dec uuid;
begin
  if not miapk.es_direccion_mfa() then raise exception 'OSI: solo Dirección con doble verificación puede aprobar'; end if;
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

create or replace function miapk.osi_poner_vigente(p_version_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_dir uuid; v miapk.osi_versiones; v_actual text; v_aprob text;
begin
  if not miapk.es_direccion_mfa() then raise exception 'OSI: solo Dirección con doble verificación puede poner vigente'; end if;
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
revoke all on function miapk.osi_aprobar(uuid, text) from public, anon;
revoke all on function miapk.osi_poner_vigente(uuid) from public, anon;
grant execute on function miapk.osi_aprobar(uuid, text) to authenticated;
grant execute on function miapk.osi_poner_vigente(uuid) to authenticated;

-- Verificación de integridad (alerta ante alteración), visible solo para Dirección aal2.
create or replace view miapk.v_osi_integridad with (security_invoker = true) as
select v.id as version_id, v.codigo, d.titulo, v.version, v.estado,
       v.sha256 as sha256_registrado,
       encode(sha256(convert_to(coalesce(v.contenido, ''), 'UTF8')), 'hex') as sha256_actual,
       (select a.sha256_aprobado from miapk.osi_aprobaciones a where a.version_id = v.id order by a.en desc limit 1) as sha256_aprobado,
       case
         when encode(sha256(convert_to(coalesce(v.contenido, ''), 'UTF8')), 'hex') <> v.sha256 then 'ALTERADO'
         when (select a.sha256_aprobado from miapk.osi_aprobaciones a where a.version_id = v.id order by a.en desc limit 1)
              is distinct from null
          and (select a.sha256_aprobado from miapk.osi_aprobaciones a where a.version_id = v.id order by a.en desc limit 1)
              <> encode(sha256(convert_to(coalesce(v.contenido, ''), 'UTF8')), 'hex') then 'ALTERADO'
         else 'Íntegro'
       end as integridad,
       d.ficticio,
       (select max(t.en) from miapk.osi_transiciones t where t.version_id = v.id) as ultima_transicion,
       now() as verificado_en
  from miapk.osi_versiones v join miapk.osi_documentos d on d.codigo = v.codigo;
revoke all on miapk.v_osi_integridad from public, anon;
grant select on miapk.v_osi_integridad to authenticated;

select 'H5 aplicado' as resultado;
