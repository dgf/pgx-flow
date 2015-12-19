-- INSERT INTO flow.input (process, data) VALUES ('mail.process', '{"subject":"read me"}');
SET search_path TO flow, public;
BEGIN TRANSACTION;
DO $$
  BEGIN

    INSERT INTO process (uri, description) VALUES
      ('mail.process', 'a sequential process with one asynchronous mail activity');

    INSERT INTO activity (uri, func, async, description, config) VALUES
      ('mail.send', 'mail', true, 'send a mail', '{"to":"root@localhost","subject":"read me"}');

    INSERT INTO flow (process, source, target, description) VALUES
      ('mail.process', 'start', 'mail.send', 'start to mail'),
      ('mail.process', 'mail.send', 'end', 'mail to end');
  END;
$$;
COMMIT;
