-- Create Tables
CREATE TABLE Books (
    book_id NUMBER PRIMARY KEY,
    title VARCHAR2(100) NOT NULL,
    author VARCHAR2(50),
    total_copies NUMBER DEFAULT 1,
    available_copies NUMBER DEFAULT 1,
    times_borrowed NUMBER DEFAULT 0
);


CREATE TABLE Members (
    member_id NUMBER PRIMARY KEY,
    name VARCHAR2(50) NOT NULL,
    email VARCHAR2(50) UNIQUE
);

CREATE TABLE Transactions (
    transaction_id NUMBER PRIMARY KEY,
    book_id NUMBER,
    member_id NUMBER,
    issue_date DATE,
    due_date DATE,
    return_date DATE,
    fine_amount NUMBER DEFAULT 0,
    FOREIGN KEY (book_id) REFERENCES Books(book_id),
    FOREIGN KEY (member_id) REFERENCES Members(member_id)
);

CREATE TABLE Waitlist (
    waitlist_id NUMBER PRIMARY KEY,
    book_id NUMBER,
    member_id NUMBER,
    request_date DATE,
    FOREIGN KEY (book_id) REFERENCES Books(book_id),
    FOREIGN KEY (member_id) REFERENCES Members(member_id)
);

CREATE TABLE FinePayments (
    payment_id NUMBER PRIMARY KEY,
    transaction_id NUMBER,
    paid_amount NUMBER,
    payment_date DATE,
    FOREIGN KEY (transaction_id) REFERENCES Transactions(transaction_id)
);

CREATE TABLE StockLog (
    log_id NUMBER PRIMARY KEY,
    book_id NUMBER,
    log_date DATE,
    message VARCHAR2(200),
    FOREIGN KEY (book_id) REFERENCES Books(book_id)
);

-- Procedures (unchanged from your script)
CREATE OR REPLACE PROCEDURE log_stock_depletion (
    p_book_id IN NUMBER
) AS
    v_available_copies NUMBER;
BEGIN
    SELECT available_copies INTO v_available_copies FROM Books WHERE book_id = p_book_id;
    IF v_available_copies = 0 THEN
        INSERT INTO StockLog (log_id, book_id, log_date, message)
        VALUES ((SELECT NVL(MAX(log_id), 0) + 1 FROM StockLog), p_book_id, SYSDATE, 'Stock depleted for Book ID ' || p_book_id);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Stock depletion logged for Book ID: ' || p_book_id);
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN DBMS_OUTPUT.PUT_LINE('Book not found.');
    WHEN OTHERS THEN ROLLBACK; DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/

CREATE OR REPLACE PROCEDURE log_fine_payment (
    p_transaction_id IN NUMBER
) AS
    v_fine_amount NUMBER;
    v_return_date DATE;
BEGIN
    SELECT fine_amount, return_date INTO v_fine_amount, v_return_date FROM Transactions WHERE transaction_id = p_transaction_id;
    IF v_fine_amount > 0 AND v_return_date IS NOT NULL THEN
        INSERT INTO FinePayments (payment_id, transaction_id, paid_amount, payment_date)
        VALUES ((SELECT NVL(MAX(payment_id), 0) + 1 FROM FinePayments), p_transaction_id, v_fine_amount, SYSDATE);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Fine payment logged for Transaction ID: ' || p_transaction_id);
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN DBMS_OUTPUT.PUT_LINE('Transaction not found.');
    WHEN OTHERS THEN ROLLBACK; DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/

CREATE OR REPLACE PROCEDURE auto_issue_from_waitlist (
    p_book_id IN NUMBER
) AS
    v_member_id NUMBER;
BEGIN
    SELECT member_id INTO v_member_id FROM Waitlist WHERE book_id = p_book_id ORDER BY request_date FETCH FIRST 1 ROWS ONLY;
    issue_book(p_book_id, v_member_id);
    DELETE FROM Waitlist WHERE book_id = p_book_id AND member_id = v_member_id;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Book auto-issued to waitlisted member ID: ' || v_member_id);
EXCEPTION
    WHEN NO_DATA_FOUND THEN DBMS_OUTPUT.PUT_LINE('No one in waitlist for this book.');
END;
/

CREATE OR REPLACE PROCEDURE issue_book (
    p_book_id IN NUMBER,
    p_member_id IN NUMBER
) AS
    v_available_copies NUMBER;
    v_due_date DATE;
BEGIN
    SELECT available_copies INTO v_available_copies FROM Books WHERE book_id = p_book_id;
    IF v_available_copies > 0 THEN
        v_due_date := SYSDATE + 14;
        INSERT INTO Transactions (transaction_id, book_id, member_id, issue_date, due_date)
        VALUES ((SELECT NVL(MAX(transaction_id), 0) + 1 FROM Transactions), p_book_id, p_member_id, SYSDATE, v_due_date);
        UPDATE Books SET available_copies = available_copies - 1, times_borrowed = times_borrowed + 1 WHERE book_id = p_book_id;
        log_stock_depletion(p_book_id);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Book issued successfully. Due date: ' || TO_CHAR(v_due_date, 'YYYY-MM-DD'));
    ELSE
        INSERT INTO Waitlist (waitlist_id, book_id, member_id, request_date)
        VALUES ((SELECT NVL(MAX(waitlist_id), 0) + 1 FROM Waitlist), p_book_id, p_member_id, SYSDATE);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Book unavailable. Added to waitlist.');
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN DBMS_OUTPUT.PUT_LINE('Book or member not found.');
    WHEN OTHERS THEN ROLLBACK; DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/

