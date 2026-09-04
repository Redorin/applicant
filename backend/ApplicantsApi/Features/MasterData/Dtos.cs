namespace ApplicantsApi.Features.MasterData;

/// <summary>One row in search results (browse/pick an applicant).</summary>
public record MasterDataSearchRow(
    int Id,
    string? Surname,
    string? Firstname,
    string? Midname,
    string? Municipality,
    DateTime? Dbirth,
    string? LatestStatus);

/// <summary>A job application row belonging to an applicant.</summary>
public record ApplicationDto(
    int? Id,                 // null/0 = new row on save
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
    string? Remarks,
    DateTime? Assumption);

/// <summary>Full applicant detail: biodata + eligibilities + applications.</summary>
public record MasterDataDetail(
    int Id,
    string? Surname,
    string? Firstname,
    string? Midname,
    string? Ext,
    DateTime? Dbirth,
    string? Gender,
    string? Civistat,
    string? Contact,
    string? Contact2,
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
    string? LegacyEligibility,
    string? Experience,
    string? Skills,
    string? Personincharge,
    string? Notes,
    string? Lenofservice,
    string? Training,
    string? PhotoPath,
    List<string> Eligibilities,
    List<ApplicationDto> Applications);

/// <summary>Outcome of one row from a bulk import.</summary>
public record MasterDataImportResult(
    int RowNumber,
    bool Success,
    int? Id,
    bool Duplicate,
    List<string> Errors);

/// <summary>Save payload — same shape for create (id null/0) and update.</summary>
public record MasterDataSaveRequest(
    int? Id,
    string? Surname,
    string? Firstname,
    string? Midname,
    string? Ext,
    DateTime? Dbirth,
    string? Gender,
    string? Civistat,
    string? Contact,
    string? Contact2,
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
    string? LegacyEligibility,
    string? Experience,
    string? Skills,
    string? Personincharge,
    string? Notes,
    string? Lenofservice,
    string? Training,
    string? PhotoPath,
    List<string>? Eligibilities,
    List<ApplicationDto>? Applications);
