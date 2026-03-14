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

## Suggested Firestore Rules For Testing

```txt
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId}/{document=**} {
      allow read, write: if true;
    }
  }
}
```

## Suggested Storage Rules For Testing

```txt
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /users/{userId}/{allPaths=**} {
      allow read, write: if true;
    }
  }
}
```

## Notes

- Guest mode stays local-only.
- Apple-login users will use local cache plus Firestore sync.
- Meal photos are uploaded to Firebase Storage when Firebase is configured.
- For production, replace the testing rules above with real auth-based rules.
