\set ON_ERROR_STOP on
-- All business answers come ONLY from core.
-- Policy: recognized revenue = item price only, delivered orders, purchase month;
-- order value for average check = price + freight at the order grain.

-- A1 monthly delivered item revenue, including empty months.
SELECT to_char(m.month_start, 'YYYY-MM') AS month,
       count(DISTINCT o.order_id) AS orders,
       coalesce(sum(i.price),0)::numeric(15,2) AS revenue
FROM generate_series('2016-09-01'::date,'2018-08-01'::date,'1 month'::interval) m(month_start)
LEFT JOIN core.orders o ON o.purchase_at >= m.month_start
                       AND o.purchase_at < m.month_start + interval '1 month'
                       AND o.order_status='delivered'
LEFT JOIN core.order_items i ON i.order_id=o.order_id
GROUP BY m.month_start ORDER BY m.month_start;

-- A2 seller revenue: attribute ONLY that seller's line items.
SELECT i.seller_id,s.city,s.state,count(DISTINCT i.order_id) AS orders,
       count(*) AS units,sum(i.price)::numeric(15,2) AS revenue
FROM core.order_items i
JOIN core.orders o ON o.order_id=i.order_id
JOIN core.sellers s ON s.seller_id=i.seller_id
WHERE o.order_status='delivered'
GROUP BY i.seller_id,s.city,s.state
ORDER BY revenue DESC,i.seller_id LIMIT 10;

-- A3 mean order check. Note: excluded orders with no items; compare control.
WITH order_totals AS (
 SELECT o.order_id,count(i.order_item_id) AS lines,
        sum(i.price + i.freight_value) AS order_total
 FROM core.orders o JOIN core.order_items i USING (order_id)
 WHERE o.order_status='delivered'
 GROUP BY o.order_id
)
SELECT round(avg(order_total),2) AS avg_order_check,
       round(avg(lines),4) AS avg_lines_per_order,
       round(avg(lines),4) AS avg_units_per_order
FROM order_totals;

-- A4 lifetime repeat customers: any order status counts (as prescribed control).
WITH per_person AS (
 SELECT c.customer_unique_id,count(*) AS order_count
 FROM core.customers c JOIN core.orders o ON o.customer_id=c.customer_id
 GROUP BY c.customer_unique_id
)
SELECT count(*) AS total_customers,
       count(*) FILTER (WHERE order_count >= 2) AS returning_customers,
       round(100.0 * count(*) FILTER (WHERE order_count >= 2) / nullif(count(*),0),2) AS returning_percent
FROM per_person;

-- A5 category revenue. Unknown for products missing category; translated labels where available.
SELECT c.category_code,c.category_name_en,
       sum(i.price)::numeric(15,2) AS revenue,
       round(100.0 * sum(i.price) / nullif(sum(sum(i.price)) OVER (),0),2) AS revenue_pct
FROM core.order_items i
JOIN core.orders o ON o.order_id=i.order_id
JOIN core.products p ON p.product_id=i.product_id
JOIN core.categories c ON c.category_code=p.category_code
WHERE o.order_status='delivered'
GROUP BY c.category_code,c.category_name_en
ORDER BY revenue DESC;
