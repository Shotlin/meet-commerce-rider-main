import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/location/location_permission_service.dart';
import '../../../core/location/location_permission_status.dart';
import '../../../core/location/location_service.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../../delivery/data/delivery_api.dart';

/// Snapshot consumed by the home screen's online toggle.
///
/// Each field is a flag the UI can react to without inspecting the
/// underlying error chain:
///
/// - [isOnline]: whether the rider is currently online (mirrors the
///   backend, optimistic). The home screen drives the toggle visual
///   off this flag.
/// - [isBusy]: a backend call is in flight (toggle-online,
///   updateLocation, or fetching the GPS fix). The toggle should be
///   non-interactive while busy.
/// - [errorMessage]: user-facing copy from the latest failure, or
///   `null` when the last action succeeded or none has run.
/// - [permissionEducationNeeded]: set to `true` when [goOnline]
///   short-circuits because location permission or service was not
///   granted (R6.2 / R6.3). The home screen routes the rider to the
///   permission education flow.
/// - [serviceDisabled]: set to `true` when [goOnline] short-circuits
///   because location services are turned off (R6.2). The UI surfaces
///   "Turn on location services to go online".
/// - [routeToApproval]: set to `true` when toggle-online fails because
///   the rider is not approved (typed 403 `RIDER_NOT_APPROVED`, or a
///   5xx while the rider is known to be unapproved). The home screen
///   navigates to the approval screen.
/// - [accountSuspended]: set to `true` when toggle-online fails with
///   the typed suspension gate (403 `RIDER_SUSPENDED`). This is NOT an
///   approval-flow problem — the home screen must surface a distinct
///   "account suspended" message instead of routing to approval.
@immutable
class OnlineToggleState {
  /// Constructs a snapshot explicitly.
  const OnlineToggleState({
    this.isOnline = false,
    this.isBusy = false,
    this.errorMessage,
    this.permissionEducationNeeded = false,
    this.serviceDisabled = false,
    this.routeToApproval = false,
    this.accountSuspended = false,
  });

  /// Whether the rider is currently online.
  final bool isOnline;

  /// Whether a backend call is in flight.
  final bool isBusy;

  /// Latest user-facing error copy.
  final String? errorMessage;

  /// Set when the rider must be routed to the permission education
  /// screen (denied permission).
  final bool permissionEducationNeeded;

  /// Set when location services are turned off at the OS level.
  final bool serviceDisabled;

  /// Set when the rider must be routed to the approval screen because
  /// the backend rejected toggle-online as unapproved.
  final bool routeToApproval;

  /// Set when the backend rejected toggle-online because the rider's
  /// account is suspended (admin action required to restore).
  final bool accountSuspended;

