-- MIAPK · Fase 1 · H3 · Motor de eventos (laboratorio, datos ficticios, USD 0)
-- Una sola puerta de entrada: public.miapk_ingerir_evento(credencial, evento).
-- No se abre escritura directa a ninguna tabla ni se cambian permisos del esquema miapk.

-- 1. Credenciales por fuente: solo se guarda el hash SHA-256; el valor vive en un secreto de GitHub.
create table if not exists miapk.credenciales_fuente (
  fuente_id text primary key references miapk.fuentes(id),
  hash_credencial text not null check (hash_credencial ~ '^[0-9a-f]{64}$'),
  activa boolean not null default true,
  creada_en timestamptz not null default now()
);
alter table miapk.credenciales_fuente enable row level security;
alter table miapk.credenciales_fuente force row level security;
revoke all on miapk.credenciales_fuente from public, anon, authenticated;
-- Sin política: nadie la lee por la API (ni siquiera Dirección); solo la función de ingesta.

-- 2. Motor de ingesta.
create or replace function public.miapk_ingerir_evento(p_credencial text, p_evento jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fuente text;
  v_motivo text;
  v_event_id uuid;
  v_occurred timestamptz;
  v_hash text;
  v_insertado int;
  v_prev text;
  v_det jsonb;
begin
  -- a) Autenticidad de la fuente (la fuente se deduce de la credencial, nunca del cuerpo).
  select c.fuente_id into v_fuente
    from miapk.credenciales_fuente c
   where c.activa
     and c.hash_credencial = encode(sha256(convert_to(coalesce(p_credencial, ''), 'UTF8')), 'hex');

  if v_fuente is null then
    insert into miapk.eventos_errores (fuente_id, motivo, cuerpo)
    values (null, 'credencial inválida', jsonb_build_object('external_id', p_evento ->> 'external_id', 'type', p_evento ->> 'type'));
    return jsonb_build_object('estado', 'rechazado', 'motivo', 'credencial inválida');
  end if;

  -- b) Separación rol/fuente: si el cuerpo declara otra fuente, se rechaza.
  if p_evento ? 'fuente_id' and p_evento ->> 'fuente_id' is distinct from v_fuente then
    v_motivo := 'la fuente declarada no coincide con la credencial';
  -- c) Validación de esquema (E03).
  elsif jsonb_typeof(p_evento) is distinct from 'object' then
    v_motivo := 'el evento no es un objeto JSON';
  elsif coalesce(p_evento ->> 'event_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    v_motivo := 'event_id ausente o no es UUID';
  elsif coalesce(p_evento ->> 'type', '') !~ '^[a-z_]+\.[a-z_]+\.[a-z_]+$' then
    v_motivo := 'type inválido (formato dominio.entidad.accion)';
  elsif coalesce(p_evento ->> 'external_id', '') = '' then
    v_motivo := 'external_id ausente';
  elsif coalesce(p_evento ->> 'subject_entity', '') = '' or coalesce(p_evento ->> 'subject_id', '') = '' then
    v_motivo := 'subject_entity o subject_id ausente';
  elsif p_evento ? 'data' and jsonb_typeof(p_evento -> 'data') is distinct from 'object' then
    v_motivo := 'data debe ser un objeto';
  elsif coalesce(p_evento -> 'data' ->> 'ficticio', '') <> 'true' then
    v_motivo := 'laboratorio: solo se aceptan datos marcados ficticio=true';
  end if;

  if v_motivo is null then
    begin
      v_occurred := (p_evento ->> 'occurred_at')::timestamptz;
    exception when others then
      v_motivo := 'occurred_at inválido';
    end;
    if v_motivo is null and (v_occurred is null or v_occurred > now() + interval '5 minutes') then
      v_motivo := 'occurred_at ausente o en el futuro';
    end if;
  end if;

  if v_motivo is not null then
    insert into miapk.eventos_errores (fuente_id, motivo, cuerpo) values (v_fuente, v_motivo, p_evento);
    return jsonb_build_object('estado', 'rechazado', 'motivo', v_motivo);
  end if;

  -- d) Inserción idempotente.
  v_event_id := (p_evento ->> 'event_id')::uuid;
  v_hash := encode(sha256(convert_to(p_evento::text, 'UTF8')), 'hex');

  insert into miapk.eventos (event_id, type, schema_version, occurred_at, fuente_id, external_id,
                             subject_entity, subject_id, correlation_id, causation_id, data,
                             firma_verificada, hash_cuerpo)
  values (v_event_id, p_evento ->> 'type', coalesce((p_evento ->> 'schema_version')::smallint, 1), v_occurred,
          v_fuente, p_evento ->> 'external_id', p_evento ->> 'subject_entity', p_evento ->> 'subject_id',
          nullif(p_evento ->> 'correlation_id', '')::uuid, nullif(p_evento ->> 'causation_id', '')::uuid,
          coalesce(p_evento -> 'data', '{}'::jsonb), true, v_hash)
  on conflict do nothing;
  get diagnostics v_insertado = row_count;

  if v_insertado = 0 then
    return jsonb_build_object('estado', 'duplicado', 'event_id', v_event_id);
  end if;

  -- e) Bitácora encadenada por hash y estado de la fuente.
  select b.hash into v_prev from miapk.bitacora b order by b.id desc limit 1;
  v_det := jsonb_build_object('event_id', v_event_id, 'type', p_evento ->> 'type', 'fuente', v_fuente, 'hash_cuerpo', v_hash);
  insert into miapk.bitacora (accion, objeto, detalle, hash_anterior, hash)
  values ('evento.recibido', 'eventos/' || v_event_id, v_det, v_prev,
          encode(sha256(convert_to(coalesce(v_prev, '') || v_det::text, 'UTF8')), 'hex'));

  update miapk.fuentes set estado = 'activa' where id = v_fuente;

  return jsonb_build_object('estado', 'aceptado', 'event_id', v_event_id);
end $$;

revoke all on function public.miapk_ingerir_evento(text, jsonb) from public, authenticated;
grant execute on function public.miapk_ingerir_evento(text, jsonb) to anon;

-- 3. Recálculo (E04): resumen por fuente, visible solo para Dirección con doble verificación (RLS del invocador).
create or replace view miapk.v_resumen_fuentes with (security_invoker = true) as
select f.id as fuente_id,
       f.nivel_confianza,
       f.estado,
       (select count(*) from miapk.eventos e where e.fuente_id = f.id) as eventos,
       (select max(e.received_at) from miapk.eventos e where e.fuente_id = f.id) as ultimo_evento,
       (select count(*) from miapk.eventos_errores x where x.fuente_id = f.id) as errores,
       case
         when (select max(e.received_at) from miapk.eventos e where e.fuente_id = f.id) is null then 'Sin datos'
         when f.plazo_esperado is not null
              and (select max(e.received_at) from miapk.eventos e where e.fuente_id = f.id) < now() - f.plazo_esperado then 'Desactualizado'
         when exists (select 1 from miapk.eventos_errores x where x.fuente_id = f.id and x.recibido_en > now() - interval '1 day') then 'Con errores recientes'
         else 'Al día'
       end as semaforo
  from miapk.fuentes f;
revoke all on miapk.v_resumen_fuentes from public, anon;
grant select on miapk.v_resumen_fuentes to authenticated;
