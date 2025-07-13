# 📚 Library Management System (Oracle SQL)

This project is a backend **Library Management System** implemented entirely in **Oracle SQL**. It manages book inventory, member transactions, fines, waitlists, and generates usage reports.

---

## 🗃️ Database Schema

### 📘 Books
Stores details of each book:
- `book_id` (Primary Key)
- `title`
- `author`
- `total_copies`
- `available_copies`
- `times_borrowed`

### 👤 Members
Stores library member details:
- `member_id` (Primary Key)
- `name`
- `email` (Unique)

### 🔄 Transactions
Tracks borrowing and returning of books:
- `transaction_id` (Primary Key)
- `book_id` (Foreign Key)
- `member_id` (Foreign Key)
- `issue_date`, `due_date`, `return_date`
- `fine_amount`

### ⏳ Waitlist
Maintains queue for books that are unavailable:
- `waitlist_id` (Primary Key)
- `book_id`, `member_id` (Foreign Keys)
- `request_date`

### 💸 FinePayments
Logs fine payments:
- `payment_id` (Primary Key)
- `transaction_id` (Foreign Key)
- `paid_amount`, `payment_date`

### 📋 StockLog
Logs when a book goes out of stock:
- `log_id` (Primary Key)
- `book_id` (Foreign Key)
- `log_date`, `message`

---

## ⚙️ Stored Procedures

### `issue_book(p_book_id, p_member_id)`
- Issues a book if available.
- Adds to waitlist if unavailable.
- Logs stock depletion if no copies remain.

### `return_book(p_transaction_id)`
- Returns a book.
- Calculates fine if overdue.
- Updates availability.
- Auto-issues to next waitlisted member (if any).

### `pay_fine(p_transaction_id)`
- Allows members to pay fines for returned books.

### `log_stock_depletion(p_book_id)`
- Logs when stock reaches zero.

### `log_fine_payment(p_transaction_id)`
- Logs fine payment when a book is returned with a fine.

### `auto_issue_from_waitlist(p_book_id)`
- Issues a returned book to the next member in the waitlist.

### `book_borrowing_report`
- Shows top 5 most and least borrowed books.

### `view_borrowing_history(p_member_id)`
- Displays borrowing history for a member including fine and return status.

### `check_book_availability(p_book_id)`
- Displays total and available copies of a book.

---

## 🧪 Sample Data

Preloaded book and member records included:
- ~12 sample books (Indian authors)
- ~12 sample members with unique emails
- Example transactions, waitlist, and updated stock

---

## ▶️ Example Usage

```sql
-- Issue a book
BEGIN
  issue_book(5, 6);
END;

-- Return a book
BEGIN
  return_book(3);
END;

-- Pay fine
BEGIN
  pay_fine(3);
END;

-- Check availability
BEGIN
  check_book_availability(8);
END;

-- View member borrowing history
BEGIN
  view_borrowing_history(5);
END;

-- Generate book usage report
BEGIN
  book_borrowing_report();
END;
```

---

## ✅ Features

- Fine calculation for overdue books
- Waitlist auto-handling
- Usage reports
- Stock status logging
- Data integrity via constraints and foreign keys

---

## 🧱 Requirements

- Oracle SQL environment (SQL*Plus, Oracle LiveSQL, etc.)
- Enabled output (`SET SERVEROUTPUT ON` for DBMS_OUTPUT)

---

## 📌 Notes

- Fines are calculated at $1 per day overdue.
- Return must happen before paying fines.
- Procedures use `DBMS_OUTPUT.PUT_LINE` for feedback.

---
