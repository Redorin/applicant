using ApplicantsApi.Data;
using Dapper;
using Microsoft.Extensions.Caching.Memory;

namespace ApplicantsApi.Features.Lookups;

public record ProvinceRow(int Id, string? Province, string? Region);
public record MunicipalRow(int Id, string? Municipal, string? District, int? ProvinceId, string? Province);
public record MunicipalUsageRow(string Municipal, int Uses);
public record SimpleRow(int Id, string? Value);
public record RecommendationRow(int Id, string? Recommending, string? Designation, string? Remarks);

/// <summary>
/// Read endpoints for the seven lookup tables feeding dropdowns.
/// (Full CRUD for the Settings screen lands in a later milestone.)
/// These back largely-static dropdown data, so results are cached; a long
/// TTL is backstop only — <see cref="LookupCacheKeys.Remove"/> is the real
/// invalidation path, called from the batch-save and quick-add endpoints
/// right after a write actually changes one of these tables.
/// </summary>
public static class LookupEndpoints
{
    public static void MapLookups(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/lookups");

        group.MapGet("/provinces", async (Db db, IMemoryCache cache) =>
            Results.Ok(await cache.GetOrCreateAsync(LookupCacheKeys.For("provinces"), async entry =>
            {
                LookupCacheKeys.SetLongTtl(entry);
                await using var conn = await db.OpenAsync();
                return await conn.QueryAsync<ProvinceRow>(
                    "SELECT id AS Id, province AS Province, region AS Region FROM provinces ORDER BY province");
            })));

        group.MapGet("/municipals", async (Db db, IMemoryCache cache) =>
            Results.Ok(await cache.GetOrCreateAsync(LookupCacheKeys.For("municipals"), async entry =>
            {
                LookupCacheKeys.SetLongTtl(entry);
                await using var conn = await db.OpenAsync();
                return await conn.QueryAsync<MunicipalRow>(
                    "SELECT m.id AS Id, m.municipal AS Municipal, m.district AS District, " +
                    "m.province_id AS ProvinceId, p.province AS Province " +
                    "FROM municipals m LEFT JOIN provinces p ON m.province_id = p.id ORDER BY m.municipal");
            })));

        // How often each municipality appears on active applicants — lets the
        // client order the dropdown most-used-first for faster entry. This is
        // a live aggregate over masterdata (not a static table), so it gets a
        // short TTL instead of being wired into every save/import invalidation.
        group.MapGet("/municipals/usage", async (Db db, IMemoryCache cache) =>
            Results.Ok(await cache.GetOrCreateAsync("lookup:municipals-usage", async entry =>
            {
                entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(3);
                await using var conn = await db.OpenAsync();
                // masterdata.municipality is trimmed at write time and
                // backfilled once at startup, so grouping on it directly
                // (no LTRIM/RTRIM) can use the municipality index.
                return await conn.QueryAsync<MunicipalUsageRow>(
                    "SELECT municipality AS Municipal, COUNT(*) AS Uses FROM masterdata" +
                    " WHERE municipality IS NOT NULL AND municipality <> ''" +
                    " AND (archived = 0 OR archived IS NULL)" +
                    " GROUP BY municipality ORDER BY COUNT(*) DESC");
            })));

        group.MapGet("/departments", async (Db db, IMemoryCache cache) =>
            Results.Ok(await cache.GetOrCreateAsync(LookupCacheKeys.For("departments"), async entry =>
            {
                LookupCacheKeys.SetLongTtl(entry);
                await using var conn = await db.OpenAsync();
                return await conn.QueryAsync<SimpleRow>(
                    "SELECT id AS Id, departments AS Value FROM departments " +
                    "WHERE (archived IS NULL OR archived != 'yes') ORDER BY departments");
            })));

        group.MapGet("/education", async (Db db, IMemoryCache cache) =>
            Results.Ok(await cache.GetOrCreateAsync(LookupCacheKeys.For("education"), async entry =>
            {
                LookupCacheKeys.SetLongTtl(entry);
                await using var conn = await db.OpenAsync();
                return await conn.QueryAsync<SimpleRow>(
                    "SELECT id AS Id, education AS Value FROM education " +
                    "WHERE (archived IS NULL OR archived != 'yes') ORDER BY education");
            })));

        group.MapGet("/eligibilities", async (Db db, IMemoryCache cache) =>
            Results.Ok(await cache.GetOrCreateAsync(LookupCacheKeys.For("eligibilities"), async entry =>
            {
                LookupCacheKeys.SetLongTtl(entry);
                await using var conn = await db.OpenAsync();
                return await conn.QueryAsync<SimpleRow>(
                    "SELECT id AS Id, eligibility AS Value FROM eligibilities ORDER BY eligibility");
            })));

        group.MapGet("/recommendation", async (Db db, IMemoryCache cache) =>
            Results.Ok(await cache.GetOrCreateAsync(LookupCacheKeys.For("recommendation"), async entry =>
            {
                LookupCacheKeys.SetLongTtl(entry);
                await using var conn = await db.OpenAsync();
                return await conn.QueryAsync<RecommendationRow>(
                    "SELECT id AS Id, recommending AS Recommending, designation AS Designation, remarks AS Remarks " +
                    "FROM recommendation WHERE (archived IS NULL OR archived != 'yes') ORDER BY recommending");
            })));

        group.MapGet("/staff", async (Db db, IMemoryCache cache) =>
            Results.Ok(await cache.GetOrCreateAsync(LookupCacheKeys.For("staff"), async entry =>
            {
                LookupCacheKeys.SetLongTtl(entry);
                await using var conn = await db.OpenAsync();
                return await conn.QueryAsync<SimpleRow>(
                    "SELECT id AS Id, fullname AS Value FROM staff ORDER BY fullname");
            })));

        // School graduated from — distinct from `education` (which holds the
        // course/degree). "None" is a seeded, selectable option.
        group.MapGet("/schools", async (Db db, IMemoryCache cache) =>
            Results.Ok(await cache.GetOrCreateAsync(LookupCacheKeys.For("schools"), async entry =>
            {
                LookupCacheKeys.SetLongTtl(entry);
                await using var conn = await db.OpenAsync();
                return await conn.QueryAsync<SimpleRow>(
                    "SELECT id AS Id, school AS Value FROM schools " +
                    "ORDER BY CASE WHEN school = 'None' THEN 0 ELSE 1 END, school");
            })));
    }
}

/// <summary>Shared cache-key convention for the static lookup tables, so the
/// batch-save/quick-add endpoints can invalidate exactly what they changed.</summary>
public static class LookupCacheKeys
{
    public static string For(string table) => $"lookup:{table}";

    public static void SetLongTtl(ICacheEntry entry) =>
        entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(30);

    public static void Remove(IMemoryCache cache, string table) => cache.Remove(For(table));
}
