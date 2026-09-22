import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/secure_dns.dart';
import '../../core/update_check.dart';
import '../../design/colors.dart';
import '../../design/icons.dart';
import '../../design/typography.dart';
import '../../design/widgets/focusable_item.dart';
import '../../player/external_player.dart';
import '../../player/quality_cap.dart';
import '../../player/subtitle_style.dart';
import '../../shell/input_mode.dart';
import '../../sources/addons/addon_client.dart';
import '../../sources/addons/addons_store.dart';
import '../../storage/backup.dart';
import '../../storage/library_controller.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _addAddon(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: VesperColors.surface,
        title: const Text('Add a stream addon', style: VesperType.sectionTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste the manifest URL of any Stremio compatible addon.',
              style: VesperType.body,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              style: VesperType.body.copyWith(color: VesperColors.textPrimary),
              cursorColor: VesperColors.accent,
              decoration: const InputDecoration(
                hintText: 'https://example.com/manifest.json',
                hintStyle: VesperType.meta,
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: VesperColors.divider),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: VesperColors.accent),
                ),
              ),
              onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel', style: VesperType.label),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text('Add', style: VesperType.label.copyWith(color: VesperColors.accent)),
          ),
        ],
      ),
    );

    if (url == null || url.trim().isEmpty) return;
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final error = await ref.read(addonsProvider.notifier).install(url);

    messenger.showSnackBar(
      SnackBar(
        content: Text(error ?? 'Addon installed.'),
        backgroundColor: VesperColors.surfaceRaised,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(inputModeProvider);
    final addons = ref.watch(addonsProvider).value ?? const <InstalledAddon>[];
    final history = ref.watch(libraryProvider).value?.history ?? const [];

    return Scaffold(
      backgroundColor: VesperColors.canvas,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(mode.gutter, 18, mode.gutter, 40),
          children: [
            Row(
              children: [
                FocusableItem(
                  onActivate: () => Navigator.of(context).maybePop(),
                  borderRadius: 22,
                  scaleOnFocus: false,
                  semanticLabel: 'Back',
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(VesperIcons.back, size: 24),
                  ),
                ),
                const SizedBox(width: 10),
                const Text('Settings', style: VesperType.sectionTitle),
              ],
            ),
            const SizedBox(height: 26),
            const _SectionHeader(
              title: 'Stream addons',
              subtitle: 'Vesper resolves streams from MovieBox plus any Stremio compatible addon you add.',
            ),
            const SizedBox(height: 10),
            if (addons.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No addons installed.', style: VesperType.body),
              )
            else
              for (final addon in addons)
                _AddonRow(
                  addon: addon,
                  onToggle: () => ref.read(addonsProvider.notifier).toggle(addon),
                  onRemove: () => ref.read(addonsProvider.notifier).remove(addon),
                ),
            const SizedBox(height: 12),
            _ActionButton(
              icon: VesperIcons.add,
              label: 'Add addon',
              onTap: () => _addAddon(context, ref),
            ),
            const SizedBox(height: 32),
            const _SectionHeader(
              title: 'Playback',
              subtitle:
                  'Choose the player, and cap the stream quality on slow connections. Auto picks '
                  'the best stream, preferring 1080p on phones. VLC opens the best direct stream.',
            ),
            const SizedBox(height: 10),
            _SettingRow(
              label: 'Play with',
              value: ref.watch(playerChoiceProvider).label,
              onPrevious: () => ref.read(playerChoiceProvider.notifier).cycle(),
              onNext: () => ref.read(playerChoiceProvider.notifier).cycle(),
            ),
            _SettingRow(
              label: 'Prefer Hindi audio',
              value: ref.watch(preferHindiProvider) ? 'On' : 'Off',
              onPrevious: () => ref.read(preferHindiProvider.notifier).toggle(),
              onNext: () => ref.read(preferHindiProvider.notifier).toggle(),
            ),
            _SettingRow(
              label: 'Maximum quality',
              value: ref.watch(qualityCapProvider).label,
              onPrevious: () => ref.read(qualityCapProvider.notifier).cycle(-1),
              onNext: () => ref.read(qualityCapProvider.notifier).cycle(1),
            ),
            const SizedBox(height: 32),
            const _SectionHeader(
              title: 'Subtitles',
              subtitle: 'These defaults apply to every stream. You can still change them mid play.',
            ),
            const SizedBox(height: 10),
            const _SubtitleDefaults(),
            const SizedBox(height: 32),
            const _SectionHeader(
              title: 'Watch history',
              subtitle: 'Continue Watching is built from what you have played.',
            ),
            const SizedBox(height: 10),
            Text('${history.length} titles remembered', style: VesperType.body),
            const SizedBox(height: 12),
            _ActionButton(
              icon: VesperIcons.deleteItem,
              label: 'Clear history',
              onTap: () => ref.read(libraryProvider.notifier).clearHistory(),
            ),
            const SizedBox(height: 32),
            const _SectionHeader(
              title: 'Backup',
              subtitle: 'Save My List, watch history and addons to a file, or restore them after a reinstall.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                _ActionButton(
                  icon: VesperIcons.backup,
                  label: 'Back up to a file',
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final message = await exportBackup(ref);
                    messenger.showSnackBar(SnackBar(content: Text(message)));
                  },
                ),
                _ActionButton(
                  icon: VesperIcons.restore,
                  label: 'Restore from a file',
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final message = await importBackup(ref);
                    messenger.showSnackBar(SnackBar(content: Text(message)));
                  },
                ),
              ],
            ),
            const SizedBox(height: 32),
            const _SectionHeader(
              title: 'Network',
              subtitle:
                  'Vesper looks up servers over encrypted DNS so carrier blocks do not stop it. '
                  'Turn the playback route off if videos will not start on your connection.',
            ),
            const SizedBox(height: 12),
            const _PlaybackRouteToggle(),
            const SizedBox(height: 32),
            const _SectionHeader(
              title: 'Updates',
              subtitle: 'Checks the public release list on GitHub. Nothing about you is sent.',
            ),
            const SizedBox(height: 12),
            const _UpdateStatus(),
            const SizedBox(height: 32),
            const _SectionHeader(
              title: 'Privacy',
              subtitle:
                  'No telemetry, no analytics, no server run by this project. Logs never contain '
                  'an IP, a search query or a full request URL.',
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: VesperType.bodyStrong.copyWith(fontSize: 17)),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Text(subtitle, style: VesperType.meta),
        ),
      ],
    );
  }
}

