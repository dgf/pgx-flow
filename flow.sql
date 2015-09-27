SET search_path TO flow, public;

CREATE FUNCTION log_error(puid uuid, activity text, data json)
  RETURNS void AS $$
  BEGIN
    INSERT INTO error (puid, activity, data) VALUES  (puid, activity, data);
    RETURN;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION log_state(puid uuid, branch int, activity text, await boolean, data json)
  RETURNS void AS $$
  BEGIN
    INSERT INTO state (puid, branch, activity, await, data) VALUES (puid, branch, activity, await, data);
    RETURN;
  END;
$$ LANGUAGE plpgsql;

-- starts a flow for each new input record
CREATE FUNCTION start_flow()
  RETURNS TRIGGER AS $$
  BEGIN
    SET search_path TO flow, public; -- TODO set path of all application schemas
    IF TG_TABLE_NAME != 'input' OR TG_OP != 'INSERT' THEN
      PERFORM log_error(NEW.puid, 'start', '{"message":"invalid start flow trigger call"}');
    ELSE
      INSERT INTO instance (puid, process) VALUES (NEW.puid, NEW.process);
      INSERT INTO branch (puid, num) VALUES (NEW.puid, 0);
      PERFORM log_state(NEW.puid, 0, 'start', true, NEW.data);
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
  BEGIN
    IF TG_TABLE_NAME != 'state' OR TG_OP != 'INSERT' THEN
      PERFORM log_error(NEW.puid, NEW.activity, '{"message":"invalid activity trigger call"}');
    ELSE
      IF NEW.await THEN
        SELECT * FROM activity WHERE uri = NEW.activity INTO a;
        EXECUTE 'SELECT * FROM '||quote_ident(a.proc)||'($1, $2, $3, $4)'
          USING NEW.puid, NEW.activity, a.config, NEW.data;
      END IF;
      IF NOT a.async THEN
        UPDATE state SET await = false WHERE id = NEW.id;
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
    puri text;
    steps flow[];
    wait boolean;
  BEGIN
    IF TG_TABLE_NAME != 'state' OR TG_OP != 'UPDATE' THEN
      PERFORM log_error(NEW.puid, NEW.activity, '{"message":"invalid close activity trigger call"}');
    ELSIF NEW.await = false THEN
      SELECT process FROM instance WHERE puid = NEW.puid INTO puri;

      -- check condition of next flow steps
      FOR next IN SELECT * FROM flow WHERE process = puri AND source = NEW.activity
      LOOP
        IF next.condition IS NULL THEN
          go := true;
        ELSE
          EXECUTE 'SELECT * FROM '||quote_ident(next.condition)||'($1,$2,$3)' USING NEW.puid, NEW.activity, NEW.data INTO go;
        END IF;
        IF go THEN
          steps := array_append(steps, next);
        END IF;
      END LOOP;

      -- keep the flow
      IF array_length(steps, 1) > 0 THEN

        -- remember branch count
        UPDATE branch SET gates = array_length(steps, 1) WHERE puid = NEW.puid AND num = NEW.branch;

        -- check next steps
        FOREACH next IN ARRAY steps
        LOOP
          SELECT count(*) FROM flow WHERE process = puri AND target = next.target INTO prev_count;

          -- start activity (can't branch)
          IF prev_count = 0 THEN
            PERFORM log_state(NEW.puid, NEW.branch, next.target, true, NEW.data);

          ELSE
            wait := true;

            -- fetch state of all finshed previous activities
            SELECT array_agg(s) FROM flow f JOIN state s ON s.activity = f.source AND s.await = false
            WHERE f.process = puri AND f.target = next.target AND s.puid = NEW.puid
            INTO acts;

            -- one prev => next on same branch
            IF prev_count = 1 THEN
              IF array_length(acts, 1) = 1 THEN
                wait := false;
                bn := NEW.branch;
                data := acts[1].data;
              END IF;

            -- check active parent gates count
            ELSE

              SELECT p.* FROM branch b
                JOIN branch p ON p.num = b.parent AND p.puid = NEW.puid
                WHERE b.puid = NEW.puid AND b.num = NEW.branch INTO parent;

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
                  SELECT json_object_agg(b.label, s.data) FROM unnest(acts) s JOIN branch b ON b.num = s.branch WHERE b.puid = NEW.puid INTO data;
                END IF;
              END IF;
            END IF;

            -- call the next activity
            IF NOT wait THEN

              -- branch?
              IF array_length(steps, 1) > 1 THEN
                SELECT max(num) + 1 FROM branch WHERE puid = NEW.puid INTO bn;
                INSERT INTO branch (puid, parent, num, label) VALUES (NEW.puid, NEW.branch, bn, next.label);
              END IF;

              -- update state to trigger next activity
              PERFORM log_state(NEW.puid, bn, next.target, true, data);
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

