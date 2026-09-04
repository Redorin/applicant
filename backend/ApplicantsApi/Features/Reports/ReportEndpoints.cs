using ApplicantsApi.Features.AuditLog;
using ApplicantsApi.Features.Reports.Documents;
using QuestPDF.Fluent;

namespace ApplicantsApi.Features.Reports;

public static class ReportEndpoints
{
    public static void MapReports(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/reports");

        group.MapPost("/list", async (ListReportRequest req, ReportQueries queries, AuditLogService audit) =>
        {
            var rows = await queries.QueryRowsAsync(req, hiredOnly: false);
            var doc = new ListReportDocument(
                string.IsNullOrWhiteSpace(req.Title) ? "Report on Status of Application" : req.Title!,
                Subtitle(req), req.SortMode ?? "original", hired: false, rows);
            await audit.LogAsync("report", 0, "generate", "List of applicants");
            return Results.File(doc.GeneratePdf(), "application/pdf", "list-of-applicants.pdf");
        });

        group.MapPost("/hired", async (ListReportRequest req, ReportQueries queries, AuditLogService audit) =>
        {
            var rows = await queries.QueryRowsAsync(req, hiredOnly: true);
            var doc = new ListReportDocument(
                string.IsNullOrWhiteSpace(req.Title) ? "Monthly Employment Report" : req.Title!,
                Subtitle(req), req.SortMode ?? "original", hired: true, rows);
            await audit.LogAsync("report", 0, "generate", "Hired applicants");
            return Results.File(doc.GeneratePdf(), "application/pdf", "hired-applicants.pdf");
        });

        group.MapPost("/recommendation-summary", async (
            RecommendationSummaryRequest req, ReportQueries queries, AuditLogService audit) =>
        {
            var rows = await queries.QueryOfficerYearMatrixAsync(req);
            var doc = new RecommendationSummaryDocument(req.YearFrom, req.YearTo, rows);
            await audit.LogAsync("report", 0, "generate",
                $"Recommendation summary ({req.YearFrom}-{req.MonthFrom:D2} to {req.YearTo}-{req.MonthTo:D2})");
            return Results.File(doc.GeneratePdf(), "application/pdf", "recommendation-summary.pdf");
        });

        group.MapGet("/resume/{id:int}", async (int id, ReportQueries queries, AuditLogService audit) =>
        {
            var (applicant, applications) = await queries.QueryApplicantWithHistoryAsync(id);
            if (applicant is null) return Results.NotFound();
            var doc = new ResumeDocument(applicant, applications);
            await audit.LogAsync("report", id, "generate", "Resume");
            return Results.File(doc.GeneratePdf(), "application/pdf", "resume.pdf");
        });

        group.MapGet("/letter/{id:int}", async (int id, ReportQueries queries, AuditLogService audit) =>
        {
            var applicant = await queries.QuerySingleApplicantAsync(id);
            if (applicant is null) return Results.NotFound();
            var doc = new LetterDocument(applicant);
            await audit.LogAsync("report", id, "generate", "Letter");
            return Results.File(doc.GeneratePdf(), "application/pdf", "letter.pdf");
        });

        group.MapGet("/card/{id:int}", async (int id, ReportQueries queries, AuditLogService audit) =>
        {
            var applicant = await queries.QuerySingleApplicantAsync(id);
            if (applicant is null) return Results.NotFound();
            var doc = new CardDocument(applicant);
            await audit.LogAsync("report", id, "generate", "Card");
            return Results.File(doc.GeneratePdf(), "application/pdf", "card.pdf");
        });
    }

    private static string? Subtitle(ListReportRequest req)
    {
        var parts = new List<string>();
        if (req.DateFrom is not null || req.DateTo is not null)
        {
            parts.Add($"Applications {req.DateFrom:MMM dd, yyyy} – {req.DateTo:MMM dd, yyyy}");
        }
        if (req.HiredFrom is not null || req.HiredTo is not null)
        {
            parts.Add($"Hired {req.HiredFrom:MMM dd, yyyy} – {req.HiredTo:MMM dd, yyyy}");
        }
        if (!string.IsNullOrWhiteSpace(req.Recommendation)) parts.Add($"Recommendation: {req.Recommendation}");
        if (!string.IsNullOrWhiteSpace(req.Position)) parts.Add($"Position: {req.Position}");
        if (!string.IsNullOrWhiteSpace(req.Department)) parts.Add($"Department: {req.Department}");
        if (!string.IsNullOrWhiteSpace(req.Education)) parts.Add($"Education: {req.Education}");
        if (!string.IsNullOrWhiteSpace(req.Status)) parts.Add($"Status: {req.Status}");
        return parts.Count == 0 ? "All applicants" : string.Join("  ·  ", parts);
    }
}
