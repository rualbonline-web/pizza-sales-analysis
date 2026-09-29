/* =====================================================================
   ПРОМІЖНИЙ ПРОЄКТ: ПРОДАЖІ ПІЦЕРІЇ (Pizza Place Sales, 2015)
   Автор: Рут Альбрехт
   Середовище: SQLite Online (https://sqliteonline.com/)
   Таблиці імпортовано з CSV: orders, order_details, pizzas, pizza_types.
   Після імпорту всі колонки мають тип TEXT, тому числа приводимо через CAST.
   ===================================================================== */


/* ---------------------------------------------------------------------
   0. ПЕРЕВІРКА ДАНИХ
   --------------------------------------------------------------------- */

-- 0.1 Кількість рядків у кожній таблиці
SELECT 'orders'        AS table_name, COUNT(*) AS n_rows FROM orders
UNION ALL SELECT 'order_details', COUNT(*) FROM order_details
UNION ALL SELECT 'pizzas',        COUNT(*) FROM pizzas
UNION ALL SELECT 'pizza_types',   COUNT(*) FROM pizza_types;
-- Очікувано: 21 350 / 48 620 / 96 / 32

-- 0.2 Пропуски (NULL або порожні рядки) у ключових колонках
SELECT
  SUM(CASE WHEN order_id IS NULL OR order_id = '' THEN 1 ELSE 0 END) AS null_order_id,
  SUM(CASE WHEN date     IS NULL OR date     = '' THEN 1 ELSE 0 END) AS null_date,
  SUM(CASE WHEN time     IS NULL OR time     = '' THEN 1 ELSE 0 END) AS null_time
FROM orders;

SELECT
  SUM(CASE WHEN order_id IS NULL OR order_id = '' THEN 1 ELSE 0 END) AS null_order_id,
  SUM(CASE WHEN pizza_id IS NULL OR pizza_id = '' THEN 1 ELSE 0 END) AS null_pizza_id,
  SUM(CASE WHEN quantity IS NULL OR quantity = '' THEN 1 ELSE 0 END) AS null_quantity
FROM order_details;

-- 0.3 Цілісність зв'язків: рядки order_details без пари в orders / pizzas
SELECT COUNT(*) AS details_without_order
FROM order_details od LEFT JOIN orders o ON o.order_id = od.order_id
WHERE o.order_id IS NULL;

SELECT COUNT(*) AS details_without_pizza
FROM order_details od LEFT JOIN pizzas p ON p.pizza_id = od.pizza_id
WHERE p.pizza_id IS NULL;

-- 0.4 Формат дати та часу (strftime потребує РРРР-ММ-ДД і ГГ:ХХ:СС)
SELECT date, time, strftime('%w', date) AS weekday_num, strftime('%H', time) AS hour
FROM orders LIMIT 5;

-- 0.5 Діапазон дат і кількість робочих днів
SELECT MIN(date) AS first_day, MAX(date) AS last_day, COUNT(DISTINCT date) AS open_days
FROM orders;


/* ---------------------------------------------------------------------
   ВИБІРКА sales_lines ДЛЯ TABLEAU (оформлена як VIEW — бонус)
   Один рядок = одна позиція замовлення (рядок order_details).
   JOIN усіх чотирьох таблиць:
     order_details → orders      (по order_id)
     order_details → pizzas      (по pizza_id)
     pizzas        → pizza_types (по pizza_type_id)
   --------------------------------------------------------------------- */
DROP VIEW IF EXISTS sales_lines;
CREATE VIEW sales_lines AS
SELECT
  CAST(o.order_id AS INTEGER)                        AS order_id,
  o.date                                             AS order_date,
  o.time                                             AS order_time,
  strftime('%m', o.date)                             AS month,
  CASE strftime('%w', o.date)
       WHEN '0' THEN 'Sunday'    WHEN '1' THEN 'Monday'
       WHEN '2' THEN 'Tuesday'   WHEN '3' THEN 'Wednesday'
       WHEN '4' THEN 'Thursday'  WHEN '5' THEN 'Friday'
       WHEN '6' THEN 'Saturday'
  END                                                AS weekday,
  CAST(strftime('%H', o.time) AS INTEGER)            AS hour,
  pt.name                                            AS pizza_name,
  pt.category                                        AS category,
  p.size                                             AS size,
  CAST(p.price AS REAL)                              AS unit_price,
  CAST(od.quantity AS INTEGER)                       AS quantity,
  ROUND(CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER), 2) AS revenue
