using System.Collections.Concurrent;
using System.Security.Cryptography;
using ApplicantsApi.Data;
using ApplicantsApi.Features.AuditLog;
using Dapper;

namespace ApplicantsApi.Features.Auth;

public record LoginRequest(string Username, string Password);
public record LoginResponse(string Token, string FullName);
public record ChangePasswordRequest(string CurrentPassword, string NewPassword);
public record UpdateProfileRequest(string FirstName, string LastName);

/// <summary>
/// Stage-2 auth: a real per-user account table (six named office accounts,
/// all with equal access — no roles). Replaces the single shared office
/// credential that used to live in configuration.
/// </summary>
public sealed class SessionStore
{
    public sealed record Session(string Username, string FullName, DateTimeOffset IssuedAt);

    private readonly ConcurrentDictionary<string, Session> _tokens = new();

    public string Issue(string username, string fullName)
    {
        var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
        _tokens[token] = new Session(username, fullName, DateTimeOffset.UtcNow);
        return token;
    }

    public bool IsValid(string token) => _tokens.ContainsKey(token);

    /// <summary>Username of the account holding this token, or null if the
    /// token is missing/expired — used by AuditLogService to record who did
    /// what instead of a fabricated shared identity.</summary>
    public string? UsernameFor(string token) =>
        _tokens.TryGetValue(token, out var s) ? s.Username : null;

    public void Revoke(string token) => _tokens.TryRemove(token, out _);
}

public static class AuthEndpoints
{
    public static void MapAuth(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/auth");

        group.MapPost("/login", async (
            LoginRequest req, Db db, SessionStore sessions, AuditLogService audit) =>
        {
            var username = req.Username?.Trim() ?? "";
            await using var conn = await db.OpenAsync();
            var user = await conn.QuerySingleOrDefaultAsync<(string Username, string PasswordHash, string FullName)?>(
                "SELECT username AS Username, password_hash AS PasswordHash, full_name AS FullName " +
                "FROM users WHERE username = @username",
                new { username });

            if (user is null || !BCrypt.Net.BCrypt.Verify(req.Password ?? "", user.Value.PasswordHash))
            {
                await audit.LogAsync("auth", 0, "login_failed", username, overrideChangedBy: username);
                return Results.Json(new { error = "Incorrect username or password." }, statusCode: 401);
            }

            var token = sessions.Issue(user.Value.Username, user.Value.FullName);
            await audit.LogAsync("auth", 0, "login", overrideChangedBy: user.Value.Username);
            return Results.Ok(new LoginResponse(token, user.Value.FullName));
        });

        group.MapPost("/logout", async (HttpContext ctx, SessionStore sessions, AuditLogService audit) =>
        {
            string? username = null;
            if (ctx.Request.Headers.TryGetValue("X-Session-Token", out var token))
            {
                username = sessions.UsernameFor(token.ToString());
                sessions.Revoke(token.ToString());
            }
            await audit.LogAsync("auth", 0, "logout", overrideChangedBy: username);
            return Results.NoContent();
        });

        // Both routes below live under /api/auth, which SessionAuthMiddleware
        // deliberately exempts from its token check (see the middleware
        // below) — so unlike every other endpoint in the app, these two
        // resolve and validate the session token themselves.
        group.MapPost("/change-password", async (
            ChangePasswordRequest req, HttpContext ctx, Db db, SessionStore sessions, AuditLogService audit) =>
        {
            if (!ctx.Request.Headers.TryGetValue("X-Session-Token", out var token) ||
                sessions.UsernameFor(token.ToString()) is not { } username)
            {
                return Results.Json(new { error = "Not signed in." }, statusCode: 401);
            }

            if (string.IsNullOrWhiteSpace(req.NewPassword) || req.NewPassword.Length < 6)
            {
                return Results.Json(new { error = "New password must be at least 6 characters." }, statusCode: 422);
            }

            await using var conn = await db.OpenAsync();
            var currentHash = await conn.QuerySingleOrDefaultAsync<string?>(
                "SELECT password_hash FROM users WHERE username = @username", new { username });
            if (currentHash is null || !BCrypt.Net.BCrypt.Verify(req.CurrentPassword ?? "", currentHash))
            {
                return Results.Json(new { error = "Current password is incorrect." }, statusCode: 401);
            }

            var newHash = BCrypt.Net.BCrypt.HashPassword(req.NewPassword);
            await conn.ExecuteAsync(
                "UPDATE users SET password_hash = @newHash WHERE username = @username",
                new { newHash, username });
            await audit.LogAsync("auth", 0, "change_password", username);
            return Results.NoContent();
        });

        group.MapPut("/profile", async (
            UpdateProfileRequest req, HttpContext ctx, Db db, SessionStore sessions, AuditLogService audit) =>
        {
            if (!ctx.Request.Headers.TryGetValue("X-Session-Token", out var token) ||
                sessions.UsernameFor(token.ToString()) is not { } username)
            {
                return Results.Json(new { error = "Not signed in." }, statusCode: 401);
            }

            var firstName = (req.FirstName ?? "").Trim();
            var lastName = (req.LastName ?? "").Trim();
            if (firstName.Length == 0 || lastName.Length == 0)
            {
                return Results.Json(new { error = "First and last name are required." }, statusCode: 422);
            }

            var fullName = $"{firstName} {lastName}";
            await using var conn = await db.OpenAsync();
            await conn.ExecuteAsync(
                "UPDATE users SET full_name = @fullName WHERE username = @username",
                new { fullName, username });
            await audit.LogAsync("auth", 0, "update_profile", username);
            return Results.Ok(new { fullName });
        });
    }
}

/// <summary>Requires a valid X-Session-Token header on everything except /api/auth/* and /health.</summary>
public sealed class SessionAuthMiddleware(RequestDelegate next, SessionStore sessions)
{
    public async Task InvokeAsync(HttpContext ctx)
    {
        var path = ctx.Request.Path;
        if (path.StartsWithSegments("/api/auth") || path.StartsWithSegments("/health"))
        {
            await next(ctx);
            return;
        }

        if (!ctx.Request.Headers.TryGetValue("X-Session-Token", out var token) ||
            !sessions.IsValid(token.ToString()))
        {
            ctx.Response.StatusCode = 401;
            await ctx.Response.WriteAsJsonAsync(new { error = "Not signed in." });
            return;
        }

        await next(ctx);
    }
}
