import 'package:flutter/foundation.dart';

import 'flavor.dart';

/// Immutable environment value object.
///
/// Encapsulates everything that varies (or could vary) per flavor: the REST
/// base URL, the Socket.IO base URL, and the dev-affordance gate. Feature
/// code depends on `Env` without caring how the flavor was resolved.
///
/// Resolution order for the two transport URLs:
/// 1. `--dart-define=API_BASE_URL=...` / `--dart-define=SOCKET_BASE_URL=...`
///    (used for local Docker integration, e.g.
///    `--dart-define=API_BASE_URL=http://localhost:4500/api/v1`);
/// 2. the Meet Commerce backend host below.
///
/// Resolve the active environment via [Env.current], which reads
/// `--dart-define=FLAVOR=...` (defaulting to `dev` when unset).
@immutable
class Env {
  /// Constructs an [Env] explicitly. Most call sites should use
  /// [Env.forFlavor] or [Env.current].
  const Env({
    required this.apiBaseUrl,
    required this.socketBaseUrl,
    required this.flavor,
    required this.enableDevAffordances,
    this.tileUrlTemplate = _defaultTileUrlTemplate,
  });

  /// Builds the canonical [Env] for [flavor].
  ///
  /// Every flavor defaults to the Meet Commerce backend
  /// (`https://api.fc.opslin.com`) — the same host the Meet Commerce customer
  /// app uses. Override per build with `--dart-define=API_BASE_URL=...` and
  /// `--dart-define=SOCKET_BASE_URL=...` when integrating against the
  /// locally running backend.
  factory Env.forFlavor(AppFlavor flavor) {
    return Env(
      apiBaseUrl: _apiBaseUrlOverride.isEmpty
          ? _defaultApiBaseUrl
          : _apiBaseUrlOverride,
      socketBaseUrl: _socketBaseUrlOverride.isEmpty
          ? _defaultSocketBaseUrl
          : _socketBaseUrlOverride,
      flavor: flavor,
      enableDevAffordances: flavor.isDev,
      tileUrlTemplate: _defaultTileUrlTemplate,
    );
  }

  /// Raster tile URL template used by the interim Flutter map renderer.
  ///
  /// INTERIM ONLY — the production map/navigation stack for this app is Ola
  /// Maps (see Big Phase 12 of the rebuild plan). This provider and the
  /// `flutter_map` dependency that consumes it are removed once the Ola
  /// implementation is proven on both platforms. Nothing here may be treated
  /// as the production map provider.
  final String tileUrlTemplate;

  /// Interim raster tile endpoint (see [tileUrlTemplate]).
  static const String _defaultTileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// REST API root, e.g. `https://api.fc.opslin.com/api/v1`.
  ///
  /// All authenticated and unauthenticated calls go through this base.
  final String apiBaseUrl;

  /// Socket.IO endpoint root, e.g. `https://api.fc.opslin.com`.
  ///
  /// The Socket.IO client is configured with `transports: ['websocket']`
  /// against this URL.
  final String socketBaseUrl;

  /// Active build flavor.
  final AppFlavor flavor;

  /// Whether to render developer-only affordances (demo complete button,
  /// OTP echo on the OTP screen, verbose state logs).
  ///
  /// True iff [flavor] is [AppFlavor.dev]. Production builds MUST never
  /// surface these affordances regardless of backend response shape.
  final bool enableDevAffordances;

  // Meet Commerce backend host — the same origin the FreshCuts customer app
  // talks to.
  static const String _defaultApiBaseUrl = 'https://api.fc.opslin.com/api/v1';
  static const String _defaultSocketBaseUrl = 'https://api.fc.opslin.com';

  /// Compile-time overrides. Empty when the corresponding `--dart-define`
  /// was not supplied.
  static const String _apiBaseUrlOverride = String.fromEnvironment(
    'API_BASE_URL',
  );
  static const String _socketBaseUrlOverride = String.fromEnvironment(
    'SOCKET_BASE_URL',
  );

  /// Raw `FLAVOR` token passed via `--dart-define=FLAVOR=...`.
  ///
  /// Resolved at compile time so tree-shaking can eliminate dev-only
  /// branches from production builds.
  static const String _flavorRaw = String.fromEnvironment(
    'FLAVOR',
    defaultValue: 'dev',
  );

  /// The resolved environment for this build.
  ///
  /// Computed once on first access and memoized.
  static final Env current = Env.forFlavor(AppFlavor.parse(_flavorRaw));

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Env &&
        other.apiBaseUrl == apiBaseUrl &&
        other.socketBaseUrl == socketBaseUrl &&
        other.flavor == flavor &&
        other.enableDevAffordances == enableDevAffordances &&
        other.tileUrlTemplate == tileUrlTemplate;
  }

  @override
  int get hashCode => Object.hash(
    apiBaseUrl,
    socketBaseUrl,
    flavor,
    enableDevAffordances,
    tileUrlTemplate,
  );

  @override
  String toString() {
    return 'Env('
        'flavor=${flavor.name}, '
        'apiBaseUrl=$apiBaseUrl, '
        'socketBaseUrl=$socketBaseUrl, '
        'enableDevAffordances=$enableDevAffordances'
        ')';
  }
}
