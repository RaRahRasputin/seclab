-- db - one-time initialisation. Run by start.sh as the postgres superuser.
-- Creates the application account, the database and deterministic sample data.
-- (The data is synthetic: generated names and example.test addresses.)

CREATE ROLE portal LOGIN;
CREATE DATABASE portal OWNER postgres;
\connect portal

CREATE TABLE customers (
    id     integer PRIMARY KEY,
    name   text NOT NULL,
    email  text NOT NULL,
    region text NOT NULL
);

CREATE TABLE orders (
    id          integer PRIMARY KEY,
    customer_id integer NOT NULL REFERENCES customers(id),
    region      text    NOT NULL,
    amount      numeric(10,2) NOT NULL,
    placed_on   date    NOT NULL
);

INSERT INTO customers
SELECT g,
       'Customer ' || g,
       'customer' || g || '@example.test',
       (ARRAY['APAC','EMEA','AMER'])[1 + g % 3]
FROM generate_series(1, 500) AS g;

INSERT INTO orders
SELECT g,
       1 + g % 500,
       (ARRAY['APAC','EMEA','AMER'])[1 + (g % 500) % 3],
       round((20 + (g * 37) % 980)::numeric + ((g * 13) % 100)::numeric / 100, 2),
       DATE '2026-01-01' + (g % 300)
FROM generate_series(1, 20000) AS g;

-- Least privilege: the application account can read these two tables and do nothing else.
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE  ON SCHEMA public TO portal;
GRANT SELECT ON customers, orders TO portal;
