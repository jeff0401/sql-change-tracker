# sql-change-tracker
A SQL-only solution to track and extract DML changes to a database

####Use Case
I want to make a series of data changes to a SQL database.  At some point in the future, I want to generate SQL scripts that will apply all of the changes made to another (target) database.  This is helpful when configuring a test system and you want to generate scripts to push all the changes made to a production database.
