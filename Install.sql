CREATE TABLE [dbo].[TrackChangeConfig](
	[TrackChangeConfigId] [int] IDENTITY(1,1) NOT NULL,
	[SchemaName] [varchar](100) NOT NULL,
	[TableName] [varchar](100) NOT NULL,
	[IdentityIncrement] [int] NULL,
	[TrackChanges] [bit] NOT NULL,
 CONSTRAINT [PK_TrackChangeConfig] PRIMARY KEY CLUSTERED 
(
	[TrackChangeConfigId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [dbo].[TrackChangeConfig] ADD  CONSTRAINT [DF_TrackChangeTable_TrackChanges]  DEFAULT ((0)) FOR [TrackChanges]
GO

INSERT INTO dbo.TrackChangeConfig (SchemaName, TableName, IdentityIncrement)
SELECT s.name, t.name, CASE WHEN c.column_id IS NULL THEN NULL ELSE 1000 END
FROM sys.tables t INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
LEFT OUTER JOIN sys.identity_columns c ON t.object_id = c.object_id
GO


IF EXISTS ( SELECT * 
            FROM   sysobjects 
            WHERE  id = object_id(N'[dbo].[uspTrackChangeGenerateInsert]') 
                   and OBJECTPROPERTY(id, N'IsProcedure') = 1 )
BEGIN
    DROP PROCEDURE [dbo].[uspTrackChangeGenerateInsert]
END
GO
CREATE PROCEDURE [dbo].[uspTrackChangeGenerateInsert]
(
  @ObjectName nvarchar(261)
, @TargetObjectName nvarchar(261) = NULL
, @OmmitInsertColumnList bit = 0
, @GenerateSingleInsertPerRow bit = 0
, @UseSelectSyntax bit = 0
, @UseColumnAliasInSelect bit = 0
, @FormatCode bit = 1
, @GenerateOneColumnPerLine bit = 0
, @GenerateGo bit = 0
, @PrintGeneratedCode bit = 1
, @TopExpression varchar(max) = NULL
, @SearchCondition varchar(max) = NULL
, @OmmitUnsupportedDataTypes bit = 1
, @PopulateIdentityColumn bit = 0
, @PopulateTimestampColumn bit = 0
, @PopulateComputedColumn bit = 0
, @GenerateProjectInfo bit = 1
, @GenerateSetNoCount bit = 1
, @GenerateStatementTerminator bit = 1
, @ShowWarnings bit = 1
, @Debug bit = 0
)
AS
/*******************************************************************************
Procedure: GenerateInsert (Build 3)
Decription: Generates INSERT statement(s) for data in a table.
Purpose: To regenerate data at another location.
  To script data populated in automated way.
  To script setup data populated in automated/manual way.
Project page: http://github.com/drumsta/sql-generate-insert
Arguments:
  @ObjectName
    Format: [schema_name.]object_name
    Specifies the name of a table or view to generate the INSERT statement(s) for
  @TargetObjectName
    Specifies the name of target table or view to insert into
  @OmmitInsertColumnList
    When 0 then syntax is like INSERT INTO object (column_list)...
    When 1 then syntax is like INSERT INTO object...
  @GenerateSingleInsertPerRow bit = 0
    When 0 then only one INSERT statement is generated for all rows
    When 1 then separate INSERT statement is generated for every row
  @UseSelectSyntax bit = 0
    When 0 then syntax is like INSERT INTO object (column_list) VALUES(...)
    When 1 then syntax is like INSERT INTO object (column_list) SELECT...
  @UseColumnAliasInSelect bit = 0
    Has effect only when @UseSelectSyntax = 1
    When 0 then syntax is like SELECT 'value1','value2'
    When 1 then syntax is like SELECT 'value1' column1,'value2' column2
  @FormatCode bit = 1
    When 0 then no Line Feeds are generated
    When 1 then additional Line Feeds are generated for better readibility
  @GenerateOneColumnPerLine bit = 0
    When 0 then syntax is like SELECT 'value1','value2'...
      or VALUES('value1','value2')...
    When 1 then syntax is like
         SELECT
         'value1'
         ,'value2'
         ...
      or VALUES(
         'value1'
         ,'value2'
         )...
  @GenerateGo bit = 0
    When 0 then no GO commands are generated
    When 1 then GO commands are generated after each INSERT
  @PrintGeneratedCode bit = 1
    When 0 then generated code will be printed using PRINT command
    When 1 then generated code will be selected using SELECT statement 
  @TopExpression varchar(max) = NULL
    When supplied then INSERT statements are generated only for TOP rows
    Format: (expression) [PERCENT]
    Example: @TopExpression='(5)' is equivalent to SELECT TOP (5)
    Example: @TopExpression='(50) PERCENT' is equivalent to SELECT TOP (5) PERCENT
  @SearchCondition varchar(max) = NULL
    When supplied then specifies the search condition for the rows returned by the query
    Format: <search_condition>
    Example: @SearchCondition='column1 != ''test''' is equivalent to WHERE column1 != 'test'
  @OmmitUnsupportedDataTypes bit = 1
    When 0 then error is raised on unsupported data types
    When 1 then columns with unsupported data types are excluded from generation process
  @PopulateIdentityColumn bit = 1
    When 0 then identity columns are excluded from generation process
    When 1 then identity column values are preserved on insertion
  @PopulateTimestampColumn bit = 0
    When 0 then rowversion/timestamp column is inserted using DEFAULT value
    When 1 then rowversion/timestamp column values are preserved on insertion,
      useful when restoring into archive table as varbinary(8) to preserve history
  @PopulateComputedColumn bit = 0
    When 0 then computed columns are excluded from generation process
    When 1 then computed column values are preserved on insertion,
      useful when restoring into archive table as scalar values to preserve history
  @GenerateProjectInfo bit = 1
    When 0 then no spam is generated at all.
    When 1 then short comments are generated, i.e. SP build number and project page.
  @GenerateSetNoCount bit = 1
    When 0 then no SET NOCOUNT ON is generated at the beginning.
    When 1 then SET NOCOUNT ON is generated at the beginning.
  @GenerateStatementTerminator bit = 1
    When 0 then each statement is not separated by semicolon (;).
    When 1 then semicolon (;) is generated at the end of each statement.
  @ShowWarnings bit = 1
    When 0 then no warnings are printed.
    When 1 then warnings are printed if columns with unsupported data types
      have been excluded from generation process
    Has effect only when @OmmitUnsupportedDataTypes = 1
  @Debug bit = 0
    When 0 then no debug information are printed.
    When 1 then constructed SQL statements are printed for later examination

	The MIT License (MIT)

Copyright (c) 2015 Arturas Drumsta

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*******************************************************************************/
BEGIN
SET NOCOUNT ON;

DECLARE @CrLf char(2) = CHAR(13) + CHAR(10);
DECLARE @ColumnName sysname;
DECLARE @DataType sysname;
DECLARE @ColumnList nvarchar(max) = '';
DECLARE @SelectList nvarchar(max) = '';
DECLARE @SelectStatement nvarchar(max) = '';
DECLARE @OmmittedColumnList nvarchar(max) = '';
DECLARE @InsertSql varchar(max) = 'INSERT INTO ' + COALESCE(@TargetObjectName,@ObjectName);
DECLARE @ValuesSql varchar(max) = 'VALUES (';
DECLARE @SelectSql varchar(max) = 'SELECT ';
DECLARE @TableData table (TableRow varchar(max));
DECLARE @Results table (TableRow varchar(max));
DECLARE @TableRow nvarchar(max);
DECLARE @RowNo int;

IF PARSENAME(@ObjectName,3) IS NOT NULL
  OR PARSENAME(@ObjectName,4) IS NOT NULL
BEGIN
  RAISERROR('Server and database names are not allowed to specify in @ObjectName parameter. Required format is [schema_name.]object_name',16,1);
  RETURN -1;
END

IF OBJECT_ID(@ObjectName,N'U') IS NULL
  AND OBJECT_ID(@ObjectName,N'V') IS NULL
BEGIN
  RAISERROR(N'User table or view %s not found or insuficient permission to query the table or view.',16,1,@ObjectName);
  RETURN -1;
END

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = PARSENAME(@ObjectName,1) AND TABLE_TYPE IN ('BASE TABLE','VIEW') AND (TABLE_SCHEMA = PARSENAME(@ObjectName,2) OR PARSENAME(@ObjectName,2) IS NULL))
BEGIN
  RAISERROR(N'User table or view %s not found or insuficient permission to query the table or view.',16,1,@ObjectName);
  RETURN -1;
END

DECLARE ColumnCursor CURSOR LOCAL FAST_FORWARD FOR
SELECT c.name ColumnName
,TYPE_NAME(c.system_type_id) DataType
FROM sys.objects o
  INNER JOIN sys.columns c ON c.object_id = o.object_id
WHERE o.type IN (N'U',N'V') -- USER_TABLE,VIEW
  AND (o.object_id = OBJECT_ID(@ObjectName)
    OR o.name = @ObjectName)
  AND (COLUMNPROPERTY(c.object_id,c.name,'IsIdentity') != 1
    OR @PopulateIdentityColumn = 1)
  AND (COLUMNPROPERTY(c.object_id,c.name,'IsComputed') != 1
    OR @PopulateComputedColumn = 1)
ORDER BY COLUMNPROPERTY(c.object_id,c.name,'ordinal') -- ORDINAL_POSITION
FOR READ ONLY
;
OPEN ColumnCursor;
FETCH NEXT FROM ColumnCursor INTO @ColumnName,@DataType;

WHILE @@FETCH_STATUS = 0
BEGIN
  -- Handle different data types
  DECLARE @ColumnExpression varchar(max);
  SET @ColumnExpression = 
    CASE
    WHEN @DataType IN ('char','varchar','text','uniqueidentifier')
    THEN 'ISNULL(''''''''+REPLACE(CONVERT(varchar(max),'+  QUOTENAME(@ColumnName) + '),'''''''','''''''''''')+'''''''',''NULL'') COLLATE database_default'
      
    WHEN @DataType IN ('nchar','nvarchar','sysname','ntext','sql_variant','xml')
    THEN 'ISNULL(''N''''''+REPLACE(CONVERT(nvarchar(max),'+  QUOTENAME(@ColumnName) + '),'''''''','''''''''''')+'''''''',''NULL'') COLLATE database_default'
      
    WHEN @DataType IN ('int','bigint','smallint','tinyint','decimal','numeric','bit')
    THEN 'ISNULL(CONVERT(varchar(max),'+  QUOTENAME(@ColumnName) + '),''NULL'') COLLATE database_default'
      
    WHEN @DataType IN ('float','real','money','smallmoney')
    THEN 'ISNULL(CONVERT(varchar(max),'+  QUOTENAME(@ColumnName) + ',2),''NULL'') COLLATE database_default'
      
    WHEN @DataType IN ('datetime','smalldatetime','date','time','datetime2','datetimeoffset')
    THEN '''CONVERT('+@DataType+',''+ISNULL(''''''''+CONVERT(varchar(max),'+  QUOTENAME(@ColumnName) + ',121)+'''''''',''NULL'') COLLATE database_default' + '+'',121)'''

    WHEN @DataType IN ('rowversion','timestamp')
    THEN
      CASE WHEN @PopulateTimestampColumn = 1
      THEN '''CONVERT(varbinary(max),''+ISNULL(''''''''+CONVERT(varchar(max),CONVERT(varbinary(max),'+  QUOTENAME(@ColumnName) + '),1)+'''''''',''NULL'') COLLATE database_default' + '+'',1)'''
      ELSE '''NULL''' END

    WHEN @DataType IN ('binary','varbinary','image')
    THEN '''CONVERT(varbinary(max),''+ISNULL(''''''''+CONVERT(varchar(max),CONVERT(varbinary(max),'+  QUOTENAME(@ColumnName) + '),1)+'''''''',''NULL'') COLLATE database_default' + '+'',1)'''

    WHEN @DataType IN ('geography')
    -- convert geography to text: ?? column.STAsText();
    -- convert text to geography: ?? geography::STGeomFromText('LINESTRING(-122.360 47.656, -122.343 47.656 )', 4326);
    THEN NULL

    ELSE NULL END;

  IF @ColumnExpression IS NULL
    AND @OmmitUnsupportedDataTypes != 1
  BEGIN
    RAISERROR(N'Datatype %s is not supported. Use @OmmitUnsupportedDataTypes to exclude unsupported columns.',16,1,@DataType);
    RETURN -1;
  END

  IF @ColumnExpression IS NULL
  BEGIN
    SET @OmmittedColumnList = @OmmittedColumnList
      + CASE WHEN @OmmittedColumnList != '' THEN '; ' ELSE '' END
      + 'column ' + QUOTENAME(@ColumnName)
      + ', datatype ' + @DataType;
  END

  IF @ColumnExpression IS NOT NULL
  BEGIN
    SET @ColumnList = @ColumnList
      + CASE WHEN @ColumnList != '' THEN ',' ELSE '' END
      + QUOTENAME(@ColumnName)
      + CASE WHEN @GenerateOneColumnPerLine = 1 THEN @CrLf ELSE '' END;
  
    SET @SelectList = @SelectList
      + CASE WHEN @SelectList != '' THEN '+'',''+' + @CrLf ELSE '' END
      + @ColumnExpression
      + CASE WHEN @UseColumnAliasInSelect = 1 AND @UseSelectSyntax = 1 THEN '+'' ' + QUOTENAME(@ColumnName) + '''' ELSE '' END
      + CASE WHEN @GenerateOneColumnPerLine = 1 THEN '+CHAR(13)+CHAR(10)' ELSE '' END;
  END

  FETCH NEXT FROM ColumnCursor INTO @ColumnName,@DataType;
END

CLOSE ColumnCursor;
DEALLOCATE ColumnCursor;

IF NULLIF(@ColumnList,'') IS NULL
BEGIN
  RAISERROR(N'No columns to select.',16,1);
  RETURN -1;
END

IF @Debug = 1
BEGIN
  PRINT '--Column list';
  PRINT @ColumnList;
END

IF NULLIF(@OmmittedColumnList,'') IS NOT NULL
  AND @ShowWarnings = 1
BEGIN
  PRINT(N'--*************************');
  PRINT(N'--WARNING: The following columns have been ommitted because of unsupported datatypes: ' + @OmmittedColumnList);
  PRINT(N'--*************************');
END

IF @GenerateSingleInsertPerRow = 1
BEGIN
  SET @SelectList = 
    '''' + @InsertSql + '''+' + @CrLf
    + CASE WHEN @FormatCode = 1
      THEN 'CHAR(13)+CHAR(10)+' + @CrLf
      ELSE ''' ''+'
      END
    + CASE WHEN @OmmitInsertColumnList = 1
      THEN ''
      ELSE '''(' + @ColumnList + ')''+' + @CrLf
      END
    + CASE WHEN @FormatCode = 1
      THEN 'CHAR(13)+CHAR(10)+' + @CrLf
      ELSE ''' ''+'
      END
    + CASE WHEN @UseSelectSyntax = 1
      THEN '''' + @SelectSql + '''+'
      ELSE '''' + @ValuesSql + '''+'
      END
    + @CrLf
    + @SelectList
    + CASE WHEN @UseSelectSyntax = 1
      THEN ''
      ELSE '+' + @CrLf + ''')'''
      END
    + CASE WHEN @GenerateStatementTerminator = 1
      THEN '+'';'''
      ELSE ''
      END
    + CASE WHEN @GenerateGo = 1
      THEN '+' + @CrLf + 'CHAR(13)+CHAR(10)+' + @CrLf + '''GO'''
      ELSE ''
      END
  ;
END ELSE BEGIN
  SET @SelectList =
    CASE WHEN @UseSelectSyntax = 1
      THEN '''' + @SelectSql + '''+'
      ELSE '''(''+'
      END
    + @CrLf
    + @SelectList
    + CASE WHEN @UseSelectSyntax = 1
      THEN ''
      ELSE '+' + @CrLf + ''')'''
      END
  ;
END

SET @SelectStatement = 'SELECT'
  + CASE WHEN NULLIF(@TopExpression,'') IS NOT NULL
    THEN ' TOP ' + @TopExpression
    ELSE '' END
  + @CrLf + @SelectList + @CrLf
  + 'FROM ' + @ObjectName
  + CASE WHEN NULLIF(@SearchCondition,'') IS NOT NULL
    THEN @CrLf + 'WHERE ' + @SearchCondition
    ELSE '' END
;

IF @Debug = 1
BEGIN
  PRINT '--Select statement';
  PRINT @SelectStatement;
END

INSERT INTO @TableData
EXECUTE (@SelectStatement);

IF @GenerateProjectInfo = 1
BEGIN
  INSERT INTO @Results
  SELECT '--INSERTs generated by GenerateInsert (Build 3)'
  UNION SELECT '--Project page: http://github.com/drumsta/sql-generate-insert'
END

IF @GenerateSetNoCount = 1
BEGIN
  INSERT INTO @Results
  SELECT 'SET NOCOUNT ON'
END

IF @PopulateIdentityColumn = 1
BEGIN
  INSERT INTO @Results
  SELECT 'SET IDENTITY_INSERT ' + COALESCE(@TargetObjectName,@ObjectName) + ' ON'
END

IF @GenerateSingleInsertPerRow = 1
BEGIN
  INSERT INTO @Results
  SELECT TableRow
  FROM @TableData
END ELSE BEGIN
  IF @FormatCode = 1
  BEGIN
    INSERT INTO @Results
    SELECT @InsertSql;

    IF @OmmitInsertColumnList != 1
    BEGIN
      INSERT INTO @Results
      SELECT '(' + @ColumnList + ')';
    END

    IF @UseSelectSyntax != 1
    BEGIN
      INSERT INTO @Results
      SELECT 'VALUES';
    END
  END ELSE BEGIN
    INSERT INTO @Results
    SELECT @InsertSql
      + CASE WHEN @OmmitInsertColumnList = 1 THEN '' ELSE ' (' + @ColumnList + ')' END
      + CASE WHEN @UseSelectSyntax = 1 THEN '' ELSE ' VALUES' END
  END

  SET @RowNo = 0;
  DECLARE DataCursor CURSOR LOCAL FAST_FORWARD FOR
  SELECT TableRow
  FROM @TableData
  FOR READ ONLY
  ;
  OPEN DataCursor;
  FETCH NEXT FROM DataCursor INTO @TableRow;

  WHILE @@FETCH_STATUS = 0
  BEGIN
    SET @RowNo = @RowNo + 1;

    INSERT INTO @Results
    SELECT
      CASE WHEN @UseSelectSyntax = 1
      THEN CASE WHEN @RowNo > 1 THEN 'UNION' + CASE WHEN @FormatCode = 1 THEN @CrLf ELSE ' ' END ELSE '' END
      ELSE CASE WHEN @RowNo > 1 THEN ',' ELSE ' ' END END
      + @TableRow;

    FETCH NEXT FROM DataCursor INTO @TableRow;
  END

  CLOSE DataCursor;
  DEALLOCATE DataCursor;

  IF @GenerateStatementTerminator = 1
  BEGIN
    INSERT INTO @Results
    SELECT ';';
  END

  IF @GenerateGo = 1
  BEGIN
    INSERT INTO @Results
    SELECT 'GO';
  END
END

IF @PopulateIdentityColumn = 1
BEGIN
  INSERT INTO @Results
  SELECT 'SET IDENTITY_INSERT ' + COALESCE(@TargetObjectName,@ObjectName) + ' OFF'
END

IF @FormatCode = 1
BEGIN
  INSERT INTO @Results
  SELECT ''; -- An empty line at the end
END

IF @PrintGeneratedCode = 1
BEGIN
  DECLARE ResultsCursor CURSOR LOCAL FAST_FORWARD FOR
  SELECT TableRow
  FROM @Results
  FOR READ ONLY
  ;
  OPEN ResultsCursor;
  FETCH NEXT FROM ResultsCursor INTO @TableRow;

  WHILE @@FETCH_STATUS = 0
  BEGIN
    PRINT(@TableRow);

    FETCH NEXT FROM ResultsCursor INTO @TableRow;
  END

  CLOSE ResultsCursor;
  DEALLOCATE ResultsCursor;
END ELSE BEGIN
  SELECT *
  FROM @Results;
END

END

GO


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
	SET @DB = db_name()

	PRINT 'activating database level'
	EXEC('ALTER DATABASE [' + @DB + '] SET CHANGE_TRACKING = ON (CHANGE_RETENTION = 365 DAYS, AUTO_CLEANUP = ON);')
	
	DECLARE cur CURSOR FOR
		SELECT SchemaName, TableName FROM dbo.TrackChangeConfig WHERE TrackChanges = 1
	OPEN cur
	FETCH NEXT FROM cur INTO @Schema, @Table
	WHILE @@FETCH_STATUS = 0 BEGIN
		PRINT 'activating [' + @Schema + '].[' + @Table + ']'
		EXEC('ALTER TABLE [' + @Schema + '].[' + @Table + '] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF);')
		FETCH NEXT FROM cur INTO @Schema, @Table
	END
	CLOSE cur
	DEALLOCATE cur
END
GO

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
