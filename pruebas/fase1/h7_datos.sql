-- H7 · datos del informe (solo lectura). Cada cifra sale de una consulta reproducible.
\pset format unaligned
\pset tuples_only on
select json_build_object(
  'corte_utc', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
  'corte_col', to_char(now() at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS'),
  'fuentes', (select json_agg(json_build_object('fuente', r.fuente_id, 'confianza', r.nivel_confianza, 'estado_fuente', r.estado,
                 'eventos', r.eventos, 'errores', r.errores, 'semaforo', r.semaforo,
                 'ultimo_evento_col', to_char(r.ultimo_evento at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS'),
                 'integrada', miapk.fuente_integrada(r.fuente_id)) order by r.fuente_id)
              from miapk.v_resumen_fuentes r),
  'indicador', (select json_build_object('nombre', i.nombre, 'valor', i.valor, 'valor_anterior', i.valor_anterior, 'estado', i.estado,
                 'ultimo_event_id', i.ultimo_event_id,
                 'ultimo_recibido_col', to_char(i.ultimo_received_at at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS'),
                 'ultimo_error_col', to_char(i.ultimo_error_at at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS'))
                from miapk.v_indicadores i),
  'eventos_por_tipo', (select json_agg(json_build_object('type', type, 'n', n) order by type)
                       from (select type, count(*) n from miapk.eventos group by type) x),
  'eventos_total', (select count(*) from miapk.eventos),
  'errores_por_origen', (select json_agg(json_build_object('origen', origen, 'n', n) order by origen)
                         from (select coalesce(origen, 'sin etiqueta') origen, count(*) n from miapk.eventos_errores group by 1) x),
  'errores_total', (select count(*) from miapk.eventos_errores),
  'osi', (select json_agg(json_build_object('codigo', codigo, 'version', version, 'estado', estado, 'integridad', integridad,
            'sha256_aprobado', sha256_aprobado, 'ficticio', ficticio) order by codigo, version) from miapk.v_osi_integridad),
  'bitacora', (select json_build_object('entradas', count(*),
                 'ultimo_hash', (select hash from miapk.bitacora order by id desc limit 1),
                 'cadena_continua', bool_and(b.hash_anterior is not distinct from (select p.hash from miapk.bitacora p where p.id < b.id order by p.id desc limit 1)))
               from miapk.bitacora b),
  'decisiones_direccion', (select count(*) from miapk.decisiones),
  'programas', (select count(*) from miapk.programas),
  'actores_activos', (select json_agg(json_build_object('hat', hat, 'tipo', tipo) order by hat) from miapk.actores where activo)
);
