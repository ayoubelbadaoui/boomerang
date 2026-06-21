import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:boomerang/core/audio/app_audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

import 'package:boomerang/features/chat/domain/message_entity.dart';
import 'package:boomerang/features/chat/presentation/widgets/gif_picker_sheet.dart';

class ChatInputField extends StatefulWidget {
  const ChatInputField({
    super.key,
    required this.onSendText,
    required this.onSendImage,
    required this.onSendGif,
    required this.onSendAudio,
    this.isSending = false,
    this.emojiOpen = false,
    required this.onToggleEmoji,
    this.replyingTo,
    this.replyToSenderName,
    this.onClearReply,
  });

  final ValueChanged<String> onSendText;
  final ValueChanged<String> onSendImage;
  final ValueChanged<String> onSendGif;
  final void Function(String path, int durationMs) onSendAudio;
  final bool isSending;
  final bool emojiOpen;
  final VoidCallback onToggleEmoji;
  final MessageEntity? replyingTo;
  final String? replyToSenderName;
  final VoidCallback? onClearReply;

  @override
  State<ChatInputField> createState() => ChatInputFieldState();
}

/// Sub-states of the voice recorder.
enum _RecordPhase { idle, recording, locked }

class ChatInputFieldState extends State<ChatInputField>
    with TickerProviderStateMixin {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  // ── Audio recording ────────────────────────────────────────────────────
  final _recorder = AudioRecorder();
  _RecordPhase _phase = _RecordPhase.idle;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  String? _currentRecordingPath;

  // Live drag offset from the press origin (mic center at press time).
  double _dragDx = 0;
  double _dragDy = 0;
  // Whether we've already fired the haptic for crossing the cancel edge.
  bool _hapticCancelFired = false;
  // A start is considered "in-flight" between pointer-down and the recorder
  // actually being ready. We guard against pointer-up arriving in that window.
  bool _starting = false;
  // If the pointer is lifted while we were still starting, honor that by
  // stopping as soon as recording actually begins.
  bool _abortRequested = false;
  // Track whether the user has dragged past the lock threshold since press
  // (so a swipe-up past the lock icon reliably latches into locked mode).
  bool _lockArmed = false;

  // Thresholds (logical pixels). Kept generous for forgiving gestures.
  static const double _cancelThresholdX = -80;
  static const double _lockThresholdY = -80;
  static const int _minDurationMs = 500;

  // Animation controller for the pulsing red dot. Eagerly created in
  // initState (NOT via a `late final` lazy initializer) so that dispose()
  // never triggers createTicker -> ancestor lookup on a deactivated State.
  // The old `late final` form crashed with "Looking up a deactivated
  // widget's ancestor is unsafe" whenever the input field was torn down
  // before it ever built (AnimatedSwitcher swaps / quick back navigation).
  late final AnimationController _pulseController;
  bool _pulseReady = false;

  TextEditingController get controller => _controller;
  FocusNode get focusNode => _focusNode;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseReady = true;
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    if (_pulseReady) _pulseController.dispose();
    _controller.dispose();
    _focusNode.dispose();
    _recordingTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSendText(text);
    _controller.clear();
  }

  void _showHoldToRecordHint() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 2),
        content: Text('Hold to record a voice message'),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final isCamera = source == ImageSource.camera;
    if (isCamera && !await _ensureCameraPermission()) return;
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: source, imageQuality: 70);
      if (file == null) return;
      widget.onSendImage(file.path);
    } catch (e) {
      if (!mounted) return;
      _showPermissionMessage(
        isCamera
            ? 'Unable to open the camera. Please allow camera access in Settings.'
            : 'Unable to open your photos. Please allow photo access in Settings.',
        withSettings: true,
      );
    }
  }

  /// Ensures camera access for taking photos in chat. Requests it when
  /// possible; if permanently denied, guides the user to Settings.
  Future<bool> _ensureCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied || status.isRestricted) {
      _showPermissionMessage(
        'Camera access is off. Enable it in Settings to take photos.',
        withSettings: true,
      );
    } else {
      _showPermissionMessage('Camera permission is required to take photos.');
    }
    return false;
  }

  Future<void> _openGifPicker() async {
    final gifUrl = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const GifPickerSheet(),
    );
    if (gifUrl != null && gifUrl.isNotEmpty) {
      widget.onSendGif(gifUrl);
    }
  }

  // ── Audio recording — gesture handlers ───────────────────────────────

  Future<void> _onLongPressStart() async {
    // Ignore if we're already in a recording flow.
    if (_phase != _RecordPhase.idle || _starting) return;
    _starting = true;
    _abortRequested = false;
    _dragDx = 0;
    _dragDy = 0;
    _hapticCancelFired = false;
    _lockArmed = false;

    try {
      if (!await _ensureMicPermission()) {
        _starting = false;
        return;
      }

      // Reconfigure the shared audio session for speech recording.
      // We do NOT treat `setActive == false` as a hard failure here because
      // it can also return false on Android when another app simply holds
      // audio focus (e.g. music). The recorder.start() call below is the
      // authoritative signal — if the mic is really in use (phone call,
      // Siri, voice memo, etc.) it will throw, and we'll show a friendly
      // "end your call" message at that point.
      await _ensureRecordableAudioSession();

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      try {
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );
      } catch (e) {
        // Most common cause: another app (phone call, Siri, voice memo,
        // etc.) already holds the microphone. The error surface differs
        // by platform/version so we don't try to interpret it; we simply
        // surface an actionable message.
        _starting = false;
        _currentRecordingPath = null;
        _showMicBusyMessage();
        return;
      }
      _currentRecordingPath = path;

      if (!mounted) {
        await _recorder.stop();
        _starting = false;
        return;
      }

      HapticFeedback.mediumImpact();

      setState(() {
        _phase = _RecordPhase.recording;
        _recordingDuration = Duration.zero;
      });

      _recordingTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        setState(() {
          _recordingDuration += const Duration(milliseconds: 200);
        });
      });

      _starting = false;

      // If pointer was released during the async start, honor the release now.
      if (_abortRequested) {
        _abortRequested = false;
        await _finalizeRecording(cancelled: false);
      }
    } catch (_) {
      _starting = false;
      _currentRecordingPath = null;
      if (mounted) {
        setState(() {
          _phase = _RecordPhase.idle;
          _recordingDuration = Duration.zero;
        });
      }
    }
  }

  /// Reconfigure the shared audio session for speech recording. Best effort:
  /// if this fails, the recorder.start() call will still surface the issue.
  Future<void> _ensureRecordableAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      await session.setActive(true);
    } catch (_) {}
  }

  void _showMicMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  /// Shows a permission message. When [withSettings] is true (access was
  /// permanently denied), the snackbar offers a shortcut to the app's
  /// Settings page so the user can enable access.
  void _showPermissionMessage(String message, {bool withSettings = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        action: withSettings
            ? SnackBarAction(label: 'Settings', onPressed: openAppSettings)
            : null,
      ),
    );
  }

  /// Ensures microphone access. Requests it when possible; if permanently
  /// denied, guides the user to Settings. Returns true only when granted.
  Future<bool> _ensureMicPermission() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied || status.isRestricted) {
      _showPermissionMessage(
        'Microphone access is off. Enable it in Settings to record voice '
        'messages.',
        withSettings: true,
      );
    } else {
      _showMicMessage(
        'Microphone permission is required to record voice messages.',
      );
    }
    return false;
  }

  void _showMicBusyMessage() {
    _showMicMessage(
      "Your microphone is in use. If you're on a call or using another voice "
      'app, please end it and try again.',
    );
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_phase != _RecordPhase.recording) return;
    // `offsetFromOrigin` is the delta from press origin.
    final dx = details.offsetFromOrigin.dx;
    final dy = details.offsetFromOrigin.dy;

    // Prefer whichever axis is dominant, so a tiny horizontal wobble while
    // swiping up doesn't accidentally trigger the cancel zone.
    final useLockAxis = dy.abs() > dx.abs();
    final clampedDx = useLockAxis ? 0.0 : dx.clamp(-240.0, 0.0);
    final clampedDy = useLockAxis ? dy.clamp(-240.0, 0.0) : 0.0;

    // Haptic tick when entering the cancel zone.
    if (clampedDx < _cancelThresholdX && !_hapticCancelFired) {
      _hapticCancelFired = true;
      HapticFeedback.selectionClick();
    } else if (clampedDx > _cancelThresholdX + 8) {
      _hapticCancelFired = false;
    }

    // Latch into locked mode as soon as the user passes the lock threshold.
    if (clampedDy < _lockThresholdY) {
      _lockArmed = true;
    }
    if (_lockArmed && clampedDy < _lockThresholdY - 40) {
      _transitionToLocked();
      return;
    }

    setState(() {
      _dragDx = clampedDx;
      _dragDy = clampedDy;
    });
  }

  Future<void> _onLongPressEnd(LongPressEndDetails details) async {
    // If start is still in-flight, request abort and bail; the start path
    // will finalize once the recorder actually comes up.
    if (_starting) {
      _abortRequested = true;
      return;
    }
    if (_phase != _RecordPhase.recording) return;

    final cancel = _dragDx < _cancelThresholdX;
    await _finalizeRecording(cancelled: cancel);
  }

  Future<void> _onLongPressCancel() async {
    if (_starting) {
      _abortRequested = true;
      return;
    }
    if (_phase != _RecordPhase.recording) return;
    await _finalizeRecording(cancelled: true);
  }

  void _transitionToLocked() {
    HapticFeedback.mediumImpact();
    setState(() {
      _phase = _RecordPhase.locked;
      _dragDx = 0;
      _dragDy = 0;
    });
  }

  Future<void> _stopAndSend() async {
    if (_phase != _RecordPhase.locked) return;
    await _finalizeRecording(cancelled: false);
  }

  Future<void> _cancelLocked() async {
    if (_phase != _RecordPhase.locked) return;
    HapticFeedback.lightImpact();
    await _finalizeRecording(cancelled: true);
  }

  /// Stops the recorder, optionally deletes the temp file, and sends the
  /// captured audio up if the recording was long enough and not cancelled.
  Future<void> _finalizeRecording({required bool cancelled}) async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    final capturedMs = _recordingDuration.inMilliseconds;
    final desiredPath = _currentRecordingPath;
    String? actualPath;
    try {
      actualPath = await _recorder.stop();
    } catch (_) {
      actualPath = null;
    }

    final path = actualPath ?? desiredPath;
    final tooShort = capturedMs < _minDurationMs;

    if (cancelled || tooShort || path == null) {
      // Best-effort cleanup of the orphaned file.
      if (path != null) {
        try {
          final f = File(path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      // if (!cancelled && tooShort && mounted) {
      //   ScaffoldMessenger.of(context).showSnackBar(
      //     const SnackBar(
      //       content: Text('Hold to record — release to send.'),
      //       duration: Duration(milliseconds: 1500),
      //     ),
      //   );
      // }
    } else {
      widget.onSendAudio(path, capturedMs);
    }

    _currentRecordingPath = null;
    if (mounted) {
      setState(() {
        _phase = _RecordPhase.idle;
        _recordingDuration = Duration.zero;
        _dragDx = 0;
        _dragDy = 0;
        _hapticCancelFired = false;
        _lockArmed = false;
      });
    }

    // Restore the app-wide ambient session so background music resumes
    // mixing and nothing else gets disturbed after the recording ends.
    unawaited(_restoreAmbientAudioSession());
  }

  Future<void> _restoreAmbientAudioSession() async {
    await configureAmbientAudioSession();
  }

  String _formatTimer(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomSafe = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.replyingTo != null) _buildReplyPreview(theme),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16.w,
              12.h,
              16.w,
              12.h + (bottomSafe > 0 ? bottomSafe : 8.h),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder:
                  (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SizeTransition(
                      sizeFactor: anim,
                      axisAlignment: -1,
                      child: child,
                    ),
                  ),
              child:
                  _phase == _RecordPhase.locked
                      ? KeyedSubtree(
                        key: const ValueKey('locked'),
                        child: _buildLockedRow(theme),
                      )
                      : KeyedSubtree(
                        key: const ValueKey('input'),
                        child: _buildActiveRow(theme),
                      ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview(ThemeData theme) {
    final reply = widget.replyingTo!;
    String previewText;
    switch (reply.type) {
      case MessageType.image:
        previewText = '📷 Photo';
        break;
      case MessageType.gif:
        previewText = 'GIF';
        break;
      case MessageType.audio:
        previewText = '🎤 Voice message';
        break;
      case MessageType.sharedPost:
        previewText = '📫 Shared a post';
        break;
      case MessageType.text:
        previewText = reply.text;
        break;
    }

    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 10.h, 8.w, 0),
      child: Row(
        children: [
          Container(
            width: 3.w,
            height: 36.h,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to ${widget.replyToSenderName ?? ''}',
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  previewText,
                  style: TextStyle(fontSize: 12.sp, color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18.sp, color: Colors.grey),
            onPressed: widget.onClearReply,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(maxWidth: 32.w, maxHeight: 32.w),
          ),
        ],
      ),
    );
  }

  /// Idle or unlocked-recording: same shell so the mic GestureDetector never
  /// gets unmounted mid-gesture. The left side crossfades between the text
  /// field and a recording readout.
  Widget _buildActiveRow(ThemeData theme) {
    final recording = _phase == _RecordPhase.recording;
    final cancelProgress =
        (_dragDx / _cancelThresholdX).clamp(0.0, 1.0).toDouble();
    final lockProgress = (_dragDy / _lockThresholdY).clamp(0.0, 1.0).toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Lock indicator floats above the mic during unlocked recording.
        AnimatedAlign(
          duration: const Duration(milliseconds: 140),
          alignment: Alignment.centerRight,
          heightFactor: recording ? 1 : 0,
          child: Padding(
            padding: EdgeInsets.only(bottom: 8.h, right: 12.w),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 140),
              opacity: recording ? 1 : 0,
              child: _LockIndicator(progress: lockProgress),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder:
                    (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                child:
                    recording
                        ? _RecordingBar(
                          key: const ValueKey('rec-bar'),
                          duration: _recordingDuration,
                          cancelProgress: cancelProgress,
                          pulse: _pulseController,
                          formatter: _formatTimer,
                        )
                        : KeyedSubtree(
                          key: const ValueKey('text-bar'),
                          child: _buildTextBar(theme),
                        ),
              ),
            ),
            SizedBox(width: 8.w),
            _buildMicOrSend(theme),
          ],
        ),
      ],
    );
  }

  Widget _buildTextBar(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(24.r),
      ),
      child: Row(
        children: [
          _IconBtn(
            icon:
                widget.emojiOpen
                    ? Icons.keyboard_outlined
                    : Icons.emoji_emotions_outlined,
            onTap: widget.onToggleEmoji,
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Message...',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 10.h),
              ),
              style: theme.textTheme.bodyMedium,
              onSubmitted: (_) => _send(),
              onTap: () {
                if (widget.emojiOpen) widget.onToggleEmoji();
              },
            ),
          ),
          _IconBtn(icon: Icons.gif_box_outlined, onTap: _openGifPicker),
          _IconBtn(
            icon: Icons.photo_outlined,
            onTap: () => _pickImage(ImageSource.gallery),
          ),
          _IconBtn(
            icon: Icons.camera_alt_outlined,
            onTap: () => _pickImage(ImageSource.camera),
          ),
        ],
      ),
    );
  }

  /// The mic slot. While recording, the mic follows the finger (pull-left
  /// for cancel, up for lock) while the underlying GestureDetector stays put.
  Widget _buildMicOrSend(ThemeData theme) {
    final recording = _phase == _RecordPhase.recording;
    final showSend = _hasText && !recording;
    final scale = recording ? 1.25 : 1.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.isSending
          ? null
          : (showSend ? _send : _showHoldToRecordHint),
      onLongPressStart:
          _hasText || widget.isSending ? null : (_) => _onLongPressStart(),
      onLongPressMoveUpdate:
          _hasText || widget.isSending ? null : _onLongPressMoveUpdate,
      onLongPressEnd: _hasText || widget.isSending ? null : _onLongPressEnd,
      onLongPressCancel:
          _hasText || widget.isSending ? null : _onLongPressCancel,
      child: SizedBox(
        width: 48.w,
        height: 48.w,
        child: Transform.translate(
          offset: Offset(_dragDx, _dragDy),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 140),
            scale: scale,
            child: Container(
              width: 48.w,
              height: 48.w,
              decoration: BoxDecoration(
                color: recording ? Colors.red : theme.colorScheme.primary,
                shape: BoxShape.circle,
                boxShadow:
                    recording
                        ? [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.35),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ]
                        : null,
              ),
              child:
                  widget.isSending
                      ? Padding(
                        padding: EdgeInsets.all(12.w),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.w,
                          color: Colors.white,
                        ),
                      )
                      : Icon(
                        showSend ? Icons.send_rounded : Icons.mic,
                        color: Colors.white,
                        size: 22.sp,
                      ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLockedRow(ThemeData theme) {
    return Row(
      children: [
        GestureDetector(
          onTap: _cancelLocked,
          child: Container(
            width: 44.w,
            height: 44.w,
            decoration: BoxDecoration(
              color: const Color(0xFFFEECEC),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.delete_outline,
              color: Colors.red.shade600,
              size: 22.sp,
            ),
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Container(
            height: 44.h,
            padding: EdgeInsets.symmetric(horizontal: 14.w),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(22.r),
            ),
            child: Row(
              children: [
                _PulsingDot(controller: _pulseController),
                SizedBox(width: 10.w),
                Text(
                  _formatTimer(_recordingDuration),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Icon(Icons.lock_outlined, size: 16.sp, color: Colors.black45),
                SizedBox(width: 6.w),
                Text(
                  'Locked',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(width: 8.w),
        GestureDetector(
          onTap: _stopAndSend,
          child: Container(
            width: 48.w,
            height: 48.w,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.send_rounded, color: Colors.white, size: 22.sp),
          ),
        ),
      ],
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.all(10.w),
        child: Icon(
          icon,
          size: 22.sp,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Red capsule shown in the text-bar slot while the user holds to record.
/// Fades toward a "cancelling" look as the finger drags left.
class _RecordingBar extends StatelessWidget {
  const _RecordingBar({
    super.key,
    required this.duration,
    required this.cancelProgress,
    required this.pulse,
    required this.formatter,
  });

  final Duration duration;
  final double cancelProgress;
  final AnimationController pulse;
  final String Function(Duration) formatter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 48.h,
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(24.r),
      ),
      child: Opacity(
        opacity: (1.0 - cancelProgress * 0.6).clamp(0.0, 1.0).toDouble(),
        child: Row(
          children: [
            _PulsingDot(controller: pulse),
            SizedBox(width: 10.w),
            Text(
              formatter(duration),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_left, size: 16.sp, color: Colors.black45),
            SizedBox(width: 4.w),
            Text(
              cancelProgress >= 1 ? 'Release to cancel' : 'Slide to cancel',
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    cancelProgress >= 1 ? Colors.red.shade600 : Colors.black45,
                fontWeight:
                    cancelProgress >= 1 ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsingDot extends StatelessWidget {
  const _PulsingDot({required this.controller});
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = controller.value;
        return Container(
          width: 10.w,
          height: 10.w,
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.55 + 0.45 * t),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

/// Floating lock affordance shown above the mic during unlocked recording.
/// Grows and lights up as the user drags upward.
class _LockIndicator extends StatelessWidget {
  const _LockIndicator({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    final locked = progress >= 1;
    final color = locked ? Colors.white : Colors.black87;
    final bg = locked ? Colors.red : Colors.white;
    return AnimatedScale(
      duration: const Duration(milliseconds: 140),
      scale: 1.0 + progress * 0.1,
      child: Container(
        width: 36.w,
        height: 56.h,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              locked ? Icons.lock : Icons.lock_open_outlined,
              size: 18.sp,
              color: color,
            ),
            SizedBox(height: 2.h),
            Icon(
              Icons.keyboard_arrow_up_rounded,
              size: 14.sp,
              color: color.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}
