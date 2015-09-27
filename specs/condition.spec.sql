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
      INSERT INTO input (process, data) VALUES ('condition.process', '{"check":1}') RETURNING puid INTO pid;

      -- assert direct flow from start to end on root
      SELECT count(*) FROM state WHERE puid = pid AND branch = 0 INTO acts;
      IF acts = 5 THEN
        RAISE INFO 'OK: process % ends sequential on the root branch', pid;
      ELSE
        RAISE 'unexpected execution result of conditional process %', pid;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: check 2 with two child branches';
      INSERT INTO input (process, data) VALUES ('condition.process', '{"check":2}') RETURNING puid INTO pid;

      -- assert branch count
      SELECT count(*) FROM branch WHERE puid = pid AND parent = 0 INTO acts;
      IF acts = 2 THEN
        RAISE INFO 'OK: process % branches two times', pid;
      ELSE
        RAISE 'conditional process % has % branches', pid, acts;
      END IF;

      -- assert activity count
      SELECT count(*) FROM state WHERE puid = pid AND await = false INTO acts;
      IF acts = 8 THEN
        RAISE INFO 'OK: process % ends sequential', pid;
      ELSE
        RAISE 'unexpected execution result of conditional process %', pid;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: check 3 with two logs';
      INSERT INTO input (process, data) VALUES ('condition.process', '{"check":3}') RETURNING puid INTO pid;

      -- assert direct flow from start to end on root
      SELECT count(*) FROM state WHERE puid = pid AND branch = 0 INTO acts;
      IF acts = 6 THEN
        RAISE INFO 'OK: process % ends sequential on the root branch', pid;
      ELSE
        RAISE 'unexpected execution result of conditional process %', pid;
      END IF;
    END;
  END;
$$;
ROLLBACK;

