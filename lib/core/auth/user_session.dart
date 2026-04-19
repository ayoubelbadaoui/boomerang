import 'dart:convert';

/// Lightweight representation of a stored account session.
/// Pure Dart — no Flutter or Firebase dependencies.
class UserSession {
  const UserSession({
    required this.uid,
    required this.email,
    this.displayName = '',
    this.photoUrl,
    required this.lastLogin,
  });

  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final DateTime lastLogin;

  UserSession copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoUrl,
    bool clearPhotoUrl = false,
    DateTime? lastLogin,
  }) {
    return UserSession(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: clearPhotoUrl ? null : (photoUrl ?? this.photoUrl),
      lastLogin: lastLogin ?? this.lastLogin,
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'lastLogin': lastLogin.toIso8601String(),
      };

  factory UserSession.fromJson(Map<String, dynamic> json) => UserSession(
        uid: json['uid'] as String,
        email: json['email'] as String,
        displayName: (json['displayName'] ?? '') as String,
        photoUrl: json['photoUrl'] as String?,
        lastLogin: DateTime.parse(json['lastLogin'] as String),
      );

  static String encodeList(List<UserSession> sessions) =>
      jsonEncode(sessions.map((s) => s.toJson()).toList());

  static List<UserSession> decodeList(String encoded) {
    final list = jsonDecode(encoded) as List;
    return list
        .map((e) => UserSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserSession &&
          runtimeType == other.runtimeType &&
          uid == other.uid;

  @override
  int get hashCode => uid.hashCode;
}
