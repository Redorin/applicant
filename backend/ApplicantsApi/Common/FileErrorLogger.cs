namespace ApplicantsApi.Common;

/// <summary>
/// Appends unhandled exceptions to a rolling error log under ProgramData so
/// crashes leave a trace on the machine even without a console attached.
/// </summary>
public static class FileErrorLog
{
    private static readonly object Gate = new();

    private static string LogDir => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
        "Applicants Information System");

    public static string CurrentLogPath =>
        Path.Combine(LogDir, $"error-{DateTime.Today:yyyyMM}.log");

    public static void Write(string context, Exception ex)
    {
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(LogDir);
                File.AppendAllText(CurrentLogPath,
                    $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {context}{Environment.NewLine}{ex}{Environment.NewLine}{Environment.NewLine}");
            }
        }
        catch
        {
            // Logging must never take the app down.
        }
    }
}

/// <summary>Catches unhandled request exceptions, logs them to the error
/// file, and returns a clean 500 instead of a stack trace.</summary>
public sealed class ErrorLoggingMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext ctx)
    {
        try
        {
            await next(ctx);
        }
        catch (Exception ex)
        {
            FileErrorLog.Write($"{ctx.Request.Method} {ctx.Request.Path}", ex);
            if (!ctx.Response.HasStarted)
            {
                ctx.Response.StatusCode = 500;
                await ctx.Response.WriteAsJsonAsync(new
                {
                    error = "Something went wrong on the local service. " +
                            "Details were written to the error log.",
                });
            }
        }
    }
}
