SET search_path TO flow, public;

BEGIN TRANSACTION;
DO $$
  DECLARE
    acts int;
    pid uuid;
  BEGIN

    BEGIN
      RAISE INFO 'SPEC: asynchronous activity execution';
    END;

    BEGIN
      RAISE INFO 'TEST: start process with one asynchronous task activity';
      INSERT INTO input (process, data) VALUES ('task.process', '{"confirm":"this"}') RETURNING puid INTO pid;

      -- assert waiting activity
      SELECT count(*) FROM state WHERE puid = pid AND await = true AND activity = 'task.create' INTO acts;
      IF acts = 1 THEN
        RAISE INFO 'OK: process % awaits activity result', pid;
      ELSE
        RAISE 'unexpected execution result of task process %', pid;
      END IF;

      -- assert new task
      SELECT count(*) FROM task WHERE puid = pid AND status = 'new' INTO acts;
      IF acts = 1 THEN
        RAISE INFO 'OK: process % has one open task', pid;
      ELSE
        RAISE 'no open task in process % found', pid;
      END IF;
    END;

    BEGIN
      RAISE INFO 'TEST: confirm asynchronous task';
      UPDATE task SET status = 'done', data = '{"confirm":"done"}' WHERE puid = pid AND activity = 'task.create';

      -- assert synchronous process ending
      SELECT count(*) FROM state WHERE puid = pid AND await = false INTO acts;
      IF acts = 3 THEN
        RAISE INFO 'OK: process % ends synchronous', pid;
      ELSE
        RAISE 'unexpected execution result of task process %', pid;
      END IF;
    END;

  END;
$$;
ROLLBACK;

