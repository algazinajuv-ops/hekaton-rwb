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