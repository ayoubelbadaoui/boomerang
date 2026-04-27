import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class InputFilled extends StatefulWidget {
  const InputFilled({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
    this.validator,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  @override
  State<InputFilled> createState() => _InputFilledState();
}

class _InputFilledState extends State<InputFilled> {
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) {
    final showToggle = widget.obscure && widget.suffix == null;

    return TextFormField(
      controller: widget.controller,
      keyboardType: widget.keyboardType,
      obscureText: _hidden,
      validator: widget.validator,
      decoration: InputDecoration(
        hintText: widget.hint,
        filled: true,
        fillColor: const Color(0xFFF4F4F4),
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 18.h),
        prefixIcon: Icon(widget.icon),
        suffixIcon: showToggle
            ? IconButton(
                icon: Icon(
                  _hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  color: Colors.black45,
                ),
                splashRadius: 20,
                onPressed: () => setState(() => _hidden = !_hidden),
              )
            : widget.suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20.r),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
