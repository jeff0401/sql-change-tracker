# sql-track-change
A SQL-only solution to track and extract DML changes to a database

####Use Case
I wish to make a series of data changes to a SQL database.  At some point in the future, I want to generate SQL scripts that will apply all of the changes made to another (target) database.  This is useful when configuring a test system and I want to generate scripts to push all the changes made to a production database.

####Implementation
This solution uses a table and several stored procedures to allow configuration of what is tracked, enabling/disabling tracking and extracting SQL statements for all the changes made.  It is built upon the SQL Server Change Tracking feature introduced in SQL Server 2008. It also uses the GenerateInsert project (https://github.com/drumsta/sql-generate-insert) by @drumsta.

#### Roadmap

Feature                                                                     | State
--------------------------------------------------------------------------- | :------------:
Initial release                                                             | ✓
Make delete statements type correct                                         | v2.0
Add a new table to tracking while running                                   | v2.0
