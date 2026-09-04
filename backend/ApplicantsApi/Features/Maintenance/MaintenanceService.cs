using System.Text.Json;
using ApplicantsApi.Data;
using Dapper;
using Microsoft.Data.SqlClient;

namespace ApplicantsApi.Features.Maintenance;

/// <summary>
/// Startup maintenance: ensures the query-critical indexes exist (idempotent)
/// and takes a daily .bak backup of the Applicants database.
/// </summary>
public sealed class MaintenanceService(Db db, ILogger<MaintenanceService> logger, IConfiguration config)
{
    // (name, table, columns) — created only when missing; never destructive.
    private static readonly (string Name, string Table, string Columns)[] Indexes =
    [
        ("IX_applications_app_id", "applications", "app_id"),
        ("IX_applications_app_date", "applications", "app_date"),
        ("IX_applications_hired_date", "applications", "hired_date"),
        ("IX_masterdata_surname_firstname", "masterdata", "surname, firstname"),
        ("IX_masterdata_archived", "masterdata", "archived"),
        ("IX_masterdata_eligibilities_fk", "masterdata_eligibilities", "masterdata_id"),
        // Added for the caching/sargability pass: composite covers the
        // "latest application status" per-applicant lookup (MasterDataService
        // SearchAsync/ListArchivedAsync) as a seek instead of a per-row scan.
        ("IX_applications_appid_id", "applications", "app_id, id DESC"),
        ("IX_masterdata_municipality", "masterdata", "municipality"),
        ("IX_masterdata_dbirth", "masterdata", "dbirth"),
        ("IX_masterdata_eligibilities_masterdata_eligibility", "masterdata_eligibilities", "masterdata_id, eligibility"),
        ("IX_municipals_municipal", "municipals", "municipal"),
        // Backs the Browse grid's Office/Course filters (BrowseEndpoints.cs)
        // — the only two of its five filter dropdowns with no supporting
        // index before this.
        ("IX_applications_department", "applications", "department"),
        ("IX_masterdata_education", "masterdata", "education"),
        // status is already trimmed at rest (EnsureTrimmedDataAsync below)
        // but had no index despite being filtered/grouped on by Dashboard's
        // onProcess/onProcessByMonth/statusBreakdown on every cache refresh.
        ("IX_applications_status", "applications", "status"),
        // recommendation backs the Reports officer filter and the
        // recommendation-summary matrix (ReportQueries.cs) — see the
        // matching LTRIM/RTRIM removal in EnsureTrimmedDataAsync below.
        ("IX_applications_recommendation", "applications", "recommendation"),
        // Audit-log query patterns: user filter + DISTINCT user list,
        // action filter, and the default ORDER BY (changed_at DESC, id DESC).
        ("IX_audit_log_changed_by", "audit_log", "changed_by, changed_at DESC"),
        ("IX_audit_log_action", "audit_log", "action, changed_at DESC"),
        ("IX_audit_log_changed_at_id", "audit_log", "changed_at DESC, id DESC"),
    ];

