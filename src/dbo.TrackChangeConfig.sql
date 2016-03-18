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
