using Microsoft.Data.SqlClient;

namespace ApplicantsApi.Data;

/// <summary>Opens connections to the existing Applicants SQL Server Express database.</summary>
public sealed class Db(IConfiguration config)
{
    private readonly string _connectionString = config.GetConnectionString("Applicants")
        ?? throw new InvalidOperationException("Missing ConnectionStrings:Applicants");

    public async Task<SqlConnection> OpenAsync(CancellationToken ct = default)
    {
        var conn = new SqlConnection(_connectionString);
        await conn.OpenAsync(ct);
        return conn;
    }
}
