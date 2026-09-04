# System Report — HRMDO-Flutter-Recreation

*The brand-new modern version, built from scratch · Reviewed 19 July 2026 · Updated the same day after the improvement batch*

## Part 1 — Summary in plain language

**What this is.** This is a **completely new version of the Applicants Information System**, built from the ground up with modern technology. It is not a repair of the old program — it is its planned successor. It uses the **same applicant records** as the current program (the same database), so nothing needs to be re-typed.

**What it can already do.** Almost everything the current program does: log in, search and browse applicants, add and edit records, manage the reference lists (municipalities, offices, schools, etc.), and print the usual reports as PDFs. It also adds things the old program never had:

- A **dashboard** — charts and counts showing hiring activity at a glance.
- A **data-health screen** — it finds records with problems (wrong dates, missing towns, badly typed contact numbers) and lists them for clean-up.
- **Excel export** of any search result.
- Its own **automatic daily backup** of the records.

**Why it isn't ready for the office yet.** It's close, but a few important switches are still in "testing position":

- ~~The login screen is currently bypassed~~ — *fixed later on 19 July*: the app now asks for the username and password every time it opens.
- The password is still a **simple placeholder chosen for convenience**, stored unprotected — set a strong one before other staff use the system.
- A few small gaps remain (for example, the list of *positions* is typed free-hand instead of picked from a maintained list).

**Recommendation.** Think of this as the system's future. Finish the login and security work so it can take over with no rush.

---

## Update — 19 July 2026: this became the default system

Later the same day as the review above, this version was **chosen as the system going forward**, and a full working session was spent making it faster and safer for the person who encodes hundreds of applicants. In plain terms, what was added:

**Faster typing, less repetition**
- **Save + New**: one click (or Ctrl+Shift+S) saves the applicant and opens the next blank form with the cursor already in Surname.
- **Carried-over values**: after saving a new applicant, the next form starts pre-filled with the same municipality, position, recommender, and date received — because applicants arrive in batches. A small chip shows what was carried; one click clears it.
- **The Enter key walks the form** field by field, so a whole record can be typed without touching the mouse.
- **Smart defaults**: province starts as Pangasinan; the municipality list shows the most-used towns first (Lingayen, Binmaley, San Carlos…) instead of alphabetical.
- A **"Encoded today: N" counter** in the bottom bar shows the day's output.

**Fewer mistakes, less rework**
- **Duplicate warning while typing**: half a second after typing a name that's already on file, a warning chip appears — before anything else is typed.
- **Names tidy themselves**: "DELA CRUZ, juan" is saved as "dela Cruz, Juan"; stray spaces are trimmed everywhere.
- **Missing school or eligibility?** A small ➕ next to those lists adds the new entry on the spot — no more detour through the password-gated Settings screen.
- **Crash protection**: the half-typed record autosaves every 2 seconds; after a crash the app offers "Recover unsaved work?".

**Address entry, rebuilt to match how addresses are written**
- New **Street** and **Subdivision** fields (House/Blk/Lot · Street · Subdivision · Barangay, then Province · Municipality).
- The composed "address on record" writes streets properly ("Ramos" becomes "Ramos St., …") and is now **editable** — type to override it, clear it to let it compose itself again.

**Bugs found in testing, fixed the same day**
- "Discard changes" now really discards (it used to keep nagging on every tab change).
- A newly archived applicant now appears in the Archived list immediately.
- Person-in-charge & notes moved above the Applications table on the form.

**Housekeeping that makes this a real system**
- The code is now under **version control (git)** — every change is recorded and reversible. (A one-screen layout experiment was tried and cleanly rolled back this way.)
- A **desktop shortcut ("Applicants System")** starts everything with one double-click — it quietly starts the background service if needed, checks it's healthy, then opens the app.
- Rebuild instructions live in `deploy\README.md`.

---

## Part 2 — Technical review

### Architecture

- **Backend** (`backend\ApplicantsApi`): ASP.NET Core **Minimal API on .NET 10**, vertical-slice feature folders, **Dapper** over parameterized SQL against the shared `.\SQLEXPRESS`/`Applicants` DB (Integrated Security — no DB credentials on disk), **QuestPDF** for reports. Binds to `http://127.0.0.1:5080` (localhost-only). Startup tasks: idempotent schema top-up (`contact2`), 6 idempotent indexes, daily backup-if-due. `/health` endpoint. No Swagger, CORS, or TLS (acceptable while localhost-only).
- **Frontend** (`frontend\applicants_app`): Flutter **2.0.0**, Windows-desktop only (single platform folder), **Riverpod** state, **go_router** navigation, `http` client with `X-Session-Token` header. Six sidebar sections: Dashboard, Master Data, List of Applicants, Hired Applicants, Summary Reports, Data Health (+ routed Settings and Archived screens).
- **Database folder**: 62 MB verified `.bak` (2026-07-17) + `RESTORE.md`.

### Feature coverage vs the original system