    /// <summary>Idempotent, additive-only schema updates (never drops anything).</summary>
    public async Task EnsureSchemaAsync()
    {
        await using var conn = await db.OpenAsync();
        // Columns added for the Flutter rewrite. The old WinForms app simply
        // ignores the extras: contact2 (second number), street + subdivision
        // (finer-grained address parts feeding the composed address).
        foreach (var (name, ddl) in new[]
                 {
                     ("contact2", "ALTER TABLE masterdata ADD contact2 nvarchar(50) NULL"),
                     ("street", "ALTER TABLE masterdata ADD street nvarchar(120) NULL"),
                     ("subdivision", "ALTER TABLE masterdata ADD subdivision nvarchar(120) NULL"),
                     ("school", "ALTER TABLE masterdata ADD school nvarchar(200) NULL"),
                     ("photo_path", "ALTER TABLE masterdata ADD photo_path nvarchar(255) NULL"),
                     // Second degree/course entry, alongside the original single `education`
                     // column — same lookup list, purely additive for applicants with two
                     // qualifications.
                     ("education2", "ALTER TABLE masterdata ADD education2 nvarchar(200) NULL"),
                 })
        {
            await conn.ExecuteAsync(
                $"""
                IF NOT EXISTS (SELECT 1 FROM sys.columns
                               WHERE object_id = OBJECT_ID('masterdata') AND name = '{name}')
                    {ddl}
                """);
        }

        // Who changed what, when — added for the Flutter rewrite; the old
        // WinForms app has its own separate audit trail via triggers and
        // never touches this table.
        await conn.ExecuteAsync(
            """
            IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'audit_log')
                CREATE TABLE audit_log (
                    id INT IDENTITY PRIMARY KEY,
                    entity_type NVARCHAR(50) NOT NULL,
                    entity_id INT NOT NULL,
                    action NVARCHAR(50) NOT NULL,
                    detail NVARCHAR(500) NULL,
                    changed_at DATETIME NOT NULL,
                    changed_by NVARCHAR(100) NULL
                )
            """);
        await conn.ExecuteAsync(
            """
            IF NOT EXISTS (SELECT 1 FROM sys.indexes
                           WHERE name = 'IX_audit_log_entity' AND object_id = OBJECT_ID('audit_log'))
                CREATE INDEX IX_audit_log_entity ON audit_log (entity_type, entity_id, changed_at DESC)
            """);

        // provinces.region was sized for the original Luzon-only labels
        // (nvarchar(50)); the BARMM label needs more room. Widening is
        // always safe (never truncates existing data).
        await conn.ExecuteAsync(
            """
            IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
                       WHERE TABLE_NAME = 'provinces' AND COLUMN_NAME = 'region' AND CHARACTER_MAXIMUM_LENGTH < 150)
                ALTER TABLE provinces ALTER COLUMN region NVARCHAR(150) NULL
            """);

        await EnsureUsersAsync(conn);
        await EnsureStaffAsync(conn);
        await EnsureSchoolsAsync(conn);
        await EnsureNationwideGeoAsync(conn);
        await EnsureTrimmedDataAsync(conn);
        await PurgeOldAuditLogsAsync(conn);

        logger.LogInformation("Schema maintenance completed");
    }

    // Rows saved by this app are already trimmed at write time
    // (MasterDataService.SaveAsync), so the query layer's LTRIM(RTRIM())
    // wrapping only exists to tolerate legacy untrimmed data imported from
    // the old WinForms app. That wrapping defeats index seeks on every
    // request; cleaning the data once here lets the query layer compare
    // columns directly. Each UPDATE is guarded so it's a no-op (and near
    // instant) on every restart after the first.
    private static async Task EnsureTrimmedDataAsync(SqlConnection conn)
    {
        foreach (var (table, column) in new[]
                 {
                     ("masterdata", "municipality"),
                     ("masterdata", "surname"),
                     ("masterdata", "firstname"),
                     ("masterdata", "education"),
                     ("applications", "department"),
                     ("applications", "status"),
                     ("applications", "recommendation"),
                     ("municipals", "municipal"),
                 })
        {
            await conn.ExecuteAsync(
                $"""
                UPDATE {table} SET {column} = LTRIM(RTRIM({column}))
                WHERE {column} IS NOT NULL AND {column} <> LTRIM(RTRIM({column}))
                """);
        }
    }

    /// <summary>Deletes audit_log entries older than the configured retention
    /// period (default 365 days). Prevents unbounded table growth while
    /// keeping a full year of history.</summary>
    private async Task PurgeOldAuditLogsAsync(SqlConnection conn)
    {
        var retentionDays = int.TryParse(config["AuditLog:RetentionDays"], out var d) ? d : 365;
        var cutoff = DateTime.UtcNow.AddDays(-retentionDays);
        var deleted = await conn.ExecuteAsync(
            "DELETE FROM audit_log WHERE changed_at < @cutoff", new { cutoff });
        if (deleted > 0)
            logger.LogInformation("Purged {Count} audit log entries older than {Days} days", deleted, retentionDays);
    }

