/// Snapshot of every signal that contributed to a post's final score.
/// Kept around for debugging, A/B comparison, and the ranking-sheet UI.
class ScoreComponents {
  const ScoreComponents({
    required this.recency,
    required this.relationship,
    required this.engagement,
    required this.serverScore,
    required this.exploration,
    required this.finalScore,
  });

  final double recency;
  final double relationship;
  final double engagement;
  final double serverScore;
  final double exploration;
  final double finalScore;

  Map<String, double> toMap() => {
        'recency': recency,
        'relationship': relationship,
        'engagement': engagement,
        'serverScore': serverScore,
        'exploration': exploration,
        'finalScore': finalScore,
      };
}
