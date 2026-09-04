using System.Text.RegularExpressions;
using ApplicantsApi.Data;
using ApplicantsApi.Features.AuditLog;
using Dapper;
using Microsoft.Data.SqlClient;

namespace ApplicantsApi.Features.MasterData;

public sealed partial class MasterDataService(Db db, AuditLogService audit)
{
    [GeneratedRegex(@"^(\d{4}[\s-]?\d{3}[\s-]?\d{4}|\d{11})$")]
    private static partial Regex ContactPattern();

    private const string NotArchived = "(archived = 0 OR archived IS NULL)";

    // ---------- validation (same rules as the old masterfrom.cs, aggregated) ----------

    /// <summary>
    /// Required: surname, first name, date of birth, gender, civil status,
    /// contact no. 1, municipality, province, education, school graduated
    /// from, at least one eligibility, and person-in-charge. Everything else
    /// is optional.
    /// </summary>
    public async Task<List<string>> ValidateAsync(MasterDataSaveRequest req)
    {
        var errors = new List<string>();

        if (string.IsNullOrWhiteSpace(req.Surname)) errors.Add("Surname is required.");
        if (string.IsNullOrWhiteSpace(req.Firstname)) errors.Add("First name is required.");

        if (req.Dbirth is null)
        {
            errors.Add("Date of birth is required.");
        }
        else if (req.Dbirth.Value.Year >= DateTime.Today.Year)
        {
            errors.Add("Date of birth cannot fall in the current year.");
        }

        if (string.IsNullOrWhiteSpace(req.Gender)) errors.Add("Gender is required.");
        if (string.IsNullOrWhiteSpace(req.Civistat)) errors.Add("Civil status is required.");
        if (string.IsNullOrWhiteSpace(req.Province)) errors.Add("Province is required.");
        if (string.IsNullOrWhiteSpace(req.Education)) errors.Add("Education is required.");
        if (string.IsNullOrWhiteSpace(req.School)) errors.Add("School graduated from is required.");
        if (string.IsNullOrWhiteSpace(req.Personincharge)) errors.Add("Person-in-charge is required.");

        if (string.IsNullOrWhiteSpace(req.Contact) || !ContactPattern().IsMatch(req.Contact))
        {
            errors.Add("Contact number 1 must be a valid phone or telephone number (e.g. 09XX XXX XXXX or 1234-567-8901).");
        }
        // The second number is optional but must be valid when present.
        if (!string.IsNullOrWhiteSpace(req.Contact2) && !ContactPattern().IsMatch(req.Contact2))
        {
            errors.Add("Contact number 2 must be a valid phone or telephone number (or be left blank).");
        }

        var hasEligibility =
            (req.Eligibilities?.Any(e => !string.IsNullOrWhiteSpace(e)) ?? false) ||
            !string.IsNullOrWhiteSpace(req.LegacyEligibility);
        if (!hasEligibility) errors.Add("At least one eligibility is required.");

        await using var conn = await db.OpenAsync();

        if (!string.IsNullOrWhiteSpace(req.Municipality))
        {
            var muniExists = await conn.ExecuteScalarAsync<int>(
                "SELECT COUNT(*) FROM municipals WHERE municipal = @m",
                new { m = req.Municipality.Trim() });
            if (muniExists == 0) errors.Add("Municipality is not in the municipality list.");
        }
        else
        {
            errors.Add("Municipality is required.");
        }

        return errors;
    }

    // ---------- duplicate check (same semantics as CountByNameAndBirth) ----------

    public async Task<int> CountDuplicatesAsync(string surname, string firstname, DateTime? dbirth, int? excludeId)
    {
        await using var conn = await db.OpenAsync();
        return await conn.ExecuteScalarAsync<int>(
            "SELECT COUNT(*) FROM masterdata WHERE surname = @surname" +
            " AND firstname = @firstname" +
            " AND (@dayStart IS NULL OR (dbirth >= @dayStart AND dbirth < @dayEnd))" +
            " AND id <> @excludeId AND " + NotArchived,
            new
            {
                surname = surname.Trim(),
                firstname = firstname.Trim(),
                dayStart = dbirth?.Date,
                dayEnd = dbirth?.Date.AddDays(1),
                excludeId = excludeId ?? -1,
            });
    }

