DROP SCHEMA deps CASCADE;
CREATE SCHEMA deps;
SET search_path TO deps, public;

CREATE VIEW database_objects AS (
  WITH all_tables AS (
    SELECT 'table'::TEXT t, c.oid id, c.relname oname FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE c.relkind = 'r' AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  ), all_views AS (
    SELECT 'view'::TEXT t, c.oid id, c.relname oname FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE c.relkind = 'v' AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  ), all_procs AS (
    SELECT 'proc'::TEXT t, p.oid id, p.proname oname FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  )
  SELECT t, id, oname FROM all_tables
  UNION
  SELECT t, id, oname FROM all_views
  UNION
  SELECT t, id, oname FROM all_procs
);

CREATE VIEW dependencies AS (
  -- combine all objects with pgAdmin3 dependency query
  SELECT DISTINCT
    o.id
  , o.t
  , o.oname
  , dep.objid
  , CASE dep.deptype
    WHEN 'n' THEN 'normal'
    WHEN 'a' THEN 'autodependent'
    WHEN 'i' THEN 'internal'
    WHEN 'e' THEN 'extension'
    WHEN 'p' THEN 'pin'
    ELSE 'deptype ' || dep.deptype || ' n/a'
    END AS deptype
  , CASE cl.relkind
    WHEN 'r' THEN 'table'
    WHEN 'i' THEN 'index'
    WHEN 'S' THEN 'sequence'
    WHEN 'v' THEN 'view'
    WHEN 'm' THEN 'materialized view'
    WHEN 'c' THEN 'composite type'
    WHEN 't' THEN 'toast'
    WHEN 'f' THEN 'foreign table'
    ELSE 'relkind ' || cl.relkind || ' n/a'
    END AS reltype
  , CASE
    WHEN cl.relkind IS NOT NULL THEN cl.relkind || COALESCE(dep.objsubid::text, '')
    WHEN tg.oid IS NOT NULL THEN 'trigger'::text
    WHEN ty.oid IS NOT NULL THEN 'type'::text
    WHEN ns.oid IS NOT NULL THEN 'namespace'::text
    WHEN pr.oid IS NOT NULL THEN 'procedure'::text
    WHEN la.oid IS NOT NULL THEN 'language'::text
    WHEN rw.oid IS NOT NULL THEN 'rewrite'::text
    WHEN co.oid IS NOT NULL THEN CASE co.contype
      WHEN 'p' THEN 'primary'
      WHEN 'f' THEN 'foreign'
      WHEN 'u' THEN 'unique'
      ELSE concat_ws('_', 'constraint', co.contype) END
    WHEN ad.oid IS NOT NULL THEN 'attrdef'::text
    ELSE ''
    END AS cltype
  , COALESCE(coc.relname, clrw.relname) AS ownertable
  , CASE
    WHEN cl.relname IS NOT NULL AND att.attname IS NOT NULL THEN cl.relname || '.' || att.attname
    ELSE COALESCE(cl.relname, co.conname, pr.proname, tg.tgname, ty.typname, la.lanname, rw.rulename, ns.nspname)
    END AS refname
  , COALESCE(nsc.nspname, nso.nspname, nsp.nspname, nst.nspname, nsrw.nspname) AS nspname
  FROM database_objects o
  LEFT JOIN pg_depend dep ON dep.refobjid = o.id
  LEFT JOIN pg_class cl ON dep.objid = cl.oid
  LEFT JOIN pg_attribute att ON dep.objid=att.attrelid AND dep.objsubid = att.attnum
  LEFT JOIN pg_namespace nsc ON cl.relnamespace = nsc.oid
  LEFT JOIN pg_proc pr ON dep.objid = pr.oid
  LEFT JOIN pg_namespace nsp ON pr.pronamespace = nsp.oid
  LEFT JOIN pg_trigger tg ON dep.objid = tg.oid
  LEFT JOIN pg_type ty ON dep.objid = ty.oid
  LEFT JOIN pg_namespace nst ON ty.typnamespace = nst.oid
  LEFT JOIN pg_constraint co ON dep.objid = co.oid
  LEFT JOIN pg_class coc ON co.conrelid = coc.oid
  LEFT JOIN pg_namespace nso ON co.connamespace = nso.oid
  LEFT JOIN pg_rewrite rw ON dep.objid = rw.oid
  LEFT JOIN pg_class clrw ON clrw.oid = rw.ev_class
  LEFT JOIN pg_namespace nsrw ON clrw.relnamespace = nsrw.oid
  LEFT JOIN pg_language la ON dep.objid = la.oid
  LEFT JOIN pg_namespace ns ON dep.objid = ns.oid
  LEFT JOIN pg_attrdef ad ON ad.oid = dep.objid
  WHERE classid IN (SELECT oid FROM pg_class
  WHERE relname IN ('pg_class', 'pg_constraint', 'pg_conversion'
  , 'pg_language', 'pg_proc', 'pg_rewrite', 'pg_namespace', 'pg_trigger', 'pg_type', 'pg_attrdef'))
);

CREATE VIEW dependency_list AS (
  SELECT t, oname, cltype, ownertable, refname FROM dependencies
  -- filter global name spaces
  WHERE nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
  -- filter primary, unique keys,
  AND (cltype IS NULL OR cltype NOT IN ('primary', 'unique', 'type'))
  -- filter sequences
  AND (reltype IS NULL OR reltype NOT IN ('sequence'))
  -- remove self references
  AND oname <> ownertable
  ORDER BY t, oname, cltype
);

CREATE VIEW dependency_graph AS (
  SELECT ownertable || ' -> ' || oname || ' [label="' || refname || '"];' FROM dependency_list ORDER BY ownertable, oname, refname
);

