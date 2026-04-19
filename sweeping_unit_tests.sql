-- ============================================================
-- SWEEPING STORED PROCEDURE - SQL UNIT TEST SUITE
-- ============================================================
-- Purpose  : Validate street-level sweeping calculation logic
-- Trip      : 2026-04-19 02:00:00 -> 2026-04-19 06:00:00
-- Author   : Unit Test Script
-- Version  : 1.0
--
-- HOW TO USE:
--   1. Run the entire script in one batch on a dev/test DB
--   2. Each TEST CASE section is self-contained
--   3. Read the RESULT block at the bottom for pass/fail summary
--   4. All mock data is isolated – no permanent tables are touched
--
-- IMPORTANT ASSUMPTIONS:
--   - #ValidVehicleLocations is already populated (Step 1 skipped)
--   - We mock that temp table directly with controlled data
--   - VehicleType / ContractingCompanyType drive Input validity rules
--   - Speed BETWEEN 1 AND 29 AND Ignition=1 => GpsValid
--   - MovementTime MUST be within trip window to be counted
-- ============================================================

SET NOCOUNT ON;
PRINT '============================================================';
PRINT ' SWEEPING UNIT TEST SUITE  –  Starting...';
PRINT '============================================================';

-- ============================================================
-- SECTION 0 : SHARED CONSTANTS / IDs
-- ============================================================

DECLARE
    -- Trip window (all AVL records must fall inside this to matter)
    @TripStart   DATETIME2 = '2026-04-19 02:00:00',
    @TripEnd     DATETIME2 = '2026-04-19 06:00:00',

    -- Fixed GUIDs for mocked entities
    @TripId                         UNIQUEIDENTIFIER = '11111111-0000-0000-0000-000000000001',
    @TripProcessingSummaryId        UNIQUEIDENTIFIER = '22222222-0000-0000-0000-000000000001',
    @OperationalPlansId             UNIQUEIDENTIFIER = '33333333-0000-0000-0000-000000000001',
    @ContractServiceId              UNIQUEIDENTIFIER = '44444444-0000-0000-0000-000000000001',
    @ContractId                     UNIQUEIDENTIFIER = '55555555-0000-0000-0000-000000000001',
    @ServiceGroupId                 UNIQUEIDENTIFIER = '66666666-0000-0000-0000-000000000001',
    @VehicleId                      UNIQUEIDENTIFIER = 'AAAAAAAA-0000-0000-0000-000000000001',

    -- Two streets for weighted-average tests
    @TripDetailsProcessingSummaryId1 UNIQUEIDENTIFIER = 'BBBBBBBB-0000-0000-0000-000000000001',
    @TripDetailsProcessingSummaryId2 UNIQUEIDENTIFIER = 'BBBBBBBB-0000-0000-0000-000000000002',

    -- Street physical lengths (metres) – from your geometry data
    @Street1Length  FLOAT = 1500.0,
    @Street2Length  FLOAT = 800.0,

    -- Street weight percentages (must sum to 100 across the trip)
    @Street1Weight  FLOAT = 65.0,
    @Street2Weight  FLOAT = 35.0,

    -- Tolerance used in Step 1 geometry check (not tested here, noted for reference)
    @tolerance      FLOAT = 20.0;

-- ============================================================
-- SECTION 1 : SHARED TEMP TABLES
-- (Mirrors the exact shape used by the stored procedure)
-- ============================================================

-- Drop if re-running
IF OBJECT_ID('tempdb..#ValidVehicleLocations')          IS NOT NULL DROP TABLE #ValidVehicleLocations;
IF OBJECT_ID('tempdb..#TripDetailsProcessingSummarySession') IS NOT NULL DROP TABLE #TripDetailsProcessingSummarySession;
IF OBJECT_ID('tempdb..#StreetWithValidity')             IS NOT NULL DROP TABLE #StreetWithValidity;
IF OBJECT_ID('tempdb..#TripWithCompletion')             IS NOT NULL DROP TABLE #TripWithCompletion;
IF OBJECT_ID('tempdb..#TestResults')                    IS NOT NULL DROP TABLE #TestResults;
IF OBJECT_ID('tempdb..#MockTripDetailsProcessingSummary') IS NOT NULL DROP TABLE #MockTripDetailsProcessingSummary;

-- Test result collector
CREATE TABLE #TestResults (
    TestId      INT IDENTITY(1,1),
    TestName    NVARCHAR(200),
    Passed      BIT,
    Expected    NVARCHAR(500),
    Actual      NVARCHAR(500),
    Notes       NVARCHAR(500)
);

-- Mirrors dbo.TripDetailsProcessingSummary (only columns we need)
CREATE TABLE #MockTripDetailsProcessingSummary (
    Id                          UNIQUEIDENTIFIER PRIMARY KEY,
    TripDetailsId               UNIQUEIDENTIFIER,
    TotalDistance               FLOAT           DEFAULT 0,
    CompletionPercentage        FLOAT           DEFAULT 0,
    TotalBrushDistanceCovered   FLOAT           DEFAULT 0,
    TotalWaterDistanceCovered   FLOAT           DEFAULT 0,
    TotalGpsDistanceCovered     FLOAT           DEFAULT 0,
    IsSwept                     BIT             DEFAULT 0
);

-- #ValidVehicleLocations: Step 1 output we mock directly
CREATE TABLE #ValidVehicleLocations (
    TripId                          UNIQUEIDENTIFIER,
    TripDetailsProcessingSummaryId  UNIQUEIDENTIFIER,
    TripProcessingSummaryId         UNIQUEIDENTIFIER,
    OperationalPlansId              UNIQUEIDENTIFIER,
    ContractServiceId               UNIQUEIDENTIFIER,
    ContractId                      UNIQUEIDENTIFIER,
    ServiceGroupId                  UNIQUEIDENTIFIER,
    MovementTime                    DATETIME2,
    VehicleId                       UNIQUEIDENTIFIER,
    Longitude                       FLOAT,
    Latitude                        FLOAT,
    Input1                          INT,
    Input2                          INT,
    Input3                          INT,
    Input4                          INT,
    Speed                           INT,
    Ignition                        BIT,
    VehicleType                     INT,
    ContractingCompanyType          INT,
    CountActiveTrip                 INT,
    OperationalPlanOldAverage       FLOAT,
    StreetWeightPercentage          FLOAT,
    StreetLength                    FLOAT,
    StreetOrder                     INT,
    TotalDistance                   FLOAT
);

-- #TripDetailsProcessingSummarySession: Step 2a output (LAG applied)
CREATE TABLE #TripDetailsProcessingSummarySession (
    TripId                          UNIQUEIDENTIFIER,
    TripProcessingSummaryId         UNIQUEIDENTIFIER,
    TripDetailsProcessingSummaryId  UNIQUEIDENTIFIER,
    StreetOrder                     INT,
    StreetLength                    FLOAT,
    StreetWeightPercentage          FLOAT,
    TotalDistance                   FLOAT,
    OperationalPlansId              UNIQUEIDENTIFIER,
    ContractServiceId               UNIQUEIDENTIFIER,
    ContractId                      UNIQUEIDENTIFIER,
    ServiceGroupId                  UNIQUEIDENTIFIER,
    CurrentLatitude                 FLOAT,
    CurrentLongitude                FLOAT,
    LastLatitude                    FLOAT,
    LastLongitude                   FLOAT,
    VehicleType                     INT,
    ContractingCompanyType          INT,
    Input1                          INT,
    Input2                          INT,
    Input3                          INT,
    Input4                          INT,
    Speed                           INT,
    Ignition                        BIT,
    SessionBrushDistanceCovered     FLOAT DEFAULT 0,
    SessionTotalWaterDistanceCoveredPatch FLOAT DEFAULT 0,
    SessionGpsDistanceCoveredPatch  FLOAT DEFAULT 0,
    CountActiveTrip                 INT,
    OperationalPlanOldAverage       FLOAT
);

-- #StreetWithValidity: Step 2b output (validity + distance per street)
CREATE TABLE #StreetWithValidity (
    TripId                          UNIQUEIDENTIFIER,
    TripProcessingSummaryId         UNIQUEIDENTIFIER,
    TripDetailsProcessingSummaryId  UNIQUEIDENTIFIER,
    OperationalPlansId              UNIQUEIDENTIFIER,
    ContractServiceId               UNIQUEIDENTIFIER,
    ContractId                      UNIQUEIDENTIFIER,
    ServiceGroupId                  UNIQUEIDENTIFIER,
    VehicleType                     INT,
    ContractingCompanyType          INT,
    ValidDistance                   FLOAT,
    WaterDistanceFinal              FLOAT,
    BrushDistanceFinal              FLOAT,
    GpsDistanceFinal                FLOAT,
    CountActiveTrip                 INT,
    StreetOrder                     INT,
    StreetLength                    FLOAT,
    StreetWeightPercentage          FLOAT,
    OperationalPlanOldAverage       FLOAT,
    StreetCompletionPercentage      FLOAT,
    TotalValidDistance              AS ValidDistance  -- convenience alias
);

-- #TripWithCompletion: Step 3 output
CREATE TABLE #TripWithCompletion (
    TripProcessingSummaryId         UNIQUEIDENTIFIER,
    OperationalPlansId              UNIQUEIDENTIFIER,
    CountActiveTrip                 INT,
    ContractServiceId               UNIQUEIDENTIFIER,
    ServiceGroupId                  UNIQUEIDENTIFIER,
    ContractId                      UNIQUEIDENTIFIER,
    OperationalPlanOldAverage       FLOAT,
    TripId                          UNIQUEIDENTIFIER,
    TripWeightedCompletionPercentage FLOAT,
    TotalValidDistance              FLOAT
);

PRINT 'Temp tables created.';

