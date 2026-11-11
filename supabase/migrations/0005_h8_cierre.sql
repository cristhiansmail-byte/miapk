-- MIAPK · Fase 1 · H8 · ajustes para los bloques E09 5, 6 y pendientes de H2 (laboratorio, USD 0)

-- (E09-5) Corrección por evento compensatorio: entrega.pfv.revertido con causation_id = event_id del PFV aceptado.
drop view if exists miapk.v_indicadores;
create view miapk.v_indicadores with (security_invoker = true) as
with acep as (
  select e.event_id, e.occurred_at, e.received_at, 1 as signo
    from miapk.eventos e where e.type = 'entrega.pfv.aceptado' and e.fuente_id = 'laboratorio'
), rev as (
  select distinct on (e.causation_id) e.event_id, e.occurred_at, e.received_at, -1 as signo
    from miapk.eventos e
   where e.type = 'entrega.pfv.revertido' and e.fuente_id = 'laboratorio'
     and e.causation_id in (select event_id from acep)
   order by e.causation_id, e.received_at
), ev as (select * from acep union all select * from rev),
ult as (select * from ev order by received_at desc, event_id limit 1),
fu as (
  select f.plazo_esperado, miapk.fuente_integrada(f.id) as integrada,
         (select max(e.received_at) from miapk.eventos e where e.fuente_id = f.id) as ultimo_fuente
    from miapk.fuentes f where f.id = 'laboratorio'
), er as (
  select max(x.recibido_en) as ultimo_error from miapk.eventos_errores x
   where x.fuente_id = 'laboratorio' and x.cuerpo ->> 'type' like 'entrega.pfv.%'
)
select 'pfv_aceptados'::text as indicador_id, 'PFV aceptados'::text as nombre, 'laboratorio'::text as fuente_id,
       (select coalesce(sum(signo), 0) from ev)::bigint as valor,
       case when (select count(*) from ev) > 0 then ((select coalesce(sum(signo), 0) from ev) - (select signo from ult))::bigint end as valor_anterior,
       (select event_id from ult) as ultimo_event_id,
       (select occurred_at from ult) as ultimo_occurred_at,
       (select received_at from ult) as ultimo_received_at,
       (select ultimo_error from er) as ultimo_error_at,
       case
         when not coalesce((select integrada from fu), false) then 'Pendiente'
         when (select ultimo_error from er) > coalesce((select received_at from ult), '-infinity'::timestamptz) then 'Error'
         when (select ultimo_fuente from fu) is null
              or (select ultimo_fuente from fu) < now() - coalesce((select plazo_esperado from fu), interval '100 years') then 'Desactualizado'
         when (select count(*) from ev) = 0 then 'Sin datos'
         else 'Confirmado'
       end as estado,
       (select count(*) from rev) as correcciones,
       now() as calculado_en;
revoke all on miapk.v_indicadores from public, anon;
grant select on miapk.v_indicadores to authenticated;

-- (E09-6) Los intentos prohibidos de aprobar o poner vigente quedan registrados en la bitácora (no solo rechazados).
do $do$
declare d text;
begin
  d := pg_get_functiondef('miapk.osi_aprobar(uuid,text)'::regprocedure);
  d := replace(d,
    $r$if not miapk.es_direccion_mfa() then raise exception 'OSI: solo Dirección con doble verificación puede aprobar'; end if;$r$,
    $r$if not miapk.es_direccion_mfa() then
    perform miapk.bitacora_agregar(null, 'osi.rechazo', p_version_id::text, jsonb_build_object('intento', 'aprobar', 'uid', auth.uid(), 'aal', auth.jwt() ->> 'aal', 'motivo', 'no es Dirección con aal2'));
    return jsonb_build_object('estado', 'rechazado', 'motivo', 'solo Dirección con doble verificación puede aprobar');
  end if;$r$);
  execute d;
  d := pg_get_functiondef('miapk.osi_poner_vigente(uuid)'::regprocedure);
  d := replace(d,
    $r$if not miapk.es_direccion_mfa() then raise exception 'OSI: solo Dirección con doble verificación puede poner vigente'; end if;$r$,
    $r$if not miapk.es_direccion_mfa() then
    perform miapk.bitacora_agregar(null, 'osi.rechazo', p_version_id::text, jsonb_build_object('intento', 'poner_vigente', 'uid', auth.uid(), 'aal', auth.jwt() ->> 'aal', 'motivo', 'no es Dirección con aal2'));
    return jsonb_build_object('estado', 'rechazado', 'motivo', 'solo Dirección con doble verificación puede poner vigente');
  end if;$r$);
  execute d;
end $do$;

-- (H2 pendiente) Límite a la cola de errores por intentos anónimos con credencial inválida: 20 por minuto.
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.miapk_ingerir_evento(text,jsonb)'::regprocedure);
  if position('límite de intentos inválidos' in d) = 0 then
    d := replace(d, 'if v_fuente is null then',
      $r$if v_fuente is null then
    if (select count(*) from miapk.eventos_errores x where x.fuente_id is null and x.recibido_en > now() - interval '1 minute') >= 20 then
      return jsonb_build_object('estado', 'rechazado', 'motivo', 'límite de intentos inválidos por minuto');
    end if;$r$);
    execute d;
  end if;
end $do$;

select 'H8 aplicado' as resultado;

-- Higiene: las funciones de trigger no se ejecutan por la API.
revoke all on function miapk.prohibir_cambios() from public, anon, authenticated;
revoke all on function miapk.etiquetar_error() from public, anon, authenticated;
revoke all on function miapk.osi_proteger() from public, anon, authenticated;
