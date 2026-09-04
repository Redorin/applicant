using ApplicantsApi.Common;
using ApplicantsApi.Data;
using Dapper;
using Microsoft.Extensions.Caching.Memory;

namespace ApplicantsApi.Features.Dashboard;

public record MonthCount(DateTime Month, int Count);
public record LabelCount(string Label, int Count);
public record DayCount(DateTime Day, int Count);

public record DashboardSummary(
    int ApplicantsOnFile,
    int ApplicationsThisYear,
    int HiredThisYear,
    int OnProcess,
    List<MonthCount> ApplicationsByMonth,
    List<MonthCount> HiredByMonth,
    List<MonthCount> OnProcessByMonth,
    List<LabelCount> TopMunicipalities,
    List<LabelCount> StatusBreakdown,
    List<DayCount> ApplicationsByDay);

public static class DashboardEndpoints
{
    // Same join + archived filter the old dashboard.cs used for every aggregate.
    private const string Joined =
        " FROM applications a JOIN masterdata m ON a.app_id = m.id" +
        " WHERE (m.archived = 0 OR m.archived IS NULL)";

    // Wide-but-finite bounds for "all time" — SQL Server's datetime floor is
    // 1753-01-01, so true DateTime.MinValue/MaxValue would overflow.
    private static readonly DateTime AllTimeStart = new(1900, 1, 1);
    private static readonly DateTime AllTimeEnd = new(2100, 1, 1);

    private static (DateTime From, DateTime To) PeriodBounds(string? period)
    {
        var today = DateTime.Today;
        return period switch
        {
            "month" => (new DateTime(today.Year, today.Month, 1),
                        new DateTime(today.Year, today.Month, 1).AddMonths(1)),
            "all" => (AllTimeStart, AllTimeEnd),
            _ => (new DateTime(today.Year, 1, 1), new DateTime(today.Year + 1, 1, 1)), // "year" (default)
        };
    }

