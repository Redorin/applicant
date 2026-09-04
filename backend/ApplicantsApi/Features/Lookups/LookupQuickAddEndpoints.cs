using ApplicantsApi.Data;
using ApplicantsApi.Features.AuditLog;
using Dapper;
using Microsoft.Extensions.Caching.Memory;

namespace ApplicantsApi.Features.Lookups;

public record QuickAddRequest(string? Value);

/// <summary>
/// Single-value additive inserts for the lookups the record form can extend
/// inline (a school or eligibility that isn't in the list yet). Unlike the
/// batch endpoints these trim, dedupe case-insensitively, and return the id.
/// </summary>
public static class LookupQuickAddEndpoints
{
    public static void MapLookupQuickAdd(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/lookups");

        group.MapPost("/education", (QuickAddRequest req, Db db, AuditLogService audit, IMemoryCache cache) =>
            QuickAdd(db, audit, cache, req.Value, "education", "education"));

        group.MapPost("/eligibilities", (QuickAddRequest req, Db db, AuditLogService audit, IMemoryCache cache) =>
            QuickAdd(db, audit, cache, req.Value, "eligibilities", "eligibility"));
    }

    private static async Task<IResult> QuickAdd(
        Db db, AuditLogService audit, IMemoryCache cache, string? value, string table, string column)
    {
        var v = value?.Trim();
        if (string.IsNullOrEmpty(v))
            return Results.Json(new { errors = new[] { "Value is required." } }, statusCode: 422);

        await using var conn = await db.OpenAsync();

        var existing = await conn.QueryFirstOrDefaultAsync<(int Id, string Value)?>(
            $"SELECT TOP 1 id, {column} FROM {table}" +
            $" WHERE LOWER(LTRIM(RTRIM({column}))) = LOWER(@v)",
            new { v });
        if (existing is { } row)
            return Results.Ok(new { id = row.Id, value = row.Value.Trim(), existed = true });

        var id = await conn.ExecuteScalarAsync<int>(
            $"INSERT INTO {table} ({column}) OUTPUT INSERTED.id VALUES (@v)",
            new { v });
        LookupCacheKeys.Remove(cache, table);
        await audit.LogAsync("lookup", id, "quick_add", $"{table}: {v}");
        return Results.Ok(new { id, value = v, existed = false });
    }
}
