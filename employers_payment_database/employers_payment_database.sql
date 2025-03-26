CREATE TABLE FIRM (
    id SERIAL PRIMARY KEY ,
 date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

--drop table EMPLOYEE_MONEY_TRAIL, people, firm
CREATE TABLE PEOPLE (
    id SERIAL PRIMARY KEY,        
    name VARCHAR(100),           
    isBoss BOOLEAN,               
    firmID INT REFERENCES FIRM(id) ON DELETE CASCADE,                  
    balance DECIMAL(10, 2) CHECK(balance >= 0),       
    rating DECIMAL(5, 2)          
);

CREATE UNIQUE INDEX ON PEOPLE(firmID) --у фирмы один босс
WHERE isBoss = True ; 

CREATE TABLE EMPLOYEE_MONEY_TRAIL (
    id SERIAL PRIMARY KEY,                  
    personID INT REFERENCES PEOPLE(id) ON DELETE CASCADE,                           
    money DECIMAL(10, 2) CHECK(money >= 0),                   
    action VARCHAR(50),                     
    status VARCHAR(50),                     
    errorDescription TEXT DEFAULT(''),                  
    ratingAfterOperation DECIMAL(5, 2),     
    date TIMESTAMP DEFAULT CURRENT_TIMESTAMP, 
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, 
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE OR REPLACE FUNCTION handle_salary_payment() RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    boss_balance NUMERIC;
    salary_amount NUMERIC := NEW.balance - OLD.balance;
 last_updated TIMESTAMP;
BEGIN
 SELECT created_at into last_updated from EMPLOYEE_MONEY_TRAIL where personID = NEW.id
 order by created_at desc limit 1;  

    -- Получаем баланс руководителя фирмы
    SELECT balance INTO boss_balance
    FROM PEOPLE
    WHERE firmId = NEW.firmID AND isBoss = TRUE;

    -- Проверяем, достаточно ли средств на счете руководителя
    IF boss_balance < salary_amount THEN
        INSERT INTO EMPLOYEE_MONEY_TRAIL (personID, money, action, status, errorDescription, ratingAfterOperation, date, created_at, updated_at)
        VALUES (NEW.id, salary_amount, 'salary', 'failed', 'Boss balance for salary payment < 0', NEW.rating, NOW(), NOW(), last_updated);
        
        RETURN OLD;
    END IF;

    -- Корректируем баланс руководителя
    UPDATE PEOPLE
    SET balance = balance - salary_amount
    WHERE firmId = NEW.firmID AND isBoss = TRUE;

    NEW.rating := NEW.rating + 10;

    INSERT INTO EMPLOYEE_MONEY_TRAIL (personID, money, action, status, ratingAfterOperation, date, created_at, updated_at)
    VALUES (NEW.id, salary_amount, 'salary', 'completed', NEW.rating, NOW(), NOW(), last_updated);

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION handle_damage_payment() RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    boss_id INT;
 damage_amount NUMERIC := OLD.balance - NEW.balance;
 last_updated TIMESTAMP;
BEGIN
 SELECT created_at into last_updated from EMPLOYEE_MONEY_TRAIL where personID = NEW.id
 order by created_at desc limit 1;

    IF NEW.balance < 0 THEN    
        UPDATE PEOPLE SET balance = balance + OLD.balance
        WHERE firmId = NEW.firmID AND isBoss = TRUE;

  IF old.balance > 0 THEN NEW.rating := NEW.rating + 10; --в этом случае баланс изменился, иначе как был 0 так и остался.
  END IF;
  
        NEW.balance := 0;

        NEW.rating := NEW.rating - (damage_amount - OLD.balance) / 10;

  INSERT INTO EMPLOYEE_MONEY_TRAIL (personID, money, action, status, errorDescription, ratingAfterOperation, date, created_at, updated_at)
        VALUES (NEW.id, damage_amount, 'damage', 'failed', 'employee balance < 0, rating applied', NEW.rating, NOW(), NOW(), last_updated);
  
  INSERT INTO EMPLOYEE_MONEY_TRAIL (personID, money, action, status, ratingAfterOperation, date, created_at, updated_at)
        VALUES (NEW.id, damage_amount, 'damage', 'complited', NEW.rating, NOW(), NOW(), last_updated);
    ELSE
    
  UPDATE PEOPLE SET balance = balance + damage_amount
        WHERE firmId = NEW.firmID AND isBoss = TRUE;
        
  NEW.rating := NEW.rating + 10;

        INSERT INTO EMPLOYEE_MONEY_TRAIL (personID, money, action, status, ratingAfterOperation, date, created_at, updated_at)
        VALUES (NEW.id, damage_amount, 'damage', 'completed', NEW.rating, NOW(), NOW(), last_updated);
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER before_salary_update
BEFORE UPDATE OF balance ON PEOPLE
FOR EACH ROW
WHEN (NEW.balance > OLD.balance AND NEW.isBoss = FALSE) -- Срабатывает при увеличении баланса и если не босс
EXECUTE FUNCTION handle_salary_payment();

CREATE OR REPLACE TRIGGER before_damage_update
BEFORE UPDATE OF balance ON PEOPLE
FOR EACH ROW
WHEN (NEW.balance < OLD.balance AND NEW.isBoss = FALSE) -- Срабатывает при уменьшении баланса и если не босс
EXECUTE FUNCTION handle_damage_payment();

CREATE OR REPLACE FUNCTION promote_to_leader() RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    new_firm_id INT;
BEGIN
    IF NEW.rating >= 100 AND NEW.isBoss = FALSE THEN
        -- Создаём новую фирму
        INSERT INTO FIRM DEFAULT VALUES RETURNING id INTO new_firm_id;

        NEW.isBoss := TRUE;
        NEW.firmID := new_firm_id;

    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER check_promotion
BEFORE UPDATE OF rating ON PEOPLE
FOR EACH ROW
WHEN (NEW.rating >= 100 AND NEW.isBoss = FALSE)
EXECUTE FUNCTION promote_to_leader();

CREATE OR REPLACE FUNCTION assign_new_employee() RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    target_firm_id INT;
BEGIN
    IF NEW.rating > 20 THEN
        NEW.rating := 20;
    END IF;

    SELECT id INTO target_firm_id
    FROM (
        SELECT f.id,
               COALESCE(SUM(p.rating) FILTER(where p.isBoss = FALSE), 0) AS total_rating, -- 0 для фирм без сотрудников
               MAX(f.date) AS most_recent_date
        FROM FIRM f, PEOPLE p where f.id = p.firmID 
        GROUP BY f.id
        ORDER BY total_rating ASC, most_recent_date DESC
        LIMIT 1
    ) AS firm_with_min_rating;

    
    NEW.firmID := target_firm_id;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER before_insert_employee
BEFORE INSERT ON PEOPLE
FOR EACH ROW
WHEN (NEW.isBoss = FALSE)  
EXECUTE FUNCTION assign_new_employee();

CREATE OR REPLACE FUNCTION setup_new_boss() RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    new_firm_id INT;
BEGIN
    IF NEW.rating < 250 THEN
        NEW.rating := 250;
    END IF;

    IF NEW.balance < 10000 THEN
        NEW.balance := 10000;
    END IF;

    INSERT INTO FIRM DEFAULT VALUES RETURNING id INTO new_firm_id;

    NEW.firmID := new_firm_id;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER before_insert_boss
BEFORE INSERT ON PEOPLE
FOR EACH ROW
WHEN (NEW.isBoss = TRUE)
EXECUTE FUNCTION setup_new_boss();

--добавление новых руководителей 
INSERT INTO PEOPLE (name, isBoss, firmID, balance, rating) 
VALUES ('Bob', TRUE, NULL, 15000, 300);

INSERT INTO PEOPLE (name, isBoss, firmID, balance, rating) 
VALUES ('Carl', TRUE, NULL, 10000, 200);

INSERT INTO PEOPLE (name, isBoss, firmID, balance, rating) 
VALUES ('Jim', TRUE, NULL, 8000, 400);

--1)в самую новую фирму
INSERT INTO PEOPLE (name, isBoss, firmID, balance, rating) 
VALUES ('Zara', FALSE, NULL, 3000, 20);

--4)в более новую из firm с один. рейтингом 
INSERT INTO PEOPLE (name, isBoss, firmID, balance, rating) 
VALUES ('Jeen', FALSE, NULL, 2500, 15);

