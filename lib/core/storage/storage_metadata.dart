import 'package:firebase_storage/firebase_storage.dart';

/// Firebase Storage serves objects with `cache-control: private, max-age=0`
/// unless upload metadata says otherwise — which forbids caching at Google's
/// edge, in proxies, and in any HTTP-respecting client. Our media files use
/// timestamped names and are never rewritten in place, so they can be cached
/// forever.
SettableMetadata immutableMediaMetadata(String contentType) {
  return SettableMetadata(
    contentType: contentType,
    cacheControl: 'public, max-age=31536000, immutable',
  );
}

/// For uploads that reuse a fixed path (e.g. `users/{uid}/avatar.jpg`).
/// The download token rotates on overwrite (busting URL-keyed caches), but a
/// bounded max-age keeps any path-keyed intermediary from pinning stale bytes.
SettableMetadata mutableMediaMetadata(String contentType) {
  return SettableMetadata(
    contentType: contentType,
    cacheControl: 'public, max-age=86400',
  );
}
