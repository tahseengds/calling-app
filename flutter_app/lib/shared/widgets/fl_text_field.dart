import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/config/app_colors.dart';

/// FamilyLink branded text field with floating label, 18 px radius, 60 px min
/// height, optional prefix widget, and password visibility toggle.
class FlTextField extends StatefulWidget {
  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool obscureText;
  final bool showToggle;       // show eye icon for password fields
  final Widget? prefixWidget;  // e.g. flag + country-code prefix
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onFieldSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final String? hint;
  final bool readOnly;
  final int? maxLines;

  const FlTextField({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.obscureText = false,
    this.showToggle = false,
    this.prefixWidget,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.inputFormatters,
    this.hint,
    this.readOnly = false,
    this.maxLines = 1,
  });

  @override
  State<FlTextField> createState() => _FlTextFieldState();
}

class _FlTextFieldState extends State<FlTextField> {
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _obscure = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fillColor =
        isDark ? AppColors.darkSurfaceLo : AppColors.lightSurfaceLo;

    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: widget.showToggle ? _obscure : widget.obscureText,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onFieldSubmitted,
      inputFormatters: widget.inputFormatters,
      readOnly: widget.readOnly,
      maxLines: widget.showToggle ? 1 : widget.maxLines,
      style: TextStyle(
        fontSize: 16,
        color: isDark ? AppColors.darkFg1 : AppColors.lightFg1,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        hintStyle: TextStyle(
          color: isDark ? AppColors.darkFg3 : AppColors.lightFg2,
          fontSize: 15,
        ),
        fillColor: fillColor,
        prefixIcon: widget.prefixWidget != null
            ? Padding(
                padding: const EdgeInsets.only(left: 16, right: 8),
                child: widget.prefixWidget,
              )
            : null,
        prefixIconConstraints:
            widget.prefixWidget != null
                ? const BoxConstraints(minWidth: 0, minHeight: 0)
                : null,
        suffixIcon: widget.showToggle
            ? IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: isDark ? AppColors.darkFg3 : AppColors.lightFg2,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              )
            : null,
        constraints: const BoxConstraints(minHeight: 60),
      ),
    );
  }
}

/// Phone prefix widget: flag emoji + country code, used in login/register.
class PhonePrefix extends StatelessWidget {
  final String flag;
  final String dialCode;

  const PhonePrefix({
    super.key,
    this.flag = '🇺🇸',
    this.dialCode = '+1',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(flag, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 4),
        Text(
          dialCode,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: isDark ? AppColors.darkFg2 : AppColors.lightFg2,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Container(
            width: 1,
            height: 20,
            color: isDark ? AppColors.darkHairline : AppColors.lightHairline,
          ),
        ),
      ],
    );
  }
}
