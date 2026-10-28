\set ON_ERROR_STOP on
-- 01_build_core.sql
-- Строит слой core из raw. Идемпотентен: можно запускать повторно.
-- Принципы:
--   * Грейн каждой таблицы = грейн исходной (ни одной потерянной/склеенной строки),
--     строки core == строки raw (это проверяет 02_checks.sql).
--   * Только типизация и чистка (TRIM, пустая строка -> NULL). Бизнес-правил здесь нет:
--     «что считать выручкой» живёт в запросах 03_answers, а не в данных.
--   * Покупатель = customer_unique_id (customer_id меняется от заказа к заказу).
--   * Пустая категория -> 'unknown', иначе INNER JOIN молча теряет выручку.

BEGIN;

CREATE SCHEMA IF NOT EXISTS core;

DROP VIEW  IF EXISTS core.order_totals CASCADE;
DROP TABLE IF EXISTS core.order_reviews  CASCADE;
DROP TABLE IF EXISTS core.order_payments CASCADE;
DROP TABLE IF EXISTS core.order_items    CASCADE;
DROP TABLE IF EXISTS core.orders         CASCADE;
DROP TABLE IF EXISTS core.products       CASCADE;
DROP TABLE IF EXISTS core.categories     CASCADE;
DROP TABLE IF EXISTS core.sellers        CASCADE;
DROP TABLE IF EXISTS core.customers      CASCADE;

-- ---------------------------------------------------------------- categories
-- Справочник: все категории из переводов + все, что реально встречаются в товарах
-- (в т.ч. без перевода) + 'unknown' для товаров без категории.
CREATE TABLE core.categories (
    category_code    text PRIMARY KEY,
    category_name_en text NOT NULL
);

INSERT INTO core.categories (category_code, category_name_en)
SELECT c.code, COALESCE(NULLIF(TRIM(t.product_category_name_english), ''), c.code)
FROM (
    SELECT TRIM(product_category_name) AS code
    FROM raw.products
    WHERE NULLIF(TRIM(product_category_name), '') IS NOT NULL
    UNION
    SELECT TRIM(product_category_name)
    FROM raw.product_category_translation
    WHERE NULLIF(TRIM(product_category_name), '') IS NOT NULL
) c
LEFT JOIN raw.product_category_translation t
       ON TRIM(t.product_category_name) = c.code;

INSERT INTO core.categories (category_code, category_name_en)
VALUES ('unknown', 'unknown');

-- ----------------------------------------------------------------- customers
-- Одна строка = один customer_id (запись покупателя в заказе).
-- Человек = customer_unique_id.
CREATE TABLE core.customers (
    customer_id        text PRIMARY KEY,
    customer_unique_id text NOT NULL,
    zip_prefix         text,
    city               text,
    state              text
);
CREATE INDEX ON core.customers (customer_unique_id);

INSERT INTO core.customers
SELECT TRIM(customer_id),
       TRIM(customer_unique_id),
       NULLIF(TRIM(customer_zip_code_prefix), ''),
       NULLIF(TRIM(customer_city), ''),
       NULLIF(UPPER(TRIM(customer_state)), '')
FROM raw.customers;

-- ------------------------------------------------------------------- sellers
CREATE TABLE core.sellers (
    seller_id  text PRIMARY KEY,
    zip_prefix text,
    city       text,
    state      text
);

INSERT INTO core.sellers
SELECT TRIM(seller_id),
       NULLIF(TRIM(seller_zip_code_prefix), ''),
       NULLIF(TRIM(seller_city), ''),
       NULLIF(UPPER(TRIM(seller_state)), '')
FROM raw.sellers;

-- ------------------------------------------------------------------ products
CREATE TABLE core.products (
    product_id         text PRIMARY KEY,
    category_code      text NOT NULL REFERENCES core.categories (category_code),
    name_length        integer,
    description_length integer,
    photos_qty         integer,
    weight_g           numeric(12,2),
    length_cm          numeric(10,2),
    height_cm          numeric(10,2),
    width_cm           numeric(10,2)
);

INSERT INTO core.products
SELECT TRIM(product_id),
       COALESCE(NULLIF(TRIM(product_category_name), ''), 'unknown'),
       NULLIF(TRIM(product_name_lenght), '')::integer,
       NULLIF(TRIM(product_description_lenght), '')::integer,
       NULLIF(TRIM(product_photos_qty), '')::integer,
       NULLIF(TRIM(product_weight_g), '')::numeric,
       NULLIF(TRIM(product_length_cm), '')::numeric,
       NULLIF(TRIM(product_height_cm), '')::numeric,
       NULLIF(TRIM(product_width_cm), '')::numeric
FROM raw.products;

-- ------------------------------------------------------------------- orders
-- Грейн: заказ. Статус сохраняем как есть — фильтр «доставлен» делают запросы.
CREATE TABLE core.orders (
    order_id              text PRIMARY KEY,
    customer_id           text NOT NULL REFERENCES core.customers (customer_id),
    order_status          text NOT NULL,
    purchase_at           timestamp NOT NULL,
    approved_at           timestamp,
    delivered_carrier_at  timestamp,
    delivered_customer_at timestamp,
    estimated_delivery_at timestamp
);
CREATE INDEX ON core.orders (customer_id);
CREATE INDEX ON core.orders (purchase_at);
CREATE INDEX ON core.orders (order_status);