FROM order_details od
JOIN orders      o  ON o.order_id       = od.order_id
JOIN pizzas      p  ON p.pizza_id       = od.pizza_id
JOIN pizza_types pt ON pt.pizza_type_id = p.pizza_type_id;

-- Перевірка: рядків у sales_lines має бути стільки ж, скільки в order_details (48 620)
SELECT (SELECT COUNT(*) FROM sales_lines)   AS sales_lines_rows,
       (SELECT COUNT(*) FROM order_details) AS order_details_rows;

-- Вивантаження для Tableau: виконати цей запит і натиснути Export → CSV
SELECT * FROM sales_lines ORDER BY order_id;


/* ---------------------------------------------------------------------
   Q1. ЗАГАЛЬНІ ПОКАЗНИКИ ЗА РІК
   Виручка, кількість замовлень, кількість піц (з урахуванням quantity),
   середній чек (виручка / кількість унікальних замовлень),
   середня кількість піц у замовленні.
   --------------------------------------------------------------------- */
SELECT
  ROUND(SUM(CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER)), 2)       AS total_revenue,
  COUNT(DISTINCT od.order_id)                                               AS total_orders,
  SUM(CAST(od.quantity AS INTEGER))                                         AS pizzas_sold,
  ROUND(SUM(CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER))
        / COUNT(DISTINCT od.order_id), 2)                                   AS avg_order_value,
  ROUND(1.0 * SUM(CAST(od.quantity AS INTEGER))
        / COUNT(DISTINCT od.order_id), 2)                                   AS avg_pizzas_per_order
FROM order_details od
JOIN pizzas p ON p.pizza_id = od.pizza_id;


/* ---------------------------------------------------------------------
   Q2. ДИНАМІКА ПО МІСЯЦЯХ + ★ зміна до попереднього місяця (LAG)
   --------------------------------------------------------------------- */
WITH monthly AS (
  SELECT
    strftime('%m', o.date)                                              AS month,
    ROUND(SUM(CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER)), 2) AS revenue,
    COUNT(DISTINCT o.order_id)                                          AS orders
  FROM orders o
  JOIN order_details od ON od.order_id = o.order_id
  JOIN pizzas p         ON p.pizza_id  = od.pizza_id
  GROUP BY month
)
SELECT
  month,
  revenue,
  orders,
  ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
        / LAG(revenue) OVER (ORDER BY month), 1)                        AS revenue_mom_pct,
  ROUND(100.0 * (orders - LAG(orders) OVER (ORDER BY month))
        / LAG(orders) OVER (ORDER BY month), 1)                         AS orders_mom_pct,
  RANK() OVER (ORDER BY revenue DESC)                                   AS revenue_rank
FROM monthly
ORDER BY month;


/* ---------------------------------------------------------------------
   Q3. НАВАНТАЖЕННЯ ЗА ДНЯМИ ТИЖНЯ ТА ГОДИНАМИ
   3a — середня кількість замовлень за ОДИН день кожного типу
        (ділимо на COUNT(DISTINCT date), а не беремо просту суму)
   --------------------------------------------------------------------- */
SELECT
  strftime('%w', date)                                  AS weekday_num,
  CASE strftime('%w', date)
       WHEN '0' THEN 'Sunday'   WHEN '1' THEN 'Monday'   WHEN '2' THEN 'Tuesday'
       WHEN '3' THEN 'Wednesday' WHEN '4' THEN 'Thursday' WHEN '5' THEN 'Friday'
       WHEN '6' THEN 'Saturday' END                     AS weekday,
  COUNT(*)                                              AS total_orders,
  COUNT(DISTINCT date)                                  AS n_days,
  ROUND(1.0 * COUNT(*) / COUNT(DISTINCT date), 1)       AS avg_orders_per_day
