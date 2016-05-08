SET search_path TO flow, public;
BEGIN TRANSACTION;
DO $$
  BEGIN

    INSERT INTO process (uri, description) VALUES
      ('task.example', 'a sequential process with one asynchronous task activity');

    INSERT INTO activity (process, name, func, description, config) VALUES
      ('task.example', 'start', 'log', 'log start', '{"level":"INFO","message":"start task example process"}'),
      ('task.example', 'confirm', 'task', 'create a task', '{"group":"staff","subject":"confirm me"}'),
      ('task.example', 'end', 'log', 'log end', '{"level":"INFO","message":"end task example process"}');

    INSERT INTO flow (process, source, target, description) VALUES
      ('task.example', 'start', 'confirm', 'start to task'),
      ('task.example', 'confirm', 'end', 'task to end');
  END;
$$;
COMMIT;
