// my_code_sheet.dart: "Your Aaina code" sheet with a QR code. UI only.
//
// Someone else can scan it in QR mode to open your card, e.g. when the
// camera can't recognise you (bad light, mask). The code only opens the
// card you already share; nothing else. "New code" cancels the old one.
//
// The QR is drawn on the phone by the qr_flutter package (free, offline).

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/theme.dart';
import 'aaina_logo.dart';

/// Opens the sheet. [loadCode] fetches the current code; [newCode] asks the
/// server for a fresh one. Both return null on failure.
Future<void> showMyCodeSheet(
  BuildContext context, {
  required String name,
  required Future<String?> Function() loadCode,
  required Future<String?> Function() newCode,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _MyCodeSheet(name: name, loadCode: loadCode, newCode: newCode),
  );
}

class _MyCodeSheet extends StatefulWidget {
  final String name;
  final Future<String?> Function() loadCode;
  final Future<String?> Function() newCode;

  const _MyCodeSheet({required this.name, required this.loadCode, required this.newCode});

  @override
  State<_MyCodeSheet> createState() => _MyCodeSheetState();
}

class _MyCodeSheetState extends State<_MyCodeSheet> {
  String? _code;
  bool _busy = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _run(widget.loadCode);
  }

  Future<void> _run(Future<String?> Function() job) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    final code = await job();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (code != null) {
        _code = code;
      } else {
        _failed = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.sheetTop, AppColors.sheetBottom],
        ),
        border: Border(top: BorderSide(color: AppColors.accent.withValues(alpha: 0.4))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line2,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Your Aaina code', style: AppText.sheetTitle),
              const SizedBox(height: 4),
              Text(
                "Let someone scan this if the camera can't recognise you.",
                style: AppText.small.copyWith(fontSize: 12.5),
              ),
              const SizedBox(height: 18),
              Center(child: _qrBox()),
              const SizedBox(height: 12),
              Text(widget.name,
                  textAlign: TextAlign.center,
                  style: AppText.arName.copyWith(fontSize: 17)),
              const SizedBox(height: 3),
              Text('SHOWS YOUR CARD, NOTHING ELSE',
                  textAlign: TextAlign.center, style: AppText.fine),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _run(widget.newCode),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        side: const BorderSide(color: AppColors.line2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md)),
                      ),
                      child: Text('New code',
                          style: AppText.bodyStrong.copyWith(fontSize: 13.5)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md)),
                      ),
                      child: Text('Done', style: AppText.button),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('New code = old screenshots stop working',
                  textAlign: TextAlign.center, style: AppText.fine),
            ],
          ),
        ),
      ),
    );
  }

  Widget _qrBox() {
    const size = 210.0;
    Widget inside;
    if (_busy && _code == null) {
      inside = const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accent),
        ),
      );
    } else if (_code == null) {
      inside = Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            _failed ? "Couldn't reach the laptop. Try again in a moment." : '',
            textAlign: TextAlign.center,
            style: AppText.small.copyWith(color: AppColors.sheetBottom),
          ),
        ),
      );
    } else {
      inside = AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _busy ? 0.25 : 1,
        child: Stack(
          alignment: Alignment.center,
          children: [
            QrImageView(
              data: _code!,
              padding: EdgeInsets.zero,
              // High error correction so the logo in the middle doesn't break it.
              errorCorrectionLevel: QrErrorCorrectLevel.H,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: AppColors.sheetBottom,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: AppColors.sheetBottom,
              ),
            ),
            // Aaina mark in the middle.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.sheetBottom,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: const AainaMark(height: 14),
            ),
          ],
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F5F8),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: AppColors.accent.withValues(alpha: 0.5), spreadRadius: 1),
          BoxShadow(color: AppColors.accent.withValues(alpha: 0.35), blurRadius: 36),
        ],
      ),
      child: inside,
    );
  }
}
