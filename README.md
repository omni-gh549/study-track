# StudyTrack

A native SwiftUI study tracker concept for iPhone (iOS 17+). Built entirely from system components — `TabView`, `NavigationStack`, `Form`, `List`, Swift Charts, SwiftData, `ContentUnavailableView`, wheel `Picker`s, `DatePicker`, `Stepper`, `ProgressView`, `sensoryFeedback`.

## Screens

| Tab | What it does |
| --- | --- |
| **Today** | Progress ring vs. your daily goal, streak, 7‑day stacked bar chart by subject, recent sessions |
| **Timer** | Start / pause / finish a live session, then rate focus and add notes before saving |
| **Goals** | Daily and weekly targets (all subjects or one), live progress bars |
| **History** | Sessions grouped by day, search, swipe to delete, manage Subjects (colour + SF Symbol) |

Manual entry: `+` on Today / History opens a form with subject, start time, duration wheels, focus stars and notes.

## Structure

```
project.yml                 XcodeGen spec (the .xcodeproj is generated, not committed)
StudyTrack/
  StudyTrackApp.swift       App entry + TabView
  Models/Models.swift       SwiftData: Subject, StudySession, Goal
  Views/                    Dashboard, Timer, Goals, History, Subjects, SessionForm
  Support/                  Formatting helpers, first-launch sample data
.github/workflows/build-ipa.yml
```

Sample data is seeded once on first launch (`RootView`); remove the `.task` there to start empty.

## Building the IPA

The `Build IPA` workflow runs on a macOS runner: `xcodegen generate` → `xcodebuild` (Release, iphoneos, **unsigned**) → zips `Payload/StudyTrack.app` into `StudyTrack.ipa`, uploaded as the `StudyTrack-ipa` artifact.

An unsigned IPA can't be installed directly. Sign/sideload it with AltStore, Sideloadly, etc. (free Apple ID, 7‑day certs), or add signing secrets to the workflow for a proper development/ad‑hoc/TestFlight build.

Local: `brew install xcodegen && xcodegen generate && open StudyTrack.xcodeproj` — every view has a `#Preview` backed by in‑memory sample data.
