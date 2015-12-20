SET search_path TO flow, public;
BEGIN TRANSACTION;
DO $$
  BEGIN

    INSERT INTO process (uri, description) VALUES
      ('log.example', 'a sequential process with one synchronous log activity');

    INSERT INTO activity (process, uri, func, description, config) VALUES
      ('log.example', 'start', 'log', 'log start data', '{"level":"INFO","message":"start log example process"}'),
      ('log.example', 'call', 'log', 'log actual token data', '{"level":"INFO","message":"synchronous log call"}'),
      ('log.example', 'end', 'log', 'log end data', '{"level":"INFO","message":"end log example process"}');

    INSERT INTO flow (process, source, target, description) VALUES
      ('log.example', 'start', 'call', 'start to log'),
      ('log.example', 'call', 'end', 'log to end');
  END;
$$;
COMMIT;
