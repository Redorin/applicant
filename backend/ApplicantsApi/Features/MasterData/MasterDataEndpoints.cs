using ApplicantsApi.Features.AuditLog;
using Microsoft.Extensions.Caching.Memory;

namespace ApplicantsApi.Features.MasterData;

public static class MasterDataEndpoints
{
    private static string PhotoPathCacheKey(int id) => $"photo-path:{id}";

    public static void MapMasterData(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/masterdata");

        group.MapGet("/", async (
            string? search, string? municipality, string? status,
            DateTime? dateFrom, DateTime? dateTo, int? limit,
            MasterDataService svc) =>
        {
            var rows = await svc.SearchAsync(
                search, municipality, status, dateFrom, dateTo,
                Math.Clamp(limit ?? 100, 1, 1000));
            return Results.Ok(rows);
        });

        group.MapGet("/{id:int}", async (int id, MasterDataService svc) =>
        {
            var detail = await svc.GetByIdAsync(id);
            return detail is null ? Results.NotFound() : Results.Ok(detail);
        });

        group.MapGet("/duplicate-check", async (
            string surname, string firstname, DateTime? dbirth, int? excludeId,
            MasterDataService svc) =>
        {
            var count = await svc.CountDuplicatesAsync(surname, firstname, dbirth, excludeId);
            return Results.Ok(new { count });
        });

        group.MapPost("/", async (MasterDataSaveRequest req, MasterDataService svc) =>
        {
            var errors = await svc.ValidateAsync(req);
            if (errors.Count > 0) return Results.Json(new { errors }, statusCode: 422);
            var id = await svc.SaveAsync(req with { Id = null });
            return Results.Ok(new { id });
        });

        group.MapPut("/{id:int}", async (int id, MasterDataSaveRequest req, MasterDataService svc) =>
        {
            var errors = await svc.ValidateAsync(req);
            if (errors.Count > 0) return Results.Json(new { errors }, statusCode: 422);
            var savedId = await svc.SaveAsync(req with { Id = id });
            return Results.Ok(new { id = savedId });
        });

        group.MapPost("/import", async (List<MasterDataSaveRequest> rows, MasterDataService svc, AuditLogService audit) =>
        {
            if (rows.Count == 0) return Results.Ok(new List<MasterDataImportResult>());
            if (rows.Count > 5000)
                return Results.Json(new { error = "Maximum 5,000 rows per import." }, statusCode: 422);
            var results = await svc.ImportAsync(rows);
            var imported = results.Count(r => r.Success);
            var duplicates = results.Count(r => !r.Success && r.Duplicate);
            var failed = results.Count(r => !r.Success && !r.Duplicate);
            await audit.LogAsync("masterdata", 0, "import",
                $"{imported} imported, {duplicates} duplicates, {failed} failed of {rows.Count} rows");
            return Results.Ok(results);
        });

        group.MapPost("/{id:int}/archive", async (int id, MasterDataService svc) =>
        {
            var ok = await svc.ArchiveAsync(id);
            return ok ? Results.NoContent() : Results.NotFound();
        });

        group.MapGet("/archived", async (string? search, MasterDataService svc) =>
            Results.Ok(await svc.ListArchivedAsync(search)));

        group.MapPost("/{id:int}/restore", async (int id, MasterDataService svc) =>
        {
            var ok = await svc.RestoreAsync(id);
            return ok ? Results.NoContent() : Results.NotFound();
        });

        group.MapPost("/{id:int}/photo", async (int id, IFormFile photo, MasterDataService svc, IMemoryCache cache) =>
        {
            const long maxBytes = 2 * 1024 * 1024;
            var ext = Path.GetExtension(photo.FileName).ToLowerInvariant();
            if (photo.Length == 0 || photo.Length > maxBytes)
                return Results.Json(new { error = "Photo must be under 2MB." }, statusCode: 422);
            if (ext is not (".jpg" or ".jpeg" or ".png"))
                return Results.Json(new { error = "Only JPG and PNG photos are allowed." }, statusCode: 422);

            var dir = Path.Combine(AppContext.BaseDirectory, "Photos");
            Directory.CreateDirectory(dir);

            var oldFileName = await svc.GetPhotoPathAsync(id);
            var fileName = $"{id}-{Guid.NewGuid():N}{ext}";
            await using (var stream = File.Create(Path.Combine(dir, fileName)))
                await photo.CopyToAsync(stream);

            await svc.SetPhotoPathAsync(id, fileName);
            cache.Remove(PhotoPathCacheKey(id));

            if (!string.IsNullOrEmpty(oldFileName))
            {
                var oldFile = Path.Combine(dir, oldFileName);
                if (File.Exists(oldFile)) File.Delete(oldFile);
            }

            return Results.Ok(new { photoPath = fileName });
        });

        group.MapGet("/{id:int}/photo", async (int id, HttpContext ctx, MasterDataService svc, IMemoryCache cache) =>
        {
            // photo_path rarely changes and is otherwise re-read from SQL
            // Server on every single photo view — cached short-TTL, and
            // explicitly invalidated by the upload/delete endpoints above/
            // below so a just-changed photo is never served stale.
            var photoPath = await cache.GetOrCreateAsync(PhotoPathCacheKey(id), async entry =>
            {
                entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(10);
                return await svc.GetPhotoPathAsync(id);
            });
            if (string.IsNullOrEmpty(photoPath)) return Results.NotFound();

            var file = Path.Combine(AppContext.BaseDirectory, "Photos", photoPath);
            if (!File.Exists(file)) return Results.NotFound();

            // The filename itself is a fresh GUID on every upload (see above),
            // so it doubles as a perfect strong ETag: unchanged photo → 304
            // without re-reading the file; a new upload always gets a new
            // filename, so a cached image can never be served stale.
            var etag = $"\"{photoPath}\"";
            if (ctx.Request.Headers.IfNoneMatch == etag) return Results.StatusCode(StatusCodes.Status304NotModified);
            ctx.Response.Headers.ETag = etag;
            ctx.Response.Headers.CacheControl = "private, max-age=3600, must-revalidate";

            var contentType = Path.GetExtension(file).ToLowerInvariant() switch
            {
                ".png" => "image/png",
                _ => "image/jpeg",
            };
            // Streams from disk instead of buffering the whole file into
            // memory first (Results.File(Stream, ...) takes ownership and
            // disposes it once the response finishes).
            return Results.File(File.OpenRead(file), contentType, enableRangeProcessing: true);
        });

        group.MapDelete("/{id:int}/photo", async (int id, MasterDataService svc, IMemoryCache cache) =>
        {
            var photoPath = await svc.GetPhotoPathAsync(id);
            if (!string.IsNullOrEmpty(photoPath))
            {
                var file = Path.Combine(AppContext.BaseDirectory, "Photos", photoPath);
                if (File.Exists(file)) File.Delete(file);
            }
            await svc.SetPhotoPathAsync(id, null);
            cache.Remove(PhotoPathCacheKey(id));
            return Results.NoContent();
        });
    }
}
