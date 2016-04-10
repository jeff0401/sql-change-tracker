# sql-track-change
A SQL-only solution to track and extract DML changes to a database

####Use Case
I want to make a series of data changes to a database (source).  At some point in the future, I want to generate SQL scripts that will apply all of the changes that I've made to the source database to another database (target).  This will be useful when configuring a test system, and I want to generate scripts to propagate all the changes made to a production database.

####Implementation
This solution uses a table for configuration of what is tracked, and several stored procedures for enabling/disabling tracking and extracting SQL statements for all the changes made.  It uses the SQL Server Change Tracking feature introduced in SQL Server 2008. It also uses the GenerateInsert project (https://github.com/drumsta/sql-generate-insert) by @drumsta.

####Usage

######Installation
Execute the _Install.sql_ script to create the table and stored procedures.  The configuration table (_dbo.TrackChangeConfig_) will be prepopulated with all tables from the database.

######Configuration
Configuration is stored in the _dbo.TrackChangeConfig_ table.  Tracking is an opt-in operation.  Set the _TrackChanges_ field to 1 for each table to track.  If the table contains an identity column, you can set the _IdentityIncrement_ field.  If set, the table will be reseeded to the current value plus this increment when tracking is started.  This option creates a buffer between the records configured in the source database and the records in the target database.  This is to avoid Id conflicts when the script is executed in the target database. 

######Begin Tracking
Execute the _dbo.uspTrackChangeStart_ stored procedure.  This will turn on change tracking at the database level and enable tracking on each table configured for tracking.  If a table has an _IdentityIncrement_ value, the table will be reseeded.  SQL Server Change Tracking is set to retain changes for 365 days.

######Make Changes
Set it and forget it.  SQL Server Change Tracking will keep track of all the changes automatically.

######Generate Scripts
After changes are completed or at a checkpoint, execute the _dbo.uspTrackChangeExtract_ stored procedure.  This will generate delete/insert statements needed to propagate all stored changes to the target database.  This procedure always begins with the changes made since the _dbo.uspTrackChangeStart_ procedure was called. 

######Stop Tracking
Execute the _dbo.uspTrackChangeStop_ stored procedure to stop tracking on all tables and the database.

######Uninstall
Execute the _Uninstall.sql_ script to remove the table and stored procedures from the database.

#### Limitations
1. A table must have a primary key for its data to be tracked
2. This tool only supports composite primary keys with three or less columns

#### Roadmap

Feature                                                                     | State
--------------------------------------------------------------------------- | :------------:
Initial release                                                             | ✓
Make delete statements type correct                                         | ✓
Enhance start proc to only operate on new tables                            | ✓
Make the retention period configurable                                      | v3.0

