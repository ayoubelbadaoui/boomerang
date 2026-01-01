import 'package:boomerang/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'app.dart';

// Top-level background handler for FCM messages
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized when the process is woken up
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Register the background message handler before initializing the app
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: BoomerangApp()));
}

// TODO: Create UserProfile entity + repo (Firestore /users/{uid}).
// TODO: Build Post entity + repo for uploads (Storage + Firestore /posts).
// TODO: Replace HomeShell with real feed and guarded tabs.
//
