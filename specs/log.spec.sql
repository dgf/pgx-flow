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
      INSERT INTO input (process, data) VALUES ('log.process', '{"check":"sequential log flow"}') RETURNING puid INTO pid;

      -- assert three acts in one branch
      SELECT count(*) FROM state WHERE puid = pid AND branch = 0 AND await = false INTO acts;
      IF acts = 3 THEN
        RAISE INFO 'OK: process % ends synchronous', pid;
      ELSE
        RAISE 'unexpected execution result of log process %', pid;
      END IF;
    END;

  END;
$$;
ROLLBACK;

