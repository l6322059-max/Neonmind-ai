# NeonMind

A neon-on-black AI chat assistant for Android, built with Flutter.

## What it is

- **Two brains in one app.** With no setup, an offline brain handles math, time and date, and jokes. Add an Anthropic API key in Settings and NeonMind answers anything through a real AI model.
- **Black and neon design.** Pure black background, cyan and magenta glow, a pulsing orb that speeds up while the AI thinks.
- **Private by default.** Chats stay on your phone. Your API key is stored only on your device.

## Declaration

NeonMind is an AI assistant. It can be wrong, so double-check anything important. It is not a substitute for professional medical, legal, or financial advice. When an API key is set, your messages are sent to the Anthropic API to generate answers and are handled under Anthropic's terms. The assistant's identity and behavior rules live in `kPersona` in `lib/ai_engine.dart`.

## Get the APK (no setup on your computer)

1. Create a new GitHub repository and upload everything from this folder (including the hidden `.github` folder).
2. Open the **Actions** tab and run **Build APK** (it also runs on every push to `main`).
3. When it finishes (about 5 minutes), open the run and download **NeonMind-apk** under Artifacts.
4. Unzip it and install `app-release.apk` on your phone. Allow "install unknown apps" if asked.

## Build locally

```
flutter create --platforms=android --project-name neonmind --org com.neonmind .
flutter pub get
flutter build apk --release
```

Then add `<uses-permission android:name="android.permission.INTERNET"/>` to `android/app/src/main/AndroidManifest.xml`.

## Customize

- Colors: constants at the top of `lib/main.dart`.
- AI personality: `kPersona` in `lib/ai_engine.dart`.
- Default model: `kDefaultModel` in `lib/ai_engine.dart` (also editable in Settings).