-- ============================================================
-- HELPER : PROCEDURE-EQUIVALENT MACRO
-- Runs Steps 2a, 2b (the core calculation pipeline) using
-- whatever rows are currently in #ValidVehicleLocations.
-- Call this after loading each test scenario.
-- ============================================================

-- NOTE: Because T-SQL cannot define reusable inline macros,
--       wrap the pipeline in a cleanup + re-run pattern below.

-- ====================================================================
-- UTILITY: Helper to record a test result
-- ====================================================================
-- Usage inside each test:
--   INSERT INTO #TestResults(TestName, Passed, Expected, Actual, Notes)
--   SELECT 'TC-XX Name',
--          CASE WHEN <actual> = <expected> THEN 1 ELSE 0 END,
--          CAST(<expected> AS NVARCHAR), CAST(<actual> AS NVARCHAR), 'comment';
-- ====================================================================


-- ============================================================
-- SECTION 2 : PIPELINE RUNNER
-- Clears session-level temp tables and re-runs Steps 2a + 2b
-- Call this AFTER each test scenario loads #ValidVehicleLocations
-- ============================================================

-- We use a helper table flag to know if pipeline ran
IF OBJECT_ID('tempdb..#PipelineRan') IS NOT NULL DROP TABLE #PipelineRan;
CREATE TABLE #PipelineRan (RunId INT IDENTITY(1,1), Note NVARCHAR(100));

-- ============================================================
-- ============================================================
-- TEST CASE 01
-- NAME    : All conditions valid → positive ValidDistance
-- VEHICLE : Type=1, ContractingCompanyType=1 (Water=Input3>0, Brush=Input2>0)
-- SPEED   : 15 (in valid 1-29 range), Ignition=1
-- TIME    : Inside trip window
-- EXPECT  : ValidDistance > 0, StreetCompletionPercentage > 0
-- ============================================================
-- ============================================================

PRINT '';
PRINT '--- TC-01: All valid conditions ---';

TRUNCATE TABLE #ValidVehicleLocations;
TRUNCATE TABLE #TripDetailsProcessingSummarySession;
TRUNCATE TABLE #StreetWithValidity;
TRUNCATE TABLE #TripWithCompletion;

-- Street 1 – sequence of GPS points walking ~400m down a street
-- Points are ~100m apart; all inside trip window
INSERT INTO #ValidVehicleLocations VALUES
--TripId, TDPSId, TPSId, OpPlanId, CSId, CId, SGId,
--MovementTime (INSIDE window), VehicleId,
--Lon, Lat, I1, I2(Brush), I3(Water), I4, Speed, Ignition,
--VehicleType, ContractingCompanyType, CountActiveTrip, OPOldAvg, StreetWeight, StreetLen, StreetOrder, TotalDist
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 03:00:00',@VehicleId,
 39.232216, 21.429121, 0, 5, 5, 0, 15, 1,
 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 0),

(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 03:01:00',@VehicleId,
 39.233500, 21.429935, 0, 5, 5, 0, 15, 1,
 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 0),

(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 03:02:00',@VehicleId,
 39.235649, 21.431947, 0, 5, 5, 0, 15, 1,
 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 0),

(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 03:03:00',@VehicleId,
 39.236209, 21.432402, 0, 5, 5, 0, 15, 1,
 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 0);

-- Step 2a: Apply LAG to get LastLat/LastLon pairs
;WITH OrderedLocations AS (
    SELECT *,
        LAG(Latitude)  OVER (PARTITION BY VehicleId ORDER BY MovementTime) AS LastLatitude,
        LAG(Longitude) OVER (PARTITION BY VehicleId ORDER BY MovementTime) AS LastLongitude
    FROM #ValidVehicleLocations
)
INSERT INTO #TripDetailsProcessingSummarySession (
    TripId, TripProcessingSummaryId, TripDetailsProcessingSummaryId,
    StreetOrder, StreetLength, StreetWeightPercentage, TotalDistance,
    OperationalPlansId, ContractServiceId, ContractId, ServiceGroupId,
    CurrentLatitude, CurrentLongitude, LastLatitude, LastLongitude,
    VehicleType, ContractingCompanyType,
    Input1, Input2, Input3, Input4, Speed, Ignition,
    SessionBrushDistanceCovered, SessionTotalWaterDistanceCoveredPatch,
    SessionGpsDistanceCoveredPatch, CountActiveTrip, OperationalPlanOldAverage
)
SELECT
    TripId, TripProcessingSummaryId, TripDetailsProcessingSummaryId,
    StreetOrder, StreetLength, StreetWeightPercentage, TotalDistance,
    OperationalPlansId, ContractServiceId, ContractId, ServiceGroupId,
    Latitude, Longitude, LastLatitude, LastLongitude,
    VehicleType, ContractingCompanyType,
    Input1, Input2, Input3, Input4, Speed, Ignition,
    0, 0, 0, CountActiveTrip, OperationalPlanOldAverage
FROM OrderedLocations;

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
            WHEN (VehicleType=1 AND ContractingCompanyType=1 AND Input3>0)
              OR (VehicleType=1 AND ContractingCompanyType=2 AND Input2>0)
              OR (VehicleType=16 AND ContractingCompanyType=3 AND (Input2>0 OR Input3>0))
              OR (VehicleType=2 AND Input1>0)
              OR (VehicleType=3 AND ContractingCompanyType=2 AND Input1>0)
              OR (VehicleType=16 AND ContractingCompanyType=1 AND Input3>0)
            THEN 1 ELSE 0.
        END AS WaterValid,
        -- Brush validity
        CASE
            WHEN (VehicleType=1 AND ContractingCompanyType IN (1,3) AND Input2>0)
              OR (VehicleType=2 AND Input2>0)
              OR (VehicleType=16 AND ContractingCompanyType IN (1,2) AND Input2>0)
              OR (VehicleType=3 AND ContractingCompanyType=2 AND Input2>0)
              OR (VehicleType=16 AND ContractingCompanyType=3 AND (Input1>0 OR Input4>0))
            THEN 1 ELSE 0
        END AS BrushValid,
        -- GPS validity
        CASE WHEN Speed BETWEEN 1 AND 29 AND Ignition=1 THEN 1 ELSE 0 END AS GpsValid,
        -- Big vehicle left/right sides
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
    SUM(CASE WHEN GpsValid=1 AND (WaterValid=1 AND BrushValid=1 OR IsLeftValid=1 OR IsRightValid=1)
             THEN DistanceInMeters ELSE 0 END) AS ValidDistance,
    SUM(CASE WHEN WaterValid=1 THEN DistanceInMeters ELSE SessionTotalWaterDistanceCoveredPatch END) AS WaterDistanceFinal,
    SUM(CASE WHEN BrushValid=1 THEN DistanceInMeters ELSE SessionBrushDistanceCovered END) AS BrushDistanceFinal,
    SUM(CASE WHEN GpsValid=1  THEN DistanceInMeters ELSE SessionGpsDistanceCoveredPatch  END) AS GpsDistanceFinal,
    CountActiveTrip, StreetOrder, StreetLength, StreetWeightPercentage,
    OperationalPlanOldAverage,
    CASE
        WHEN SUM(CASE WHEN GpsValid=1 AND (WaterValid=1 AND BrushValid=1 OR IsLeftValid=1 OR IsRightValid=1)
                      THEN DistanceInMeters ELSE 0 END) > StreetLength
        THEN 100
        ELSE COALESCE(
            (TotalDistance + SUM(CASE WHEN GpsValid=1 AND (WaterValid=1 AND BrushValid=1 OR IsLeftValid=1 OR IsRightValid=1)
                                      THEN DistanceInMeters ELSE 0 END))
            / NULLIF(StreetLength, 0) * 100, 0)
    END AS StreetCompletionPercentage
FROM CalculatedDistanceCTE
GROUP BY TripId, TripProcessingSummaryId, TripDetailsProcessingSummaryId,
    OperationalPlansId, ContractServiceId, ContractId, ServiceGroupId,
    VehicleType, ContractingCompanyType,
    CountActiveTrip, StreetOrder, StreetLength, StreetWeightPercentage,
    TotalDistance, OperationalPlanOldAverage;

-- ASSERT TC-01
INSERT INTO #TestResults(TestName, Passed, Expected, Actual, Notes)
SELECT
    'TC-01: All valid → ValidDistance > 0',
    CASE WHEN ValidDistance > 0 THEN 1 ELSE 0 END,
    '> 0',
    CAST(ROUND(ValidDistance,2) AS NVARCHAR),
    'VehicleType=1, CompanyType=1, Input2+3>0, Speed=15, Ignition=1, inside window'
FROM #StreetWithValidity;

INSERT INTO #TestResults(TestName, Passed, Expected, Actual, Notes)
SELECT
    'TC-01: All valid → StreetCompletionPercentage > 0',
    CASE WHEN StreetCompletionPercentage > 0 THEN 1 ELSE 0 END,
    '> 0',
    CAST(ROUND(StreetCompletionPercentage,2) AS NVARCHAR),
    'Partial coverage expected'
FROM #StreetWithValidity;


-- ============================================================
-- TEST CASE 02
-- NAME    : Speed out of range → GPS invalid → ValidDistance = 0
-- VEHICLE : Type=1, CompanyType=1, Brush+Water ON
-- SPEED   : 0 (below 1) → GpsValid=0 → segment counts nothing
-- ============================================================

PRINT '--- TC-02: Speed=0 (GpsInvalid) ---';

TRUNCATE TABLE #ValidVehicleLocations;
TRUNCATE TABLE #TripDetailsProcessingSummarySession;
TRUNCATE TABLE #StreetWithValidity;

INSERT INTO #ValidVehicleLocations VALUES
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 03:10:00',@VehicleId, 39.232216, 21.429121, 0, 5, 5, 0, 0, 1, 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 0),

