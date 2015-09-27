DROP SCHEMA viz CASCADE;
CREATE SCHEMA viz;
SET search_path TO viz, flow, public;

CREATE FUNCTION dot_process(puri text)
  RETURNS SETOF text AS $$
  DECLARE
    f flow.flow;
  BEGIN
    FOR f IN SELECT * FROM flow.flow WHERE process = puri
    LOOP
      RETURN NEXT '"' || f.source || '" -> "' || f.target || '"';
    END LOOP;
    RETURN;
  END;
$$ LANGUAGE plpgsql;

