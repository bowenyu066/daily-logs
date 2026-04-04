# Firebase Setup

This app now supports Firebase-backed cloud sync for Apple-login users.

## What You Need

1. Create a Firebase project.
2. Add an iOS app with bundle id:
   `com.flyfishyu.DailyLogs`
3. Download `GoogleService-Info.plist`.
4. Put it here:
   `DailyLogs/Resources/GoogleService-Info.plist`
5. Regenerate the project:
   `xcodegen generate`

## Enable

- Firestore Database
- Storage
- Functions

## Suggested Firestore Rules For Production

```txt
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

## Suggested Storage Rules For Production

```txt
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /users/{userId}/{allPaths=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

## Notes

- Guest mode stays local-only.
- Apple-login users will use local cache plus Firestore sync.
- Meal photos are uploaded to Firebase Storage when Firebase is configured.
- If you enable end-to-end encryption in the app, Firestore and Storage will only contain ciphertext for records, preferences, and meal photos.

## AI Proxy Deployment

The repository now includes a minimal Cloud Functions proxy in [firebase/functions/index.js](/Users/flyfishyu/Documents/2026/Dev Exps/Daily_logs/firebase/functions/index.js).

1. Install the Firebase CLI and log in.
2. In [firebase/functions/package.json](/Users/flyfishyu/Documents/2026/Dev Exps/Daily_logs/firebase/functions/package.json), install dependencies with your preferred Node package manager.
3. Set the OpenAI secret:
   `firebase functions:secrets:set OPENAI_API_KEY`
4. Deploy:
   `firebase deploy --only functions:proxyOpenAIResponses`
5. Copy the deployed HTTPS URL into `AIProxyURL` in [DailyLogs/Resources/Info.plist](/Users/flyfishyu/Documents/2026/Dev Exps/Daily_logs/DailyLogs/Resources/Info.plist).

Behavior:

- The function requires a Firebase Auth bearer token.
- Requests are rate-limited per user per UTC day, default `5`.
- The OpenAI API key stays only in Functions secrets and is never sent to the client.