FROM orders
GROUP BY weekday_num
ORDER BY avg_orders_per_day DESC;

-- 3b — середня кількість замовлень за годину (в середньому за робочий день)
SELECT
  CAST(strftime('%H', time) AS INTEGER)                             AS hour,
  COUNT(*)                                                          AS total_orders,
  ROUND(1.0 * COUNT(*) / (SELECT COUNT(DISTINCT date) FROM orders), 1) AS avg_orders_per_day
FROM orders
GROUP BY hour
ORDER BY hour;

-- 3c — теплова карта «день тижня × година»: середнє замовлень за одну таку годину
SELECT
  CASE strftime('%w', date)
       WHEN '0' THEN '7 Sun' WHEN '1' THEN '1 Mon' WHEN '2' THEN '2 Tue'
       WHEN '3' THEN '3 Wed' WHEN '4' THEN '4 Thu' WHEN '5' THEN '5 Fri'
       WHEN '6' THEN '6 Sat' END                                    AS weekday,
  CAST(strftime('%H', time) AS INTEGER)                             AS hour,
  COUNT(*)                                                          AS total_orders,
  ROUND(1.0 * COUNT(*) / (SELECT COUNT(DISTINCT o2.date) FROM orders o2
                          WHERE strftime('%w', o2.date) = strftime('%w', orders.date)), 1)
                                                                    AS avg_orders
FROM orders
GROUP BY weekday, hour
ORDER BY weekday, hour;


/* ---------------------------------------------------------------------
   Q4. БЕСТСЕЛЕРИ ТА АУТСАЙДЕРИ (рівень назви піци, усі розміри разом)
   --------------------------------------------------------------------- */
-- 4a. Топ-5 за виручкою
SELECT pt.name,
       ROUND(SUM(CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER)), 2) AS revenue,
       SUM(CAST(od.quantity AS INTEGER))                                   AS qty
FROM order_details od
JOIN pizzas p       ON p.pizza_id = od.pizza_id
JOIN pizza_types pt ON pt.pizza_type_id = p.pizza_type_id
GROUP BY pt.name
ORDER BY revenue DESC
LIMIT 5;

-- 4b. Останні 5 за виручкою
SELECT pt.name,
       ROUND(SUM(CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER)), 2) AS revenue,
       SUM(CAST(od.quantity AS INTEGER))                                   AS qty
FROM order_details od
JOIN pizzas p       ON p.pizza_id = od.pizza_id
JOIN pizza_types pt ON pt.pizza_type_id = p.pizza_type_id
GROUP BY pt.name
ORDER BY revenue ASC
LIMIT 5;

-- 4c. Топ-5 за кількістю
SELECT pt.name,
       SUM(CAST(od.quantity AS INTEGER))                                   AS qty,
       ROUND(SUM(CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER)), 2) AS revenue
FROM order_details od
JOIN pizzas p       ON p.pizza_id = od.pizza_id
JOIN pizza_types pt ON pt.pizza_type_id = p.pizza_type_id
GROUP BY pt.name
ORDER BY qty DESC
LIMIT 5;

-- 4d. Останні 5 за кількістю
SELECT pt.name,
       SUM(CAST(od.quantity AS INTEGER))                                   AS qty,
       ROUND(SUM(CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER)), 2) AS revenue
FROM order_details od
JOIN pizzas p       ON p.pizza_id = od.pizza_id
JOIN pizza_types pt ON pt.pizza_type_id = p.pizza_type_id
GROUP BY pt.name
ORDER BY qty ASC
LIMIT 5;

