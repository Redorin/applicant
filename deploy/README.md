# Deploy & daily launch

| Script | What it does | When |
|---|---|---|
| `build.ps1` | Publishes the API to `deploy\api\` and the Flutter app to `deploy\app\` (both gitignored) | After any code change |
| `Start-HRMDO.ps1` | Starts the API hidden if it isn't running (waits for `/health`), then opens the app | Every launch — this is what the shortcut runs |
| `Install-Shortcut.ps1` | Puts the **Applicants System** shortcut on the Desktop | Once |

Requirements on this machine: SQL Server Express (`.\SQLEXPRESS`) with the
`Applicants` database, .NET 10 SDK (build) / runtime (run), Flutter SDK at
`D:\flutter` (build only).

Notes:

- The API stays running after the app closes — relaunches are instant, and
  the daily database backup runs on API startup.
- The app opens at the **login screen** (`kAutoLoginForTesting = false`).
  The credential lives in `backend\ApplicantsApi\appsettings.json`
  (`Auth:Username` / `Auth:Password`) — after changing it, republish the
  API (or edit `deploy\api\appsettings.json` to match) and restart the
  service. The current password is weak and the file is committed to the
  local repo; set a strong one before any remote push or multi-user use.
