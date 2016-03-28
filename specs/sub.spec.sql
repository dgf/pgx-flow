SET search_path TO flow, public;

BEGIN TRANSACTION;
DO $$
  DECLARE
    acts int;
    pid uuid;
  BEGIN

    BEGIN
      RAISE INFO 'SPEC: sub process execution';
    END;

    BEGIN
      RAISE INFO 'TEST: process with one sub process activity';
      INSERT INTO input (process, data)
      VALUES ('sub.example', '{"check":"sub log flow"}')
      RETURNING uid INTO pid;

      -- assert three parent acts in one branch
      SELECT count(*) INTO acts FROM state
      WHERE instance = pid AND branch = 0 AND await = false;
      IF acts = 3 THEN
        RAISE INFO 'OK: parent process % ends synchronous', pid;
      ELSE
        RAISE 'unexpected execution result of parent process %', pid;
      END IF;

      -- reference sub process instance
      SELECT uid FROM sub WHERE parent = pid INTO pid;

      -- assert three sub acts in one branch
      SELECT count(*) INTO acts FROM state
      WHERE instance = pid AND branch = 0 AND await = false;
      IF acts = 3 THEN
        RAISE INFO 'OK: sub process % ends synchronous', pid;
      ELSE
        RAISE 'unexpected execution result of sub process %', pid;
      END IF;
    END;

  END;
$$;
ROLLBACK;

