--1 task
with recursive l as (
 select 1 as k,num as num1 from nums where id=1
 union
 select k+1, 
 (num1* (select num from nums where id=k+1))%1000 from l where k<(select count(*) from nums )
)

select LPAD(num1::text, 3, '0') as last_three from l order by k desc limit 1


--2 task
with data0 as (select month, sum(amount) filter(where amount>0)as поступило,
-sum(amount) filter(where amount<0)as ушло 
from factory
group by month)
,
data1 as (select month,поступило,ушло,
sum(поступило-ушло) over(order by month) as конец_месяца
from data0)

select month,поступило,ушло,конец_месяца,
COALESCE(LAG(конец_месяца) OVER (ORDER BY month), 0) as начало_месяца from data1

  
--3 task
with recursive Hours AS (
    SELECT c.name AS customer_name, generate_series(21, 30) AS hour 
    FROM customer c
),

DrinkEffects AS (
    SELECT 
        c.name AS customer_name,
        EXTRACT(HOUR FROM b.date)+
  case when EXTRACT(HOUR FROM b.date) < 6 then 24 else 0 end AS drink_hour, 
        SUM(CASE 
            WHEN d.name = 'Wine' THEN 1  
            WHEN d.name = 'Rum' THEN 2   
            ELSE 0
        END) AS drink_effect
    FROM 
        bar b
    JOIN customer c ON b.customer = c.id
    JOIN drinks d ON b.drinks = d.id
    WHERE EXTRACT(HOUR FROM b.date) BETWEEN 21 AND 23  
       OR EXTRACT(HOUR FROM b.date) BETWEEN 0 AND 6   
    GROUP BY c.name, EXTRACT(HOUR FROM b.date)
),

Drink_effects_with_null AS (
   
    SELECT 
        h.customer_name,
        h.hour AS drink_hour,
        COALESCE(de.drink_effect, 0) AS drink_effect 
    FROM Hours h
    LEFT JOIN DrinkEffects de ON h.customer_name = de.customer_name AND h.hour = de.drink_hour
),

result_effect AS (
   
    SELECT 
        customer_name,
        drink_hour,
        drink_effect AS adjusted_effect  
    FROM Drink_effects_with_null
    WHERE drink_hour = 21 

    UNION ALL

    SELECT 
        r2.customer_name,
        r2.drink_hour,
        r2.drink_effect+ GREATEST(adjusted_effect - 1, 0) AS adjusted_effect 
    FROM result_effect r1
    JOIN Drink_effects_with_null r2 ON r1.customer_name = r2.customer_name AND r1.drink_hour + 1 = r2.drink_hour
    WHERE r1.drink_hour < 30 
)

SELECT 
    customer_name,
    adjusted_effect AS final_drunkenness
FROM result_effect
WHERE drink_hour = 30 
ORDER BY 
    final_drunkenness DESC
LIMIT 5;



--4 task
WITH RECURSIVE descendants AS (  
    SELECT id, name, parent
    FROM Italians
    WHERE parent = (SELECT id FROM Italians WHERE name = 'Paulo Fellini') and gender = 'm'

    UNION ALL

   
    SELECT i.id, i.name, i.parent
    FROM Italians i
    JOIN descendants d ON i.parent = d.id where i.gender = 'm'
),

grandpa_with_two_sons as(
SELECT parent
FROM descendants
GROUP BY parent
HAVING COUNT(*) = 2
),

first_son as (select id, name from descendants
where parent = (select parent from grandpa_with_two_sons) limit 1
),

second_son as (select id, name from descendants
where parent = (select parent from grandpa_with_two_sons) offset 1
),

first_sons_descendants as(
 select id, name from first_son
 UNION ALL
 select d.id, d.name
 from first_sons_descendants t
 JOIN
 descendants d on d.parent = t.id
),

second_sons_descendants as(
 select id, name from second_son
 UNION ALL
 select d.id, d.name
 from second_sons_descendants t
 JOIN
 descendants d on d.parent = t.id
)

select name from((select name from first_sons_descendants order by id desc limit 1)
union all
(select name from second_sons_descendants order by id desc limit 1))
where name != 'Vito Fellini'
