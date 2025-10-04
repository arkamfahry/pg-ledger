CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION gen_ulid()
    RETURNS text
AS
$$
DECLARE
    -- Crockford's Base32 (lowercase)
    encoding  bytea = '0123456789abcdefghjkmnpqrstvwxyz';
    timestamp bytea = E'\\000\\000\\000\\000\\000\\000';
    output    text  = '';
    unix_time bigint;
    ulid      bytea;
BEGIN
    unix_time = (extract(epoch from clock_timestamp()) * 1000)::bigint;
    timestamp = set_byte(timestamp, 0, (unix_time >> 40)::bit(8)::integer);
    timestamp = set_byte(timestamp, 1, (unix_time >> 32)::bit(8)::integer);
    timestamp = set_byte(timestamp, 2, (unix_time >> 24)::bit(8)::integer);
    timestamp = set_byte(timestamp, 3, (unix_time >> 16)::bit(8)::integer);
    timestamp = set_byte(timestamp, 4, (unix_time >> 8)::bit(8)::integer);
    timestamp = set_byte(timestamp, 5, unix_time::bit(8)::integer);

    -- 10 entropy bytes
    ulid = timestamp || gen_random_bytes(10);

    -- Encode the timestamp
    output = output || chr(get_byte(encoding, (get_byte(ulid, 0) & 224) >> 5));
    output = output || chr(get_byte(encoding, (get_byte(ulid, 0) & 31)));
    output = output || chr(get_byte(encoding, (get_byte(ulid, 1) & 248) >> 3));
    output = output || chr(get_byte(encoding, ((get_byte(ulid, 1) & 7) << 2) | ((get_byte(ulid, 2) & 192) >> 6)));
    output = output || chr(get_byte(encoding, (get_byte(ulid, 2) & 62) >> 1));
    output = output || chr(get_byte(encoding, ((get_byte(ulid, 2) & 1) << 4) | ((get_byte(ulid, 3) & 240) >> 4)));
    output = output || chr(get_byte(encoding, ((get_byte(ulid, 3) & 15) << 1) | ((get_byte(ulid, 4) & 128) >> 7)));
    output = output || chr(get_byte(encoding, (get_byte(ulid, 4) & 124) >> 2));
    output = output || chr(get_byte(encoding, ((get_byte(ulid, 4) & 3) << 3) | ((get_byte(ulid, 5) & 224) >> 5)));
    output = output || chr(get_byte(encoding, (get_byte(ulid, 5) & 31)));

    -- Encode the entropy
    output = output || chr(get_byte(encoding, (get_byte(ulid, 6) & 248) >> 3));
    output = output || chr(get_byte(encoding, ((get_byte(ulid, 6) & 7) << 2) | ((get_byte(ulid, 7) & 192) >> 6)));
    output = output || chr(get_byte(encoding, (get_byte(ulid, 7) & 62) >> 1));
    output = output || chr(get_byte(encoding, ((get_byte(ulid, 7) & 1) << 4) | ((get_byte(ulid, 8) & 240) >> 4)));
    output = output || chr(get_byte(encoding, ((get_byte(ulid, 8) & 15) << 1) | ((get_byte(ulid, 9) & 128) >> 7)));
    output = output || chr(get_byte(encoding, (get_byte(ulid, 9) & 124) >> 2));
    output = output || chr(get_byte(encoding, ((get_byte(ulid, 9) & 3) << 3) | ((get_byte(ulid, 10) & 224) >> 5)));
    output = output || chr(get_byte(encoding, (get_byte(ulid, 10) & 31)));
    output = output || chr(get_byte(encoding, (get_byte(ulid, 11) & 248) >> 3));
    output = output || chr(get_byte(encoding, ((get_byte(ulid, 11) & 7) << 2) | ((get_byte(ulid, 12) & 192) >> 6)));
    output = output || chr(get_byte(encoding, (get_byte(ulid, 12) & 62) >> 1));
    output = output || chr(get_byte(encoding, ((get_byte(ulid, 12) & 1) << 4) | ((get_byte(ulid, 13) & 240) >> 4)));
    output = output || chr(get_byte(encoding, ((get_byte(ulid, 13) & 15) << 1) | ((get_byte(ulid, 14) & 128) >> 7)));
    output = output || chr(get_byte(encoding, (get_byte(ulid, 14) & 124) >> 2));
    output = output || chr(get_byte(encoding, ((get_byte(ulid, 14) & 3) << 3) | ((get_byte(ulid, 15) & 224) >> 5)));
    output = output || chr(get_byte(encoding, (get_byte(ulid, 15) & 31)));

    RETURN output;
