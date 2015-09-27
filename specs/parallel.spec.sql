SET search_path TO flow, public;

BEGIN TRANSACTION;
DO $$
  DECLARE
    acts int;
    pid uuid;
  BEGIN

    BEGIN
      RAISE INFO 'SPEC: parallel execution';
    END;

    BEGIN
      RAISE INFO 'TEST: create a parallel with some logs and a waiting task';
      INSERT INTO input (process, data) VALUES ('parallel.process', '{"parallelize":"this"}') RETURNING puid INTO pid;

      -- assert waiting activity
      SELECT count(*) FROM state WHERE puid = pid AND await = true AND activity = 'parallel.task2b2g' INTO acts;
      IF acts = 1 THEN
        RAISE INFO 'OK: process % awaits activity result', pid;
      ELSE
        RAISE 'unexpected execution result of parallel process %', pid;
      END IF;

      -- assert first gateway1 branches on root
      SELECT gates FROM branch WHERE puid = pid AND num = 0 INTO acts;
      IF acts = 2 THEN
        RAISE INFO 'OK: process % branches parallel at gateway 1', pid;
      ELSE
        RAISE 'root branch of parallel process % has % child branches', pid, acts;
      END IF;

      -- assert second gateway2 branches
      SELECT b.gates FROM state s JOIN branch b ON b.num = s.branch WHERE b.puid = pid AND s.puid = pid AND s.activity = 'parallel.gateway2' INTO acts;
      IF acts = 2 THEN
        RAISE INFO 'OK: process % branches parallel at gateway 2', pid;
      ELSE
        RAISE 'gateway2 of parallel process % has % child branches', pid, acts;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: confirm asynchronous task';
      UPDATE task SET status = 'done', data = '{"confirm":"done"}' WHERE puid = pid AND activity = 'parallel.task2b2g';

      -- assert join1 on root branch
      SELECT count(*) FROM state WHERE puid = pid AND branch = 0 AND activity = 'parallel.join1' INTO acts;
      IF acts = 1 THEN
        RAISE INFO 'OK: process % joins gateway 1 on root branch', pid;
      ELSE
        RAISE 'join1 of parallel process % joins not on root branch', pid;
      END IF;

      -- assert join2 on gateway2 branch
      SELECT branch FROM state WHERE puid = pid AND activity = 'parallel.gateway2' INTO acts;
      SELECT count(*) FROM state WHERE puid = pid AND branch = acts AND activity = 'parallel.join2' INTO acts;
      IF acts = 1 THEN
        RAISE INFO 'OK: process % joins gateway 2 branch', pid;
      ELSE
        RAISE 'join2 of parallel process % joins not on gateway2 branch', pid;
      END IF;

      -- assert synchronous process ending
      SELECT count(*) FROM state WHERE puid = pid AND await = false INTO acts;
      IF acts = 9 THEN
        RAISE INFO 'OK: process % ends synchronous', pid;
      ELSE
        RAISE 'unexpected execution result of parallel process %', pid;
      END IF;
    END;

  END;
$$;
ROLLBACK;