| Original feature | Status here |
|---|---|
| Login gate | ✅ active (`kAutoLoginForTesting = false` since 19 Jul) |
| Browse/search applicants (incl. hired view) | ✅ paginated with filters |
| Master data CRUD (biodata, applications, eligibilities) | ✅ transactional save with diff, duplicate check, archive/restore |
| Reference lists (provinces, municipals, offices, education, eligibilities, recommenders) | ✅ read + batch CRUD |
| Positions master list | ❌ free-text only, no lookup table |
| Staff list | ⚠️ read-only endpoint, no CRUD |
| Reports: list / hired / recommendation summary / resume / letter | ✅ all as QuestPDF PDFs |
| Transfer/export | ✅ reframed as Excel (.xlsx) export |
| *New:* dashboard analytics, data-health worklist, status-merge tool, daily backups | ✅ beyond the original |

### Security review

| # | Finding | Severity |
|---|---|---|
| 1 | ~~Auto-login bypass~~ — *fixed 19 Jul*: login screen active on every launch | Resolved |
| 2 | Shared credential in plaintext `appsettings.json` (currently a weak keyboard-pattern password); compared with plain `!=` (no hash, no constant-time compare) | High |
| 3 | Session tokens never expire (timestamp stored, never checked) and vanish on restart | Medium |
| 4 | 62 MB PII `.bak` in the project tree despite `RESTORE.md`'s own warning | Medium |
| 5 | Hardcoded API base URL in `api_client.dart` — host change requires recompile | Low |
| 6 | Client-side settings password `'33'` (self-described accident-guard) | Low |

**Positives:** all user-input SQL is parameterized (no injection surface found — interpolation only over hardcoded table-name constants), transactional saves with change diffs, FK-violation handling with friendly messages, error-logging middleware + global exception logger, idempotent schema/index maintenance, retained daily backups.

### Gaps / quality notes

- ~~No documentation at all~~ — *partly fixed 19 Jul*: `deploy\README.md` covers build/launch; a full restore-to-new-machine guide is still worth writing.
- ~~One stale test~~ — *fixed 19 Jul*: the widget test now pumps LoginScreen directly; suite is 8/8 green (incl. new name-normalization tests).
- ~~Not under git~~ — *fixed 19 Jul*: own repo, baseline + ~15 feature/fix commits. No off-machine remote yet.

### Recommendations (priority order)

1. ~~Put this codebase under git~~ — *done 19 Jul* (local only; add a private remote before relying on it as backup — note `appsettings.json` carries the auth password, move it first).
2. ~~Flip `kAutoLoginForTesting` to false~~ — *done 19 Jul*. Still pending: a strong credential and session-token expiry.
3. ~~Write a minimal README/run guide~~ — *deploy README done*; write the full new-machine guide when deployment nears.
4. Add a **positions lookup table** and staff CRUD to reach full parity.
5. Make the API base URL configurable for a future client/server split.

### Technical changelog — 19 July 2026 batch

**Backend (ApplicantsApi)**
- `GET /api/masterdata/duplicate-check`: `dbirth` now optional — name-only counting enables warn-while-typing.
- New `GET /api/lookups/municipals/usage` — usage counts over active `masterdata.municipality` for most-used-first ordering.
- New `POST /api/lookups/{education|eligibilities}` quick-add — trims, dedupes case-insensitively, returns `{id, value, existed}` (the batch endpoints do neither and return no id).
- `masterdata` gains `street` and `subdivision` columns via the idempotent `EnsureSchemaAsync` (same pattern as `contact2`; legacy WinForms apps unaffected). DTOs, GetById, and the save transaction carry them.

**Frontend (applicants_app)**
- `MasterDataState.epoch` keys the form cards so blank-draft → blank-draft transitions (Save + New) rebuild cleanly.
- `saveAndNew()` sharing a `_persist()` core with `save()`; Save + New button + Ctrl+Shift+S; surname `autofocus` on new drafts.
- `StickyFields` notifier persisted in shared_preferences; applied in `newApplicant()` incl. a pre-created application row (status "On Process"); carried-over `InputChip` with clear.
- `DuplicateWarning` enum (none / nameOnly / nameAndBirth) with a 500 ms debounce off the name fields.
- `core/text/name_case.dart`: Title Case with Filipino particle handling (dela, de la, delos…), hyphen/apostrophe capitals, ñ; `normalizeDraftForSave` called once in the save path; unit-tested.
- Keyboard flow: `textInputAction.next` + `nextFocus()` on every single-line field, `FocusTraversalGroup` on the form, case-insensitive `filterCallback` on `SearchableDropdown`.
- Inline lookup add: `promptAddLookupValue` dialog + ➕ buttons; invalidates `lookupsProvider`; selects the canonical value.
- Draft autosave: 2 s debounce off `touch()` to shared_preferences; cleared on save/load/new/discard; recovery dialog on first Master Data open.
- Fixes: `discardDraft()` wired to the unsaved-changes dialog; archived list provider is `autoDispose`; PIC & notes card moved above Applications.
- Address card: Street + Subdivision fields; Province before Municipality; composed address emits "«street» St.," (no doubling); "Address on record" editable with manual-override/clear-to-recompose semantics.
- Status bar shows "Ready · Encoded today: N" (new-applicant saves, resets daily).
- A one-screen split layout was built, judged too cramped at 150 % text, and reverted (`0eb3754`) — the classic scrolling form stands.

**Deploy**
- `deploy\build.ps1` (publish API + Flutter release into gitignored `deploy\{api,app}`, stops running processes first), `deploy\Start-HRMDO.ps1` (health-checked hidden API start, then app), `deploy\Install-Shortcut.ps1` (Desktop "Applicants System"), `deploy\README.md`.
