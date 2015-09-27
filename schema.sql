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
  puid        uuid      NOT NULL, -- DEFAULT uuid_generate_v4()
  process     text      NOT NULL REFERENCES process(uri),
  UNIQUE (puid)
);

CREATE TABLE activity (
  id          serial    PRIMARY KEY,
  created     timestamp DEFAULT now(),
  uri         text      NOT NULL,
  proc        text      NOT NULL,
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
  puid        uuid      NOT NULL REFERENCES instance(puid),
  num         int       NOT NULL,
  parent      int       CHECK (NOT NULL OR num = 0), -- branch 0 has no parent
  gates       int       NOT NULL DEFAULT 1,
  label       text,  -- optional label
  PRIMARY KEY (puid, num) -- only accept branch increments
);

CREATE TABLE state (
  id          serial    PRIMARY KEY,
  created     timestamp DEFAULT now(),
  puid        uuid      NOT NULL,
  branch      int       NOT NULL,
  activity    text      NOT NULL REFERENCES activity(uri),
  await       boolean   DEFAULT false,
  data        json      NOT NULL,
  UNIQUE (puid, activity, branch), -- prefend endless loop
  FOREIGN KEY (puid, branch) REFERENCES branch (puid, num)
);

CREATE TABLE error (
  id          serial    PRIMARY KEY,
  created     timestamp DEFAULT now(),
  puid        uuid      NOT NULL REFERENCES instance(puid),
  activity    text      NOT NULL REFERENCES activity(uri),
  data        json      NOT NULL
);

CREATE TYPE status AS ENUM ('new', 'open', 'done');

CREATE TABLE call (
  id          serial    PRIMARY KEY,
  created     timestamp DEFAULT now(),
  cuid        uuid      DEFAULT uuid_generate_v4(),
  puid        uuid      NOT NULL REFERENCES instance(puid),
  activity    text      NOT NULL REFERENCES activity(uri),
  status      status    NOT NULL DEFAULT 'new',
  proc        text      NOT NULL,
  request     json      NOT NULL,
  response    json,
  UNIQUE(cuid)
);

CREATE TABLE task (
  id          serial    PRIMARY KEY,
  created     timestamp DEFAULT now(),
  puid        uuid      NOT NULL REFERENCES instance(puid),
  activity    text      NOT NULL REFERENCES activity(uri),
  assignee    text      ,
  agroup      text      ,
  status      status    NOT NULL DEFAULT 'new',
  subject     text      NOT NULL,
  data        json
);

CREATE TABLE input (
  id          serial    PRIMARY KEY,
  created     timestamp DEFAULT now(),
  puid        uuid      DEFAULT uuid_generate_v4(),
  process     text      NOT NULL REFERENCES process(uri),
  data        json      NOT NULL,
  UNIQUE (puid)
);

CREATE TABLE log (
  id          serial    PRIMARY KEY,
  created     timestamp DEFAULT now(),
  puid        uuid      NOT NULL REFERENCES instance(puid),
  activity    text      NOT NULL REFERENCES activity(uri),
  level       text      NOT NULL,
  message     text      NOT NULL,
  data        json      NOT NULL
);

CREATE VIEW flows AS (
  SELECT i.puid, i.process
  , b.num, b.parent
  , s.activity, s.await, s.data
  FROM instance i
  JOIN state s ON s.puid = i.puid
  JOIN branch b ON b.puid = i.puid AND b.num = s.branch
);

