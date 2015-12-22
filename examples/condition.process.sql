SET search_path TO flow, public;

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
      ('condition.example', 'log4g'   , 'log' , false , 'log gate 4'   , '{"level":"INFO","message":"log gate 4 1"}'),
      ('condition.example', 'join'    , 'log' , false , 'log join'     , '{"level":"INFO","message":"join gates of branch"}'),
      ('condition.example', 'end'     , 'log' , false , 'log end data' , '{"level":"INFO","message":"end conditional example process"}');

    INSERT INTO flow (process, source    , target    , label     , expression  , description) VALUES
      ('condition.example'   , 'start'   , 'gateway' , NULL      , NULL        , 'start to gateway'),
      ('condition.example'   , 'gateway' , 'log1g'   , 'one'     , 'check = 1' , 'gateway to log gate 1'),
      ('condition.example'   , 'gateway' , 'log2g1'  , 'two'     , 'check = 2' , 'gateway to log gate 2 1'),
      ('condition.example'   , 'log2g1'  , 'log2g2'  , NULL      , NULL        , 'gateway to log gate 2 2'),
      ('condition.example'   , 'gateway' , 'log3g1'  , 'gto'     , 'check > 1' , 'gateway to log gate 3 1'),
      ('condition.example'   , 'log3g1'  , 'log3g2'  , NULL      , NULL        , 'gateway to log gate 3 2'),
      ('condition.example'   , 'gateway' , 'log4g'   , 'default' , NULL        , 'gateway to log gate 4'),
      ('condition.example'   , 'log1g'   , 'join'    , NULL      , NULL        , 'join gate 1'),
      ('condition.example'   , 'log2g2'  , 'join'    , NULL      , NULL        , 'join gate 2'),
      ('condition.example'   , 'log3g2'  , 'join'    , NULL      , NULL        , 'join gate 3'),
      ('condition.example'   , 'log4g'   , 'join'    , NULL      , NULL        , 'join gate 4'),
      ('condition.example'   , 'join'    , 'end'     , NULL      , NULL        , 'branch 1 to end');
  END;
$$;
COMMIT;
