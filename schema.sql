CREATE SCHEMA flow;
SET search_path TO flow, public;

CREATE TABLE process (
  id          serial    PRIMARY KEY,
  created     timestamp DEFAULT now(),
  uri         text      NOT NULL,
  description text,
  UNIQUE (uri)
);

CREATE TABLE instance (
  id          serial    PRIMARY KEY,
  created     timestamp DEFAULT now(),
  uid         uuid      DEFAULT uuid_generate_v4(),
  process     text      NOT NULL REFERENCES process(uri),
  UNIQUE (uid)
);

CREATE TABLE activity (
  id          serial    PRIMARY KEY,
  created     timestamp DEFAULT now(),
  uri         text      NOT NULL,
  func        text      NOT NULL,
  async       boolean   DEFAULT false,
  config      json      NOT NULL,
  description text,
  UNIQUE (uri)
);

CREATE TABLE flow (
  id          serial    PRIMARY KEY,
  created     timestamp DEFAULT now(),
  process     text      NOT NULL REFERENCES process(uri),
  source      text      REFERENCES activity(uri),
  target      text      REFERENCES activity(uri),
  label       text,  -- optional label of a branch
  condition   text,  -- optional SQL function
  description text,
  UNIQUE (process, source, target)
);

CREATE TABLE branch (
  created     timestamp DEFAULT now(),
  instance    uuid      NOT NULL REFERENCES instance(uid),
  num         int       NOT NULL,
  parent      int       CHECK (NOT NULL OR num = 0), -- branch 0 has no parent
  gates       int       NOT NULL DEFAULT 1,
  label       text,  -- optional label of the flow
  PRIMARY KEY (instance, num) -- only accept branch increments
);

CREATE TABLE state (
  id          serial    PRIMARY KEY,
  created     timestamp DEFAULT now(),
  instance    uuid      NOT NULL,
  branch      int       NOT NULL,
  activity    text      NOT NULL REFERENCES activity(uri),
  await       boolean   DEFAULT false,
  data        json      NOT NULL,
  UNIQUE (instance, activity, branch), -- prevent endless loop
  FOREIGN KEY (instance, branch) REFERENCES branch (instance, num)
);

CREATE TABLE error (
  id          serial    PRIMARY KEY,
  created     timestamp DEFAULT now(),
  instance    uuid      NOT NULL REFERENCES instance(uid),
  activity    text      NOT NULL REFERENCES activity(uri),
  data        json      NOT NULL
);

CREATE TYPE status AS ENUM ('new', 'open', 'done');

CREATE TABLE call (
  id          serial    PRIMARY KEY,
  created     timestamp DEFAULT now(),
  uid         uuid      DEFAULT uuid_generate_v4(),
  instance    uuid      NOT NULL REFERENCES instance(uid),
  activity    text      NOT NULL REFERENCES activity(uri),
  status      status    NOT NULL DEFAULT 'new',
  func        text      NOT NULL,
  request     json      NOT NULL,
  response    json      CHECK (status <> 'done' OR NOT NULL),
  UNIQUE(uid)
);

CREATE TABLE task (
  id          serial    PRIMARY KEY,
  created     timestamp DEFAULT now(),
  instance    uuid      NOT NULL REFERENCES instance(uid),
  activity    text      NOT NULL REFERENCES activity(uri),
  assignee    text,  -- optional assigned user
  agroup      text,  -- optional assigned group
  status      status    NOT NULL DEFAULT 'new',
  subject     text      NOT NULL,
  data        json
);

CREATE TABLE input (
  id          serial    PRIMARY KEY,
  created     timestamp DEFAULT now(),
  uid         uuid      DEFAULT uuid_generate_v4(),
  process     text      NOT NULL REFERENCES process(uri),
  data        json      NOT NULL,
  UNIQUE (uid)
);

CREATE TABLE log (
  id          serial    PRIMARY KEY,
  created     timestamp DEFAULT now(),
  instance    uuid      NOT NULL REFERENCES instance(uid),
  activity    text      NOT NULL REFERENCES activity(uri),
  level       text      NOT NULL,
  message     text      NOT NULL,
  data        json      NOT NULL
);

CREATE VIEW flows AS (
  SELECT i.uid, i.process
  , b.num, b.parent
  , s.activity, s.await, s.data
  FROM instance i
  JOIN state s ON s.instance = i.uid
  JOIN branch b ON b.instance = i.uid AND b.num = s.branch
);