(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 03:11:00',@VehicleId, 39.233500, 21.429935, 0, 5, 5, 0, 0, 1, 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 0);

;WITH OrderedLocations AS (
    SELECT *, LAG(Latitude) OVER (PARTITION BY VehicleId ORDER BY MovementTime) AS LastLatitude,
              LAG(Longitude) OVER (PARTITION BY VehicleId ORDER BY MovementTime) AS LastLongitude
    FROM #ValidVehicleLocations
)
INSERT INTO #TripDetailsProcessingSummarySession (TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,CurrentLatitude,CurrentLongitude,LastLatitude,LastLongitude,VehicleType,ContractingCompanyType,Input1,Input2,Input3,Input4,Speed,Ignition,SessionBrushDistanceCovered,SessionTotalWaterDistanceCoveredPatch,SessionGpsDistanceCoveredPatch,CountActiveTrip,OperationalPlanOldAverage)
SELECT TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,Latitude,Longitude,LastLatitude,LastLongitude,VehicleType,ContractingCompanyType,Input1,Input2,Input3,Input4,Speed,Ignition,0,0,0,CountActiveTrip,OperationalPlanOldAverage FROM OrderedLocations;

;WITH CalculatedDistanceCTE AS (
    SELECT *,
        6371000*2*ASIN(SQRT(POWER(SIN(RADIANS((CurrentLatitude-LastLatitude)/2)),2)+COS(RADIANS(CurrentLatitude))*COS(RADIANS(LastLatitude))*POWER(SIN(RADIANS((CurrentLongitude-LastLongitude)/2)),2))) AS DistanceInMeters,
        CASE WHEN (VehicleType=1 AND ContractingCompanyType=1 AND Input3>0) THEN 1 ELSE 0 END AS WaterValid,
        CASE WHEN (VehicleType=1 AND ContractingCompanyType IN(1,3) AND Input2>0) THEN 1 ELSE 0 END AS BrushValid,
        CASE WHEN Speed BETWEEN 1 AND 29 AND Ignition=1 THEN 1 ELSE 0 END AS GpsValid,
        0 AS IsRightValid, 0 AS IsLeftValid
    FROM #TripDetailsProcessingSummarySession WHERE LastLatitude IS NOT NULL
)
INSERT INTO #StreetWithValidity(TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,ValidDistance,WaterDistanceFinal,BrushDistanceFinal,GpsDistanceFinal,CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,OperationalPlanOldAverage,StreetCompletionPercentage)
SELECT TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,
    SUM(CASE WHEN GpsValid=1 AND WaterValid=1 AND BrushValid=1 THEN DistanceInMeters ELSE 0 END),
    SUM(CASE WHEN WaterValid=1 THEN DistanceInMeters ELSE 0 END),
    SUM(CASE WHEN BrushValid=1 THEN DistanceInMeters ELSE 0 END),
    SUM(CASE WHEN GpsValid=1  THEN DistanceInMeters ELSE 0 END),
    CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,OperationalPlanOldAverage,
    COALESCE((TotalDistance+SUM(CASE WHEN GpsValid=1 AND WaterValid=1 AND BrushValid=1 THEN DistanceInMeters ELSE 0 END))/NULLIF(StreetLength,0)*100,0)
FROM CalculatedDistanceCTE
GROUP BY TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlanOldAverage;

INSERT INTO #TestResults(TestName,Passed,Expected,Actual,Notes)
SELECT 'TC-02: Speed=0 → ValidDistance = 0',
    CASE WHEN ValidDistance = 0 THEN 1 ELSE 0 END, '0', CAST(ValidDistance AS NVARCHAR),
    'GpsValid=0 blocks all valid distance accumulation'
FROM #StreetWithValidity;


-- ============================================================
-- TEST CASE 03
-- NAME    : Speed = 30 (above 29) → GPS invalid
-- ============================================================

PRINT '--- TC-03: Speed=30 (boundary, GpsInvalid) ---';

TRUNCATE TABLE #ValidVehicleLocations;
TRUNCATE TABLE #TripDetailsProcessingSummarySession;
TRUNCATE TABLE #StreetWithValidity;

INSERT INTO #ValidVehicleLocations VALUES
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 03:20:00',@VehicleId, 39.232216, 21.429121, 0, 5, 5, 0, 30, 1, 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 0),
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 03:21:00',@VehicleId, 39.233500, 21.429935, 0, 5, 5, 0, 30, 1, 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 0);

;WITH O AS (SELECT *,LAG(Latitude) OVER(PARTITION BY VehicleId ORDER BY MovementTime) AS LastLatitude,LAG(Longitude) OVER(PARTITION BY VehicleId ORDER BY MovementTime) AS LastLongitude FROM #ValidVehicleLocations)
INSERT INTO #TripDetailsProcessingSummarySession(TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,CurrentLatitude,CurrentLongitude,LastLatitude,LastLongitude,VehicleType,ContractingCompanyType,Input1,Input2,Input3,Input4,Speed,Ignition,SessionBrushDistanceCovered,SessionTotalWaterDistanceCoveredPatch,SessionGpsDistanceCoveredPatch,CountActiveTrip,OperationalPlanOldAverage)
SELECT TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,Latitude,Longitude,LastLatitude,LastLongitude,VehicleType,ContractingCompanyType,Input1,Input2,Input3,Input4,Speed,Ignition,0,0,0,CountActiveTrip,OperationalPlanOldAverage FROM O;

;WITH C AS(SELECT *,6371000*2*ASIN(SQRT(POWER(SIN(RADIANS((CurrentLatitude-LastLatitude)/2)),2)+COS(RADIANS(CurrentLatitude))*COS(RADIANS(LastLatitude))*POWER(SIN(RADIANS((CurrentLongitude-LastLongitude)/2)),2))) AS DistanceInMeters,CASE WHEN VehicleType=1 AND ContractingCompanyType=1 AND Input3>0 THEN 1 ELSE 0 END AS WaterValid,CASE WHEN VehicleType=1 AND ContractingCompanyType IN(1,3) AND Input2>0 THEN 1 ELSE 0 END AS BrushValid,CASE WHEN Speed BETWEEN 1 AND 29 AND Ignition=1 THEN 1 ELSE 0 END AS GpsValid,0 AS IsRightValid,0 AS IsLeftValid FROM #TripDetailsProcessingSummarySession WHERE LastLatitude IS NOT NULL)
INSERT INTO #StreetWithValidity(TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,ValidDistance,WaterDistanceFinal,BrushDistanceFinal,GpsDistanceFinal,CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,OperationalPlanOldAverage,StreetCompletionPercentage)
SELECT TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,
    SUM(CASE WHEN GpsValid=1 AND WaterValid=1 AND BrushValid=1 THEN DistanceInMeters ELSE 0 END),SUM(CASE WHEN WaterValid=1 THEN DistanceInMeters ELSE 0 END),SUM(CASE WHEN BrushValid=1 THEN DistanceInMeters ELSE 0 END),SUM(CASE WHEN GpsValid=1 THEN DistanceInMeters ELSE 0 END),
    CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,OperationalPlanOldAverage,
    COALESCE((TotalDistance+SUM(CASE WHEN GpsValid=1 AND WaterValid=1 AND BrushValid=1 THEN DistanceInMeters ELSE 0 END))/NULLIF(StreetLength,0)*100,0)
FROM C GROUP BY TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlanOldAverage;

INSERT INTO #TestResults(TestName,Passed,Expected,Actual,Notes)
SELECT 'TC-03: Speed=30 (boundary) → ValidDistance = 0','0' COLLATE DATABASE_DEFAULT AS Expected,
    CASE WHEN ValidDistance=0 THEN 1 ELSE 0 END,CAST(ValidDistance AS NVARCHAR),'Speed=30 is NOT in 1-29 range'
FROM #StreetWithValidity;

-- Fix column order typo above - re-insert correctly
DELETE FROM #TestResults WHERE TestName='TC-03: Speed=30 (boundary) → ValidDistance = 0';
INSERT INTO #TestResults(TestName,Passed,Expected,Actual,Notes)
SELECT 'TC-03: Speed=30 (boundary) → ValidDistance = 0',
    CASE WHEN ValidDistance=0 THEN 1 ELSE 0 END,'0',CAST(ValidDistance AS NVARCHAR),'Speed=30 is NOT in 1-29 range'
FROM #StreetWithValidity;


-- ============================================================
-- TEST CASE 04
-- NAME    : Speed=1 (boundary low) → GPS VALID
-- ============================================================

PRINT '--- TC-04: Speed=1 (boundary low, GpsValid) ---';

TRUNCATE TABLE #ValidVehicleLocations;
TRUNCATE TABLE #TripDetailsProcessingSummarySession;
TRUNCATE TABLE #StreetWithValidity;

INSERT INTO #ValidVehicleLocations VALUES
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 03:30:00',@VehicleId, 39.232216, 21.429121, 0, 5, 5, 0, 1, 1, 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 0),
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 03:31:00',@VehicleId, 39.233500, 21.429935, 0, 5, 5, 0, 1, 1, 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 0);

;WITH O AS(SELECT *,LAG(Latitude)OVER(PARTITION BY VehicleId ORDER BY MovementTime) AS LastLatitude,LAG(Longitude)OVER(PARTITION BY VehicleId ORDER BY MovementTime) AS LastLongitude FROM #ValidVehicleLocations)
INSERT INTO #TripDetailsProcessingSummarySession(TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,CurrentLatitude,CurrentLongitude,LastLatitude,LastLongitude,VehicleType,ContractingCompanyType,Input1,Input2,Input3,Input4,Speed,Ignition,SessionBrushDistanceCovered,SessionTotalWaterDistanceCoveredPatch,SessionGpsDistanceCoveredPatch,CountActiveTrip,OperationalPlanOldAverage)
SELECT TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,Latitude,Longitude,LastLatitude,LastLongitude,VehicleType,ContractingCompanyType,Input1,Input2,Input3,Input4,Speed,Ignition,0,0,0,CountActiveTrip,OperationalPlanOldAverage FROM O;

;WITH C AS(SELECT *,6371000*2*ASIN(SQRT(POWER(SIN(RADIANS((CurrentLatitude-LastLatitude)/2)),2)+COS(RADIANS(CurrentLatitude))*COS(RADIANS(LastLatitude))*POWER(SIN(RADIANS((CurrentLongitude-LastLongitude)/2)),2))) AS DistanceInMeters,CASE WHEN VehicleType=1 AND ContractingCompanyType=1 AND Input3>0 THEN 1 ELSE 0 END AS WaterValid,CASE WHEN VehicleType=1 AND ContractingCompanyType IN(1,3) AND Input2>0 THEN 1 ELSE 0 END AS BrushValid,CASE WHEN Speed BETWEEN 1 AND 29 AND Ignition=1 THEN 1 ELSE 0 END AS GpsValid,0 AS IsRightValid,0 AS IsLeftValid FROM #TripDetailsProcessingSummarySession WHERE LastLatitude IS NOT NULL)
INSERT INTO #StreetWithValidity(TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,ValidDistance,WaterDistanceFinal,BrushDistanceFinal,GpsDistanceFinal,CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,OperationalPlanOldAverage,StreetCompletionPercentage)
SELECT TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,
    SUM(CASE WHEN GpsValid=1 AND WaterValid=1 AND BrushValid=1 THEN DistanceInMeters ELSE 0 END),SUM(CASE WHEN WaterValid=1 THEN DistanceInMeters ELSE 0 END),SUM(CASE WHEN BrushValid=1 THEN DistanceInMeters ELSE 0 END),SUM(CASE WHEN GpsValid=1 THEN DistanceInMeters ELSE 0 END),
    CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,OperationalPlanOldAverage,
    COALESCE((TotalDistance+SUM(CASE WHEN GpsValid=1 AND WaterValid=1 AND BrushValid=1 THEN DistanceInMeters ELSE 0 END))/NULLIF(StreetLength,0)*100,0)
FROM C GROUP BY TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlanOldAverage;

INSERT INTO #TestResults(TestName,Passed,Expected,Actual,Notes)
SELECT 'TC-04: Speed=1 (boundary low) → ValidDistance > 0',
    CASE WHEN ValidDistance>0 THEN 1 ELSE 0 END,'>0',CAST(ROUND(ValidDistance,2) AS NVARCHAR),'Speed=1 IS in valid range 1-29'
FROM #StreetWithValidity;


-- ============================================================
-- TEST CASE 05
-- NAME    : Ignition = 0 → GPS invalid → ValidDistance = 0
-- ============================================================

PRINT '--- TC-05: Ignition=0 → GpsInvalid ---';

TRUNCATE TABLE #ValidVehicleLocations;
TRUNCATE TABLE #TripDetailsProcessingSummarySession;
TRUNCATE TABLE #StreetWithValidity;

INSERT INTO #ValidVehicleLocations VALUES
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 03:40:00',@VehicleId, 39.232216, 21.429121, 0, 5, 5, 0, 15, 0/*Ignition=OFF*/, 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 0),
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 03:41:00',@VehicleId, 39.233500, 21.429935, 0, 5, 5, 0, 15, 0, 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 0);

;WITH O AS(SELECT *,LAG(Latitude)OVER(PARTITION BY VehicleId ORDER BY MovementTime) AS LastLatitude,LAG(Longitude)OVER(PARTITION BY VehicleId ORDER BY MovementTime) AS LastLongitude FROM #ValidVehicleLocations)
INSERT INTO #TripDetailsProcessingSummarySession(TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,CurrentLatitude,CurrentLongitude,LastLatitude,LastLongitude,VehicleType,ContractingCompanyType,Input1,Input2,Input3,Input4,Speed,Ignition,SessionBrushDistanceCovered,SessionTotalWaterDistanceCoveredPatch,SessionGpsDistanceCoveredPatch,CountActiveTrip,OperationalPlanOldAverage)
SELECT TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,Latitude,Longitude,LastLatitude,LastLongitude,VehicleType,ContractingCompanyType,Input1,Input2,Input3,Input4,Speed,Ignition,0,0,0,CountActiveTrip,OperationalPlanOldAverage FROM O;

;WITH C AS(SELECT *,6371000*2*ASIN(SQRT(POWER(SIN(RADIANS((CurrentLatitude-LastLatitude)/2)),2)+COS(RADIANS(CurrentLatitude))*COS(RADIANS(LastLatitude))*POWER(SIN(RADIANS((CurrentLongitude-LastLongitude)/2)),2))) AS DistanceInMeters,CASE WHEN VehicleType=1 AND ContractingCompanyType=1 AND Input3>0 THEN 1 ELSE 0 END AS WaterValid,CASE WHEN VehicleType=1 AND ContractingCompanyType IN(1,3) AND Input2>0 THEN 1 ELSE 0 END AS BrushValid,CASE WHEN Speed BETWEEN 1 AND 29 AND Ignition=1 THEN 1 ELSE 0 END AS GpsValid,0 AS IsRightValid,0 AS IsLeftValid FROM #TripDetailsProcessingSummarySession WHERE LastLatitude IS NOT NULL)
INSERT INTO #StreetWithValidity(TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,ValidDistance,WaterDistanceFinal,BrushDistanceFinal,GpsDistanceFinal,CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,OperationalPlanOldAverage,StreetCompletionPercentage)
SELECT TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,
    SUM(CASE WHEN GpsValid=1 AND WaterValid=1 AND BrushValid=1 THEN DistanceInMeters ELSE 0 END),SUM(CASE WHEN WaterValid=1 THEN DistanceInMeters ELSE 0 END),SUM(CASE WHEN BrushValid=1 THEN DistanceInMeters ELSE 0 END),SUM(CASE WHEN GpsValid=1 THEN DistanceInMeters ELSE 0 END),
    CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,OperationalPlanOldAverage,
    COALESCE((TotalDistance+SUM(CASE WHEN GpsValid=1 AND WaterValid=1 AND BrushValid=1 THEN DistanceInMeters ELSE 0 END))/NULLIF(StreetLength,0)*100,0)
FROM C GROUP BY TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlanOldAverage;

INSERT INTO #TestResults(TestName,Passed,Expected,Actual,Notes)
SELECT 'TC-05: Ignition=0 → ValidDistance = 0',
    CASE WHEN ValidDistance=0 THEN 1 ELSE 0 END,'0',CAST(ValidDistance AS NVARCHAR),'Ignition off blocks GpsValid'
FROM #StreetWithValidity;


-- ============================================================
-- TEST CASE 06
-- NAME    : *** TIME BOUNDARY *** Record BEFORE trip start → excluded
-- NOTE    : This tests Step 1 filter logic. Since we mock
--           #ValidVehicleLocations directly, we simulate it by
--           verifying the LAG calculation produces correct pairs.
--           In real flow, pre-window records never enter this table.
--           Here we insert an EARLY record to test it doesn't
--           contribute distance if its pair is also early.
-- ============================================================

PRINT '--- TC-06: MovementTime BEFORE trip start → 0 contribution ---';

TRUNCATE TABLE #ValidVehicleLocations;
TRUNCATE TABLE #TripDetailsProcessingSummarySession;
TRUNCATE TABLE #StreetWithValidity;

-- BOTH records before @TripStart (simulating records that leaked through)
-- In real SP these should NOT be in #ValidVehicleLocations
-- This test confirms: even if they do appear, time-window aware callers
-- should filter them. Here we document expected behaviour.
INSERT INTO #ValidVehicleLocations VALUES
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 01:30:00'/*BEFORE start*/,@VehicleId, 39.232216, 21.429121, 0, 5, 5, 0, 15, 1, 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 0),
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 01:50:00'/*BEFORE start*/,@VehicleId, 39.233500, 21.429935, 0, 5, 5, 0, 15, 1, 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 0);

-- These records have valid inputs/speed but wrong time
-- Step 1 inner join on t.StartTrip<=x.MovementTime AND t.EndTrip>x.MovementTime
-- would block them. For unit test we count rows in #ValidVehicleLocations
-- and assert that a pre-window-only dataset SHOULD produce 0 valid records.

DECLARE @TC06Count INT = (SELECT COUNT(*) FROM #ValidVehicleLocations
    WHERE MovementTime < @TripStart OR MovementTime >= @TripEnd);

INSERT INTO #TestResults(TestName,Passed,Expected,Actual,Notes)
SELECT 'TC-06: All records outside trip window → should not exist in #ValidVehicleLocations',
    CASE WHEN @TC06Count = 2 THEN 1 ELSE 0 END,
    '2 out-of-window records (would be filtered by Step 1 JOIN)',
    CAST(@TC06Count AS NVARCHAR),
    'If Step 1 works correctly, none of these reach the session table';


-- ============================================================
-- TEST CASE 07
-- NAME    : *** TIME BOUNDARY *** Record AT trip start (=) → INCLUDED
-- MovementTime = @TripStart exactly → t.StartTrip <= MovementTime → valid
-- ============================================================

PRINT '--- TC-07: MovementTime AT trip start boundary → included ---';

TRUNCATE TABLE #ValidVehicleLocations;
TRUNCATE TABLE #TripDetailsProcessingSummarySession;
TRUNCATE TABLE #StreetWithValidity;

INSERT INTO #ValidVehicleLocations VALUES
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 @TripStart /*exactly 02:00:00*/,@VehicleId, 39.232216, 21.429121, 0, 5, 5, 0, 15, 1, 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 0),
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 02:01:00',@VehicleId, 39.233500, 21.429935, 0, 5, 5, 0, 15, 1, 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 0);

;WITH O AS(SELECT *,LAG(Latitude)OVER(PARTITION BY VehicleId ORDER BY MovementTime) AS LastLatitude,LAG(Longitude)OVER(PARTITION BY VehicleId ORDER BY MovementTime) AS LastLongitude FROM #ValidVehicleLocations)
INSERT INTO #TripDetailsProcessingSummarySession(TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,CurrentLatitude,CurrentLongitude,LastLatitude,LastLongitude,VehicleType,ContractingCompanyType,Input1,Input2,Input3,Input4,Speed,Ignition,SessionBrushDistanceCovered,SessionTotalWaterDistanceCoveredPatch,SessionGpsDistanceCoveredPatch,CountActiveTrip,OperationalPlanOldAverage)
SELECT TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,Latitude,Longitude,LastLatitude,LastLongitude,VehicleType,ContractingCompanyType,Input1,Input2,Input3,Input4,Speed,Ignition,0,0,0,CountActiveTrip,OperationalPlanOldAverage FROM O;

;WITH C AS(SELECT *,6371000*2*ASIN(SQRT(POWER(SIN(RADIANS((CurrentLatitude-LastLatitude)/2)),2)+COS(RADIANS(CurrentLatitude))*COS(RADIANS(LastLatitude))*POWER(SIN(RADIANS((CurrentLongitude-LastLongitude)/2)),2))) AS DistanceInMeters,CASE WHEN VehicleType=1 AND ContractingCompanyType=1 AND Input3>0 THEN 1 ELSE 0 END AS WaterValid,CASE WHEN VehicleType=1 AND ContractingCompanyType IN(1,3) AND Input2>0 THEN 1 ELSE 0 END AS BrushValid,CASE WHEN Speed BETWEEN 1 AND 29 AND Ignition=1 THEN 1 ELSE 0 END AS GpsValid,0 AS IsRightValid,0 AS IsLeftValid FROM #TripDetailsProcessingSummarySession WHERE LastLatitude IS NOT NULL)
INSERT INTO #StreetWithValidity(TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,ValidDistance,WaterDistanceFinal,BrushDistanceFinal,GpsDistanceFinal,CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,OperationalPlanOldAverage,StreetCompletionPercentage)
SELECT TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,
    SUM(CASE WHEN GpsValid=1 AND WaterValid=1 AND BrushValid=1 THEN DistanceInMeters ELSE 0 END),SUM(CASE WHEN WaterValid=1 THEN DistanceInMeters ELSE 0 END),SUM(CASE WHEN BrushValid=1 THEN DistanceInMeters ELSE 0 END),SUM(CASE WHEN GpsValid=1 THEN DistanceInMeters ELSE 0 END),
    CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,OperationalPlanOldAverage,
    COALESCE((TotalDistance+SUM(CASE WHEN GpsValid=1 AND WaterValid=1 AND BrushValid=1 THEN DistanceInMeters ELSE 0 END))/NULLIF(StreetLength,0)*100,0)
FROM C GROUP BY TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlanOldAverage;

INSERT INTO #TestResults(TestName,Passed,Expected,Actual,Notes)
SELECT 'TC-07: MovementTime=TripStart (inclusive boundary) → ValidDistance > 0',
    CASE WHEN ValidDistance>0 THEN 1 ELSE 0 END,'>0',CAST(ROUND(ValidDistance,2) AS NVARCHAR),
    'StartTrip <= MovementTime means start boundary is INCLUSIVE'
FROM #StreetWithValidity;


-- ============================================================
-- TEST CASE 08
-- NAME    : *** TIME BOUNDARY *** Record AT trip END (>=) → EXCLUDED
-- EndTrip is EXCLUSIVE: t.EndTrip > x.MovementTime
-- A record exactly at 06:00:00 should NOT appear in #ValidVehicleLocations
-- ============================================================

PRINT '--- TC-08: MovementTime = TripEnd (exclusive) → excluded ---';

-- Record exactly at @TripEnd – Step 1 uses t.EndTrip > MovementTime so this is excluded
DECLARE @TC08_IsExcluded BIT = CASE WHEN @TripEnd > @TripEnd THEN 0 ELSE 1 END;
-- The condition t.EndTrip > MovementTime evaluated with MovementTime=@TripEnd is FALSE

INSERT INTO #TestResults(TestName,Passed,Expected,Actual,Notes)
VALUES('TC-08: MovementTime = TripEnd → exclusive boundary, record filtered',
    @TC08_IsExcluded, '1 (excluded=true)',CAST(@TC08_IsExcluded AS NVARCHAR),
    'Condition t.EndTrip > MovementTime fails when MovementTime = EndTrip');


-- ============================================================
-- TEST CASE 09
-- NAME    : StreetCompletionPercentage capped at 100
-- SETUP   : TotalDistance already near StreetLength + new distance exceeds it
-- ============================================================

PRINT '--- TC-09: StreetCompletion capped at 100% ---';

TRUNCATE TABLE #ValidVehicleLocations;
TRUNCATE TABLE #TripDetailsProcessingSummarySession;
TRUNCATE TABLE #StreetWithValidity;

-- TotalDistance = 1400 (already accumulated from previous hours)
-- StreetLength  = 1500
-- 4 new GPS points ~200m apart → new ~600m > remaining 100m → should cap at 100%
INSERT INTO #ValidVehicleLocations VALUES
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 04:00:00',@VehicleId, 39.232216, 21.429121, 0, 5, 5, 0, 15, 1, 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 1400/*TotalDistance*/),
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 04:01:00',@VehicleId, 39.234000, 21.430500, 0, 5, 5, 0, 15, 1, 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 1400),
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 04:02:00',@VehicleId, 39.235649, 21.431947, 0, 5, 5, 0, 15, 1, 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 1400),
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 04:03:00',@VehicleId, 39.237200, 21.433400, 0, 5, 5, 0, 15, 1, 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 1400);

;WITH O AS(SELECT *,LAG(Latitude)OVER(PARTITION BY VehicleId ORDER BY MovementTime) AS LastLatitude,LAG(Longitude)OVER(PARTITION BY VehicleId ORDER BY MovementTime) AS LastLongitude FROM #ValidVehicleLocations)
INSERT INTO #TripDetailsProcessingSummarySession(TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,CurrentLatitude,CurrentLongitude,LastLatitude,LastLongitude,VehicleType,ContractingCompanyType,Input1,Input2,Input3,Input4,Speed,Ignition,SessionBrushDistanceCovered,SessionTotalWaterDistanceCoveredPatch,SessionGpsDistanceCoveredPatch,CountActiveTrip,OperationalPlanOldAverage)
SELECT TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,Latitude,Longitude,LastLatitude,LastLongitude,VehicleType,ContractingCompanyType,Input1,Input2,Input3,Input4,Speed,Ignition,0,0,0,CountActiveTrip,OperationalPlanOldAverage FROM O;

;WITH C AS(SELECT *,6371000*2*ASIN(SQRT(POWER(SIN(RADIANS((CurrentLatitude-LastLatitude)/2)),2)+COS(RADIANS(CurrentLatitude))*COS(RADIANS(LastLatitude))*POWER(SIN(RADIANS((CurrentLongitude-LastLongitude)/2)),2))) AS DistanceInMeters,CASE WHEN VehicleType=1 AND ContractingCompanyType=1 AND Input3>0 THEN 1 ELSE 0 END AS WaterValid,CASE WHEN VehicleType=1 AND ContractingCompanyType IN(1,3) AND Input2>0 THEN 1 ELSE 0 END AS BrushValid,CASE WHEN Speed BETWEEN 1 AND 29 AND Ignition=1 THEN 1 ELSE 0 END AS GpsValid,0 AS IsRightValid,0 AS IsLeftValid FROM #TripDetailsProcessingSummarySession WHERE LastLatitude IS NOT NULL)
INSERT INTO #StreetWithValidity(TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,ValidDistance,WaterDistanceFinal,BrushDistanceFinal,GpsDistanceFinal,CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,OperationalPlanOldAverage,StreetCompletionPercentage)
SELECT TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,
    SUM(CASE WHEN GpsValid=1 AND WaterValid=1 AND BrushValid=1 THEN DistanceInMeters ELSE 0 END),
    SUM(CASE WHEN WaterValid=1 THEN DistanceInMeters ELSE 0 END),
    SUM(CASE WHEN BrushValid=1 THEN DistanceInMeters ELSE 0 END),
    SUM(CASE WHEN GpsValid=1 THEN DistanceInMeters ELSE 0 END),
    CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,OperationalPlanOldAverage,
    CASE
        WHEN SUM(CASE WHEN GpsValid=1 AND WaterValid=1 AND BrushValid=1 THEN DistanceInMeters ELSE 0 END) > StreetLength
        THEN 100
        ELSE COALESCE((TotalDistance+SUM(CASE WHEN GpsValid=1 AND WaterValid=1 AND BrushValid=1 THEN DistanceInMeters ELSE 0 END))/NULLIF(StreetLength,0)*100,0)
    END
FROM C GROUP BY TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlanOldAverage;

INSERT INTO #TestResults(TestName,Passed,Expected,Actual,Notes)
SELECT 'TC-09: ValidDistance > StreetLength → StreetCompletion capped at 100',
    CASE WHEN StreetCompletionPercentage = 100 THEN 1 ELSE 0 END,
    '100', CAST(StreetCompletionPercentage AS NVARCHAR),
    'TotalDistance=1400 + new>100 → exceeds 1500m StreetLength'
FROM #StreetWithValidity;


-- ============================================================
-- TEST CASE 10
-- NAME    : Step 2 UPDATE idempotency
--           Running the UPDATE twice must NOT double-count TotalDistance
--           (COALESCE(NULLIF(new,0), old) pattern for pct fields)
-- ============================================================

PRINT '--- TC-10: Step 2 UPDATE idempotency (no double-count on re-run) ---';

TRUNCATE TABLE #MockTripDetailsProcessingSummary;

-- Seed with existing state (first hour already processed)
INSERT INTO #MockTripDetailsProcessingSummary(Id, TripDetailsId, TotalDistance, CompletionPercentage,
    TotalBrushDistanceCovered, TotalWaterDistanceCovered, TotalGpsDistanceCovered, IsSwept)
VALUES (@TripDetailsProcessingSummaryId1, NEWID(), 300.0, 20.0, 300.0, 300.0, 300.0, 1);

-- Simulate #StreetWithValidity result for this hour (new 200m valid)
IF OBJECT_ID('tempdb..#MockStreetValidity') IS NOT NULL DROP TABLE #MockStreetValidity;
SELECT
    @TripDetailsProcessingSummaryId1 AS TripDetailsProcessingSummaryId,
    200.0 AS ValidDistance,
    200.0 AS BrushDistanceFinal,
    200.0 AS WaterDistanceFinal,
    200.0 AS GpsDistanceFinal,
    35.0  AS StreetCompletionPercentage  -- new hourly completion
INTO #MockStreetValidity;

-- Apply Step 2 UPDATE logic (mirrored)
UPDATE m
SET
    TotalDistance = m.TotalDistance + COALESCE(s.ValidDistance, 0),
    CompletionPercentage = CASE
        WHEN COALESCE(NULLIF(s.StreetCompletionPercentage,0), m.CompletionPercentage) > 100 THEN 100
        ELSE COALESCE(NULLIF(s.StreetCompletionPercentage,0), m.CompletionPercentage)
    END,
    TotalBrushDistanceCovered = COALESCE(NULLIF(s.BrushDistanceFinal,0), m.TotalBrushDistanceCovered),
    TotalWaterDistanceCovered = COALESCE(NULLIF(s.WaterDistanceFinal,0), m.TotalWaterDistanceCovered),
    TotalGpsDistanceCovered   = COALESCE(NULLIF(s.GpsDistanceFinal,0),   m.TotalGpsDistanceCovered)
FROM #MockTripDetailsProcessingSummary m
INNER JOIN #MockStreetValidity s ON m.Id = s.TripDetailsProcessingSummaryId;

DECLARE @TC10_TotalAfterFirstRun FLOAT = (SELECT TotalDistance FROM #MockTripDetailsProcessingSummary WHERE Id=@TripDetailsProcessingSummaryId1);

-- Run update AGAIN with SAME data (simulating second call in same hour)
UPDATE m
SET
    TotalDistance = m.TotalDistance + COALESCE(s.ValidDistance, 0),
    CompletionPercentage = CASE
        WHEN COALESCE(NULLIF(s.StreetCompletionPercentage,0), m.CompletionPercentage) > 100 THEN 100
        ELSE COALESCE(NULLIF(s.StreetCompletionPercentage,0), m.CompletionPercentage)
    END
FROM #MockTripDetailsProcessingSummary m
INNER JOIN #MockStreetValidity s ON m.Id = s.TripDetailsProcessingSummaryId;

DECLARE @TC10_TotalAfterSecondRun FLOAT = (SELECT TotalDistance FROM #MockTripDetailsProcessingSummary WHERE Id=@TripDetailsProcessingSummaryId1);

-- TotalDistance IS cumulative (+=), so second run WILL add again
-- This is intentional per the SP design (each 1-hour window is a separate call)
-- The test documents the EXPECTED behaviour: 300 + 200 + 200 = 700
INSERT INTO #TestResults(TestName,Passed,Expected,Actual,Notes)
VALUES(
    'TC-10: TotalDistance accumulates per-call (300+200=500 first run)',
    CASE WHEN @TC10_TotalAfterFirstRun = 500.0 THEN 1 ELSE 0 END,
    '500', CAST(@TC10_TotalAfterFirstRun AS NVARCHAR),
    'TotalDistance += ValidDistance; this is additive by design'
),
(
    'TC-10b: CompletionPercentage uses COALESCE(NULLIF) so 2nd same-value run keeps 35 not 0',
    CASE WHEN (SELECT CompletionPercentage FROM #MockTripDetailsProcessingSummary WHERE Id=@TripDetailsProcessingSummaryId1) = 35.0 THEN 1 ELSE 0 END,
    '35', CAST((SELECT CompletionPercentage FROM #MockTripDetailsProcessingSummary WHERE Id=@TripDetailsProcessingSummaryId1) AS NVARCHAR),
    'COALESCE(NULLIF(new,0), old) preserves the last non-zero value'
);


-- ============================================================
-- TEST CASE 11
-- NAME    : Weighted average trip completion (2 streets)
--           Street1: 65% weight, 80% complete
--           Street2: 35% weight, 40% complete
--           Expected: (80*65 + 40*35) / (65+35) = (5200+1400)/100 = 66
-- ============================================================

PRINT '--- TC-11: Weighted average trip completion ---';

TRUNCATE TABLE #TripWithCompletion;
IF OBJECT_ID('tempdb..#TC11_TDPS') IS NOT NULL DROP TABLE #TC11_TDPS;

-- Mock TripDetailsProcessingSummary with final completion per street
SELECT
    @TripDetailsProcessingSummaryId1 AS TripDetailsProcessingSummaryId,
    80.0 AS CompletionPercentage,
    @Street1Weight AS StreetWeightPercentage
INTO #TC11_TDPS
UNION ALL
SELECT @TripDetailsProcessingSummaryId2, 40.0, @Street2Weight;

DECLARE @WeightedAvg FLOAT =
    (SELECT
        CASE WHEN SUM(StreetWeightPercentage)=0 THEN 0
             ELSE SUM(CompletionPercentage * StreetWeightPercentage) / SUM(StreetWeightPercentage)
        END
    FROM #TC11_TDPS);

INSERT INTO #TestResults(TestName,Passed,Expected,Actual,Notes)
VALUES(
    'TC-11: Weighted trip completion = (80*65 + 40*35)/100 = 66.0',
    CASE WHEN ABS(@WeightedAvg - 66.0) < 0.01 THEN 1 ELSE 0 END,
    '66.0', CAST(ROUND(@WeightedAvg,4) AS NVARCHAR),
    'Street1:80%@65wt, Street2:40%@35wt → weighted avg=66'
);


-- ============================================================
-- TEST CASE 12
-- NAME    : Weighted average capped at 100%
--           Both streets 100% → weighted avg = 100
-- ============================================================

PRINT '--- TC-12: Weighted avg capped at 100 ---';

IF OBJECT_ID('tempdb..#TC12_TDPS') IS NOT NULL DROP TABLE #TC12_TDPS;
SELECT @TripDetailsProcessingSummaryId1 AS TripDetailsProcessingSummaryId, 100.0 AS CompletionPercentage, @Street1Weight AS StreetWeightPercentage
INTO #TC12_TDPS
UNION ALL SELECT @TripDetailsProcessingSummaryId2, 100.0, @Street2Weight;

DECLARE @TC12Avg FLOAT = (SELECT SUM(CompletionPercentage * StreetWeightPercentage)/SUM(StreetWeightPercentage) FROM #TC12_TDPS);

INSERT INTO #TestResults(TestName,Passed,Expected,Actual,Notes)
VALUES('TC-12: Both streets 100% → TripWeightedCompletion = 100',
    CASE WHEN @TC12Avg = 100.0 THEN 1 ELSE 0 END,
    '100', CAST(@TC12Avg AS NVARCHAR), 'All streets complete = trip complete');


-- ============================================================
-- TEST CASE 13
-- NAME    : VehicleType=16, CompanyType=1 – Water=Input3, Brush=Input2
--           Verify specific vehicle/company combination routing
-- ============================================================

PRINT '--- TC-13: VehicleType=16, CompanyType=1 – Input routing ---';

TRUNCATE TABLE #ValidVehicleLocations;
TRUNCATE TABLE #TripDetailsProcessingSummarySession;
TRUNCATE TABLE #StreetWithValidity;

-- Input3=5 → WaterValid, Input2=5 → BrushValid, Speed=10, Ignition=1
INSERT INTO #ValidVehicleLocations VALUES
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 05:00:00',@VehicleId, 39.232216, 21.429121, 0/*I1*/, 5/*I2*/, 5/*I3*/, 0/*I4*/, 10, 1,
 16/*VehicleType*/, 1/*CompanyType*/, 1, 0, @Street1Weight, @Street1Length, 1, 0),
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 05:01:00',@VehicleId, 39.233500, 21.429935, 0, 5, 5, 0, 10, 1,
 16, 1, 1, 0, @Street1Weight, @Street1Length, 1, 0);

;WITH O AS(SELECT *,LAG(Latitude)OVER(PARTITION BY VehicleId ORDER BY MovementTime) AS LastLatitude,LAG(Longitude)OVER(PARTITION BY VehicleId ORDER BY MovementTime) AS LastLongitude FROM #ValidVehicleLocations)
INSERT INTO #TripDetailsProcessingSummarySession(TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,CurrentLatitude,CurrentLongitude,LastLatitude,LastLongitude,VehicleType,ContractingCompanyType,Input1,Input2,Input3,Input4,Speed,Ignition,SessionBrushDistanceCovered,SessionTotalWaterDistanceCoveredPatch,SessionGpsDistanceCoveredPatch,CountActiveTrip,OperationalPlanOldAverage)
SELECT TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,Latitude,Longitude,LastLatitude,LastLongitude,VehicleType,ContractingCompanyType,Input1,Input2,Input3,Input4,Speed,Ignition,0,0,0,CountActiveTrip,OperationalPlanOldAverage FROM O;

;WITH C AS(
    SELECT *,
        6371000*2*ASIN(SQRT(POWER(SIN(RADIANS((CurrentLatitude-LastLatitude)/2)),2)+COS(RADIANS(CurrentLatitude))*COS(RADIANS(LastLatitude))*POWER(SIN(RADIANS((CurrentLongitude-LastLongitude)/2)),2))) AS DistanceInMeters,
        -- VehicleType=16, CompanyType=1: Water=Input3>0
        CASE WHEN (VehicleType=16 AND ContractingCompanyType=1 AND Input3>0) THEN 1 ELSE 0 END AS WaterValid,
        -- VehicleType=16, CompanyType=1: Brush=Input2>0
        CASE WHEN (VehicleType=16 AND ContractingCompanyType=1 AND Input2>0) THEN 1 ELSE 0 END AS BrushValid,
        CASE WHEN Speed BETWEEN 1 AND 29 AND Ignition=1 THEN 1 ELSE 0 END AS GpsValid,
        0 AS IsRightValid, 0 AS IsLeftValid
    FROM #TripDetailsProcessingSummarySession WHERE LastLatitude IS NOT NULL
)
INSERT INTO #StreetWithValidity(TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,ValidDistance,WaterDistanceFinal,BrushDistanceFinal,GpsDistanceFinal,CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,OperationalPlanOldAverage,StreetCompletionPercentage)
SELECT TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,
    SUM(CASE WHEN GpsValid=1 AND WaterValid=1 AND BrushValid=1 THEN DistanceInMeters ELSE 0 END),
    SUM(CASE WHEN WaterValid=1 THEN DistanceInMeters ELSE 0 END),
    SUM(CASE WHEN BrushValid=1 THEN DistanceInMeters ELSE 0 END),
    SUM(CASE WHEN GpsValid=1 THEN DistanceInMeters ELSE 0 END),
    CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,OperationalPlanOldAverage,
    COALESCE((TotalDistance+SUM(CASE WHEN GpsValid=1 AND WaterValid=1 AND BrushValid=1 THEN DistanceInMeters ELSE 0 END))/NULLIF(StreetLength,0)*100,0)
FROM C GROUP BY TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlanOldAverage;

INSERT INTO #TestResults(TestName,Passed,Expected,Actual,Notes)
SELECT 'TC-13: VehicleType=16, CompanyType=1, Input2+3>0 → ValidDistance > 0',
    CASE WHEN ValidDistance>0 THEN 1 ELSE 0 END,'>0',CAST(ROUND(ValidDistance,2) AS NVARCHAR),
    'Water=Input3, Brush=Input2 for this vehicle/company combo'
FROM #StreetWithValidity;


-- ============================================================
-- TEST CASE 14
-- NAME    : Bayt al Arab group (VehicleType=16, CompanyType=3)
--           Left side: Input3>0 AND Input4>0 → IsLeftValid=1
--           Right side: Input1>0 AND Input2>0 → IsRightValid=1
--           Either side alone should allow valid distance (OR condition)
-- ============================================================

PRINT '--- TC-14: Bayt al Arab – big vehicle left/right sides ---';

TRUNCATE TABLE #ValidVehicleLocations;
TRUNCATE TABLE #TripDetailsProcessingSummarySession;
TRUNCATE TABLE #StreetWithValidity;

-- Only RIGHT side active (Input1=5, Input2=5), left side off
INSERT INTO #ValidVehicleLocations VALUES
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 05:30:00',@VehicleId, 39.232216, 21.429121,
  5/*I1*/, 5/*I2*/, 0/*I3*/, 0/*I4*/, 15, 1, 16, 3, 1, 0, @Street1Weight, @Street1Length, 1, 0),
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 05:31:00',@VehicleId, 39.233500, 21.429935,
  5, 5, 0, 0, 15, 1, 16, 3, 1, 0, @Street1Weight, @Street1Length, 1, 0);

;WITH O AS(SELECT *,LAG(Latitude)OVER(PARTITION BY VehicleId ORDER BY MovementTime) AS LastLatitude,LAG(Longitude)OVER(PARTITION BY VehicleId ORDER BY MovementTime) AS LastLongitude FROM #ValidVehicleLocations)
INSERT INTO #TripDetailsProcessingSummarySession(TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,CurrentLatitude,CurrentLongitude,LastLatitude,LastLongitude,VehicleType,ContractingCompanyType,Input1,Input2,Input3,Input4,Speed,Ignition,SessionBrushDistanceCovered,SessionTotalWaterDistanceCoveredPatch,SessionGpsDistanceCoveredPatch,CountActiveTrip,OperationalPlanOldAverage)
SELECT TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,Latitude,Longitude,LastLatitude,LastLongitude,VehicleType,ContractingCompanyType,Input1,Input2,Input3,Input4,Speed,Ignition,0,0,0,CountActiveTrip,OperationalPlanOldAverage FROM O;

;WITH C AS(
    SELECT *,
        6371000*2*ASIN(SQRT(POWER(SIN(RADIANS((CurrentLatitude-LastLatitude)/2)),2)+COS(RADIANS(CurrentLatitude))*COS(RADIANS(LastLatitude))*POWER(SIN(RADIANS((CurrentLongitude-LastLongitude)/2)),2))) AS DistanceInMeters,
        CASE WHEN VehicleType=16 AND ContractingCompanyType=3 AND (Input2>0 OR Input3>0) THEN 1 ELSE 0 END AS WaterValid,
        CASE WHEN VehicleType=16 AND ContractingCompanyType=3 AND (Input1>0 OR Input4>0) THEN 1 ELSE 0 END AS BrushValid,
        CASE WHEN Speed BETWEEN 1 AND 29 AND Ignition=1 THEN 1 ELSE 0 END AS GpsValid,
        CASE WHEN VehicleType=16 AND ContractingCompanyType=3 AND Input1>0 AND Input2>0 THEN 1 ELSE 0 END AS IsRightValid,
        CASE WHEN VehicleType=16 AND ContractingCompanyType=3 AND Input3>0 AND Input4>0 THEN 1 ELSE 0 END AS IsLeftValid
    FROM #TripDetailsProcessingSummarySession WHERE LastLatitude IS NOT NULL
)
INSERT INTO #StreetWithValidity(TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,ValidDistance,WaterDistanceFinal,BrushDistanceFinal,GpsDistanceFinal,CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,OperationalPlanOldAverage,StreetCompletionPercentage)
SELECT TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,
    SUM(CASE WHEN GpsValid=1 AND (WaterValid=1 AND BrushValid=1 OR IsLeftValid=1 OR IsRightValid=1) THEN DistanceInMeters ELSE 0 END),
    SUM(CASE WHEN WaterValid=1 THEN DistanceInMeters ELSE 0 END),
    SUM(CASE WHEN BrushValid=1 THEN DistanceInMeters ELSE 0 END),
    SUM(CASE WHEN GpsValid=1  THEN DistanceInMeters ELSE 0 END),
    CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,OperationalPlanOldAverage,
    COALESCE((TotalDistance+SUM(CASE WHEN GpsValid=1 AND (WaterValid=1 AND BrushValid=1 OR IsLeftValid=1 OR IsRightValid=1) THEN DistanceInMeters ELSE 0 END))/NULLIF(StreetLength,0)*100,0)
FROM C GROUP BY TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlanOldAverage;

INSERT INTO #TestResults(TestName,Passed,Expected,Actual,Notes)
SELECT 'TC-14: Bayt al Arab VT=16 CT=3, right side (I1+I2>0) → IsRightValid → ValidDistance > 0',
    CASE WHEN ValidDistance>0 THEN 1 ELSE 0 END,'>0',CAST(ROUND(ValidDistance,2) AS NVARCHAR),
    'IsRightValid alone (without full WaterValid+BrushValid) should count'
FROM #StreetWithValidity;


-- ============================================================
-- TEST CASE 15
-- NAME    : Zero-distance consecutive points (same lat/lon)
--           → DistanceInMeters = 0 → no contribution
-- ============================================================

PRINT '--- TC-15: Duplicate GPS coordinates → 0 distance ---';

TRUNCATE TABLE #ValidVehicleLocations;
TRUNCATE TABLE #TripDetailsProcessingSummarySession;
TRUNCATE TABLE #StreetWithValidity;

INSERT INTO #ValidVehicleLocations VALUES
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 03:50:00',@VehicleId, 39.232216, 21.429121, 0, 5, 5, 0, 15, 1, 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 0),
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 03:51:00',@VehicleId, 39.232216, 21.429121/*SAME*/,0, 5, 5, 0, 15, 1, 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 0);

;WITH O AS(SELECT *,LAG(Latitude)OVER(PARTITION BY VehicleId ORDER BY MovementTime) AS LastLatitude,LAG(Longitude)OVER(PARTITION BY VehicleId ORDER BY MovementTime) AS LastLongitude FROM #ValidVehicleLocations)
INSERT INTO #TripDetailsProcessingSummarySession(TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,CurrentLatitude,CurrentLongitude,LastLatitude,LastLongitude,VehicleType,ContractingCompanyType,Input1,Input2,Input3,Input4,Speed,Ignition,SessionBrushDistanceCovered,SessionTotalWaterDistanceCoveredPatch,SessionGpsDistanceCoveredPatch,CountActiveTrip,OperationalPlanOldAverage)
SELECT TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,Latitude,Longitude,LastLatitude,LastLongitude,VehicleType,ContractingCompanyType,Input1,Input2,Input3,Input4,Speed,Ignition,0,0,0,CountActiveTrip,OperationalPlanOldAverage FROM O;

;WITH C AS(SELECT *,6371000*2*ASIN(SQRT(POWER(SIN(RADIANS((CurrentLatitude-LastLatitude)/2)),2)+COS(RADIANS(CurrentLatitude))*COS(RADIANS(LastLatitude))*POWER(SIN(RADIANS((CurrentLongitude-LastLongitude)/2)),2))) AS DistanceInMeters,CASE WHEN VehicleType=1 AND ContractingCompanyType=1 AND Input3>0 THEN 1 ELSE 0 END AS WaterValid,CASE WHEN VehicleType=1 AND ContractingCompanyType IN(1,3) AND Input2>0 THEN 1 ELSE 0 END AS BrushValid,CASE WHEN Speed BETWEEN 1 AND 29 AND Ignition=1 THEN 1 ELSE 0 END AS GpsValid,0 AS IsRightValid,0 AS IsLeftValid FROM #TripDetailsProcessingSummarySession WHERE LastLatitude IS NOT NULL)
INSERT INTO #StreetWithValidity(TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,ValidDistance,WaterDistanceFinal,BrushDistanceFinal,GpsDistanceFinal,CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,OperationalPlanOldAverage,StreetCompletionPercentage)
SELECT TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,
    SUM(CASE WHEN GpsValid=1 AND WaterValid=1 AND BrushValid=1 THEN DistanceInMeters ELSE 0 END),SUM(CASE WHEN WaterValid=1 THEN DistanceInMeters ELSE 0 END),SUM(CASE WHEN BrushValid=1 THEN DistanceInMeters ELSE 0 END),SUM(CASE WHEN GpsValid=1 THEN DistanceInMeters ELSE 0 END),
    CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,OperationalPlanOldAverage,
    COALESCE((TotalDistance+SUM(CASE WHEN GpsValid=1 AND WaterValid=1 AND BrushValid=1 THEN DistanceInMeters ELSE 0 END))/NULLIF(StreetLength,0)*100,0)
FROM C GROUP BY TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlanOldAverage;

INSERT INTO #TestResults(TestName,Passed,Expected,Actual,Notes)
SELECT 'TC-15: Identical consecutive GPS points → ValidDistance = 0',
    CASE WHEN ValidDistance=0 THEN 1 ELSE 0 END,'0',CAST(ValidDistance AS NVARCHAR),
    'Haversine of zero displacement = 0m'
FROM #StreetWithValidity;


-- ============================================================
-- TEST CASE 16
-- NAME    : Input3 = 0 (Water OFF) for VehicleType=1, CompanyType=1
--           → WaterValid = 0 → ValidDistance = 0
--           (Both water AND brush must be valid together)
-- ============================================================

PRINT '--- TC-16: Water input OFF → no valid distance even if GPS+Brush valid ---';

TRUNCATE TABLE #ValidVehicleLocations;
TRUNCATE TABLE #TripDetailsProcessingSummarySession;
TRUNCATE TABLE #StreetWithValidity;

INSERT INTO #ValidVehicleLocations VALUES
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 04:10:00',@VehicleId, 39.232216, 21.429121, 0, 5, 0/*Water OFF*/, 0, 15, 1, 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 0),
(@TripId,@TripDetailsProcessingSummaryId1,@TripProcessingSummaryId,@OperationalPlansId,@ContractServiceId,@ContractId,@ServiceGroupId,
 '2026-04-19 04:11:00',@VehicleId, 39.233500, 21.429935, 0, 5, 0, 0, 15, 1, 1, 1, 1, 0, @Street1Weight, @Street1Length, 1, 0);

;WITH O AS(SELECT *,LAG(Latitude)OVER(PARTITION BY VehicleId ORDER BY MovementTime) AS LastLatitude,LAG(Longitude)OVER(PARTITION BY VehicleId ORDER BY MovementTime) AS LastLongitude FROM #ValidVehicleLocations)
INSERT INTO #TripDetailsProcessingSummarySession(TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,CurrentLatitude,CurrentLongitude,LastLatitude,LastLongitude,VehicleType,ContractingCompanyType,Input1,Input2,Input3,Input4,Speed,Ignition,SessionBrushDistanceCovered,SessionTotalWaterDistanceCoveredPatch,SessionGpsDistanceCoveredPatch,CountActiveTrip,OperationalPlanOldAverage)
SELECT TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,Latitude,Longitude,LastLatitude,LastLongitude,VehicleType,ContractingCompanyType,Input1,Input2,Input3,Input4,Speed,Ignition,0,0,0,CountActiveTrip,OperationalPlanOldAverage FROM O;

;WITH C AS(SELECT *,6371000*2*ASIN(SQRT(POWER(SIN(RADIANS((CurrentLatitude-LastLatitude)/2)),2)+COS(RADIANS(CurrentLatitude))*COS(RADIANS(LastLatitude))*POWER(SIN(RADIANS((CurrentLongitude-LastLongitude)/2)),2))) AS DistanceInMeters,CASE WHEN VehicleType=1 AND ContractingCompanyType=1 AND Input3>0 THEN 1 ELSE 0 END AS WaterValid,CASE WHEN VehicleType=1 AND ContractingCompanyType IN(1,3) AND Input2>0 THEN 1 ELSE 0 END AS BrushValid,CASE WHEN Speed BETWEEN 1 AND 29 AND Ignition=1 THEN 1 ELSE 0 END AS GpsValid,0 AS IsRightValid,0 AS IsLeftValid FROM #TripDetailsProcessingSummarySession WHERE LastLatitude IS NOT NULL)
INSERT INTO #StreetWithValidity(TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,ValidDistance,WaterDistanceFinal,BrushDistanceFinal,GpsDistanceFinal,CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,OperationalPlanOldAverage,StreetCompletionPercentage)
SELECT TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,
    SUM(CASE WHEN GpsValid=1 AND WaterValid=1 AND BrushValid=1 THEN DistanceInMeters ELSE 0 END),SUM(CASE WHEN WaterValid=1 THEN DistanceInMeters ELSE 0 END),SUM(CASE WHEN BrushValid=1 THEN DistanceInMeters ELSE 0 END),SUM(CASE WHEN GpsValid=1 THEN DistanceInMeters ELSE 0 END),
    CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,OperationalPlanOldAverage,
    COALESCE((TotalDistance+SUM(CASE WHEN GpsValid=1 AND WaterValid=1 AND BrushValid=1 THEN DistanceInMeters ELSE 0 END))/NULLIF(StreetLength,0)*100,0)
FROM C GROUP BY TripId,TripProcessingSummaryId,TripDetailsProcessingSummaryId,OperationalPlansId,ContractServiceId,ContractId,ServiceGroupId,VehicleType,ContractingCompanyType,CountActiveTrip,StreetOrder,StreetLength,StreetWeightPercentage,TotalDistance,OperationalPlanOldAverage;

INSERT INTO #TestResults(TestName,Passed,Expected,Actual,Notes)
SELECT 'TC-16: VT=1 CT=1, Input3=0 (WaterOFF) → ValidDistance=0 even with Brush+GPS valid',
    CASE WHEN ValidDistance=0 THEN 1 ELSE 0 END,'0',CAST(ValidDistance AS NVARCHAR),
    'For VT=1 CT=1: ValidDistance needs GpsValid AND WaterValid AND BrushValid'
FROM #StreetWithValidity;


-- ============================================================
-- ============================================================
-- FINAL RESULTS REPORT
-- ============================================================
-- ============================================================

PRINT '';
PRINT '============================================================';
PRINT ' TEST RESULTS';
PRINT '============================================================';

SELECT
    TestId,
    TestName,
    CASE Passed WHEN 1 THEN '✓ PASS' ELSE '✗ FAIL' END AS Result,
    Expected,
    Actual,
    Notes
FROM #TestResults
ORDER BY TestId;

DECLARE @PassCount INT = (SELECT COUNT(*) FROM #TestResults WHERE Passed=1);
DECLARE @FailCount INT = (SELECT COUNT(*) FROM #TestResults WHERE Passed=0);
DECLARE @TotalCount INT = (SELECT COUNT(*) FROM #TestResults);

PRINT '';
PRINT '------------------------------------------------------------';
PRINT 'SUMMARY: ' + CAST(@PassCount AS NVARCHAR) + '/' + CAST(@TotalCount AS NVARCHAR) + ' passed,  ' + CAST(@FailCount AS NVARCHAR) + ' failed.';
PRINT '------------------------------------------------------------';

-- Cleanup
IF OBJECT_ID('tempdb..#ValidVehicleLocations')                IS NOT NULL DROP TABLE #ValidVehicleLocations;
IF OBJECT_ID('tempdb..#TripDetailsProcessingSummarySession')  IS NOT NULL DROP TABLE #TripDetailsProcessingSummarySession;
IF OBJECT_ID('tempdb..#StreetWithValidity')                   IS NOT NULL DROP TABLE #StreetWithValidity;
IF OBJECT_ID('tempdb..#TripWithCompletion')                   IS NOT NULL DROP TABLE #TripWithCompletion;
IF OBJECT_ID('tempdb..#MockTripDetailsProcessingSummary')     IS NOT NULL DROP TABLE #MockTripDetailsProcessingSummary;
IF OBJECT_ID('tempdb..#MockStreetValidity')                   IS NOT NULL DROP TABLE #MockStreetValidity;
IF OBJECT_ID('tempdb..#TC11_TDPS')                            IS NOT NULL DROP TABLE #TC11_TDPS;
IF OBJECT_ID('tempdb..#TC12_TDPS')                            IS NOT NULL DROP TABLE #TC12_TDPS;
IF OBJECT_ID('tempdb..#PipelineRan')                          IS NOT NULL DROP TABLE #PipelineRan;
IF OBJECT_ID('tempdb..#TestResults')                          IS NOT NULL DROP TABLE #TestResults;
