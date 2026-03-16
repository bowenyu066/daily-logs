# DailyLogs

DailyLogs is an iPhone-first habit tracker for a few recurring parts of the day: sleep, wake time, meals, and showers.

It is intentionally small. The goal is to make daily logging feel light enough to keep using.

## Features

- Log bedtime and wake time manually or sync sleep data from Apple Health
- Record meals with timestamps and optional photos
- Track showers in a fast single-step flow
- Review simple trend views once enough history is available
- Switch between English, Simplified Chinese, or system language
- Sync account data and meal photos with Firebase

## Built With

- SwiftUI
- Firebase Auth, Firestore, and Storage
- HealthKit

## Development

1. Open `DailyLogs.xcodeproj` in Xcode.
2. Add a valid `GoogleService-Info.plist` for your Firebase project.
3. Enable the required capabilities, including Sign in with Apple and HealthKit.
4. Build and run on an iPhone or simulator.

## Website

Project page: [bowenyu066.github.io/daily-logs](https://bowenyu066.github.io/daily-logs/)

The repository includes a static site in `docs/` for GitHub Pages deployment.
