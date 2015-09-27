SET search_path TO flow, public;

INSERT INTO activity (uri, proc, description, config) VALUES
('start', 'log', 'logs flow start', '{"level":"INFO","message":"flow start"}'),
('end', 'log', 'logs flow end', '{"level":"INFO","message":"flow end"}');

-- notfifies async call execution
CREATE FUNCTION call()
  RETURNS TRIGGER AS $$
  BEGIN
    PERFORM pg_notify('call', json_build_object('proc', NEW.proc, 'cuid', NEW.cuid)::text);
    RETURN NEW;
  END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER call_proc
  AFTER INSERT ON call
  FOR EACH ROW
  EXECUTE PROCEDURE call();

-- updates flow state for each finished call
CREATE FUNCTION finish_call()
  RETURNS TRIGGER AS $$
  DECLARE
    s flow.state;
  BEGIN
    SET search_path TO flow, public; -- TODO set path of all application schemas
    IF TG_TABLE_NAME != 'call' OR TG_OP != 'UPDATE' THEN
      PERFORM log_error(NEW.puid, NEW.activity, '{"message":"invalid finish call"}');
    ELSE
      IF NEW.status = 'done' THEN
        SELECT * FROM state WHERE puid = NEW.puid AND activity = NEW.activity AND await = true INTO s;
        IF s IS NULL THEN
          PERFORM log_error(NEW.puid, NEW.activity, '{"message":"activity call state not found"}');
        ELSE
          UPDATE state SET await = false, data = NEW.response WHERE puid = NEW.puid AND activity = NEW.activity;
        END IF;
      END IF;
    END IF;
    RETURN NEW;
 END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER call_done
  AFTER UPDATE ON call
  FOR EACH ROW
  EXECUTE PROCEDURE finish_call();

-- delegates mail activity call
CREATE FUNCTION mail(puid uuid, activity text, config json, data json)
  RETURNS json AS $$
  BEGIN
    INSERT INTO call (puid, activity, proc, request) VALUES
      (puid, activity, 'mail', json_build_object('to', config->'to', 'subject', data->'subject'));
    RETURN data;
  END;
$$ LANGUAGE plpgsql;

-- delegates http activity call
CREATE FUNCTION http(puid uuid, activity text, config json, data json)
  RETURNS json AS $$
  BEGIN
    INSERT INTO call (puid, activity, proc, request) VALUES
      (puid, activity, 'http', json_build_object('method', config->'method', 'url', data->'url'));
    RETURN data;
  END;
$$ LANGUAGE plpgsql;

-- creates a new log record with actual flow data
CREATE FUNCTION log(puid uuid, activity text, config json, data json)
  RETURNS json AS $$
  BEGIN
    INSERT INTO log (puid, activity, level, message, data) VALUES
      (puid, activity, config->'level', config->'message', data);
    RETURN data;
  END;
$$LANGUAGE plpgsql;

-- creates a new task record
CREATE FUNCTION task(puid uuid, activity text, config json, data json)
  RETURNS json AS $$
  BEGIN
    INSERT INTO task (puid, activity, agroup, subject, data) VALUES
      (puid, activity, config->'group', config->'subject', data);
    RETURN data;
  END;
$$ LANGUAGE plpgsql;

-- updates flow state for each finished task
CREATE FUNCTION finish_task()
  RETURNS TRIGGER AS $$
  DECLARE
    sId int;
  BEGIN
    SET search_path TO flow, public; -- TODO set path of all application schemas
    IF TG_TABLE_NAME != 'task' OR TG_OP != 'UPDATE' THEN
      PERFORM log_error(NEW.puid, NEW.activity, '{"message":"invalid task finish call"}');
    ELSE
      IF NEW.status = 'done' THEN
        UPDATE state SET await = false, data = NEW.data
          WHERE puid = NEW.puid AND activity = NEW.activity AND await = true
          RETURNING id INTO sId;
        IF sId IS NULL THEN
          PERFORM log_error(NEW.puid, NEW.activity, '{"message":"task process state not found"}');
        END IF;
      END IF;
    END IF;
    RETURN NEW;
 END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER task_done
  AFTER UPDATE ON task
  FOR EACH ROW
  EXECUTE PROCEDURE finish_task();

