USE [AVL22_Qa]
GO
/****** Object:  StoredProcedure [dbo].[sp_DynamicServiceProcess]    Script Date: 6/23/2026 10:17:35 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[sp_DynamicServiceProcess]
    @FinishedFlag INT OUTPUT

AS
BEGIN
SET NOCOUNT ON;



    BEGIN TRY




    DECLARE @tolerance FLOAT = 0.0002;
	DECLARE @TenantId UNIQUEIDENTIFIER ='10000001-1001-1001-1001-100000000001';
	DECLARE @Today DATE = CAST(GETDATE() AS DATE);   -- use GETUTCDATE() if you store UTC
	DECLARE @CurrentTime DATETIME2=GETDATE();
	DECLARE @VehicleWeigth FLOAT = 0;
-- ======================================================
-- Step 0.0: Prepare temporary table for raw AVL patch data (COMMON)
-- ======================================================


-- ======================================================
-- Step 0.0: Create SWEEPING TABLES
-- ======================================================

---------------------------------------------------------
-- ✅ 1. TripWithCompletion
---------------------------------------------------------
CREATE TABLE #TripWithCompletion (
    TripProcessingSummaryId UNIQUEIDENTIFIER,
    OperationalPlansId UNIQUEIDENTIFIER,
    CountActiveTrip INT,
    ContractServiceId UNIQUEIDENTIFIER,
    ServiceGroupId UNIQUEIDENTIFIER,
    ContractId UNIQUEIDENTIFIER,
    OperationalPlanOldAverage FLOAT,
    TripId UNIQUEIDENTIFIER,
    TripWeightedCompletionPercentage FLOAT, -- adjust precision as needed
    TotalValidDistance FLOAT  
);

CREATE NONCLUSTERED INDEX IX_OperationalPlansId ON #TripWithCompletion (OperationalPlansId);
CREATE NONCLUSTERED INDEX IX_TripId ON #TripWithCompletion (TripId);


---------------------------------------------------------
-- ✅ 2. ValidVehicleLocations
---------------------------------------------------------
    CREATE TABLE #ValidVehicleLocations (TripId UNIQUEIDENTIFIER,
        TripProcessingSummaryId UNIQUEIDENTIFIER,
        TripDetailsProcessingSummaryId UNIQUEIDENTIFIER ,
        OperationalPlansId UNIQUEIDENTIFIER,
        ContractServiceId UNIQUEIDENTIFIER,
        ContractingCompanyId UNIQUEIDENTIFIER,
        ContractId UNIQUEIDENTIFIER,
        ServiceGroupId UNIQUEIDENTIFIER,
        MovementTime DATETIME2,
        VehicleId UNIQUEIDENTIFIER,
        Longitude FLOAT,
        Latitude FLOAT,
        Input1 INT,
        Input2 INT,
        Input3 INT,
        Input4 INT,
        Speed INT,
        Ignition INT,
        VehicleType INT,
        ContractingCompanyType INT,
		CountActiveTrip INT,
		StreetOrder INT ,
		StreetLength FLOAT,
		StreetWeightPercentage FLOAT,
		TotalDistance DECIMAL(18,2),
		OperationalPlanOldAverage FLOAT,
       ServiceGroupType INT,  
       ContractTypeId UNIQUEIDENTIFIER,  

    );

	    CREATE CLUSTERED INDEX IX_TripId ON #ValidVehicleLocations(TripId);
	    CREATE NONCLUSTERED INDEX IX_XTripDetailsProcessingSummaryId ON #ValidVehicleLocations(TripDetailsProcessingSummaryId);
	    CREATE NONCLUSTERED INDEX IX_TripProcessingSummaryId ON #ValidVehicleLocations(TripProcessingSummaryId);
	    CREATE NONCLUSTERED INDEX IX_OperationalPlansId ON #ValidVehicleLocations(OperationalPlansId);

		
---------------------------------------------------------
-- ✅ 3. TripDetailsProcessingSummarySession
---------------------------------------------------------

	 CREATE TABLE #TripDetailsProcessingSummarySession (
        TripId UNIQUEIDENTIFIER,
        TripProcessingSummaryId UNIQUEIDENTIFIER,
        TripDetailsProcessingSummaryId UNIQUEIDENTIFIER,
        OperationalPlansId UNIQUEIDENTIFIER,
        ContractServiceId UNIQUEIDENTIFIER,
        ContractId UNIQUEIDENTIFIER,
        ServiceGroupId UNIQUEIDENTIFIER,
        CurrentLatitude FLOAT,
        CurrentLongitude FLOAT,
        LastLatitude FLOAT,
        LastLongitude FLOAT,
        VehicleType INT,
        ContractingCompanyType INT,
        Input1 INT,
        Input2 INT,
        Input3 INT,
        Input4 INT,
        Speed INT,
        Ignition BIT,
        SessionBrushDistanceCovered DECIMAL,
        SessionTotalWaterDistanceCoveredPatch DECIMAL,
        SessionGpsDistanceCoveredPatch DECIMAL,
	CountActiveTrip INT,
		StreetOrder INT ,
		StreetLength FLOAT,
		StreetWeightPercentage FLOAT,
		TotalDistance DECIMAL(18,2),
		OperationalPlanOldAverage FLOAT,
            MovementTime DATETIME2,

    );


	
	    CREATE CLUSTERED INDEX IX_TripId ON #TripDetailsProcessingSummarySession(TripId);
	    CREATE NONCLUSTERED INDEX IX_TripDetailsProcessingSummaryId ON #TripDetailsProcessingSummarySession(TripProcessingSummaryId);
	    CREATE NONCLUSTERED INDEX IX_TripProcessingSummaryId ON #TripDetailsProcessingSummarySession(TripDetailsProcessingSummaryId);
	    CREATE NONCLUSTERED INDEX IX_OperationalPlansId ON #TripDetailsProcessingSummarySession(OperationalPlansId);




---------------------------------------------------------
-- ✅ 4. StreetWithValidity
---------------------------------------------------------
CREATE TABLE #StreetWithValidity (
    TripId UNIQUEIDENTIFIER,
    TripProcessingSummaryId UNIQUEIDENTIFIER,
    TripDetailsProcessingSummaryId UNIQUEIDENTIFIER,
    OperationalPlansId UNIQUEIDENTIFIER,
    ContractServiceId UNIQUEIDENTIFIER NULL,
    ContractId UNIQUEIDENTIFIER NULL,
    ServiceGroupId UNIQUEIDENTIFIER NULL,
    VehicleType INT,
    ContractingCompanyType INT,
    ValidDistance DECIMAL(18,6),
    WaterDistanceFinal DECIMAL(18,6),
    BrushDistanceFinal DECIMAL(18,6),
    GpsDistanceFinal DECIMAL(18,6),
    CountActiveTrip INT,
    StreetOrder INT,
    StreetLength FLOAT,
    StreetWeightPercentage FLOAT,
    OperationalPlanOldAverage FLOAT,
    StreetCompletionPercentage FLOAT
);

CREATE CLUSTERED INDEX IX_TripId ON #StreetWithValidity(TripId);
CREATE NONCLUSTERED INDEX IX_TripProcessingSummaryId ON #StreetWithValidity(TripProcessingSummaryId);
CREATE NONCLUSTERED INDEX IX_TripDetailsProcessingSummaryId ON #StreetWithValidity(TripDetailsProcessingSummaryId);


---------------------------------------------------------
-- ✅ 5. TempAvlPatchToProcess
---------------------------------------------------------
CREATE TABLE #TempAvlPatchForLifting (
    Id UNIQUEIDENTIFIER, 
    VehicleId UNIQUEIDENTIFIER, 
    Longitude FLOAT,
    Latitude FLOAT,
    Tag NVARCHAR(255),
    MovementTime DATETIME2,
    IMEI NVARCHAR(155),
    Io9 FLOAT,
    ContractTypeId UNIQUEIDENTIFIER, 
    ContractingCompanyId UNIQUEIDENTIFIER, 
    TenantId UNIQUEIDENTIFIER, 
);

CREATE CLUSTERED INDEX IX_Id_lifiting ON #TempAvlPatchForLifting(Id);
CREATE NONCLUSTERED INDEX IX_VehicleId_lifting ON #TempAvlPatchForLifting(VehicleId);
CREATE NONCLUSTERED INDEX IX_MovementTime_lifting ON #TempAvlPatchForLifting(MovementTime);
CREATE NONCLUSTERED INDEX IX_Tag_lifting ON #TempAvlPatchForLifting(Tag);



CREATE TABLE #TempAvlPatchForSweeping (
    Id UNIQUEIDENTIFIER, 
    VehicleId UNIQUEIDENTIFIER, 
    Longitude FLOAT,
    Latitude FLOAT,
    Tag NVARCHAR(255),
    MovementTime DATETIME2,
    IMEI NVARCHAR(155),
    Input1 INT,
    Input2 INT,
    Input3 INT,
    Input4 INT,
    Speed INT,
    Ignition BIT,
    wasteCollectionTime DATETIME2
);

CREATE CLUSTERED INDEX IX_Id_sweeeping ON #TempAvlPatchForSweeping(Id);
CREATE NONCLUSTERED INDEX IX_VehicleId_Sweeping ON #TempAvlPatchForSweeping(VehicleId);
CREATE NONCLUSTERED INDEX IX_MovementTime_sweeping ON #TempAvlPatchForSweeping(MovementTime);


---------------------------------------------------------
-- ✅ 6. TripProcessingContext
---------------------------------------------------------
CREATE TABLE #TripProcessingContext (
    TripId UNIQUEIDENTIFIER,
    TripProcessingSummaryId UNIQUEIDENTIFIER,
    OperationalPlansId UNIQUEIDENTIFIER,
    CurrentLiftBinCount INT,
    ExpectedCoverage INT,
    ActualCoverage INT,
    TotalLiftedCount INT,
    TripCompletionPercentage FLOAT,
    ContractServiceId UNIQUEIDENTIFIER,
    ContractId UNIQUEIDENTIFIER,
    ServiceGroupId UNIQUEIDENTIFIER,
    ContractTypeId UNIQUEIDENTIFIER,
    ServiceGroupType INT,
    ContractingCompanyId UNIQUEIDENTIFIER,
    CountActiveTrip INT,
    OperationalPlanOldAverage FLOAT
);

CREATE CLUSTERED INDEX IX_TripId ON #TripProcessingContext(TripId);
CREATE NONCLUSTERED INDEX IX_TripProcessingSummaryId ON #TripProcessingContext(TripProcessingSummaryId);
CREATE NONCLUSTERED INDEX IX_ServiceGroupId ON #TripProcessingContext(ServiceGroupId);


---------------------------------------------------------
-- ✅ 7. OperationalPlanCompletionSummary
---------------------------------------------------------
CREATE TABLE #OperationalPlanCompletionSummary (
    OperationalPlansId UNIQUEIDENTIFIER PRIMARY KEY,
    OperationalPlanCompletionPercentage FLOAT,
    ContractServiceId UNIQUEIDENTIFIER,
    ContractId UNIQUEIDENTIFIER,
    ServiceGroupId UNIQUEIDENTIFIER
);

CREATE NONCLUSTERED INDEX IX_ContractServiceId ON #OperationalPlanCompletionSummary (ContractServiceId);
CREATE NONCLUSTERED INDEX IX_ContractId ON #OperationalPlanCompletionSummary (ContractId);
CREATE NONCLUSTERED INDEX IX_ServiceGroupId ON #OperationalPlanCompletionSummary (ServiceGroupId);



  -- --------------------------------------------------------
-- 5.1: Staging table to hold per-AVL-record vehicle data
--      (multiple rows per TripId are expected and valid)
-- --------------------------------------------------------
CREATE TABLE #WasteBinCollectionPreCalculation (
    TripId       UNIQUEIDENTIFIER,
    FullVoltage  FLOAT,
    EmptyVoltage FLOAT,
    EmptyWeight  FLOAT,
    FullWeight   FLOAT,
    Io9          FLOAT
);

CREATE CLUSTERED INDEX IX_WBC_C1 
    ON #WasteBinCollectionPreCalculation(TripId);

    -- --------------------------------------------------------
-- 5.3: Final output table — one row per Trip
--      holding the total waste weight collected
-- --------------------------------------------------------
CREATE TABLE #TripWasteWeightCalculated (
    TripId          UNIQUEIDENTIFIER PRIMARY KEY,
    TotalWasteWeight FLOAT
);



 ---------------------------------------------------------
        -- Details match temp tables
        ---------------------------------------------------------

      







        CREATE TABLE #DetailsMatchedValidTag (
            AvlId UNIQUEIDENTIFIER,
            TripDetailsId UNIQUEIDENTIFIER,
            TripId UNIQUEIDENTIFIER,
            TripDetailsProcessingSummaryId UNIQUEIDENTIFIER,
            BinStatusId INT,
            BinLongitude FLOAT,
            BinLatitude FLOAT,
            MovementTime DATETIME2,
            Tag NVARCHAR(255),
            IMEI NVARCHAR(155),
            VehicleId UNIQUEIDENTIFIER,
                Io9 FLOAT

        );
        CREATE CLUSTERED INDEX IX_DMV_C1 ON #DetailsMatchedValidTag(TripDetailsId);
        CREATE NONCLUSTERED INDEX IX_DMV_TripIdTime ON #DetailsMatchedValidTag(TripId, MovementTime) INCLUDE (TripDetailsProcessingSummaryId, BinStatusId, VehicleId, Tag);

        CREATE TABLE #DetailsMatchedValidTagCaseTwo (
            AvlId UNIQUEIDENTIFIER,
            TripDetailsId UNIQUEIDENTIFIER,
            TripId UNIQUEIDENTIFIER,
            TripDetailsProcessingSummaryId UNIQUEIDENTIFIER,
            BinStatusId INT,
            BinLongitude FLOAT,
            BinLatitude FLOAT,
            MovementTime DATETIME2,
            Tag NVARCHAR(255),
            IMEI NVARCHAR(155),
            VehicleId UNIQUEIDENTIFIER
        );
        CREATE CLUSTERED INDEX IX_DMV_C2 ON #DetailsMatchedValidTagCaseTwo(TripDetailsId);
        CREATE NONCLUSTERED INDEX IX_DMV_C2_VehicleId    ON #DetailsMatchedValidTagCaseTwo(VehicleId);
        CREATE NONCLUSTERED INDEX IX_DMV_C2_MovementTime ON #DetailsMatchedValidTagCaseTwo(MovementTime);
		
        CREATE TABLE #DetailsMatchedValidTagOtherThree(
            AvlId UNIQUEIDENTIFIER,
            TripId UNIQUEIDENTIFIER,
            BinLongitude FLOAT,
            BinLatitude FLOAT,
            MovementTime DATETIME2,
            Tag NVARCHAR(255),
            IMEI NVARCHAR(155),
            VehicleId UNIQUEIDENTIFIER,
                Io9 FLOAT

        );
        CREATE CLUSTERED INDEX IX_DMV_34_TripId ON #DetailsMatchedValidTagOtherThree(TripId);
        CREATE NONCLUSTERED INDEX IX_DMV_34_TagTrip ON #DetailsMatchedValidTagOtherThree(TripId, Tag) INCLUDE (MovementTime, IMEI, VehicleId);
		
        CREATE TABLE #DetailsMatchedValidTagOtherFour(
            AvlId UNIQUEIDENTIFIER,
            TripId UNIQUEIDENTIFIER,
            BinLongitude FLOAT,
            BinLatitude FLOAT,
            MovementTime DATETIME2,
            Tag NVARCHAR(255),
            IMEI NVARCHAR(155),
            VehicleId UNIQUEIDENTIFIER
        );
        CREATE CLUSTERED INDEX IX_DMV_34_TripId ON #DetailsMatchedValidTagOtherFour(TripId);
        CREATE NONCLUSTERED INDEX IX_DMV_34_TagTrip ON #DetailsMatchedValidTagOtherFour(TripId, Tag) INCLUDE (MovementTime, IMEI, VehicleId);

        CREATE TABLE #DetailsMatchedValidTagOtherFive(
            AvlId UNIQUEIDENTIFIER,
            TripDetailsId UNIQUEIDENTIFIER,
            TripId UNIQUEIDENTIFIER,
            TripDetailsProcessingSummaryId UNIQUEIDENTIFIER,
            BinStatusId INT,
            BinLongitude FLOAT,
            BinLatitude FLOAT,
            MovementTime DATETIME2,
            Tag NVARCHAR(255),
            IMEI NVARCHAR(155),
            VehicleId UNIQUEIDENTIFIER,
                Io9 FLOAT

        );
        CREATE CLUSTERED INDEX IX_DMV_56_PK ON #DetailsMatchedValidTagOtherFive(TripDetailsId);
        CREATE NONCLUSTERED INDEX IX_DMV_56_TagTime ON #DetailsMatchedValidTagOtherFive(Tag, MovementTime) INCLUDE (TripId, TripDetailsProcessingSummaryId, VehicleId);

		
        CREATE TABLE #DetailsMatchedValidTagOtherSix(
            AvlId UNIQUEIDENTIFIER,
            TripDetailsId UNIQUEIDENTIFIER,
            TripId UNIQUEIDENTIFIER,
            TripDetailsProcessingSummaryId UNIQUEIDENTIFIER,
            BinStatusId INT,
            BinLongitude FLOAT,
            BinLatitude FLOAT,
            MovementTime DATETIME2,
            Tag NVARCHAR(255),
            IMEI NVARCHAR(155),
            VehicleId UNIQUEIDENTIFIER
        );
        CREATE CLUSTERED INDEX IX_DMV_56_PK ON #DetailsMatchedValidTagOtherSix(TripDetailsId);
        CREATE NONCLUSTERED INDEX IX_DMV_56_TagTime ON #DetailsMatchedValidTagOtherSix(Tag, MovementTime) INCLUDE (TripId, TripDetailsProcessingSummaryId, VehicleId);

        CREATE TABLE #DetailsMatchedValidTagOtherCases (
            AvlId UNIQUEIDENTIFIER,
            TripDetailsId UNIQUEIDENTIFIER,
            TripId UNIQUEIDENTIFIER,
            TripDetailsProcessingSummaryId UNIQUEIDENTIFIER,
            BinStatusId INT,
            BinLongitude FLOAT,
            BinLatitude FLOAT,
            MovementTime DATETIME2,
            Tag NVARCHAR(255),
            IMEI NVARCHAR(155),
            VehicleId UNIQUEIDENTIFIER,
            Status INT
        );
        CREATE CLUSTERED INDEX IX_DMV_7_PK ON #DetailsMatchedValidTagOtherCases(TripDetailsId);
        CREATE NONCLUSTERED INDEX IX_DMV_7_TagTime ON #DetailsMatchedValidTagOtherCases(Tag, MovementTime) INCLUDE (VehicleId);

        CREATE TABLE #AllCasesCombined(
            AvlId UNIQUEIDENTIFIER,
            TripDetailsId UNIQUEIDENTIFIER,
            TripId UNIQUEIDENTIFIER,
            TripDetailsProcessingSummaryId UNIQUEIDENTIFIER,
            BinStatusId INT,
            BinLongitude FLOAT,
            BinLatitude FLOAT,
            MovementTime DATETIME2,
            Tag NVARCHAR(255),
            IMEI NVARCHAR(155),
            VehicleId UNIQUEIDENTIFIER,
            Status INT
        );

        ---------------------------------------------------------
        -- Temp TripDetails / TripDetailsProcessingSummary
        ---------------------------------------------------------
        CREATE TABLE #TripDetails
        (
            [Id] UNIQUEIDENTIFIER NOT NULL,
            [TripId] UNIQUEIDENTIFIER NOT NULL,
            [CompletionType] INT NULL,
            [TagId] NVARCHAR(200) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
            [ActualWeight] FLOAT NOT NULL,
            [Order] INT NOT NULL,
            [BinId] UNIQUEIDENTIFIER NULL,
            [CreatedDate] DATETIME2(7) NOT NULL,
            [CreatedBy] NVARCHAR(255) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
            [ModifiedDate] DATETIME2(7) NULL,
            [ModifiedBy] NVARCHAR(255) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
            [IsDeleted] BIT NOT NULL,
            [TenantId] UNIQUEIDENTIFIER NOT NULL,
            [StreetWeightPercentage] DECIMAL(18, 2) NOT NULL DEFAULT ((0.0)),
            [StreetLength] FLOAT NOT NULL DEFAULT ((0.0)),
            [TagHash] AS (CONVERT(VARBINARY(32), HASHBYTES('SHA2_256', CONVERT(NVARCHAR(4000), [TagId])))) PERSISTED,
            [ReferenceCode] NVARCHAR(200) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
            [ContractServiceMapGeometryId] UNIQUEIDENTIFIER NULL
        );

	
        CREATE TABLE #TripDetailsProcessingSummary
        (
            [Id] UNIQUEIDENTIFIER NOT NULL,
            [LastCompletion] DATETIME2(7) NULL,
            [ArrivalTime] DATETIME2(7) NULL,
            [TotalDistance] DECIMAL(18, 2) NOT NULL,
            [WaterUsedLiters] DECIMAL(18, 2) NOT NULL,
            [SweptAreaSquareMeters] DECIMAL(18, 2) NOT NULL,
            [TripDetailsId] UNIQUEIDENTIFIER NOT NULL,
            [CompletionTime] DATETIME2(7) NULL,
            [TenantId] UNIQUEIDENTIFIER NOT NULL,
            [BinLatitude] FLOAT NOT NULL DEFAULT ((0.0)),
            [BinLongitude] FLOAT NOT NULL DEFAULT ((0.0)),
            [BinStatusId] INT NOT NULL DEFAULT ((0)),
            [BinWeight] FLOAT NOT NULL DEFAULT ((0.0)),
            [CompilationReason] NVARCHAR(200) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
            [CompletionOrder] INT NOT NULL DEFAULT ((0)),
            [CompletionPercentage] DECIMAL(18, 2) NOT NULL DEFAULT ((0.0)),
            [NumberOfLefts] INT NOT NULL DEFAULT ((0)),
            [NumberOfRotation] INT NOT NULL DEFAULT ((0)),
            [TotalOfWasteCollectedFromContainer] FLOAT NOT NULL DEFAULT ((0.0)),
            [WasteActualWeight] FLOAT NOT NULL DEFAULT ((0.0)),
            [CreatedBy] NVARCHAR(255) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL DEFAULT (N''),
            [ModifiedBy] NVARCHAR(255) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
            [ModifiedDate] DATETIME2(7) NULL,
            [TotalGpsDistanceCovered] FLOAT NOT NULL DEFAULT ((0.0)),
            [Description] NVARCHAR(200) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
            [CreatedDate] DATETIME NULL,
            [CompletionType] INT NULL,
            [TotalBrushDistanceCovered] FLOAT NULL,
            [TotalWaterDistanceCovered] FLOAT NULL,
            [IsSwept] BIT NOT NULL DEFAULT (CONVERT(BIT,(0))),
            [ManualLiftReasonLookupId] INT NULL,
            [TrackingDeviceNumber] BIGINT NOT NULL DEFAULT (CONVERT(BIGINT,(0))),
            [VehicleId] UNIQUEIDENTIFIER NULL,
            StatusLookupId INT
        );
		CREATE UNIQUE NONCLUSTERED INDEX UX_TmpTDPS_TripDetailsId
ON #TripDetailsProcessingSummary(TripDetailsId);

---------------------------------------------------------
-- ✅ 8. NewCombinedAverageForOperationalPlan
---------------------------------------------------------
CREATE TABLE #NewCombinedAverageForOperationalPlan (
    OperationalPlansId UNIQUEIDENTIFIER,
    CombinedAverage FLOAT
);
 
-- End of temp table creation

-- ==============================================
-- PRE-SEED DAILY LOG ROWS (SERVICE GROUP LEVEL)
-- ==============================================

INSERT INTO dbo.DynamicServiceProcessLog (
    Id,
    ContractId,
    ServiceGroupId,
    ContractingCompanyId,
    TenantId,
    GroupServiceType,
	ServiceGroupCompletionPercentage,
	ContractCompletionPercentage,
	ServiceCompletionPercentage,
    ContractTypeId,
	ContractType,
    LogDateTime,
    CreatedBy,
    CreatedDate
)
SELECT
    NEWID(),
    cg.ContractId,
    cg.ServiceGroupId,
    c.ContractingCompanyId,
    @TenantId,
    0,
	0,0,0,
    ct.Id,
	0,
    GETDATE(),
    'System',
    @Today
FROM ContractGroup cg
INNER JOIN contracts c ON c.Id = cg.ContractId
INNER JOIN dbo.ContractServices cs ON cs.ContractId = c.Id AND cs.ServiceGroupId=cg.ServiceGroupId
INNER JOIN dbo.ContractTypes ct ON ct.Id = c.ContractTypeId
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.DynamicServiceProcessLog d
    WHERE d.ContractId       = cg.ContractId
      AND d.ServiceGroupId   = cg.ServiceGroupId
      AND d.TenantId         = @TenantId
      AND d.CreatedDate      = @Today
	  AND CAST (LogDateTime AS DATE) =@Today
);


-- ==================================================
-- Step 0.0: Load AVL patch data from source into temp  (COMMON FOR ALL SERVICES)
-- ==================================================

	
-- For LIFTING (with valid uqniue  tags)
;WITH UniqueTagsCTE AS (
SELECT 
   avl.Id,
   avl.Tag,
   avl.MovementTime,
    avl.IMEI,
 avl.VehicleId,
 avl.Longitude,
 avl.Latitude,
   avl.Io9,
   ISNULL(veh.ContractTypeId,       '00000000-0000-0000-0000-000000000000') AS ContractTypeId,
   ISNULL(veh.ContractingCompanyId, '00000000-0000-0000-0000-000000000000') AS ContractingCompanyId,
   ISNULL(veh.TenantId,             '00000000-0000-0000-0000-000000000000') AS TenantId,
    ROW_NUMBER() OVER (PARTITION BY avl.Tag ORDER BY avl.MovementTime ASC) AS rn
FROM dbo.VehicleAvlDataPatch avl
left join vehicle veh on veh.Id=avl.VehicleId
WHERE Tag IS NOT NULL 
  AND Tag <> '-1' 
  AND LEN(LTRIM(RTRIM(Tag))) > 0
  AND LEN(Tag) <= 30 
)
INSERT INTO #TempAvlPatchForLifting(
        Id, VehicleId, Longitude, Latitude, Tag,
        MovementTime, IMEI,Io9,ContractTypeId,ContractingCompanyId,TenantId)
		SELECT xx.Id,xx.VehicleId, xx.Longitude, xx.Latitude,xx.Tag,xx.MovementTime,xx.IMEI,xx.Io9,xx.ContractTypeId,xx.ContractingCompanyId,xx.TenantId
FROM UniqueTagsCTE xx
WHERE rn = 1
OPTION (MAXDOP 1);





-- For SWEEPING (without tags)
INSERT INTO #TempAvlPatchForSweeping(
        Id, VehicleId, Longitude, Latitude, Tag,
        MovementTime, IMEI, Input1, Input2, Input3,Input4, Speed, Ignition,wasteCollectionTime
    )
SELECT 
        Id, VehicleId, Longitude, Latitude, Tag,
        MovementTime, IMEI, Input1, Input2, Input3,Input4, Speed, Ignition,wasteCollectionTime
    FROM dbo.VehicleAvlDataPatch
WHERE Tag IS NULL 
   OR Tag = '-1' 
   OR LEN(LTRIM(RTRIM(Tag))) = 0;


-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ================LIFTING===========================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================





-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ================INSERT INTO REFERENCE TAG LOCATION===========================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================


INSERT INTO dbo.TagReferenceLocation (Id, Tag, Longitude, Latitude, TenantId, CreatedAt)
SELECT NEWID(), avl.Tag, avl.Longitude, avl.Latitude, @tenantId, GETDATE()
FROM #TempAvlPatchForLifting avl
LEFT JOIN dbo.TagReferenceLocation tl ON tl.Tag = avl.Tag
WHERE tl.Tag IS NULL;









-- ========================================================================
-- Step 2.0: Match AVL tags to trip details & collect valid lifted trip bins
-- ========================================================================

        /* ======================================================
           Step 2: Match AVL tags to trip details (Case 1)
        ====================================================== */
        INSERT INTO #DetailsMatchedValidTag
        (
           AvlId, TripDetailsId, TripId, TripDetailsProcessingSummaryId,
            BinStatusId, BinLongitude, BinLatitude, MovementTime,
            Tag, IMEI, VehicleId,Io9
        )
        SELECT
            avl.Id, td.Id, td.TripId, tdps.Id,
            tdps.BinStatusId, avl.Longitude, avl.Latitude,
            avl.MovementTime, avl.Tag, avl.IMEI, avl.VehicleId,avl.Io9
        FROM dbo.TripDetails td WITH (NOLOCK)
        INNER JOIN dbo.TripDetailsProcessingSummary tdps WITH (NOLOCK)
            ON td.Id = tdps.TripDetailsId
        INNER JOIN dbo.Trips t WITH (NOLOCK)
            ON t.Id = td.TripId
        INNER JOIN #TempAvlPatchForLifting avl
            ON td.TagId = avl.Tag
           AND avl.VehicleId = t.VehicleId
        WHERE t.IsDeleted=0 AND avl.MovementTime BETWEEN t.StartTrip AND t.EndTrip ;

		 -- Remove Case 1 processed records
        DELETE FROM #TempAvlPatchForLifting
        WHERE Id IN (SELECT AvlId FROM #DetailsMatchedValidTag);



		 /* ======================================================
           Case 2 (closest ended trip) the most recent trip (by EndTrip) 
		   that ended before the AVL movement time, has the tag, 
		   is not deleted, and does not contain the AVL time inside its window.
        ====================================================== */
 INSERT INTO #DetailsMatchedValidTagCaseTwo
(
    AvlId, TripDetailsId, TripId, TripDetailsProcessingSummaryId,
    BinStatusId, BinLongitude, BinLatitude, MovementTime,
    Tag, IMEI, VehicleId
)
SELECT 
    avl.Id,
    chosenTrip.tripdetailsId,
    chosenTrip.Id AS TripId,
    tdps.Id,
    tdps.BinStatusId,
    avl.Longitude,
    avl.Latitude,
    avl.MovementTime,
    avl.Tag,
    avl.IMEI,
    avl.VehicleId
FROM #TempAvlPatchForLifting avl
CROSS APPLY
(
    SELECT TOP 1
           t.Id,
           td.Id AS tripdetailsId
    FROM dbo.Trips t WITH (NOLOCK)
    JOIN dbo.TripDetails td
        ON td.TripId = t.Id
       AND td.TagId = avl.Tag
    WHERE t.VehicleId = avl.VehicleId
      AND t.EndTrip < avl.MovementTime
	  AND t.IsDeleted=0
    ORDER BY t.EndTrip DESC
) AS chosenTrip
INNER JOIN dbo.TripDetailsProcessingSummary tdps WITH (NOLOCK)
    ON chosenTrip.tripdetailsId = tdps.TripDetailsId;



	 -- Remove Case 2 processed records
        DELETE FROM #TempAvlPatchForLifting
        WHERE Id IN (SELECT AvlId FROM #DetailsMatchedValidTagCaseTwo);


 /* =====================================================================
   Case 3/4 (Improved trip selection)
   - Vehicle is in plan: pick ONE "best" trip for that vehicle around MovementTime basiclly and high priorty trip where movement time bigger than it directly 
   - Bin is NOT in plan: Tag NOT exists in TripDetails for that chosen trip
   - Status 3: inside trip time, Status 4: outside trip time
   - Added time window filter to avoid picking very old trips
   ================================================================================== */
 
 
INSERT INTO #DetailsMatchedValidTagOtherThree
(
    AvlId, TripId, BinLongitude, BinLatitude, MovementTime, Tag, IMEI, VehicleId,Io9
)
SELECT
    avl.Id,
    chosenTrip.Id AS TripId,
    avl.Longitude,
    avl.Latitude,
    avl.MovementTime,
    avl.Tag,
    avl.IMEI,
    avl.VehicleId,
    avl.Io9
FROM #TempAvlPatchForLifting avl
CROSS APPLY
(
    SELECT TOP (1) t.Id
    FROM dbo.Trips t WITH (NOLOCK)
    WHERE t.VehicleId = avl.VehicleId
	AND t.IsDeleted=0 
     AND  avl.MovementTime >=t.StartTrip AND avl.MovementTime<t.EndTrip
) chosenTrip
WHERE
    --  Bin NOT in plan: tag does not exist in TripDetails for that chosen trip
    NOT EXISTS
    (
        SELECT 1
        FROM dbo.TripDetails td WITH (NOLOCK)
        WHERE td.TripId = chosenTrip.Id
		AND td.TagId  = avl.Tag  
    );


	-- Remove Case 3 processed records
        DELETE FROM #TempAvlPatchForLifting
        WHERE Id IN (SELECT AvlId FROM #DetailsMatchedValidTagOtherThree);

INSERT INTO #DetailsMatchedValidTagOtherFour
(
    AvlId, TripId, BinLongitude, BinLatitude, MovementTime, Tag, IMEI, VehicleId
)
SELECT
    avl.Id,
    chosenTrip.Id AS TripId,
    avl.Longitude,
    avl.Latitude,
    avl.MovementTime,
    avl.Tag,
    avl.IMEI,
    avl.VehicleId
FROM #TempAvlPatchForLifting avl
CROSS APPLY
(
    SELECT TOP (1) t.Id
    FROM dbo.Trips t WITH (NOLOCK)
    WHERE t.VehicleId = avl.VehicleId
	AND t.IsDeleted=0 
     AND t.EndTrip < avl.MovementTime
    ORDER BY
        t.EndTrip DESC
) chosenTrip
WHERE
    --  Bin NOT in plan: tag does not exist in TripDetails for that chosen trip
    NOT EXISTS
    (
        SELECT 1
        FROM dbo.TripDetails td WITH (NOLOCK)
        WHERE td.TripId = chosenTrip.Id
		AND td.TagId  = avl.Tag 
    );


	 -- Remove Case 4 processed records
        DELETE FROM #TempAvlPatchForLifting
        WHERE Id IN (SELECT AvlId FROM #DetailsMatchedValidTagOtherFour);


  /* ======================================================
           Cases 5/6 (same tag, different vehicle)
        ====================================================== */


    
INSERT INTO #DetailsMatchedValidTagOtherFive
(
    AvlId, TripId, BinLongitude, BinLatitude, MovementTime, Tag, IMEI, VehicleId,Io9
)
SELECT
    avl.Id,
    chosenTrip.Id AS TripId,
    avl.Longitude,
    avl.Latitude,
    avl.MovementTime,
    avl.Tag,
    avl.IMEI,
    avl.VehicleId,
    avl.Io9
FROM #TempAvlPatchForLifting avl
CROSS APPLY
(
    SELECT TOP (1) t.Id, t.StartTrip, t.EndTrip, t.VehicleId, t.OperationalPlansId
    FROM dbo.Trips t WITH (NOLOCK)
	INNER JOIN dbo.TripDetails td ON td.TripId = t.Id AND td.TagId=avl.Tag
    WHERE t.VehicleId <> avl.VehicleId
	AND t.IsDeleted=0 
	AND 
    avl.MovementTime>=t.starttrip  AND  avl.MovementTime<t.EndTrip
) chosenTrip;

     -- Remove Case 5 processed records
        DELETE FROM #TempAvlPatchForLifting
        WHERE Id IN (SELECT AvlId FROM #DetailsMatchedValidTagOtherFive);

       
INSERT INTO #DetailsMatchedValidTagOtherSix
(
    AvlId, TripId, BinLongitude, BinLatitude, MovementTime, Tag, IMEI, VehicleId
)
SELECT
    avl.Id,
    chosenTrip.Id AS TripId,
    avl.Longitude,
    avl.Latitude,
    avl.MovementTime,
    avl.Tag,
    avl.IMEI,
    avl.VehicleId
FROM #TempAvlPatchForLifting avl
CROSS APPLY
(
    SELECT TOP (1) t.Id, t.StartTrip, t.EndTrip, t.VehicleId, t.OperationalPlansId
    FROM dbo.Trips t WITH (NOLOCK)
	INNER JOIN dbo.TripDetails td ON td.TripId = t.Id AND td.TagId=avl.Tag
    WHERE t.VehicleId <> avl.VehicleId
	AND t.IsDeleted=0 
	AND t.EndTrip < avl.MovementTime
    ORDER BY t.EndTrip DESC
) chosenTrip;




    -- Remove Case 6 processed records
        DELETE FROM #TempAvlPatchForLifting
        WHERE Id IN (SELECT AvlId FROM #DetailsMatchedValidTagOtherSix);
    

        /* ======================================================
           Case 7 (other cases)
        ====================================================== */
        INSERT INTO #DetailsMatchedValidTagOtherCases
        (
            AvlId, TripDetailsId, TripId, TripDetailsProcessingSummaryId,
            BinStatusId, BinLongitude, BinLatitude, MovementTime,
            Tag, IMEI, VehicleId, Status
        )
        SELECT
            avl.Id,
            td.Id,
            td.TripId,
            tdps.Id,
            tdps.BinStatusId,
            avl.Longitude,
            avl.Latitude,
            avl.MovementTime,
            avl.Tag,
            avl.IMEI,
            avl.VehicleId,
            7
        FROM #TempAvlPatchForLifting avl
        LEFT JOIN dbo.TripDetails td WITH (NOLOCK)
            ON avl.Tag = td.TagId
        LEFT JOIN dbo.TripDetailsProcessingSummary tdps WITH (NOLOCK)
            ON tdps.TripDetailsId = td.Id
        LEFT JOIN dbo.Trips t WITH (NOLOCK)
            ON td.TripId = t.Id
        WHERE (avl.VehicleId <> t.VehicleId OR t.VehicleId IS NULL)
          AND (avl.Tag <> td.TagId OR td.TagId IS NULL)
          AND (t.StartTrip IS NULL
               OR avl.MovementTime < t.StartTrip
               OR avl.MovementTime > t.EndTrip 
			   AND t.IsDeleted=0);

        /* ======================================================
           Step 0.1: Update Bins locations
        ====================================================== */
        BEGIN TRY
            BEGIN TRANSACTION;
			-- Combine into single UPDATE with CASE statements
UPDATE B
SET 
ModifiedDate = @CurrentTime,
    Longitude = CASE 
        WHEN dm1.Tag IS NOT NULL THEN dm1.BinLongitude
        WHEN dm2.Tag IS NOT NULL THEN dm2.BinLongitude
        WHEN dm3.Tag IS NOT NULL THEN dm3.BinLongitude
        WHEN dm4.Tag IS NOT NULL THEN dm4.BinLongitude
        WHEN dm5.Tag IS NOT NULL THEN dm5.BinLongitude
        WHEN dm6.Tag IS NOT NULL THEN dm6.BinLongitude
        WHEN dmxx.Tag IS NOT NULL THEN dmxx.BinLongitude
    END,
    Latitude = CASE 
        WHEN dm1.Tag IS NOT NULL THEN dm1.BinLatitude
		WHEN dm2.Tag IS NOT NULL THEN dm2.BinLatitude
        WHEN dm3.Tag IS NOT NULL THEN dm3.BinLatitude
        WHEN dm4.Tag IS NOT NULL THEN dm4.BinLatitude
        WHEN dm5.Tag IS NOT NULL THEN dm5.BinLatitude
        WHEN dm6.Tag IS NOT NULL THEN dm6.BinLatitude
      WHEN dmxx.Tag IS NOT NULL THEN dmxx.BinLatitude
    END,
    ModifiedBy = CASE 
        WHEN dm1.Tag IS NOT NULL THEN 'SP_DynamicServiceStored_locationHasBeenChanged_Case_One'
		WHEN dm2.Tag IS NOT NULL THEN 'SP_DynamicServiceStored_locationHasBeenChanged_Case_Two'
        WHEN dm3.Tag IS NOT NULL THEN 'SP_DynamicServiceStored_locationHasBeenChanged_Case_Three'
        WHEN dm4.Tag IS NOT NULL THEN 'SP_DynamicServiceStored_locationHasBeenChanged_Case_Four'
        WHEN dm5.Tag IS NOT NULL THEN 'SP_DynamicServiceStored_locationHasBeenChanged_Case_Five'
        WHEN dm6.Tag IS NOT NULL THEN 'SP_DynamicServiceStored_locationHasBeenChanged_Case_Six'
      WHEN dmxx.Tag IS NOT NULL THEN  'SP_DynamicServiceStored_locationHasBeenChanged_Case_OtherCases'
    END
FROM dbo.Bins B
LEFT JOIN #DetailsMatchedValidTag dm1 ON B.TagId = dm1.Tag AND b.IsDeleted=0
LEFT JOIN #DetailsMatchedValidTagCaseTwo dm2 ON B.TagId = dm2.Tag AND b.IsDeleted=0
LEFT JOIN #DetailsMatchedValidTagOtherThree dm3 ON B.TagId = dm3.Tag AND b.IsDeleted=0
LEFT JOIN #DetailsMatchedValidTagOtherFour dm4 ON B.TagId = dm4.Tag AND b.IsDeleted=0
LEFT JOIN #DetailsMatchedValidTagOtherFive dm5 ON B.TagId = dm5.Tag AND b.IsDeleted=0
LEFT JOIN #DetailsMatchedValidTagOtherSix dm6 ON B.TagId = dm6.Tag AND b.IsDeleted=0
LEFT JOIN #DetailsMatchedValidTagOtherCases dmxx ON B.TagId = dmxx.Tag AND b.IsDeleted=0
WHERE dm1.Tag IS NOT NULL OR dm2.Tag IS NOT NULL OR dm3.Tag IS NOT NULL
OR dm4.Tag IS NOT NULL OR dm5.Tag IS NOT NULL OR dm5.Tag IS NOT NULL OR dmxx.Tag IS NOT NULL;
   

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH;

        /* ======================================================
           Step 0.2: Update ContractServiceMapGeometry
        ====================================================== */
        BEGIN TRY
            BEGIN TRANSACTION;

            UPDATE csmg
            SET 
               Longitude = dm.BinLongitude,
               Latitude  = dm.BinLatitude,
               ModifiedDate = @CurrentTime,
               ModifiedBy   = 'SP_DynamicServiceStored_locationHasBeenChanged'
            FROM dbo.ContractServiceMapGeometry csmg
            INNER JOIN #DetailsMatchedValidTag dm 
                ON csmg.Tag = dm.Tag AND csmg.IsDeleted=0;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH;



        /* ======================================================
           Step 4: Update(CASE 1 ,2)/Insert TripDetailsProcessingSummary statuses + create TripDetails for 3/4
        ====================================================== */
        BEGIN TRY
            BEGIN TRANSACTION;
			            -- Case 1 update

			-- Step 1: Pre-calculate expensive operations in a CTE
;WITH PreCalculated AS (
    SELECT 
        dm.TripDetailsProcessingSummaryId,
        dm.BinStatusId,
        dm.MovementTime,
		dm.VehicleId,
		dm.BinLongitude, 
        dm.BinLatitude,   
        TRY_CAST(dm.Imei AS BIGINT) AS ImeiAsBigInt,  
        tdps.LastCompletion,
        tdps.NumberOfLefts,
        tdps.BinStatusId AS CurrentBinStatus,
        tdps.CompletionTime AS CurrentCompletionTime,
        -- ✅ Calculate ONCE and store the result
        DATEDIFF(MINUTE, tdps.LastCompletion, dm.MovementTime) AS MinutesDifference
    FROM #DetailsMatchedValidTag dm
    INNER JOIN dbo.TripDetailsProcessingSummary tdps 
        ON tdps.Id = dm.TripDetailsProcessingSummaryId AND  ((tdps.StatusLookupId IS NULL) OR  tdps.StatusLookupId = (13))
)
-- Step 2: Use the pre-calculated value
UPDATE tdps
SET 
    tdps.BinStatusId = CASE 
        WHEN pc.BinStatusId = 1 THEN 2 
        ELSE pc.CurrentBinStatus 
    END,
    
    tdps.CompletionTime = CASE 
        WHEN pc.BinStatusId = 1 THEN pc.MovementTime 
        ELSE pc.CurrentCompletionTime 
    END,
    
    tdps.LastCompletion = CASE
        WHEN pc.BinStatusId = 1 THEN pc.MovementTime
        WHEN pc.BinStatusId = 2 AND pc.MinutesDifference >= 60 THEN pc.MovementTime  -- ✅ Just reference, no recalculation!
        ELSE pc.LastCompletion
    END,
    
    tdps.NumberOfLefts = CASE
        WHEN pc.BinStatusId = 1 THEN 1
        WHEN pc.BinStatusId = 2 AND pc.MinutesDifference >= 60 THEN pc.NumberOfLefts + 1  -- ✅ Just reference!
        ELSE pc.NumberOfLefts
    END,
	tdps.StatusLookupId=13,
	    tdps.BinLongitude = pc.BinLongitude,  
    tdps.BinLatitude = pc.BinLatitude,    

               VehicleId = pc.VehicleId,
               TrackingDeviceNumber = CAST(pc.ImeiAsBigInt AS BIGINT),
    tdps.ModifiedBy = 'SP_DynamicServiceStored_BIN_CaseOne',
    tdps.ModifiedDate = @CurrentTime
FROM dbo.TripDetailsProcessingSummary tdps
INNER JOIN PreCalculated pc ON tdps.Id = pc.TripDetailsProcessingSummaryId
where tdps.StatusLookupId=null OR tdps.StatusLookupId=13;

            -- Case 2 update

						-- Step 1: Pre-calculate expensive operations in a CTE
;WITH PreCalculated AS (
    SELECT 
        dm.TripDetailsProcessingSummaryId,
        dm.BinStatusId,
        dm.MovementTime,
		dm.VehicleId,
     	dm.BinLongitude, 
        dm.BinLatitude,   
        TRY_CAST(dm.Imei AS BIGINT) AS ImeiAsBigInt,   
		tdps.LastCompletion,
        tdps.NumberOfLefts,
        tdps.BinStatusId AS CurrentBinStatus,
        tdps.CompletionTime AS CurrentCompletionTime,
        -- ✅ Calculate ONCE and store the result
        DATEDIFF(MINUTE, tdps.LastCompletion, dm.MovementTime) AS MinutesDifference
    FROM #DetailsMatchedValidTagCaseTwo dm
    INNER JOIN dbo.TripDetailsProcessingSummary tdps 
        ON tdps.Id = dm.TripDetailsProcessingSummaryId AND  ((tdps.StatusLookupId IS NULL) OR  tdps.StatusLookupId = (14))
)
-- Step 2: Use the pre-calculated value
UPDATE tdps
SET 
    tdps.BinStatusId = CASE 
        WHEN pc.BinStatusId = 1 THEN 2 
        ELSE pc.CurrentBinStatus 
    END,
    
    tdps.CompletionTime = CASE 
        WHEN pc.BinStatusId = 1 THEN pc.MovementTime 
        ELSE pc.CurrentCompletionTime 
    END,
    
    tdps.LastCompletion = CASE
        WHEN pc.BinStatusId = 1 THEN pc.MovementTime
        WHEN pc.BinStatusId = 2 AND pc.MinutesDifference >= 60 THEN pc.MovementTime  -- ✅ Just reference, no recalculation!
        ELSE pc.LastCompletion
    END,
    
    tdps.NumberOfLefts = CASE
        WHEN pc.BinStatusId = 1 THEN 1
        WHEN pc.BinStatusId = 2 AND pc.MinutesDifference >= 60 THEN pc.NumberOfLefts + 1  -- ✅ Just reference!
        ELSE pc.NumberOfLefts
    END,
	tdps.StatusLookupId=14,
		    tdps.BinLongitude = pc.BinLongitude,  
    tdps.BinLatitude = pc.BinLatitude,    

               VehicleId = pc.VehicleId,
               TrackingDeviceNumber = CAST(pc.ImeiAsBigInt AS BIGINT),
    tdps.ModifiedBy = 'SP_DynamicServiceStored_BIN_CaseTwo',
    tdps.ModifiedDate = @CurrentTime
FROM dbo.TripDetailsProcessingSummary tdps
INNER JOIN PreCalculated pc ON tdps.Id = pc.TripDetailsProcessingSummaryId;

            /* ===========================
               Insert TripDetails for FIXED Case 3/4
               (dedupe per TripId+Tag)
            =========================== */
   ;WITH Dedup3 AS
(
    SELECT
        TripId,
        Tag,
        MIN(MovementTime) AS MovementTime,
        MAX(IMEI) AS IMEI,
        MAX(VehicleId) AS VehicleId
    FROM #DetailsMatchedValidTagOtherThree
    GROUP BY TripId, Tag
)
INSERT INTO #TripDetails
(
    Id, TripId, CompletionType, TagId, ActualWeight, [Order],
    BinId, CreatedDate, CreatedBy, ModifiedDate, ModifiedBy,
    IsDeleted, TenantId, StreetWeightPercentage, StreetLength,
    ReferenceCode, ContractServiceMapGeometryId
)
SELECT 
    NEWID(),
    d.TripId,
    0,
    d.Tag,
    0,
    -1,
    b1.BinId,
    d.MovementTime,
    'System_Status3',
    NULL,
    NULL,
    0,
    @TenantId,
    0,
    0,
    'TRD-00000-00000',
    g1.CsmgId
FROM Dedup3 d
OUTER APPLY
(
    -- ✅ choose exactly one bin for the tag
    SELECT TOP (1) b.Id AS BinId
    FROM dbo.Bins b WITH (NOLOCK)
    WHERE b.TagId = d.Tag
    ORDER BY b.ModifiedDate DESC, b.CreatedDate DESC, b.Id
) b1
OUTER APPLY
(
    -- ✅ choose exactly one geometry for the tag (if multiple exist)
    SELECT TOP (1) c.Id AS CsmgId
    FROM dbo.ContractServiceMapGeometry c WITH (NOLOCK)
    WHERE c.Tag = d.Tag
    ORDER BY c.ModifiedDate DESC, c.CreatedDate DESC, c.Id
) g1
WHERE b1.BinId IS NOT NULL
  AND NOT EXISTS
  (
      SELECT 1
      FROM dbo.TripDetails tdx WITH (NOLOCK)
      INNER JOIN trips tt WITH (NOLOCK) ON tt.Id = tdx.TripId 
	  WHERE tdx.TripId = d.TripId
	  AND tt.IsDeleted=0 
        AND tdx.TagId  = d.Tag
        AND tdx.IsDeleted = 0
  );
       
	   
	   ;WITH Dedup3 AS
(
    SELECT
        TripId,
        Tag,
        MIN(MovementTime) AS MovementTime,
        MAX(IMEI) AS IMEI,
        MAX(VehicleId) AS VehicleId
    FROM #DetailsMatchedValidTagOtherThree
    GROUP BY TripId, Tag
)
INSERT INTO #TripDetailsProcessingSummary
(
    Id, LastCompletion, ArrivalTime, TotalDistance, WaterUsedLiters, SweptAreaSquareMeters,
    TripDetailsId, CompletionTime, TenantId, BinLatitude, BinLongitude, BinStatusId, BinWeight,
    CompilationReason, CompletionOrder, CompletionPercentage, NumberOfLefts, NumberOfRotation,
    TotalOfWasteCollectedFromContainer, WasteActualWeight, CreatedBy, ModifiedBy, ModifiedDate,
    TotalGpsDistanceCovered, Description, CreatedDate, CompletionType, TotalBrushDistanceCovered,
    TotalWaterDistanceCovered, IsSwept, ManualLiftReasonLookupId, TrackingDeviceNumber, VehicleId,
    StatusLookupId
)
SELECT
    NEWID(),
    d.MovementTime,
    NULL,
    0, 0, 0,
    td.Id,
    d.MovementTime,
	td.TenantId,
    ISNULL(b1.Latitude, 0),
    ISNULL(b1.Longitude, 0),
    2,
    0,
    NULL,
    1,
    0,
    1,
    0,
    0,
    0,
    ' _fromStatus_3',
    NULL,
    NULL,
    0,
    NULL,
    td.CreatedDate,
    1,
    0,
    0,
    0,
    NULL,
    TRY_CAST(d.IMEI AS BIGINT),
    d.VehicleId,
     15 -- status look up id
FROM #TripDetails td
INNER JOIN Dedup3 d
    ON d.TripId = td.TripId
   AND d.Tag    = td.TagId
OUTER APPLY
(
    -- ✅ take only one bins row for that tag
    SELECT TOP (1) b.Latitude, b.Longitude
    FROM dbo.Bins b WITH (NOLOCK)
    WHERE b.TagId = td.TagId
    ORDER BY b.ModifiedDate DESC, b.CreatedDate DESC, b.Id
) b1


WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.TripDetailsProcessingSummary x WITH (UPDLOCK, HOLDLOCK)
    WHERE x.TripDetailsId = td.Id
);

 

			  ;WITH Dedup4 AS
(
    SELECT
        TripId,
        Tag,
        MIN(MovementTime) AS MovementTime,
        MAX(IMEI) AS IMEI,
        MAX(VehicleId) AS VehicleId
    FROM #DetailsMatchedValidTagOtherFour
    GROUP BY TripId, Tag
)
INSERT INTO #TripDetails
(
    Id, TripId, CompletionType, TagId, ActualWeight, [Order],
    BinId, CreatedDate, CreatedBy, ModifiedDate, ModifiedBy,
    IsDeleted, TenantId, StreetWeightPercentage, StreetLength,
    ReferenceCode, ContractServiceMapGeometryId
)
SELECT 
    NEWID(),
    d.TripId,
    0,
    d.Tag,
    0,
    -1,
    b1.BinId,
    d.MovementTime,
    'System_Status4',
    NULL,
    NULL,
    0,
    @TenantId,
    0,
    0,
    'TRD-00000-00000',
    g1.CsmgId
FROM Dedup4 d
OUTER APPLY
(
    -- ✅ choose exactly one bin for the tag
    SELECT TOP (1) b.Id AS BinId
    FROM dbo.Bins b WITH (NOLOCK)
    WHERE b.TagId = d.Tag
    ORDER BY b.ModifiedDate DESC, b.CreatedDate DESC, b.Id
) b1
OUTER APPLY
(
    -- ✅ choose exactly one geometry for the tag (if multiple exist)
    SELECT TOP (1) c.Id AS CsmgId
    FROM dbo.ContractServiceMapGeometry c WITH (NOLOCK)
    WHERE c.Tag = d.Tag
    ORDER BY c.ModifiedDate DESC, c.CreatedDate DESC, c.Id
) g1
WHERE b1.BinId IS NOT NULL
  AND NOT EXISTS
  (
      SELECT 1
      FROM dbo.TripDetails tdx WITH (NOLOCK)
	  INNER JOIN dbo.Trips tt ON tt.Id = tdx.TripId
      WHERE 
	  
	    tdx.TripId = d.TripId
		AND tt.IsDeleted=0
		AND tdx.TagId  = d.Tag
        AND tdx.IsDeleted = 0
		
  );
        ;WITH Dedup4 AS
(
    SELECT
        TripId,
        Tag,
        MIN(MovementTime) AS MovementTime,
        MAX(IMEI) AS IMEI,
        MAX(VehicleId) AS VehicleId
    FROM #DetailsMatchedValidTagOtherFour
    GROUP BY TripId, Tag
)
INSERT INTO #TripDetailsProcessingSummary
(
    Id, LastCompletion, ArrivalTime, TotalDistance, WaterUsedLiters, SweptAreaSquareMeters,
    TripDetailsId, CompletionTime, TenantId, BinLatitude, BinLongitude, BinStatusId, BinWeight,
    CompilationReason, CompletionOrder, CompletionPercentage, NumberOfLefts, NumberOfRotation,
    TotalOfWasteCollectedFromContainer, WasteActualWeight, CreatedBy, ModifiedBy, ModifiedDate,
    TotalGpsDistanceCovered, Description, CreatedDate, CompletionType, TotalBrushDistanceCovered,
    TotalWaterDistanceCovered, IsSwept, ManualLiftReasonLookupId, TrackingDeviceNumber, VehicleId,
    StatusLookupId
)
SELECT
    NEWID(),
    d.MovementTime,
    NULL,
    0, 0, 0,
    td.Id,
        d.MovementTime,
    td.TenantId,
    ISNULL(b1.Latitude, 0),
    ISNULL(b1.Longitude, 0),
    2,
    0,
    NULL,
    1,
    0,
    1,
    0,
    0,
    0,
    ' _fromStatus_4',
    NULL,
    NULL,
    0,
    NULL,
    td.CreatedDate,
    1,
    0,
    0,
    0,
    NULL,
    TRY_CAST(d.IMEI AS BIGINT),
    d.VehicleId,
     16 -- status look up id
FROM #TripDetails td
INNER JOIN Dedup4 d
    ON d.TripId = td.TripId
   AND d.Tag    = td.TagId
OUTER APPLY
(
    -- ✅ take only one bins row for that tag
    SELECT TOP (1) b.Latitude, b.Longitude
    FROM dbo.Bins b WITH (NOLOCK)
    WHERE b.TagId = td.TagId
    ORDER BY b.ModifiedDate DESC, b.CreatedDate DESC, b.Id
) b1
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.TripDetailsProcessingSummary x WITH (UPDLOCK, HOLDLOCK)

    WHERE x.TripDetailsId = td.Id
);
            -- Insert to real TripDetails
            INSERT INTO dbo.TripDetails
            (
                Id, TripId, CompletionType, TagId, ActualWeight, [Order], BinId,
                CreatedDate, CreatedBy, ModifiedDate, ModifiedBy, IsDeleted, TenantId,
                StreetWeightPercentage, StreetLength, ReferenceCode, ContractServiceMapGeometryId
            )
            SELECT
                Id, TripId, CompletionType, TagId, ActualWeight, [Order], BinId,
                CreatedDate, CreatedBy, ModifiedDate, ModifiedBy, IsDeleted, TenantId,
                StreetWeightPercentage, StreetLength, ReferenceCode, ContractServiceMapGeometryId
            FROM #TripDetails;

            -- Insert to real TripDetailsProcessingSummary (only missing)
            INSERT INTO dbo.TripDetailsProcessingSummary
            (
                Id, LastCompletion, ArrivalTime, TotalDistance, WaterUsedLiters, SweptAreaSquareMeters,
                TripDetailsId, CompletionTime, TenantId, BinLatitude, BinLongitude, BinStatusId, BinWeight,
                CompilationReason, CompletionOrder, CompletionPercentage, NumberOfLefts, NumberOfRotation,
                TotalOfWasteCollectedFromContainer, WasteActualWeight, CreatedBy, ModifiedBy, ModifiedDate,
                TotalGpsDistanceCovered, Description, CreatedDate, CompletionType, TotalBrushDistanceCovered,
                TotalWaterDistanceCovered, IsSwept, ManualLiftReasonLookupId, TrackingDeviceNumber, VehicleId, StatusLookupId
            )
            SELECT
                s.Id, s.LastCompletion, s.ArrivalTime, s.TotalDistance, s.WaterUsedLiters, s.SweptAreaSquareMeters,
                s.TripDetailsId, s.CompletionTime, s.TenantId, s.BinLatitude, s.BinLongitude, s.BinStatusId, s.BinWeight,
                s.CompilationReason, s.CompletionOrder, s.CompletionPercentage, s.NumberOfLefts, s.NumberOfRotation,
                s.TotalOfWasteCollectedFromContainer, s.WasteActualWeight, s.CreatedBy, s.ModifiedBy, s.ModifiedDate,
                s.TotalGpsDistanceCovered, s.Description, s.CreatedDate, s.CompletionType, s.TotalBrushDistanceCovered,
                s.TotalWaterDistanceCovered, s.IsSwept, s.ManualLiftReasonLookupId, s.TrackingDeviceNumber, s.VehicleId, s.StatusLookupId
            FROM #TripDetailsProcessingSummary s
            WHERE NOT EXISTS
            (------------ I Am waiting yazlamah!
                SELECT 1
                FROM dbo.TripDetailsProcessingSummary x 
                WHERE x.TripDetailsId = s.TripDetailsId
            );

            -- Case 5/6 update
          UPDATE tdps
SET 
    tdps.VehicleId = dm.VehicleId,
    tdps.TrackingDeviceNumber = TRY_CAST(dm.Imei AS BIGINT),
    tdps.BinLongitude = dm.BinLongitude,
    tdps.BinLatitude  = dm.BinLatitude,
    tdps.ModifiedBy   = 'SP_DynamicServiceStored_BIN_CaseFive',
    tdps.ModifiedDate = @CurrentTime,
 
    tdps.BinStatusId =
        CASE 
            WHEN dm.BinStatusId = 1 THEN 2 
            ELSE tdps.BinStatusId 
        END,
 
    tdps.CompletionTime =
        CASE 
            WHEN dm.BinStatusId = 1 THEN dm.MovementTime 
            ELSE tdps.CompletionTime 
        END,
 
    tdps.LastCompletion =
        CASE
            WHEN dm.BinStatusId = 1 THEN dm.MovementTime
            WHEN dm.BinStatusId = 2 
                 AND DATEDIFF(MINUTE, tdps.LastCompletion, dm.MovementTime) >= 60
            THEN dm.MovementTime
            ELSE tdps.LastCompletion
        END,
 
    tdps.NumberOfLefts =
        CASE
            WHEN dm.BinStatusId = 1 THEN 1
            WHEN dm.BinStatusId = 2 
                 AND DATEDIFF(MINUTE, tdps.LastCompletion, dm.MovementTime) >= 60
            THEN tdps.NumberOfLefts + 1
            ELSE tdps.NumberOfLefts
        END,
 
    tdps.StatusLookupId =17
    
FROM dbo.TripDetailsProcessingSummary tdps
INNER JOIN #DetailsMatchedValidTagOtherFive dm
    ON tdps.Id = dm.TripDetailsProcessingSummaryId AND     tdps.StatusLookupId IS NULL;
 

      UPDATE tdps
SET 
    tdps.VehicleId = dm.VehicleId,
    tdps.TrackingDeviceNumber = TRY_CAST(dm.Imei AS BIGINT),
    tdps.BinLongitude = dm.BinLongitude,
    tdps.BinLatitude  = dm.BinLatitude,
    tdps.ModifiedBy   = 'SP_DynamicServiceStored_BIN_CaseSix',
    tdps.ModifiedDate = @CurrentTime,
 
    tdps.BinStatusId =
        CASE 
            WHEN dm.BinStatusId = 1 THEN 2 
            ELSE tdps.BinStatusId 
        END,
 
    tdps.CompletionTime =
        CASE 
            WHEN dm.BinStatusId = 1 THEN dm.MovementTime 
            ELSE tdps.CompletionTime 
        END,
 
    tdps.LastCompletion =
        CASE
            WHEN dm.BinStatusId = 1 THEN dm.MovementTime
            WHEN dm.BinStatusId = 2 
                 AND DATEDIFF(MINUTE, tdps.LastCompletion, dm.MovementTime) >= 60
            THEN dm.MovementTime
            ELSE tdps.LastCompletion
        END,
 
    tdps.NumberOfLefts =
        CASE
            WHEN dm.BinStatusId = 1 THEN 1
            WHEN dm.BinStatusId = 2 
                 AND DATEDIFF(MINUTE, tdps.LastCompletion, dm.MovementTime) >= 60
            THEN tdps.NumberOfLefts + 1
            ELSE tdps.NumberOfLefts
        END,
 
    tdps.StatusLookupId =18
    
FROM dbo.TripDetailsProcessingSummary tdps
INNER JOIN #DetailsMatchedValidTagOtherSix dm
    ON tdps.Id = dm.TripDetailsProcessingSummaryId AND     tdps.StatusLookupId IS NULL;
 


            -- Case 7 insert LatestTagEvent
            INSERT INTO dbo.LatestTagEvent
            (
                Id, Tag, TrackingDeviceNumber, VehicleId, BinId, IsDeleted,
                Createdby, ModifiedBy, CreatedDate, ModifiedDate, TenantId
            )
            SELECT
                NEWID(), xxx.Tag, xxx.IMEI, vv.Id, bb.Id, 0,
               '_recoverForCase_7', @TenantId, xxx.MovementTime, xxx.MovementTime, @TenantId
            FROM #DetailsMatchedValidTagOtherCases xxx
            LEFT JOIN dbo.Bins bb ON xxx.Tag = bb.TagId
            LEFT JOIN dbo.Vehicle vv ON xxx.VehicleId = vv.Id
			WHERE bb.IsDeleted=0 AND vv.IsDeleted=0;

				-- update LastCompletion column in bin table
				UPDATE bn
				SET bn.LastCompletion = x.LatestMovementTime
				FROM dbo.Bins bn
				JOIN
				(
					SELECT 
						Tag,
						MAX(MovementTime) AS LatestMovementTime
					FROM #DetailsMatchedValidTagOtherCases
					GROUP BY Tag
				) x
					ON x.Tag = bn.TagId
				WHERE bn.IsDeleted = 0;


            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH;





  /* ======================================================
   Step 5.0: Calculate Waste Weight on Each Trip Level
   ====================================================== */

















        /* ======================================================
           Step 3: Aggregate lifted bins and compute trip completion
        ====================================================== */
        ;WITH TripLiftedBinSet AS
        (
            SELECT
                t.Id AS TripId,
                tps.Id AS TripProcessingSummaryId,
                t.OperationalPlansId,
                COUNT(CASE WHEN dt.BinStatusId = 1 THEN 1 END) AS CurrentLiftBinCount,
                tps.ExpectedCovarge AS ExpectedCoverage,
                tps.ActualCovarge   AS ActualCoverage,
                op.ContractServiceId,
                op.ContractId,
                cs.ServiceGroupId,
                ct.Id AS ContractTypeId,
                cs.ServiceGroupType,
                c.ContractingCompanyId,
                op.CountActiveTrip,
                op.TotalTripsCompletionPercentaion AS OperationalPlanOldAverage
            FROM #DetailsMatchedValidTag dt
            INNER JOIN dbo.Trips t WITH (NOLOCK) ON dt.TripId = t.Id
            INNER JOIN dbo.TripProcessingSummary tps WITH (NOLOCK) ON t.Id = tps.TripId
            INNER JOIN dbo.OperationalPlans op WITH (NOLOCK) ON t.OperationalPlansId = op.Id
            INNER JOIN dbo.ContractServices cs WITH (NOLOCK) ON op.ContractServiceId = cs.Id AND cs.IsDeleted = 0
            INNER JOIN dbo.Contracts c WITH (NOLOCK) ON c.Id = cs.ContractId
            INNER JOIN dbo.ContractTypes ct WITH (NOLOCK) ON ct.Id = c.ContractTypeId
            INNER JOIN dbo.ServiceGroups sg WITH (NOLOCK) ON sg.Id = cs.ServiceGroupId
            GROUP BY 
                t.Id, tps.Id, t.OperationalPlansId,
                tps.ExpectedCovarge, tps.ActualCovarge,
                op.ContractServiceId, op.ContractId,
                cs.ServiceGroupId, ct.Id, cs.ServiceGroupType,
                c.ContractingCompanyId, op.CountActiveTrip, op.TotalTripsCompletionPercentaion
        )
        INSERT INTO #TripProcessingContext
        (
            TripId, TripProcessingSummaryId, OperationalPlansId,
            CurrentLiftBinCount, ExpectedCoverage, ActualCoverage,
            TotalLiftedCount, TripCompletionPercentage,
            ContractServiceId, ContractId, ServiceGroupId,
            ContractTypeId, ServiceGroupType, ContractingCompanyId,
            CountActiveTrip, OperationalPlanOldAverage
        )
        SELECT
            TripId,
            TripProcessingSummaryId,
            OperationalPlansId,
            CurrentLiftBinCount,
            ExpectedCoverage,
            ActualCoverage,
            (CurrentLiftBinCount + ActualCoverage) AS TotalLiftedCount,
            CAST((CurrentLiftBinCount + ActualCoverage) * 100.0 / NULLIF(ExpectedCoverage,0) AS DECIMAL(18,2)) AS TripCompletionPercentage,
            ContractServiceId,
            ContractId,
            ServiceGroupId,
            ContractTypeId,
            ServiceGroupType,
            ContractingCompanyId,
            CountActiveTrip,
            OperationalPlanOldAverage
        FROM TripLiftedBinSet
        WHERE TripId IS NOT NULL;

        



-- --------------------------------------------------------
-- 5.4: Aggregate per-AVL-record payloads up to trip level.
--
--      Formula per AVL record:
--
--        PayloadWeight = 
--            (FullWeight - EmptyWeight)          <- weight range of vehicle
--            / (FullVoltage - EmptyVoltage)      <- voltage range (sensitivity)
--            * (Io9 - EmptyVoltage)              <- actual measured voltage offset
--
--      Guards:
--        - Io9 IS NULL          => treat record as 0 (no sensor reading)
--        - Voltage range = 0    => treat record as 0 (avoid division by zero)
--
--      Then SUM all AVL record payloads per TripId
-- --------------------------------------------------------



-- --------------------------------------------------------
-- 5.2: Populate staging table from all matching cases.
--      Each case independently contributes its own rows
--      (a trip only needs to match ONE case to be included)
-- --------------------------------------------------------

-- Case 1: Direct tag match
INSERT INTO #WasteBinCollectionPreCalculation 
    (TripId, FullVoltage, EmptyVoltage, EmptyWeight, FullWeight, Io9)
SELECT
    tps.TripId,
    vt.FullVoltage,
    vt.EmptyVoltage,
    vt.EmptyWeight,
    vt.FullWeight,
    c1.Io9
FROM       dbo.TripProcessingSummary          tps
INNER JOIN #DetailsMatchedValidTag            c1  ON c1.TripId = tps.TripId
INNER JOIN Vehicle                            v   ON v.Id      = c1.VehicleId
INNER JOIN VehicleType                        vt  ON vt.Id     = v.VehicleTypeId

UNION ALL

-- Case 3: Other-three tag match
SELECT
    tps.TripId,
    vt.FullVoltage,
    vt.EmptyVoltage,
    vt.EmptyWeight,
    vt.FullWeight,
    c3.Io9
FROM       dbo.TripProcessingSummary          tps
INNER JOIN #DetailsMatchedValidTagOtherThree  c3  ON c3.TripId = tps.TripId
INNER JOIN Vehicle                            v   ON v.Id      = c3.VehicleId
INNER JOIN VehicleType                        vt  ON vt.Id     = v.VehicleTypeId

UNION ALL

-- Case 5: Other-five tag match
SELECT
    tps.TripId,
    vt.FullVoltage,
    vt.EmptyVoltage,
    vt.EmptyWeight,
    vt.FullWeight,
    c5.Io9
FROM       dbo.TripProcessingSummary          tps
INNER JOIN #DetailsMatchedValidTagOtherFive   c5  ON c5.TripId = tps.TripId
INNER JOIN Vehicle                            v   ON v.Id      = c5.VehicleId
INNER JOIN VehicleType                        vt  ON vt.Id     = v.VehicleTypeId;

INSERT INTO #TripWasteWeightCalculated 
    (TripId, TotalWasteWeight)
SELECT
    wbc.TripId,
    SUM(
        CASE
            -- No sensor reading
            WHEN wbc.Io9 IS NULL THEN 0

            -- Invalid voltage range
            WHEN (wbc.FullVoltage - wbc.EmptyVoltage) = 0 THEN 0

            ELSE
                CASE
                    -- If calculated weight is negative → ignore
                    WHEN (
                        (wbc.FullWeight - wbc.EmptyWeight)
                        / NULLIF((wbc.FullVoltage - wbc.EmptyVoltage), 0)
                        * (wbc.Io9 - wbc.EmptyVoltage)
                    ) < 0
                    THEN 0

                    -- Otherwise use actual value
                    ELSE
                        (
                            (wbc.FullWeight - wbc.EmptyWeight)
                            / NULLIF((wbc.FullVoltage - wbc.EmptyVoltage), 0)
                            * (wbc.Io9 - wbc.EmptyVoltage)
                        )
                END
        END
    ) AS TotalWasteWeight
FROM #WasteBinCollectionPreCalculation wbc
GROUP BY wbc.TripId;


        /* ======================================================
           Step 5.1: Update TripProcessingSummary (ActualStartTrip from first MovementTime)
        ====================================================== */
           BEGIN TRY
            BEGIN TRANSACTION;

            ;WITH FirstTripMovement AS
            (
                SELECT
                    ctx.TripProcessingSummaryId,
                    MIN(dm.MovementTime) AS FirstMovementTime
                FROM #TripProcessingContext ctx
                INNER JOIN #DetailsMatchedValidTag dm
                    ON dm.TripId = ctx.TripId
                GROUP BY ctx.TripProcessingSummaryId
            )
            UPDATE tps WITH (ROWLOCK)
            SET 
                tps.ActualWasteWeight=tps.ActualWasteWeight+twwc.TotalWasteWeight,---waste collection per trip
                tps.ActualCovarge = ctx.TotalLiftedCount,
                tps.CompletionPercentage =
                    CASE 
                        WHEN ctx.TripCompletionPercentage > 100 THEN 100
                        ELSE ctx.TripCompletionPercentage
                    END,
                tps.ActualStartTrip =
                    CASE 
                        WHEN tps.ActualStartTrip IS NULL AND ftm.FirstMovementTime IS NOT NULL
                        THEN ftm.FirstMovementTime
                        ELSE tps.ActualStartTrip
                    END,
                tps.ModifiedDate = @CurrentTime,
                tps.ModifiedBy = 'SP_DynamicServiceStored_Bin',
                tps.Status = 2
            FROM dbo.TripProcessingSummary AS tps
            INNER JOIN #TripProcessingContext AS ctx 
                ON tps.Id = ctx.TripProcessingSummaryId
            LEFT JOIN FirstTripMovement ftm
                ON ftm.TripProcessingSummaryId = ctx.TripProcessingSummaryId
            left join #TripWasteWeightCalculated twwc on tps.TripId=twwc.TripID;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH;





		  /* ======================================================
           Step 6+: OP 
        ====================================================== */

        INSERT INTO #NewCombinedAverageForOperationalPlan (OperationalPlansId, CombinedAverage)
        SELECT 
            tps.OperationalPlansId,
            (
                (tps.OperationalPlanOldAverage * tps.CountActiveTrip)
                + (AVG(tps.TripCompletionPercentage) * COUNT(tps.TripId))
            ) / NULLIF((tps.CountActiveTrip + COUNT(tps.TripId)), 0)
        FROM #TripProcessingContext tps
        GROUP BY tps.OperationalPlansId, tps.CountActiveTrip, tps.OperationalPlanOldAverage;

        ;WITH RankedPlans AS
        (
            SELECT
                cte.OperationalPlansId,
                cte.CombinedAverage AS OperationalPlanCompletionPercentage,
                ctx.ContractServiceId,
                ctx.ContractId,
                ctx.ServiceGroupId,
                ROW_NUMBER() OVER (PARTITION BY cte.OperationalPlansId ORDER BY ctx.ContractServiceId) AS rn
            FROM #TripProcessingContext ctx
            INNER JOIN #NewCombinedAverageForOperationalPlan cte 
                ON cte.OperationalPlansId = ctx.OperationalPlansId
        )
        INSERT INTO #OperationalPlanCompletionSummary
        (
            OperationalPlansId, OperationalPlanCompletionPercentage,
            ContractServiceId, ContractId, ServiceGroupId
        )
        SELECT
            OperationalPlansId, OperationalPlanCompletionPercentage,
            ContractServiceId, ContractId, ServiceGroupId
        FROM RankedPlans
        WHERE rn = 1;





        
-- ==============================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ================Notification_EVENT_TRIGGER=============
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================


-- ============================================================
--  stage bin-lift outside-scope rows.
-- Category 2 = vehicle lifted a bin in its own contract scope
--              but was triggered by the SP's cross-scope logic
--              (ContractTypeId match).
-- Category 1 = genuine cross-scope lift (mismatch).
-- ============================================================

INSERT INTO BinLiftOutsideScopeEvents
(
    TenantId,
    Category,
    PlateNumber,
    ContainerSlot,
    ContractingCompanyId,
    ContractTypeId,
    ContractName,
    Latitude,
    Longitude,
    LiftedAt,
    VehicleId
)
-- ── Case 3: AVL cross-scope matches (third temp table) ──────
SELECT
@TenantId,
    CASE
        WHEN b.ContractTypeId = v.ContractTypeId THEN 1
        ELSE 2
    END                         AS Category,
    v.PlateNumber               AS PlateNumber,
    b.TagId                     AS ContainerSlot,
    v.ContractingCompanyId      AS ContractingCompanyId,
    v.ContractTypeId            AS ContractTypeId,
    ct.Name                     AS ContractName,      -- human-readable name, not the raw FK
    case3.BinLatitude           AS Latitude,
    case3.BinLongitude          AS Longitude,
    case3.MovementTime          AS LiftedAt,
    v.Id                        AS VehicleId
FROM  #DetailsMatchedValidTagOtherThree AS case3
INNER JOIN Bins          AS b  ON b.TagId          = case3.Tag
INNER JOIN Vehicle       AS v  ON v.Id             = case3.VehicleId
INNER JOIN ContractTypes AS ct ON v.ContractTypeId = ct.Id

UNION ALL

--── Case 4: AVL cross-scope matches (fourth temp table) ─────
SELECT
@TenantId,
    CASE
        WHEN b.ContractTypeId = v.ContractTypeId THEN 1
        ELSE 2
    END                         AS Category,
    v.PlateNumber               AS PlateNumber,
    b.TagId                     AS ContainerSlot,
    v.ContractingCompanyId      AS ContractingCompanyId,
    v.ContractTypeId            AS ContractTypeId,
    ct.Name                     AS ContractName,
    case4.BinLatitude           AS Latitude,
    case4.BinLongitude          AS Longitude,
    case4.MovementTime          AS LiftedAt,
    v.Id                        AS VehicleId
FROM  #DetailsMatchedValidTagOtherFour AS case4
INNER JOIN Bins          AS b  ON b.TagId          = case4.Tag
INNER JOIN Vehicle       AS v  ON v.Id             = case4.VehicleId
INNER JOIN ContractTypes AS ct ON v.ContractTypeId = ct.Id;


-- ==================================================
-- ==================================================
-- ==================================================
-- ==============stage tags whose latest read exceeds the reference distance====================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
DECLARE @distanceThresholdMeters INT = 5;

INSERT INTO dbo.TagLocationViolation
(
    Id,
    Tag,
    Longitude,
    Latitude,
    ViolationDate,
    TenantId,
    CreatedAt,
    ContractingCompanyId,
    ContractTypeId,
    VehicleId
)
SELECT
    NEWID(),
    v.Tag,
    v.Longitude,
    v.Latitude,
    v.MovementTime,
    @TenantId,
    GETDATE(),
    b.ContractingCompanyId,
    b.ContractTypeId,
    v.VehicleId
FROM #TempAvlPatchForLifting v
INNER JOIN dbo.TagReferenceLocation ref WITH (NOLOCK)
    ON ref.Tag = v.Tag
INNER JOIN dbo.Bins b WITH (NOLOCK)
on b.TagId=v.Tag
    AND ref.ReferencePoint IS NOT NULL
    AND geography::Point(v.Latitude, v.Longitude, 4326)
        .STDistance(ref.ReferencePoint) > @distanceThresholdMeters
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.TagLocationViolation vio WITH (NOLOCK)
    WHERE vio.Tag = v.Tag
);

-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================









-- ==============================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ================SWEEPING==========================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================
-- ==================================================


  INSERT INTO #ValidVehicleLocations (
			TripId,
			TripDetailsProcessingSummaryId,
			TripProcessingSummaryId, 
			OperationalPlansId,
			ContractServiceId ,
			ContractId ,
			ServiceGroupId ,
			MovementTime,
			VehicleId,
			Longitude, Latitude, Input1, Input2, Input3,Input4, Speed, Ignition,
			VehicleType, ContractingCompanyType, CountActiveTrip ,
			OperationalPlanOldAverage ,StreetWeightPercentage,StreetLength,StreetOrder,TotalDistance,ContractingCompanyId,ServiceGroupType,ContractTypeId
		)
		SELECT 
			t.Id,tdps.Id, tps.Id, t.OperationalPlansId,op.ContractServiceId,op.ContractId,
			cs.ServiceGroupId, 
			x.MovementTime, x.VehicleId,
			x.Longitude, x.Latitude, x.Input1, x.Input2, x.Input3,x.Input4,
			x.Speed, x.Ignition, vt.Type, cg.Type,
			OP.CountActiveTrip,op.TotalTripsCompletionPercentaion AS OperationalPlanOldAverage,
			td.StreetWeightPercentage,td.StreetLength
			,td.[Order] AS StreetOrder,
			tdps.TotalDistance,
			cg.Id,
			cs.ServiceGroupType,
			ct.Id AS ContractTypeId
		FROM #TempAvlPatchForSweeping x
			INNER JOIN dbo.VehicleOperationalPlan vop WITH (NOLOCK) ON vop.vehicleId= x.VehicleId
			INNER JOIN dbo.OperationalPlans op  WITH (NOLOCK) ON 
			vop.OperationalPlansId=op.Id
			INNER JOIN dbo.ContractServices cs WITH (NOLOCK) ON 
			op.ContractServiceId =cs.Id
			INNER JOIN dbo.Contracts c WITH (NOLOCK) ON c.Id=cs.ContractId 
			INNER JOIN dbo.ContractTypes ct WITH (NOLOCK) ON ct.id=c.ContractTypeId
		INNER JOIN Trips t WITH (NOLOCK)
			ON t.OperationalPlansId = op.Id
			AND t.StartTrip <= x.MovementTime AND t.EndTrip > x.MovementTime
		INNER JOIN Vehicle v WITH (NOLOCK)
			ON vop.VehicleId = v.Id
		INNER JOIN VehicleType vt WITH (NOLOCK)
			ON v.VehicleTypeId = vt.Id
		INNER JOIN ContractingCompanies cg WITH (NOLOCK)
			ON v.ContractingCompanyId = cg.Id
		INNER JOIN TripProcessingSummary tps WITH (NOLOCK)
			ON t.Id = tps.TripId
			INNER JOIN dbo.TripDetails td WITH (NOLOCK) ON td.TripId = t.Id
			INNER JOIN dbo.ContractServiceMapGeometry csmg ON td.ContractServiceMapGeometryId = csmg.Id AND csmg.GeoType=2
			INNER JOIN dbo.TripDetailsProcessingSummary tdps WITH (NOLOCK) ON td.Id= tdps.TripDetailsId
			CROSS APPLY (
		SELECT geometry::Point(x.Longitude, x.Latitude, 4326) AS VehiclePoint
	) AS vp
	WHERE 
	t.IsDeleted=0
	AND
	x.MovementTime BETWEEN t.StartTrip AND t.EndTrip  
	AND
	t.Status=3 
			AND csmg.Geometry.STDistance(vp.VehiclePoint) <= @tolerance;
	 

	 

-- ==============================================
-- ==============================================
-- ======================LOG (insert records )=====================
-- ===================after that only update records ===========================
-- ==============================================
BEGIN TRY
 BEGIN TRANSACTION

MERGE dbo.DynamicServiceProcessLog AS target
USING (
    SELECT * FROM (
        -- Source 1: From #TripProcessingContext (Lifting)
        SELECT  
            ctx.OperationalPlansId AS OperationalPlanId,
            ctx.ContractServiceId,
            ctx.ContractId,
            ctx.ServiceGroupId,
            ctx.ContractingCompanyId,
            @TenantId AS TenantId,
            ctx.ServiceGroupType AS GroupServiceType,
            ctx.ContractTypeId AS ContractTypeId,
            GETDATE() AS LogDateTime,
            'System' AS CreatedBy,
            @Today AS CreatedDate,
            ROW_NUMBER() OVER (PARTITION BY ctx.OperationalPlansId ORDER BY ctx.OperationalPlansId) AS rn
        FROM #TripProcessingContext ctx
        
        UNION ALL
        
        -- Source 2: From #ValidVehicleLocations (Sweeping)
        SELECT  
            ctx.OperationalPlansId AS OperationalPlanId,
            ctx.ContractServiceId,
            ctx.ContractId,
            ctx.ServiceGroupId,
            ctx.ContractingCompanyId,
            @TenantId AS TenantId,
            ctx.ServiceGroupType AS GroupServiceType,
            ctx.ContractTypeId AS ContractTypeId,
            GETDATE() AS LogDateTime,
            'SP_Streets' AS CreatedBy,
            @Today AS CreatedDate,
            ROW_NUMBER() OVER (PARTITION BY ctx.OperationalPlansId ORDER BY ctx.OperationalPlansId) AS rn
        FROM #ValidVehicleLocations ctx
    ) sub
    WHERE rn = 1
) AS src
ON 
    target.OperationalPlanId = src.OperationalPlanId
    AND target.ContractServiceId = src.ContractServiceId
    AND target.ContractId = src.ContractId
    AND target.ServiceGroupId = src.ServiceGroupId
    AND target.ContractingCompanyId = src.ContractingCompanyId
    AND target.TenantId = src.TenantId
    AND target.CreatedDate = @Today
WHEN MATCHED THEN 
    UPDATE SET 
        target.ModifiedDate = GETDATE(),
        target.ModifiedBy = CASE 
            WHEN src.CreatedBy = 'System' THEN 'SP_DynamicServiceStored_lifting'
            WHEN src.CreatedBy = 'SP_Streets' THEN 'SP_DynamicServiceStored_streeting'
            ELSE 'SP_DynamicServiceStored'
        END
WHEN NOT MATCHED THEN 
    INSERT (
        Id,
        OperationalPlanId,
        ContractServiceId,
        ContractId,
        ServiceGroupId,
        ContractingCompanyId,
        TenantId,
        GroupServiceType,
        ContractTypeId,
		ContractType,
        LogDateTime,
        CreatedBy,
        CreatedDate
    )
    VALUES (
        NEWID(),
        src.OperationalPlanId,
        src.ContractServiceId,
        src.ContractId,
        src.ServiceGroupId,
        src.ContractingCompanyId,
        src.TenantId,
        src.GroupServiceType,
        src.ContractTypeId,
		0,
        src.LogDateTime,
        src.CreatedBy,
        src.CreatedDate
    );

	
COMMIT TRANSACTION;
END TRY
BEGIN CATCH
IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
THROW;
END CATCH;
	-- ==============================================
-- ==============================================
-- ==============================================






	 -- I Need to calculate each street length!! 
	  ---NEXT STEP GETTEING OR  SPLITTING Last (long,lattiude)
	  
			  
		  ;WITH OrderedLocations AS (
        SELECT *,
            LAG(Latitude) OVER (PARTITION BY VehicleId ORDER BY MovementTime) AS LastLatitude,
            LAG(Longitude) OVER (PARTITION BY VehicleId ORDER BY MovementTime) AS LastLongitude
        FROM #ValidVehicleLocations
    )
    INSERT INTO #TripDetailsProcessingSummarySession (
        TripId, TripProcessingSummaryId,TripDetailsProcessingSummaryId,
		StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance ,OperationalPlansId, ContractServiceId, ContractId, ServiceGroupId,
        CurrentLatitude, CurrentLongitude, LastLatitude, LastLongitude,
        VehicleType, ContractingCompanyType,
        Input1, Input2, Input3,Input4, Speed, Ignition,
        SessionBrushDistanceCovered, SessionTotalWaterDistanceCoveredPatch, SessionGpsDistanceCoveredPatch,CountActiveTrip
		,OperationalPlanOldAverage,MovementTime
    )
    SELECT 
        TripId, TripProcessingSummaryId,TripDetailsProcessingSummaryId,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance, OperationalPlansId, ContractServiceId, ContractId, ServiceGroupId,
        Latitude, Longitude, LastLatitude, LastLongitude,
        VehicleType, ContractingCompanyType,
        Input1, Input2, Input3,Input4, Speed, Ignition,
        0, 0, 0,CountActiveTrip
		,OperationalPlanOldAverage,MovementTime
    FROM OrderedLocations;
	---------------------------------------------------
    -- Step 2b: Calculate distances + validity flags, insert into #StreetWithValidity
;WITH CalculatedDistanceCTE AS (
    SELECT *,
        6371000 * 2 * ASIN(SQRT(
            POWER(SIN(RADIANS((CurrentLatitude  - LastLatitude)  / 2)), 2) +
            COS(RADIANS(CurrentLatitude)) * COS(RADIANS(LastLatitude)) *
            POWER(SIN(RADIANS((CurrentLongitude - LastLongitude) / 2)), 2)
        )) AS DistanceInMeters,
        -- Water validity
        CASE
            WHEN
                  --LARGE SWEEPER WITH FAHAD COMPANY
                 (VehicleType=16 AND ContractingCompanyType=1 AND Input3>0)
                OR
                  --SMALL SWEEPER WITH FAHAD COMPANY/ BAYT AL ARAB COMPANY/saader cp
                 (VehicleType=24 AND (ContractingCompanyType=3 OR ContractingCompanyType=2 OR  ContractingCompanyType=1) AND Input1>0)
                OR

                 --LARGE SWEEPER WITH BAYT AL ARAB COMPANY (right or left) 
                 (VehicleType=16 AND ContractingCompanyType=3 AND (Input2>0 OR Input3>0))
                OR 
                 --MAGRORAR (TRAILED) SWEEPER WITH SAADER COMPANY/al fahad ccompany 
                 (VehicleType=4 AND (ContractingCompanyType=2 OR ContractingCompanyType=1) AND Input3>0)

            THEN 1 ELSE 0.
        END AS WaterValid,
        -- Brush validity
        CASE
            WHEN 
            --Large sweeper for al-fahad  company
            (VehicleType=16 AND ContractingCompanyType =1 AND Input2>0)
            OR
            --SMALL sweeper for al-fahad  company/ BAYT AL ARAB (set brush on ground!) and (BRUSH IS TURNING ON!)

              --SMALL sweeper for al-fahad  company/ BAYT AL ARAB ( up brush from ground!)
             (VehicleType =24 AND ContractingCompanyType IN (1,2,3) AND Input4  >0AND Input2  >0)
             OR
             --Large sweeper for BAYT AL ARAB  company (RIGHT/LEFT BRUSH IS WORKING!)
            (VehicleType=16 AND ContractingCompanyType =3 AND (Input1>0 OR Input4>0))
            OR
            --trailed(مجرورة) sweeper for fahad company/sadder
            (VehicleType=4 AND ContractingCompanyType in(1,2) AND Input2>0)
            THEN 1 ELSE 0
        END AS BrushValid,
        -- GPS validity
        CASE WHEN Speed BETWEEN 0.5 AND 30 
        --AND Ignition=1
        THEN 1 ELSE 0 END AS GpsValid,
        -- Big vehicle for bayt al arab  left/right sides
        CASE WHEN VehicleType=16 AND ContractingCompanyType=3 AND Input1>0 AND Input2>0 THEN 1 ELSE 0 END AS IsRightValid, 
        CASE WHEN VehicleType=16 AND ContractingCompanyType=3 AND Input3>0 AND Input4>0 THEN 1 ELSE 0 END AS IsLeftValid
    FROM #TripDetailsProcessingSummarySession
    WHERE LastLatitude IS NOT NULL  -- skip the first point (no pair)
    )
INSERT INTO #StreetWithValidity (
    TripId, TripProcessingSummaryId, TripDetailsProcessingSummaryId,
    OperationalPlansId, ContractServiceId, ContractId, ServiceGroupId,
    VehicleType, ContractingCompanyType,
    ValidDistance, WaterDistanceFinal, BrushDistanceFinal, GpsDistanceFinal,
    CountActiveTrip, StreetOrder, StreetLength, StreetWeightPercentage,
    OperationalPlanOldAverage, StreetCompletionPercentage
)
SELECT
    TripId, TripProcessingSummaryId, TripDetailsProcessingSummaryId,
    OperationalPlansId, ContractServiceId, ContractId, ServiceGroupId,
    VehicleType, ContractingCompanyType,
    -- ValidDistance
  SUM(CASE 
    WHEN GpsValid = 1 AND (
        (VehicleType = 16 AND ContractingCompanyType = 3 AND (IsLeftValid = 1 OR IsRightValid = 1))
        OR 
        (NOT (VehicleType = 16 AND ContractingCompanyType = 3) AND WaterValid = 1 AND BrushValid = 1)
    ) THEN DistanceInMeters 
    ELSE 0 
END) AS TotalValidStreetDistance,

    SUM(
        CASE 
            WHEN WaterValid = 1 
            THEN DistanceInMeters 
            ELSE SessionTotalWaterDistanceCoveredPatch 
        END
    ) AS TotalWaterStreetValidDsitnace,

    SUM(
        CASE 
            WHEN BrushValid = 1 
            THEN DistanceInMeters 
            ELSE SessionBrushDistanceCovered 
        END
    ) AS TotalBrushStreetValidDsitnace,

    SUM(
        CASE 
            WHEN GpsValid = 1 
            THEN DistanceInMeters 
            ELSE SessionGpsDistanceCoveredPatch 
        END
    ) AS TotalGpsStreetValidDsitnace,

    CountActiveTrip,
    StreetOrder,
    StreetLength,
    StreetWeightPercentage,
    OperationalPlanOldAverage,
    -- StreetCompletionPercentage
    CASE 
        WHEN
            SUM(
               
                       CASE 
            WHEN GpsValid = 1 AND (
                (VehicleType = 16 AND ContractingCompanyType = 3 AND (IsLeftValid = 1 OR IsRightValid = 1))
                OR 
                (NOT (VehicleType = 16 AND ContractingCompanyType = 3) AND WaterValid = 1 AND BrushValid = 1)
            )
                    THEN DistanceInMeters
                    ELSE 0
                END
            ) > StreetLength
        THEN 100
        ELSE
            COALESCE(
                (
                    TotalDistance
                    + SUM(
                     CASE 
            WHEN GpsValid = 1 AND (
                (VehicleType = 16 AND ContractingCompanyType = 3 AND (IsLeftValid = 1 OR IsRightValid = 1))
                OR 
                (NOT (VehicleType = 16 AND ContractingCompanyType = 3) AND WaterValid = 1 AND BrushValid = 1)
            )
                            THEN DistanceInMeters
                            ELSE 0
                        END
                    )
                ) / NULLIF(StreetLength, 0) * 100,
                0
            )
    END AS StreetCompletionPercentage
