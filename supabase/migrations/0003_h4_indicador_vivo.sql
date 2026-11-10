-- MIAPK · Fase 1 · H4 · Indicador E04 en vivo (laboratorio, datos ficticios, USD 0)
-- Atiende además las salvedades (a)–(c) del dictamen de Magid sobre H3.

-- (a) Significado exacto de firma_verificada.
comment on column miapk.eventos.firma_verificada is
  'true = la credencial de la fuente fue validada contra su hash. NO es una firma digital del origen; la firma criptográfica (p. ej. webhook firmado) llega con fuentes reales.';

-- (c) Etiquetar el origen de cada error para no confundir pruebas negativas con incidentes.
alter table miapk.eventos_errores add column if not exists origen text;
update miapk.eventos_errores set origen = 'prueba negativa H3' where origen is null;

create or replace function miapk.etiquetar_error() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.origen := coalesce(nullif(new.cuerpo ->> 'origen', ''),
                         case when new.fuente_id is null then 'sin fuente identificable' else 'sin etiqueta' end);
  return new;
end $$;
drop trigger if exists eventos_errores_origen on miapk.eventos_errores;
create trigger eventos_errores_origen before insert on miapk.eventos_errores
  for each row execute function miapk.etiquetar_error();

-- El rechazo por credencial inválida conserva también la etiqueta de origen que declare el emisor.
do $do$
declare d text;
begin
  d := pg_get_functiondef('public.miapk_ingerir_evento(text,jsonb)'::regprocedure);
  d := replace(d,
    $r$jsonb_build_object('external_id', p_evento ->> 'external_id', 'type', p_evento ->> 'type')$r$,
    $r$jsonb_build_object('external_id', p_evento ->> 'external_id', 'type', p_evento ->> 'type', 'origen', p_evento ->> 'origen')$r$);
  execute d;
end $do$;

-- ¿La fuente está integrada? (lee credenciales sin exponerlas; solo devuelve sí/no)
create or replace function miapk.fuente_integrada(p_fuente text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from miapk.credenciales_fuente c where c.fuente_id = p_fuente and c.activa);
$$;
revoke all on function miapk.fuente_integrada(text) from public, anon;
grant execute on function miapk.fuente_integrada(text) to authenticated;

-- Indicador E04 n.º 1 «PFV aceptados», alimentado por eventos entrega.pfv.aceptado.
-- Cinco estados (E04): Pendiente · Error · Desactualizado · Sin datos · Confirmado.
create or replace view miapk.v_indicadores with (security_invoker = true) as
with ev as (
  select e.event_id, e.occurred_at, e.received_at
    from miapk.eventos e
   where e.type = 'entrega.pfv.aceptado' and e.fuente_id = 'laboratorio'
), ult as (
  select * from ev order by received_at desc, event_id limit 1
), fu as (
  select f.plazo_esperado,
         miapk.fuente_integrada(f.id) as integrada,
         (select max(e.received_at) from miapk.eventos e where e.fuente_id = f.id) as ultimo_fuente
    from miapk.fuentes f where f.id = 'laboratorio'
), er as (
  select max(x.recibido_en) as ultimo_error
    from miapk.eventos_errores x
   where x.fuente_id = 'laboratorio' and x.cuerpo ->> 'type' = 'entrega.pfv.aceptado'
)
select 'pfv_aceptados'::text                as indicador_id,
       'PFV aceptados'::text                as nombre,
       'laboratorio'::text                  as fuente_id,
       (select count(*) from ev)            as valor,
       case when (select count(*) from ev) > 0 then (select count(*) from ev) - 1 end as valor_anterior,
       (select event_id from ult)           as ultimo_event_id,
       (select occurred_at from ult)        as ultimo_occurred_at,
       (select received_at from ult)        as ultimo_received_at,
       (select ultimo_error from er)        as ultimo_error_at,
       case
         when not coalesce((select integrada from fu), false) then 'Pendiente'
         when (select ultimo_error from er) > coalesce((select received_at from ult), '-infinity'::timestamptz) then 'Error'
         when (select ultimo_fuente from fu) is null
              or (select ultimo_fuente from fu) < now() - coalesce((select plazo_esperado from fu), interval '100 years') then 'Desactualizado'
         when (select count(*) from ev) = 0 then 'Sin datos'
         else 'Confirmado'
       end                                  as estado,
       now()                                as calculado_en;
revoke all on miapk.v_indicadores from public, anon;
grant select on miapk.v_indicadores to authenticated;

select 'H4 aplicado' as resultado;
