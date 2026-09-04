using ApplicantsApi.Common;
using ApplicantsApi.Data;
using ApplicantsApi.Features.Auth;
using ApplicantsApi.Features.AuditLog;
using ApplicantsApi.Features.Browse;
using ApplicantsApi.Features.Dashboard;
using ApplicantsApi.Features.DataHealth;
using ApplicantsApi.Features.Lookups;
using ApplicantsApi.Features.Maintenance;
using ApplicantsApi.Features.MasterData;
using ApplicantsApi.Features.Notifications;
using ApplicantsApi.Features.Reports;
using Dapper;
using QuestPDF.Infrastructure;

QuestPDF.Settings.License = LicenseType.Community;

// Default of 30s is too tight on the shared office machine this runs on —
// under heavy concurrent load (other apps, builds, etc.) SQL Server queries
// that normally finish in well under a second can get starved of scheduling
// time and hit the timeout even though the query itself isn't slow. Widen
// the default so a busy machine fails queries less often; per-call
// overrides still take precedence if a specific query ever needs a tighter
// or looser bound.
SqlMapper.Settings.CommandTimeout = 90;

AppDomain.CurrentDomain.UnhandledException += (_, e) =>
    FileErrorLog.Write("UnhandledException", (e.ExceptionObject as Exception) ?? new Exception("unknown"));

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddHttpContextAccessor();
builder.Services.AddMemoryCache();
builder.Services.AddSingleton<Db>();
builder.Services.AddSingleton<SessionStore>();
builder.Services.AddSingleton<AuditLogService>();
builder.Services.AddSingleton<MasterDataService>();
builder.Services.AddSingleton<ReportQueries>();
builder.Services.AddSingleton<MaintenanceService>();

var app = builder.Build();

app.UseMiddleware<ErrorLoggingMiddleware>();
app.UseMiddleware<SessionAuthMiddleware>();

// Schema/index checks are awaited (not backgrounded): they're just
// IF NOT EXISTS probes after the first run on a given database, so they're
// fast, but they used to race the first real requests after every restart —
// a query could run before an index it needed existed. Only the slow daily
// backup stays in the background.
{
    var maintenance = app.Services.GetRequiredService<MaintenanceService>();
    await maintenance.EnsureSchemaAsync();
    await maintenance.EnsureIndexesAsync();
}
_ = Task.Run(async () =>
{
    var maintenance = app.Services.GetRequiredService<MaintenanceService>();
    try
    {
        await maintenance.BackupIfDueAsync();
    }
    catch (Exception ex)
    {
        FileErrorLog.Write("StartupMaintenance", ex);
    }
});

app.MapGet("/health", async (Db db) =>
{
    try
    {
        await using var conn = await db.OpenAsync();
        var one = await conn.ExecuteScalarAsync<int>("SELECT 1");
        return Results.Ok(new { status = "ok", database = "connected" });
    }
    catch (Exception ex)
    {
        return Results.Json(new { status = "degraded", database = ex.Message }, statusCode: 503);
    }
});

app.MapAuditLog();
app.MapAuth();
app.MapBrowse();
app.MapDashboard();
app.MapDataHealth();
app.MapLookups();
app.MapLookupBatches();
app.MapLookupQuickAdd();
app.MapMaintenance();
app.MapMasterData();
app.MapNotifications();
app.MapReports();
app.MapStatusTools();

app.Run();