FROM CalculatedDistanceCTE
GROUP BY TripId, TripProcessingSummaryId, TripDetailsProcessingSummaryId,
    OperationalPlansId, ContractServiceId, ContractId, ServiceGroupId,
    VehicleType, ContractingCompanyType,
    CountActiveTrip, StreetOrder, StreetLength, StreetWeightPercentage,
    TotalDistance, OperationalPlanOldAverage;

	-- you need to add street completion percentage to trip with validaity table , and then calucalte weigthed average for streetes for each trip , op => grou[p


		


-- =============================================================
-- Step: Update street summary processing Info & street completion percentage 
-- =============================================================

BEGIN TRY
BEGIN TRANSACTION;

UPDATE tdps
SET 
    IsSwept=1,
    TotalDistance =
	tdps.TotalDistance + COALESCE(swv.ValidDistance, 0),
CompletionPercentage = CASE 
    WHEN COALESCE(NULLIF(swv.StreetCompletionPercentage, 0), tdps.CompletionPercentage) > 100 
        THEN 100
    ELSE COALESCE(NULLIF(swv.StreetCompletionPercentage, 0), tdps.CompletionPercentage)
END
,
    TotalBrushDistanceCovered = COALESCE(NULLIF(swv.BrushDistanceFinal, 0), tdps.TotalBrushDistanceCovered),
    TotalWaterDistanceCovered = COALESCE(NULLIF(swv.WaterDistanceFinal, 0), tdps.TotalWaterDistanceCovered),
    TotalGpsDistanceCovered = COALESCE(NULLIF(swv.GpsDistanceFinal, 0), tdps.TotalGpsDistanceCovered),
ModifiedBy = 'SP_DynamicServiceStored_StreetInfo',
ModifiedDate=GETDATE()
FROM dbo.TripDetailsProcessingSummary tdps WITH (NOLOCK) 
INNER JOIN #StreetWithValidity swv ON tdps.Id=swv.TripDetailsProcessingSummaryId;

COMMIT TRANSACTION;
END TRY
BEGIN CATCH
IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
THROW;
END CATCH;
	-- =============================================================
	-- =============================================================


-- Step 2: Insert data into the temp table
INSERT INTO #TripWithCompletion (
    TripProcessingSummaryId,
    OperationalPlansId,
    CountActiveTrip,
    ContractServiceId,
    ServiceGroupId,
    ContractId,
	OperationalPlanOldAverage,
	TripId,
    TripWeightedCompletionPercentage,
	TotalValidDistance
)
SELECT
    tps.Id AS TripProcessingSummaryId,
    t.OperationalPlansId,
    swv.CountActiveTrip,
    swv.ContractServiceId,
    swv.ServiceGroupId,
    swv.ContractId,
	swv.OperationalPlanOldAverage,
	swv.TripId,
    CASE 
        WHEN SUM(td.StreetWeightPercentage) = 0 THEN 0
        ELSE SUM(tdps.CompletionPercentage * td.StreetWeightPercentage) / SUM(td.StreetWeightPercentage)
    END AS TripWeightedCompletionPercentage,
	MAX(swv.TotalValidDistance)
