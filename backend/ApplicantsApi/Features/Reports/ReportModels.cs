namespace ApplicantsApi.Features.Reports;

/// <summary>Criteria for the List / Hired reports. Text fields support
/// slash-delimited alternatives ("Nurse/Midwife" → OR of LIKEs), matching the
/// old criteria grid's convention.</summary>
public record ListReportRequest(
    string? Title,
    string? SortMode,        // "original" | "recommendation" | "education"
    DateTime? DateFrom,
    DateTime? DateTo,
    string? Recommendation,
    string? Position,
    string? Department,
    string? Education,
    string? Status,
    DateTime? HiredFrom,     // hired report only
    DateTime? HiredTo);

public record RecommendationSummaryRequest(
    List<string>? Officers,  // empty/null = all officers
    int YearFrom,
    int YearTo,
    int MonthFrom = 1,
    int MonthTo = 12);

/// <summary>One applicant+application row feeding the List/Hired layouts —
/// the same field set the old Crystal reports pulled.</summary>
public record ReportRow(
    string? Surname,
    string? Firstname,
    string? Midname,
    string? Ext,
    DateTime? Dbirth,
    string? Gender,
    string? Civistat,
    string? Address,
    string? HouseNo,
    string? Street,
    string? Subdivision,
    string? Barangay,
    string? Municipality,
    string? District,
    string? Province,
    string? Education,
    string? Education2,
    string? School,
    string? Eligibility,
    string? Contact,
    string? Contact2,
    string? Experience,
    string? Skills,
    string? Training,
    string? Lenofservice,
    string? Personincharge,
    string? Notes,
    DateTime? AppDate,
    string? Position,
    string? Department,
    string? Status,
    DateTime? IntvwDate,
    string? Recommendation,
    DateTime? HiredDate,
    string? FinalPosition,
    string? FinalDepartment,
    string? FinalStatus,
    string? EmpStatus,
    string? Remarks)
{
    public string FullName =>
        $"{(Surname ?? "").Trim()}, {(Firstname ?? "").Trim()}" +
        (string.IsNullOrWhiteSpace(Midname) ? "" : $" {Midname.Trim()}") +
        (string.IsNullOrWhiteSpace(Ext) ? "" : $" {Ext.Trim()}");

    public string FullAddress
    {
        get
        {
            var parts = new List<string>();
            if (!string.IsNullOrWhiteSpace(HouseNo)) parts.Add(HouseNo.Trim());
            if (!string.IsNullOrWhiteSpace(Street)) parts.Add(Street.Trim());
            if (!string.IsNullOrWhiteSpace(Subdivision)) parts.Add(Subdivision.Trim());
            if (!string.IsNullOrWhiteSpace(Barangay)) parts.Add($"Brgy. {Barangay.Trim()}");
            if (!string.IsNullOrWhiteSpace(Municipality)) parts.Add(Municipality.Trim());
            if (!string.IsNullOrWhiteSpace(Province)) parts.Add(Province.Trim());
            return parts.Count == 0 ? (Address ?? "").Trim() : string.Join(", ", parts);
        }
    }
}

public record OfficerSummaryRow(string Officer, int Requested, int Hired);

/// <summary>Per-officer, per-year counts feeding the old report's
/// year-column matrix (Requests | Hired per year + Total pair).</summary>
public record OfficerYearRow(string Officer, int Year, int Requested, int Hired);
