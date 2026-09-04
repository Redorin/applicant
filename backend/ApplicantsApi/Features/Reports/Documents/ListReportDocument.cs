using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace ApplicantsApi.Features.Reports.Documents;

/// <summary>List of Applicants / Hired Applicants report (replaces
/// CSMainSummary.rpt / CSMainSummaryhired.rpt). Landscape table, optionally
/// grouped by recommending officer or educational attainment.</summary>
public sealed class ListReportDocument(
    string title, string? subtitle, string sortMode, bool hired, List<ReportRow> rows)
    : IDocument
{
    public void Compose(IDocumentContainer container)
    {
        container.Page(page =>
        {
            page.Size(PageSizes.Legal.Landscape());
            page.Margin(28);
            page.DefaultTextStyle(t => t.FontSize(8.2f).FontColor("#000000").FontFamily("Arial"));

            page.Header().Element(c => ReportStyle.Letterhead(c, title));
            page.Footer().Element(c => ReportStyle.Footer(c,
                hired ? "HRMDO-Hired Applicants" : "HRMDO-List of Applicants"));

            page.Content().PaddingTop(10).Column(col =>
            {
                if (!string.IsNullOrWhiteSpace(subtitle))
                {
                    col.Item().PaddingBottom(6).AlignCenter().Text(subtitle!)
                        .FontSize(8f).FontColor(ReportStyle.Muted);
                }

                if (rows.Count == 0)
                {
                    col.Item().PaddingTop(30).AlignCenter()
                        .Text("No records match the selected criteria.")
                        .FontSize(10).FontColor(ReportStyle.Muted);
                    return;
                }

                var groups = sortMode switch
                {
                    "recommendation" => rows
                        .GroupBy(r => string.IsNullOrWhiteSpace(r.Recommendation) ? "(No recommendation)" : r.Recommendation!.Trim())
                        .ToList(),
                    "education" => rows
                        .GroupBy(r => string.IsNullOrWhiteSpace(r.Education) ? "(No education on file)" : r.Education!.Trim())
                        .ToList(),
                    _ => [rows.GroupBy(_ => "").First()],
                };

                var grouped = sortMode is "recommendation" or "education";

                foreach (var group in groups)
                {
                    if (grouped)
                    {
                        col.Item().PaddingTop(8).Row(r =>
                        {
                            r.AutoItem().Border(0.6f).BorderColor(ReportStyle.LightGray)
                                .Background(ReportStyle.Navy)
                                .PaddingVertical(4).PaddingHorizontal(8)
                                .Text($"{group.Key}  ·  {group.Count():N0}")
                                .FontSize(8.6f).Bold().FontColor("#FFFFFF");
                        });
                    }

                    col.Item().PaddingTop(4).Table(table =>
                    {
                        table.ColumnsDefinition(c =>
                        {
                            c.RelativeColumn(2.4f);  // name
                            c.RelativeColumn(1.4f);  // municipality
                            c.RelativeColumn(2.0f);  // position
                            c.RelativeColumn(2.2f);  // department
                            c.RelativeColumn(1.1f);  // date applied
                            c.RelativeColumn(1.3f);  // status
                            c.RelativeColumn(1.8f);  // recommendation
                            c.RelativeColumn(1.9f);  // education
                            if (hired)
                            {
                                c.RelativeColumn(1.1f);  // date hired
                                c.RelativeColumn(1.8f);  // final position
                                c.RelativeColumn(1.2f);  // emp status
                            }
                        });

                        table.Header(h =>
                        {
                            void Th(string label) => h.Cell().HeaderCell()
                                .Text(label).FontSize(7.2f).Bold().FontColor("#FFFFFF");
                            Th("NAME"); Th("MUNICIPALITY"); Th("POSITION APPLIED");
                            Th("OFFICE / DEPARTMENT"); Th("DATE APPLIED");
                            Th(hired ? "FINAL STATUS" : "STATUS"); Th("RECOMMENDATION"); Th("EDUCATION");
                            if (hired) { Th("DATE HIRED"); Th("FINAL POSITION"); Th("EMP. STATUS"); }
                        });

                        var rowIndex = 0;
                        foreach (var r in group)
                        {
                            var isOdd = rowIndex % 2 == 1;
                            void Td(string text) => table.Cell().BodyCell(isOdd).Text(text);
                            Td(r.FullName);
                            Td(ReportStyle.S(r.Municipality));
                            Td(ReportStyle.S(r.Position));
                            Td(ReportStyle.S(r.Department));
                            Td(ReportStyle.D(r.AppDate));
                            Td(hired ? ReportStyle.S(r.FinalStatus) : ReportStyle.S(r.Status));
                            Td(ReportStyle.S(r.Recommendation));
                            Td(ReportStyle.S(r.Education));
                            if (hired)
                            {
                                Td(ReportStyle.D(r.HiredDate));
                                Td(ReportStyle.S(r.FinalPosition));
                                Td(ReportStyle.S(r.EmpStatus));
                            }
                            rowIndex++;
                        }
                    });
                }

                col.Item().PaddingTop(10).AlignRight()
                    .Text($"Total records: {rows.Count:N0}")
                    .FontSize(8.6f).Bold();
            });
        });
    }
}
