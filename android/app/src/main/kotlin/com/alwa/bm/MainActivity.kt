package com.alwa.bm

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.camerax.CameraAndroidCameraxPlugin
import io.flutter.plugins.firebase.auth.FlutterFirebaseAuthPlugin
import io.flutter.plugins.firebase.core.FlutterFirebaseCorePlugin
import io.flutter.plugins.firebase.firestore.FlutterFirebaseFirestorePlugin
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingPlugin
import io.flutter.plugins.firebase.storage.FlutterFirebaseStoragePlugin
import io.flutter.plugins.flutter_plugin_android_lifecycle.FlutterAndroidLifecyclePlugin
import io.flutter.plugins.imagepicker.ImagePickerPlugin
import io.flutter.plugins.pathprovider.PathProviderPlugin
import io.flutter.plugins.videoplayer.VideoPlayerPlugin
import vn.hunghd.flutter.plugins.imagecropper.ImageCropperPlugin
import com.dexterous.flutterlocalnotifications.FlutterLocalNotificationsPlugin
import dev.fluttercommunity.plus.share.SharePlusPlugin
import com.antonkarpenko.ffmpegkit.FFmpegKitFlutterPlugin

class MainActivity : FlutterActivity() {
    // Manually register plugins (include ffmpeg for Edit Boomerang video processing).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Skip super.configureFlutterEngine to avoid auto-registration failure.
        val plugins = flutterEngine.plugins
        plugins.add(FFmpegKitFlutterPlugin())
        plugins.add(CameraAndroidCameraxPlugin())
        plugins.add(FlutterFirebaseFirestorePlugin())
        plugins.add(FlutterFirebaseAuthPlugin())
        plugins.add(FlutterFirebaseCorePlugin())
        plugins.add(FlutterFirebaseMessagingPlugin())
        plugins.add(FlutterFirebaseStoragePlugin())
        plugins.add(FlutterLocalNotificationsPlugin())
        plugins.add(FlutterAndroidLifecyclePlugin())
        plugins.add(ImageCropperPlugin())
        plugins.add(ImagePickerPlugin())
        plugins.add(PathProviderPlugin())
        plugins.add(SharePlusPlugin())
        plugins.add(VideoPlayerPlugin())
    }
}