END
$$
    LANGUAGE plpgsql
    VOLATILE;


CREATE TABLE accounts
(
    id                     TEXT                 DEFAULT gen_ulid() PRIMARY KEY,
    name                   TEXT        NOT NULL,
    currency               TEXT        NOT NULL,
    balance                NUMERIC     NOT NULL DEFAULT 0,
    version                BIGINT      NOT NULL DEFAULT 0,
    allow_negative_balance BOOLEAN     NOT NULL,
    allow_positive_balance BOOLEAN     NOT NULL,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE transfers
(
    id              TEXT                 DEFAULT gen_ulid() PRIMARY KEY,
    from_account_id TEXT        NOT NULL REFERENCES accounts (id),
    to_account_id   TEXT        NOT NULL REFERENCES accounts (id),
    amount          NUMERIC     NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (amount > 0 AND from_account_id != to_account_id)
);

CREATE INDEX ON transfers (from_account_id);
CREATE INDEX ON transfers (to_account_id);

CREATE TABLE entries
(
    id                       TEXT                 DEFAULT gen_ulid() PRIMARY KEY,
    account_id               TEXT        NOT NULL REFERENCES accounts (id),
    transfer_id              TEXT        NOT NULL REFERENCES transfers (id),
    amount                   NUMERIC     NOT NULL,
    account_previous_balance NUMERIC     NOT NULL,
    account_current_balance  NUMERIC     NOT NULL,
    account_version          BIGINT      NOT NULL,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ON entries (account_id);
CREATE INDEX ON entries (transfer_id);

CREATE OR REPLACE FUNCTION add_account(
    name_param TEXT,
    currency_param TEXT)
    RETURNS TABLE
            (
                id       BIGINT,
                name     TEXT,
                currency TEXT,
                balance  NUMERIC
            )
AS
$$
BEGIN
    RETURN QUERY
        INSERT INTO accounts (name, currency, allow_negative_balance, allow_positive_balance, created_at, updated_at)
            VALUES (name_param, currency_param, TRUE, TRUE, now(), now())
            RETURNING accounts.id, accounts.name, accounts.currency, accounts.balance;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_account(
    name_param TEXT,
    currency_param TEXT,
    allow_negative_balance_param BOOLEAN DEFAULT TRUE,
    allow_positive_balance_param BOOLEAN DEFAULT TRUE
)
    RETURNS TABLE
            (
                id                     TEXT,
                name                   TEXT,
                currency               TEXT,
                balance                NUMERIC,
                version                BIGINT,
                allow_negative_balance BOOLEAN,
                allow_positive_balance BOOLEAN,
                created_at             TIMESTAMPTZ,
                updated_at             TIMESTAMPTZ
            )
AS
$$
BEGIN
    RETURN QUERY
        INSERT INTO accounts (name, currency, allow_negative_balance, allow_positive_balance, created_at, updated_at)
            VALUES (name_param, currency_param, allow_negative_balance_param, allow_positive_balance_param, now(),
                    now())
            RETURNING accounts.id, accounts.name, accounts.currency, accounts.balance, accounts.version,
                accounts.allow_negative_balance, accounts.allow_positive_balance,
                accounts.created_at, accounts.updated_at;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_account(id_param TEXT)
    RETURNS TABLE
            (
                id                     TEXT,
                name                   TEXT,
                currency               TEXT,
                balance                NUMERIC,
                version                BIGINT,
                allow_negative_balance BOOLEAN,
                allow_positive_balance BOOLEAN,
                created_at             TIMESTAMPTZ,
                updated_at             TIMESTAMPTZ
            )
AS
$$
BEGIN
    RETURN QUERY
        SELECT accounts.id,
               accounts.name,
               accounts.currency,
               accounts.balance,
               accounts.version,
               accounts.allow_negative_balance,
               accounts.allow_positive_balance,
               accounts.created_at,
               accounts.updated_at
        FROM accounts
        WHERE accounts.id = id_param;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_transfer(id_param TEXT)
    RETURNS TABLE
            (
                id              TEXT,
                from_account_id TEXT,
                to_account_id   TEXT,
                amount          NUMERIC,
                created_at      TIMESTAMPTZ
            )
AS
$$
BEGIN
    RETURN QUERY
        SELECT t.id,
               t.from_account_id,
               t.to_account_id,
               t.amount,
               t.created_at
        FROM transfers t
        WHERE t.id = id_param;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION check_account_balance_constraints(account RECORD) RETURNS VOID AS
$$
BEGIN
    IF NOT account.allow_negative_balance AND (account.balance < 0) THEN
        RAISE EXCEPTION 'account (id=%, name=%) does not allow negative balance', account.id, account.name;
    END IF;

    IF NOT account.allow_positive_balance AND (account.balance > 0) THEN
        RAISE EXCEPTION 'account (id=%, name=%) does not allow positive balance', account.id, account.name;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION create_transfer(from_account_id_param TEXT, to_account_id_param TEXT,
                                           amount_param NUMERIC)
    RETURNS TABLE
            (
                id              TEXT,
                from_account_id TEXT,
                to_account_id   TEXT,
                amount          NUMERIC,
                created_at      TIMESTAMPTZ
            )
AS
$$
DECLARE
    transfer_id  TEXT;
    account_ids  TEXT[] := ARRAY [
        LEAST(from_account_id_param, to_account_id_param),
        GREATEST(from_account_id_param, to_account_id_param)
        ];
    from_account RECORD;
    to_account   RECORD;
BEGIN
    IF amount_param <= 0 THEN
        RAISE EXCEPTION 'amount (%) must be positive', amount_param;
    END IF;

    IF from_account_id_param = to_account_id_param THEN
        RAISE EXCEPTION 'cannot transfer to the same account (id=%)', from_account_id_param;
    END IF;

    PERFORM accounts.id
    FROM accounts
    WHERE accounts.id = account_ids[1]
        FOR UPDATE;

    PERFORM accounts.id
    FROM accounts
    WHERE accounts.id = account_ids[2]
        FOR UPDATE;

    UPDATE accounts
    SET balance    = balance - amount_param,
        version    = version + 1,
        updated_at = now()
    WHERE accounts.id = from_account_id_param
    RETURNING * INTO from_account;

    PERFORM check_account_balance_constraints(from_account);

    UPDATE accounts
    SET balance    = balance + amount_param,
        version    = version + 1,
        updated_at = now()
    WHERE accounts.id = to_account_id_param
    RETURNING * INTO to_account;

    PERFORM check_account_balance_constraints(to_account);

    IF from_account.currency != to_account.currency THEN
        RAISE EXCEPTION 'cannot transfer between different currencies (% and %)', from_account.currency, to_account.currency;
    END IF;

    INSERT INTO transfers (from_account_id, to_account_id, amount, created_at)
    VALUES (from_account_id_param, to_account_id_param, amount_param, now())
    RETURNING transfers.id INTO transfer_id;

    INSERT INTO entries (account_id, transfer_id, amount, account_previous_balance, account_current_balance,
                         account_version, created_at)
    VALUES (from_account_id_param, transfer_id, -amount_param, from_account.balance + amount_param,
            from_account.balance, from_account.version, now());

    INSERT INTO entries (account_id, transfer_id, amount, account_previous_balance, account_current_balance,
                         account_version, created_at)
    VALUES (to_account_id_param, transfer_id, amount_param, to_account.balance - amount_param, to_account.balance,
            to_account.version, now());

    RETURN QUERY
        SELECT t.id,
               t.from_account_id,
               t.to_account_id,
               t.amount,
               t.created_at
        FROM transfers t
        WHERE t.id = transfer_id;
END;
$$ LANGUAGE plpgsql;
