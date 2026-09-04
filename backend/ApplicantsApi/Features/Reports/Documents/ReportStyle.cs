using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace ApplicantsApi.Features.Reports.Documents;

/// <summary>
/// Shared letterhead/footer matching the old Crystal Reports output:
/// provincial seal left, Pangasinan map right, centered office block,
/// and the old "Source: …" / "HRMDO-…" footer.
/// </summary>
public static class ReportStyle
{
    public const string Navy = "#1E2F4D";
    public const string Ink = "#1C2433";
    public const string Muted = "#5C6579";
    public const string Line = "#9AA1AD";
    public const string Surface2 = "#F6F8FB";
    public const string LightGray = "#D0D5DD";
    public const string ZebraStripe = "#F8FAFC";

    private static readonly string AssetDir =
        Path.Combine(AppContext.BaseDirectory, "Features", "Reports", "Assets");

    public static byte[] Seal { get; } =
        File.ReadAllBytes(Path.Combine(AssetDir, "provincial-seal.png"));
    public static byte[] Map { get; } =
        File.ReadAllBytes(Path.Combine(AssetDir, "pangasinan-map.png"));
    public static byte[] Signature { get; } =
        File.ReadAllBytes(Path.Combine(AssetDir, "governor-signature.png"));

    /// <summary>HRMDO letterhead (used by the list/summary reports).</summary>
    public static void Letterhead(IContainer container, string reportTitle)
    {
        container.Column(col =>
        {
            col.Item().Row(row =>
            {
                row.ConstantItem(64).AlignTop().Height(64).Image(Seal).FitArea();
                row.RelativeItem().AlignCenter().Column(c =>
                {
                    c.Item().AlignCenter().Text("Republic of the Philippines").FontSize(8.5f);
                    c.Item().PaddingTop(2).AlignCenter().Text("PROVINCE OF PANGASINAN").FontSize(12).Bold();
                    c.Item().PaddingTop(1).AlignCenter().Text("HUMAN RESOURCE MANAGEMENT AND DEVELOPMENT OFFICE")
                        .FontSize(10).Bold();
                    c.Item().PaddingTop(1).AlignCenter().Text("Lingayen, Pangasinan").FontSize(8.5f);
                    c.Item().PaddingTop(6).AlignCenter().Text(reportTitle.ToUpperInvariant())
                        .FontSize(10).Bold().FontColor("#FFFFFF").BackgroundColor(Navy);
                });
                row.ConstantItem(64).AlignTop().Height(44).Image(Map).FitArea();
            });
            col.Item().PaddingTop(4).LineHorizontal(1.5f).LineColor(Navy);
        });
    }

    /// <summary>Clean letterhead without banner — used by resume/profile reports.</summary>
    public static void LetterheadClean(IContainer container, string reportTitle)
    {
        container.Column(col =>
        {
            col.Item().Row(row =>
            {
                row.ConstantItem(64).AlignTop().Height(64).Image(Seal).FitArea();
                row.RelativeItem().AlignCenter().Column(c =>
                {
                    c.Item().AlignCenter().Text("Republic of the Philippines").FontSize(8.5f);
                    c.Item().PaddingTop(2).AlignCenter().Text("PROVINCE OF PANGASINAN").FontSize(12).Bold();
                    c.Item().PaddingTop(1).AlignCenter().Text("HUMAN RESOURCE MANAGEMENT AND DEVELOPMENT OFFICE")
                        .FontSize(10).Bold();
                    c.Item().PaddingTop(1).AlignCenter().Text("Lingayen, Pangasinan").FontSize(8.5f);
                    c.Item().PaddingTop(6).AlignCenter().Text(reportTitle.ToUpperInvariant())
                        .FontSize(10).Bold().FontColor(Navy);
                });
                row.ConstantItem(64).AlignTop().Height(44).Image(Map).FitArea();
            });
            col.Item().PaddingTop(4).LineHorizontal(1.5f).LineColor(Navy);
        });
    }

    /// <summary>Office of the Governor letterhead (used by the Letter).</summary>
    public static void GovernorLetterhead(IContainer container)
    {
        container.Column(col =>
        {
            col.Item().Row(row =>
            {
                row.ConstantItem(70).AlignTop().Height(70).Image(Seal).FitArea();
                row.RelativeItem().AlignCenter().Column(c =>
                {
                    c.Item().AlignCenter().Text("Provincial Government of Pangasinan")
                        .FontSize(9).FontFamily("Times New Roman");
                    c.Item().AlignCenter().Text("Province of Pangasinan")
                        .FontSize(9).FontFamily("Times New Roman");
                    c.Item().PaddingTop(2).AlignCenter().Text("Office of the Governor")
                        .FontSize(18).Bold().FontFamily("Times New Roman");
                    c.Item().PaddingTop(1).AlignCenter().Text("Capitol Compound, Lingayen, Pangasinan")
                        .FontSize(9).FontFamily("Times New Roman");
                    c.Item().PaddingTop(1).AlignCenter()
                        .Text("Telefax: 075-662-1001; Digitel 075-542-6012 / 075-5426013 / 075-542-3578")
                        .FontSize(8).FontFamily("Times New Roman");
                    c.Item().AlignCenter().Text("Email Address: govespino@yahoo.com")
                        .FontSize(8).FontFamily("Times New Roman");
                });
                row.ConstantItem(70).AlignTop().PaddingTop(4).Height(46).Image(Map).FitArea();
            });
            col.Item().PaddingTop(4).LineHorizontal(2.2f).LineColor(Navy);
        });
    }

    /// <summary>Old-style footer: long date + source line left, page + report tag right.</summary>
    public static void Footer(IContainer container, string reportTag)
    {
        container.Row(row =>
        {
            row.RelativeItem().Column(c =>
            {
                c.Item().Text(DateTime.Today.ToString("dddd, MMMM dd, yyyy"))
                    .FontSize(7.5f).FontColor(Muted);
                c.Item().Text("Source: Applicants Information System Generated Report")
                    .FontSize(7.5f).FontColor(Muted);
            });
            row.ConstantItem(140).AlignRight().Column(c =>
            {
                c.Item().AlignRight().Text(t =>
                {
                    t.Span("Page ").FontSize(7.5f).FontColor(Muted);
                    t.CurrentPageNumber().FontSize(7.5f).FontColor(Muted);
                    t.Span(" of ").FontSize(7.5f).FontColor(Muted);
                    t.TotalPages().FontSize(7.5f).FontColor(Muted);
                });
                c.Item().AlignRight().Text(reportTag).FontSize(7.5f).FontColor(Muted);
            });
        });
    }

    // Bordered grid cells, as in the old Crystal tables.
    public static IContainer HeaderCell(this IContainer c) => c
        .Border(0.6f).BorderColor(LightGray)
        .Background(Navy)
        .PaddingVertical(4).PaddingHorizontal(5);

    public static IContainer HeaderCellWhite(this IContainer c) => c
        .Border(0.6f).BorderColor(LightGray)
        .Background(Navy)
        .PaddingVertical(4).PaddingHorizontal(5);

    public static IContainer BodyCell(this IContainer c, bool isOdd = false) => c
        .Border(0.4f).BorderColor(LightGray)
        .Background(isOdd ? ZebraStripe : Colors.White)
        .PaddingVertical(3.5f).PaddingHorizontal(5);

    public static string D(DateTime? d) => d is null ? "—" : d.Value.ToString("MM/dd/yyyy");
    public static string S(string? s) => string.IsNullOrWhiteSpace(s) ? "—" : s.Trim();
}