    // Real per-user accounts, replacing the old single shared office login.
    // All six accounts have identical access — there is no roles table.
    private static readonly (string Username, string Password, string FullName)[] SeedUsers =
    [
        ("des", "samson", "Lourdes C. Samson"),
        ("ann", "vinluan", "Andrea Dawn Criselda T. Vinluan"),
        ("kath", "torres", "Kathlyn Joy DC. Torres"),
        ("hara", "pascua", "Harah Karylle S. Pascua"),
        ("lyn", "felix", "Lyndon P. Felix"),
        ("red", "gonzales", "Reddrick M. Gonzales"),
    ];

    private async Task EnsureUsersAsync(SqlConnection conn)
    {
        await conn.ExecuteAsync(
            """
            IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'users')
                CREATE TABLE users (
                    id INT IDENTITY PRIMARY KEY,
                    username NVARCHAR(50) NOT NULL UNIQUE,
                    password_hash NVARCHAR(200) NOT NULL,
                    full_name NVARCHAR(150) NOT NULL
                )
            """);

        foreach (var (username, password, fullName) in SeedUsers)
        {
            var exists = await conn.ExecuteScalarAsync<int>(
                "SELECT COUNT(*) FROM users WHERE username = @username", new { username });
            if (exists == 0)
            {
                var hash = BCrypt.Net.BCrypt.HashPassword(password);
                await conn.ExecuteAsync(
                    "INSERT INTO users (username, password_hash, full_name) VALUES (@username, @hash, @fullName)",
                    new { username, hash, fullName });
            }
        }
    }

    // The six office users double as Person-in-charge options — the `staff`
    // lookup table backs that dropdown and is otherwise unrelated to login.
    private async Task EnsureStaffAsync(SqlConnection conn)
    {
        foreach (var (_, _, fullName) in SeedUsers)
        {
            var exists = await conn.ExecuteScalarAsync<int>(
                "SELECT COUNT(*) FROM staff WHERE LTRIM(RTRIM(fullname)) = @fullName", new { fullName });
            if (exists == 0)
            {
                await conn.ExecuteAsync(
                    "INSERT INTO staff (fullname) VALUES (@fullName)", new { fullName });
            }
        }
    }

