/// App-wide non-secret constants.
///
/// This is the single source of truth for default timeouts, location
/// throttling budgets, image compression parameters, and shared copy used
/// across empty / error / offline states. Anything that could plausibly
/// change per build flavor lives in [Env]; everything else lives here.
///
/// Marked `abstract final` so callers cannot instantiate or extend it.
abstract final class AppConstants {
  // ---------------------------------------------------------------------------
  // Network defaults (R1, R3)
  // ---------------------------------------------------------------------------

  /// Time to establish a TCP connection before failing.
  static const Duration connectTimeout = Duration(seconds: 30);

  /// Time to receive a complete response body before failing.
  static const Duration receiveTimeout = Duration(seconds: 40);

  /// Time to write a request body before failing.
  static const Duration sendTimeout = Duration(seconds: 40);

  /// Default delivery profile fetch timeout used by the Session_Restorer.
  static const Duration profileFetchTimeout = Duration(seconds: 30);

  // ---------------------------------------------------------------------------
  // Location throttling (R17)
  // ---------------------------------------------------------------------------

  /// Sliding window for the rate budget. Defined by the spec as one minute.
  static const Duration locationRateWindow = Duration(seconds: 60);

  /// Per-minute upload budget while online but without an active delivery.
  static const int locationBudgetWaitingPerMinute = 2;

  /// Per-minute upload budget after the rider has accepted an offer
  /// (heading to the store).
  static const int locationBudgetAcceptedPerMinute = 6;

  /// Per-minute upload budget while in transit to the customer.
  static const int locationBudgetInTransitPerMinute = 12;

  /// Distance filter (metres) for the waiting-online profile.
  static const int locationDistanceFilterWaitingMeters = 75;

  /// Distance filter (metres) for the heading-to-store profile.
  static const int locationDistanceFilterAcceptedMeters = 30;

  /// Distance filter (metres) for the in-transit profile.
  static const int locationDistanceFilterInTransitMeters = 20;

  /// REST keepalive interval. We force a REST upload at least this often
  /// while online so the backend always has a recent fix.
  static const Duration locationRestKeepalive = Duration(seconds: 60);

  /// Threshold after which the socket is considered "stale" and a REST
  /// upload is sent in addition to the next socket emit.
  static const Duration locationSocketStaleThreshold = Duration(seconds: 20);

  // ---------------------------------------------------------------------------
  // Map screen (R12)
  // ---------------------------------------------------------------------------

  /// Window during which a manual pan suppresses auto-recenter.
  static const Duration manualPanSuppressionWindow = Duration(seconds: 6);

  /// Camera animation duration for recenter actions.
  static const Duration cameraAnimationDuration = Duration(milliseconds: 280);

  // ---------------------------------------------------------------------------
  // Image compression (R4, R15)
  // ---------------------------------------------------------------------------

  /// Longest edge in pixels for compressed JPEG uploads (rider documents,
  /// proof photos).
  static const int imageMaxLongestEdgePx = 1600;

  /// JPEG quality in the 0-100 range for compressed uploads.
  static const int imageJpegQuality = 80;

  // ---------------------------------------------------------------------------
  // Auth (R1)
  // ---------------------------------------------------------------------------

  /// Cooldown between OTP resend attempts.
  static const Duration otpResendCooldown = Duration(seconds: 30);

  /// Length of the login OTP entered on the OTP screen.
  static const int loginOtpLength = 6;

  /// Length of the customer delivery OTP entered on the deliver sheet.
  static const int deliveryOtpLength = 4;

  // ---------------------------------------------------------------------------
  // Realtime (R7)
  // ---------------------------------------------------------------------------

  /// Lower bound for the Socket.IO reconnection backoff.
  static const Duration socketReconnectBaseDelay = Duration(seconds: 1);

  /// Upper bound for the Socket.IO reconnection backoff (R7.3).
  static const Duration socketReconnectMaxDelay = Duration(seconds: 30);

  // ---------------------------------------------------------------------------
  // Copy strings (R5, R8, R10, R11, R14)
  //
  // These are intentionally short, sentence-case strings without trailing
  // punctuation variation so QA can grep for them. They are NOT translated
  // for the MVP demo; localization is deferred.
  // ---------------------------------------------------------------------------

  /// Empty-state copy when the rider is online and has no offers.
  static const String emptyStateOnlineWaiting =
      'You are online. Waiting for orders near your store';

  /// Empty-state copy when the rider is offline.
  static const String emptyStateOffline =
      'You are offline. Go online to receive orders';

  /// Generic error title for inline error cards.
  static const String errorTitleGeneric = 'Something went wrong';

  /// Generic error body / retry hint.
  static const String errorBodyRetry = 'Tap to retry';

  /// Banner shown when the device has no connectivity.
  static const String offlineBannerCopy =
      'You are offline. Some features may be unavailable';

  /// Trust line under the phone-login call to action (design §7: "concise
  /// trust/support copy"). Deliberately states only what the login flow
  /// actually does — the number is used to sign the rider in — rather than
  /// making support-channel promises the app cannot keep.
  static const String loginTrustCopy =
      'We use your number only to sign you in and keep your rider account '
      'secure.';

  /// Pill / banner copy while the socket is reconnecting.
  static const String connectingPillCopy = 'Connecting';

  /// Toast shown when an offer expires before the rider can accept.
  static const String toastOfferExpired = 'Offer expired';

  /// Toast shown after a reject succeeds.
  static const String toastOfferDeclined = 'Order declined';

  /// Error shown when accept conflicts with another rider.
  static const String errorOrderAlreadyTaken =
      'Order was already taken by another rider';
}
