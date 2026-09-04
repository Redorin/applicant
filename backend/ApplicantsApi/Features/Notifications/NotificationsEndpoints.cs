using ApplicantsApi.Common;
using ApplicantsApi.Data;
using Dapper;
using Microsoft.Extensions.Caching.Memory;

namespace ApplicantsApi.Features.Notifications;

public record NotificationsSummary(int StaleCount);
public record StaleRow(int MasterdataId, string Applicant, string Detail);

/// <summary>
/// A lighter, "look at this now" sibling to Data Health: RECENT applications
/// sitting On Process for more than 30 days with no interview and no hire
/// recorded — the ones most likely to have been forgotten. Computed live,
/// same as Data Health, since there's no notification store (or per-user
/// identity) to persist against yet.
///
/// Bounded to the last 6 months on purpose: an On Process row from a decade
/// ago isn't a forgotten task, it's just old data nobody ever closed out —
/// exactly the "47,789" mistake caught in the Data Health badge. A
/// notification bell should surface things to act on today, not the entire
/// backlog of history.
/// </summary>
public static class NotificationsEndpoints
{
    private const string StaleWhere =
        """
        FROM applications a JOIN masterdata m ON a.app_id = m.id
        WHERE (m.archived = 0 OR m.archived IS NULL)
          AND a.status IN @processStatuses
          AND a.app_date IS NOT NULL
          AND a.app_date < DATEADD(day, -30, GETDATE())
          AND a.app_date >= DATEADD(day, -180, GETDATE())
          AND a.intvw_date IS NULL AND a.hired_date IS NULL
        """;

    public static void MapNotifications(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/notifications");

        group.MapGet("/summary", async (Db db, IMemoryCache cache) =>
        {
            var count = await cache.GetOrCreateAsync("notifications-summary", async entry =>
            {
                entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromSeconds(90);
                await using var conn = await db.OpenAsync();
                var processStatuses = await ProcessStatusCache.GetAsync(conn, cache);
                return await conn.ExecuteScalarAsync<int>($"SELECT COUNT(*) {StaleWhere}", new { processStatuses });
            });
            return Results.Ok(new NotificationsSummary(count));
        });

        group.MapGet("/stale", async (Db db, IMemoryCache cache) =>
        {
            var rows = await cache.GetOrCreateAsync("notifications-stale", async entry =>
            {
                entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromSeconds(90);
                await using var conn = await db.OpenAsync();
                var processStatuses = await ProcessStatusCache.GetAsync(conn, cache);
                var result = await conn.QueryAsync<StaleRow>(
                    $"""
                    SELECT TOP 50 m.id AS MasterdataId,
                        LTRIM(RTRIM(ISNULL(m.surname,''))) + ', ' + LTRIM(RTRIM(ISNULL(m.firstname,''))) AS Applicant,
                        'Applied ' + CONVERT(varchar, a.app_date, 107) +
                            ' (' + CAST(DATEDIFF(day, a.app_date, GETDATE()) AS varchar) + ' days ago) — ' +
                            ISNULL(NULLIF(LTRIM(RTRIM(a.position)), ''), 'no position recorded') AS Detail
                    {StaleWhere}
                    ORDER BY a.app_date ASC
                    """, new { processStatuses });
                return result.ToList();
            });
            return Results.Ok(rows);
        });
    }
}