FROM dbo.Trips t
INNER JOIN (
    SELECT 
        TripId,
        SUM(ValidDistance) AS TotalValidDistance,
        MAX(CountActiveTrip) AS CountActiveTrip,
        MAX(ContractServiceId) AS ContractServiceId,
        MAX(ServiceGroupId) AS ServiceGroupId,
        MAX(ContractId) AS ContractId,
        MAX(OperationalPlanOldAverage) AS OperationalPlanOldAverage
    FROM #StreetWithValidity
    GROUP BY TripId
) swv ON swv.TripId = t.Id
INNER JOIN dbo.TripProcessingSummary tps WITH (NOLOCK) ON tps.TripId = t.Id
INNER JOIN dbo.TripDetails td WITH (NOLOCK) ON td.TripId = t.Id
INNER JOIN dbo.TripDetailsProcessingSummary tdps WITH (NOLOCK) ON tdps.TripDetailsId = td.Id
GROUP BY 
    tps.Id,
    t.OperationalPlansId,
    swv.CountActiveTrip,
    swv.ContractServiceId,
    swv.ServiceGroupId,
    swv.ContractId,
	swv.TripId,
	swv.OperationalPlanOldAverage;


	-- =============================================================

-- =============================================================
-- Step: Update Trip summary processing Completion Percentage
-- =============================================================
BEGIN TRY
    BEGIN TRANSACTION;
    -- Update CompletionPercentage with weighted average
    
            ;WITH FirstTripMovement AS
            (
                SELECT
                    ctx.TripProcessingSummaryId,
                    MIN(dm.MovementTime) AS FirstMovementTime
                FROM #TripWithCompletion ctx
                INNER JOIN #TripDetailsProcessingSummarySession dm
                    ON dm.TripId = ctx.TripId
                GROUP BY ctx.TripProcessingSummaryId
            )
    UPDATE tps
    SET CompletionPercentage = twc.TripWeightedCompletionPercentage,
    tps.ActualStartTrip = 
    
        case 
             when tps.ActualStartTrip is null and ftm.FirstMovementTime is not null 
             then ftm.FirstMovementTime
             else tps.ActualStartTrip
             End,
    tps.ActualCovarge=tps.ActualCovarge+twc.TotalValidDistance,
	tps.ModifiedDate =GETDATE(),
	tps.ModifiedBy='SP_DynamicServiceStored_street'
    FROM dbo.TripProcessingSummary tps WITH (NOLOCK)
	INNER JOIN #TripWithCompletion  twc
		ON twc.TripProcessingSummaryId = tps.Id 
    LEFT JOIN FirstTripMovement ftm on ftm.TripProcessingSummaryId=twc.TripProcessingSummaryId;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

	-- =============================================================
	-- =============================================================


