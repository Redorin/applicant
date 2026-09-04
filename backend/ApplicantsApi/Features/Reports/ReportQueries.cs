using System.Text;
using ApplicantsApi.Data;
using Dapper;

namespace ApplicantsApi.Features.Reports;

public sealed class ReportQueries(Db db)
{
    /// <summary>Eligibility summary: STRING_AGG over the junction table with a
    /// fallback to the legacy free-text column — same rule as the old export.</summary>
    // The district-lookup subquery below compares mu.municipal = m.municipality
    // with no LTRIM/RTRIM wrapping — both columns are trimmed at write time and
    // backfilled once at startup (MaintenanceService.EnsureTrimmedDataAsync),
    // so the direct comparison can use IX_municipals_municipal instead of
    // defeating it with a wrapped, non-sargable predicate.
    private const string EligibilityExpr =
        """
        ISNULL(NULLIF((SELECT STRING_AGG(e.eligibility, ', ')
                       FROM masterdata_eligibilities e
                       WHERE e.masterdata_id = m.id), ''), m.eligibility)
        """;

    public async Task<List<ReportRow>> QueryRowsAsync(ListReportRequest req, bool hiredOnly)
    {
        var where = new StringBuilder(
            "WHERE (m.archived = 0 OR m.archived IS NULL)");
        var args = new DynamicParameters();

        if (hiredOnly)
        {
            where.Append(" AND a.hired_date IS NOT NULL");
            if (req.HiredFrom is not null)
            {
                where.Append(" AND a.hired_date >= @hiredFrom");
                args.Add("hiredFrom", req.HiredFrom);
            }
            if (req.HiredTo is not null)
            {
                where.Append(" AND a.hired_date < @hiredToX");
                args.Add("hiredToX", req.HiredTo.Value.Date.AddDays(1));
            }
        }

        if (req.DateFrom is not null)
        {
            where.Append(" AND a.app_date >= @dateFrom");
            args.Add("dateFrom", req.DateFrom);
        }
        if (req.DateTo is not null)
        {
            where.Append(" AND a.app_date < @dateToX");
            args.Add("dateToX", req.DateTo.Value.Date.AddDays(1));
        }

        // Slash-delimited alternatives become OR groups of LIKEs, matching the
        // old criteria grid's "Nurse/Midwife" convention.
        void AddLikeGroup(string? raw, string column, string prefix)
        {
            if (string.IsNullOrWhiteSpace(raw)) return;
            var alternatives = raw.Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (alternatives.Length == 0) return;
            var clauses = new List<string>();
            for (var i = 0; i < alternatives.Length; i++)
            {
                var p = $"{prefix}{i}";
                clauses.Add($"{column} LIKE @{p}");
                args.Add(p, $"%{alternatives[i]}%");
            }
            where.Append($" AND ({string.Join(" OR ", clauses)})");
        }

        AddLikeGroup(req.Recommendation, "a.recommendation", "rec");
        AddLikeGroup(req.Position, "a.position", "pos");
        AddLikeGroup(req.Department, "a.department", "dep");
        AddLikeGroup(req.Education, "m.education", "edu");
        AddLikeGroup(req.Status, hiredOnly ? "a.finalstatus" : "a.status", "sta");

        var orderBy = req.SortMode switch
        {
            "recommendation" => "ISNULL(a.recommendation,''), m.surname, m.firstname",
            "education" => "ISNULL(m.education,''), m.surname, m.firstname",
            _ => "m.surname, m.firstname, a.app_date",
        };

        await using var conn = await db.OpenAsync();
        var rows = await conn.QueryAsync<ReportRow>(
            $"""
            SELECT
                m.surname AS Surname, m.firstname AS Firstname, m.midname AS Midname, m.ext AS Ext,
                m.dbirth AS Dbirth, m.gender AS Gender, m.civistat AS Civistat,
                m.address AS Address, m.house_no AS HouseNo, m.street AS Street,
                m.subdivision AS Subdivision, m.barangay AS Barangay,
                m.municipality AS Municipality,
                ISNULL(NULLIF(LTRIM(RTRIM(m.district)),''),
                       (SELECT TOP 1 mu.district FROM municipals mu
                        WHERE mu.municipal = m.municipality)) AS District,
                m.province AS Province,
                m.education AS Education, m.education2 AS Education2, m.school AS School,
                {EligibilityExpr} AS Eligibility,
                m.contact AS Contact, m.contact2 AS Contact2,
                m.experience AS Experience, m.skills AS Skills, m.training AS Training,
                m.lenofservice AS Lenofservice,
                m.personincharge AS Personincharge, m.notes AS Notes,
                a.app_date AS AppDate, a.position AS Position, a.department AS Department,
                a.status AS Status, a.intvw_date AS IntvwDate, a.recommendation AS Recommendation,
                a.hired_date AS HiredDate, a.finalposition AS FinalPosition,
                a.finaldepartment AS FinalDepartment, a.finalstatus AS FinalStatus,
                a.emp_status AS EmpStatus, a.remarks AS Remarks
            FROM applications a
            JOIN masterdata m ON a.app_id = m.id
            {where}
            ORDER BY {orderBy}
            """, args);
        return rows.ToList();
    }