    // ---------- bulk import ----------

    /// <summary>
    /// Inserts each row with the same validation and duplicate rules as a
    /// single manual save — no relaxed path for bulk data. Rows that fail
    /// validation or match an existing applicant (by surname+firstname+dbirth)
    /// are skipped and reported rather than blocking the rest of the batch.
    ///
    /// Unlike a manual save, this avoids one DB round trip per row for the
    /// municipality-exists check and the duplicate count (previously ~4N+
    /// round trips, each opening its own connection, for an N-row import):
    /// the municipality list and any existing applicants sharing a surname
    /// with the batch are pulled once up front, and everything after that is
    /// compared in memory. Two rows in the *same* file that duplicate each
    /// other still behave exactly as a sequential import would — the
    /// in-memory "seen" set grows as each row is accepted, so row 2 still
    /// sees row 1 as a duplicate even though row 1 hasn't hit the database
    /// yet. All accepted rows are then saved in one transaction instead of
    /// one transaction per row.
    /// </summary>
    public async Task<List<MasterDataImportResult>> ImportAsync(List<MasterDataSaveRequest> rows)
    {
        await using var conn = await db.OpenAsync();

        var municipalNames = new HashSet<string>(
            await conn.QueryAsync<string>("SELECT municipal FROM municipals"),
            StringComparer.OrdinalIgnoreCase);

        var candidateSurnames = rows
            .Select(r => r.Surname?.Trim())
            .Where(s => !string.IsNullOrEmpty(s))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        var seen = candidateSurnames.Count > 0
            ? (await conn.QueryAsync<(string? Surname, string? Firstname, DateTime? Dbirth)>(
                $"SELECT surname AS Surname, firstname AS Firstname, dbirth AS Dbirth FROM masterdata" +
                $" WHERE surname IN @candidateSurnames AND {NotArchived}",
                new { candidateSurnames })).ToList()
            : [];

        var results = new List<MasterDataImportResult>();
        var toSave = new List<(int RowNumber, MasterDataSaveRequest Req)>();
        var rowNumber = 0;

        foreach (var raw in rows)
        {
            rowNumber++;
            var req = raw with { Id = null };

            var errors = ValidateOffline(req, municipalNames);
            if (errors.Count > 0)
            {
                results.Add(new MasterDataImportResult(rowNumber, false, null, false, errors));
                continue;
            }

            var isDuplicate = seen.Any(e => IsSameApplicant(e.Surname, e.Firstname, e.Dbirth, req));
            if (isDuplicate)
            {
                results.Add(new MasterDataImportResult(rowNumber, false, null, true,
                    ["Possible duplicate of an existing applicant (same name and date of birth)."]));
                continue;
            }

            seen.Add((req.Surname, req.Firstname, req.Dbirth));
            toSave.Add((rowNumber, req));
        }

        if (toSave.Count > 0)
        {
            await using var tx = (SqlTransaction)await conn.BeginTransactionAsync();
            try
            {
                foreach (var (savedRowNumber, req) in toSave)
                {
                    var id = await SaveWithinTransactionAsync(conn, tx, req);
                    results.Add(new MasterDataImportResult(savedRowNumber, true, id, false, []));
                }
                await tx.CommitAsync();
            }
            catch
            {
                await tx.RollbackAsync();
                throw;
            }
        }

        return results.OrderBy(r => r.RowNumber).ToList();
    }

