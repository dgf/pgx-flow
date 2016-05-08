SET search_path TO flow, public;

-- starts a flow for each new input record
CREATE FUNCTION start_flow()
  RETURNS TRIGGER AS $$
  BEGIN
    SET search_path TO flow, public; -- TODO set path of all application schemas
    IF TG_TABLE_NAME != 'input' OR TG_OP != 'INSERT' OR TG_WHEN != 'AFTER' THEN
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
  AFTER INSERT ON input
  FOR EACH ROW
  EXECUTE PROCEDURE start_flow();

-- calls an activity for each new state record
CREATE FUNCTION call_activity()
  RETURNS TRIGGER AS $$
  DECLARE
    a activity;
    f flow;
    fn func;
    p process;
  BEGIN
    IF TG_TABLE_NAME != 'state' OR TG_OP != 'INSERT' OR TG_WHEN != 'AFTER' THEN
      PERFORM log_error(NEW.instance, NEW.activity, '{"message":"invalid activity trigger call"}');
    ELSE
      IF NEW.await THEN
        SELECT * INTO a FROM activity
        JOIN instance ON instance.process = activity.process
        WHERE instance.uid = NEW.instance AND name = NEW.activity;
        EXECUTE 'SELECT * FROM ' || quote_ident(a.func) || '($1, $2, $3, $4)'
        USING NEW.instance, NEW.activity, a.config, NEW.data;
      END IF;
      SELECT * FROM func WHERE name = a.func INTO fn;
      IF NOT fn.async THEN -- synchronous update triggers the close function
        UPDATE state SET await = false -- TODO merge data result
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
    IF TG_TABLE_NAME != 'state' OR TG_OP != 'UPDATE' OR TG_WHEN != 'AFTER' THEN
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

      -- end => output
      IF NEW.activity = 'end' THEN
        INSERT INTO output (instance, process, data)
        VALUES(NEW.instance, NEW.process, NEW.data);

      --  keep the flow
      ELSEIF cardinality(steps) > 0 THEN

        -- remember branch count
        UPDATE branch SET gates = cardinality(steps)
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
              IF cardinality(acts) = 1 THEN
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
              IF (parent IS NULL OR parent.gates = 1) AND cardinality(acts) = 1 THEN
                wait := false;
                bn := NEW.branch;
                data := acts[1].data;

              -- check finished previous count => next on parent branch
              ELSE
                IF parent.gates = cardinality(acts) THEN
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
              IF cardinality(steps) > 1 THEN
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

-- start sub process
CREATE FUNCTION start_sub()
  RETURNS TRIGGER AS $$
  BEGIN
    SET search_path TO flow, public; -- TODO set path of all application schemas
    IF TG_WHEN != 'AFTER' OR TG_OP != 'INSERT' OR TG_TABLE_NAME != 'sub' THEN
      PERFORM log_error(NEW.uid, 'call', '{"message":"invalid sub flow trigger call"}');
    ELSE
      INSERT INTO input(uid, process, data) VALUES (NEW.uid, NEW.process, NEW.data);
    END IF;
    RETURN NEW;
  END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sub_start
  AFTER INSERT ON sub
  FOR EACH ROW
  EXECUTE PROCEDURE start_sub();

-- finish sub process
CREATE FUNCTION finish_sub()
  RETURNS TRIGGER AS $$
  DECLARE
    s sub;
  BEGIN
    SET search_path TO flow, public; -- TODO set path of all application schemas
    IF TG_WHEN != 'AFTER' OR TG_OP != 'INSERT' OR TG_TABLE_NAME != 'output' THEN
      PERFORM log_error(NEW.uid, 'call', '{"message":"invalid sub flow finish call"}');
    ELSE
      SELECT * INTO s FROM sub WHERE uid = NEW.instance;
      IF s IS NOT NULL THEN
        UPDATE state SET await = false, data = NEW.data -- TODO merge data
        WHERE instance = s.parent AND await = true; -- TODO join and filter activity
      END IF;
    END IF;
    RETURN NEW;
  END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sub_finish
  AFTER INSERT ON output
  FOR EACH ROW
  EXECUTE PROCEDURE finish_sub();

