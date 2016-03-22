IF EXISTS ( SELECT * 
            FROM   sysobjects 
            WHERE  id = object_id(N'[dbo].[uspTrackChangeExtract]') 
                   and OBJECTPROPERTY(id, N'IsProcedure') = 1 )
BEGIN
    DROP PROCEDURE [dbo].[uspTrackChangeExtract]
END
GO
CREATE PROCEDURE [dbo].[uspTrackChangeExtract]
AS
BEGIN
	SET NOCOUNT ON

	DECLARE @DB varchar(100), @Schema varchar(100), @Table varchar(100)
	DECLARE @PK1 varchar(100), @PK2 varchar(100), @PK3 varchar(100) 
	DECLARE @PK1Val varchar(max), @PK2Val varchar(max) , @PK3Val varchar(max) 
	DECLARE @PK1Type varchar(100), @PK2Type varchar(100), @PK3Type varchar(100) 
	DECLARE @SQL varchar(4000)
	DECLARE @FullTable varchar(500)
	DECLARE @SearchCondition varchar(4000), @PopulateIdentity bit

	CREATE TABLE #PKVals (PKVal1 varchar(max), PKVal2 varchar(max), PKVal3 varchar(max))

	-- set up transaction
	PRINT 'BEGIN TRANSACTION;'
	PRINT 'BEGIN TRY'

	-- disable FKs
	PRINT 'EXEC sp_msforeachtable "ALTER TABLE ? NOCHECK CONSTRAINT all";'
	PRINT ''

	DECLARE cur CURSOR FOR
		SELECT SchemaName, TableName FROM dbo.TrackChangeConfig WHERE TrackChanges = 1
	OPEN cur
	FETCH NEXT FROM cur INTO @Schema, @Table
	WHILE @@FETCH_STATUS = 0 BEGIN
	
		SET @FullTable = '[' + @Schema + '].[' + @Table + ']'
	
		IF EXISTS(select column_id FROM sys.identity_columns c WHERE object_id = OBJECT_ID(@FullTable)) BEGIN
			SET @PopulateIdentity = 1
		END ELSE BEGIN
			SET @PopulateIdentity = 0
		END
		--print @FullTable
	
		-- determine PK names
		SELECT @PK1 = PK1, @PK2 = PK2, @PK3 = PK3
		FROM
		(
			SELECT 
			c.Name, 'PK' + convert(varchar(10), ic.key_ordinal) AS KeyPart
			FROM sys.key_constraints k 
			INNER JOIN sys.tables t ON t.object_id = k.parent_object_id
			INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
			INNER JOIN sys.index_columns ic ON ic.object_id = t.object_id AND ic.index_id = k.unique_index_id
			INNER JOIN sys.columns c ON c.object_id = t.object_id AND c.column_id = ic.column_id
			WHERE k.type = 'PK'
			AND s.name = @Schema
			AND t.name = @Table
		) d
		pivot
		(
		  MAX(Name)
		  FOR KeyPart IN (PK1, PK2, PK3)
		) piv

		-- get the types for the PKs
		SELECT @PK1Type = ty.name
		FROM sys.tables t
		INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
		INNER JOIN sys.columns c ON t.object_id = c.object_id
		INNER JOIN sys.types ty ON c.system_type_id = ty.system_type_id
		WHERE s.name = @Schema
		AND t.name = @Table
		AND c.name = @PK1
		
		SELECT @PK2Type = ty.name
		FROM sys.tables t
		INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
		INNER JOIN sys.columns c ON t.object_id = c.object_id
		INNER JOIN sys.types ty ON c.system_type_id = ty.system_type_id
		WHERE s.name = @Schema
		AND t.name = @Table
		AND c.name = @PK2

		SELECT @PK3Type = ty.name
		FROM sys.tables t
		INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
		INNER JOIN sys.columns c ON t.object_id = c.object_id
		INNER JOIN sys.types ty ON c.system_type_id = ty.system_type_id
		WHERE s.name = @Schema
		AND t.name = @Table
		AND c.name = @PK3

		DELETE FROM #PKVals
		SET @SQL = 'insert into #PKVals (PKVal1, PKVal2, PKVal3) select ' + @PK1 + ', ' + COALESCE(@PK2, '1') + ', ' + COALESCE(@PK3, '1')
		SET @SQL = @SQL + ' FROM CHANGETABLE(CHANGES ' + @FullTable + ', 0) AS CT'
		--print @SQL
		EXEC(@SQL)
	
		IF EXISTS (SELECT TOP 1 * FROM #PKVals) BEGIN
			DECLARE change CURSOR FOR
				SELECT PKVal1, PKVal2, PKVal3 FROM #PKVals
			OPEN change
			FETCH NEXT FROM change INTO @PK1Val, @PK2Val, @PK3Val
			WHILE @@FETCH_STATUS = 0 BEGIN
				--write delete statement
				SET @SQL = 'DELETE FROM ' + @FullTable + ' WHERE ' + @PK1 + ' = '
				SET @SQL = @SQL + CASE 
					WHEN @PK1Type IN ('int','bigint','smallint','tinyint','decimal','numeric','bit') THEN @PK1Val
					ELSE '''' + REPLACE(@PK1Val, '''', '''''') + ''''
				END
				IF @PK2 IS NOT NULL BEGIN
					SET @SQL = @SQL + ' AND ' + @PK2 + ' = '
					SET @SQL = @SQL + CASE 
						WHEN @PK2Type IN ('int','bigint','smallint','tinyint','decimal','numeric','bit') THEN @PK2Val
						ELSE '''' + REPLACE(@PK2Val, '''', '''''') + ''''
					END
				END
				IF @PK3 IS NOT NULL BEGIN
					SET @SQL = @SQL + ' AND ' + @PK3 + ' = '
					SET @SQL = @SQL + CASE 
						WHEN @PK3Type IN ('int','bigint','smallint','tinyint','decimal','numeric','bit') THEN @PK3Val
						ELSE '''' + REPLACE(@PK3Val, '''', '''''') + ''''
					END
				END
				PRINT @SQL
				FETCH NEXT FROM change INTO @PK1Val, @PK2Val, @PK3Val
			END
			CLOSE change
			DEALLOCATE change

			-- generate inserts
			IF @PK3 IS NOT NULL BEGIN
				SET @SearchCondition = 'EXISTS (SELECT * FROM CHANGETABLE(CHANGES ' + @FullTable + ', 0) AS CT WHERE ' + @FullTable + '.' + @PK1 + ' = CT.' + @PK1 + ' AND ' + @FullTable + '.' + @PK2 + ' = CT.' + @PK2 + ' AND ' + @FullTable + '.' + @PK3 + ' = CT.' + @PK3 + ')'
			END ELSE IF @PK2 is not null BEGIN
				SET @SearchCondition = 'EXISTS (SELECT * FROM CHANGETABLE(CHANGES ' + @FullTable + ', 0) AS CT WHERE ' + @FullTable + '.' + @PK1 + ' = CT.' + @PK1 + ' AND ' + @FullTable + '.' + @PK2 + ' = CT.' + @PK2 + ')'
			END ELSE BEGIN
				SET @SearchCondition = @PK1 + ' IN (SELECT ' + @PK1 + ' FROM CHANGETABLE(CHANGES ' + @FullTable + ', 0) AS CT)'
			END
			--print @SearchCondition

		
			EXEC uspTrackChangeGenerateInsert
				@ObjectName = @FullTable,
				@GenerateSingleInsertPerRow = 1, 
				@GenerateProjectInfo = 0,
				@PopulateIdentityColumn = @PopulateIdentity, 
				@OmmitUnsupportedDataTypes = 0,
				@GenerateSetNoCount = 0,
				@SearchCondition = @SearchCondition
		END
		
		FETCH NEXT FROM cur INTO @Schema, @Table
	END
	CLOSE cur
	DEALLOCATE cur

	DROP TABLE #PKVals	
	
	-- enable FKs
	PRINT 'EXEC sp_msforeachtable "ALTER TABLE ? WITH CHECK CHECK CONSTRAINT all"';
	
	-- handle transaction
	PRINT 'END TRY'
	PRINT 'BEGIN CATCH'
	PRINT '	SELECT ERROR_NUMBER() AS ErrorNumber,ERROR_SEVERITY() AS ErrorSeverity,ERROR_STATE() AS ErrorState,ERROR_PROCEDURE() AS ErrorProcedure,ERROR_LINE() AS ErrorLine,ERROR_MESSAGE() AS ErrorMessage;'
	PRINT '	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;'
	PRINT 'END CATCH'
	PRINT 'IF @@TRANCOUNT > 0 COMMIT TRANSACTION;'
	
END
GO
