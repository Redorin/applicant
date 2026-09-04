using ApplicantsApi.Data;
using ApplicantsApi.Features.Auth;
using Dapper;
using Microsoft.AspNetCore.Http;
using Microsoft.Data.SqlClient;

namespace ApplicantsApi.Features.AuditLog;

public record AuditEntry(
    int Id, string EntityType, int EntityId, string Action,
    string? Detail, DateTime ChangedAt, string? ChangedBy);

/// <summary>Same shape as <see cref="AuditEntry"/> plus the window-computed
/// grand total — lets the paged query and the count share one round trip.</summary>
internal record AuditEntryPaged(
    int Id, string EntityType, int EntityId, string Action,
    string? Detail, DateTime ChangedAt, string? ChangedBy, int TotalCount);

/// <summary>
/// Who changed what, when — now backed by real per-user accounts: ChangedBy
/// is resolved from the current request's session token, so it reflects the
/// individual logged-in user rather than a shared office identity.
/// </summary>
public sealed class AuditLogService(Db db, IHttpContextAccessor httpContextAccessor, SessionStore sessions)
{
    private string? _cachedUsers;
    private DateTime _cachedUsersAt;
    private static readonly TimeSpan CacheTtl = TimeSpan.FromMinutes(5);
    private string? ChangedBy
    {
        get
        {
            var ctx = httpContextAccessor.HttpContext;
            if (ctx != null && ctx.Request.Headers.TryGetValue("X-Session-Token", out var token))
            {
                return sessions.UsernameFor(token.ToString());
            }
            return null;
        }
    }

    /// <summary>For writes that already hold an open transaction (e.g. the
    /// master data save) — the audit row lives or dies with that transaction.</summary>
    public Task LogInTransactionAsync(
        SqlConnection conn, SqlTransaction tx, string entityType, int entityId,
        string action, string? detail = null)
    {
        _cachedUsers = null; // new user may have been added
        return conn.ExecuteAsync(
            """
            INSERT INTO audit_log (entity_type, entity_id, action, detail, changed_at, changed_by)
            VALUES (@entityType, @entityId, @action, @detail, GETDATE(), @changedBy)
            """,
            new { entityType, entityId, action, detail, changedBy = ChangedBy }, tx);
    }

    /// <summary>Same as <see cref="LogInTransactionAsync"/>, but for many
    /// entities sharing the same action/detail (e.g. a bulk status update) —
    /// one multi-row INSERT instead of one round trip per entity.</summary>
    public Task LogManyInTransactionAsync(
        SqlConnection conn, SqlTransaction tx, string entityType, IReadOnlyList<int> entityIds,
        string action, string? detail = null)
    {
        if (entityIds.Count == 0) return Task.CompletedTask;

        _cachedUsers = null; // new user may have been added

        var parameters = new DynamicParameters();
        parameters.Add("entityType", entityType);
        parameters.Add("action", action);
        parameters.Add("detail", detail);
        parameters.Add("changedBy", ChangedBy);
        var valueRows = new List<string>();
        for (var i = 0; i < entityIds.Count; i++)
        {
            valueRows.Add($"(@entityType, @entityId{i}, @action, @detail, GETDATE(), @changedBy)");
            parameters.Add($"entityId{i}", entityIds[i]);
        }
        return conn.ExecuteAsync(
            $"INSERT INTO audit_log (entity_type, entity_id, action, detail, changed_at, changed_by) VALUES {string.Join(",", valueRows)}",
            parameters, tx);
    }

    /// <summary>For writes with no transaction of their own (archive/restore,
    /// bulk-status) — a standalone insert on its own connection.
    /// When <paramref name="overrideChangedBy"/> is provided it is used
    /// instead of the automatic session-token resolution (needed for
    /// login/logout where the token is being created or revoked).</summary>
    public async Task LogAsync(string entityType, int entityId, string action,
        string? detail = null, string? overrideChangedBy = null)
    {
        _cachedUsers = null; // new user may have been added
        await using var conn = await db.OpenAsync();
        await conn.ExecuteAsync(
            """
            INSERT INTO audit_log (entity_type, entity_id, action, detail, changed_at, changed_by)
            VALUES (@entityType, @entityId, @action, @detail, GETDATE(), @changedBy)
            """,
            new { entityType, entityId, action, detail, changedBy = overrideChangedBy ?? ChangedBy });
    }

    /// <summary>Real entityType/action pairs behind each Activity Logs
    /// "Action" dropdown bucket — kept in one place so the dropdown, once
    /// picked, always maps to the same real rows regardless of which
    /// screen/version of the frontend is asking.</summary>
    private static readonly Dictionary<string, (string EntityType, string Action)[]> Buckets = new(StringComparer.OrdinalIgnoreCase)
    {
        ["statusChange"] = [("application", "bulk-status")],
        ["applicantAdded"] = [("masterdata", "insert")],
        ["applicantEdited"] = [("masterdata", "update")],
        ["hired"] = [("application", "hire")],
        ["reportGenerated"] = [("report", "generate"), ("report", "save_copy")],
        ["login"] = [("auth", "login")],
    };

