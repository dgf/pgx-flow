SET search_path TO flow, public;

CREATE FUNCTION check_one(instance uuid, activity text, data json)
  RETURNS boolean AS $$
  BEGIN
    IF (data->'check')::text::int = 1 THEN
      RETURN true;
    ELSE
      RETURN false;
    END IF;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION check_two(instance uuid, activity text, data json)
  RETURNS boolean AS $$
  BEGIN
    IF (data->'check')::text::int = 2 THEN
      RETURN true;
    ELSE
      RETURN false;
    END IF;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION check_gt_one(instance uuid, activity text, data json)
  RETURNS boolean AS $$
  BEGIN
    IF (data->'check')::text::int > 1 THEN
      RETURN true;
    ELSE
      RETURN false;
    END IF;
  END;
$$ LANGUAGE plpgsql;

BEGIN TRANSACTION;
DO $$
  BEGIN

    INSERT INTO process (uri, description) VALUES
      ('condition.example', 'a conditional process');

    INSERT INTO activity (process, uri, func  , async , description    , config) VALUES
      ('condition.example', 'start'   , 'log' , false , 'log start'    , '{"level":"INFO","message":"start conditional example process"}'),
      ('condition.example', 'gateway' , 'log' , false , 'log gateway'  , '{"level":"INFO","message":"gateway branches"}'),
      ('condition.example', 'log1g'   , 'log' , false , 'log gate 1'   , '{"level":"INFO","message":"log gate 1"}'),
      ('condition.example', 'log2g1'  , 'log' , false , 'log gate 2 1' , '{"level":"INFO","message":"log gate 2 1"}'),
      ('condition.example', 'log2g2'  , 'log' , false , 'log gate 2 2' , '{"level":"INFO","message":"log gate 2 2"}'),
      ('condition.example', 'log3g1'  , 'log' , false , 'log gate 3 1' , '{"level":"INFO","message":"log gate 3 1"}'),
      ('condition.example', 'log3g2'  , 'log' , false , 'log gate 3 2' , '{"level":"INFO","message":"log gate 3 2"}'),
      ('condition.example', 'join'    , 'log' , false , 'log join'     , '{"level":"INFO","message":"join gates of branch"}'),
      ('condition.example', 'end'     , 'log' , false , 'log end data' , '{"level":"INFO","message":"end conditional example process"}');

    INSERT INTO flow (process, source    , target    , label , condition      , description) VALUES
      ('condition.example'   , 'start'   , 'gateway' , NULL  ,NULL           , 'start to gateway'),
      ('condition.example'   , 'gateway' , 'log1g'   , 'one' ,'check_one'    , 'gateway to log gate 1'),
      ('condition.example'   , 'gateway' , 'log2g1'  , 'two' ,'check_two'    , 'gateway to log gate 2 1'),
      ('condition.example'   , 'log2g1'  , 'log2g2'  , NULL  ,NULL           , 'gateway to log gate 2 2'),
      ('condition.example'   , 'gateway' , 'log3g1'  , 'gto' ,'check_gt_one' , 'gateway to log gate 3 1'),
      ('condition.example'   , 'log3g1'  , 'log3g2'  , NULL  ,NULL           , 'gateway to log gate 3 2'),
      ('condition.example'   , 'log1g'   , 'join'    , NULL  ,NULL           , 'join gate 1'),
      ('condition.example'   , 'log2g2'  , 'join'    , NULL  ,NULL           , 'join gate 2'),
      ('condition.example'   , 'log3g2'  , 'join'    , NULL  ,NULL           , 'join gate 3'),
      ('condition.example'   , 'join'    , 'end'     , NULL  ,NULL           , 'branch 1 to end');
  END;
$$;
COMMIT;