  /// Returns a copy with the supplied fields replaced. Pass the
  /// `clear*` flags to reset transient signals (errorMessage,
  /// permissionEducationNeeded, etc.).
  OnlineToggleState copyWith({
    bool? isOnline,
    bool? isBusy,
    String? errorMessage,
    bool? permissionEducationNeeded,
    bool? serviceDisabled,
    bool? routeToApproval,
    bool? accountSuspended,
    bool clearError = false,
    bool clearPermissionEducation = false,
    bool clearServiceDisabled = false,
    bool clearRouteToApproval = false,
    bool clearAccountSuspended = false,
  }) {
    return OnlineToggleState(
      isOnline: isOnline ?? this.isOnline,
      isBusy: isBusy ?? this.isBusy,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      permissionEducationNeeded: clearPermissionEducation
          ? false
          : (permissionEducationNeeded ?? this.permissionEducationNeeded),
      serviceDisabled: clearServiceDisabled
          ? false
          : (serviceDisabled ?? this.serviceDisabled),
      routeToApproval: clearRouteToApproval
          ? false
          : (routeToApproval ?? this.routeToApproval),
      accountSuspended: clearAccountSuspended
          ? false
          : (accountSuspended ?? this.accountSuspended),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is OnlineToggleState &&
        other.isOnline == isOnline &&
        other.isBusy == isBusy &&
        other.errorMessage == errorMessage &&
        other.permissionEducationNeeded == permissionEducationNeeded &&
        other.serviceDisabled == serviceDisabled &&
        other.routeToApproval == routeToApproval &&
        other.accountSuspended == accountSuspended;
  }

  @override
  int get hashCode => Object.hash(
    isOnline,
    isBusy,
    errorMessage,
    permissionEducationNeeded,
    serviceDisabled,
    routeToApproval,
    accountSuspended,
  );
}

/// Controls the rider's online/offline transition (R6).
///
/// The two flows owned by this controller are deliberately strict:
///
/// **goOnline**:
/// 1. Ensure location permission via [LocationPermissionService.ensureWhileInUse].
///    - If services are disabled or permission is not granted, set
///      [OnlineToggleState.permissionEducationNeeded] /
///      [OnlineToggleState.serviceDisabled] and return without
///      hitting the backend (R6.2 / R6.3).
/// 2. Acquire one current GPS fix via [LocationService.getCurrentPosition]
///    (high accuracy, 10 s timeout) (R6.4).
/// 3. Call `DeliveryApi.toggleOnline(true)` (R6.5).
/// 4. Immediately follow with `DeliveryApi.updateLocation(lat, lng)`
///    using the acquired fix (R6.6).
/// 5. If `toggleOnline` returns [ApiServerException] (HTTP 500) and
///    the rider is known to be `!isApproved`, set
///    [OnlineToggleState.routeToApproval] (R6.7). The same routing
///    signal is set when the live backend's typed
///    [RiderNotApprovedError] is thrown.
///
/// **goOffline**:
/// 1. Call `DeliveryApi.toggleOnline(false)` (R6.8).
/// 2. Reset state to `isOnline: false` regardless of backend result —
///    a failed toggle-off should not strand the rider in a
///    locally-online state.
/// 3. The `rider:offline` socket emit and the location stream
///    teardown live in Task 6.x — they're explicitly NOT this
///    controller's job today.
class OnlineToggleController extends ChangeNotifier {
  /// Constructs the controller. Pass [isApprovedProvider] so the
  /// controller can read the latest known approval flag at the moment
  /// of failure without holding a mutable reference to a profile
  /// notifier.
  OnlineToggleController({
    required DeliveryApi api,
    required LocationPermissionService permissionService,
    required LocationService locationService,
    required bool Function() isApprovedProvider,
  }) : _api = api,
       _permissionService = permissionService,
       _locationService = locationService,
       _isApprovedProvider = isApprovedProvider;

  final DeliveryApi _api;
  final LocationPermissionService _permissionService;
  final LocationService _locationService;
  final bool Function() _isApprovedProvider;

  OnlineToggleState _state = const OnlineToggleState();

  /// Latest snapshot. Listeners receive a [notifyListeners] call when
  /// this value changes.
  OnlineToggleState get state => _state;

  /// Mirrors the rider's known online state from an external source
  /// (e.g. the home dashboard's profile fetch).
  ///
  /// Should be called when the home screen first observes the
  /// profile's `isOnline` flag so the toggle visual matches reality
  /// before any user interaction.
  void syncFromProfile({required bool isOnline}) {
    if (_state.isOnline == isOnline) return;
    _emit(_state.copyWith(isOnline: isOnline));
  }

  /// Clears one-shot routing / permission flags after the UI has
  /// reacted to them. Safe to call multiple times.
  void clearTransientFlags() {
    if (!_state.permissionEducationNeeded &&
        !_state.serviceDisabled &&
        !_state.routeToApproval &&
        !_state.accountSuspended &&
        _state.errorMessage == null) {
      return;
    }
    _emit(
      _state.copyWith(
        clearError: true,
        clearPermissionEducation: true,
        clearServiceDisabled: true,
        clearRouteToApproval: true,
        clearAccountSuspended: true,
      ),
    );
  }

