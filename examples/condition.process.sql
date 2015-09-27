SET search_path TO flow, public;

CREATE FUNCTION check_one(puid uuid, activity text, data json)
  RETURNS boolean AS $$
  BEGIN
    IF (data->'check')::text::int = 1 THEN
      RETURN true;
    ELSE
      RETURN false;
    END IF;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION check_two(puid uuid, activity text, data json)
  RETURNS boolean AS $$
  BEGIN
    IF (data->'check')::text::int = 2 THEN
      RETURN true;
    ELSE
      RETURN false;
    END IF;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION check_gt_one(puid uuid, activity text, data json)
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
      ('condition.process', 'a conditional process');

    INSERT INTO activity (uri, proc  , async , description    , config) VALUES
      ('condition.gateway'   , 'log' , false , 'log gateway'  , '{"level":"INFO","message":"gateway branches"}'),
      ('condition.log1g'     , 'log' , false , 'log gate 1'   , '{"level":"INFO","message":"log gate 1"}'),
      ('condition.log2g1'    , 'log' , false , 'log gate 2 1' , '{"level":"INFO","message":"log gate 2 1"}'),
      ('condition.log2g2'    , 'log' , false , 'log gate 2 2' , '{"level":"INFO","message":"log gate 2 2"}'),
      ('condition.log3g1'    , 'log' , false , 'log gate 3 1' , '{"level":"INFO","message":"log gate 3 1"}'),
      ('condition.log3g2'    , 'log' , false , 'log gate 3 2' , '{"level":"INFO","message":"log gate 3 2"}'),
      ('condition.join'      , 'log' , false , 'log join'     , '{"level":"INFO","message":"join gates of branch"}');

    INSERT INTO flow (process, source              , target              , label , condition      , description) VALUES
      ('condition.process'   , 'start'             , 'condition.gateway' , NULL  ,NULL           , 'start to gateway'),
      ('condition.process'   , 'condition.gateway' , 'condition.log1g'   , 'one' ,'check_one'    , 'gateway to log gate 1'),
      ('condition.process'   , 'condition.gateway' , 'condition.log2g1'  , 'two' ,'check_two'    , 'gateway to log gate 2 1'),
      ('condition.process'   , 'condition.log2g1'  , 'condition.log2g2'  , NULL  ,NULL           , 'gateway to log gate 2 2'),
      ('condition.process'   , 'condition.gateway' , 'condition.log3g1'  , 'gto' ,'check_gt_one' , 'gateway to log gate 3 1'),
      ('condition.process'   , 'condition.log3g1'  , 'condition.log3g2'  , NULL  ,NULL           , 'gateway to log gate 3 2'),
      ('condition.process'   , 'condition.log1g'   , 'condition.join'    , NULL  ,NULL           , 'join gate 1'),
      ('condition.process'   , 'condition.log2g2'  , 'condition.join'    , NULL  ,NULL           , 'join gate 2'),
      ('condition.process'   , 'condition.log3g2'  , 'condition.join'    , NULL  ,NULL           , 'join gate 3'),
      ('condition.process'   , 'condition.join'    , 'end'               , NULL  ,NULL           , 'branch 1 to end');
  END;
$$;
COMMIT;