    /// <summary>Same field-level rules as <see cref="ValidateAsync"/>, but the
    /// municipality-exists check is a lookup against a set loaded once for the
    /// whole batch instead of its own query per row.</summary>
    private static List<string> ValidateOffline(MasterDataSaveRequest req, HashSet<string> municipalNames)
    {
        var errors = new List<string>();

        if (string.IsNullOrWhiteSpace(req.Surname)) errors.Add("Surname is required.");
        if (string.IsNullOrWhiteSpace(req.Firstname)) errors.Add("First name is required.");

        if (req.Dbirth is null)
        {
            errors.Add("Date of birth is required.");
        }
        else if (req.Dbirth.Value.Year >= DateTime.Today.Year)
        {
            errors.Add("Date of birth cannot fall in the current year.");
        }

        if (string.IsNullOrWhiteSpace(req.Gender)) errors.Add("Gender is required.");
        if (string.IsNullOrWhiteSpace(req.Civistat)) errors.Add("Civil status is required.");
        if (string.IsNullOrWhiteSpace(req.Province)) errors.Add("Province is required.");
        if (string.IsNullOrWhiteSpace(req.Education)) errors.Add("Education is required.");
        if (string.IsNullOrWhiteSpace(req.School)) errors.Add("School graduated from is required.");
        if (string.IsNullOrWhiteSpace(req.Personincharge)) errors.Add("Person-in-charge is required.");

        if (string.IsNullOrWhiteSpace(req.Contact) || !ContactPattern().IsMatch(req.Contact))
        {
            errors.Add("Contact number 1 must match the format 09XX XXX XXXX.");
        }
        if (!string.IsNullOrWhiteSpace(req.Contact2) && !ContactPattern().IsMatch(req.Contact2))
        {
            errors.Add("Contact number 2 must match the format 09XX XXX XXXX (or be left blank).");
        }

        var hasEligibility =
            (req.Eligibilities?.Any(e => !string.IsNullOrWhiteSpace(e)) ?? false) ||
            !string.IsNullOrWhiteSpace(req.LegacyEligibility);
        if (!hasEligibility) errors.Add("At least one eligibility is required.");

        if (!string.IsNullOrWhiteSpace(req.Municipality))
        {
            if (!municipalNames.Contains(req.Municipality.Trim()))
                errors.Add("Municipality is not in the municipality list.");
        }
        else
        {
            errors.Add("Municipality is required.");
        }

        return errors;
    }

    /// <summary>Same day-window match <see cref="CountDuplicatesAsync"/> uses,
    /// against an in-memory candidate instead of a fresh COUNT(*) query.</summary>
    private static bool IsSameApplicant(
        string? surname, string? firstname, DateTime? dbirth, MasterDataSaveRequest req) =>
        string.Equals(surname?.Trim(), req.Surname?.Trim(), StringComparison.OrdinalIgnoreCase) &&
        string.Equals(firstname?.Trim(), req.Firstname?.Trim(), StringComparison.OrdinalIgnoreCase) &&
        (req.Dbirth is null || dbirth?.Date == req.Dbirth.Value.Date);

    // ---------- read ----------

    public async Task<List<MasterDataSearchRow>> SearchAsync(
        string? search, string? municipality, string? status, DateTime? dateFrom, DateTime? dateTo, int limit)
    {
        await using var conn = await db.OpenAsync();
        var rows = await conn.QueryAsync<MasterDataSearchRow>(
            $"""
            SELECT TOP (@limit) Id, Surname, Firstname, Midname, Municipality, Dbirth, LatestStatus
            FROM (
                SELECT DISTINCT
                    m.id AS Id, m.surname AS Surname, m.firstname AS Firstname, m.midname AS Midname,
                    m.municipality AS Municipality, m.dbirth AS Dbirth,
                    (SELECT TOP 1 a2.status FROM applications a2 WHERE a2.app_id = m.id ORDER BY a2.id DESC) AS LatestStatus
                FROM masterdata m
                LEFT JOIN applications a ON a.app_id = m.id
                WHERE {NotArchived.Replace("archived", "m.archived")}
                  AND (@search IS NULL OR (m.surname + ', ' + m.firstname + ' ' + ISNULL(m.midname,'')) LIKE @searchLike)
                  AND (@municipality IS NULL OR m.municipality = @municipality)
                  AND (@status IS NULL OR a.status LIKE @statusLike)
                  AND (@dateFrom IS NULL OR a.app_date >= @dateFrom)
                  AND (@dateToExclusive IS NULL OR a.app_date < @dateToExclusive)
            ) x
            -- Surname matches rank above a hit buried in the first/middle name —
            -- searching "Cruz" should surface people actually named Cruz first.
            ORDER BY
                CASE
                    WHEN LTRIM(RTRIM(x.Surname)) = @searchTrim THEN 0
                    WHEN x.Surname LIKE @searchPrefix THEN 1
                    WHEN x.Surname LIKE @searchLike THEN 2
                    ELSE 3
                END,
                x.Surname, x.Firstname
            """,
            new
            {
                limit,
                search = string.IsNullOrWhiteSpace(search) ? null : search.Trim(),
                searchTrim = search?.Trim(),
                searchPrefix = $"{search?.Trim()}%",
                searchLike = $"%{search?.Trim()}%",
                municipality = string.IsNullOrWhiteSpace(municipality) ? null : municipality.Trim(),
                status = string.IsNullOrWhiteSpace(status) ? null : status.Trim(),
                statusLike = $"%{status?.Trim()}%",
                dateFrom,
                dateToExclusive = dateTo?.Date.AddDays(1),
            });
        return rows.ToList();
    }