CREATE OR REPLACE PROCEDURE return_book (
    p_transaction_id IN NUMBER
) AS
    v_book_id NUMBER;
    v_days_overdue NUMBER;
    v_fine NUMBER := 0;
    v_return_date DATE;
BEGIN
    SELECT book_id, return_date INTO v_book_id, v_return_date FROM Transactions WHERE transaction_id = p_transaction_id;
    IF v_return_date IS NULL THEN
        SELECT GREATEST(0, TRUNC(SYSDATE - due_date)) INTO v_days_overdue FROM Transactions WHERE transaction_id = p_transaction_id;
        v_fine := v_days_overdue * 1;
        UPDATE Transactions SET return_date = SYSDATE, fine_amount = v_fine WHERE transaction_id = p_transaction_id;
        log_fine_payment(p_transaction_id);
        UPDATE Books SET available_copies = available_copies + 1 WHERE book_id = v_book_id;
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Book returned. Fine: $' || v_fine);
        auto_issue_from_waitlist(v_book_id);
    ELSE
        DBMS_OUTPUT.PUT_LINE('Book already returned.');
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN DBMS_OUTPUT.PUT_LINE('Transaction not found.');
    WHEN OTHERS THEN ROLLBACK; DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/

CREATE OR REPLACE PROCEDURE pay_fine (
    p_transaction_id IN NUMBER
) AS
    v_fine NUMBER;
BEGIN
    SELECT fine_amount INTO v_fine FROM Transactions WHERE transaction_id = p_transaction_id AND return_date IS NOT NULL;
    IF v_fine > 0 THEN
        INSERT INTO FinePayments (payment_id, transaction_id, paid_amount, payment_date)
        VALUES ((SELECT NVL(MAX(payment_id), 0) + 1 FROM FinePayments), p_transaction_id, v_fine, SYSDATE);
        UPDATE Transactions SET fine_amount = 0 WHERE transaction_id = p_transaction_id;
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Fine paid: $' || v_fine);
    ELSE
        DBMS_OUTPUT.PUT_LINE('No fine to pay or book not returned.');
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN DBMS_OUTPUT.PUT_LINE('Transaction not found.');
    WHEN OTHERS THEN ROLLBACK; DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/

CREATE OR REPLACE PROCEDURE book_borrowing_report AS
BEGIN
    DBMS_OUTPUT.PUT_LINE('Most Borrowed Books:');
    FOR rec IN (SELECT title, times_borrowed FROM Books ORDER BY times_borrowed DESC FETCH FIRST 5 ROWS ONLY)
    LOOP
        DBMS_OUTPUT.PUT_LINE(rec.title || ' - Borrowed ' || rec.times_borrowed || ' times');
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('Least Borrowed Books:');
    FOR rec IN (SELECT title, times_borrowed FROM Books ORDER BY times_borrowed ASC FETCH FIRST 5 ROWS ONLY)
    LOOP
        DBMS_OUTPUT.PUT_LINE(rec.title || ' - Borrowed ' || rec.times_borrowed || ' times');
    END LOOP;
EXCEPTION
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/

