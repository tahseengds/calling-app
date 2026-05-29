import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import 'lumio_icons.dart';

/// Lumio text field — floating label, 56 px min height, 16 px radius.
class FlTextField extends StatefulWidget {
  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool obscureText;
  final bool showToggle;
  final Widget? prefixWidget;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onFieldSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final String? hint;
  final bool readOnly;
  final int? maxLines;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;

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
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
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
    final fillColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final fg3 = isDark ? AppColors.darkFg3 : AppColors.lightFg2;

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
      autofillHints: widget.autofillHints,
      textCapitalization: widget.textCapitalization,
      style: TextStyle(
        fontSize: 16,
        color: isDark ? AppColors.darkFg1 : AppColors.lightFg1,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        hintStyle: TextStyle(color: fg3, fontSize: 15),
        fillColor: fillColor,
        prefixIcon: widget.prefixWidget != null
            ? Padding(
                padding: const EdgeInsets.only(left: 16, right: 8),
                child: widget.prefixWidget,
              )
            : null,
        prefixIconConstraints: widget.prefixWidget != null
            ? const BoxConstraints(minWidth: 0, minHeight: 0)
            : null,
        suffixIcon: widget.showToggle
            ? Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Material(
                  color: (isDark
                          ? AppColors.darkSurfaceLo
                          : AppColors.lightSurfaceLo)
                      .withAlpha(180),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _obscure = !_obscure),
                    child: Semantics(
                      button: true,
                      label: _obscure ? 'Show password' : 'Hide password',
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(
                          _obscure ? LumioIcons.eye : LumioIcons.eyeOff,
                          size: 20,
                          color: fg3,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : null,
        constraints: const BoxConstraints(minHeight: 56),
      ),
    );
  }
}

/// Phone prefix: US flag SVG + +1 + divider (lumio-screens-design.html).
class PhonePrefix extends StatelessWidget {
  const PhonePrefix({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const UsFlagIcon(),
        const SizedBox(width: 8),
        Text(
          '+1',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: isDark ? AppColors.darkFg2 : AppColors.lightFg2,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
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
