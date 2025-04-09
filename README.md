# Pg Ledger

## Overview

pgledger is a PostgreSQL database schema designed for managing financial transactions and accounts.
It provides a robust and scalable foundation for building financial applications.

## Features

- **Accounts**: Create and manage accounts with unique IDs, names, currencies, and balances.
- **Transfers**: Record transactions between accounts, including transfer amounts, timestamps, and account balances.
- **Entries**: Store detailed information about each transaction, including account IDs, transfer IDs, amounts, and
  timestamps.
- **Constraints**: Enforce rules for account balances, such as preventing negative or positive balances.
- **Functions**: Utilize pre-built functions for creating accounts, transfers, and entries, as well as checking account
  balance constraints.

## Schema

The pgledger schema consists of the following

- **Tables**
    - **accounts**: Stores information about each account.
    - **transfers**: Records transactions between accounts.
    - **entries**: Stores detailed information about each transaction.

- **Indexes**
    - **accounts_id_idx**: Index on the accounts table for efficient lookup by ID.
    - **transfers_from_account_id_idx**: Index on the transfers table for efficient lookup by from_account_id.
    - **transfers_to_account_id_idx**: Index on the transfers table for efficient lookup by to_account_id.

- **Functions**
    - **create_account**: Creates a new account with the specified name, currency, and balance constraints.
    - **create_transfer**: Records a transaction between two accounts.
    - **check_account_balance_constraints**: Verifies that an account's balance complies with its constraints.

## Usage of Pg Ledger

Once you've created the `pgledger.sql` schema in your Postgres instance, you can use it as follows.

```sql
-- Create a new account with the specified name, currency, and balance constraints
-- Parameters: account name, currency, allow negative balance, allow positive balance
SELECT *
FROM create_account('My Account', 'USD', TRUE, TRUE);

-- Record a transfer of a specified amount between two accounts
-- Parameters: from account ID, to account ID, transfer amount
SELECT *
FROM create_transfer('account1', 'account2', 100.00);

-- Check if an account's balance complies with its constraints (e.g. negative or positive balance)
-- Parameter: account ID
SELECT *
FROM check_account_balance_constraints('account1');
```