class _AddonRow extends StatelessWidget {
  const _AddonRow({required this.addon, required this.onToggle, required this.onRemove});

  final InstalledAddon addon;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: VesperColors.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Icon(
                VesperIcons.source,
                size: 20,
                color: addon.enabled ? VesperColors.accent : VesperColors.textTertiary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      addon.name,
                      style: VesperType.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (addon.description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        addon.description!,
                        style: VesperType.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              FocusableItem(
                onActivate: onToggle,
                borderRadius: 16,
                scaleOnFocus: false,
                semanticLabel: addon.enabled ? 'Disable ${addon.name}' : 'Enable ${addon.name}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    addon.enabled ? 'On' : 'Off',
                    style: VesperType.label.copyWith(
                      color: addon.enabled ? VesperColors.accent : VesperColors.textTertiary,
                    ),
                  ),
                ),
              ),
              FocusableItem(
                onActivate: onRemove,
                borderRadius: 16,
                scaleOnFocus: false,
                semanticLabel: 'Remove ${addon.name}',
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(VesperIcons.deleteItem, size: 19, color: VesperColors.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtitleDefaults extends ConsumerWidget {
  const _SubtitleDefaults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(subtitleDefaultsProvider);
    final notifier = ref.read(subtitleDefaultsProvider.notifier);

    return Column(
      children: [
        _SettingRow(
          label: 'Size',
          value: style.size.label,
          onPrevious: () => notifier.cycleSize(-1),
          onNext: () => notifier.cycleSize(1),
        ),
        _SettingRow(
          label: 'Colour',
          value: style.colour.label,
          onPrevious: () => notifier.cycleColour(-1),
          onNext: () => notifier.cycleColour(1),
        ),
        _SettingRow(
          label: 'Background',
          value: style.background.label,
          onPrevious: () => notifier.cycleBackground(-1),
          onNext: () => notifier.cycleBackground(1),
        ),
        _SettingRow(
          label: 'Position',
          value: '${style.position}',
          onPrevious: () => notifier.nudgePosition(-5),
          onNext: () => notifier.nudgePosition(5),
        ),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.value,
    required this.onPrevious,
    required this.onNext,
  });

  final String label;
  final String value;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: VesperType.body)),
          _Stepper(icon: VesperIcons.chevronLeft, onTap: onPrevious, label: 'Decrease $label'),
          SizedBox(
            width: 110,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: VesperType.bodyStrong,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _Stepper(icon: VesperIcons.chevronRight, onTap: onNext, label: 'Increase $label'),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.icon, required this.onTap, required this.label});

  final IconData icon;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FocusableItem(
      onActivate: onTap,
      borderRadius: 14,
      scaleOnFocus: false,
      semanticLabel: label,
      child: Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(color: VesperColors.surface, shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: VesperColors.textSecondary),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: FocusableItem(
        onActivate: onTap,
        borderRadius: 6,
        scaleOnFocus: false,
        semanticLabel: label,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: VesperColors.surface,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: VesperColors.accent),
              const SizedBox(width: 8),
              Text(label, style: VesperType.label.copyWith(color: VesperColors.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateStatus extends ConsumerWidget {
  const _UpdateStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final check = ref.watch(updateCheckProvider);
    final info = check.value;

    final String status;
    if (check.isLoading) {
      status = 'Checking for updates';
    } else if (info == null) {
      status = 'Could not reach GitHub right now.';
    } else if (info.isNewer) {
      status = 'Version ${info.latest} is available. You have ${info.current}.';
    } else {
      status = 'You are on the latest version, ${info.current}.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(status, style: VesperType.body),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            if (info != null && info.isNewer)
              _ActionButton(
                icon: VesperIcons.update,
                label: 'Get version ${info.latest}',
                onTap: () => launchUrl(Uri.parse(info.url), mode: LaunchMode.externalApplication),
              ),
            _ActionButton(
              icon: VesperIcons.refresh,
              label: 'Check again',
              onTap: () => ref.invalidate(updateCheckProvider),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlaybackRouteToggle extends StatefulWidget {
  const _PlaybackRouteToggle();

  @override
  State<_PlaybackRouteToggle> createState() => _PlaybackRouteToggleState();
}

class _PlaybackRouteToggleState extends State<_PlaybackRouteToggle> {
  bool _on = StreamTunnel.routePlayback;

  @override
  Widget build(BuildContext context) {
    return FocusableItem(
      onActivate: () {
        final next = !_on;
        setState(() => _on = next);
        StreamTunnel.setRoutePlayback(next);
      },
      borderRadius: 6,
      scaleOnFocus: false,
      semanticLabel: 'Route playback through encrypted DNS',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            const Expanded(
              child: Text('Route playback through encrypted DNS', style: VesperType.body),
            ),
            Switch(
              value: _on,
              activeThumbColor: VesperColors.accent,
              onChanged: (value) {
                setState(() => _on = value);
                StreamTunnel.setRoutePlayback(value);
              },
            ),
          ],
        ),
      ),
    );
  }
}
