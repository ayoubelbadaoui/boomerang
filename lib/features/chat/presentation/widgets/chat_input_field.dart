import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';

class ChatInputField extends StatefulWidget {
  const ChatInputField({
    super.key,
    required this.onSendText,
    required this.onSendImage,
    this.isSending = false,
    this.emojiOpen = false,
    required this.onToggleEmoji,
  });

  final ValueChanged<String> onSendText;
  final ValueChanged<String> onSendImage;
  final bool isSending;
  final bool emojiOpen;
  final VoidCallback onToggleEmoji;

  @override
  State<ChatInputField> createState() => ChatInputFieldState();
}

class ChatInputFieldState extends State<ChatInputField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  TextEditingController get controller => _controller;
  FocusNode get focusNode => _focusNode;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSendText(text);
    _controller.clear();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 70);
    if (file == null) return;
    widget.onSendImage(file.path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(24.r),
              ),
              child: Row(
                children: [
                  _IconBtn(
                    icon: widget.emojiOpen
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
            ),
          ),
          SizedBox(width: 8.w),
          GestureDetector(
            onTap: widget.isSending ? null : (_hasText ? _send : null),
            child: Container(
              width: 48.w,
              height: 48.w,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: widget.isSending
                  ? Padding(
                      padding: EdgeInsets.all(12.w),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.w,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      _hasText ? Icons.send_rounded : Icons.mic,
                      color: Colors.white,
                      size: 22.sp,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

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
