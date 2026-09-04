using Dapper;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Caching.Memory;

namespace ApplicantsApi.Common;

/// <summary>
/// "On process" is a membership check against a small, effectively-fixed
/// vocabulary of status strings (not free text), so `status LIKE '%process%'`
/// — a full-table-scan pattern used by Dashboard and Notifications — can be
/// replaced by `status IN (...)` against the literal values actually in use.
/// Cached briefly since new status spellings are rare and this only feeds
/// "on process" counts/lists, not exact per-row correctness elsewhere.
/// </summary>
public static class ProcessStatusCache
{
    private const string CacheKey = "processStatuses";

    public static async Task<IReadOnlyList<string>> GetAsync(SqlConnection conn, IMemoryCache cache)
    {
        var cached = await cache.GetOrCreateAsync(CacheKey, async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(15);
            var values = await conn.QueryAsync<string>(
                "SELECT DISTINCT status FROM applications WHERE status LIKE '%process%'");
            return values.ToList();
        });
        return cached ?? [];
    }
}