    /// <summary>Builds the WHERE fragment for a bucket value — a named bucket
    /// matches its own pairs; "other" matches everything NOT in any named
    /// bucket, so a future action string always lands somewhere instead of
    /// silently vanishing from every filter option.</summary>
    private static string? BucketCondition(string? bucket, DynamicParameters parameters)
    {
        if (string.IsNullOrWhiteSpace(bucket)) return null;

        var isOther = bucket.Equals("other", StringComparison.OrdinalIgnoreCase);
        if (!isOther && !Buckets.TryGetValue(bucket, out _)) return null;

        var pairs = isOther ? Buckets.Values.SelectMany(p => p).ToArray() : Buckets[bucket];
        var clauses = new List<string>();
        for (var i = 0; i < pairs.Length; i++)
        {
            clauses.Add($"(entity_type = @bucketType{i} AND action = @bucketAction{i})");
            parameters.Add($"bucketType{i}", pairs[i].EntityType);
            parameters.Add($"bucketAction{i}", pairs[i].Action);
        }
        var combined = "(" + string.Join(" OR ", clauses) + ")";
        return isOther ? $"NOT {combined}" : combined;
    }

    /// <summary>Paged, newest-first — the Logs screen scrolls back through
    /// the whole history, not just the most recent handful.</summary>
    public async Task<(int Total, List<AuditEntry> Rows)> QueryAsync(
        string? entityType, int? entityId, string? action, string? search,
        string? changedBy, string? bucket, int offset, int limit)
    {
        await using var conn = await db.OpenAsync();

        var conditions = new List<string>
        {
            "(@entityType IS NULL OR entity_type = @entityType)",
            "(@entityId IS NULL OR entity_id = @entityId)",
            "(@action IS NULL OR action = @action)",
            "(@changedBy IS NULL OR changed_by = @changedBy)",
        };
        var parameters = new DynamicParameters();
        parameters.Add("entityType", entityType);
        parameters.Add("entityId", entityId);
        parameters.Add("action", action);
        parameters.Add("changedBy", changedBy);
        parameters.Add("offset", offset);
        parameters.Add("limit", limit);

        var searchTrim = string.IsNullOrWhiteSpace(search) ? null : search.Trim();
        if (searchTrim != null)
        {
            conditions.Add("(detail LIKE @searchLike OR changed_by LIKE @searchLike)");
            parameters.Add("searchLike", $"%{searchTrim}%");
        }

        var bucketSql = BucketCondition(bucket, parameters);
        if (bucketSql != null) conditions.Add(bucketSql);

        var where = string.Join("\n  AND ", conditions);

        // One round trip instead of two: COUNT(*) OVER() rides along with the
        // page itself (computed over the full WHERE-matched set regardless of
        // the OFFSET/FETCH below), same pattern already used by /api/browse.
        var paged = (await conn.QueryAsync<AuditEntryPaged>(
            $"""
            SELECT id AS Id, entity_type AS EntityType, entity_id AS EntityId,
                   action AS Action, detail AS Detail, changed_at AS ChangedAt, changed_by AS ChangedBy,
                   COUNT(*) OVER() AS TotalCount
            FROM audit_log
            WHERE {where}
            ORDER BY changed_at DESC, id DESC
            OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY
            """, parameters)).ToList();

        var total = paged.Count > 0 ? paged[0].TotalCount : 0;
        var rows = paged.Select(p => new AuditEntry(
            p.Id, p.EntityType, p.EntityId, p.Action, p.Detail, p.ChangedAt, p.ChangedBy));
        return (total, rows.ToList());
    }

    /// <summary>Distinct usernames that have actually logged activity — backs
    /// the Logs screen's "User" filter dropdown without hardcoding accounts
    /// that could change. Cached in-memory for 5 minutes since the user set
    /// is small and changes rarely.</summary>
    public async Task<List<string>> DistinctUsersAsync()
    {
        if (_cachedUsers != null && DateTime.UtcNow - _cachedUsersAt < CacheTtl)
            return _cachedUsers.Split('\n').ToList();

        await using var conn = await db.OpenAsync();
        var rows = await conn.QueryAsync<string>(
            "SELECT DISTINCT changed_by FROM audit_log WHERE changed_by IS NOT NULL ORDER BY changed_by");
        var list = rows.ToList();
        _cachedUsers = string.Join('\n', list);
        _cachedUsersAt = DateTime.UtcNow;
        return list;
    }
}

public record RecordLogRequest(string EntityType, int? EntityId, string Action, string? Detail);

public static class AuditLogEndpoints
{
    public static void MapAuditLog(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/audit-log");

        group.MapGet("/", async (
            string? entityType, int? entityId, string? action, string? search,
            string? changedBy, string? bucket, int? offset, int? limit, AuditLogService svc) =>
        {
            var (total, rows) = await svc.QueryAsync(
                entityType, entityId, action, search, changedBy, bucket,
                Math.Max(offset ?? 0, 0), Math.Clamp(limit ?? 50, 1, 200));
            return Results.Ok(new { total, rows });
        });

        // Backs the Logs screen's "User" filter dropdown.
        group.MapGet("/users", async (AuditLogService svc) =>
            Results.Ok(await svc.DistinctUsersAsync()));

        // For client-only events the backend has no other way to observe —
        // an Excel export or a "save a copy" of a PDF preview never touches
        // any other endpoint, so the app reports those directly.
        group.MapPost("/", async (RecordLogRequest req, AuditLogService svc) =>
        {
            if (string.IsNullOrWhiteSpace(req.EntityType) || string.IsNullOrWhiteSpace(req.Action))
            {
                return Results.Json(new { error = "entityType and action are required." }, statusCode: 422);
            }
            await svc.LogAsync(req.EntityType, req.EntityId ?? 0, req.Action, req.Detail);
            return Results.NoContent();
        });
    }
}
