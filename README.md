# DB2 to BigQuery!

## Motivation
Multiple DB2 tables exist, and data engineers want to work on.
So let's automate/simplify the Extraction of ETL for them!

## Todos
1. [ ] Build a rust binary which has db2 odbc properly configured/installed in x86 linux container
    1. [ ] MacOS arm64
1. [ ] Deploy it to a cluster w/DB access and print some rows of data
1. [ ] Upload the targeted database table to targeted bigquery
   1. [ ] Upload only diff in table
   1. [ ] Upload multiple tables
1. [ ] Allow for different versions of DB2 / its driver?
1. [ ] Allow upload to postgres?
