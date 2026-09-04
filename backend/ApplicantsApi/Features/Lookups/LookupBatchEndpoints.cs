using ApplicantsApi.Data;
using ApplicantsApi.Features.AuditLog;
using Dapper;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Caching.Memory;

namespace ApplicantsApi.Features.Lookups;

public record ProvinceUpsert(int? Id, string? Province, string? Region);
public record MunicipalUpsert(int? Id, string? Municipal, string? District, int? ProvinceId);
public record SimpleUpsert(int? Id, string? Value);
public record RecommendationUpsert(int? Id, string? Recommending, string? Designation, string? Remarks);

public record BatchRequest<T>(List<T>? Rows, List<int>? DeleteIds);

/// <summary>
/// Batch save per lookup table — the Settings screen's "Save all" sends each
/// dirty tab as one transactional batch (upserts + deletes), mirroring the old
/// TableAdapterManager.UpdateAll behavior.
/// </summary>
public static class LookupBatchEndpoints
{
    public static void MapLookupBatches(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/lookups");

        group.MapPost("/provinces/batch", (BatchRequest<ProvinceUpsert> req, Db db, AuditLogService audit, IMemoryCache cache) =>
            RunBatch(db, audit, cache, req.Rows, req.DeleteIds, "provinces",
                r => r.Id,
                "INSERT INTO provinces (province, region) VALUES (@Province, @Region)",
                "UPDATE provinces SET province=@Province, region=@Region WHERE id=@Id"));

        group.MapPost("/municipals/batch", (BatchRequest<MunicipalUpsert> req, Db db, AuditLogService audit, IMemoryCache cache) =>
            RunBatch(db, audit, cache, req.Rows, req.DeleteIds, "municipals",
                r => r.Id,
                "INSERT INTO municipals (municipal, district, province_id) VALUES (@Municipal, @District, @ProvinceId)",
                "UPDATE municipals SET municipal=@Municipal, district=@District, province_id=@ProvinceId WHERE id=@Id"));

        group.MapPost("/departments/batch", (BatchRequest<SimpleUpsert> req, Db db, AuditLogService audit, IMemoryCache cache) =>
            RunBatch(db, audit, cache, req.Rows, req.DeleteIds, "departments",
                r => r.Id,
                "INSERT INTO departments (departments) VALUES (@Value)",
                "UPDATE departments SET departments=@Value WHERE id=@Id"));

        group.MapPost("/education/batch", (BatchRequest<SimpleUpsert> req, Db db, AuditLogService audit, IMemoryCache cache) =>
            RunBatch(db, audit, cache, req.Rows, req.DeleteIds, "education",
                r => r.Id,
                "INSERT INTO education (education) VALUES (@Value)",
                "UPDATE education SET education=@Value WHERE id=@Id"));

        group.MapPost("/eligibilities/batch", (BatchRequest<SimpleUpsert> req, Db db, AuditLogService audit, IMemoryCache cache) =>
            RunBatch(db, audit, cache, req.Rows, req.DeleteIds, "eligibilities",
                r => r.Id,
                "INSERT INTO eligibilities (eligibility) VALUES (@Value)",
                "UPDATE eligibilities SET eligibility=@Value WHERE id=@Id"));

        group.MapPost("/recommendation/batch", (BatchRequest<RecommendationUpsert> req, Db db, AuditLogService audit, IMemoryCache cache) =>
            RunBatch(db, audit, cache, req.Rows, req.DeleteIds, "recommendation",
                r => r.Id,
                "INSERT INTO recommendation (recommending, designation, remarks) VALUES (@Recommending, @Designation, @Remarks)",
                "UPDATE recommendation SET recommending=@Recommending, designation=@Designation, remarks=@Remarks WHERE id=@Id"));

        group.MapPost("/schools/batch", (BatchRequest<SimpleUpsert> req, Db db, AuditLogService audit, IMemoryCache cache) =>
            RunBatch(db, audit, cache, req.Rows, req.DeleteIds, "schools",
                r => r.Id,
                "INSERT INTO schools (school) VALUES (@Value)",
                "UPDATE schools SET school=@Value WHERE id=@Id"));
    }

    private static async Task<IResult> RunBatch<T>(
        Db db, AuditLogService audit, IMemoryCache cache, List<T>? rows, List<int>? deleteIds, string table,
        Func<T, int?> idOf, string insertSql, string updateSql)
    {
        await using var conn = await db.OpenAsync();
        await using var tx = (SqlTransaction)await conn.BeginTransactionAsync();
        try
        {
            var inserted = 0;
            var updated = 0;
            foreach (var row in rows ?? [])
            {
                var id = idOf(row);
                if (id is > 0)
                {
                    await conn.ExecuteAsync(updateSql, row, tx);
                    updated++;
                }
                else
                {
                    await conn.ExecuteAsync(insertSql, row, tx);
                    inserted++;
                }
            }

            foreach (var id in deleteIds ?? [])
            {
                await conn.ExecuteAsync(
                    $"DELETE FROM {table} WHERE id = @id", new { id }, tx);
            }

            await tx.CommitAsync();
            if (inserted > 0 || updated > 0 || (deleteIds?.Count ?? 0) > 0)
            {
                LookupCacheKeys.Remove(cache, table);
                await audit.LogAsync("lookup", 0, "batch_save",
                    $"{table}: {inserted} added, {updated} edited, {deleteIds?.Count ?? 0} removed");
            }
            return Results.NoContent();
        }
        catch (SqlException ex) when (ex.Number == 547)
        {
            // FK violation, e.g. deleting a province still referenced by
            // municipalities — return a friendly, actionable message.
            await tx.RollbackAsync();
            return Results.Json(new
            {
                error = "One of the rows is still used by other records " +
                        "(for example, a province assigned to municipalities). " +
                        "Reassign or remove those references first.",
            }, statusCode: 409);
        }
        catch
        {
            await tx.RollbackAsync();
            throw;
        }
    }
}
