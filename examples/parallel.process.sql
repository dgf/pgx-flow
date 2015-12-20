SET search_path TO flow, public;
BEGIN TRANSACTION;
DO $$
  BEGIN

    INSERT INTO process (uri, description) VALUES
      ('parallel.example', 'a parallel process with two gateways, some synchronous log activities and one asynchronous task activity');

    INSERT INTO activity (process, uri, func   , async , description            , config) VALUES
      ('parallel.example', 'start'    , 'log'  , false , 'log start data'       , '{"level":"INFO","message":"start parallel example process"}'),
      ('parallel.example', 'gateway1' , 'log'  , false , 'log gateway branch 1' , '{"level":"INFO","message":"parallel gateway branches 1"}'),
      ('parallel.example', 'log1b1g'  , 'log'  , false , 'log branch 1 gate 1'  , '{"level":"INFO","message":"parallel log branch 1 gate 1"}'),
      ('parallel.example', 'gateway2' , 'log'  , false , 'log gateway branch 2' , '{"level":"INFO","message":"parallel gateway branches 2"}'),
      ('parallel.example', 'log2b1g'  , 'log'  , false , 'log branch 2 gate 1'  , '{"level":"INFO","message":"parallel log branch 2 gate 1"}'),
      ('parallel.example', 'task2b2g' , 'task' , true  , 'create a task'        , '{"group":"staff","subject":"confirm branch 2 gate 2"}'),
      ('parallel.example', 'join2'    , 'log'  , false , 'log join branch 2'    , '{"level":"INFO","message":"join gates of branch 2"}'),
      ('parallel.example', 'join1'    , 'log'  , false , 'log join branch 1'    , '{"level":"INFO","message":"join gates of branch 1"}'),
      ('parallel.example', 'end'      , 'log'  , false , 'log end data'         , '{"level":"INFO","message":"end parallel example process"}');

    INSERT INTO flow (process, source     , target     , label  , description) VALUES
      ('parallel.example'    , 'start'    , 'gateway1' , NULL   ,'start to gateway 1'),
      ('parallel.example'    , 'gateway1' , 'log1b1g'  , 'one'  ,'parallel to log branch 1 gate 1'),
      ('parallel.example'    , 'log1b1g'  , 'join1'    , NULL   ,'log to join branch 1'),
      ('parallel.example'    , 'gateway1' , 'gateway2' , 'two'  ,'parallel to next gateway'),
      ('parallel.example'    , 'gateway2' , 'log2b1g'  , 'three','parallel to log branch 2 gate 1'),
      ('parallel.example'    , 'gateway2' , 'task2b2g' , 'four' ,'parallel to task of branch 2'),
      ('parallel.example'    , 'log2b1g'  , 'join2'    , NULL   ,'task to join branch 2'),
      ('parallel.example'    , 'task2b2g' , 'join2'    , NULL   ,'task to join branch 2'),
      ('parallel.example'    , 'join2'    , 'join1'    , NULL   ,'branch 2 back to branch 1'),
      ('parallel.example'    , 'join1'    , 'end'      , NULL   ,'branch 1 to end');
  END;
$$;
COMMIT;
