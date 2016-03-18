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
	DECLARE @PK1Val varchar(100), @PK2Val varchar(100) , @PK3Val varchar(100) 
	DECLARE @SQL varchar(4000)
	DECLARE @FullTable varchar(200)
	DECLARE @SearchCondition varchar(500), @PopulateIdentity bit
	CREATE TABLE #PKVals (PKVal1 varchar(500), PKVal2 varchar(500), PKVal3 varchar(500))

	DECLARE cur cursor for
		SELECT SchemaName, TableName FROM dbo.TrackChangeConfig WHERE TrackChanges = 1
	open cur
	fetch next from cur into @Schema, @Table
	while @@FETCH_STATUS = 0 begin
	
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

		
		DELETE FROM #PKVals
		set @SQL = 'insert into #PKVals (PKVal1, PKVal2, PKVal3) select ' + @PK1 + ', ' + COALESCE(@PK2, '1') + ', ' + COALESCE(@PK3, '1')
		set @SQL = @SQL + ' FROM CHANGETABLE(CHANGES ' + @FullTable + ', 0) AS CT'
		--print @SQL
		exec(@SQL)
	
	
		if exists (select top 1 * from #PKVals) begin
			DECLARE change cursor for 
				select PKVal1, PKVal2, PKVal3 from #PKVals
			open change
			fetch next from change into @PK1Val, @PK2Val, @PK3Val
			while @@FETCH_STATUS = 0 begin
				--write delete statement
				set @SQL = 'DELETE FROM ' + @FullTable + ' WHERE ' + @PK1 + ' = ''' + @PK1Val + ''''
				if @PK2 is not null begin
					set @SQL = @SQL + ' AND ' + @PK2 + ' = ''' + @PK2Val + ''''
				end
				if @PK3 is not null begin
					set @SQL = @SQL + ' AND ' + @PK3 + ' = ''' + @PK3Val + ''''
				end
				print @SQL
				fetch next from change into @PK1Val, @PK2Val, @PK3Val
			end
			close change
			deallocate change

			-- generate inserts
			if @PK3 is not null begin
				set @SearchCondition = 'EXISTS (SELECT * FROM CHANGETABLE(CHANGES ' + @FullTable + ', 0) AS CT WHERE ' + @FullTable + '.' + @PK1 + ' = CT.' + @PK1 + ' AND ' + @FullTable + '.' + @PK2 + ' = CT.' + @PK2 + ' AND ' + @FullTable + '.' + @PK3 + ' = CT.' + @PK3 + ')'
			end else if @PK2 is not null begin
				set @SearchCondition = 'EXISTS (SELECT * FROM CHANGETABLE(CHANGES ' + @FullTable + ', 0) AS CT WHERE ' + @FullTable + '.' + @PK1 + ' = CT.' + @PK1 + ' AND ' + @FullTable + '.' + @PK2 + ' = CT.' + @PK2 + ')'
			end else begin
				set @SearchCondition = @PK1 + ' IN (SELECT ' + @PK1 + ' FROM CHANGETABLE(CHANGES ' + @FullTable + ', 0) AS CT)'
			end
			print @SearchCondition

		
			exec uspTrackChangeGenerateInsert
				@ObjectName = @FullTable,
				@GenerateSingleInsertPerRow = 1, 
				@GenerateProjectInfo = 0,
				@PopulateIdentityColumn = @PopulateIdentity, 
				@OmmitUnsupportedDataTypes = 0,
				@GenerateSetNoCount = 0,
				@SearchCondition = @SearchCondition

			
		end
		
		fetch next from cur into @Schema, @Table
	end
	close cur
	deallocate cur

	drop table #PKVals	
	
END
GO
