using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace ApplicantsApi.Features.Reports.Documents;

/// <summary>
/// Acknowledgment letter — faithful reproduction of the old letter.rpt output
/// (Office of the Governor letterhead, same body text, signature block).
/// NOTE: signatory ("Hon. Amado T. Espino, Jr.") and contact lines are carried
/// over from the old template and are outdated — HR should confirm/update.
/// </summary>
public sealed class LetterDocument(ReportRow applicant) : IDocument
{
    public void Compose(IDocumentContainer container)
    {
        container.Page(page =>
        {
            page.Size(PageSizes.A4);
            page.Margin(50);
            page.DefaultTextStyle(t => t.FontSize(11).FontColor("#000000").FontFamily("Times New Roman"));

            page.Header().Element(ReportStyle.GovernorLetterhead);

            page.Content().PaddingTop(10).Column(col =>
            {
                col.Item().Text("Hon. Amado T. Espino, Jr.").FontSize(14).Bold();
                col.Item().PaddingLeft(24).Text("GOVERNOR").FontSize(10);

                col.Item().PaddingTop(24).Text(DateTime.Today.ToString("MMMM dd, yyyy"));

                col.Item().PaddingTop(20).Column(addr =>
                {
                    addr.Item().Text(applicant.FullName).Bold();
                    if (!string.IsNullOrWhiteSpace(applicant.FullAddress))
                    {
                        addr.Item().Text(applicant.FullAddress);
                    }
                    else if (!string.IsNullOrWhiteSpace(applicant.Address))
                    {
                        addr.Item().Text(applicant.Address!.Trim());
                    }
                    if (!string.IsNullOrWhiteSpace(applicant.Municipality))
                    {
                        addr.Item().Text(applicant.Municipality.Trim());
                    }
                });

                col.Item().PaddingTop(24).Text("Greetings!").Italic();

                void Para(string text) => col.Item().PaddingTop(12)
                    .Text(text).Justify().LineHeight(1.3f);

                Para("This is to acknowledge receipt of your application papers expressing " +
                     "your intention to enter the government service.");
                Para("Please be informed that the Provincial Government of Pangasinan has " +
                     "recently undergone reorganization and at present we have enough " +
                     "workforce and we are not in the process of filling-up vacant positions.");
                Para("However, the Human Resource Management and Development Office has " +
                     "initially screened your application papers and should your qualification " +
                     "fit, we may consider you to any opportunity that may become available " +
                     "in the future.");
                Para("Your Papers are now placed among the active files of applicants for " +
                     "our future reference.");
                Para("Our warmest regards.");

                col.Item().PaddingTop(28).Text("Very truly yours,").Bold();
                col.Item().PaddingTop(4).Width(150).Image(ReportStyle.Signature).FitWidth();
                col.Item().PaddingTop(2).Text("AMADO T. ESPINO, JR.").Bold();
            });
        });
    }
}
