SET search_path TO flow, public;

BEGIN TRANSACTION;
DO $$
  DECLARE
    acts int;
    pid uuid;
  BEGIN

    BEGIN
      RAISE INFO 'SPEC: sequential process execution';
    END;

    BEGIN
      RAISE INFO 'TEST: process with one synchronous log activity';
      INSERT INTO input (process, data)
      VALUES ('log.example', '{"check":"sequential log flow"}')
      RETURNING uid INTO pid;

      -- assert three acts in one branch
      SELECT count(*) INTO acts FROM state
      WHERE instance = pid AND branch = 0 AND await = false;
      IF acts = 3 THEN
        RAISE INFO 'OK: process % ends synchronous', pid;
      ELSE
        RAISE 'unexpected execution result of log process %', pid;
      END IF;
    END;

  END;
$$;
ROLLBACK;
