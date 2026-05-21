
begin transaction 
;WITH cte AS (
   SELECT 
    tps.ExpectedCovarge AS recoredForUi,
    COUNT(td.Id) AS realExpectedCovarge,
    td.TripId
FROM TripDetails td 
INNER JOIN dbo.TripDetailsProcessingSummary tdps ON td.Id = tdps.TripDetailsId
INNER JOIN dbo.Trips t ON t.Id = td.TripId 
INNER JOIN dbo.TripProcessingSummary tps ON tps.TripId = t.Id
WHERE t.Id IN (
      SELECT t_inner.Id 
    FROM Trips t_inner 
    INNER JOIN OperationalPlans op ON op.Id = t_inner.OperationalPlansId
    INNER JOIN ContractServices cs ON cs.Id = op.ContractServiceId
    INNER JOIN ServiceGeometryType sgt ON sgt.ServiceId = cs.ServiceId
    WHERE sgt.GeometryTypeId = 1 and t_inner.Id in (
select TripId from  tripprocessingsummary 
where expectedCovarge =ActualCovarge)
) 
AND NOT EXISTS (
    SELECT 1 
    FROM dbo.TripDetailsProcessingSummary tdps2
    WHERE tdps2.TripDetailsId = td.Id
    AND tdps2.StatusLookupId IN (15, 16)
)
GROUP BY 
    td.TripId,
    tps.ExpectedCovarge

HAVING COUNT(td.Id) <> tps.ExpectedCovarge
)
UPDATE tps
SET tps.ExpectedCovarge = xx.realExpectedCovarge
FROM TripProcessingSummary tps
INNER JOIN cte xx ON xx.TripId = tps.TripId;


;WITH cte AS (
    SELECT 
    sum(case when tdps.binstatusId=2 and tdps.statuslookupId=13 then 1 else 0 END)
        AS realActualCovarge,
        td.TripId
    FROM TripDetails td 
    INNER JOIN dbo.TripDetailsProcessingSummary tdps ON td.Id = tdps.TripDetailsId
    INNER JOIN dbo.Trips t ON t.Id = td.TripId 
    INNER JOIN dbo.TripProcessingSummary tps ON tps.TripId = t.Id
    WHERE t.Id IN (
      SELECT t_inner.Id 
    FROM Trips t_inner 
    INNER JOIN OperationalPlans op ON op.Id = t_inner.OperationalPlansId
    INNER JOIN ContractServices cs ON cs.Id = op.ContractServiceId
    INNER JOIN ServiceGeometryType sgt ON sgt.ServiceId = cs.ServiceId
    WHERE sgt.GeometryTypeId = 1 
    )     GROUP BY 
        td.TripId
)
UPDATE tps
SET tps.ActualCovarge = xx.realActualCovarge
FROM TripProcessingSummary tps
INNER JOIN cte xx ON xx.TripId = tps.TripId;

UPDATE TripProcessingSummary  
SET CompletionPercentage = 
    CASE 
        WHEN ActualCovarge * 100.0 / NULLIF(ExpectedCovarge, 0) > 100 
            THEN 100
        ELSE 
            CAST(ActualCovarge * 100.0 / NULLIF(ExpectedCovarge, 0) AS DECIMAL(18,2))
    END

WHERE TripId IN (
    SELECT t_inner.Id 
    FROM Trips t_inner 
    INNER JOIN OperationalPlans op ON op.Id = t_inner.OperationalPlansId
    INNER JOIN ContractServices cs ON cs.Id = op.ContractServiceId
    INNER JOIN ServiceGeometryType sgt ON sgt.ServiceId = cs.ServiceId
    WHERE sgt.GeometryTypeId = 1
);


commit transaction ;