-- =============================================================
-- Step : Preapare operational plans to update for Sweeping service 
-- =============================================================

INSERT INTO #NewCombinedAverageForOperationalPlan (OperationalPlansId, CombinedAverage)
SELECT 
    twc.OperationalPlansId,
    (
        (twc.OperationalPlanOldAverage * twc.CountActiveTrip) 
        + (AVG(twc.TripWeightedCompletionPercentage) * COUNT(twc.TripId))
    ) / NULLIF((twc.CountActiveTrip + COUNT(twc.TripId)), 0) AS CombinedAverage
FROM #TripWithCompletion twc
GROUP BY twc.OperationalPlansId, twc.CountActiveTrip, twc.OperationalPlanOldAverage
ORDER BY twc.OperationalPlansId;


-- =============================================================
-- ================Operational Plan Completion % combined average  LIFTING &&Sweeping =================================
-- =============================================================
-- =============================================================
-- Step 6.0: Preapare operational plans to update for lifting service 
-- =============================================================
INSERT INTO #OperationalPlanCompletionSummary (OperationalPlansId,
OperationalPlanCompletionPercentage,ContractServiceId,ContractId,
ServiceGroupId)
SELECT
cte.OperationalPlansId,
cte.CombinedAverage AS OperationalPlanCompletionPercentage,  --new way
ctx.ContractServiceId,
ctx.ContractId,
ctx.ServiceGroupId
FROM #TripProcessingContext ctx
INNER JOIN #NewCombinedAverageForOperationalPlan cte 
ON cte.OperationalPlansId = ctx.OperationalPlansId WHERE NOT EXISTS (
    SELECT 1
    FROM #OperationalPlanCompletionSummary ops
    WHERE ops.OperationalPlansId = cte.OperationalPlansId
);   