    public async Task<MasterDataDetail?> GetByIdAsync(int id)
    {
        await using var conn = await db.OpenAsync();

        // One round trip instead of three: the record, its eligibilities,
        // and its applications are all read off a single batched query
        // (SQL Server returns all three result sets from one execution).
        using var multi = await conn.QueryMultipleAsync(
            $"""
            SELECT * FROM masterdata WHERE id = @id AND {NotArchived};
            SELECT eligibility FROM masterdata_eligibilities WHERE masterdata_id = @id ORDER BY id;
            SELECT id AS Id, app_date AS AppDate, position AS Position, department AS Department,
                   status AS Status, intvw_date AS IntvwDate, recommendation AS Recommendation,
                   hired_date AS HiredDate, finalposition AS FinalPosition, finaldepartment AS FinalDepartment,
                   finalstatus AS FinalStatus, emp_status AS EmpStatus, remarks AS Remarks, assumption AS Assumption
            FROM applications WHERE app_id = @id ORDER BY app_date DESC, id DESC;
            """,
            new { id });

        var m = await multi.ReadSingleOrDefaultAsync();
        if (m is null) return null;

        var eligibilities = (await multi.ReadAsync<string>()).ToList();
        var applications = (await multi.ReadAsync<ApplicationDto>()).ToList();

        var row = (IDictionary<string, object?>)m;
        string? S(string key) => row.TryGetValue(key, out var v) ? v as string : null;

        return new MasterDataDetail(
            Id: (int)row["id"]!,
            Surname: S("surname"),
            Firstname: S("firstname"),
            Midname: S("midname"),
            Ext: S("ext"),
            Dbirth: row["dbirth"] as DateTime?,
            Gender: S("gender"),
            Civistat: S("civistat"),
            Contact: S("contact"),
            Contact2: S("contact2"),
            Address: S("address"),
            HouseNo: S("house_no"),
            Street: S("street"),
            Subdivision: S("subdivision"),
            Barangay: S("barangay"),
            Municipality: S("municipality"),
            District: S("district"),
            Province: S("province"),
            Education: S("education"),
            Education2: S("education2"),
            School: S("school"),
            LegacyEligibility: S("eligibility"),
            Experience: S("experience"),
            Skills: S("skills"),
            Personincharge: S("personincharge"),
            Notes: S("notes"),
            Lenofservice: S("lenofservice"),
            Training: S("training"),
            PhotoPath: S("photo_path"),
            Eligibilities: eligibilities,
            Applications: applications);
    }

    // ---------- write (one real transaction, replacing the old DataSet dance) ----------

    public async Task<int> SaveAsync(MasterDataSaveRequest req)
    {
        await using var conn = await db.OpenAsync();
        await using var tx = (SqlTransaction)await conn.BeginTransactionAsync();
        try
        {
            var id = await SaveWithinTransactionAsync(conn, tx, req);
            await tx.CommitAsync();
            return id;
        }
        catch
        {
            await tx.RollbackAsync();
            throw;
        }
    }

