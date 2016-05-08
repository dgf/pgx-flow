CREATE SCHEMA bpmn;
SET search_path TO bpmn, flow, public;

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

--
-- BPMN import function
--
-- bpmn:process
--   id = process.uri
--   name = process.description
--
-- bpmn:startEvent
--   'start' = activity.name
--   'log' = activity.func
--
-- bpmn:endEvent
--   'end' = activity.name
--   'log' = activity.func
--
-- bpmn:serviceTask
--   id = activity.name
--   name = activity.description
--   camunda:expression = activity.func
--   bpmn:documentation = activity.config
--
-- userTask
--   id = activity.name
--   name = activity.description
--   bpmn:documentation = activity.config
--
-- bpmn:parallelGateway and bpmn:exclusiveGateway
--   id = activity.name
--   'log' = activity.func
--   starts 1 bpmn:incoming + X bpmn:outgoing
--   ends   X bpmn:incoming + 1 bpmn:outgoing
--
-- bpmn:sequenceFlow
--   name = flow.label
--   sourceRef = flow.source
--   targetRef = flow.target
--   bpmn:conditionExpression = flow.expression
--
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
    SET search_path TO bpmn, flow, public;

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
--      result name = attribute camunda:resultVariable
    SELECT xpath('//bpmn:startEvent', bpmn, ns) INTO xp;
    len := array_length(xp, 1);
    IF len = 0 THEN
      RAISE 'process without start event';
    ELSEIF len > 1 THEN
      RAISE 'only one start event supported, found %', len;
    ELSE
      c := json_build_object('level', 'INFO', 'message', 'start ' || p.uri);
      INSERT INTO activity (process, name, func, description, config)
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
      c := json_build_object('level', 'INFO', 'message', 'end ' || p.uri);
      INSERT INTO activity (process, name, func, description, config)
      VALUES (p.uri, 'end', 'log', 'log end', c);
    END IF;

    -- create service task activities
    SELECT xpath('//bpmn:serviceTask', bpmn, ns) INTO xp;
    FOREACH x IN ARRAY xp
    LOOP
      id := attribute(x, 'bpmn:serviceTask', 'id', ns);
      name := xml_decode(attribute(x, 'bpmn:serviceTask', 'name', ns));
      c := xml_decode(xpath_text(x, 'bpmn:documentation', ns));
      IF exist(x, 'bpmn:serviceTask', 'camunda:expression', ns) THEN
        func := attribute(x, 'bpmn:serviceTask', 'camunda:expression', ns);
      ELSE
        RAISE 'no function reference for service task "%" found', id;
      END IF;
      INSERT INTO activity (process, name, func, description, config)
      VALUES (p.uri, id, func, name, c);
    END LOOP;

    -- create user task activities
    SELECT xpath('//bpmn:userTask', bpmn, ns) INTO xp;
    FOREACH x IN ARRAY xp
    LOOP
      id := attribute(x, 'bpmn:userTask', 'id', ns);
      name := xml_decode(attribute(x, 'bpmn:userTask', 'name', ns));
      c := xml_decode(xpath_text(x, 'bpmn:documentation', ns));
      INSERT INTO activity (process, name, func, description, config)
      VALUES (p.uri, id, 'task', name, c);
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
        c := json_build_object('level', 'INFO', 'message', 'parallel start ' || id);
      ELSEIF xpath_count(x, 'bpmn:incoming', ns) > 1 THEN
        c := json_build_object('level', 'INFO', 'message', 'parallel end ' || id);
      ELSE
        RAISE 'useless parallel gateway "%" found', id;
      END IF;
      INSERT INTO activity (process, name, func, description, config)
      VALUES (p.uri, id, 'log', name, c);
    END LOOP;

    -- create exclusive gateway activities
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
        c := json_build_object('level', 'INFO', 'message', 'exclusive start ' || id);
      ELSEIF xpath_count(x, 'bpmn:incoming', ns) > 1 THEN
        c := json_build_object('level', 'INFO', 'message', 'exclusive end ' || id);
      ELSE
        RAISE 'useless exclusive gateway "%" found', id;
      END IF;
      INSERT INTO activity (process, name, func, description, config)
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