CREATE OR REPLACE PROCEDURE view_borrowing_history (
    p_member_id IN NUMBER
) AS
BEGIN
    FOR rec IN (
        SELECT t.transaction_id, b.title, t.issue_date, t.return_date, t.fine_amount
        FROM Transactions t JOIN Books b ON t.book_id = b.book_id
        WHERE t.member_id = p_member_id
        ORDER BY t.issue_date DESC
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('Txn ID: ' || rec.transaction_id || ' | Title: ' || rec.title ||
                             ' | Issued: ' || TO_CHAR(rec.issue_date, 'YYYY-MM-DD') ||
                             ' | Returned: ' || NVL(TO_CHAR(rec.return_date, 'YYYY-MM-DD'), 'Not Returned') ||
                             ' | Fine: $' || rec.fine_amount);
    END LOOP;
END;
/

CREATE OR REPLACE PROCEDURE check_book_availability (
    p_book_id IN NUMBER
) AS
    v_title VARCHAR2(100);
    v_available_copies NUMBER;
    v_total_copies NUMBER;
BEGIN
    SELECT title, available_copies, total_copies
    INTO v_title, v_available_copies, v_total_copies
    FROM Books
    WHERE book_id = p_book_id;
    
    DBMS_OUTPUT.PUT_LINE('Book: ' || v_title);
    DBMS_OUTPUT.PUT_LINE('Available Copies: ' || v_available_copies || ' / ' || v_total_copies);
    IF v_available_copies = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Book is currently unavailable.');
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN DBMS_OUTPUT.PUT_LINE('Book not found.');
    WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/

-- Sample Data
-- Books
INSERT INTO Books VALUES (3, 'The God of Small Things', 'Arundhati Roy', 4, 4, 0);
INSERT INTO Books VALUES (4, 'Midnight''s Children', 'Salman Rushdie', 3, 3, 0);
INSERT INTO Books VALUES (5, 'The White Tiger', 'Aravind Adiga', 2, 2, 0);
INSERT INTO Books VALUES (6, 'A Suitable Boy', 'Vikram Seth', 3, 3, 0);
INSERT INTO Books VALUES (7, 'Malgudi Days', 'R.K. Narayan', 5, 5, 0);
INSERT INTO Books VALUES (8, 'The Palace of Illusions', 'Chitra Banerjee Divakaruni', 2, 2, 0);
INSERT INTO Books VALUES (9, 'Sakina''s Kiss', 'Vivek Shanbhag', 2, 2, 0);
INSERT INTO Books VALUES (10, 'The Blue Umbrella', 'Ruskin Bond', 4, 4, 0);
INSERT INTO Books VALUES (11, 'Train to Pakistan', 'Khushwant Singh', 3, 3, 0);
INSERT INTO Books VALUES (12, 'Acts of God', 'Kanan Gill', 2, 2, 0);
INSERT INTO Books VALUES (13, 'An Uncommon Love', 'Sudha Murty', 3, 3, 0);
INSERT INTO Books VALUES (14, 'My Beloved Life', 'Amitava Kumar', 2, 2, 0);

-- Members
INSERT INTO Members VALUES (3, 'Rahul Sharma', 'rahul.sharma@gmail.com');
INSERT INTO Members VALUES (4, 'Priya Patel', 'priya.patel@yahoo.com');
INSERT INTO Members VALUES (5, 'Amit Kumar', 'amit.kumar@outlook.com');
INSERT INTO Members VALUES (6, 'Ananya Desai', 'ananya.desai@gmail.com');
INSERT INTO Members VALUES (7, 'Vikram Singh', 'vikram.singh@hotmail.com');
INSERT INTO Members VALUES (8, 'Neha Gupta', 'neha.gupta@gmail.com');
INSERT INTO Members VALUES (9, 'Sanjay Reddy', 'sanjay.reddy@yahoo.com');
INSERT INTO Members VALUES (10, 'Pooja Iyer', 'pooja.iyer@outlook.com');
INSERT INTO Members VALUES (11, 'Arjun Mehra', 'arjun.mehra@gmail.com');
INSERT INTO Members VALUES (12, 'Divya Nair', 'divya.nair@hotmail.com');
INSERT INTO Members VALUES (13, 'Rohan Joshi', 'rohan.joshi@yahoo.com');
INSERT INTO Members VALUES (14, 'Shalini Rao', 'shalini.rao@gmail.com');

-- Transactions
-- Transactions (using new transaction_id values)
INSERT INTO Transactions (transaction_id, book_id, member_id, issue_date, due_date)
VALUES (3, 3, 3, TO_DATE('2025-04-20', 'YYYY-MM-DD'), TO_DATE('2025-05-04', 'YYYY-MM-DD')); -- Rahul Sharma, Book 3
INSERT INTO Transactions (transaction_id, book_id, member_id, issue_date, due_date)
VALUES (4, 4, 4, TO_DATE('2025-04-25', 'YYYY-MM-DD'), TO_DATE('2025-05-09', 'YYYY-MM-DD')); -- Priya Patel, Book 4

-- Update Books to reflect borrowing
UPDATE Books SET available_copies = available_copies - 1, times_borrowed = times_borrowed + 1 WHERE book_id = 3;
UPDATE Books SET available_copies = available_copies - 1, times_borrowed = times_borrowed + 1 WHERE book_id = 4;

COMMIT;


-- Waitlist
INSERT INTO Waitlist (waitlist_id, book_id, member_id, request_date)
VALUES (1, 3, 5, SYSDATE);
INSERT INTO Waitlist (waitlist_id, book_id, member_id, request_date)
VALUES (2, 3, 6, SYSDATE + 1);

COMMIT;

-- Example Run
BEGIN
    -- issue_book(5,6);        -- Book issue (Book id , Member id)

    -- issue_book(6,4);

    -- issue_book(9,5);

    -- issue_book(10, 12); 

    -- return_book(5);             -- Book returned

    -- pay_fine(12);                   -- Calculating fine

    -- book_borrowing_report();        -- Most and Least Borrowed 5 books Report

    -- view_borrowing_history(5);          -- Book borrow history

    check_book_availability(8);

    return_book(3);
END;
/

begin
    for i in 1..14 loop
        check_book_availability(i);
    end loop;
end;
/

begin
    for i in 1..14 loop
        view_borrowing_history(i);
    end loop;
end;