SET search_path TO flow, public;

CREATE FUNCTION attribute(document xml, element text, attribute text, namespaces text[])
  RETURNS text AS $$
  DECLARE x xml[];
  BEGIN
    SELECT xpath('//' || element || '/@' || attribute, document, namespaces) INTO x;
    IF array_length(x, 1) = 0 OR x[1] IS NULL THEN
      RAISE 'element "%" without "%" attribute: %', element, attribute, document;
    END IF;
    RETURN x[1];
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION exist(document xml, element text, attribute text, namespaces text[])
  RETURNS boolean AS $$
  DECLARE x xml[];
  BEGIN
    SELECT xpath('//' || element || '/@' || attribute, document, namespaces) INTO x;
    IF array_length(x, 1) = 0 OR x[1] IS NULL THEN
      RETURN false;
    ELSE
      RETURN true;
    END IF;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION xpath_count(document xml, element text, namespaces text[])
  RETURNS int AS $$
  DECLARE x xml[];
  BEGIN
    SELECT xpath('//' || element, document, namespaces) INTO x;
    RETURN array_length(x, 1);
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION xpath_text(document xml, element text, namespaces text[])
  RETURNS text AS $$
  DECLARE x xml[];
  BEGIN
    SELECT xpath('//' || element || '/text()', document, namespaces) INTO x;
    IF array_length(x, 1) = 1 THEN
      RETURN x[1];
    ELSE
      RETURN null;
    END IF;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION xml_decode(INOUT value text) AS $$
  BEGIN
    value := replace(value, '&gt;', '>');
    value := replace(value, '&lt;', '<');
    value := replace(value, '&amp;', '&');
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION import(bpmn xml)
  RETURNS flow.process AS $$
  DECLARE
    ns text[] = ARRAY[
      ARRAY['bpmn', 'http://www.omg.org/spec/BPMN/20100524/MODEL'],
      ARRAY['camunda', 'http://camunda.org/schema/1.0/bpmn']];
    p flow.process;
    c json;
    x xml;
    xp xml[];
    len int;
    id text;
    name text;
    func text;
    async boolean;
    source text;
    target text;
  BEGIN
    -- fix search path of absolute call
    SET search_path TO flow, public;

    -- create process
    SELECT xpath('//bpmn:process', bpmn, ns) INTO xp;
    len := array_length(xp, 1);
    IF len = 0 THEN
      RAISE 'definition without process';
    ELSEIF len > 1 THEN
      RAISE 'only one process supported, found %', len;
    ELSE
      id := attribute(xp[1], 'bpmn:process', 'id', ns);
      name := xml_decode(attribute(xp[1], 'bpmn:process', 'name', ns));
      INSERT INTO flow.process (uri, description)
      VALUES (id, name)
      RETURNING * INTO p;
    END IF;

    -- create start event
    SELECT xpath('//bpmn:startEvent', bpmn, ns) INTO xp;
    len := array_length(xp, 1);
    IF len = 0 THEN
      RAISE 'process without start event';
    ELSEIF len > 1 THEN
      RAISE 'only one start event supported, found %', len;
    ELSE
      c := json_build_object('level', 'INFO', 'message', 'start ' || p.uri || '"}');
      INSERT INTO activity (process, uri, func, description, config)
      VALUES (p.uri, 'start', 'log', 'log start', c);
    END IF;

    -- create end event
    SELECT xpath('//bpmn:endEvent', bpmn, ns) INTO xp;
    len := array_length(xp, 1);
    IF len = 0 THEN
      RAISE 'process without end event';
    ELSEIF len > 1 THEN
      RAISE 'only one end event supported';
    ELSE
      c := json_build_object('level', 'INFO', 'message', 'end ' || p.uri || '"}');
      INSERT INTO activity (process, uri, func, description, config)
      VALUES (p.uri, 'end', 'log', 'log end', c);
    END IF;

    -- create service task activities
    SELECT xpath('//bpmn:serviceTask', bpmn, ns) INTO xp;
    FOREACH x IN ARRAY xp
    LOOP
      id := attribute(x, 'bpmn:serviceTask', 'id', ns);
      name := xml_decode(attribute(x, 'bpmn:serviceTask', 'name', ns));
      c := xml_decode(xpath_text(x, 'bpmn:documentation', ns));
      IF exist(x, 'bpmn:serviceTask', 'camunda:delegateExpression', ns) THEN
        async := false;
        func := attribute(x, 'bpmn:serviceTask', 'camunda:delegateExpression', ns);
      ELSEIF exist(x, 'bpmn:serviceTask', 'camunda:topic', ns) THEN
        async := true;
        func := attribute(x, 'bpmn:serviceTask', 'camunda:topic', ns);
      ELSE
        RAISE 'no function reference for service task "%" found', id;
      END IF;
      INSERT INTO activity (process, uri, func, async, description, config)
      VALUES (p.uri, id, func, async, name, c);
    END LOOP;

    -- create user task activities
    SELECT xpath('//bpmn:userTask', bpmn, ns) INTO xp;
    FOREACH x IN ARRAY xp
    LOOP
      id := attribute(x, 'bpmn:userTask', 'id', ns);
      name := xml_decode(attribute(x, 'bpmn:userTask', 'name', ns));
      c := xml_decode(xpath_text(x, 'bpmn:documentation', ns));
      INSERT INTO activity (process, uri, func, async, description, config)
      VALUES (p.uri, id, 'task', true, name, c);
    END LOOP;

    -- create parallel gateway activities
    SELECT xpath('//bpmn:parallelGateway', bpmn, ns) INTO xp;
    FOREACH x IN ARRAY xp
    LOOP
      id := attribute(x, 'bpmn:parallelGateway', 'id', ns);
      IF NOT exist(x, 'bpmn:parallelGateway', 'name', ns) THEN
        name := id;
      ELSE
        name := xml_decode(attribute(x, 'bpmn:parallelGateway', 'name', ns));
      END IF;
      IF xpath_count(x, 'bpmn:outgoing', ns) > 1 THEN
        c := json_build_object('level', 'INFO', 'message', 'parallel start ' || id || '"}');
      ELSEIF xpath_count(x, 'bpmn:incoming', ns) > 1 THEN
        c := json_build_object('level', 'INFO', 'message', 'parallel end ' || id || '"}');
      ELSE
        RAISE 'useless parallel gateway "%" found', id;
      END IF;
      INSERT INTO activity (process, uri, func, description, config)
      VALUES (p.uri, id, 'log', name, c);
    END LOOP;

    -- create parallel gateway activities
    SELECT xpath('//bpmn:exclusiveGateway', bpmn, ns) INTO xp;
    FOREACH x IN ARRAY xp
    LOOP
      id := attribute(x, 'bpmn:exclusiveGateway', 'id', ns);
      IF NOT exist(x, 'bpmn:exclusiveGateway', 'name', ns) THEN
        name := id;
      ELSE
        name := xml_decode(attribute(x, 'bpmn:exclusiveGateway', 'name', ns));
      END IF;
      IF xpath_count(x, 'bpmn:outgoing', ns) > 1 THEN
        c := json_build_object('level', 'INFO', 'message', 'exclusive start ' || id || '"}');
      ELSEIF xpath_count(x, 'bpmn:incoming', ns) > 1 THEN
        c := json_build_object('level', 'INFO', 'message', 'exclusive end ' || id || '"}');
      ELSE
        RAISE 'useless exclusive gateway "%" found', id;
      END IF;
      INSERT INTO activity (process, uri, func, description, config)
      VALUES (p.uri, id, 'log', name, c);
    END LOOP;

    -- create flow
    SELECT xpath('//bpmn:sequenceFlow', bpmn, ns) INTO xp;
    FOREACH x IN ARRAY xp
    LOOP
      source := attribute(x, 'bpmn:sequenceFlow', 'sourceRef', ns);
      target := attribute(x, 'bpmn:sequenceFlow', 'targetRef', ns);
      IF NOT exist(x, 'bpmn:sequenceFlow', 'name', ns) THEN
        name := NULL;
      ELSE
        name := xml_decode(attribute(x, 'bpmn:sequenceFlow', 'name', ns));
      END IF;
      IF xpath_count(x, 'bpmn:conditionExpression', ns) != 1 THEN
        func := NULL;
      ELSE
        func := xml_decode(xpath_text(x, 'bpmn:conditionExpression', ns));
      END IF;
      INSERT INTO flow (process, source, target, label, expression, description)
      VALUES (p.uri, source, target, name, func, NULL);
    END LOOP;

    -- return imported process
    RETURN p;
  END;