-- =============================================================
-- =============================================================SWEEping operational plans
--=============================================================

INSERT INTO #OperationalPlanCompletionSummary (OperationalPlansId,
OperationalPlanCompletionPercentage,ContractServiceId,ContractId,
ServiceGroupId)
SELECT 
        ctx.OperationalPlansId,
        ctx.CombinedAverage AS OperationalPlanCompletionPercentage,
        xx.ContractServiceId,
        xx.ContractId,
        xx.ServiceGroupId
  FROM #NewCombinedAverageForOperationalPlan ctx
    INNER JOIN #TripWithCompletion xx 
        ON ctx.OperationalPlansId = xx.OperationalPlansId 
		WHERE NOT EXISTS (
    SELECT 1
    FROM #OperationalPlanCompletionSummary ops
    WHERE ops.OperationalPlansId = ctx.OperationalPlansId
);   
-- =============================================================
-- =============================================================
-- =============================================================
-- =============================================================
-- Step 0.0: Update Completion % at OperationalPlans level (COMMON BOTH OPERATIONAL PLANS (LIFTING & SWEEPING)
-- =============================================================
BEGIN TRY
BEGIN TRANSACTION;
--I don't need to log opertional plan Id because 

UPDATE op
SET op.TotalTripsCompletionPercentaion = tmp.OperationalPlanCompletionPercentage,
op.ModifiedDate=@Today,
op.ModifiedBy='SP_DynamicServiceStored'
FROM dbo.OperationalPlans op
INNER JOIN #OperationalPlanCompletionSummary tmp ON op.Id = tmp.OperationalPlansId;

---------------------LOG_-----------------------------------------------------------

	UPDATE tlog
    SET tlog.OperationalPlanCompletionPercentage =  ISNULL(tmp.OperationalPlanCompletionPercentage, 0),
        tlog.ModifiedDate = GETDATE(),
        tlog.ModifiedBy   = 'SP_DynamicServiceStored'
    FROM dbo.DynamicServiceProcessLog tlog
    INNER JOIN #OperationalPlanCompletionSummary tmp 
        ON tmp.OperationalPlansId = tlog.OperationalPlanId
WHERE tlog.CreatedDate =@Today;	

COMMIT TRANSACTION;
END TRY
BEGIN CATCH
IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
THROW;
END CATCH;

-- ==========================================================
-- Step 0.0: Update contract service completion % (COMMON)
-- ======================================================

-- INSERT RESULT INTO TEMP TABLE TO AVOID RE-CALCULATE THEM AGAIN 

CREATE TABLE #TempContractServiceCompletionPercentage 
(
    ContractServiceId UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    CompletionPercentage FLOAT
);

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO #TempContractServiceCompletionPercentage (ContractServiceId, CompletionPercentage)
    SELECT 
        temp.ContractServiceId,
        AVG(op.TotalTripsCompletionPercentaion)   AS CompletionPercentage
    FROM #OperationalPlanCompletionSummary temp
    INNER JOIN dbo.ContractServices cs ON cs.Id = temp.ContractServiceId
	INNER JOIN dbo.OperationalPlans op ON op.ContractServiceId=cs.Id
    GROUP BY temp.ContractServiceId;

	-- this is current average you need to multiply with already exists average !!! 
    -- Update the ContractServices table
 
    UPDATE cs
    SET cs.CompletionPercentage = temp.CompletionPercentage,
	cs.ModifiedDate=@Today,
	cs.ModifiedBy='SP_DynamicServiceStored'
    FROM dbo.ContractServices cs
    INNER JOIN #TempContractServiceCompletionPercentage temp ON temp.ContractServiceId = cs.Id;


-- ==================================================
-- ======================log============================
-- ==================================================
-- ==================================================

	UPDATE tlog
    SET tlog.ServiceCompletionPercentage =  ISNULL(tmp.CompletionPercentage, 0),
        tlog.ModifiedDate = GETDATE(),
        tlog.ModifiedBy   = 'SP_DynamicServiceStored'
    FROM dbo.DynamicServiceProcessLog tlog
    INNER JOIN #TempContractServiceCompletionPercentage tmp 
        ON tmp.ContractServiceId = tlog.ContractServiceId
WHERE tlog.CreatedDate =@Today;




DROP TABLE IF EXISTS #TempContractServiceCompletionPercentage; 


    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
-- =========================
-- Step 0.0: Update contract group perecentage  completion % (COMMON)
-- =========================

-- =========================
-- Calculate Contract Group Completion % into temp table
-- =========================
CREATE TABLE #TempContractGroupCompletionPercentage 
(
    ContractId UNIQUEIDENTIFIER NOT NULL,
    ServiceGroupId UNIQUEIDENTIFIER NOT NULL,
    CompletionPercentage FLOAT,
    CONSTRAINT PK_TempContractGroup_v21 PRIMARY KEY (ContractId, ServiceGroupId)
);

BEGIN TRY
    BEGIN TRANSACTION;

    -- Insert calculated weighted completion Into temp table
  INSERT INTO #TempContractGroupCompletionPercentage 
(
    ContractId, 
    ServiceGroupId, 
    CompletionPercentage
)
SELECT
    cg.ContractId,
    cg.ServiceGroupId,
    SUM(cs.CompletionPercentage * cs.ServiceWeightInGroup) / NULLIF(SUM(cs.ServiceWeightInGroup),0)
FROM dbo.ContractGroup cg 
INNER JOIN dbo.ContractServices cs 
    ON cg.ContractId = cs.ContractId 
    AND cg.ServiceGroupId = cs.ServiceGroupId
GROUP BY 
    cg.ContractId, 
    cg.ServiceGroupId;

    -- Update the ContractGroup table
    UPDATE cg
    SET cg.GroupCompletionPercentage =ISNULL(temp.CompletionPercentage, 0)
    FROM dbo.ContractGroup cg
    INNER JOIN #TempContractGroupCompletionPercentage temp
        ON cg.ContractId = temp.ContractId
        AND cg.ServiceGroupId = temp.ServiceGroupId;


    -- ==================================================
    -- Log update for ContractGroup
    -- ==================================================



		-------------------log---------------------------
	UPDATE tlog
    SET tlog.ServiceGroupCompletionPercentage =  ISNULL(tmp.CompletionPercentage, 0),
        tlog.ModifiedDate = GETDATE(),
        tlog.ModifiedBy   = 'SP_DynamicServiceStored'
    FROM dbo.DynamicServiceProcessLog tlog
    INNER JOIN #TempContractGroupCompletionPercentage tmp 
        ON tmp.ContractId = tlog.ContractId
		AND tlog.ServiceGroupId = tmp.ServiceGroupId
    WHERE tlog.CreatedDate =@Today;





    -- Drop temp table
    DROP TABLE IF EXISTS #TempContractGroupCompletionPercentage;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;


-- =========================
-- Step 0.0: Update Contract completion % (COMMON)
-- =========================

-- Create temp table to store calculated completion %
CREATE TABLE #TempContractCompletionPercentage
(
    ContractId UNIQUEIDENTIFIER NOT NULL PRIMARY KEY,
    CompletionPercentage FLOAT
);

BEGIN TRY
    BEGIN TRANSACTION;
	
	
	


	  INSERT INTO #TempContractCompletionPercentage (ContractId, CompletionPercentage)
    SELECT 
        b.ContractId,
        SUM((b.GroupCompletionPercentage / 100.0) * b.GroupWeightInContract)/ NULLIF(SUM(b.GroupWeightInContract),0) * 100
		AS CompletionPercentage
    FROM dbo.ContractGroup b
    GROUP BY b.ContractId;


  
 -- Update Contracts table
    UPDATE c
    SET c.CompletionPercentage = ISNULL(temp.CompletionPercentage, 0)
    FROM dbo.Contracts c
    INNER JOIN #TempContractCompletionPercentage temp
        ON c.Id = temp.ContractId;


    -- Update log table with Contract completion %
	UPDATE tlog
    SET tlog.ContractCompletionPercentage =  ISNULL(tmp.CompletionPercentage, 0),
        tlog.ModifiedDate = GETDATE(),
        tlog.ModifiedBy   = 'SP_DynamicServiceStored'
    FROM dbo.DynamicServiceProcessLog tlog
    INNER JOIN #TempContractCompletionPercentage tmp 
        ON tmp.ContractId = tlog.ContractId
    WHERE tlog.CreatedDate =@Today;


    -- Drop temp table
    DROP TABLE IF EXISTS #TempContractCompletionPercentage;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

-- ============================================
-- Step 14: Delete processed AVL Patch records
-- ============================================
BEGIN TRY

BEGIN
    BEGIN TRANSACTION;

               TRUNCATE TABLE dbo.VehicleAvlDataPatch;

    COMMIT TRANSACTION;
	        SET @FinishedFlag = 1;

END;

END TRY
BEGIN CATCH
TRUNCATE TABLE dbo.VehicleAvlDataPatch;
IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
THROW;
END CATCH;
    END TRY
	 BEGIN CATCH
        PRINT 'An error occurred, cleaning up VehicleAvlDataPatch...';
		        SET @FinishedFlag = -1;

        BEGIN TRY
            -- Clean up in case of failure
			DROP TABLE IF EXISTS #TripProcessingContext;--LIFTING
 DROP TABLE IF EXISTS #TempAvlPatchForLifting;--LIFTING
 DROP TABLE IF EXISTS #NewCombinedAverageForOperationalPlan;--LIFTING
 DROP TABLE IF EXISTS #DetailsMatchedValidTag;--LIFTING
 DROP TABLE IF EXISTS #TripWasteWeightCalculated;--LIFTING
 DROP TABLE IF EXISTS #WasteBinCollectionPreCalculation;--LIFTING
 DROP TABLE IF EXISTS #OperationalPlanCompletionSummary; --LIFTING & SWEEPING
 DROP TABLE IF EXISTS #ValidVehicleLocations; --SWEEPING
 DROP TABLE IF EXISTS #TripWithValidity;--SWEEPING
 DROP TABLE IF EXISTS #TempAvlPatchForSweeping;--Sweeping
 DROP TABLE IF EXISTS #TripProcessingSummarySession;--SWEEPING
 DROP TABLE IF EXISTS #StreetProcessingValues; --SWEEPING
 DROP TABLE IF EXISTS #StreetWithValidity;--SWEEPING
 DROP TABLE IF EXISTS #TripDetailsProcessingSummarySession;--SWEEPING
 DROP TABLE IF EXISTS #TripWithCompletion ;  
 DROP TABLE IF EXISTS #TempAvlPatchToProcess;
 DROP TABLE IF EXISTS #DetailsMatchedValidTagCaseTwo;
 DROP TABLE IF EXISTS #DetailsMatchedValidTagOtherThree;
 DROP TABLE IF EXISTS #DetailsMatchedValidTagOtherFour;
 DROP TABLE IF EXISTS #DetailsMatchedValidTagOtherFive;
 DROP TABLE IF EXISTS #DetailsMatchedValidTagOtherSix;
 DROP TABLE IF EXISTS #DetailsMatchedValidTagOtherCases;
 DROP TABLE IF EXISTS #AllCasesCombined;
 DROP TABLE IF EXISTS #TripDetailsProcessingSummary;
 DROP TABLE IF EXISTS #TripDetails;
            TRUNCATE TABLE dbo.VehicleAvlDataPatch;
        END TRY
        BEGIN CATCH
		        SET @FinishedFlag = -1;

            PRINT 'Cleanup failed too!';
            -- Optionally log this error in an error log table
        END CATCH;

        -- Optionally rethrow the error to mark job as failed
        THROW;
    END CATCH;
-- =========================
-- Step 15: Cleanup tables
-- =========================
DROP TABLE IF EXISTS #TripProcessingContext;--LIFTING
DROP TABLE IF EXISTS #TempAvlPatchForLifting;--LIFTING
DROP TABLE IF EXISTS #NewCombinedAverageForOperationalPlan;--LIFTING
DROP TABLE IF EXISTS #DetailsMatchedValidTag;--LIFTING
 DROP TABLE IF EXISTS #TripWasteWeightCalculated;--LIFTING
 DROP TABLE IF EXISTS #WasteBinCollectionPreCalculation;--LIFTING
DROP TABLE IF EXISTS #OperationalPlanCompletionSummary; --LIFTING & SWEEPING
 DROP TABLE IF EXISTS #ValidVehicleLocations; --SWEEPING
DROP TABLE IF EXISTS #TempAvlPatchForSweeping;--sWEEPING
 DROP TABLE IF EXISTS #TripWithValidity;--SWEEPING
 DROP TABLE IF EXISTS #TripProcessingSummarySession;--SWEEPING
 DROP TABLE IF EXISTS #StreetProcessingValues; --SWEEPING
 DROP TABLE IF EXISTS #StreetWithValidity;--SWEEPING
 DROP TABLE IF EXISTS #TripDetailsProcessingSummarySession;--SWEEPING
 DROP TABLE IF EXISTS #TripWithCompletion ;  


END;
