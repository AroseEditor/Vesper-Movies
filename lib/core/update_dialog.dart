import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design/colors.dart';
import '../design/typography.dart';
import '../design/widgets/focusable_item.dart';
import 'update_check.dart';
import 'update_install.dart';

Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _UpdateDialog(info: info),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info});

  final UpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double _progress = 0;
  InstallResult? _result;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _result = null;
      _progress = 0;
    });
    final result = await installUpdate(widget.info, (value) {
      if (mounted) setState(() => _progress = value);
    });
    if (!mounted) return;
    if (result == InstallResult.started || result == InstallResult.openedPage) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final message = switch (result) {
      null => 'Downloading version ${widget.info.latest}',
      InstallResult.needsPermission =>
        'Allow Vesper to install apps in the screen that just opened, then choose Try again.',
      _ => 'The download did not finish. Check your connection and try again.',
    };

    return Dialog(
      backgroundColor: VesperColors.surfaceRaised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Updating Vesper', style: VesperType.sectionTitle),
              const SizedBox(height: 12),
              Text(message, style: VesperType.body),
              const SizedBox(height: 18),
              if (result == null)
                LinearProgressIndicator(
                  value: _progress <= 0 ? null : _progress,
                  color: VesperColors.accent,
                  backgroundColor: VesperColors.surfaceHover,
                )
              else
                Row(
                  children: [
                    FocusableItem(
                      autofocus: true,
                      onActivate: _run,
                      borderRadius: 6,
                      scaleOnFocus: false,
                      semanticLabel: 'Try again',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        color: VesperColors.accent,
                        child: const Text('Try again', style: VesperType.button),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FocusableItem(
                      onActivate: () {
                        launchUrl(Uri.parse(widget.info.url), mode: LaunchMode.externalApplication);
                        Navigator.of(context).pop();
                      },
                      borderRadius: 6,
                      scaleOnFocus: false,
                      semanticLabel: 'Open the download page',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        color: VesperColors.surface,
                        child: const Text('Download page', style: VesperType.label),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FocusableItem(
                      onActivate: () => Navigator.of(context).pop(),
                      borderRadius: 6,
                      scaleOnFocus: false,
                      semanticLabel: 'Close',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        color: VesperColors.surface,
                        child: const Text('Close', style: VesperType.label),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
