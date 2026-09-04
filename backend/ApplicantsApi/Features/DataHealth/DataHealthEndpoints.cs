using ApplicantsApi.Data;
using Dapper;
using Microsoft.Extensions.Caching.Memory;

namespace ApplicantsApi.Features.DataHealth;

public record HealthCategory(string Key, string Title, string Description, int Count);
public record HealthRow(int MasterdataId, string Applicant, string Detail);

/// <summary>
/// Surfaces data anomalies found in the live database as a fix-it worklist:
/// future-dated applications, blank statuses, malformed contact numbers,
/// missing address parts, and legacy eligibilities never migrated to chips.
/// </summary>
public static class DataHealthEndpoints
{
    private const string NotArchived = "(m.archived = 0 OR m.archived IS NULL)";

    // Each category: (title, description, count SQL, rows SQL).
    // Row queries return MasterdataId, Applicant, Detail.
    private static readonly Dictionary<string, (string Title, string Description, string CountSql, string RowsSql)> Categories = new()
    {
        ["future-dates"] = (
            "Future-dated applications",
            "Application, interview, or hiring dates after today — almost always a typo in the year.",
            $"""
            SELECT COUNT(*) FROM applications a JOIN masterdata m ON a.app_id = m.id
            WHERE {NotArchived} AND (a.app_date > GETDATE() OR a.hired_date > GETDATE() OR a.intvw_date > GETDATE())
            """,
            $"""
            SELECT TOP 200 m.id AS MasterdataId,
                LTRIM(RTRIM(ISNULL(m.surname,''))) + ', ' + LTRIM(RTRIM(ISNULL(m.firstname,''))) AS Applicant,
                'Applied ' + CONVERT(varchar, a.app_date, 107) +
                    ISNULL(' · hired ' + CONVERT(varchar, a.hired_date, 107), '') AS Detail
            FROM applications a JOIN masterdata m ON a.app_id = m.id
            WHERE {NotArchived} AND (a.app_date > GETDATE() OR a.hired_date > GETDATE() OR a.intvw_date > GETDATE())
            ORDER BY a.app_date DESC
            """),

        ["blank-status"] = (
            "Applications with no status",
            "Blank status text — these rows show as \"(blank)\" on the dashboard and reports.",
            $"""
            SELECT COUNT(*) FROM applications a JOIN masterdata m ON a.app_id = m.id
            WHERE {NotArchived} AND LTRIM(RTRIM(ISNULL(a.status,''))) = ''
            """,
            $"""
            SELECT TOP 200 m.id AS MasterdataId,
                LTRIM(RTRIM(ISNULL(m.surname,''))) + ', ' + LTRIM(RTRIM(ISNULL(m.firstname,''))) AS Applicant,
                ISNULL('Applied ' + CONVERT(varchar, a.app_date, 107), 'No application date') +
                    ISNULL(' for ' + NULLIF(LTRIM(RTRIM(a.position)),''), '') AS Detail
            FROM applications a JOIN masterdata m ON a.app_id = m.id
            WHERE {NotArchived} AND LTRIM(RTRIM(ISNULL(a.status,''))) = ''
            ORDER BY a.app_date DESC
            """),

        ["invalid-contacts"] = (
            "Malformed contact numbers",
            "Contact numbers not in the 09XX XXX XXXX format — these block saving the record until fixed.",
            $"""
            SELECT COUNT(*) FROM masterdata m
            WHERE {NotArchived} AND LTRIM(RTRIM(ISNULL(m.contact,''))) <> ''
              AND m.contact NOT LIKE '09[0-9][0-9] [0-9][0-9][0-9] [0-9][0-9][0-9][0-9]'
            """,
            $"""
            SELECT TOP 200 m.id AS MasterdataId,
                LTRIM(RTRIM(ISNULL(m.surname,''))) + ', ' + LTRIM(RTRIM(ISNULL(m.firstname,''))) AS Applicant,
                'Contact: ' + m.contact AS Detail
            FROM masterdata m
            WHERE {NotArchived} AND LTRIM(RTRIM(ISNULL(m.contact,''))) <> ''
              AND m.contact NOT LIKE '09[0-9][0-9] [0-9][0-9][0-9] [0-9][0-9][0-9][0-9]'
            ORDER BY m.surname, m.firstname
            """),

        ["missing-municipality"] = (
            "No municipality on record",
            "Records without a municipality — they never appear in municipality filters or the dashboard chart.",
            $"""
            SELECT COUNT(*) FROM masterdata m
            WHERE {NotArchived} AND LTRIM(RTRIM(ISNULL(m.municipality,''))) = ''
            """,
            $"""
            SELECT TOP 200 m.id AS MasterdataId,
                LTRIM(RTRIM(ISNULL(m.surname,''))) + ', ' + LTRIM(RTRIM(ISNULL(m.firstname,''))) AS Applicant,
                ISNULL('Address: ' + NULLIF(LTRIM(RTRIM(m.address)),''), 'No address at all') AS Detail
            FROM masterdata m
            WHERE {NotArchived} AND LTRIM(RTRIM(ISNULL(m.municipality,''))) = ''
            ORDER BY m.surname, m.firstname
            """),

        ["legacy-eligibility"] = (
            "Eligibilities not yet migrated",
            "Records still using the old single-text eligibility instead of the chips list — they display, but editing benefits from migrating.",
            $"""
            SELECT COUNT(*) FROM masterdata m
            WHERE {NotArchived} AND LTRIM(RTRIM(ISNULL(m.eligibility,''))) <> ''
              AND NOT EXISTS (SELECT 1 FROM masterdata_eligibilities e WHERE e.masterdata_id = m.id)
            """,
            $"""
            SELECT TOP 200 m.id AS MasterdataId,
                LTRIM(RTRIM(ISNULL(m.surname,''))) + ', ' + LTRIM(RTRIM(ISNULL(m.firstname,''))) AS Applicant,
                'Legacy: ' + m.eligibility AS Detail
            FROM masterdata m
            WHERE {NotArchived} AND LTRIM(RTRIM(ISNULL(m.eligibility,''))) <> ''
              AND NOT EXISTS (SELECT 1 FROM masterdata_eligibilities e WHERE e.masterdata_id = m.id)
            ORDER BY m.surname, m.firstname
            """),
    };

