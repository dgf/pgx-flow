-- INSERT INTO flow.input (process, data) VALUES ('http.process', '{"url":"http://httpbin.org/get"}');
SET search_path TO flow, public;
BEGIN TRANSACTION;
DO $$
  BEGIN

    INSERT INTO process (uri, description) VALUES
      ('http.process', 'a sequential process with one asynchronous http activity');

    INSERT INTO activity (uri, proc, async, description, config) VALUES
      ('http.get', 'http', true, 'GET HTTP', '{"method":"get"}');

    INSERT INTO flow (process, source, target, description) VALUES
      ('http.process', 'start', 'http.get', 'start to http'),
      ('http.process', 'http.get', 'end', 'http to end');
  END;
$$;
COMMIT;