-- 4e. ★ Порівняння рангів (RANK): чи збігаються списки за виручкою і за кількістю
WITH by_pizza AS (
  SELECT pt.name,
         SUM(CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER)) AS revenue,
         SUM(CAST(od.quantity AS INTEGER))                         AS qty
  FROM order_details od
  JOIN pizzas p       ON p.pizza_id = od.pizza_id
  JOIN pizza_types pt ON pt.pizza_type_id = p.pizza_type_id
  GROUP BY pt.name
)
SELECT name,
       ROUND(revenue, 2)                         AS revenue,
       qty,
       RANK() OVER (ORDER BY revenue DESC)       AS rank_revenue,
       RANK() OVER (ORDER BY qty DESC)           AS rank_qty
FROM by_pizza
ORDER BY rank_revenue;


/* ---------------------------------------------------------------------
   Q5. КАТЕГОРІЇ ТА РОЗМІРИ: частка виручки
   5a — через підзапит (обов'язковий варіант)
   --------------------------------------------------------------------- */
SELECT pt.category,
       ROUND(SUM(CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER)), 2) AS revenue,
       SUM(CAST(od.quantity AS INTEGER))                                   AS qty,
       ROUND(100.0 * SUM(CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER))
             / (SELECT SUM(CAST(p2.price AS REAL) * CAST(od2.quantity AS INTEGER))
                FROM order_details od2 JOIN pizzas p2 ON p2.pizza_id = od2.pizza_id), 1)
                                                                           AS revenue_share_pct
FROM order_details od
JOIN pizzas p       ON p.pizza_id = od.pizza_id
JOIN pizza_types pt ON pt.pizza_type_id = p.pizza_type_id
GROUP BY pt.category
ORDER BY revenue DESC;

-- 5b — ★ розміри через віконну функцію SUM() OVER ()
SELECT p.size,
       ROUND(SUM(CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER)), 2)  AS revenue,
       SUM(CAST(od.quantity AS INTEGER))                                    AS qty,
       ROUND(100.0 * SUM(CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER))
             / SUM(SUM(CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER))) OVER (), 1)
                                                                            AS revenue_share_pct,
       ROUND(100.0 * SUM(CAST(od.quantity AS INTEGER))
             / SUM(SUM(CAST(od.quantity AS INTEGER))) OVER (), 1)           AS qty_share_pct
FROM order_details od
JOIN pizzas p ON p.pizza_id = od.pizza_id
GROUP BY p.size
ORDER BY revenue DESC;


/* ---------------------------------------------------------------------
   Q6. КАНДИДАТИ НА ВИЛУЧЕННЯ З МЕНЮ (рівень назви піци)
   6a — усі 32 піци від найслабшої: частка виручки,
        ★ накопичувальна частка (SUM() OVER (ORDER BY …)),
        CASE: «зона ризику» = частка виручки < 2 % І продажі < 1 000 шт.
   --------------------------------------------------------------------- */
WITH by_pizza AS (
  SELECT pt.pizza_type_id,
         pt.name,
         pt.category,
         SUM(CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER)) AS revenue,
         SUM(CAST(od.quantity AS INTEGER))                         AS qty
  FROM order_details od
  JOIN pizzas p       ON p.pizza_id = od.pizza_id
  JOIN pizza_types pt ON pt.pizza_type_id = p.pizza_type_id
  GROUP BY pt.pizza_type_id, pt.name, pt.category
)
SELECT name,
       category,
       ROUND(revenue, 2)                                                   AS revenue,
       qty,
       ROUND(100.0 * revenue / SUM(revenue) OVER (), 2)                    AS revenue_share_pct,
       ROUND(100.0 * SUM(revenue) OVER (ORDER BY revenue
                                         ROWS UNBOUNDED PRECEDING)
             / SUM(revenue) OVER (), 2)                                    AS cumulative_share_pct,
       CASE WHEN 100.0 * revenue / SUM(revenue) OVER () < 2.0 AND qty < 1000
            THEN 'зона ризику' ELSE 'залишити' END                        AS status
FROM by_pizza
ORDER BY revenue ASC;

-- 6b — фільтр через HAVING: піци, що дали < 2 % річної виручки та < 1 000 шт.
SELECT pt.pizza_type_id,
       pt.name,
       ROUND(SUM(CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER)), 2) AS revenue,
       SUM(CAST(od.quantity AS INTEGER))                                   AS qty
