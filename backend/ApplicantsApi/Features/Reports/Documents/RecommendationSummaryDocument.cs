using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace ApplicantsApi.Features.Reports.Documents;

/// <summary>
/// Faithful reproduction of the old RecSummary.rpt: HRMDO letterhead, a
/// Requests|Hired column pair per year plus a bold Total pair, bordered grid,
/// officers alphabetical.
/// </summary>
public sealed class RecommendationSummaryDocument(
    int yearFrom, int yearTo, List<OfficerYearRow> rows) : IDocument
{
    public void Compose(IDocumentContainer container)
    {
        var years = Enumerable.Range(yearFrom, yearTo - yearFrom + 1).ToList();
        var officers = rows.Select(r => r.Officer).Distinct()
            .OrderBy(o => o, StringComparer.OrdinalIgnoreCase).ToList();
        var lookup = rows.ToDictionary(r => (r.Officer, r.Year));

        container.Page(page =>
        {
            page.Size(years.Count > 5 ? PageSizes.Legal.Landscape() : PageSizes.A4.Landscape());
            page.Margin(30);
            page.DefaultTextStyle(t => t.FontSize(8.4f).FontColor("#000000").FontFamily("Arial"));

            page.Header().Element(c => ReportStyle.Letterhead(
                c, "Client Satisfaction Rating and Ranking Summary Report"));
            page.Footer().Element(c => ReportStyle.Footer(c, "HRMDO-List of Applicants"));

            page.Content().PaddingTop(12).Column(col =>
            {
                if (officers.Count == 0)
                {
                    col.Item().PaddingTop(28).AlignCenter()
                        .Text("No recommendations found for the selected officers and years.")
                        .FontSize(10);
                    return;
                }

                col.Item().Table(table =>
                {
                    table.ColumnsDefinition(c =>
                    {
                        c.RelativeColumn(2.6f);                    // officer
                        foreach (var _ in years)
                        {
                            c.RelativeColumn(0.62f);               // requests
                            c.RelativeColumn(0.52f);               // hired
                        }
                        c.RelativeColumn(0.66f);                   // total requests
                        c.RelativeColumn(0.56f);                   // total hired
                    });

                    table.Header(h =>
                    {
                        // Year band row.
                        h.Cell().RowSpan(2).HeaderCell().AlignMiddle().Text("");
                        foreach (var y in years)
                        {
                            h.Cell().ColumnSpan(2).HeaderCell().AlignCenter()
                                .Text($"{y}").Bold();
                        }
                        h.Cell().ColumnSpan(2).HeaderCell().AlignCenter()
                            .Text("Total").Bold();

                        // Requests | Hired sub-row.
                        foreach (var _ in Enumerable.Range(0, years.Count + 1))
                        {
                            h.Cell().HeaderCell().AlignCenter().Text("Requests").FontSize(7.2f).Bold();
                            h.Cell().HeaderCell().AlignCenter().Text("Hired").FontSize(7.2f).Bold();
                        }
                    });

                    foreach (var officer in officers)
                    {
                        var isOdd = officers.IndexOf(officer) % 2 == 1;
                        table.Cell().BodyCell(isOdd).Text(officer).Bold();
                        var totalReq = 0;
                        var totalHired = 0;
                        foreach (var y in years)
                        {
                            var found = lookup.TryGetValue((officer, y), out var r);
                            var req = found ? r!.Requested : 0;
                            var hired = found ? r!.Hired : 0;
                            totalReq += req;
                            totalHired += hired;
                            table.Cell().BodyCell(isOdd).AlignCenter().Text($"{req}");
                            table.Cell().BodyCell(isOdd).AlignCenter().Text($"{hired}");
                        }
                        table.Cell().BodyCell(isOdd).AlignCenter().Text($"{totalReq}").Bold();
                        table.Cell().BodyCell(isOdd).AlignCenter().Text($"{totalHired}").Bold();
                    }
                });
            });
        });
    }
}
