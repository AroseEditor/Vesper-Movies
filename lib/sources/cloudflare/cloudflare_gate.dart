import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../design/colors.dart';
import '../../design/typography.dart';
import '../../shell/router.dart';

const _cursorStep = 22.0;
int _syntheticPointer = 90000;

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
  final GlobalKey _webviewKey = GlobalKey();
  final FocusNode _cursorFocus = FocusNode(debugLabel: 'cf-cursor');
  Timer? _poll;
  bool _done = false;
  Offset? _cursor;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) => _startPolling()));
    unawaited(_configureAndLoad());
    WidgetsBinding.instance.addPostFrameCallback((_) => _claimFocus());
  }

  Future<void> _configureAndLoad() async {
    try {
      await WebViewCookieManager().clearCookies();
    } on Object {
      return;
    }

    final android = _controller.platform;
    if (android is AndroidWebViewController) {
      await android.setUseWideViewPort(true);
      await android.setAllowFileAccess(true);
      await android.setAllowContentAccess(true);
      final cookieManager = WebViewCookieManager().platform;
      if (cookieManager is AndroidWebViewCookieManager) {
        await cookieManager.setAcceptThirdPartyCookies(android, true);
      }
    }

    if (!mounted) return;
    await _controller.loadRequest(Uri.parse(widget.url));
  }

  void _claimFocus() {
    if (!mounted) return;
    final size = _webviewSize;
    if (size != null) {
      _cursor ??= Offset(size.width / 2, size.height / 2);
    }
    _cursorFocus.requestFocus();
    setState(() {});
  }

  @override
  void dispose() {
    _poll?.cancel();
    _cursorFocus.dispose();
    super.dispose();
  }

  Future<bool> _challengePageShowing() async {
    try {
      final raw = await _controller.runJavaScriptReturningResult('document.title');
      final title = raw.toString().replaceAll('"', '').trim().toLowerCase();
      if (title.isEmpty) return true;
      return title.contains('just a moment') ||
          title.contains('attention required') ||
          title.contains('checking your browser') ||
          title.contains('verify you are human');
    } on Object {
      return true;
    }
  }

  Size? get _webviewSize => (_webviewKey.currentContext?.findRenderObject() as RenderBox?)?.size;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final size = _webviewSize;
    if (size == null) return KeyEventResult.ignored;

    final current = _cursor ?? Offset(size.width / 2, size.height / 2);
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        setState(
          () => _cursor = Offset(current.dx, (current.dy - _cursorStep).clamp(0, size.height)),
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        setState(
          () => _cursor = Offset(current.dx, (current.dy + _cursorStep).clamp(0, size.height)),
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        setState(
          () => _cursor = Offset((current.dx - _cursorStep).clamp(0, size.width), current.dy),
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        setState(
          () => _cursor = Offset((current.dx + _cursorStep).clamp(0, size.width), current.dy),
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.gameButtonA:
        setState(() => _cursor = current);
        _tapAt(current);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  void _tapAt(Offset local) {
    final box = _webviewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final global = box.localToGlobal(local);
    final pointer = _syntheticPointer++;

    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: pointer, position: global, kind: PointerDeviceKind.touch),
    );
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(pointer: pointer, position: global, kind: PointerDeviceKind.touch),
    );
  }

  void _startPolling() {
    _poll ??= Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_check()));
  }

  Future<void> _check() async {
    if (_done || !mounted) return;
    if (await _challengePageShowing()) return;
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
    final tv = MediaQuery.navigationModeOf(context) == NavigationMode.directional;

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
                  ExcludeFocus(
                    excluding: tv,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: VesperColors.textSecondary),
                      onPressed: () => Navigator.of(context).pop(null),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                tv
                    ? 'This source needs a quick human check. Use the arrow keys to move the '
                          'dot onto the checkbox, then press select.'
                    : 'This source needs a quick human check. Complete it below.',
                style: VesperType.meta,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                child: Stack(
                  key: _webviewKey,
                  children: [
                    Positioned.fill(child: WebViewWidget(controller: _controller)),
                    if (tv)
                      Positioned.fill(
                        child: Focus(
                          focusNode: _cursorFocus,
                          autofocus: true,
                          onKeyEvent: _handleKey,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    if (tv && _cursor != null)
                      Positioned(
                        left: _cursor!.dx - 10,
                        top: _cursor!.dy - 10,
                        child: IgnorePointer(
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: VesperColors.danger.withValues(alpha: 0.9),
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
