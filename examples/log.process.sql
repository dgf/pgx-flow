SET search_path TO flow, public;
BEGIN TRANSACTION;
DO $$
  BEGIN

    INSERT INTO process (uri, description) VALUES
      ('log.process', 'a sequential process with one synchronous log activity');

    INSERT INTO activity (uri, proc, description, config) VALUES
      ('log.log', 'log', 'log actual token data', '{"level":"INFO","message":"synchronous log call"}');

    INSERT INTO flow (process, source, target, description) VALUES
      ('log.process', 'start', 'log.log', 'start to log'),
      ('log.process', 'log.log', 'end', 'log to end');
  END;
$$;
COMMIT;

