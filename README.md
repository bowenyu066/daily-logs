# DailyLogs

`DailyLogs` is an iPhone-first personal tracking app for the smallest recurring pieces of a day: wake time, sleep, meals, and showers.

The goal is not to build an everything app. It is to make daily logging feel light enough that you actually keep using it.

## What It Does

- Log bedtime and wake time manually or sync sleep data from Apple Health / HealthKit
- Record meals with timestamps and optional photos
- Track showers with a quick single-entry flow
- Review lightweight analytics for sleep, wake time, meal completion, and daily trends
- Switch between English, Simplified Chinese, or system language
- Use Apple Sign In or continue in guest mode for local-only testing
- Sync records, preferences, and meal photos through Firebase

## Product Direction

DailyLogs is designed around a few principles:

- Fewer decisions
- Fast logging
- Calm, legible UI
- Useful trends without dashboard overload
- A good iPhone experience before anything else

## Stack

- SwiftUI
- Firebase Auth, Firestore, and Storage
- HealthKit
- Local JSON persistence for offline-first behavior
- GitHub Actions / GitHub Pages for project documentation and web presence

## Current Status

The app is in active beta.

Recent work includes:

- runtime language switching
- Analytics gating after 7 consecutive days of records
- improved chart callouts and selection states
- HealthKit sleep syncing fixes
- better persistence for account nickname and cloud profile data
- Firebase meal photo upload support
- TestFlight upload readiness updates

## Project Structure

- [DailyLogs](/Users/flyfishyu/Documents/2026/Dev%20Exps/Daily_logs/DailyLogs) — app source
- [DailyLogs/Views](/Users/flyfishyu/Documents/2026/Dev%20Exps/Daily_logs/DailyLogs/Views) — SwiftUI screens and sheets
- [DailyLogs/ViewModels](/Users/flyfishyu/Documents/2026/Dev%20Exps/Daily_logs/DailyLogs/ViewModels) — app state and business logic
- [DailyLogs/Services](/Users/flyfishyu/Documents/2026/Dev%20Exps/Daily_logs/DailyLogs/Services) — auth, cloud sync, HealthKit, local storage
- [DailyLogs/Resources](/Users/flyfishyu/Documents/2026/Dev%20Exps/Daily_logs/DailyLogs/Resources) — app assets, plist files, localization resources
- [FIREBASE_SETUP.md](/Users/flyfishyu/Documents/2026/Dev%20Exps/Daily_logs/FIREBASE_SETUP.md) — Firebase setup notes

## Local Development

1. Open `DailyLogs.xcodeproj` in Xcode.
2. Add a valid [GoogleService-Info.plist](/Users/flyfishyu/Documents/2026/Dev%20Exps/Daily_logs/DailyLogs/Resources/GoogleService-Info.plist) for your Firebase project.
3. Enable the capabilities you need:
   - Sign in with Apple
   - HealthKit
4. Build and run on an iPhone or simulator.

For Firebase-backed features, make sure Authentication, Firestore, and Storage are configured in the Firebase Console.

## TestFlight Notes

The project is currently configured as:

- iPhone only
- portrait only
- Apple Health read access for sleep data
- App Store Connect upload compatible

If you plan to distribute in more regions or broaden device support later, you can expand the App Store / Info.plist configuration from here.

## Website

A matching product page is published from the GitHub Pages site at:

- [bowenyu066.github.io/daily-logs](https://bowenyu066.github.io/daily-logs/)

This repository includes a static GitHub Pages site under [docs](/Users/flyfishyu/Documents/2026/Dev%20Exps/Daily_logs/docs). If GitHub Pages is configured to deploy from the `main` branch `/docs` folder, the product page will publish at the URL above.

## Credits

Designed and built by Bowen Yu, with iterative development support from OpenAI Codex.
