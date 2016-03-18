CREATE PROCEDURE dbo.uspTrackChangeStart
AS
BEGIN
		
	DECLARE @DB varchar(100), @Schema varchar(100), @Table varchar(100) 
	SET @DB = db_name()

	PRINT 'activating database level'
	EXEC('ALTER DATABASE [' + @DB + '] SET CHANGE_TRACKING = ON (CHANGE_RETENTION = 365 DAYS, AUTO_CLEANUP = ON);')
	
	DECLARE cur CURSOR FOR
		SELECT SchemaName, TableName FROM dbo.TrackChangeConfig WHERE TrackChanges = 1
	OPEN cur
	FETCH NEXT FROM cur INTO @schema, @table
	WHILE @@FETCH_STATUS = 0 BEGIN
		PRINT 'activating [' + @schema + '].[' + @table + ']'
		EXEC('ALTER TABLE [' + @schema + '].[' + @table + '] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF);')
		FETCH NEXT FROM cur INTO @schema, @table
	END
	CLOSE cur
	DEALLOCATE cur
END
GO