INSERT INTO core.orders
SELECT TRIM(order_id),
       TRIM(customer_id),
       LOWER(TRIM(order_status)),
       NULLIF(TRIM(order_purchase_timestamp), '')::timestamp,
       NULLIF(TRIM(order_approved_at), '')::timestamp,
       NULLIF(TRIM(order_delivered_carrier_date), '')::timestamp,
       NULLIF(TRIM(order_delivered_customer_date), '')::timestamp,
       NULLIF(TRIM(order_estimated_delivery_date), '')::timestamp
FROM raw.orders;

-- -------------------------------------------------------------- order_items
-- Грейн: позиция (1 строка = 1 единица товара). Продавец — на уровне позиции.
CREATE TABLE core.order_items (
    order_id            text    NOT NULL REFERENCES core.orders (order_id),
    order_item_id       integer NOT NULL,
    product_id          text    NOT NULL REFERENCES core.products (product_id),
    seller_id           text    NOT NULL REFERENCES core.sellers (seller_id),
    shipping_limit_at   timestamp,
    price               numeric(12,2) NOT NULL,
    freight_value       numeric(12,2) NOT NULL,
    PRIMARY KEY (order_id, order_item_id)
);
CREATE INDEX ON core.order_items (seller_id);
CREATE INDEX ON core.order_items (product_id);

INSERT INTO core.order_items
SELECT TRIM(order_id),
       NULLIF(TRIM(order_item_id), '')::integer,
       TRIM(product_id),
       TRIM(seller_id),
       NULLIF(TRIM(shipping_limit_date), '')::timestamp,
       NULLIF(TRIM(price), '')::numeric,
       COALESCE(NULLIF(TRIM(freight_value), '')::numeric, 0)
FROM raw.order_items;

-- ----------------------------------------------------------- order_payments
-- Грейн: платёж (у заказа их может быть несколько).
CREATE TABLE core.order_payments (
    order_id             text    NOT NULL REFERENCES core.orders (order_id),
    payment_sequential   integer NOT NULL,
    payment_type         text,
    payment_installments integer,
    payment_value        numeric(12,2),
    PRIMARY KEY (order_id, payment_sequential)
);

INSERT INTO core.order_payments
SELECT TRIM(order_id),
       NULLIF(TRIM(payment_sequential), '')::integer,
       NULLIF(LOWER(TRIM(payment_type)), ''),
       NULLIF(TRIM(payment_installments), '')::integer,
       NULLIF(TRIM(payment_value), '')::numeric
FROM raw.order_payments;

-- ------------------------------------------------------------ order_reviews
-- review_id в исходнике НЕ уникален (один отзыв может относиться к нескольким
-- заказам), поэтому свой суррогатный ключ review_row_id.
CREATE TABLE core.order_reviews (
    review_row_id  bigint PRIMARY KEY,
    review_id      text NOT NULL,
    order_id       text NOT NULL REFERENCES core.orders (order_id),
    review_score   smallint,
    comment_title  text,
    comment_text   text,
    created_at     timestamp,
    answered_at    timestamp
);
CREATE INDEX ON core.order_reviews (order_id);
CREATE INDEX ON core.order_reviews (review_id);

INSERT INTO core.order_reviews
SELECT ROW_NUMBER() OVER (
           ORDER BY TRIM(review_id), TRIM(order_id),
                    NULLIF(TRIM(review_answer_timestamp), ''),
                    NULLIF(TRIM(review_creation_date), '')
       ),
       TRIM(review_id),
       TRIM(order_id),
       NULLIF(TRIM(review_score), '')::smallint,
       NULLIF(TRIM(review_comment_title), ''),
       NULLIF(TRIM(review_comment_message), ''),
       NULLIF(TRIM(review_creation_date), '')::timestamp,
       NULLIF(TRIM(review_answer_timestamp), '')::timestamp
FROM raw.order_reviews;

-- ------------------------------------------------------------- order_totals
-- Витрина-помощник на грейне ЗАКАЗА (1 строка = 1 заказ, включая заказы без позиций).
-- Позиции и платежи агрегируются по отдельности, чтобы не размножать строки
-- (items x payments даёт fan-out и завышает суммы).
CREATE VIEW core.order_totals AS
WITH it AS (
    SELECT order_id,
           COUNT(*)                    AS lines,
           SUM(price)                  AS items_value,
           SUM(freight_value)          AS freight_value,
           COUNT(DISTINCT seller_id)   AS sellers
    FROM core.order_items
    GROUP BY order_id
), pay AS (
    SELECT order_id,
           SUM(payment_value) AS paid_value
    FROM core.order_payments
    GROUP BY order_id
)
SELECT o.order_id,
       o.customer_id,
       o.order_status,
       o.purchase_at,
       COALESCE(it.lines, 0)          AS lines,
       COALESCE(it.items_value, 0)    AS items_value,
       COALESCE(it.freight_value, 0)  AS freight_value,
       COALESCE(it.items_value, 0) + COALESCE(it.freight_value, 0) AS order_value,
       COALESCE(it.sellers, 0)        AS sellers,
       pay.paid_value
FROM core.orders o
LEFT JOIN it  ON it.order_id  = o.order_id
LEFT JOIN pay ON pay.order_id = o.order_id;

COMMIT;

ANALYZE;