--2)в самую древнюю, так как минамальный рейтинг
INSERT INTO PEOPLE (name, isBoss, firmID, balance, rating) 
VALUES ('Mike', FALSE, NULL, 2000, 17);

--3)не куда хотел
INSERT INTO PEOPLE (name, isBoss, firmID, balance, rating) 
VALUES ('Mill', FALSE, 3, 2000, 20);

--5)меньше уровень надёжности
INSERT INTO PEOPLE (name, isBoss, firmID, balance, rating) 
VALUES ('Bill', FALSE, NULL, 2000, 25);

--1)Успешно обработалась damage
UPDATE people SET balance = balance - 100 where name = 'Zara' 

--2)Частично отменена из-за недостаточного баланса, появилось две записи. 
UPDATE people SET balance = balance - 3000 where name = 'Bill' 

--3)Полностью отменена из-за недостаточного баланса руководителя
UPDATE people SET balance = balance + 11000 where name = 'Mill'

--4)'Zara' стала боссом новой фирмы с id = 4
UPDATE people SET rating = 110 where name = 'Zara'

--5)Обновлена вручную
UPDATE people SET balance = balance + 100 where name = 'Mill'
UPDATE people SET balance = balance + 200 where name = 'Mill'
UPDATE EMPLOYEE_MONEY_TRAIL SET money=100, updated_at = CURRENT_TIMESTAMP
where id = 5

select * from EMPLOYEE_MONEY_TRAIL
select * from people
select * from firm

 