FROM order_details od
JOIN pizzas p       ON p.pizza_id = od.pizza_id
JOIN pizza_types pt ON pt.pizza_type_id = p.pizza_type_id
GROUP BY pt.pizza_type_id, pt.name
HAVING SUM(CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER))
         < 0.02 * (SELECT SUM(CAST(p2.price AS REAL) * CAST(od2.quantity AS INTEGER))
                   FROM order_details od2 JOIN pizzas p2 ON p2.pizza_id = od2.pizza_id)
   AND SUM(CAST(od.quantity AS INTEGER)) < 1000
ORDER BY revenue;

-- 6c — унікальні інгредієнти: для кожної піци — інгредієнти, яких немає в жодній іншій
--      (рекурсивний CTE розбиває рядок інгредієнтів за комою)
WITH RECURSIVE split(pizza_type_id, ingredient, rest) AS (
  SELECT pizza_type_id, '', ingredients || ',' FROM pizza_types
  UNION ALL
  SELECT pizza_type_id,
         TRIM(SUBSTR(rest, 1, INSTR(rest, ',') - 1)),
         SUBSTR(rest, INSTR(rest, ',') + 1)
  FROM split WHERE rest <> ''
),
ingr AS (SELECT DISTINCT pizza_type_id, ingredient FROM split WHERE ingredient <> '')
SELECT i.pizza_type_id,
       COUNT(*)                   AS unique_ingredients,
       GROUP_CONCAT(i.ingredient, ', ') AS ingredients
FROM ingr i
WHERE (SELECT COUNT(*) FROM ingr i2 WHERE i2.ingredient = i.ingredient) = 1
GROUP BY i.pizza_type_id
ORDER BY unique_ingredients DESC;

-- 6d — ефект рекомендації: прибрати 4 піци
--      (Brie Carre, Mediterranean, Spinach Supreme — в останній п'ятірці і за виручкою, і за кількістю;
--       Calabrese — в останній п'ятірці за кількістю і має 3 унікальні інгредієнти)
WITH by_pizza AS (
  SELECT pt.pizza_type_id,
         SUM(CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER)) AS revenue,
         SUM(CAST(od.quantity AS INTEGER))                         AS qty
  FROM order_details od
  JOIN pizzas p       ON p.pizza_id = od.pizza_id
  JOIN pizza_types pt ON pt.pizza_type_id = p.pizza_type_id
  GROUP BY pt.pizza_type_id
)
SELECT COUNT(*)                                                             AS n_pizzas,
       ROUND(SUM(revenue), 2)                                               AS revenue_at_risk,
       ROUND(100.0 * SUM(revenue) / (SELECT SUM(revenue) FROM by_pizza), 1) AS revenue_share_pct,
       SUM(qty)                                                             AS pizzas_sold
FROM by_pizza
WHERE pizza_type_id IN ('brie_carre', 'mediterraneo', 'spinach_supr', 'calabrese');

-- 6e — розмір XXL: є лише в однієї піци (The Greek) — кандидат на вилучення розміру
SELECT p.size,
       COUNT(DISTINCT p.pizza_type_id)                                      AS pizza_types,
       SUM(CAST(od.quantity AS INTEGER))                                    AS qty,
       ROUND(SUM(CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER)), 2)  AS revenue
FROM order_details od
JOIN pizzas p ON p.pizza_id = od.pizza_id
WHERE p.size IN ('XL', 'XXL')
GROUP BY p.size;


/* ---------------------------------------------------------------------
   Q7. ВЕЛИКІ ЗАМОВЛЕННЯ (4+ піци в замовленні)
   CTE на рівні замовлення → CASE для сегмента
   --------------------------------------------------------------------- */
