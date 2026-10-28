-- Capibara / Olist: reproducible analytical core
-- Run against PostgreSQL database marketplace after raw load.
-- Destructive only to the eight core tables listed below. Never changes raw.
\set ON_ERROR_STOP on
BEGIN;
CREATE SCHEMA IF NOT EXISTS core;
DROP TABLE IF EXISTS core.order_reviews, core.order_payments, core.order_items,
  core.orders, core.products, core.sellers, core.customers, core.categories CASCADE;

-- Dimension: categories; preserve untranslated Portuguese names and explicit unknown.
CREATE TABLE core.categories (
  category_code text PRIMARY KEY,
  category_name_en text NOT NULL,
  is_missing boolean NOT NULL DEFAULT false,
  translation_missing boolean NOT NULL DEFAULT false
);
INSERT INTO core.categories (category_code, category_name_en, is_missing, translation_missing)
SELECT p.product_category_name,
       COALESCE(NULLIF(t.product_category_name_english, ''), p.product_category_name),
       false,
       t.product_category_name_english IS NULL OR t.product_category_name_english = ''
FROM (SELECT DISTINCT NULLIF(BTRIM(product_category_name), '') AS product_category_name
      FROM raw.products) p
LEFT JOIN raw.product_category_translation t ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL;
INSERT INTO core.categories VALUES ('__unknown__', 'Unknown', true, false);

CREATE TABLE core.customers (
  customer_id text PRIMARY KEY,
  customer_unique_id text NOT NULL,
  zip_prefix text,
  city text,
  state text
);
INSERT INTO core.customers
SELECT customer_id, customer_unique_id, NULLIF(BTRIM(customer_zip_code_prefix),''),
       NULLIF(BTRIM(customer_city),''), NULLIF(BTRIM(customer_state),'')
FROM raw.customers;
CREATE INDEX ix_core_customers_person ON core.customers(customer_unique_id);

CREATE TABLE core.sellers (
  seller_id text PRIMARY KEY,
  zip_prefix text,
  city text,
  state text
);
INSERT INTO core.sellers
SELECT seller_id, NULLIF(BTRIM(seller_zip_code_prefix),''),
       NULLIF(BTRIM(seller_city),''), NULLIF(BTRIM(seller_state),'')
FROM raw.sellers;

CREATE TABLE core.products (
  product_id text PRIMARY KEY,
  category_code text NOT NULL REFERENCES core.categories(category_code),
  name_length integer,
  description_length integer,
  photos_qty integer,
  weight_g numeric,
  length_cm numeric,
  height_cm numeric,
  width_cm numeric
);
INSERT INTO core.products
SELECT product_id,
       COALESCE(NULLIF(BTRIM(product_category_name),''), '__unknown__'),
       NULLIF(BTRIM(product_name_lenght),'')::integer,
       NULLIF(BTRIM(product_description_lenght),'')::integer,
       NULLIF(BTRIM(product_photos_qty),'')::integer,
       NULLIF(BTRIM(product_weight_g),'')::numeric,
       NULLIF(BTRIM(product_length_cm),'')::numeric,
       NULLIF(BTRIM(product_height_cm),'')::numeric,
       NULLIF(BTRIM(product_width_cm),'')::numeric
FROM raw.products;
CREATE INDEX ix_core_products_category ON core.products(category_code);

CREATE TABLE core.orders (
  order_id text PRIMARY KEY,
  customer_id text NOT NULL REFERENCES core.customers(customer_id),
  order_status text NOT NULL,
  purchase_at timestamp,
  approved_at timestamp,
  carrier_at timestamp,
  delivered_at timestamp,
  estimated_delivery_at timestamp
);
INSERT INTO core.orders
SELECT order_id, customer_id, order_status,
       NULLIF(BTRIM(order_purchase_timestamp),'')::timestamp,
       NULLIF(BTRIM(order_approved_at),'')::timestamp,
       NULLIF(BTRIM(order_delivered_carrier_date),'')::timestamp,
       NULLIF(BTRIM(order_delivered_customer_date),'')::timestamp,
       NULLIF(BTRIM(order_estimated_delivery_date),'')::timestamp