    // "School graduated from" — distinct from the `education` table (which
    // holds the course/degree). 100 well-known Luzon HEIs plus a literal
    // "None" option; the applicant form's dropdown is fixed to this list
    // (no free-text quick-add), but Settings can still edit it like the
    // other lookup tables.
    private static readonly string[] SeedSchools =
    [
        "None",
        "University of the Philippines Diliman",
        "University of Santo Tomas",
        "Ateneo de Manila University",
        "De La Salle University",
        "Polytechnic University of the Philippines",
        "Far Eastern University",
        "University of the East",
        "Adamson University",
        "San Beda University",
        "Mapúa University",
        "Technological University of the Philippines",
        "Pamantasan ng Lungsod ng Maynila",
        "National University",
        "Centro Escolar University",
        "Philippine Normal University",
        "University of Manila",
        "Arellano University",
        "Lyceum of the Philippines University – Manila",
        "Trinity University of Asia",
        "Colegio de San Juan de Letran – Manila",
        "Philippine Christian University",
        "Emilio Aguinaldo College",
        "University of Makati",
        "Rizal Technological University",
        "Philippine Women's University",
        "St. Paul University Manila",
        "San Sebastian College – Recoletos, Manila",
        "AMA University",
        "STI College",
        "University of Perpetual Help System DALTA",
        "University of the Cordilleras",
        "Saint Louis University – Baguio",
        "University of Baguio",
        "Baguio Central University",
        "Benguet State University",
        "University of Northern Philippines",
        "Mariano Marcos State University",
        "University of Luzon",
        "Lyceum-Northwestern University",
        "Pangasinan State University",
        "Colegio de Dagupan",
        "Panpacific University North Philippines",
        "Virgen Milagrosa University Foundation",
        "Ilocos Sur Polytechnic State College",
        "Northwestern University (Laoag)",
        "Divine Word College of Laoag",
        "Data Center College of the Philippines",
        "Cagayan State University",
        "St. Paul University Philippines",
        "University of Saint Louis – Tuguegarao",
        "Isabela State University",
        "Quirino State University",
        "Nueva Vizcaya State University",
        "Holy Angel University",
        "Angeles University Foundation",
        "Don Honorio Ventura State University",
        "Pampanga State Agricultural University",
        "Bulacan State University",
        "Central Luzon State University",
        "Tarlac State University",
        "Tarlac Agricultural University",
        "Bataan Peninsula State University",
        "Nueva Ecija University of Science and Technology",
        "Wesleyan University – Philippines",
        "Systems Plus College Foundation",
        "City College of Angeles",
        "Republic Central Colleges",
        "Aurora State College of Technology",
        "Laguna State Polytechnic University",
        "Batangas State University",
        "Cavite State University",
        "Southern Luzon State University",
        "Lyceum of the Philippines University – Batangas",
        "De La Salle Lipa",
        "University of Batangas",
        "University of Perpetual Help System – Laguna",
        "Pamantasan ng Cabuyao",
        "San Pablo Colleges",
        "San Sebastian College – Recoletos de Cavite",
        "Adventist University of the Philippines",
        "Rizal State University",
        "Palawan State University",
        "Mindoro State University",
        "Marinduque State College",
        "Romblon State University",
        "Western Philippines University",
        "Bicol University",
        "Ateneo de Naga University",
        "University of Nueva Caceres",
        "Naga College Foundation",
        "Camarines Sur Polytechnic Colleges",
        "Camarines Norte State College",
        "Partido State University",
        "Sorsogon State University",
        "Catanduanes State University",
        "Bicol State College of Applied Sciences and Technology",
        "Eulogio \"Amang\" Rodriguez Institute of Science and Technology",
        "New Era University",
        "Manuel L. Quezon University",
        "Union Christian College",
    ];

    private async Task EnsureSchoolsAsync(SqlConnection conn)
    {
        await conn.ExecuteAsync(
            """
            IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'schools')
                CREATE TABLE schools (
                    id INT IDENTITY PRIMARY KEY,
                    school NVARCHAR(200) NOT NULL UNIQUE
                )
            """);

        foreach (var school in SeedSchools)
        {
            var exists = await conn.ExecuteScalarAsync<int>(
                "SELECT COUNT(*) FROM schools WHERE LTRIM(RTRIM(school)) = @school", new { school });
            if (exists == 0)
            {
                await conn.ExecuteAsync("INSERT INTO schools (school) VALUES (@school)", new { school });
            }
        }
    }

    private sealed record GeoProvinceSeed(string Province, string Region);
    private sealed record GeoMunicipalSeed(string Municipal, string Province);
    private sealed record GeoSeedFile(List<GeoProvinceSeed> Provinces, List<GeoMunicipalSeed> Municipals);

