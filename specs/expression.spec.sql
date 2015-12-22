SET search_path TO flow, public;

BEGIN TRANSACTION;
DO $$
  DECLARE
    test json;
    expr text;
    act boolean;
  BEGIN

    BEGIN
      RAISE INFO 'SPEC: expression validation';
      test := '{"check":{"b":true, "n":1, "s":"foo"}}';
    END;

    BEGIN
      RAISE INFO 'TEST: equals';

      IF evaluate('check.b = true', test) THEN
        RAISE INFO 'OK: boolean equals true';
      ELSE
        RAISE 'boolean not equals true';
      END IF;

      IF NOT evaluate('check.b = false', test) THEN
        RAISE INFO 'OK: boolean is not false';
      ELSE
        RAISE 'boolean equals false';
      END IF;

      IF evaluate('check.n = 1', test) THEN
        RAISE INFO 'OK: number equals one';
      ELSE
        RAISE 'number not equals one';
      END IF;

      IF NOT evaluate('check.n = 0', test) THEN
        RAISE INFO 'OK: number not equals zero';
      ELSE
        RAISE 'number equals zero';
      END IF;

      IF evaluate('check.s = foo', test) THEN
        RAISE INFO 'OK: string equals foo';
      ELSE
        RAISE 'string not equals foo';
      END IF;

      IF NOT evaluate('check.s = bar', test) THEN
        RAISE INFO 'OK: string not equals bar';
      ELSE
        RAISE 'string equals bar';
      END IF;

    END;

    BEGIN
      RAISE INFO 'TEST: not equals';

      IF NOT evaluate('check.b != true', test) THEN
        RAISE INFO 'OK: boolean equals true';
      ELSE
        RAISE 'boolean not equals true';
      END IF;

      IF evaluate('check.b != false', test) THEN
        RAISE INFO 'OK: boolean is not false';
      ELSE
        RAISE 'boolean equals false';
      END IF;

      IF NOT evaluate('check.n != 1', test) THEN
        RAISE INFO 'OK: number equals one';
      ELSE
        RAISE 'number not equals one';
      END IF;

      IF evaluate('check.n != 0', test) THEN
        RAISE INFO 'OK: number not equals zero';
      ELSE
        RAISE 'number equals zero';
      END IF;

      IF NOT evaluate('check.s != foo', test) THEN
        RAISE INFO 'OK: string equals foo';
      ELSE
        RAISE 'string not equals foo';
      END IF;

      IF evaluate('check.s != bar', test) THEN
        RAISE INFO 'OK: string not equals bar';
      ELSE
        RAISE 'string equals bar';
      END IF;

    END;

    BEGIN
      RAISE INFO 'TEST: less than';

      IF evaluate('check.n < 2', test) THEN
        RAISE INFO 'OK: 1 < 2 = true';
      ELSE
        RAISE '1 < 2 = false';
      END IF;

      IF NOT evaluate('check.n < 1', test) THEN
        RAISE INFO 'OK: 1 < 1 = false';
      ELSE
        RAISE '1 < 1 = true';
      END IF;

      IF NOT evaluate('check.n < 0', test) THEN
        RAISE INFO 'OK: 1 < 0 = false';
      ELSE
        RAISE '1 < 0 = true';
      END IF;

      IF evaluate('check.s < foz', test) THEN
        RAISE INFO 'OK: foo < foz = true';
      ELSE
        RAISE 'foo < foz = false';
      END IF;

      IF NOT evaluate('check.s < bar', test) THEN
        RAISE INFO 'OK: foo < bar = false';
      ELSE
        RAISE 'foo < bar = true';
      END IF;

    END;

    BEGIN
      RAISE INFO 'TEST: greater than';

      IF evaluate('check.n > 0', test) THEN
        RAISE INFO 'OK: 1 > 0 = true';
      ELSE
        RAISE '1 > 0 = false';
      END IF;

      IF NOT evaluate('check.n > 1', test) THEN
        RAISE INFO 'OK: 1 > 1 = false';
      ELSE
        RAISE '1 > 1 = true';
      END IF;

      IF NOT evaluate('check.n > 2', test) THEN
        RAISE INFO 'OK: 1 > 2 = false';
      ELSE
        RAISE '1 > 2 = true';
      END IF;

      IF evaluate('check.s > bar', test) THEN
        RAISE INFO 'OK: foo > bar  = true';
      ELSE
        RAISE 'foo > bar = false';
      END IF;

      IF NOT evaluate('check.s > foz', test) THEN
        RAISE INFO 'OK: foo > foz = false';
      ELSE
        RAISE 'foo > foz = true';
      END IF;

    END;
  END;
$$;
ROLLBACK;
