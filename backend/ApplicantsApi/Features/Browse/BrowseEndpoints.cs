using ApplicantsApi.Data;
using ApplicantsApi.Features.AuditLog;
using Dapper;
using Microsoft.Data.SqlClient;

namespace ApplicantsApi.Features.Browse;

/// <summary>One application-level row in the browse grids (List / Hired).</summary>
public record BrowseRow(
    int Id,
    int MasterdataId,
    string? Applicant,
    string? Municipality,
    string? Position,
    string? Department,
    DateTime? AppDate,
    string? Status,
    DateTime? HiredDate,
    string? FinalPosition,
    string? FinalDepartment,
    string? Recommendation,
    string? Course);

/// <summary>Same shape as <see cref="BrowseRow"/> plus the window-computed
/// grand total — lets the paged query and the count share one scan instead
/// of two (see MapGet("/") below).</summary>
internal record BrowseRowPaged(
    int Id,
    int MasterdataId,
    string? Applicant,
    string? Municipality,
    string? Position,
    string? Department,
    DateTime? AppDate,
    string? Status,
    DateTime? HiredDate,
    string? FinalPosition,
    string? FinalDepartment,
    string? Recommendation,
    string? Course,
    int TotalCount);

public record BulkStatusRequest(List<int> ApplicationIds, string Status);

public record HireRequest(string? FinalPosition, string? FinalDepartment, DateTime DateHired);

public record UnhireRequest(string? Status);

public static class BrowseEndpoints
{
    // Allow-listed sort columns — sortBy is only ever used as a dictionary
    // key, never concatenated into SQL, so this can't be used to inject.
    // masterdata.surname/firstname/municipality are trimmed at write time
    // (MasterDataService.SaveAsync) and backfilled once at startup
    // (MaintenanceService.EnsureSchemaAsync), so these no longer need
    // LTRIM(RTRIM()) — leaving it on meant SQL Server couldn't use any index
    // on these columns for sorting/filtering.
    private static readonly Dictionary<string, string> SortColumns = new(StringComparer.OrdinalIgnoreCase)
    {
        ["appDate"] = "a.app_date",
        ["surname"] = "ISNULL(m.surname,'')",
        ["municipality"] = "ISNULL(m.municipality,'')",
        ["status"] = "a.status",
    };

    private const string DefaultOrder =
        "a.app_date DESC, ISNULL(m.surname,'') ASC, ISNULL(m.firstname,'') ASC";