$$ LANGUAGE plpgsql;

-- starts a flow for each new input record
CREATE FUNCTION start_flow()
  RETURNS TRIGGER AS $$
  BEGIN
    SET search_path TO flow, public; -- TODO set path of all application schemas
    IF TG_TABLE_NAME != 'input' OR TG_OP != 'INSERT' THEN
      PERFORM log_error(NEW.uid, 'start', '{"message":"invalid start flow trigger call"}');
    ELSE
      INSERT INTO instance (uid, process) VALUES (NEW.uid, NEW.process);
      INSERT INTO branch (instance, num) VALUES (NEW.uid, 0);
      PERFORM log_state(NEW.uid, 'start', 0, true, NEW.data);
    END IF;
    RETURN NEW;
  END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER flow_input
  BEFORE INSERT ON input
  FOR EACH ROW
  EXECUTE PROCEDURE start_flow();

-- calls an activity for each new state record
CREATE FUNCTION call_activity()
  RETURNS TRIGGER AS $$
  DECLARE
    a activity;
    f flow;
    p process;
  BEGIN
    IF TG_TABLE_NAME != 'state' OR TG_OP != 'INSERT' THEN
      PERFORM log_error(NEW.instance, NEW.activity, '{"message":"invalid activity trigger call"}');
    ELSE
      IF NEW.await THEN
        SELECT * INTO a FROM activity
        JOIN instance ON instance.process = activity.process
        WHERE instance.uid = NEW.instance AND uri = NEW.activity;
        EXECUTE 'SELECT * FROM ' || quote_ident(a.func) || '($1, $2, $3, $4)'
        USING NEW.instance, NEW.activity, a.config, NEW.data;
      END IF;
      IF NOT a.async THEN
        -- call update to trigger to close function
        UPDATE state SET await = false
        WHERE instance = NEW.instance AND activity = NEW.activity AND await = true;
      END IF;
    END IF;
    RETURN NEW;
  END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER activity_call
  AFTER INSERT ON state
  FOR EACH ROW
  EXECUTE PROCEDURE call_activity();

