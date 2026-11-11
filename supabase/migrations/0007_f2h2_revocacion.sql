-- MIAPK · Fase 2 · F2-H2 · Revocación efectiva: una sesión cerrada deja de leer y operar al instante,
-- aunque su JWT de acceso siga siendo criptográficamente válido hasta su vencimiento.
-- auth.sessions no se expone: solo una función security definer responde sí/no sobre la sesión del propio token.
create or replace function miapk.sesion_vigente() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (auth.jwt() ->> 'session_id') is not null
    and exists (select 1 from auth.sessions s
                 where s.id = (auth.jwt() ->> 'session_id')::uuid
                   and s.user_id = auth.uid()),
    false);
$$;
revoke all on function miapk.sesion_vigente() from public, anon;
grant execute on function miapk.sesion_vigente() to authenticated;

-- Dirección = hat 'direccion' + aal2 + sesión todavía viva en el servidor.
create or replace function miapk.es_direccion_mfa() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((auth.jwt() ->> 'aal') = 'aal2', false)
     and miapk.sesion_vigente()
     and exists (select 1 from miapk.actores a
                 where a.auth_uid = auth.uid() and a.hat = 'direccion' and a.activo);
$$;
revoke all on function miapk.es_direccion_mfa() from public, anon;
grant execute on function miapk.es_direccion_mfa() to authenticated;
