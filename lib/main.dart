import 'package:boomerang/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: BoomerangApp()));
}

// TODO: Create UserProfile entity + repo (Firestore /users/{uid}).
// TODO: Build Post entity + repo for uploads (Storage + Firestore /posts).
// TODO: Replace HomeShell with real feed and guarded tabs.
//