-- follows the flow for each finished state record
-- by creating state entries for all following activities
--
-- supports parallel conditional flow sequence
-- by checking the optional condition function
-- and joining branches of parallel activities
CREATE FUNCTION close_activity()
  RETURNS TRIGGER AS $$
  DECLARE
    acts state[];
    a state;
    bl text;
    bn int;
    data json;
    next flow;
    parent branch;
    prev_count int;
    prev flow;
    uri text;
    steps flow[];
    checks flow[];
    wait boolean;
  BEGIN
    IF TG_TABLE_NAME != 'state' OR TG_OP != 'UPDATE' THEN
      PERFORM log_error(NEW.instance, NEW.activity, '{"message":"invalid close activity trigger call"}');
    ELSIF NEW.await = false THEN
      SELECT process INTO uri FROM instance
      WHERE uid = NEW.instance;

      -- check expression of next flow steps
      FOR next IN SELECT * FROM flow f
      WHERE f.process = uri AND f.source = NEW.activity AND f.expression IS NOT NULL
      LOOP
        checks := array_append(checks, next);
        IF evaluate(next.expression, NEW.data) THEN
          steps := array_append(steps, next);
        END IF;
      END LOOP;

      -- sequential or parallel
      IF checks IS NULL THEN
        SELECT array_agg(f) INTO steps FROM flow f
        WHERE f.process = uri AND f.source = NEW.activity AND f.expression IS NULL;

      -- conditional default flow?
      ELSEIF steps IS NULL THEN
        SELECT array_agg(f) INTO steps FROM flow f
        WHERE f.process = uri AND f.source = NEW.activity AND f.expression IS NULL;
      END IF;

      --  keep the flow
      IF array_length(steps, 1) > 0 THEN

        -- remember branch count
        UPDATE branch SET gates = array_length(steps, 1)
        WHERE instance = NEW.instance AND num = NEW.branch;

        -- check next steps
        FOREACH next IN ARRAY steps
        LOOP
          SELECT count(*) INTO prev_count FROM flow
          WHERE process = uri AND target = next.target;

          -- start activity (can't branch)
          IF prev_count = 0 THEN
            PERFORM log_state(NEW.instance, next.target, NEW.branch, true, NEW.data);

          ELSE
            wait := true;

            -- fetch state of all finished previous activities
            SELECT array_agg(s) INTO acts FROM flow f
            JOIN state s ON s.activity = f.source
            WHERE s.instance = NEW.instance AND s.await = false AND f.process = uri AND f.target = next.target;

            -- one prev => next on same branch
            IF prev_count = 1 THEN
              IF array_length(acts, 1) = 1 THEN
                wait := false;
                bn := NEW.branch;
                data := acts[1].data;
              END IF;

            -- check active parent gates count
            ELSE

              SELECT p.* INTO parent FROM branch b
              JOIN branch p ON p.num = b.parent AND p.instance = NEW.instance
              WHERE b.instance = NEW.instance AND b.num = NEW.branch;

              -- one active prev => next on same branch
              IF parent IS NULL OR parent.gates = 1 THEN
                IF array_length(acts, 1) = 1 THEN
                  wait := false;
                  bn := NEW.branch;
                  data := acts[1].data;
                END IF;

              -- check finished previous count => next on parent branch
              ELSE
                IF parent.gates = array_length(acts, 1) THEN
                  wait := false;
                  bn := parent.num;

                  -- join previous activity results into json hash
                  SELECT json_object_agg(b.label, s.data) INTO data FROM unnest(acts) s
                  JOIN branch b ON b.num = s.branch
                  WHERE b.instance = NEW.instance;
                END IF;
              END IF;
            END IF;

            -- call the next activity
            IF NOT wait THEN

              -- branch?
              IF array_length(steps, 1) > 1 THEN
                SELECT max(num) + 1 INTO bn FROM branch
                WHERE instance = NEW.instance;
                INSERT INTO branch (instance, parent, num, label)
                VALUES (NEW.instance, NEW.branch, bn, next.label);
              END IF;

              -- update state to trigger next activity
              PERFORM log_state(NEW.instance, next.target, bn, true, data);
            END IF;
          END IF;
        END LOOP;
      END IF;
    END IF;
    RETURN NEW;
  END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER activity_update
  AFTER UPDATE ON state
  FOR EACH ROW
  EXECUTE PROCEDURE close_activity();
