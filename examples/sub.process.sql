SET search_path TO flow, public;
BEGIN TRANSACTION;
DO $$
  BEGIN

    INSERT INTO process (uri, description) VALUES
      ('sub.example', 'a sequential process with one sub process activity');

    INSERT INTO activity (process, name, func, description, config) VALUES
      ('sub.example', 'start', 'log', 'log start data'  , '{"level":"INFO","message":"start sub.example process"}'),
      ('sub.example', 'call' , 'sub', 'call sub process', '{"process":"log.example"}'),
      ('sub.example', 'end'  , 'log', 'log end data'    , '{"level":"INFO","message":"end sub.example process"}');

    INSERT INTO flow (process, source, target, description) VALUES
      ('sub.example', 'start', 'call', 'start to sub'),
      ('sub.example', 'call' , 'end' , 'sub to end');
  END;
$$;
COMMIT;
