class UserProfile {
  UserProfile({
    required this.uid,
    required this.fullName,
    required this.nickname,
    required this.username,
    required this.usernameLower,
    this.avatarUrl,
    this.bio = '',
    this.instagram = '',
    this.facebook = '',
    this.twitter = '',
    this.isPrivate = false,
  });
  final String uid;
  final String fullName;
  final String nickname;
  final String username;
  final String usernameLower;
  final String? avatarUrl;
  final String bio;
  final String instagram;
  final String facebook;
  final String twitter;
  final bool isPrivate;

  String get handle => '@${nickname.replaceAll(' ', '_').toLowerCase()}';

  factory UserProfile.fromMap(String uid, Map<String, dynamic> data) {
    return UserProfile(
      uid: uid,
      fullName: (data['fullName'] ?? '') as String,
      nickname: (data['nickname'] ?? '') as String,
      username: (data['username'] ?? '') as String,
      usernameLower: (data['usernameLower'] ?? '') as String,
      avatarUrl: data['avatarUrl'] as String?,
      bio: (data['bio'] ?? '') as String,
      instagram: (data['instagram'] ?? '') as String,
      facebook: (data['facebook'] ?? '') as String,
      twitter: (data['twitter'] ?? '') as String,
      isPrivate: (data['isPrivate'] ?? false) as bool,
    );
  }
}