    // Fills in the provinces/cities/municipalities the office's Luzon-only
    // data never had (Visayas + Mindanao), sourced from the official PSGC.
    // Matches existing rows by name (case/whitespace-insensitive) so this
    // never duplicates or renames what's already there — including NCR and
    // all of Luzon, which this database already covers in full.
    private async Task EnsureNationwideGeoAsync(SqlConnection conn)
    {
        var seedPath = Path.Combine(AppContext.BaseDirectory, "Features", "Maintenance", "Seed", "nationwide_geo.json");
        if (!File.Exists(seedPath))
        {
            logger.LogWarning("Nationwide geo seed file not found at {Path}; skipping", seedPath);
            return;
        }

        var seed = JsonSerializer.Deserialize<GeoSeedFile>(
            await File.ReadAllTextAsync(seedPath),
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        if (seed is null) return;

        foreach (var p in seed.Provinces)
        {
            var exists = await conn.ExecuteScalarAsync<int>(
                "SELECT COUNT(*) FROM provinces WHERE LTRIM(RTRIM(province)) = @province", new { p.Province });
            if (exists == 0)
            {
                await conn.ExecuteAsync(
                    "INSERT INTO provinces (province, region) VALUES (@Province, @Region)", p);
            }
        }

        var provinceIds = (await conn.QueryAsync<(string Province, int Id)>(
            "SELECT LTRIM(RTRIM(province)) AS Province, id AS Id FROM provinces"))
            .GroupBy(x => x.Province, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.First().Id, StringComparer.OrdinalIgnoreCase);

        foreach (var m in seed.Municipals)
        {
            if (!provinceIds.TryGetValue(m.Province, out var provinceId))
            {
                logger.LogWarning("Skipping {Municipal}: province {Province} not found", m.Municipal, m.Province);
                continue;
            }
            var exists = await conn.ExecuteScalarAsync<int>(
                "SELECT COUNT(*) FROM municipals WHERE LTRIM(RTRIM(municipal)) = @municipal AND province_id = @provinceId",
                new { m.Municipal, provinceId });
            if (exists == 0)
            {
                await conn.ExecuteAsync(
                    "INSERT INTO municipals (municipal, district, province_id) VALUES (@municipal, NULL, @provinceId)",
                    new { m.Municipal, provinceId });
            }
        }
    }

    public async Task EnsureIndexesAsync()
    {
        await using var conn = await db.OpenAsync();
        foreach (var (name, table, columns) in Indexes)
        {
            try
            {
                await conn.ExecuteAsync(
                    $"""
                    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = @name AND object_id = OBJECT_ID(@table))
                        EXEC('CREATE INDEX {name} ON {table} ({columns})')
                    """,
                    new { name, table });
            }
            catch (Exception ex)
            {
                // Index creation is an optimization — never block startup on it.
                logger.LogWarning(ex, "Could not ensure index {Index}", name);
            }
        }
        logger.LogInformation("Index maintenance completed");
    }

    /// <summary>Backs up to the SQL Server instance's default backup folder
    /// (always writable by the SQL service). One file per day, kept 14 days.</summary>
    public async Task<string?> BackupIfDueAsync(bool force = false)
    {
        await using var conn = await db.OpenAsync();

        var backupDir = config["Backup:Folder"];
        if (string.IsNullOrWhiteSpace(backupDir))
        {
            backupDir = await conn.ExecuteScalarAsync<string>(
                "SELECT CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(4000))");
        }
        if (string.IsNullOrWhiteSpace(backupDir))
        {
            logger.LogWarning("No backup folder available; skipping backup");
            return null;
        }

        var fileName = $"Applicants-{DateTime.Today:yyyyMMdd}.bak";
        var fullPath = Path.Combine(backupDir, fileName);

        if (!force && File.Exists(fullPath))
        {
            return fullPath; // today's backup already exists
        }

        // No COMPRESSION — unsupported on SQL Server Express.
        await conn.ExecuteAsync(
            "BACKUP DATABASE [Applicants] TO DISK = @fullPath WITH INIT",
            new { fullPath },
            commandTimeout: 600);
        logger.LogInformation("Database backed up to {Path}", fullPath);

        // Keep two weeks of daily backups.
        try
        {
            var cutoff = DateTime.Today.AddDays(-14);
            foreach (var f in Directory.GetFiles(backupDir, "Applicants-*.bak"))
            {
                if (File.GetLastWriteTime(f) < cutoff) File.Delete(f);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Backup cleanup skipped");
        }

        return fullPath;
    }
}

public static class MaintenanceEndpoints
{
    public static void MapMaintenance(this IEndpointRouteBuilder app)
    {
        app.MapPost("/api/maintenance/backup", async (MaintenanceService svc) =>
        {
            try
            {
                var path = await svc.BackupIfDueAsync(force: true);
                return path is null
                    ? Results.Json(new { error = "No backup folder available." }, statusCode: 500)
                    : Results.Ok(new { path });
            }
            catch (Exception ex)
            {
                return Results.Json(new { error = $"Backup failed: {ex.Message}" }, statusCode: 500);
            }
        });
    }
}
