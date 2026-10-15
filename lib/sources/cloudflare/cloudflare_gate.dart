import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../design/colors.dart';
import '../../design/typography.dart';
import '../../shell/router.dart';

const _prefsKeyPrefix = 'pref.cf_clearance.';
const _androidCookieTtl = Duration(minutes: 25);

bool get cloudflareGateAvailable => Platform.isAndroid;

Future<String?> cachedClearanceCookie(String domain) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefsKeyPrefix$domain');
    if (raw == null) return null;

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final expiresAt = decoded['expiresAt'] as int?;
    if (expiresAt != null && DateTime.now().millisecondsSinceEpoch >= expiresAt) {
      return null;
    }
    return decoded['cookie'] as String?;
  } on Object {
    return null;
  }
}

Future<void> _storeClearanceCookie(String domain, String cookieHeader, int? expiresAtMs) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_prefsKeyPrefix$domain',
      jsonEncode({'cookie': cookieHeader, 'expiresAt': expiresAtMs}),
    );
  } on Object {
    return;
  }
}

Future<String?> solveCloudflareChallenge({
  required String url,
  required List<String> cookieDomains,
}) async {
  if (!cloudflareGateAvailable) return null;

  final context = rootNavigatorKey.currentContext;
  if (context == null) return null;

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _CloudflareSolveDialog(url: url, cookieDomains: cookieDomains),
  );
}

class _CloudflareSolveDialog extends StatefulWidget {
  const _CloudflareSolveDialog({required this.url, required this.cookieDomains});

  final String url;
  final List<String> cookieDomains;

  @override
  State<_CloudflareSolveDialog> createState() => _CloudflareSolveDialogState();
}

class _CloudflareSolveDialogState extends State<_CloudflareSolveDialog> {
  late final WebViewController _controller;
  Timer? _poll;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) => _startPolling()))
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _poll ??= Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_check()));
  }

  Future<void> _check() async {
    if (_done || !mounted) return;

    final manager = WebViewCookieManager();
    for (final domain in widget.cookieDomains) {
      final cookies = await manager.getCookies(domain: Uri.parse('https://$domain'));
      if (cookies.isEmpty) continue;
      if (!cookies.any((c) => c.name == 'cf_clearance')) continue;

      final header = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      if (!mounted) return;

      _done = true;
      _poll?.cancel();
      final expiresAt = DateTime.now().add(_androidCookieTtl).millisecondsSinceEpoch;
      await _storeClearanceCookie(domain, header, expiresAt);
      if (mounted) Navigator.of(context).pop(header);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: VesperColors.canvas,
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 480,
        height: 640,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  const Expanded(child: Text('Verify to continue', style: VesperType.sectionTitle)),
                  IconButton(
                    icon: const Icon(Icons.close, color: VesperColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'This source needs a quick human check. Complete it below.',
                style: VesperType.meta,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                child: WebViewWidget(controller: _controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
