-- 1. Проверка количества строк в исходных таблицах
SELECT 'orders' AS table_name, COUNT(*) AS rows_count FROM raw.orders
UNION ALL
SELECT 'order_items', COUNT(*) FROM raw.order_items
UNION ALL
SELECT 'order_payments', COUNT(*) FROM raw.order_payments
UNION ALL
SELECT 'order_reviews', COUNT(*) FROM raw.order_reviews
UNION ALL
SELECT 'products', COUNT(*) FROM raw.products
UNION ALL
SELECT 'sellers', COUNT(*) FROM raw.sellers
UNION ALL
SELECT 'customers', COUNT(*) FROM raw.customers
UNION ALL
SELECT 'category_translation', COUNT(*) FROM raw.product_category_translation;
-- 2. Проверка уникальности order_id
SELECT
    COUNT(*) AS total_orders,
    COUNT(DISTINCT order_id) AS unique_orders,
    COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_count
FROM raw.orders;
-- 3. Проверка уникальности ключей

-- Позиции заказа: составной ключ
SELECT
    'order_items' AS table_name,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT (order_id, order_item_id)) AS unique_keys
FROM raw.order_items

UNION ALL

-- Платежи: составной ключ
SELECT
    'order_payments',
    COUNT(*),
    COUNT(DISTINCT (order_id, payment_sequential))
FROM raw.order_payments

UNION ALL

-- Товары
SELECT
    'products',
    COUNT(*),
    COUNT(DISTINCT product_id)
FROM raw.products

UNION ALL

-- Продавцы
SELECT
    'sellers',
    COUNT(*),
    COUNT(DISTINCT seller_id)
FROM raw.sellers

UNION ALL

-- Покупатели (ID записи)
SELECT
    'customers',
    COUNT(*),
    COUNT(DISTINCT customer_id)
FROM raw.customers

UNION ALL

-- Отзывы
SELECT
    'order_reviews',
    COUNT(*),
    COUNT(DISTINCT review_id)
FROM raw.order_reviews

UNION ALL

-- Переводы категорий
SELECT
    'category_translation',
    COUNT(*),
    COUNT(DISTINCT product_category_name)
FROM raw.product_category_translation;
-- 4. Повторяющиеся review_id
SELECT
    review_id,
    COUNT(*) AS rows_count,
    COUNT(DISTINCT order_id) AS distinct_orders
FROM raw.order_reviews
GROUP BY review_id
HAVING COUNT(*) > 1
ORDER BY rows_count DESC
LIMIT 15;

-- 5. Заказы с несколькими отзывами
SELECT
    COUNT(*) AS orders_with_multiple_reviews
FROM (
    SELECT order_id
    FROM raw.order_reviews
    GROUP BY order_id
    HAVING COUNT(*) > 1
) t;

-- 6. Заказы без отзывов
SELECT COUNT(*) AS orders_without_reviews
FROM raw.orders o
WHERE NOT EXISTS (
    SELECT 1
    FROM raw.order_reviews r
    WHERE r.order_id = o.order_id
);
-- 7. Статусы заказов
SELECT order_status, COUNT(*) AS orders_count
FROM raw.orders
GROUP BY order_status
ORDER BY orders_count DESC;

-- 8. Несоответствия статусов и дат доставки
SELECT
    COUNT(*) FILTER (
        WHERE order_status = 'delivered'
          AND NULLIF(TRIM(order_delivered_customer_date), '') IS NULL
    ) AS delivered_without_date,

    COUNT(*) FILTER (
        WHERE order_status <> 'delivered'
          AND NULLIF(TRIM(order_delivered_customer_date), '') IS NOT NULL
    ) AS not_delivered_with_date
FROM raw.orders;

-- 9. Пустые категории товаров
SELECT
    COUNT(*) FILTER (
        WHERE NULLIF(TRIM(product_category_name), '') IS NULL
    ) AS products_without_category
FROM raw.products;

-- 10. Категории без перевода
SELECT COUNT(DISTINCT p.product_category_name)
       AS categories_without_translation
FROM raw.products p
LEFT JOIN raw.product_category_translation t
    ON p.product_category_name = t.product_category_name
WHERE NULLIF(TRIM(p.product_category_name), '') IS NOT NULL
  AND t.product_category_name IS NULL;