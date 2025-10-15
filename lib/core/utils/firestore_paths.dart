class FP {
  static String user(String uid) => 'users/$uid';
  static String post(String postId) => 'posts/$postId';
  static String followers(String uid, String followerUid) =>
      'followers/$uid/users/$followerUid';
  static String following(String uid, String followedUid) =>
      'following/$uid/users/$followedUid';
  static String notifications(String uid) => 'notifications/$uid';
}
