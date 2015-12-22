DROP SCHEMA viz CASCADE;
CREATE SCHEMA viz;
SET search_path TO viz, flow, public;

CREATE FUNCTION dot_process(uri text)
  RETURNS SETOF text AS $$
  DECLARE
    f flow.flow;
  BEGIN
    FOR f IN SELECT * FROM flow.flow WHERE process = uri
    LOOP
      RETURN NEXT '"' || f.source || '" -> "' || f.target || '"' || ' [label="' || COALESCE(f.label, '') || '"];';
    END LOOP;
    RETURN;
  END;
$$ LANGUAGE plpgsql;