    public async Task<ReportRow?> QuerySingleApplicantAsync(int masterdataId)
    {
        await using var conn = await db.OpenAsync();
        var rows = await conn.QueryAsync<ReportRow>(
            $"""
            SELECT
                m.surname AS Surname, m.firstname AS Firstname, m.midname AS Midname, m.ext AS Ext,
                m.dbirth AS Dbirth, m.gender AS Gender, m.civistat AS Civistat,
                m.address AS Address, m.house_no AS HouseNo, m.street AS Street,
                m.subdivision AS Subdivision, m.barangay AS Barangay,
                m.municipality AS Municipality,
                ISNULL(NULLIF(LTRIM(RTRIM(m.district)),''),
                       (SELECT TOP 1 mu.district FROM municipals mu
                        WHERE mu.municipal = m.municipality)) AS District,
                m.province AS Province,
                m.education AS Education, m.education2 AS Education2, m.school AS School,
                {EligibilityExpr} AS Eligibility,
                m.contact AS Contact, m.contact2 AS Contact2,
                m.experience AS Experience, m.skills AS Skills, m.training AS Training,
                m.lenofservice AS Lenofservice,
                m.personincharge AS Personincharge, m.notes AS Notes,
                a.app_date AS AppDate, a.position AS Position, a.department AS Department,
                a.status AS Status, a.intvw_date AS IntvwDate, a.recommendation AS Recommendation,
                a.hired_date AS HiredDate, a.finalposition AS FinalPosition,
                a.finaldepartment AS FinalDepartment, a.finalstatus AS FinalStatus,
                a.emp_status AS EmpStatus, a.remarks AS Remarks
            FROM masterdata m
            LEFT JOIN applications a ON a.app_id = m.id
            WHERE m.id = @masterdataId AND (m.archived = 0 OR m.archived IS NULL)
            ORDER BY a.app_date DESC, a.id DESC
            """, new { masterdataId });
        return rows.FirstOrDefault();
    }

    public async Task<(ReportRow? Applicant, List<ReportRow> Applications)> QueryApplicantWithHistoryAsync(int masterdataId)
    {
        await using var conn = await db.OpenAsync();
        var rows = (await conn.QueryAsync<ReportRow>(
            $"""
            SELECT
                m.surname AS Surname, m.firstname AS Firstname, m.midname AS Midname, m.ext AS Ext,
                m.dbirth AS Dbirth, m.gender AS Gender, m.civistat AS Civistat,
                m.address AS Address, m.house_no AS HouseNo, m.street AS Street,
                m.subdivision AS Subdivision, m.barangay AS Barangay,
                m.municipality AS Municipality,
                ISNULL(NULLIF(LTRIM(RTRIM(m.district)),''),
                       (SELECT TOP 1 mu.district FROM municipals mu
                        WHERE mu.municipal = m.municipality)) AS District,
                m.province AS Province,
                m.education AS Education, m.education2 AS Education2, m.school AS School,
                {EligibilityExpr} AS Eligibility,
                m.contact AS Contact, m.contact2 AS Contact2,
                m.experience AS Experience, m.skills AS Skills, m.training AS Training,
                m.lenofservice AS Lenofservice,
                m.personincharge AS Personincharge, m.notes AS Notes,
                a.app_date AS AppDate, a.position AS Position, a.department AS Department,
                a.status AS Status, a.intvw_date AS IntvwDate, a.recommendation AS Recommendation,
                a.hired_date AS HiredDate, a.finalposition AS FinalPosition,
                a.finaldepartment AS FinalDepartment, a.finalstatus AS FinalStatus,
                a.emp_status AS EmpStatus, a.remarks AS Remarks
            FROM masterdata m
            LEFT JOIN applications a ON a.app_id = m.id
            WHERE m.id = @masterdataId AND (m.archived = 0 OR m.archived IS NULL)
            ORDER BY a.app_date DESC, a.id DESC
            """, new { masterdataId })).ToList();
        return (rows.FirstOrDefault(), rows.Where(r => r.AppDate is not null || r.Position is not null).ToList());
    }

    /// <summary>Per-officer, per-year requested vs hired counts — feeds the
    /// old report's year-column matrix, officers alphabetical. The date
    /// window is month-precise (MonthFrom/MonthTo), even though rows are
    /// still grouped by calendar year — a partial year (e.g. Jan–Jul) just
    /// yields lower counts under that year's column, which is the correct
    /// behavior for a narrower period.</summary>
    public async Task<List<OfficerYearRow>> QueryOfficerYearMatrixAsync(RecommendationSummaryRequest req)
    {
        var from = new DateTime(req.YearFrom, req.MonthFrom, 1);
        var to = new DateTime(req.YearTo, req.MonthTo, 1).AddMonths(1);

        var officerFilter = "";
        var args = new DynamicParameters();
        args.Add("from", from);
        args.Add("to", to);
        if (req.Officers is { Count: > 0 })
        {
            // a.recommendation is trimmed at rest (EnsureTrimmedDataAsync) —
            // trimming just the incoming filter values (request input, not
            // guaranteed clean) is enough; the column side stays unwrapped so
            // IX_applications_recommendation can actually be seeked.
            officerFilter = " AND a.recommendation IN @officers";
            args.Add("officers", req.Officers.Select(o => o.Trim()).ToList());
        }

        await using var conn = await db.OpenAsync();
        var rows = await conn.QueryAsync<OfficerYearRow>(
            $"""
            SELECT
                a.recommendation AS Officer,
                YEAR(a.app_date) AS Year,
                COUNT(*) AS Requested,
                SUM(CASE WHEN a.hired_date IS NOT NULL THEN 1 ELSE 0 END) AS Hired
            FROM applications a
            JOIN masterdata m ON a.app_id = m.id
            WHERE (m.archived = 0 OR m.archived IS NULL)
              AND ISNULL(a.recommendation,'') <> ''
              AND a.app_date >= @from AND a.app_date < @to
              {officerFilter}
            GROUP BY a.recommendation, YEAR(a.app_date)
            ORDER BY a.recommendation, YEAR(a.app_date)
            """, args);
        return rows.ToList();
    }
}