    public static void MapBrowse(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/browse");

        // Application-level rows, paginated: newest application date first,
        // alphabetical by applicant within the same date (or by sortBy/sortDir
        // when given — unrecognized/absent sortBy keeps that default exactly).
        group.MapGet("/", async (
            bool? hiredOnly, string? name, string? status, string? municipality,
            string? office, string? course, string? eligibility,
            string? recommendation,
            DateTime? dateFrom, DateTime? dateTo, int? offset, int? pageSize,
            string? sortBy, string? sortDir, Db db) =>
        {
            // Built up rather than a fixed "(@x IS NULL OR col = @x)" string
            // for every filter: that catch-all shape makes SQL Server cache
            // one query plan shared by every filter combination, which tends
            // to fall back to scanning applications/masterdata even when a
            // single selective, indexed filter (e.g. municipality) is the
            // only one set. Only appending the predicates actually supplied
            // means the query text — and so the cached plan — matches the
            // real filter combination each time.
            var conditions = new List<string>
            {
                "(m.archived = 0 OR m.archived IS NULL)",
                "((@hiredOnly = 1 AND a.hired_date IS NOT NULL) OR (@hiredOnly = 0 AND a.hired_date IS NULL))",
            };
            var parameters = new DynamicParameters();
            parameters.Add("hiredOnly", (hiredOnly ?? false) ? 1 : 0);

            var nameTrim = string.IsNullOrWhiteSpace(name) ? null : name.Trim();
            if (nameTrim != null)
            {
                conditions.Add("(m.surname + ', ' + m.firstname + ' ' + ISNULL(m.midname,'')) LIKE @nameLike");
                parameters.Add("nameLike", $"%{nameTrim}%");
            }

            var statusTrim = string.IsNullOrWhiteSpace(status) ? null : status.Trim();
            if (statusTrim != null)
            {
                conditions.Add("a.status LIKE @statusLike");
                parameters.Add("statusLike", $"%{statusTrim}%");
            }

            var municipalityTrim = string.IsNullOrWhiteSpace(municipality) ? null : municipality.Trim();
            if (municipalityTrim != null)
            {
                conditions.Add("m.municipality = @municipality");
                parameters.Add("municipality", municipalityTrim);
            }

            var officeTrim = string.IsNullOrWhiteSpace(office) ? null : office.Trim();
            if (officeTrim != null)
            {
                conditions.Add("a.department = @office");
                parameters.Add("office", officeTrim);
            }

            var courseTrim = string.IsNullOrWhiteSpace(course) ? null : course.Trim();
            if (courseTrim != null)
            {
                conditions.Add("m.education = @course");
                parameters.Add("course", courseTrim);
            }

            var eligibilityTrim = string.IsNullOrWhiteSpace(eligibility) ? null : eligibility.Trim();
            if (eligibilityTrim != null)
            {
                conditions.Add(
                    """
                    EXISTS (SELECT 1 FROM masterdata_eligibilities me
                            WHERE me.masterdata_id = m.id AND me.eligibility = @eligibility)
                    """);
                parameters.Add("eligibility", eligibilityTrim);
            }

            var recommendationTrim = string.IsNullOrWhiteSpace(recommendation) ? null : recommendation.Trim();
            if (recommendationTrim != null)
            {
                conditions.Add("a.recommendation = @recommendation");
                parameters.Add("recommendation", recommendationTrim);
            }

            if (dateFrom != null)
            {
                conditions.Add("a.app_date >= @dateFrom");
                parameters.Add("dateFrom", dateFrom);
            }

            var dateToExclusive = dateTo?.Date.AddDays(1);
            if (dateToExclusive != null)
            {
                conditions.Add("a.app_date < @dateToExclusive");
                parameters.Add("dateToExclusive", dateToExclusive);
            }

            var offsetVal = Math.Max(offset ?? 0, 0);
            var pageSizeVal = Math.Clamp(pageSize ?? 100, 1, 10000);
            parameters.Add("offset", offsetVal);
            parameters.Add("pageSize", pageSizeVal);

            var fromWhere =
                $"""
                FROM applications a
                JOIN masterdata m ON a.app_id = m.id
                WHERE {string.Join("\n  AND ", conditions)}
                """;

            await using var conn = await db.OpenAsync();

            var orderBy = DefaultOrder;
            if (sortBy != null && SortColumns.TryGetValue(sortBy, out var sortColumn))
            {
                var dir = string.Equals(sortDir, "asc", StringComparison.OrdinalIgnoreCase) ? "ASC" : "DESC";
                orderBy = $"{sortColumn} {dir}, {DefaultOrder}";
            }

            // ROW_NUMBER pagination — works regardless of the database's
            // compatibility level (OFFSET/FETCH needs 110+, this DB predates it).
            // COUNT(*) OVER() rides along in the same pass so the grand total
            // and the page come from one scan instead of two (previously a
            // separate SELECT COUNT(*) evaluated the same WHERE a second time).
            // Edge case: if @offset lands past the end of a result set that
            // changed out from under this request (a filter changed mid-flight),
            // this returns zero rows and thus TotalCount 0 rather than the true
            // total — acceptable since the frontend always resets to offset 0
            // on every filter change.
            var paged = (await conn.QueryAsync<BrowseRowPaged>(
                $"""
                SELECT Id, MasterdataId, Applicant, Municipality, Position, Department,
                       AppDate, Status, HiredDate, FinalPosition, FinalDepartment, Recommendation, Course, TotalCount
                FROM (
                    SELECT
                        a.id AS Id,
                        m.id AS MasterdataId,
                        ISNULL(m.surname,'') + ', ' + ISNULL(m.firstname,'') AS Applicant,
                        m.municipality AS Municipality,
                        a.position AS Position,
                        a.department AS Department,
                        a.app_date AS AppDate,
                        a.status AS Status,
                        a.hired_date AS HiredDate,
                        a.finalposition AS FinalPosition,
                        a.finaldepartment AS FinalDepartment,
                        a.recommendation AS Recommendation,
                        m.education AS Course,
                        ROW_NUMBER() OVER (ORDER BY {orderBy}) AS rn,
                        COUNT(*) OVER() AS TotalCount
                    {fromWhere}
                ) paged
                WHERE rn > @offset AND rn <= @offset + @pageSize
                ORDER BY rn
                """, parameters)).ToList();

            var total = paged.Count > 0 ? paged[0].TotalCount : 0;
            var rows = paged.Select(p => new BrowseRow(
                p.Id, p.MasterdataId, p.Applicant, p.Municipality, p.Position, p.Department,
                p.AppDate, p.Status, p.HiredDate, p.FinalPosition, p.FinalDepartment, p.Recommendation, p.Course));

            return Results.Ok(new { total, rows });
        });

        // Apply one status to many applications at once — e.g. after a mass
        // interview day, or a Reject action from the Browse grid. Scoped to
        // non-archived masterdata as a defensive guard.
        group.MapPost("/bulk-status", async (BulkStatusRequest req, Db db, AuditLogService audit) =>
        {
            var ids = (req.ApplicationIds ?? []).Distinct().ToList();
            var status = req.Status?.Trim() ?? "";
            var errors = new List<string>();
            if (ids.Count == 0) errors.Add("At least one application id is required.");
            if (ids.Count > 500) errors.Add("Cannot update more than 500 applications at once.");
            if (status.Length == 0) errors.Add("Status is required.");
            if (status.Length > 100) errors.Add("Status is too long.");
            if (errors.Count > 0) return Results.UnprocessableEntity(new { errors });

            await using var conn = await db.OpenAsync();
            await using var tx = (SqlTransaction)await conn.BeginTransactionAsync();
            try
            {
                // Resolve which ids are actually eligible (non-archived) first,
                // so the audit trail only records rows that really changed.
                var eligibleIds = (await conn.QueryAsync<int>(
                    """
                    SELECT a.id FROM applications a JOIN masterdata m ON a.app_id = m.id
                    WHERE a.id IN @ids AND (m.archived = 0 OR m.archived IS NULL)
                    """, new { ids }, tx)).ToList();

                var updated = 0;
                if (eligibleIds.Count > 0)
                {
                    updated = await conn.ExecuteAsync(
                        "UPDATE applications SET status = @status WHERE id IN @eligibleIds",
                        new { status, eligibleIds }, tx);
                    await audit.LogManyInTransactionAsync(conn, tx, "application", eligibleIds,
                        "bulk-status", $"status -> {status}");
                }
                await tx.CommitAsync();
                return Results.Ok(new { updated });
            }
            catch
            {
                await tx.RollbackAsync();
                throw;
            }
        });

        // Distinct municipality values actually present in the data (legacy
        // rows may hold names missing from the municipals lookup).
        group.MapGet("/municipalities", async (Db db) =>
        {
            await using var conn = await db.OpenAsync();
            // No LTRIM(RTRIM()) here — masterdata.municipality is trimmed at
            // write time and backfilled at startup (see the SortColumns
            // comment above), so wrapping it would defeat IX_masterdata_municipality.
            var rows = await conn.QueryAsync<string>(
                """
                SELECT DISTINCT municipality
                FROM masterdata
                WHERE (archived = 0 OR archived IS NULL)
                  AND ISNULL(municipality,'') <> ''
                ORDER BY 1
                """);
            return Results.Ok(rows);
        });

        // Hire / unhire — the List and Hired grids are a strict partition on
        // hired_date, so these two actions are the only way a row moves
        // between them. dateHired is always the value the user typed in the
        // prompt dialog, never server time.
        var applications = app.MapGroup("/api/applications");

        applications.MapPost("/{id:int}/hire", async (int id, HireRequest req, Db db, AuditLogService audit) =>
        {
            var finalPosition = req.FinalPosition?.Trim();
            if (string.IsNullOrWhiteSpace(finalPosition))
            {
                return Results.Json(new { errors = new[] { "Final position is required." } }, statusCode: 422);
            }

            await using var conn = await db.OpenAsync();
            var updated = await conn.ExecuteAsync(
                """
                UPDATE applications
                SET hired_date = @dateHired, finalposition = @finalPosition, finaldepartment = @finalDepartment
                WHERE id = @id
                """,
                new
                {
                    id,
                    dateHired = req.DateHired.Date,
                    finalPosition,
                    finalDepartment = string.IsNullOrWhiteSpace(req.FinalDepartment) ? null : req.FinalDepartment.Trim(),
                });
            if (updated == 0) return Results.NotFound();

            await audit.LogAsync("application", id, "hire",
                $"Final position: {finalPosition}; Date hired: {req.DateHired:yyyy-MM-dd}");
            return Results.NoContent();
        });

        applications.MapPost("/{id:int}/unhire", async (int id, UnhireRequest req, Db db, AuditLogService audit) =>
        {
            await using var conn = await db.OpenAsync();
            var updated = await conn.ExecuteAsync(
                """
                UPDATE applications
                SET hired_date = NULL, finalposition = NULL, finaldepartment = NULL,
                    finalstatus = NULL, emp_status = NULL, assumption = NULL
                    {0}
                WHERE id = @id
                """,
                new { id, statusClause = !string.IsNullOrWhiteSpace(req.Status)
                    ? $", status = @status" : "" },
                commandTimeout: 15);
            // Re-run with status if provided
            if (!string.IsNullOrWhiteSpace(req.Status))
            {
                updated = await conn.ExecuteAsync(
                    """
                    UPDATE applications
                    SET hired_date = NULL, finalposition = NULL, finaldepartment = NULL,
                        finalstatus = NULL, emp_status = NULL, assumption = NULL,
                        status = @status
                    WHERE id = @id
                    """, new { id, status = req.Status });
            }
            else
            {
                updated = await conn.ExecuteAsync(
                    """
                    UPDATE applications
                    SET hired_date = NULL, finalposition = NULL, finaldepartment = NULL,
                        finalstatus = NULL, emp_status = NULL, assumption = NULL
                    WHERE id = @id
                    """, new { id });
            }
            if (updated == 0) return Results.NotFound();

            await audit.LogAsync("application", id, "unhire",
                detail: !string.IsNullOrWhiteSpace(req.Status) ? $"Status -> {req.Status}" : null);
            return Results.NoContent();
        });
    }
}
