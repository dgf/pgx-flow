SET search_path TO flow, public;
BEGIN TRANSACTION;
DO $$
  BEGIN

    INSERT INTO process (uri, description) VALUES
      ('task.process', 'a sequential process with one asynchronous task activity');

    INSERT INTO activity (uri, func, async, description, config) VALUES
      ('task.create', 'task', true, 'create a task', '{"group":"staff","subject":"confirm me"}');

    INSERT INTO flow (process, source, target, description) VALUES
      ('task.process', 'start', 'task.create', 'start to task'),
      ('task.process', 'task.create', 'end', 'task to end');
  END;
$$;
COMMIT;
