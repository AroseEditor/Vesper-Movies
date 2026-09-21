import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'addon_client.dart';

class AddonsStore {
  const AddonsStore();

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File(p.join(dir.path, 'addons.json'));
  }

  Future<List<InstalledAddon>> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return const [];

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];

      final addons = <InstalledAddon>[];
      for (final entry in decoded) {
        final parsed = InstalledAddon.fromJson(entry);
        if (parsed != null) addons.add(parsed);
      }
      return addons;
    } on Object catch (_) {
      return const [];
    }
  }

  Future<void> save(List<InstalledAddon> addons) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(addons.map((e) => e.toJson()).toList()), flush: true);
    } on Object catch (_) {
      return;
    }
  }
}

final addonClientProvider = Provider<AddonClient>((ref) => AddonClient());

class AddonsNotifier extends AsyncNotifier<List<InstalledAddon>> {
  @override
  Future<List<InstalledAddon>> build() => const AddonsStore().load();

  Future<String?> install(String url) async {
    try {
      final addon = await ref.read(addonClientProvider).install(url);
      final current = state.value ?? const <InstalledAddon>[];

      if (current.any((e) => e.manifestUrl == addon.manifestUrl)) {
        return 'That addon is already installed.';
      }
      if (!addon.providesStream) {
        return 'That addon does not provide streams.';
      }

      final next = [...current, addon];
      state = AsyncValue.data(next);
      await const AddonsStore().save(next);
      return null;
    } on Object catch (_) {
      return 'Could not read that addon manifest.';
    }
  }

  Future<void> remove(InstalledAddon addon) async {
    final current = state.value ?? const <InstalledAddon>[];
    final next = current.where((e) => e.manifestUrl != addon.manifestUrl).toList();
    state = AsyncValue.data(next);
    await const AddonsStore().save(next);
  }

  Future<void> toggle(InstalledAddon addon) async {
    final current = state.value ?? const <InstalledAddon>[];
    final next = [
      for (final entry in current)
        if (entry.manifestUrl == addon.manifestUrl)
          entry.copyWith(enabled: !entry.enabled)
        else
          entry,
    ];
    state = AsyncValue.data(next);
    await const AddonsStore().save(next);
  }
}

final addonsProvider = AsyncNotifierProvider<AddonsNotifier, List<InstalledAddon>>(
  AddonsNotifier.new,
);

final enabledAddonsProvider = Provider<List<InstalledAddon>>((ref) {
  final addons = ref.watch(addonsProvider).value ?? const <InstalledAddon>[];
  return addons.where((e) => e.enabled && e.providesStream).toList();
});