    public static void MapDataHealth(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/datahealth");

        group.MapGet("/summary", async (Db db, IMemoryCache cache) =>
        {
            // This is a worklist, not a live counter — a few minutes of
            // staleness is fine and avoids re-running 5 full scans on every
            // Data Health screen visit.
            var result = await cache.GetOrCreateAsync("datahealth-summary", async entry =>
            {
                entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(3);
                await using var conn = await db.OpenAsync();
                // One round trip for all 5 category counts instead of 5 —
                // order of `keys` and the read order below must match the
                // order the count statements were concatenated in.
                var keys = Categories.Keys.ToList();
                var batchSql = string.Join(" ", keys.Select(k => Categories[k].CountSql + ";"));
                using var multi = await conn.QueryMultipleAsync(batchSql);
                var list = new List<HealthCategory>();
                foreach (var key in keys)
                {
                    var cat = Categories[key];
                    var count = await multi.ReadSingleAsync<int>();
                    list.Add(new HealthCategory(key, cat.Title, cat.Description, count));
                }
                return list;
            });
            return Results.Ok(result);
        });

        group.MapGet("/{category}", async (string category, Db db, IMemoryCache cache) =>
        {
            if (!Categories.TryGetValue(category, out var cat))
            {
                return Results.NotFound();
            }
            var rows = await cache.GetOrCreateAsync($"datahealth-rows:{category}", async entry =>
            {
                entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(3);
                await using var conn = await db.OpenAsync();
                var result = await conn.QueryAsync<HealthRow>(cat.RowsSql);
                return result.ToList();
            });
            return Results.Ok(rows);
        });
    }
}
