using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace ApplicantsApi.Features.Reports.Documents;

/// <summary>
/// Compact one-page reference card — a quick-print summary distinct from the
/// full Resume (biodata + entire application history table): just the
/// person's key facts and their single most recent application, sized to
/// staple to physical papers or hand someone at the counter.
/// </summary>
public sealed class CardDocument(ReportRow applicant) : IDocument
{
    public void Compose(IDocumentContainer container)
    {
        container.Page(page =>
        {
            page.Size(PageSizes.A5.Landscape());
            page.Margin(28);
            page.DefaultTextStyle(t => t.FontSize(9f).FontColor("#000000").FontFamily("Arial"));

            page.Header().Element(c => ReportStyle.Letterhead(c, "Applicant Card"));
            page.Footer().Element(c => ReportStyle.Footer(c, "HRMDO-Applicant Card"));

            page.Content().PaddingTop(10).Column(col =>
            {
                col.Item().Text(applicant.FullName).FontSize(15).Bold();
                if (applicant.Dbirth is not null)
                {
                    col.Item().Text($"{Age(applicant.Dbirth.Value)} years old · Born {ReportStyle.D(applicant.Dbirth)}")
                        .FontSize(8.4f).FontColor(ReportStyle.Muted);
                }

                col.Item().PaddingTop(8).LineHorizontal(0.8f).LineColor("#000000");

                void Field(string label, string? value) => col.Item().PaddingTop(4).Row(r =>
                {
                    r.ConstantItem(90).Text(label).FontColor(ReportStyle.Muted).FontSize(8f);
                    r.RelativeItem().Text(ReportStyle.S(value)).FontSize(8.8f);
                });

                Field("Contact", applicant.Contact);
                Field("Address", applicant.Address);
                Field("Municipality", string.Join(" · ",
                    new[] { applicant.Municipality, applicant.District }.Where(s => !string.IsNullOrWhiteSpace(s))));
                Field("Education", applicant.Education);
                Field("Eligibility", applicant.Eligibility);

                col.Item().PaddingTop(10).Background(ReportStyle.Surface2).Padding(8).Column(app =>
                {
                    app.Item().Text("MOST RECENT APPLICATION")
                        .FontSize(7.6f).Bold().FontColor(ReportStyle.Muted).LetterSpacing(0.06f);
                    if (applicant.Position is null && applicant.AppDate is null)
                    {
                        app.Item().PaddingTop(3).Text("No applications on record.")
                            .FontColor(ReportStyle.Muted).FontSize(8.6f);
                    }
                    else
                    {
                        app.Item().PaddingTop(3).Row(r =>
                        {
                            r.RelativeItem().Text(ReportStyle.S(applicant.Position)).Bold().FontSize(10);
                            r.ConstantItem(110).AlignRight().Text(ReportStyle.S(applicant.Status)).FontSize(9);
                        });
                        app.Item().Text(ReportStyle.S(applicant.Department)).FontSize(8.6f);
                        app.Item().PaddingTop(3).Row(r =>
                        {
                            r.RelativeItem().Text($"Applied: {ReportStyle.D(applicant.AppDate)}").FontSize(8);
                            r.RelativeItem().Text(applicant.HiredDate is null
                                ? "" : $"Hired: {ReportStyle.D(applicant.HiredDate)}").FontSize(8);
                        });
                    }
                });
            });
        });
    }

    private static int Age(DateTime dbirth)
    {
        var today = DateTime.Today;
        var age = today.Year - dbirth.Year;
        if (today.Month < dbirth.Month || (today.Month == dbirth.Month && today.Day < dbirth.Day)) age--;
        return age;
    }
}
