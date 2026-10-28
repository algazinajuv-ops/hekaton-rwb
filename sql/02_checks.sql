-- Проверки качества аналитической модели
-- Запускать после создания core.

-- 1. Проверить, что все таблицы core появились
SELECT
    table_name
FROM information_schema.tables
WHERE table_schema = 'core'
ORDER BY table_name;

-- 2. Проверить структуру таблиц core
SELECT
    table_name,
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'core'
ORDER BY table_name, ordinal_position;

-- 02_checks.sql
-- Проверки качества core
-- Ожидаем: violations = 0 для каждой проверки.

WITH checks AS (
    SELECT 'orders_row_count' AS test,
           ABS((SELECT COUNT(*) FROM raw.orders)
             - (SELECT COUNT(*) FROM core.orders)) AS violations

    UNION ALL
    SELECT 'items_row_count',
           ABS((SELECT COUNT(*) FROM raw.order_items)
             - (SELECT COUNT(*) FROM core.order_items))

    UNION ALL
    SELECT 'payments_row_count',
           ABS((SELECT COUNT(*) FROM raw.order_payments)
             - (SELECT COUNT(*) FROM core.order_payments))

    UNION ALL
    SELECT 'reviews_row_count',
           ABS((SELECT COUNT(*) FROM raw.order_reviews)
             - (SELECT COUNT(*) FROM core.order_reviews))

    UNION ALL
    SELECT 'customers_row_count',
           ABS((SELECT COUNT(*) FROM raw.customers)
             - (SELECT COUNT(*) FROM core.customers))

    UNION ALL
    SELECT 'products_row_count',
           ABS((SELECT COUNT(*) FROM raw.products)
             - (SELECT COUNT(*) FROM core.products))

    UNION ALL
    SELECT 'sellers_row_count',
           ABS((SELECT COUNT(*) FROM raw.sellers)
             - (SELECT COUNT(*) FROM core.sellers))

    UNION ALL
    SELECT 'orders_duplicate_keys',
           COUNT(*) - COUNT(DISTINCT order_id)
    FROM core.orders

    UNION ALL
    SELECT 'items_duplicate_keys',
           COUNT(*) - COUNT(DISTINCT (order_id, order_item_id))
    FROM core.order_items

    UNION ALL
    SELECT 'payments_duplicate_keys',
           COUNT(*) - COUNT(DISTINCT (order_id, payment_sequential))
    FROM core.order_payments

    UNION ALL
    SELECT 'reviews_duplicate_keys',
           COUNT(*) - COUNT(DISTINCT review_row_id)
    FROM core.order_reviews

    UNION ALL
    SELECT 'items_without_orders',
           COUNT(*)
    FROM core.order_items i
    LEFT JOIN core.orders o ON i.order_id = o.order_id
    WHERE o.order_id IS NULL

    UNION ALL
    SELECT 'items_without_products',
           COUNT(*)
    FROM core.order_items i
    LEFT JOIN core.products p ON i.product_id = p.product_id
    WHERE p.product_id IS NULL

    UNION ALL
    SELECT 'payments_without_orders',
           COUNT(*)
    FROM core.order_payments p
    LEFT JOIN core.orders o ON p.order_id = o.order_id
    WHERE o.order_id IS NULL

    UNION ALL
    SELECT 'delivered_revenue_mismatch',
           CASE WHEN
             (SELECT COALESCE(SUM(i.price), 0)
              FROM core.order_items i
              JOIN core.orders o USING (order_id)
              WHERE o.order_status = 'delivered')
             = 13221498.11
           THEN 0 ELSE 1 END

    UNION ALL
    SELECT 'all_items_price_mismatch',
           CASE WHEN
             (SELECT COALESCE(SUM(price), 0)
              FROM core.order_items)
             =
             (SELECT COALESCE(SUM(NULLIF(TRIM(price), '')::numeric), 0)
              FROM raw.order_items)
           THEN 0 ELSE 1 END
)
SELECT
    test,
    violations,
    CASE
        WHEN violations = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM checks
ORDER BY test;