    /// <summary>The actual save logic, reused by both a single manual save
    /// (<see cref="SaveAsync"/>, its own connection/transaction/commit) and
    /// bulk import (<see cref="ImportAsync"/>, one shared connection/
    /// transaction/commit for the whole batch). Caller owns commit/rollback.</summary>
    private async Task<int> SaveWithinTransactionAsync(SqlConnection conn, SqlTransaction tx, MasterDataSaveRequest req)
    {
        int id;
        var wasNew = req.Id is not > 0;
        var biodata = new
        {
            surname = req.Surname?.Trim(),
            firstname = req.Firstname?.Trim(),
            midname = req.Midname?.Trim(),
            ext = req.Ext?.Trim(),
            dbirth = req.Dbirth,
            gender = req.Gender,
            civistat = req.Civistat,
            contact = req.Contact?.Trim(),
            contact2 = string.IsNullOrWhiteSpace(req.Contact2) ? null : req.Contact2.Trim(),
            address = req.Address?.Trim(),
            house_no = req.HouseNo?.Trim(),
            street = req.Street?.Trim(),
            subdivision = req.Subdivision?.Trim(),
            barangay = req.Barangay?.Trim(),
            municipality = req.Municipality?.Trim(),
            district = req.District?.Trim(),
            province = req.Province?.Trim(),
            education = req.Education,
            education2 = string.IsNullOrWhiteSpace(req.Education2) ? null : req.Education2.Trim(),
            school = req.School,
            eligibility = req.LegacyEligibility,
            experience = req.Experience,
            skills = req.Skills,
            personincharge = req.Personincharge,
            notes = req.Notes,
            lenofservice = req.Lenofservice,
            training = req.Training,
        };

        if (req.Id is > 0)
        {
            id = req.Id.Value;
            await conn.ExecuteAsync(
                """
                UPDATE masterdata SET
                    surname=@surname, firstname=@firstname, midname=@midname, ext=@ext, dbirth=@dbirth,
                    gender=@gender, civistat=@civistat, contact=@contact, contact2=@contact2, address=@address,
                    house_no=@house_no, street=@street, subdivision=@subdivision,
                    barangay=@barangay, municipality=@municipality, district=@district,
                    province=@province, education=@education, education2=@education2, school=@school, eligibility=@eligibility, experience=@experience,
                    skills=@skills, personincharge=@personincharge, notes=@notes,
                    lenofservice=@lenofservice, training=@training
                WHERE id=@id
                """,
                new { id, biodata.surname, biodata.firstname, biodata.midname, biodata.ext, biodata.dbirth, biodata.gender, biodata.civistat, biodata.contact, biodata.contact2, biodata.address, biodata.house_no, biodata.street, biodata.subdivision, biodata.barangay, biodata.municipality, biodata.district, biodata.province, biodata.education, biodata.education2, biodata.school, biodata.eligibility, biodata.experience, biodata.skills, biodata.personincharge, biodata.notes, biodata.lenofservice, biodata.training },
                tx);
        }
        else
        {
            id = await conn.ExecuteScalarAsync<int>(
                """
                INSERT INTO masterdata
                    (surname, firstname, midname, ext, dbirth, gender, civistat, contact, contact2, address,
                     house_no, street, subdivision, barangay, municipality, district, province, education, education2, school, eligibility,
                     experience, skills, personincharge, notes, lenofservice, training)
                OUTPUT INSERTED.id
                VALUES
                    (@surname, @firstname, @midname, @ext, @dbirth, @gender, @civistat, @contact, @contact2, @address,
                     @house_no, @street, @subdivision, @barangay, @municipality, @district, @province, @education, @education2, @school, @eligibility,
                     @experience, @skills, @personincharge, @notes, @lenofservice, @training)
                """,
                biodata, tx);
        }

        // Eligibilities: replace-all inside the transaction (small row counts per applicant).
        await conn.ExecuteAsync(
            "DELETE FROM masterdata_eligibilities WHERE masterdata_id = @id", new { id }, tx);
        foreach (var e in (req.Eligibilities ?? []).Where(e => !string.IsNullOrWhiteSpace(e)))
        {
            await conn.ExecuteAsync(
                "INSERT INTO masterdata_eligibilities (masterdata_id, eligibility) VALUES (@id, @e)",
                new { id, e = e.Trim() }, tx);
        }

        // Applications: diff by id — update kept rows, insert new, delete removed.
        var incoming = req.Applications ?? [];
        var keptIds = incoming.Where(a => a.Id is > 0).Select(a => a.Id!.Value).ToList();

        await conn.ExecuteAsync(
            keptIds.Count > 0
                ? "DELETE FROM applications WHERE app_id = @id AND id NOT IN @keptIds"
                : "DELETE FROM applications WHERE app_id = @id",
            new { id, keptIds }, tx);

        foreach (var a in incoming)
        {
            var p = new
            {
                appId = id,
                rowId = a.Id,
                app_date = a.AppDate,
                a.Position,
                a.Department,
                status = string.IsNullOrWhiteSpace(a.Status) ? "On Process" : a.Status,
                intvw_date = a.IntvwDate,
                a.Recommendation,
                hired_date = a.HiredDate,
                finalposition = a.FinalPosition,
                finaldepartment = a.FinalDepartment,
                finalstatus = a.FinalStatus,
                emp_status = a.EmpStatus,
                a.Remarks,
                assumption = a.Assumption,
            };

            if (a.Id is > 0)
            {
                await conn.ExecuteAsync(
                    """
                    UPDATE applications SET
                        app_date=@app_date, position=@Position, department=@Department, status=@status,
                        intvw_date=@intvw_date, recommendation=@Recommendation, hired_date=@hired_date,
                        finalposition=@finalposition, finaldepartment=@finaldepartment, finalstatus=@finalstatus,
                        emp_status=@emp_status, remarks=@Remarks, assumption=@assumption
                    WHERE id=@rowId AND app_id=@appId
                    """, p, tx);
            }
            else
            {
                await conn.ExecuteAsync(
                    """
                    INSERT INTO applications
                        (app_id, app_date, position, department, status, intvw_date, recommendation,
                         hired_date, finalposition, finaldepartment, finalstatus, emp_status, remarks, assumption)
                    VALUES
                        (@appId, @app_date, @Position, @Department, @status, @intvw_date, @Recommendation,
                         @hired_date, @finalposition, @finaldepartment, @finalstatus, @emp_status, @Remarks, @assumption)
                    """, p, tx);
            }
        }

        await audit.LogInTransactionAsync(conn, tx, "masterdata", id,
            wasNew ? "insert" : "update",
            $"{biodata.surname}, {biodata.firstname}");
        return id;
    }

