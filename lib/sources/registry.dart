import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../models/media.dart';
import '../models/provider_kind.dart';
import 'bdix/circleftp_source.dart';
import 'bdix/dhakaflix_source.dart';
import 'content_source.dart';
import 'dramachi/dramachi_source.dart';
import 'fourkhdhub/fourkhdhub_source.dart';
import 'moviebox/moviebox_source.dart';

final sourceRegistryProvider = Provider<Map<ProviderKind, ContentSource>>((ref) {
  return {
    ProviderKind.moviebox: MovieBoxSource(),
    ProviderKind.dramachi: DramachiSource(),
    ProviderKind.fourkhdhub: FourKHdHubSource(),
    ProviderKind.circleftp: CircleFtpSource(),
    ProviderKind.dhakaflix: DhakaFlixSource(),
  };
});

final enabledSourcesProvider = Provider<List<ProviderKind>>((ref) {
  return ref.watch(sourceRegistryProvider).keys.toList();
});

final mediaDetailsProvider = FutureProvider.autoDispose.family<MediaDetails, MediaId>((
  ref,
  id,
) async {
  final cancel = CancelToken();
  ref.onDispose(cancel.cancel);

  final source = ref.watch(sourceRegistryProvider)[id.kind];
  if (source == null) throw const Unavailable();

  return source.details(id.value, cancel: cancel);
});
