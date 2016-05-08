CREATE SCHEMA flow;
SET search_path TO flow, public;

CREATE TABLE process (
  uri         text      NOT NULL,
  description text      NOT NULL,
  created     timestamp DEFAULT now(),
  PRIMARY KEY (uri)
);

CREATE TABLE func (
  name        text      NOT NULL,
  async       boolean   NOT NULL,
  description text      NOT NULL,
  created     timestamp DEFAULT now(),
  PRIMARY KEY (name)
);

CREATE TABLE activity (
  process     text      NOT NULL REFERENCES process(uri),
  name        text      NOT NULL,
  func        text      NOT NULL REFERENCES func(name),
  config      json      NOT NULL,
  description text      NOT NULL,
  created     timestamp DEFAULT now(),
  PRIMARY KEY (process, name)
);

CREATE TABLE flow (
  process     text      NOT NULL REFERENCES process(uri),
  source      text      NOT NULL,
  target      text      NOT NULL,
  label       text,  -- label of a branch
  expression  text,  -- conditional expression, see specs/expression.spec.sql
  description text,
  created     timestamp DEFAULT now(),
  PRIMARY KEY (process, source, target),
  FOREIGN KEY (source, process) REFERENCES activity(name, process),
  FOREIGN KEY (target, process) REFERENCES activity(name, process)
);

CREATE TABLE instance (
  uid         uuid      DEFAULT uuid_generate_v4(),
  process     text      NOT NULL REFERENCES process(uri),
  created     timestamp DEFAULT now(),
  PRIMARY KEY (uid)
);

CREATE TABLE branch (
  instance    uuid      NOT NULL REFERENCES instance(uid),
  num         int       NOT NULL,
  parent      int       CHECK (NOT NULL OR num = 0), -- branch 0 has no parent
  gates       int       NOT NULL DEFAULT 1,
  label       text,  -- label of the flow
  created     timestamp DEFAULT now(),
  PRIMARY KEY (instance, num) -- only accept branch increments
);

CREATE TABLE state (
  instance    uuid      NOT NULL REFERENCES instance(uid),
  process     text      NOT NULL,
  activity    text      NOT NULL,
  branch      int       NOT NULL,
  await       boolean   DEFAULT false,
  data        json      NOT NULL,
  created     timestamp DEFAULT now(),
  PRIMARY KEY (instance, activity, branch), -- prevent endless loop
  FOREIGN KEY (branch, instance) REFERENCES branch(num, instance),
  FOREIGN KEY (activity, process) REFERENCES activity(name, process)
);

CREATE TYPE status AS ENUM ('new', 'open', 'done');

CREATE TABLE call (
  uid         uuid      DEFAULT uuid_generate_v4(),
  instance    uuid      NOT NULL REFERENCES instance(uid),
  process     text      NOT NULL,
  activity    text      NOT NULL,
  status      status    NOT NULL DEFAULT 'new',
  func        text      NOT NULL REFERENCES func(name),
  request     json      NOT NULL,
  response    json      CHECK (status <> 'done' OR NOT NULL),
  created     timestamp DEFAULT now(),
  PRIMARY KEY (uid),
  FOREIGN KEY (activity, process) REFERENCES activity(name, process)
);

CREATE TABLE task (
  uid         uuid      DEFAULT uuid_generate_v4(),
  instance    uuid      NOT NULL REFERENCES instance(uid),
  process     text      NOT NULL,
  activity    text      NOT NULL,
  assignee    text,  -- optional assigned user
  agroup      text,  -- optional assigned group
  status      status    NOT NULL DEFAULT 'new',
  subject     text      NOT NULL,
  data        json,
  created     timestamp DEFAULT now(),
  PRIMARY KEY (uid),
  FOREIGN KEY (activity, process) REFERENCES activity(name, process)
);

CREATE TABLE error (
  id          serial    PRIMARY KEY,
  instance    uuid      NOT NULL REFERENCES instance(uid),
  process     text      NOT NULL,
  activity    text      NOT NULL,
  data        json      NOT NULL,
  created     timestamp DEFAULT now(),
  FOREIGN KEY (activity, process) REFERENCES activity(name, process)
);

CREATE TABLE log (
  id          serial    PRIMARY KEY,
  created     timestamp DEFAULT now(),
  instance    uuid      NOT NULL REFERENCES instance(uid),
  process     text      NOT NULL,
  activity    text      NOT NULL,
  level       text      NOT NULL,
  message     text      NOT NULL,
  data        json      NOT NULL,
  FOREIGN KEY (activity, process) REFERENCES activity(name, process)
);

CREATE TABLE input (
  uid         uuid      DEFAULT uuid_generate_v4(),
  process     text      NOT NULL REFERENCES process(uri),
  data        json      NOT NULL,
  created     timestamp DEFAULT now(),
  PRIMARY KEY (uid)
);

CREATE TABLE sub (
  uid         uuid      DEFAULT uuid_generate_v4(),
  parent      uuid      NOT NULL REFERENCES instance(uid),
  process     text      NOT NULL REFERENCES process(uri),
  data        json      NOT NULL,
  created     timestamp DEFAULT now(),
  PRIMARY KEY (uid)
);

CREATE TABLE output (
  instance    uuid      NOT NULL REFERENCES instance(uid),
  process     text      NOT NULL REFERENCES process(uri),
  data        json      NOT NULL,
  created     timestamp DEFAULT now(),
  PRIMARY KEY (instance)
);

CREATE FUNCTION process_uri(instance_uid uuid)
  RETURNS text AS $$
  DECLARE uri text;
  BEGIN
    SELECT process INTO uri FROM instance
    WHERE uid = instance_uid;
    RETURN uri;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION log_error(instance uuid, activity text, data json)
  RETURNS void AS $$
  BEGIN
    INSERT INTO error (instance, process, activity, data)
    VALUES (instance, process_uri(instance), activity, data);
    RETURN;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION log_state(instance uuid, activity text, branch int, await boolean, data json)
  RETURNS void AS $$
  BEGIN
    INSERT INTO state (instance, process, activity, branch, await, data)
    VALUES (instance, process_uri(instance), activity, branch, await, data);
    RETURN;
  END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION evaluate(expression text, data json)
  RETURNS boolean AS $$
  DECLARE
    e text[];
    p text[];
    path text;
    comp text;
    value text;
  BEGIN
    e := regexp_matches(expression, '([\w.]+)\s*([!=<>]+)\s*(\w+)');
    path := e[1];
    comp := e[2];
    value := e[3];
    p := regexp_split_to_array(path, '\.');
    IF comp = '=' THEN
      RETURN data#>>p = value;
    ELSEIF comp = '!=' THEN
      RETURN data#>>p != value;
    ELSEIF comp = '<' THEN
      RETURN data#>>p < value;
    ELSEIF comp = '>' THEN
      RETURN data#>>p > value;
    ELSE
      RAISE 'unsupported "%" comparator in expression "%"', comp, expression;
    END IF;
  END;
$$ LANGUAGE plpgsql;

CREATE VIEW flows AS (
  SELECT i.uid, i.process
  , b.num, b.parent
  , s.activity, s.await, s.data
  FROM instance i
  JOIN state s ON s.instance = i.uid
  JOIN branch b ON b.instance = i.uid AND b.num = s.branch
);