  /// Goes through the full online flow: permission -> GPS fix ->
  /// toggle-online -> update-location.
  Future<void> goOnline() async {
    _emit(
      _state.copyWith(
        isBusy: true,
        clearError: true,
        clearPermissionEducation: true,
        clearServiceDisabled: true,
        clearRouteToApproval: true,
        clearAccountSuspended: true,
      ),
    );

    // 1. Permission gate.
    final LocationPermissionResult permission = await _permissionService
        .ensureWhileInUse();
    if (!permission.canUseLocation) {
      AppLogger.info(
        LogTopic.location,
        'goOnline blocked: service=${permission.service.name}, '
        'permission=${permission.permission.name}',
      );
      _emit(
        _state.copyWith(
          isBusy: false,
          serviceDisabled: permission.service == LocationServiceState.disabled,
          permissionEducationNeeded:
              permission.service == LocationServiceState.enabled &&
              permission.permission != LocationPermissionState.granted,
        ),
      );
      return;
    }

    // 2. Acquire one fix.
    final Position? position = await _locationService.getCurrentPosition();
    if (position == null) {
      AppLogger.warn(
        LogTopic.location,
        'goOnline could not acquire a GPS fix within 10s',
      );
      _emit(
        _state.copyWith(
          isBusy: false,
          errorMessage:
              'Could not get your current location. Try again in a moment',
        ),
      );
      return;
    }

    // 3. Toggle online + 4. push the fix immediately.
    try {
      await _api.toggleOnline(true);
      try {
        await _api.updateLocation(position.latitude, position.longitude);
      } catch (e, stack) {
        // The location update is best-effort — losing it does not
        // undo the rider's online state. Log and keep going.
        AppLogger.warn(
          LogTopic.location,
          'goOnline: post-toggle updateLocation failed: $e',
          error: e,
          stackTrace: stack,
        );
      }
      _emit(_state.copyWith(isOnline: true, isBusy: false, clearError: true));
    } on RiderNotApprovedError catch (e) {
      AppLogger.warn(
        LogTopic.auth,
        'goOnline: rider not approved (typed): ${e.message}',
      );
      _emit(
        _state.copyWith(isBusy: false, isOnline: false, routeToApproval: true),
      );
    } on RiderSuspendedError catch (e) {
      // Suspension is an ops action, not an approval-flow problem —
      // surface it distinctly instead of routing to /approval (R6).
      AppLogger.warn(
        LogTopic.auth,
        'goOnline: rider suspended (typed): ${e.message}',
      );
      _emit(
        _state.copyWith(isBusy: false, isOnline: false, accountSuspended: true),
      );
    } on ApiServerException catch (e, stack) {
      // Compatibility path for a backend that still returns an
      // untyped 5xx for the not-approved gate: route to approval ONLY
      // when we can confirm the rider is unapproved. A transient 5xx
      // (DB down, deploy blip) against an approved rider must just
      // show an error, never send them to /approval.
      AppLogger.warn(
        LogTopic.auth,
        'goOnline: 5xx from toggle-online: ${e.message}',
        error: e,
        stackTrace: stack,
      );
      if (!_isApprovedProvider()) {
        _emit(
          _state.copyWith(
            isBusy: false,
            isOnline: false,
            routeToApproval: true,
          ),
        );
      } else {
        _emit(
          _state.copyWith(
            isBusy: false,
            isOnline: false,
            errorMessage: e.message,
          ),
        );
      }
    } on ApiException catch (e, stack) {
      AppLogger.warn(
        LogTopic.auth,
        'goOnline: api error: ${e.message}',
        error: e,
        stackTrace: stack,
      );
      _emit(
        _state.copyWith(
          isBusy: false,
          isOnline: false,
          errorMessage: e.message,
        ),
      );
    } catch (e, stack) {
      AppLogger.warn(
        LogTopic.auth,
        'goOnline: unexpected error: $e',
        error: e,
        stackTrace: stack,
      );
      _emit(
        _state.copyWith(
          isBusy: false,
          isOnline: false,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  /// Goes offline by calling `toggleOnline(false)` and resetting the
  /// online flag. Errors are surfaced via [OnlineToggleState.errorMessage]
  /// but the local online flag is always reset to `false` so the UI
  /// never shows the rider as "online" after a failed toggle-off.
  ///
  /// Note: when the rider has an active delivery, the home screen keeps
  /// GPS streaming alive around this call (going offline must not
  /// abandon the assigned order) — the teardown decision lives there,
  /// not here.
  Future<void> goOffline() async {
    _emit(
      _state.copyWith(
        isBusy: true,
        clearError: true,
        clearPermissionEducation: true,
        clearServiceDisabled: true,
        clearRouteToApproval: true,
        clearAccountSuspended: true,
      ),
    );

    try {
      await _api.toggleOnline(false);
      _emit(_state.copyWith(isOnline: false, isBusy: false, clearError: true));
    } on ApiException catch (e, stack) {
      AppLogger.warn(
        LogTopic.auth,
        'goOffline: api error: ${e.message}',
        error: e,
        stackTrace: stack,
      );
      // Force the local flag off regardless — see method-doc rationale.
      _emit(
        _state.copyWith(
          isOnline: false,
          isBusy: false,
          errorMessage: e.message,
        ),
      );
    } catch (e, stack) {
      AppLogger.warn(
        LogTopic.auth,
        'goOffline: unexpected error: $e',
        error: e,
        stackTrace: stack,
      );
      _emit(
        _state.copyWith(
          isOnline: false,
          isBusy: false,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  void _emit(OnlineToggleState next) {
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }
}
