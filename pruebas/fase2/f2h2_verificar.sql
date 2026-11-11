-- F2-H2 · verificación en el servidor (simulando tokens; no usa secretos)
\pset format unaligned
\pset tuples_only on
begin;
create temp table t (n text, r text);
grant all on t to authenticated;
do $$
declare v_dir uuid; v_ses uuid; c bigint; r jsonb;
begin
  select auth_uid into v_dir from miapk.actores where hat='direccion';
  -- 1) token aal2 de Dirección con una sesión INEXISTENTE (equivale a sesión cerrada)
  perform set_config('request.jwt.claims', json_build_object('sub',v_dir,'aal','aal2','role','authenticated','session_id',gen_random_uuid())::text, true);
  set local role authenticated;
  select count(*) into c from miapk.programas; insert into t values ('1 sesión cerrada · lee programas', c||' filas');
  r := miapk.osi_aprobar((select id from miapk.osi_versiones limit 1), 'prueba F2-H2'); insert into t values ('2 sesión cerrada · aprobar OSI', r->>'estado');
  reset role;
  -- 2) token sin session_id
  perform set_config('request.jwt.claims', json_build_object('sub',v_dir,'aal','aal2','role','authenticated')::text, true);
  set local role authenticated;
  select count(*) into c from miapk.programas; insert into t values ('3 token sin session_id · lee programas', c||' filas');
  reset role;
  -- 3) control: sesión viva temporal (creada y borrada dentro de esta transacción)
  insert into auth.sessions (id, user_id, created_at, updated_at, aal) values (gen_random_uuid(), v_dir, now(), now(), 'aal2') returning id into v_ses;
  perform set_config('request.jwt.claims', json_build_object('sub',v_dir,'aal','aal2','role','authenticated','session_id',v_ses)::text, true);
  set local role authenticated;
  select count(*) into c from miapk.programas; insert into t values ('4 control sesión viva · lee programas', c||' filas');
  reset role;
  delete from auth.sessions where id = v_ses;
  perform set_config('request.jwt.claims', json_build_object('sub',v_dir,'aal','aal2','role','authenticated','session_id',v_ses)::text, true);
  set local role authenticated;
  select count(*) into c from miapk.programas; insert into t values ('5 misma sesión tras borrarla · lee programas', c||' filas');
  reset role;
end $$;
select n||' → '||r from t order by n;
select 'anon puede leer auth.sessions: '||has_table_privilege('anon','auth.sessions','select')||' · authenticated: '||has_table_privilege('authenticated','auth.sessions','select');
rollback;
