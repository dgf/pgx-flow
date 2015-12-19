SET search_path TO flow, public;
BEGIN TRANSACTION;
DO $$
  BEGIN

    INSERT INTO process (uri, description) VALUES
      ('parallel.process', 'a parallel process with two gateways, some synchronous log activities and one asynchronous task activity');

    INSERT INTO activity (uri, func   , async , description            , config) VALUES
      ('parallel.gateway1'   , 'log'  , false , 'log gateway branch 1' , '{"level":"INFO","message":"parallel gateway branches 1"}'),
      ('parallel.log1b1g'    , 'log'  , false , 'log branch 1 gate 1'  , '{"level":"INFO","message":"parallel log branch 1 gate 1"}'),
      ('parallel.gateway2'   , 'log'  , false , 'log gateway branch 2' , '{"level":"INFO","message":"parallel gateway branches 2"}'),
      ('parallel.log2b1g'    , 'log'  , false , 'log branch 2 gate 1'  , '{"level":"INFO","message":"parallel log branch 2 gate 1"}'),
      ('parallel.task2b2g'   , 'task' , true  , 'create a task'        , '{"group":"staff","subject":"confirm branch 2 gate 2"}'),
      ('parallel.join2'      , 'log'  , false , 'log join branch 2'    , '{"level":"INFO","message":"join gates of branch 2"}'),
      ('parallel.join1'      , 'log'  , false , 'log join branch 1'    , '{"level":"INFO","message":"join gates of branch 1"}');

    INSERT INTO flow (process, source              , target              , label  , description) VALUES
      ('parallel.process'    , 'start'             , 'parallel.gateway1' , NULL   ,'start to gateway 1'),
      ('parallel.process'    , 'parallel.gateway1' , 'parallel.log1b1g'  , 'one'  ,'parallel to log branch 1 gate 1'),
      ('parallel.process'    , 'parallel.log1b1g'  , 'parallel.join1'    , NULL   ,'log to join branch 1'),
      ('parallel.process'    , 'parallel.gateway1' , 'parallel.gateway2' , 'two'  ,'parallel to next gateway'),
      ('parallel.process'    , 'parallel.gateway2' , 'parallel.log2b1g'  , 'three','parallel to log branch 2 gate 1'),
      ('parallel.process'    , 'parallel.gateway2' , 'parallel.task2b2g' , 'four' ,'parallel to task of branch 2'),
      ('parallel.process'    , 'parallel.log2b1g'  , 'parallel.join2'    , NULL   ,'task to join branch 2'),
      ('parallel.process'    , 'parallel.task2b2g' , 'parallel.join2'    , NULL   ,'task to join branch 2'),
      ('parallel.process'    , 'parallel.join2'    , 'parallel.join1'    , NULL   ,'branch 2 back to branch 1'),
      ('parallel.process'    , 'parallel.join1'    , 'end'               , NULL   ,'branch 1 to end');
  END;
$$;
COMMIT;
