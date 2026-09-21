import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sources/addons/addon_client.dart';
import '../sources/addons/addons_store.dart';
import 'library_controller.dart';
import 'library_store.dart';

const backupFormat = 'vesper-backup';
const backupVersion = 1;

class BackupContents {
  const BackupContents({required this.library, required this.addons});

  final LibraryData library;
  final List<InstalledAddon> addons;
}

Uint8List encodeBackup(BackupContents contents, {DateTime? at}) {
  final payload = {
    'format': backupFormat,
    'version': backupVersion,
    'createdAt': (at ?? DateTime.now()).toUtc().toIso8601String(),
    'library': libraryToJson(contents.library),
    'addons': contents.addons.map((e) => e.toJson()).toList(),
  };
  return Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)));
}

BackupContents? decodeBackup(List<int> bytes) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map || decoded['format'] != backupFormat) return null;

    final addons = <InstalledAddon>[];
    final rawAddons = decoded['addons'];
    if (rawAddons is List) {
      for (final entry in rawAddons) {
        final parsed = InstalledAddon.fromJson(entry);
        if (parsed != null) addons.add(parsed);
      }
    }
    return BackupContents(library: libraryFromJson(decoded['library']), addons: addons);
  } on Object {
    return null;
  }
}

Future<String> exportBackup(WidgetRef ref) async {
  final library = ref.read(libraryProvider).value ?? const LibraryData();
  final addons = ref.read(addonsProvider).value ?? const <InstalledAddon>[];
  final now = DateTime.now();
  final stamp =
      '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

  try {
    final saved = await FilePicker.saveFile(
      fileName: 'vesper-backup-$stamp.json',
      bytes: encodeBackup(
        BackupContents(library: library, addons: addons),
        at: now,
      ),
      mimeType: 'application/json',
      dialogTitle: 'Save Vesper backup',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (saved == null) return 'Backup cancelled.';
    return 'Backup saved: ${library.history.length} watched, '
        '${library.favourites.length} in My List, ${addons.length} addons.';
  } on Object {
    return 'Could not save the backup.';
  }
}

Future<String> importBackup(WidgetRef ref) async {
  try {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Open Vesper backup',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (picked == null) return 'Restore cancelled.';

    final contents = decodeBackup(await picked.readAsBytes());
    if (contents == null) return 'That file is not a Vesper backup.';

    await ref.read(libraryProvider.notifier).restore(contents.library);
    final addons = await ref.read(addonsProvider.notifier).restore(contents.addons);
    return 'Restored ${contents.library.history.length} watched, '
        '${contents.library.favourites.length} in My List, $addons new addons.';
  } on Object {
    return 'Could not read that backup.';
  }
}
