import 'package:boomerang/features/feed/presentation/hashtag_feed_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Renders a caption string with tappable hashtags.
///
/// Hashtag tokens (`#word`) are highlighted and navigate to
/// [HashtagFeedPage] on tap. Everything else is plain text.
class HashtagCaption extends StatelessWidget {
  const HashtagCaption({
    super.key,
    required this.caption,
    required this.style,
    this.hashtagColor,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
  });

  final String caption;
  final TextStyle style;
  final Color? hashtagColor;
  final int? maxLines;
  final TextOverflow overflow;

  static final _hashtagRe = RegExp(r'(?:#)([A-Za-z0-9_]{1,30})');

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in _hashtagRe.allMatches(caption)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: caption.substring(cursor, match.start)));
      }
      final fullTag = match.group(0)!;
      final tag = match.group(1)!.toLowerCase();
      spans.add(
        TextSpan(
          text: fullTag,
          style: TextStyle(
            color: hashtagColor ?? Colors.blueAccent,
            fontWeight: FontWeight.w700,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => HashtagFeedPage(tag: tag)),
              );
            },
        ),
      );
      cursor = match.end;
    }

    if (cursor < caption.length) {
      spans.add(TextSpan(text: caption.substring(cursor)));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: caption));
    }

    return RichText(
      maxLines: maxLines,
      overflow: overflow,
      text: TextSpan(style: style, children: spans),
    );
  }
}
