IF EXISTS ( SELECT * 
            FROM   sysobjects 
            WHERE  id = object_id(N'[dbo].[uspTrackChangeStop]') 
                   and OBJECTPROPERTY(id, N'IsProcedure') = 1 )
BEGIN
    DROP PROCEDURE [dbo].[uspTrackChangeStop]
END
GO
CREATE PROCEDURE [dbo].[uspTrackChangeStop]
AS
BEGIN
		
	DECLARE @DB varchar(100), @Schema varchar(100), @Table varchar(100) 
	SET @DB = db_name()

	DECLARE cur CURSOR FOR
		SELECT s.name, t.name
		FROM sys.tables t INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
		INNER JOIN sys.change_tracking_tables ct ON t.object_id = ct.object_id
	OPEN cur
	FETCH NEXT FROM cur INTO @Schema, @Table
	WHILE @@FETCH_STATUS = 0 BEGIN
		PRINT 'deactivating [' + @Schema + '].[' + @Table + ']'
		EXEC('ALTER TABLE [' + @Schema + '].[' + @Table + '] DISABLE CHANGE_TRACKING;')
		
		FETCH NEXT FROM cur INTO @Schema, @Table
	END
	CLOSE cur
	DEALLOCATE cur

	PRINT 'deactivating database level'
	EXEC('ALTER DATABASE [' + @DB + '] SET CHANGE_TRACKING = OFF;')
	
END
GO