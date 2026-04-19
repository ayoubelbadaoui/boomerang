class UserProfile {
  UserProfile({
    required this.uid,
    required this.fullName,
    required this.nickname,
    this.avatarUrl,
    this.bio = '',
    this.email = '',
    this.phone = '',
    this.birthday,
    this.instagram = '',
    this.facebook = '',
    this.twitter = '',
    this.isPrivate = false,
    this.followersCount = 0,
    this.followingCount = 0,
    this.boomerangsCount = 0,
    this.totalLikes = 0,
  });
  final String uid;
  final String fullName;
  final String nickname;
  final String? avatarUrl;
  final String bio;
  final String email;
  final String phone;
  final DateTime? birthday;
  final String instagram;
  final String facebook;
  final String twitter;
  final bool isPrivate;
  final int followersCount;
  final int followingCount;
  final int boomerangsCount;
  final int totalLikes;

  String get handle => '@${nickname.replaceAll(' ', '_').toLowerCase()}';

  static DateTime? _parseBirthday(dynamic value) {
    if (value == null) return null;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  factory UserProfile.fromMap(String uid, Map<String, dynamic> data) {
    final nickname = (data['nickname'] ?? data['username'] ?? '') as String;
    return UserProfile(
      uid: uid,
      fullName: (data['fullName'] ?? '') as String,
      nickname: nickname,
      avatarUrl: data['avatarUrl'] as String?,
      bio: (data['bio'] ?? '') as String,
      email: (data['email'] ?? '') as String,
      phone: (data['phone'] ?? '') as String,
      birthday: _parseBirthday(data['birthday']),
      instagram: (data['instagram'] ?? '') as String,
      facebook: (data['facebook'] ?? '') as String,
      twitter: (data['twitter'] ?? '') as String,
      isPrivate: (data['isPrivate'] ?? false) as bool,
      followersCount: (data['followersCount'] ?? 0) as int,
      followingCount: (data['followingCount'] ?? 0) as int,
      boomerangsCount: (data['boomerangsCount'] ?? 0) as int,
      totalLikes: (data['totalLikes'] ?? 0) as int,
    );
  }
}
