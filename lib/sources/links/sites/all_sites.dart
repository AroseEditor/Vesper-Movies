import '../../../models/provider_kind.dart';
import '../link_source.dart';
import '../web.dart';
import 'hdhub4u_source.dart';

Map<ProviderKind, LinkSource> buildLinkSources(Web web) {
  final sources = <LinkSource>[HdHub4uSource(web)];
  return {for (final source in sources) source.kind: source};
}
