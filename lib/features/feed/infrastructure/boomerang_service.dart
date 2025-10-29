import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;

import 'boomerang_processor.dart';
import 'boomerang_repo.dart';

class BoomerangService {
  BoomerangService(this._fs, this._storage, this._processor, this._repo);

  final FirebaseFirestore _fs;
  final FirebaseStorage _storage;
  final BoomerangProcessor _processor;
  final BoomerangRepo _repo;

  /// Downloads a sample video, processes into boomerang, uploads, and posts.
  /// Returns created post id.
  Future<String> createRandomProcessedBoomerang() async {
    // Pick random user
    final usersSnap = await _fs.collection('users').limit(50).get();
    if (usersSnap.docs.isEmpty) {
      throw Exception('No users found to assign the boomerang');
    }
    final docs = usersSnap.docs;
    docs.shuffle();
    final userDoc = docs.first;
    final user = userDoc.data();

    // Pick a reliable sample video
    final samples = <String>[
      'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
      'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
      'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
    ];
    samples.shuffle();
    final String sourceUrl = samples.first;

    // Download to temp
    final tempDir = Directory.systemTemp;
    final localIn = File(
      '${tempDir.path}/src_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );
    final resp = await http.get(Uri.parse(sourceUrl));
    if (resp.statusCode != 200) {
      throw Exception('Failed to download sample (${resp.statusCode})');
    }
    await localIn.writeAsBytes(resp.bodyBytes);

    // Process forward+reverse
    final outPath = await _processor.makeBoomerang(localIn.path);
    final outFile = File(outPath);

    // Upload
    final storagePath =
        'boomerangs/processed_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final task = await _storage.ref(storagePath).putFile(outFile);
    final videoUrl = await task.ref.getDownloadURL();

    // Optional poster
    final posters = [
      'https://picsum.photos/seed/bmg1/1200/1600',
      'https://picsum.photos/seed/bmg2/1200/1600',
      'https://picsum.photos/seed/bmg3/1200/1600',
      'https://picsum.photos/seed/bmg4/1200/1600',
      'https://picsum.photos/seed/bmg5/1200/1600',
    ];
    posters.shuffle();

    // Create post
    final id = await _repo.createBoomerangPost(
      userId: userDoc.id,
      userName: (user['fullName'] ?? user['nickname'] ?? 'User') as String,
      userAvatar: user['avatarUrl'] as String?,
      videoUrl: videoUrl,
      imageUrl: posters.first,
    );
    return id;
  }
}

