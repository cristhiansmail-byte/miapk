-- MIAPK · H8 · E09-2: cerrar todas las sesiones de quien lo pide (borra sus filas en auth.sessions y, en cascada, sus refresh tokens).
-- Los access tokens ya emitidos siguen válidos hasta su vencimiento (máx. 1 h): límite documentado.
create or replace function miapk.cerrar_mis_sesiones()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  if auth.uid() is null then return jsonb_build_object('estado','rechazado','motivo','sin sesión'); end if;
  delete from auth.sessions where user_id = auth.uid();
  get diagnostics n = row_count;
  perform miapk.bitacora_agregar((select id from miapk.actores where auth_uid = auth.uid() limit 1), 'sesion.cerrar_todas', 'auth.sessions',
          jsonb_build_object('uid', auth.uid(), 'sesiones_cerradas', n));
  return jsonb_build_object('estado','cerradas','sesiones', n);
end $$;
revoke all on function miapk.cerrar_mis_sesiones() from public, anon;
grant execute on function miapk.cerrar_mis_sesiones() to authenticated;
