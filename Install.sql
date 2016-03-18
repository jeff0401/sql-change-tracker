CREATE TABLE [dbo].[TrackChangeTable](
	[TrackChangeTableId] [int] IDENTITY(1,1) NOT NULL,
	[SchemaName] [varchar](100) NOT NULL,
	[TableName] [varchar](100) NOT NULL,
	[IdentityIncrement] [int] NULL,
	[TrackChanges] [bit] NOT NULL,
 CONSTRAINT [PK_TrackChangeTable] PRIMARY KEY CLUSTERED 
(
	[TrackChangeTableId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [dbo].[TrackChangeTable] ADD  CONSTRAINT [DF_TrackChangeTable_TrackChanges]  DEFAULT ((0)) FOR [TrackChanges]
GO

INSERT INTO dbo.TrackChangeTable (SchemaName, TableName, IdentityIncrement)
SELECT s.name, t.name, CASE WHEN c.column_id IS NULL THEN NULL ELSE 1000 END
FROM sys.tables t INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
LEFT OUTER JOIN sys.identity_columns c ON t.object_id = c.object_id
GO

CREATE PROCEDURE dbo.uspTrackChangeStart
AS
BEGIN
		
	DECLARE @DB varchar(100), @Schema varchar(100), @Table varchar(100) 
	SET @DB = db_name()

	PRINT 'activating database level'
	EXEC('ALTER DATABASE [' + @DB + '] SET CHANGE_TRACKING = ON (CHANGE_RETENTION = 365 DAYS, AUTO_CLEANUP = ON);')
	
	DECLARE cur CURSOR FOR
		SELECT SchemaName, TableName FROM dbo.TrackChangeTable WHERE TrackChanges = 1
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


/*

select * from TrackChangeTable

*/
