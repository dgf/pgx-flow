-- INSERT INTO flow.input (process, data) VALUES ('mail.process', '{"subject":"read me"}');
SET search_path TO flow, public;
BEGIN TRANSACTION;
DO $$
  BEGIN

    INSERT INTO process (uri, description) VALUES
      ('mail.example', 'a sequential process with one asynchronous mail activity');

    INSERT INTO activity (process, uri, func, async, description, config) VALUES
      ('mail.example', 'start', 'log', false, 'log start', '{"level":"INFO","message":"start mail example process"}'),
      ('mail.example', 'send', 'mail', true, 'send a mail', '{"to":"root@localhost","subject":"read me"}'),
      ('mail.example', 'end', 'log', false, 'log end', '{"level":"INFO","message":"end mail example process"}');

    INSERT INTO flow (process, source, target, description) VALUES
      ('mail.example', 'start', 'send', 'start to mail'),
      ('mail.example', 'send', 'end', 'mail to end');
  END;
$$;
COMMIT;