WITH order_level AS (
  SELECT od.order_id,
         SUM(CAST(od.quantity AS INTEGER))                         AS pizzas,
         SUM(CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER)) AS revenue
  FROM order_details od
  JOIN pizzas p ON p.pizza_id = od.pizza_id
  GROUP BY od.order_id
)
SELECT CASE WHEN pizzas >= 4 THEN '4+ піци' ELSE '1–3 піци' END              AS segment,
       COUNT(*)                                                             AS orders,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM order_level), 1)      AS orders_share_pct,
       ROUND(SUM(revenue), 2)                                               AS revenue,
       ROUND(100.0 * SUM(revenue) / (SELECT SUM(revenue) FROM order_level), 1) AS revenue_share_pct,
       ROUND(AVG(revenue), 2)                                               AS avg_order_value,
       ROUND(AVG(pizzas), 1)                                                AS avg_pizzas
FROM order_level
GROUP BY segment;

-- 7b — коли надходять великі замовлення (для B2B-пропозиції)
WITH order_level AS (
  SELECT o.order_id, o.date, o.time,
         SUM(CAST(od.quantity AS INTEGER)) AS pizzas
  FROM orders o JOIN order_details od ON od.order_id = o.order_id
  GROUP BY o.order_id, o.date, o.time
)
SELECT CAST(strftime('%H', time) AS INTEGER) AS hour,
       COUNT(*)                               AS big_orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_pct
FROM order_level
WHERE pizzas >= 4
GROUP BY hour
ORDER BY big_orders DESC
LIMIT 5;


/* ---------------------------------------------------------------------
   Q8. АКЦІЯ: слабкі вікна та потенціал +10 %
   Вікна обрано за тепловою картою Q3:
     A — Пн–Пт 14:00–16:59: провал між обідом і вечерею (≈4 замовлення/год проти 8 в обід),
         персонал на зміні все одно є;
     B — Неділя, весь день: найслабший день тижня (50,5 замовлення проти 70,8 у п'ятницю);
     C — Нд–Чт після 21:00: менше 3 замовлень/год — це питання графіка, а не акції.
   --------------------------------------------------------------------- */
WITH lines AS (
  SELECT o.order_id, o.date,
         strftime('%w', o.date)                                    AS wd,
         CAST(strftime('%H', o.time) AS INTEGER)                   AS hr,
         CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER)      AS revenue
  FROM orders o
  JOIN order_details od ON od.order_id = o.order_id
  JOIN pizzas p         ON p.pizza_id  = od.pizza_id
),
tagged AS (
  SELECT *,
    CASE
      WHEN wd IN ('1','2','3','4','5') AND hr BETWEEN 14 AND 16 THEN 'A: Пн–Пт 14:00–17:00'
      WHEN wd = '0'                                            THEN 'B: Неділя, весь день'
      WHEN wd IN ('1','2','3','4') AND hr >= 21                THEN 'C: Пн–Чт після 21:00'
      ELSE 'інші години' END AS time_window
  FROM lines
)
SELECT time_window,
       COUNT(DISTINCT order_id)                                     AS orders,
       COUNT(DISTINCT date)                                         AS n_days,
       ROUND(SUM(revenue), 2)                                       AS revenue,
       ROUND(SUM(revenue) / COUNT(DISTINCT date), 2)                AS revenue_per_day,
       ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1)   AS revenue_share_pct,
       ROUND(SUM(revenue) * 0.10, 2)                                AS plus_10pct_per_year
FROM tagged
GROUP BY time_window
ORDER BY revenue;

-- 8b — що купують у вікні A (розміри) — щоб скласти пропозицію
WITH lines AS (
  SELECT strftime('%w', o.date) AS wd,
         CAST(strftime('%H', o.time) AS INTEGER) AS hr,
         p.size,
         CAST(p.price AS REAL) * CAST(od.quantity AS INTEGER) AS revenue
  FROM orders o
  JOIN order_details od ON od.order_id = o.order_id
  JOIN pizzas p         ON p.pizza_id  = od.pizza_id
)
SELECT size,
       ROUND(SUM(revenue), 2)                                      AS revenue,
       ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1)  AS share_pct
FROM lines
WHERE wd IN ('1','2','3','4','5') AND hr BETWEEN 14 AND 16
GROUP BY size
ORDER BY revenue DESC;
