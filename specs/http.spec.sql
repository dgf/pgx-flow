SET search_path TO flow, public;

BEGIN TRANSACTION;
DO $$
  DECLARE
    acts int;
    pid uuid;
  BEGIN

    BEGIN
      RAISE INFO 'SPEC: http activity call';
    END;

    BEGIN
      RAISE INFO 'TEST: create a http based process';
      INSERT INTO input (process, data)
      VALUES ('http.example', '{"url":"https://httpbin.org/get"}')
      RETURNING uid INTO pid;

      -- assert waiting activity
      SELECT count(*) INTO acts FROM state
      WHERE instance = pid AND await = true AND activity = 'get';
      IF acts = 1 THEN
        RAISE INFO 'OK: process % awaits activity result', pid;
      ELSE
        RAISE 'unexpected execution result of http process %', pid;
      END IF;

      -- assert new call request
      SELECT count(*) INTO acts FROM call
      WHERE instance = pid AND status = 'new';
      IF acts = 1 THEN
        RAISE INFO 'OK: process % has one new call request', pid;
      ELSE
        RAISE 'no open call request in process % found', pid;
      END IF;

    END;

    BEGIN
      RAISE INFO 'TEST: mock http call response';
      UPDATE call SET status = 'done', response = '{"code":"200","body":"HTTP content"}'
      WHERE instance = pid;

      -- assert synchronous process ending
      SELECT count(*) INTO acts FROM state
      WHERE instance = pid AND await = false;
      IF acts = 3 THEN
        RAISE INFO 'OK: process % ends synchronous', pid;
      ELSE
        RAISE 'unexpected execution result of http process %', pid;
      END IF;
    END;

  END;
$$;
ROLLBACK;
