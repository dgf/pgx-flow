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
      INSERT INTO input (process, data) VALUES ('http.process', '{"url":"https://httpbin.org/get"}') RETURNING puid INTO pid;

      -- assert waiting activity
      SELECT count(*) FROM state WHERE puid = pid AND await = true AND activity = 'http.get' INTO acts;
      IF acts = 1 THEN
        RAISE INFO 'OK: process % awaits activity result', pid;
      ELSE
        RAISE 'unexpected execution result of http process %', pid;
      END IF;

      -- assert new call request
      SELECT count(*) FROM call WHERE puid = pid AND status = 'new' INTO acts;
      IF acts = 1 THEN
        RAISE INFO 'OK: process % has one new call request', pid;
      ELSE
        RAISE 'no open call request in process % found', pid;
      END IF;

    END;

    BEGIN
      RAISE INFO 'TEST: mock mail call response';
      UPDATE call SET status = 'done', response = '{"code":"200","body":"HTTP content"}' WHERE puid = pid;

      -- assert synchronous process ending
      SELECT count(*) FROM state WHERE puid = pid AND await = false INTO acts;
      IF acts = 3 THEN
        RAISE INFO 'OK: process % ends synchronous', pid;
      ELSE
        RAISE 'unexpected execution result of http process %', pid;
      END IF;
    END;

  END;
$$;
ROLLBACK;