    public async Task<bool> ArchiveAsync(int id)
    {
        await using var conn = await db.OpenAsync();
        var n = await conn.ExecuteAsync(
            "UPDATE masterdata SET archived = 1 WHERE id = @id", new { id });
        if (n > 0) await audit.LogAsync("masterdata", id, "archive");
        return n > 0;
    }

    public async Task<bool> RestoreAsync(int id)
    {
        await using var conn = await db.OpenAsync();
        var n = await conn.ExecuteAsync(
            "UPDATE masterdata SET archived = 0 WHERE id = @id", new { id });
        if (n > 0) await audit.LogAsync("masterdata", id, "restore");
        return n > 0;
    }

    public async Task<string?> GetPhotoPathAsync(int id)
    {
        await using var conn = await db.OpenAsync();
        return await conn.ExecuteScalarAsync<string?>(
            "SELECT photo_path FROM masterdata WHERE id = @id", new { id });
    }

    public async Task SetPhotoPathAsync(int id, string? photoPath)
    {
        await using var conn = await db.OpenAsync();
        await conn.ExecuteAsync(
            "UPDATE masterdata SET photo_path = @photoPath WHERE id = @id", new { id, photoPath });
    }

    public async Task<List<MasterDataSearchRow>> ListArchivedAsync(string? search)
    {
        await using var conn = await db.OpenAsync();
        var rows = await conn.QueryAsync<MasterDataSearchRow>(
            """
            SELECT TOP 500
                m.id AS Id, m.surname AS Surname, m.firstname AS Firstname, m.midname AS Midname,
                m.municipality AS Municipality, m.dbirth AS Dbirth,
                (SELECT TOP 1 a2.status FROM applications a2 WHERE a2.app_id = m.id ORDER BY a2.id DESC) AS LatestStatus
            FROM masterdata m
            WHERE m.archived = 1
              AND (@search IS NULL OR (m.surname + ', ' + m.firstname + ' ' + ISNULL(m.midname,'')) LIKE @searchLike)
            ORDER BY m.surname, m.firstname
            """,
            new
            {
                search = string.IsNullOrWhiteSpace(search) ? null : search.Trim(),
                searchLike = $"%{search?.Trim()}%",
            });
        return rows.ToList();
    }
}
