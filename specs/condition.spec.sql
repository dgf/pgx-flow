SET search_path TO flow, public;

BEGIN TRANSACTION;
DO $$
  DECLARE
    acts int;
    pid uuid;
  BEGIN

    BEGIN
      RAISE INFO 'SPEC: conditional flow';
    END;

    BEGIN
      RAISE INFO 'TEST: check 1 with one log';
      INSERT INTO input (process, data)
      VALUES ('condition.example', '{"check":1}')
      RETURNING uid INTO pid;

      -- assert direct flow from start to end on root
      SELECT count(*) INTO acts FROM state
      WHERE instance = pid AND branch = 0;
      IF acts = 5 THEN
        RAISE INFO 'OK: process % ends sequential on the root branch', pid;
      ELSE
        RAISE 'unexpected execution result of conditional process %', pid;
      END IF;

      -- assert log1g
      SELECT count(*) INTO acts FROM state
      WHERE instance = pid AND branch = 0 AND activity = 'log1g';
      IF acts = 1 THEN
        RAISE INFO 'OK: process % calls log1g', pid;
      ELSE
        RAISE 'unexpected execution flow of process %', pid;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: check 2 with two child branches';
      INSERT INTO input (process, data)
      VALUES ('condition.example', '{"check":2}')
      RETURNING uid INTO pid;

      -- assert branch count
      SELECT count(*) INTO acts FROM branch
      WHERE instance = pid AND parent = 0;
      IF acts = 2 THEN
        RAISE INFO 'OK: process % branches two times', pid;
      ELSE
        RAISE 'conditional process % has % branches', pid, acts;
      END IF;

      -- assert activity count
      SELECT count(*) INTO acts FROM state
      WHERE instance = pid AND await = false;
      IF acts = 8 THEN
        RAISE INFO 'OK: process % ends sequential', pid;
      ELSE
        RAISE 'unexpected execution result of conditional process %', pid;
      END IF;

      -- assert log activities
      SELECT count(*) INTO acts FROM state
      WHERE instance = pid AND branch != 0 AND activity IN ('log2g1','log2g2','log3g1','log3g2');
      IF acts = 4 THEN
        RAISE INFO 'OK: process % calls all log activities', pid;
      ELSE
        RAISE 'unexpected execution flow of process %', pid;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: check 3 with two logs';
      INSERT INTO input (process, data)
      VALUES ('condition.example', '{"check":3}')
      RETURNING uid INTO pid;

      -- assert direct flow from start to end on root
      SELECT count(*) INTO acts FROM state
      WHERE instance = pid AND branch = 0;
      IF acts = 6 THEN
        RAISE INFO 'OK: process % ends sequential on the root branch', pid;
      ELSE
        RAISE 'unexpected execution result of conditional process %', pid;
      END IF;

      -- assert log activities
      SELECT count(*) INTO acts FROM state
      WHERE instance = pid AND branch = 0 AND activity IN ('log3g1','log3g2');
      IF acts = 2 THEN
        RAISE INFO 'OK: process % calls all log activities', pid;
      ELSE
        RAISE 'unexpected execution flow of process %', pid;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: check 0 with one default log';
      INSERT INTO input (process, data)
      VALUES ('condition.example', '{"check":0}')
      RETURNING uid INTO pid;

      -- assert direct flow from start to end on root
      SELECT count(*) INTO acts FROM state
      WHERE instance = pid AND branch = 0;
      IF acts = 5 THEN
        RAISE INFO 'OK: process % ends sequential on the root branch', pid;
      ELSE
        RAISE 'unexpected execution result of conditional process %', pid;
      END IF;

      -- assert log4g1
      SELECT count(*) INTO acts FROM state
      WHERE instance = pid AND branch = 0 AND activity = 'log4g';
      IF acts = 1 THEN
        RAISE INFO 'OK: process % calls log4g', pid;
      ELSE
        RAISE 'unexpected execution flow of process %', pid;
      END IF;
    END;
  END;
$$;
ROLLBACK;
