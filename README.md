# boomerang

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Push notifications backend (Firebase Functions)

Node.js (Express + Firestore trigger) lives in `functions/`.

### Run locally
```
cd functions
npm install
npm run build
firebase emulators:start --only functions
```

### Deploy
```
cd functions
npm run deploy
```

### What it does
- Watches `notifications/{userId}/items/{itemId}` and sends push via FCM.
- Throttles per user/type to reduce spam.
- Cleans up bad tokens automatically.
- HTTP: `api` export exposes `/health` and `/notifications/test` for manual sends.

### Adding a new notification type
1. Add the type to `NotificationType` in `functions/src/domain/notificationTypes.ts`.
2. Add a template in `functions/src/domain/templates.ts`.
3. (Optional) adjust throttling window in `functions/src/config/constants.ts`.
