IF EXISTS ( SELECT * 
            FROM   sysobjects 
            WHERE  id = object_id(N'[dbo].[uspTrackChangeStart]') 
                   and OBJECTPROPERTY(id, N'IsProcedure') = 1 )
BEGIN
    DROP PROCEDURE [dbo].[uspTrackChangeStart]
END
GO
CREATE PROCEDURE [dbo].[uspTrackChangeStart]
AS
BEGIN
		
	DECLARE @DB varchar(100), @Schema varchar(100), @Table varchar(100)
	DECLARE @IdentityIncrement int, @IdentitySeed int, @IdentityValue int
	DECLARE @FullTable varchar(205)

	SET @DB = DB_NAME();
	
	IF EXISTS (SELECT * 
		FROM sys.change_tracking_databases 
		WHERE database_id = DB_ID(@DB)) BEGIN
		
		PRINT 'tracking already enabled on the database'
	END ELSE BEGIN
		PRINT 'activating database level'
		EXEC('ALTER DATABASE [' + @DB + '] SET CHANGE_TRACKING = ON (CHANGE_RETENTION = 365 DAYS, AUTO_CLEANUP = ON);')
	END

	DECLARE cur CURSOR FOR
		SELECT SchemaName, TableName, IdentityIncrement FROM dbo.TrackChangeConfig WHERE TrackChanges = 1 ORDER BY SchemaName, TableName
	OPEN cur
	FETCH NEXT FROM cur INTO @Schema, @Table, @IdentityIncrement
	WHILE @@FETCH_STATUS = 0 BEGIN
		
		SET @FullTable = '[' + @Schema + '].[' + @Table + ']';

		IF EXISTS (SELECT * FROM sys.change_tracking_tables WHERE object_id = OBJECT_ID(@FullTable)) BEGIN
			PRINT 'tracking already enabled on ' + @FullTable
		END ELSE BEGIN
			IF @IdentityIncrement > 0 BEGIN
				SET @IdentitySeed = IDENT_SEED(@FullTable);
				SET @IdentityValue = IDENT_CURRENT(@FullTable);
				SET @IdentityValue = @IdentityIncrement + CASE WHEN @IdentitySeed > @IdentityValue THEN @IdentitySeed ELSE @IdentityValue END;
				PRINT 'reseeding ' + @FullTable + ' to ' + CONVERT(VARCHAR(50), @IdentityValue)
				DBCC CHECKIDENT(@FullTable, RESEED, @IdentityValue) WITH NO_INFOMSGS;
			END
			PRINT 'activating ' + @FullTable
			EXEC('ALTER TABLE ' + @FullTable + ' ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF);')
		END
		
		FETCH NEXT FROM cur INTO @Schema, @Table, @IdentityIncrement
	END
	CLOSE cur
	DEALLOCATE cur
END
GO
