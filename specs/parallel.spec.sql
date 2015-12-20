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
      INSERT INTO input (process, data)
      VALUES ('parallel.example', '{"parallelize":"this"}')
      RETURNING uid INTO pid;

      -- assert waiting activity
      SELECT count(*) INTO acts FROM state
      WHERE instance = pid AND await = true AND activity = 'task2b2g';
      IF acts = 1 THEN
        RAISE INFO 'OK: process % awaits activity result', pid;
      ELSE
        RAISE 'unexpected execution result of parallel process %', pid;
      END IF;

      -- assert first gateway1 branches on root
      SELECT gates INTO acts FROM branch
      WHERE instance = pid AND num = 0;
      IF acts = 2 THEN
        RAISE INFO 'OK: process % branches parallel at gateway 1', pid;
      ELSE
        RAISE 'root branch of parallel process % has % child branches', pid, acts;
      END IF;

      -- assert second gateway2 branches
      SELECT b.gates INTO acts FROM state s
      JOIN branch b ON b.num = s.branch
      WHERE b.instance = pid AND s.instance = pid AND s.activity = 'gateway2';
      IF acts = 2 THEN
        RAISE INFO 'OK: process % branches parallel at gateway 2', pid;
      ELSE
        RAISE 'gateway2 of parallel process % has % child branches', pid, acts;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: confirm asynchronous task';
      UPDATE task SET status = 'done', data = '{"confirm":"done"}'
      WHERE instance = pid AND activity = 'task2b2g';

      -- assert join1 on root branch
      SELECT count(*) INTO acts FROM state
      WHERE instance = pid AND branch = 0 AND activity = 'join1';
      IF acts = 1 THEN
        RAISE INFO 'OK: process % joins gateway 1 on root branch', pid;
      ELSE
        RAISE 'join1 of parallel process % joins not on root branch', pid;
      END IF;

      -- assert join2 on gateway2 branch
      SELECT branch INTO acts FROM state
      WHERE instance = pid AND activity = 'gateway2';
      SELECT count(*) INTO acts FROM state
      WHERE instance = pid AND branch = acts AND activity = 'join2';
      IF acts = 1 THEN
        RAISE INFO 'OK: process % joins gateway 2 branch', pid;
      ELSE
        RAISE 'join2 of parallel process % joins not on gateway2 branch', pid;
      END IF;

      -- assert synchronous process ending
      SELECT count(*) INTO acts FROM state
      WHERE instance = pid AND await = false;
      IF acts = 9 THEN
        RAISE INFO 'OK: process % ends synchronous', pid;
      ELSE
        RAISE 'unexpected execution result of parallel process %', pid;
      END IF;
    END;

  END;
$$;
ROLLBACK;
