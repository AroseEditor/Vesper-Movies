import '../models/provider_kind.dart';

sealed class SourceError implements Exception {
  const SourceError();

  String userMessage(ProviderKind kind) {
    return switch (this) {
      NetworkError(:final timedOut) => kind.isBdix
          ? '${kind.label} needs a BDIX connection.'
          : timedOut
              ? '${kind.label} timed out.'
              : 'Cannot reach ${kind.label}.',
      RateLimited(:final retryAfterSeconds) => retryAfterSeconds == null
          ? 'Rate limited. Try again later.'
          : 'Rate limited. Wait ${retryAfterSeconds}s.',
      NotFound() => 'No results found.',
      ParseError(:final where) => '${kind.label} returned unexpected data ($where).',
      Unavailable(:final status) => status == null
          ? '${kind.label} is unavailable.'
          : '${kind.label} error ($status).',
      Cancelled() => '',
    };
  }

  @override
  String toString() => switch (this) {
        NetworkError(:final code) => 'NetworkError($code)',
        RateLimited(:final retryAfterSeconds) => 'RateLimited($retryAfterSeconds)',
        NotFound() => 'NotFound',
        ParseError(:final where) => 'ParseError($where)',
        Unavailable(:final status) => 'Unavailable($status)',
        Cancelled() => 'Cancelled',
      };
}

final class NetworkError extends SourceError {
  const NetworkError(this.code, {this.timedOut = false});

  final String code;
  final bool timedOut;
}

final class RateLimited extends SourceError {
  const RateLimited([this.retryAfterSeconds]);

  final int? retryAfterSeconds;
}

final class NotFound extends SourceError {
  const NotFound();
}

final class ParseError extends SourceError {
  const ParseError(this.where);

  final String where;
}

final class Unavailable extends SourceError {
  const Unavailable([this.status]);

  final int? status;
}

final class Cancelled extends SourceError {
  const Cancelled();
}
