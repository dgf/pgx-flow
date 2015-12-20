SET search_path TO flow, public;

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
    go boolean;
    next flow;
    parent branch;
    prev_count int;
    prev flow;
    uri text;
    steps flow[];
    wait boolean;
  BEGIN
    IF TG_TABLE_NAME != 'state' OR TG_OP != 'UPDATE' THEN
      PERFORM log_error(NEW.instance, NEW.activity, '{"message":"invalid close activity trigger call"}');
    ELSIF NEW.await = false THEN
      SELECT process INTO uri FROM instance
      WHERE uid = NEW.instance;

      -- check condition of next flow steps
      FOR next IN SELECT * FROM flow
      WHERE process = uri AND source = NEW.activity
      LOOP
        IF next.condition IS NULL THEN
          go := true;
        ELSE
          EXECUTE 'SELECT * FROM ' || quote_ident(next.condition) || '($1,$2,$3)' INTO go
          USING NEW.instance, NEW.activity, NEW.data;
        END IF;
        IF go THEN
          steps := array_append(steps, next);
        END IF;
      END LOOP;

      -- keep the flow
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
