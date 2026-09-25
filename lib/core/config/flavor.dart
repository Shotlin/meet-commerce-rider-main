/// Build flavor for the Meet Commerce Rider App.
///
/// Drives environment selection (`Env.current`), dev-only affordances
/// (e.g., demo delivery completion, OTP echo on the OTP screen), and log
/// suppression in production.
///
/// Three flavors are supported, matching the Android/iOS build flavors
/// declared in Task 0.1:
/// - [AppFlavor.dev]      - developer builds, demo affordances on
/// - [AppFlavor.staging]  - QA / pre-production builds against the live API
/// - [AppFlavor.prod]     - production builds, no dev affordances
///
/// All three flavors default to the same Meet Commerce backend
/// (see `Env.forFlavor`); flavor only changes UX-level behavior.
///
/// Dart enums are sealed by construction, so external code cannot extend or
/// add new cases. Use [parse] to resolve a wire value (e.g., the
/// `--dart-define=FLAVOR=...` token) into a flavor.
enum AppFlavor {
  dev,
  staging,
  prod;

  /// True iff this flavor is [AppFlavor.dev].
  bool get isDev => this == AppFlavor.dev;

  /// True iff this flavor is [AppFlavor.staging].
  bool get isStaging => this == AppFlavor.staging;

  /// True iff this flavor is [AppFlavor.prod].
  bool get isProd => this == AppFlavor.prod;

  /// Parses a textual flavor token into an [AppFlavor].
  ///
  /// Accepts (case-insensitive, surrounding whitespace trimmed):
  /// - `dev`, `development`            -> [AppFlavor.dev]
  /// - `staging`, `stage`, `qa`        -> [AppFlavor.staging]
  /// - `prod`, `production`, `release` -> [AppFlavor.prod]
  ///
  /// An empty string maps to [AppFlavor.dev] so that test runs and tooling
  /// that do not pass `--dart-define=FLAVOR=...` get the developer build.
  ///
  /// Throws [ArgumentError] for any other value so a typo at the build
  /// command line fails loudly instead of silently degrading to dev.
  static AppFlavor parse(String raw) {
    switch (raw.toLowerCase().trim()) {
      case '':
      case 'dev':
      case 'development':
        return AppFlavor.dev;
      case 'staging':
      case 'stage':
      case 'qa':
        return AppFlavor.staging;
      case 'prod':
      case 'production':
      case 'release':
        return AppFlavor.prod;
      default:
        throw ArgumentError.value(
          raw,
          'raw',
          'Unknown AppFlavor: must be one of dev, staging, prod',
        );
    }
  }
}
