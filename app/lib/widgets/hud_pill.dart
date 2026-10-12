// hud_pill.dart: small glassy label floating over the camera. UI only.
// Example: "● Live · 2 faces" or "ML Kit · 24 ms".

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/theme.dart';

class HudPill extends StatelessWidget {
  final String text;
  final Color? dot; // optional colored dot before the text
  final bool mono; // use the mono font (for numbers)
  final Widget? leading; // e.g. signal bars, drawn instead of the dot

  const HudPill({
    super.key,
    required this.text,
    this.dot,
    this.mono = false,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: AppColors.glass,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.line2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 6)],
              if (dot != null && leading == null) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Text(text, style: mono ? AppText.mono : AppText.pill),
            ],
          ),
        ),
      ),
    );
  }
}
