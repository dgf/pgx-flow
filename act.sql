SET search_path TO flow, public;

-- call sub process activity
CREATE FUNCTION sub(instance uuid, activity text, config json, data json)
  RETURNS void AS $$
  INSERT INTO sub (parent, process, data)
  VALUES (instance, config->>'process', data);
$$ LANGUAGE SQL;

-- notifies async call execution
CREATE FUNCTION call()
  RETURNS TRIGGER AS $$
  BEGIN
    PERFORM pg_notify('call', json_build_object('uid', NEW.uid, 'func', NEW.func)::text);
    RETURN NEW;
  END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER call_func
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
      PERFORM log_error(NEW.instance, NEW.activity, '{"message":"invalid finish call"}');
    ELSE
      IF NEW.status = 'done' THEN
        SELECT * INTO s FROM state
        WHERE instance = NEW.instance AND activity = NEW.activity AND await = true;
        IF s IS NULL THEN
          PERFORM log_error(NEW.instance, NEW.activity, '{"message":"activity call state not found"}');
        ELSE
          UPDATE state SET await = false, data = NEW.response -- TODO merge data
          WHERE instance = NEW.instance AND activity = NEW.activity;
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
CREATE FUNCTION mail(instance uuid, activity text, config json, data json)
  RETURNS json AS $$
  DECLARE request json;
  BEGIN
    request := json_build_object('to', config->'to', 'subject', data->'subject');
    INSERT INTO call (instance, process, activity, func, request)
    VALUES (instance, process_uri(instance), activity, 'mail', request);
    RETURN request;
  END;
$$ LANGUAGE plpgsql;

-- delegates http activity call
CREATE FUNCTION http(instance uuid, activity text, config json, data json)
  RETURNS json AS $$
  DECLARE request json;
  BEGIN
    request := json_build_object('method', config->'method', 'url', data->'url');
    INSERT INTO call (instance, process, activity, func, request)
    VALUES (instance, process_uri(instance), activity, 'http', request);
    RETURN request;
  END;
$$ LANGUAGE plpgsql;

-- creates a new log record with actual flow data
CREATE FUNCTION log(instance uuid, activity text, config json, data json)
  RETURNS json AS $$
  BEGIN
    INSERT INTO log (instance, process, activity, level, message, data)
    VALUES (instance, process_uri(instance), activity, config->'level', config->'message', data);
    RETURN data;
  END;
$$LANGUAGE plpgsql;

-- creates a new task record
CREATE FUNCTION task(instance uuid, activity text, config json, data json)
  RETURNS json AS $$
  BEGIN
    INSERT INTO task (instance, process, activity, agroup, subject, data)
    VALUES (instance, process_uri(instance), activity, config->'group', config->'subject', data);
    RETURN data;
  END;
$$ LANGUAGE plpgsql;

-- updates flow state for each finished task
CREATE FUNCTION finish_task()
  RETURNS TRIGGER AS $$
  DECLARE
    s state;
  BEGIN
    SET search_path TO flow, public; -- TODO set path of all application schemas
    IF TG_TABLE_NAME != 'task' OR TG_OP != 'UPDATE' THEN
      PERFORM log_error(NEW.instance, NEW.activity, '{"message":"invalid task finish call"}');
    ELSE
      IF NEW.status = 'done' THEN
        UPDATE state SET await = false, data = NEW.data
        WHERE instance = NEW.instance AND activity = NEW.activity AND await = true
        RETURNING * INTO s;
        IF s IS NULL THEN
          PERFORM log_error(NEW.instance, NEW.activity, '{"message":"task process state not found"}');
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
