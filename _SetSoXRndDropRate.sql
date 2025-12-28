IF EXISTS (SELECT * FROM sys.types WHERE is_table_type = 1 AND name = 'SoXRefDropItemGroupTable' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    DROP TYPE dbo.SoXRefDropItemGroupTable;
END
GO
CREATE TYPE SoXRefDropItemGroupTable AS TABLE
(
    RefItemID INT NOT NULL,
    CodeName128 VARCHAR(129) NOT NULL,
	RequiredLevel INT NOT NULL,
	DropGroup VARCHAR(129) NOT NULL,
    ProbGroup INT NOT NULL,
    Race CHAR(2) NOT NULL,
	RefItemGroupID INT NOT NULL
)
GO
IF EXISTS (SELECT * FROM sys.types WHERE is_table_type = 1 AND name = 'SoXMobTableType' AND schema_id = SCHEMA_ID('dbo'))
BEGIN
    DROP TYPE dbo.SoXMobTableType;
END
GO
CREATE TYPE SoXMobTableType AS TABLE
(
    RefMonsterID INT NOT NULL,
    CodeName128 VARCHAR(129) NOT NULL,
    MonLevel TINYINT NOT NULL,
	DropForRace VARCHAR(129) NOT NULL
)
GO
IF EXISTS (SELECT * FROM sys.procedures WHERE [name] = '_SetSoXRndDropRate')
BEGIN
	DROP PROCEDURE _SetSoXRndDropRate
END
GO
CREATE PROCEDURE _SetSoXRndDropRate
	@SealOfStarDropProbabilityStart REAL,
	@SealOfStarDropProbabilityEnd REAL,
	@SealOfMoonDropProbabilityStart REAL,
	@SealOfMoonDropProbabilityEnd REAL,
	@SealOfSunDropProbabilityStart REAL,
	@SealOfSunDropProbabilityEnd REAL,
	@MonLevelMax INT
AS
BEGIN TRY
	BEGIN TRAN

	DECLARE @Items SoXRefDropItemGroupTable
	DECLARE @MaxRefItemGroupID INT = (SELECT MAX(RefItemGroupID) FROM _RefDropItemGroup)

	INSERT INTO @Items
	SELECT 
		RefItemID,
		CodeName128,
		RequiredLevel,
		'ITEM_' + Race + '_D' + RIGHT('0' + CAST(ItemDegree AS varchar(2)), 2) + '_' + Rarity + '_DROPGROUP' AS DropGroup,
		ProbGroup,
		Race,
		CASE 
			WHEN Race = 'CH' THEN @MaxRefItemGroupID + ((ProbGroup - 1) * 2) + 1
			WHEN Race = 'EU' THEN @MaxRefItemGroupID + ((ProbGroup - 1) * 2) + 2
		END AS RefItemGroupID
	FROM
	(
		SELECT
			ROC.ID AS RefItemID,
			CodeName128,
			ITM.ItemClass AS ProbGroup,
			CASE Country
				WHEN 0 THEN 'CH'
				WHEN 1 THEN 'EU'
			END AS Race,
			CASE 
				WHEN ItemClass % 3 = 1 THEN 'SOS'
				WHEN ItemClass % 3 = 2 THEN 'SOM'
				WHEN ItemClass % 3 = 0 THEN 'SUN'
			END AS Rarity,
			(ITM.ItemClass - 1) / 3 + 1 AS ItemDegree,
			ReqLevel1 AS RequiredLevel
		FROM 
			_RefObjCommon ROC INNER JOIN _RefObjItem ITM ON ROC.Link = ITM.ID
		WHERE 
			[Service] = 1 AND
			TypeID1 = 3 AND 
			Rarity = 2 AND ReqLevel1 BETWEEN 1 AND 110 AND
			CodeName128 NOT LIKE '%_EVENT_%' AND
			CodeName128 NOT LIKE '%_BASIC' AND
			CodeName128 NOT LIKE '%_HONOR'
	) AS TEMP
		ORDER BY 
			RequiredLevel, RefItemGroupID ASC

	-- RefDropItemGroup
	INSERT INTO _RefDropItemGroup ([Service], RefItemGroupID, CodeName128, RefItemID, SelectRatio, RefMagicGroupID)
	SELECT 
		1 AS [Service],
		RefItemGroupID,
		DropGroup AS CodeName128,
		RefItemID,
		CAST(1 AS REAL) / (SELECT COUNT(*) FROM @Items WHERE RefItemGroupID = I.RefItemGroupID) AS SelectRatio,
		0 AS RefMagicGroupID
	FROM @Items I
	ORDER BY RefItemGroupID


	DECLARE @Mobs SoXMobTableType

	INSERT INTO @Mobs (RefMonsterID, CodeName128, MonLevel, DropForRace)
	SELECT 
		ROC.ID,
		CodeName128,
		[Lvl],
		'CH'
	FROM 
		_RefObjCommon ROC INNER JOIN 
		_RefObjChar CHR ON ROC.Link = CHR.ID 
	WHERE
		[Service] = 1 AND
		[Lvl] <= 42 AND
		(
			CodeName128 LIKE 'MOB_CH%' OR
			CodeName128 LIKE 'MOB_WC%' OR
			CodeName128 LIKE 'MOB_OA%'
		)
	ORDER BY 
		Lvl

	INSERT INTO @Mobs (RefMonsterID, CodeName128, MonLevel, DropForRace)
	SELECT 
		ROC.ID,
		CodeName128,
		[Lvl],
		'EU'
	FROM 
		_RefObjCommon ROC INNER JOIN 
		_RefObjChar CHR ON ROC.Link = CHR.ID 
	WHERE
		[Service] = 1 AND
		[Lvl] <= 42 AND
		(
			CodeName128 LIKE 'MOB_EU%' OR
			CodeName128 LIKE 'MOB_AM%' OR
			CodeName128 LIKE 'MOB_CA%'
		)
		AND CodeName128 NOT LIKE '%_NPC_%'
	ORDER BY 
		Lvl

	INSERT INTO @Mobs (RefMonsterID, CodeName128, MonLevel, DropForRace)
	SELECT 
		ROC.ID,
		CodeName128,
		[Lvl],
		'BOTH'
	FROM 
		_RefObjCommon ROC INNER JOIN 
		_RefObjChar CHR ON ROC.Link = CHR.ID 
	WHERE
		[Service] = 1 AND
		TypeID1 = 1 AND
		[Lvl] > 42 AND
		Lvl <= @MonLevelMax AND
		(
			CodeName128 LIKE 'MOB_KT%' OR
			CodeName128 LIKE 'MOB_KK%' OR
			CodeName128 LIKE 'MOB_TK%' OR
			CodeName128 LIKE 'MOB_DH%' OR
			CodeName128 LIKE 'MOB_RM%' OR
			CodeName128 LIKE 'MOB_TQ%' OR
			CodeName128 LIKE 'MOB_SD%'
		)
	ORDER BY 
		Lvl


	DECLARE @ProbGroup INT

	DECLARE @SealOfStarDropProbabilityDifference REAL = (@SealOfStarDropProbabilityEnd - @SealOfStarDropProbabilityStart) / (@MonLevelMax - 1)
	DECLARE @SealOfMoonDropProbabilityDifference REAL = (@SealOfMoonDropProbabilityEnd - @SealOfMoonDropProbabilityStart) / (@MonLevelMax - 1)
	DECLARE @SealOfSunDropProbabilityDifference REAL = (@SealOfSunDropProbabilityEnd - @SealOfSunDropProbabilityStart) / (@MonLevelMax - 1)

	-- Iterate through ProbGroups
	DECLARE probgroup_cur CURSOR FOR
		SELECT DISTINCT ProbGroup FROM @Items

	OPEN probgroup_cur

	FETCH NEXT FROM probgroup_cur INTO @ProbGroup

	WHILE @@FETCH_STATUS = 0
	BEGIN

		DECLARE @MonLevels TABLE (MonLevel INT);

		DECLARE @sql NVARCHAR(MAX);

		-- Get Monster levels for current ProbGroup
		SET @sql = N'
		SELECT MonLevel
		FROM _RefDropClassSel_RareEquip
		WHERE ProbGroup' + CAST(@ProbGroup AS VARCHAR(2)) + ' > 0';

		INSERT INTO @MonLevels (MonLevel)
		EXEC (@sql);

		INSERT INTO _RefMonster_AssignedItemRndDrop ([Service], RefMonsterID, RefItemGroupID, ItemGroupCodeName128, Overlap, DropAmountMin, DropAmountMax, DropRatio, param1, param2)
		SELECT
			TEMP.[Service],
			RefMonsterID,
			GRP.RefItemGroupID,
			ItemGroupCodeName128,
			Overlap,
			DropAmountMin,
			DropAmountMax,
			CASE 
				WHEN ItemGroupCodeName128 LIKE '%_SOS_%' THEN @SealOfStarDropProbabilityStart + ((MonLevel - 1) * @SealOfStarDropProbabilityDifference)
				WHEN ItemGroupCodeName128 LIKE '%_SOM_%' THEN @SealOfMoonDropProbabilityStart + ((MonLevel - 1) * @SealOfMoonDropProbabilityDifference)
				WHEN ItemGroupCodeName128 LIKE '%_SUN_%' THEN @SealOfSunDropProbabilityStart + ((MonLevel - 1) * @SealOfSunDropProbabilityDifference)
			END AS DropRatio,
			param1,
			param2
		FROM
		(
			SELECT 
				1 AS [Service],
				RefMonsterID,
				DropGroup AS ItemGroupCodeName128,
				0 AS Overlap,
				1 AS DropAmountMin,
				1 AS DropAmountMax,
				0 AS param1,
				0 AS param2,
				MonLevel
			FROM
			(
				SELECT 
					RefMonsterID,
					CodeName128,
					MonLevel,
					DropForRace
				FROM 
					@Mobs 
				WHERE 
					MonLevel IN (SELECT MonLevel FROM @MonLevels)
			) AS MOB,
			(
				SELECT
					DISTINCT DropGroup, Race
				FROM
					@Items
				WHERE
					ProbGroup = @ProbGroup
			) AS ITEM

			WHERE 
				(MonLevel <= 42 AND DropForRace = Race)
				OR MonLevel > 42
		) AS TEMP INNER JOIN (SELECT DISTINCT RefItemGroupID, CodeName128 FROM _RefDropItemGroup) GRP ON TEMP.ItemGroupCodeName128 COLLATE Korean_Wansung_CI_AS = GRP.CodeName128

		-- This has to be cleared, even if it is declared inside the loop
		DELETE FROM @MonLevels

		FETCH NEXT FROM probgroup_cur INTO @ProbGroup
	END

	CLOSE probgroup_cur
	DEALLOCATE probgroup_cur

	-- Since more groups can trigger at once, we must divide each monster by its group count by rarity
	UPDATE DRP
		SET DRP.DropRatio = DRP.DropRatio / TEMP.[Count]
	FROM 
		_RefMonster_AssignedItemRndDrop DRP INNER JOIN
	(
	SELECT
		RefMonsterID,
		SUBSTRING(ItemGroupCodeName128, 12, 5) AS Rarity,
		COUNT(*) AS [Count]
	FROM 
		_RefMonster_AssignedItemRndDrop
	WHERE 
		ItemGroupCodeName128 LIKE 'ITEM_EU_D%' OR ItemGroupCodeName128 LIKE 'ITEM_CH_D%'
	GROUP BY RefMonsterID, SUBSTRING(ItemGroupCodeName128, 12, 5)
	) AS TEMP ON SUBSTRING(DRP.ItemGroupCodeName128, 12, 5) = TEMP.Rarity AND TEMP.RefMonsterID = DRP.RefMonsterID

	-- Disable original drops
	UPDATE _RefDropClassSel_RareEquip
	SET 
		ProbGroup1 = 0,
		ProbGroup2 = 0,
		ProbGroup3 = 0,
		ProbGroup4 = 0,
		ProbGroup5 = 0,
		ProbGroup6 = 0,
		ProbGroup7 = 0,
		ProbGroup8 = 0,
		ProbGroup9 = 0,
		ProbGroup10 = 0,
		ProbGroup11 = 0,
		ProbGroup12 = 0,
		ProbGroup13 = 0,
		ProbGroup14 = 0,
		ProbGroup15 = 0,
		ProbGroup16 = 0,
		ProbGroup17 = 0,
		ProbGroup18 = 0,
		ProbGroup19 = 0,
		ProbGroup20 = 0,
		ProbGroup21 = 0,
		ProbGroup22 = 0,
		ProbGroup23 = 0,
		ProbGroup24 = 0,
		ProbGroup25 = 0,
		ProbGroup26 = 0,
		ProbGroup27 = 0,
		ProbGroup28 = 0,
		ProbGroup29 = 0,
		ProbGroup30 = 0,
		ProbGroup31 = 0

	COMMIT TRAN
END TRY
BEGIN CATCH
	ROLLBACK TRAN
END CATCH
GO
