using ApplicantsApi.Data;
using ApplicantsApi.Features.AuditLog;
using Dapper;
using Microsoft.Data.SqlClient;

namespace ApplicantsApi.Features.Maintenance;

public record StatusVariant(string Status, int InStatus, int InFinalStatus);
public record MergeStatusRequest(string From, string To);

/// <summary>
/// Status standardization: list every distinct status spelling with usage
/// counts, and merge one spelling into another across both status columns.
/// </summary>
public static class StatusEndpoints
{
    public static void MapStatusTools(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/statuses");

        // Distinct spellings across applications.status and finalstatus.
        group.MapGet("/", async (Db db) =>
        {
            await using var conn = await db.OpenAsync();
            var rows = await conn.QueryAsync<StatusVariant>(
                """
                SELECT s.Status,
                       SUM(s.InStatus) AS InStatus,
                       SUM(s.InFinalStatus) AS InFinalStatus
                FROM (
                    SELECT LTRIM(RTRIM(status)) AS Status, 1 AS InStatus, 0 AS InFinalStatus
                    FROM applications WHERE LTRIM(RTRIM(ISNULL(status,''))) <> ''
                    UNION ALL
                    SELECT LTRIM(RTRIM(finalstatus)), 0, 1
                    FROM applications WHERE LTRIM(RTRIM(ISNULL(finalstatus,''))) <> ''
                ) s
                GROUP BY s.Status
                ORDER BY SUM(s.InStatus) + SUM(s.InFinalStatus) DESC
                """);
            return Results.Ok(rows);
        });

        // Merge every occurrence of one spelling into another (both columns),
        // in one transaction. A daily backup is ensured first.
        group.MapPost("/merge", async (
            MergeStatusRequest req, Db db, MaintenanceService maintenance, AuditLogService audit) =>
        {
            var from = req.From?.Trim();
            var to = req.To?.Trim();
            if (string.IsNullOrWhiteSpace(from) || string.IsNullOrWhiteSpace(to))
            {
                return Results.Json(new { error = "Both spellings are required." }, statusCode: 422);
            }
            if (string.Equals(from, to, StringComparison.Ordinal))
            {
                return Results.Json(new { error = "The two spellings are identical." }, statusCode: 422);
            }

            try
            {
                await maintenance.BackupIfDueAsync();
            }
            catch
            {
                // A failed safety backup shouldn't block the merge outright,
                // but it is logged by the middleware if it throws later.
            }

            await using var conn = await db.OpenAsync();
            await using var tx = (SqlTransaction)await conn.BeginTransactionAsync();

            var inStatus = await conn.ExecuteAsync(
                "UPDATE applications SET status = @to WHERE LTRIM(RTRIM(ISNULL(status,''))) = @from",
                new { from, to }, tx);
            var inFinal = await conn.ExecuteAsync(
                "UPDATE applications SET finalstatus = @to WHERE LTRIM(RTRIM(ISNULL(finalstatus,''))) = @from",
                new { from, to }, tx);

            await tx.CommitAsync();
            await audit.LogAsync("status", 0, "merge",
                $"\"{from}\" → \"{to}\" ({inStatus + inFinal} rows)");
            return Results.Ok(new { updatedStatus = inStatus, updatedFinalStatus = inFinal });
        });
    }
}