FROM raw.orders;
CREATE INDEX ix_core_orders_status_month ON core.orders(order_status, purchase_at);
CREATE INDEX ix_core_orders_customer ON core.orders(customer_id);

CREATE TABLE core.order_items (
  order_id text NOT NULL REFERENCES core.orders(order_id),
  order_item_id integer NOT NULL,
  product_id text NOT NULL REFERENCES core.products(product_id),
  seller_id text NOT NULL REFERENCES core.sellers(seller_id),
  shipping_limit_at timestamp,
  price numeric(15,2) NOT NULL,
  freight_value numeric(15,2) NOT NULL,
  PRIMARY KEY (order_id, order_item_id)
);
INSERT INTO core.order_items
SELECT order_id, order_item_id::integer, product_id, seller_id,
       NULLIF(BTRIM(shipping_limit_date),'')::timestamp,
       price::numeric(15,2), freight_value::numeric(15,2)
FROM raw.order_items;
CREATE INDEX ix_core_items_seller ON core.order_items(seller_id);
CREATE INDEX ix_core_items_product ON core.order_items(product_id);

CREATE TABLE core.order_payments (
  order_id text NOT NULL REFERENCES core.orders(order_id),
  payment_sequential integer NOT NULL,
  payment_type text,
  payment_installments integer,
  payment_value numeric(15,2) NOT NULL,
  PRIMARY KEY (order_id, payment_sequential)
);
INSERT INTO core.order_payments
SELECT order_id, payment_sequential::integer,
       NULLIF(BTRIM(payment_type),''),
       NULLIF(BTRIM(payment_installments),'')::integer,
       payment_value::numeric(15,2)
FROM raw.order_payments;

-- review_id is NOT UNIQUE: genuine repeated IDs belong to different orders.
-- Local surrogate id models each source row; generated anew on every rebuild.
CREATE TABLE core.order_reviews (
  review_row_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  review_id text NOT NULL,
  order_id text NOT NULL REFERENCES core.orders(order_id),
  review_score integer,
  comment_title text,
  comment_message text,
  created_at timestamp,
  answered_at timestamp
);
INSERT INTO core.order_reviews (review_id, order_id, review_score, comment_title,
                               comment_message, created_at, answered_at)
SELECT review_id, order_id, NULLIF(BTRIM(review_score),'')::integer,
       NULLIF(BTRIM(review_comment_title),''), NULLIF(BTRIM(review_comment_message),''),
       NULLIF(BTRIM(review_creation_date),'')::timestamp,
       NULLIF(BTRIM(review_answer_timestamp),'')::timestamp
FROM raw.order_reviews
ORDER BY order_id, review_id, review_creation_date, review_answer_timestamp;
CREATE INDEX ix_core_reviews_order ON core.order_reviews(order_id);
CREATE INDEX ix_core_reviews_reviewid ON core.order_reviews(review_id);
COMMIT;

-- Quick row counts; expected 99441 / 112650 / 103886 / 99224 / 32951 / 3095 / 99441
SELECT 'orders' AS entity, count(*) AS rows FROM core.orders
UNION ALL SELECT 'order_items',count(*) FROM core.order_items
UNION ALL SELECT 'order_payments',count(*) FROM core.order_payments
UNION ALL SELECT 'order_reviews',count(*) FROM core.order_reviews
UNION ALL SELECT 'products',count(*) FROM core.products
UNION ALL SELECT 'sellers',count(*) FROM core.sellers
UNION ALL SELECT 'customers',count(*) FROM core.customers
UNION ALL SELECT 'categories',count(*) FROM core.categories
ORDER BY entity;
