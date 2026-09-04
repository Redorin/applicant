# Applicants database backup

Full verified backup of the `Applicants` database (SQL Server `.\SQLEXPRESS`), taken 2026-07-17.
All three HRMDO systems (original compiled app, updated WinForms, Flutter recreation) share this
same database.

Note: this is the database as of 2026-07-17, which includes changes made for the updated
WinForms system (audit columns, soft-delete flags, Always Encrypted PII columns). It is not
the untouched original schema.

Contains personal data — keep off shared/public storage and out of git.

## Restore

```powershell
sqlcmd -S .\SQLEXPRESS -d master -Q "RESTORE DATABASE [Applicants] FROM DISK = N'<full path to .bak>' WITH REPLACE"
```

Close all three apps first (they hold connections to the database).
