# Top bar wireframes — current state

Text wireframes of the top toolbar/header area on three screens, as currently built. Reference for redesign discussion.

## Master Data — top bar

`frontend\applicants_app\lib\features\master_data\master_data_screen.dart:379-584`. One header line, then a 64px action bar split into a scrollable left zone and a pinned right zone.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Master Data                                                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│ [Recent ▾] [+ New Applicant] [⚙ Parameters Setup] [🗄 Archived…]            │
│ [⬆ Import Data] [🗑 Archive]*  ["↺ Carried over: …" ×]*   │  [🔍 Search applicants by name…        ] [💾 Save] [📑 Save + New] │
└─────────────────────────────────────────────────────────────────────────────┘
  ←──────────────────── scrolls left ────────────────────→   ←── pinned right ──→
* only shown conditionally: Archive only when an existing (non-new) record is loaded;
  "Carried over" chip only for a fresh sticky-prefilled new draft.
```

No tabs, no breadcrumbs, no export buttons here (Letter/Resume/Card live inside the Applications section further down the form, not in this bar). No "Discard" button in the toolbar — discard only happens inside the unsaved-changes guard dialog. Keyboard shortcuts: Ctrl+S (Save), Ctrl+Shift+S (Save + New), Ctrl+N (New Applicant).

## Applicant Browse — "List of Applicants" tab

`frontend\applicants_app\lib\features\applicant_browse\applicant_browse_screen.dart:299-549`. Same screen widget serves both tabs via a `hiredOnly` flag; List and Hired are separate sidebar routes (`/list`, `/hired`), not an in-page tab bar, and each keeps its own independent filter state.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ List of Applicants                                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│ [Name contains___] [Status contains___] [Municipality▾All] [Office▾All]     │
│ [Course▾All] [Eligibility▾All] [📅 Date applied: Any time] [Clear filters]  │  [☰ Columns] [📊 Export to Excel] [🖨 Print Report…] │
├─────────────────────────────────────────────────────────────────────────────┤
│  Applicant │ Municipality │ Position Applied │ Office │ Date Applied │ Status │ [Hire] │
│  ...rows (100/page, virtualized)...                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│        [< Previous 100]   Showing 1–100 of 33,147 · Click a row to open     │
│                             it in Master Data          [Next 100 >]         │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Applicant Browse — "Hired" tab

Identical toolbar/filters to List. Differences are in the grid and the row action:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Hired Applicants                                                            │
├─────────────────────────────────────────────────────────────────────────────┤
│  (same filter bar, same buttons — Columns list omits Date Hired/Final       │
│   Position/Final Department on List since those columns don't exist there) │
├─────────────────────────────────────────────────────────────────────────────┤
│ Applicant│Municipality│Position Applied│Office│Date Applied│Status│Date Hired│Final Position│Final Department│[Unhire]│
├─────────────────────────────────────────────────────────────────────────────┤
│        [< Previous 100]   Showing 1–N of M            [Next 100 >]          │
└─────────────────────────────────────────────────────────────────────────────┘
```

Hire/Unhire both call `_refreshBothTabs()` (`applicant_browse_screen.dart:162-165`) since a row moves between tabs.
