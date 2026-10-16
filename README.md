# StudyTrack

A native SwiftUI study tracker concept for iPhone (iOS 17+). Built entirely from system components — `TabView`, `NavigationStack`, `Form`, `List`, Swift Charts, SwiftData, `ContentUnavailableView`, wheel `Picker`s, `DatePicker`, `Stepper`, `ProgressView`, `sensoryFeedback`.

## Screens

| Tab | What it does |
| --- | --- |
| **Today** | Progress ring vs. your daily goal, streak, 7‑day stacked bar chart by subject, recent sessions |
| **Timer** | Start / pause / finish a live session, then rate focus and add notes before saving |
| **Goals** | Daily and weekly targets (all subjects or one), live progress bars |
| **History** | Sessions grouped by day, search, tap to edit, swipe to delete, manage Subjects (colour + SF Symbol) |
| **Profile** | Level & XP, daily quests, 12‑week activity heatmap, 16 badges, Insights (donut + best days), Settings |

Manual entry: `+` on Today / History opens a form with subject, start time, duration wheels, focus stars and notes.

## Gamification

All derived from your sessions (so edits/deletes keep it consistent — no separate state to corrupt):

- **XP:** 1 per minute + 5 per session + 20% bonus for 4★/5★ focus + 25 per completed daily quest.
- **Levels:** reach level *n* at `50·n·(n−1)` XP (100, 300, 600, 1000…), with titles from Newcomer to Grandmaster.
- **Daily quests:** study 30 min · cover 2 subjects · log a sharp 15+ min session.
- **Badges:** sessions, hours, streaks, marathon, laser focus, early bird / night owl, polymath, goal getter, rising star.
- Saving a session shows an XP banner; level‑ups and new badges add confetti + haptics. The timer shows live XP.

Other features: timer survives app restarts, edit sessions & goals, daily reminder notification, CSV export, default daily goal, erase / load sample data.

## Structure

```
project.yml                 XcodeGen spec (the .xcodeproj is generated, not committed)
StudyTrack/
  StudyTrackApp.swift       App entry + TabView
  Models/Models.swift       SwiftData: Subject, StudySession, Goal
  Views/                    Dashboard, Timer, Goals, History, Subjects, SessionForm
  Game/                     XP / level / quest / badge engine + celebration UI
  Support/                  Formatting helpers, first-launch sample data
.github/workflows/build-ipa.yml
```

First launch shows an onboarding screen: pick your subjects, or explore with sample data (also available in Settings).

## Keeping your data safe

- Everything is stored on‑device (SwiftData) and flushed to disk whenever the app leaves the foreground.
- **Profile › Settings › Back up all data** exports a full `.json` (subjects, sessions, goals) via the share sheet — save it to iCloud Drive / Files. **Restore from backup…** brings it back. The Today tab nags you if you haven't backed up in 2 weeks.
- Deleting a subject keeps its sessions.
- **Sideloading caveat:** deleting the app deletes its data. With a free Apple ID the install expires after 7 days — *refresh/re‑sign over the top* (AltStore does this automatically) rather than uninstalling, and keep the bundle ID (`com.studytrack.app`) unchanged.
- iCloud sync needs a paid developer account (CloudKit entitlement), so it isn't enabled.

## Building the IPA

The `Build IPA` workflow runs on a macOS runner: `xcodegen generate` → `xcodebuild` (Release, iphoneos, **unsigned**) → zips `Payload/StudyTrack.app` into `StudyTrack.ipa`, uploaded as the `StudyTrack-ipa` artifact.

An unsigned IPA can't be installed directly. Sign/sideload it with AltStore, Sideloadly, etc. (free Apple ID, 7‑day certs), or add signing secrets to the workflow for a proper development/ad‑hoc/TestFlight build.

Local: `brew install xcodegen && xcodegen generate && open StudyTrack.xcodeproj` — every view has a `#Preview` backed by in‑memory sample data.
