CREATE PROCEDURE dbo.uspTrackChangeStop
AS
BEGIN
		
	DECLARE @DB varchar(100), @Schema varchar(100), @Table varchar(100) 
	SET @DB = db_name()

	DECLARE cur CURSOR FOR
		SELECT SchemaName, TableName FROM dbo.TrackChangeTable WHERE TrackChanges = 1
	OPEN cur
	FETCH NEXT FROM cur INTO @schema, @table
	WHILE @@FETCH_STATUS = 0 BEGIN
		PRINT 'deactivating [' + @schema + '].[' + @table + ']'
		EXEC('ALTER TABLE [' + @schema + '].[' + @table + '] DISABLE CHANGE_TRACKING;')
		
		FETCH NEXT FROM cur INTO @schema, @table
	END
	CLOSE cur
	DEALLOCATE cur

	PRINT 'deactivating database level'
	EXEC('ALTER DATABASE [' + @db + '] SET CHANGE_TRACKING = OFF;')
	
END
GO