    public static void MapDashboard(this IEndpointRouteBuilder app)
    {
        app.MapGet("/api/dashboard/summary", async (string? period, Db db, IMemoryCache cache) =>
        {
            var cacheKey = $"dashboard-summary:{period}";
            var summary = await cache.GetOrCreateAsync(cacheKey, async entry =>
            {
                // This is an aggregate/snapshot screen — a minute or two of
                // staleness is an acceptable trade for not re-scanning
                // applications/masterdata on every dashboard view/refresh.
                entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromSeconds(90);

                var (periodFrom, periodTo) = PeriodBounds(period);
                // The 12-month trend charts intentionally stay fixed regardless of
                // the period picker — squeezing a trend into "this month" reads as
                // a bug, not a feature.
                var from12 = new DateTime(DateTime.Today.Year, DateTime.Today.Month, 1).AddMonths(-11);
                var to12 = new DateTime(DateTime.Today.Year, DateTime.Today.Month, 1).AddMonths(1);

                await using var conn = await db.OpenAsync();

                var processStatuses = await ProcessStatusCache.GetAsync(conn, cache);

                // All 9 aggregates in one round trip instead of 9 — this only
                // runs on a cache miss (every 90s per period key at most), but
                // when it does, the request was previously paying for 9
                // sequential network/parse round trips to the same database.
                // periodFrom/periodTo and trendFrom/trendTo are deliberately
                // distinct parameter names even though two of them reuse the
                // same clause shape — a single QueryMultipleAsync call shares
                // one parameter set across every statement in the batch.
                const string monthlyShape =
                    "SELECT DATEADD(month, DATEDIFF(month, 0, a.{0}), 0) AS Month, COUNT(*) AS Count" +
                    Joined +
                    " AND a.{0} >= @trendFrom AND a.{0} < @trendTo{1}" +
                    " GROUP BY DATEADD(month, DATEDIFF(month, 0, a.{0}), 0) ORDER BY Month;";

                var batchSql =
                    "SELECT COUNT(*) FROM masterdata WHERE (archived = 0 OR archived IS NULL);" +
                    "SELECT COUNT(*)" + Joined + " AND a.app_date >= @periodFrom AND a.app_date < @periodTo;" +
                    "SELECT COUNT(*)" + Joined + " AND a.hired_date >= @periodFrom AND a.hired_date < @periodTo;" +
                    "SELECT COUNT(*)" + Joined + " AND a.status IN @processStatuses;" +
                    string.Format(monthlyShape, "app_date", "") +
                    string.Format(monthlyShape, "hired_date", "") +
                    string.Format(monthlyShape, "app_date", " AND a.status IN @processStatuses") +
                    // masterdata.municipality is trimmed at write time and backfilled
                    // once at startup (MaintenanceService), so grouping/filtering on
                    // it directly (no LTRIM/RTRIM) can use the municipality index.
                    "SELECT TOP 8 m.municipality AS Label, COUNT(*) AS Count" + Joined +
                    " AND a.app_date >= @periodFrom AND a.app_date < @periodTo AND ISNULL(m.municipality,'') <> ''" +
                    " GROUP BY m.municipality ORDER BY COUNT(*) DESC;" +
                    // Status breakdown: top 6 named statuses + "Other", as in the old
                    // dashboard. applications.status is backfilled the same way, so
                    // this can group on the raw column too.
                    "SELECT ISNULL(a.status, '') AS Label, COUNT(*) AS Count" + Joined +
                    " GROUP BY ISNULL(a.status, '') ORDER BY COUNT(*) DESC;" +
                    // Daily application counts for the heatmap — last 365 days.
                    "SELECT CAST(a.app_date AS DATE) AS Day, COUNT(*) AS Count" + Joined +
                    " AND a.app_date >= @heatmapFrom AND a.app_date < @heatmapTo" +
                    " GROUP BY CAST(a.app_date AS DATE) ORDER BY Day;";

                using var multi = await conn.QueryMultipleAsync(batchSql, new
                {
                    periodFrom,
                    periodTo,
                    trendFrom = from12,
                    trendTo = to12,
                    heatmapFrom = DateTime.Today.AddDays(-365),
                    heatmapTo = DateTime.Today.AddDays(1),
                    processStatuses,
                });

                var applicantsOnFile = await multi.ReadSingleAsync<int>();
                var applicationsThisYear = await multi.ReadSingleAsync<int>();
                var hiredThisYear = await multi.ReadSingleAsync<int>();
                var onProcess = await multi.ReadSingleAsync<int>();
                var applicationsByMonth = (await multi.ReadAsync<MonthCount>()).ToList();
                var hiredByMonth = (await multi.ReadAsync<MonthCount>()).ToList();
                var onProcessByMonth = (await multi.ReadAsync<MonthCount>()).ToList();
                var topMunicipalities = (await multi.ReadAsync<LabelCount>()).ToList();
                var allStatuses = (await multi.ReadAsync<LabelCount>()).ToList();
                var applicationsByDay = (await multi.ReadAsync<DayCount>()).ToList();

                var statusBreakdown = new List<LabelCount>();
                var other = 0;
                foreach (var row in allStatuses)
                {
                    var label = string.IsNullOrWhiteSpace(row.Label) ? "(blank)" : row.Label;
                    if (statusBreakdown.Count < 6)
                    {
                        statusBreakdown.Add(new LabelCount(label, row.Count));
                    }
                    else
                    {
                        other += row.Count;
                    }
                }
                if (other > 0) statusBreakdown.Add(new LabelCount("Other", other));

                return new DashboardSummary(
                    applicantsOnFile,
                    applicationsThisYear,
                    hiredThisYear,
                    onProcess,
                    applicationsByMonth,
                    hiredByMonth,
                    onProcessByMonth,
                    topMunicipalities,
                    statusBreakdown,
                    applicationsByDay);
            });

            return Results.Ok(summary);
        });
    }
}
