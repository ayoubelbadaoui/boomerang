package com.alwa.bm

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    // Delegate to the generated plugin registrant so every plugin listed in
    // pubspec.yaml is registered on the Android side. The previous override
    // skipped this and manually added a hard-coded subset, which silently
    // dropped `record`, `audioplayers`, `audio_session`, `shared_preferences`
    // and others — breaking voice recording, voice playback and any feature
    // that relied on SharedPreferences on Android.
    //
    // The generated registrant already wraps each plugin registration in its
    // own try/catch, so a single misbehaving plugin can never prevent the
    // others from loading — no manual workaround is needed.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
    }
}
