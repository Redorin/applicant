using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace ApplicantsApi.Features.Reports.Documents;

/// <summary>Single-applicant profile sheet (replaces Resumes.rpt).</summary>
public sealed class ResumeDocument(ReportRow applicant, List<ReportRow> applications) : IDocument
{
    public void Compose(IDocumentContainer container)
    {
        container.Page(page =>
        {
            page.Size(PageSizes.A4);
            page.Margin(40);
            page.DefaultTextStyle(t => t.FontSize(9.4f).FontColor("#000000").FontFamily("Arial"));

            page.Header().Element(c => ReportStyle.LetterheadClean(c, "Applicant Profile"));
            page.Footer().Element(c => ReportStyle.Footer(c, "HRMDO-Applicant Profile"));

            page.Content().PaddingTop(14).Column(col =>
            {
                col.Item().Text(applicant.FullName).FontSize(14).Bold().FontColor(ReportStyle.Navy);

                void Section(string title) => col.Item().PaddingTop(12).Column(s =>
                {
                    s.Item().Text(title.ToUpperInvariant())
                        .FontSize(8f).Bold().FontColor(ReportStyle.Navy).LetterSpacing(0.08f);
                    s.Item().PaddingTop(2).LineHorizontal(0.8f).LineColor(ReportStyle.Navy);
                });

                void Field(string label, string? value) => col.Item().PaddingTop(4).Row(r =>
                {
                    r.ConstantItem(140).Text(label).FontColor(ReportStyle.Muted).FontSize(8.6f);
                    r.RelativeItem().Text(ReportStyle.S(value)).FontSize(9.2f);
                });

                Section("Personal Information");
                Field("Date of birth", applicant.Dbirth?.ToString("MMMM dd, yyyy"));
                Field("Gender", applicant.Gender);
                Field("Civil status", applicant.Civistat);
                Field("District", applicant.District);
                Field("Address", applicant.FullAddress);
                Field("Contact", applicant.Contact);
                if (!string.IsNullOrWhiteSpace(applicant.Contact2))
                    Field("Alt. contact", applicant.Contact2);

                Section("Education");
                Field("Highest education", applicant.Education);
                if (!string.IsNullOrWhiteSpace(applicant.Education2))
                    Field("Graduate studies", applicant.Education2);
                if (!string.IsNullOrWhiteSpace(applicant.School))
                    Field("School", applicant.School);

                Section("Qualifications");
                Field("Eligibility", applicant.Eligibility);
                if (!string.IsNullOrWhiteSpace(applicant.Experience))
                    Field("Work experience", applicant.Experience);
                if (!string.IsNullOrWhiteSpace(applicant.Skills))
                    Field("Skills", applicant.Skills);
                if (!string.IsNullOrWhiteSpace(applicant.Training))
                    Field("Training", applicant.Training);
                if (!string.IsNullOrWhiteSpace(applicant.Lenofservice))
                    Field("Length of service", applicant.Lenofservice);

                if (!string.IsNullOrWhiteSpace(applicant.Notes))
                {
                    Section("Additional Notes");
                    col.Item().PaddingTop(4).Text(applicant.Notes).FontSize(8.8f);
                }

                Section("Application History");
                if (applications.Count == 0)
                {
                    col.Item().PaddingTop(4).Text("No applications on record.")
                        .FontColor(ReportStyle.Muted).FontSize(8.8f);
                }
                else
                {
                    col.Item().PaddingTop(6).Table(table =>
                    {
                        table.ColumnsDefinition(c =>
                        {
                            c.RelativeColumn(1.1f);
                            c.RelativeColumn(2.0f);
                            c.RelativeColumn(2.2f);
                            c.RelativeColumn(1.3f);
                            c.RelativeColumn(1.8f);
                            c.RelativeColumn(1.1f);
                        });
                        table.Header(h =>
                        {
                            void Th(string label) => h.Cell()
                                .Background(ReportStyle.Surface2)
                                .BorderBottom(0.8f).BorderColor(ReportStyle.Navy)
                                .PaddingVertical(4).PaddingHorizontal(5)
                                .Text(label).FontSize(7.4f).Bold().FontColor(ReportStyle.Navy);
                            Th("DATE"); Th("POSITION"); Th("OFFICE"); Th("STATUS"); Th("RECOMMENDATION"); Th("HIRED");
                        });
                        var idx = 0;
                        foreach (var a in applications)
                        {
                            var isOdd = idx % 2 == 1;
                            void Td(string text) => table.Cell()
                                .BorderBottom(0.4f).BorderColor(ReportStyle.LightGray)
                                .PaddingVertical(3.5f).PaddingHorizontal(5)
                                .Background(isOdd ? ReportStyle.ZebraStripe : Colors.White)
                                .Text(text).FontSize(8.4f);
                            Td(ReportStyle.D(a.AppDate));
                            Td(ReportStyle.S(a.Position));
                            Td(ReportStyle.S(a.Department));
                            Td(ReportStyle.S(a.Status));
                            Td(ReportStyle.S(a.Recommendation));
                            Td(ReportStyle.D(a.HiredDate));
                            idx++;
                        }
                    });
                }
            });
        });
    }
}
