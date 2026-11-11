-- Huellas de cotejo: conteo y md5 del contenido ordenado de cada tabla del esquema miapk,
-- más la verificación de las huellas OSI aprobadas. Se ejecuta igual en origen y en la copia restaurada.
\pset format unaligned
\pset tuples_only on
do $$
declare t text; n bigint; h text;
begin
  create temp table if not exists huellas (tabla text, filas bigint, md5 text);
  truncate huellas;
  for t in select tablename from pg_tables where schemaname = 'miapk' order by tablename loop
    execute format('select count(*), coalesce(md5(string_agg(x::text, %L order by x::text)), %L) from miapk.%I x', '|', 'vacia', t) into n, h;
    insert into huellas values (t, n, h);
  end loop;
end $$;
select json_build_object(
  'tablas', (select json_agg(json_build_object('tabla', tabla, 'filas', filas, 'md5', md5) order by tabla) from huellas),
  'osi', (select json_agg(json_build_object('codigo', v.codigo, 'version', v.version, 'estado', v.estado,
            'sha256_aprobado', a.sha256_aprobado,
            'sha256_contenido', encode(sha256(convert_to(coalesce(v.contenido, ''), 'UTF8')), 'hex'))
          order by v.codigo, v.version)
          from miapk.osi_versiones v left join miapk.osi_aprobaciones a on a.version_id = v.id),
  'bitacora_cadena_ok', (select bool_and(b.hash_anterior is not distinct from (select p.hash from miapk.bitacora p where p.id < b.id order by p.id desc limit 1))
                          from miapk.bitacora b)
);
