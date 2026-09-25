import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/realtime/socket_client.dart';
import '../../../core/realtime/socket_events.dart';
import '../../../core/utils/app_logger.dart';
import '../data/delivery_repository.dart';
import '../domain/assignment_status.dart';
import '../domain/collected_payment.dart';
import '../domain/delivery_order.dart';
import 'assignment_state_machine.dart';

/// Discriminated outcome of the delivery-lifecycle actions on
/// [ActiveDeliveryController]: [ActiveDeliveryController.markPickedUp],
/// [ActiveDeliveryController.deliverDirect],
/// [ActiveDeliveryController.deliverWithProof], and
/// [ActiveDeliveryController.deliverWithDemoMode].
///
/// The presentation layer pattern-matches on the result so each
/// outcome (success, stale order, proof upload failure, generic
/// failure) maps to its own UX path
/// (R13.5, R14.5, R14.6, R15.4, R16.4).
@immutable
sealed class DeliveryResult {
  /// Const constructor.
  const DeliveryResult();
}

/// Successful outcome. Carries enough information to render the
/// completion summary sheet without re-fetching.
@immutable
class DeliveryResultSuccess extends DeliveryResult {
  /// Const constructor.
  const DeliveryResultSuccess({
    required this.orderEarning,
    required this.customerName,
    required this.orderNumber,
  });

  /// Earning credited to the rider for this delivery.
  final double orderEarning;

  /// Customer's name (or the address if name is empty).
  final String customerName;

  /// Human-readable order number rendered on the summary.
  final String orderNumber;
}

/// The order is no longer in a state that accepts the requested
/// transition (backend returned `ORDER_NOT_AVAILABLE` / 409). The
/// caller should refetch `/delivery/orders` (R13.5).
@immutable
class DeliveryResultStale extends DeliveryResult {
  /// Const constructor.
  const DeliveryResultStale({
    this.message = 'Order is no longer in the right state. Refreshing',
  });

  /// User-facing copy.
  final String message;
}

/// Customer's OTP did not match. Keep the OTP sheet open and let the
/// rider retype (R14.5).
@immutable
class DeliveryResultInvalidOtp extends DeliveryResult {
  /// Const constructor.
  const DeliveryResultInvalidOtp({
    this.message = 'OTP did not match. Ask the customer to read it again',
  });

  /// User-facing copy.
  final String message;
}

/// OTP expired (Redis TTL elapsed). Switch to the proof flow (R14.6).
@immutable
class DeliveryResultOtpExpired extends DeliveryResult {
  /// Const constructor.
  const DeliveryResultOtpExpired({
    this.message = 'OTP expired. Use proof photo',
  });

  /// User-facing copy.
  final String message;
}

/// Proof photo upload failed (network / server error). Keep the proof
/// sheet open with a retry CTA (R15.4).
@immutable
class DeliveryResultProofFailed extends DeliveryResult {
  /// Const constructor.
  const DeliveryResultProofFailed({
    this.message = 'Could not upload photo. Try again',
  });

  /// User-facing copy.
  final String message;
}

/// Generic failure. Surface the supplied [message] verbatim (it's
/// either the backend `message` field or a translated transport error).
@immutable
class DeliveryResultFailure extends DeliveryResult {
  /// Const constructor.
  const DeliveryResultFailure(this.message);

  /// User-facing copy.
  final String message;
}

/// Holds the rider's **single active delivery** (blueprint §10: at most
/// one accepted/picked-up/in-transit order) and owns the mid-delivery
/// actions (pickup, direct deliver, proof deliver, demo deliver).
///
/// The backend enforces one-open-order per rider (Big Phase 7 — the
/// dispatch pool excludes busy riders and the accept endpoint rejects
/// `RIDER_ALREADY_HAS_ACTIVE_ORDER`), so a single field is a faithful
/// mirror, not a hopeful assumption. When the server does surface a
/// *different* open order (a replaced assignment after an admin
/// intervention), the incoming order wins: server state is
/// authoritative, and the replaced order's transient bookkeeping (busy
/// flag, recorded COD split) is dropped with it.
///
/// Transitions go through [AssignmentStateMachine] to enforce the
/// monotonicity property (R9.1, R9.2). When an order reaches a terminal
/// status via an external event it is removed immediately; when it
/// reaches terminal via one of this controller's own actions it stays
/// available until the completion summary acknowledges it with
/// [clearActiveDelivery] — the summary reads the final state before
/// clearing.
///
/// This is a plain [ChangeNotifier] (no Riverpod) so it can be
/// unit-tested in pure Dart without a Flutter widget tree. A typed
/// [DeliveryRepository] and [SocketClient] are accepted optionally so
/// constructors can stay light in tests that only exercise the local
/// state operations; production code wires both via Riverpod.
class ActiveDeliveryController extends ChangeNotifier {
  /// Wires the controller to its [repository] and [socket] dependencies.
  ///
  /// Both are nullable for test ergonomics — tests that only drive
  /// [setActiveDelivery] / [applyExternalStatus] can pass `null` for
  /// either. Network methods ([markPickedUp], [deliverDirect],
  /// [deliverWithProof], [deliverWithDemoMode]) require a non-null
  /// repository; calling them without one returns a
  /// [DeliveryResultFailure].
  ActiveDeliveryController({
    DeliveryRepository? repository,
    SocketClient? socket,
  }) : _repository = repository,
       _socket = socket;

  final DeliveryRepository? _repository;
  final SocketClient? _socket;

  DeliveryOrder? _activeOrder;
  bool _busy = false;

  /// COD cash/UPI split the rider recorded via the "Collect payment" step
  /// for the active order. Populated by [recordCollectedPayment]; the
  /// "Deliver" action reads from here rather than taking the split as a
  /// parameter, so it survives the (stateless) delivery sheet being
  /// rebuilt between the rider tapping "Collect payment" and later
  /// tapping "Deliver".
  CollectedPayment? _collectedPayment;

  /// The payment split recorded for the active order, or `null` if the
  /// rider hasn't gone through the collection step yet (or the order
  /// isn't COD).
  CollectedPayment? collectedPaymentFor(String orderId) =>
      _activeOrder != null && _activeOrder!.orderId == orderId
      ? _collectedPayment
      : null;

  /// Records [payment] as the confirmed cash/UPI split for the active
  /// order and notifies listeners so the "Deliver" button un-disables.
  void recordCollectedPayment(String orderId, CollectedPayment payment) {
    if (_activeOrder == null || _activeOrder!.orderId != orderId) return;
    _collectedPayment = payment;
    notifyListeners();
  }

  /// The rider's single active delivery (`ACCEPTED` or `IN_TRANSIT`),
  /// or `null` when there is none. Kept as the same getter name the
  /// pre-batch consumers already used.
  DeliveryOrder? get current => _activeOrder;

  /// Alias of [current] under the target-product name (blueprint
  /// architecture §7: `DeliveryOrder? activeOrder`).
  DeliveryOrder? get activeOrder => _activeOrder;

  /// Looks up the active delivery by id — `null` when [orderId] isn't
  /// the active order's id (there is exactly one candidate).
  DeliveryOrder? byId(String orderId) =>
      _activeOrder?.orderId == orderId ? _activeOrder : null;

  /// Whether a network action is in flight. Sheets read this flag to
  /// disable their primary buttons.
  bool get isBusy => _busy;

  /// Whether a network action is in flight for [orderId] specifically.
  /// With a single active order this is only `true` when [orderId] is
  /// the active order's id.
  bool isBusyFor(String orderId) => _busy && _activeOrder?.orderId == orderId;

  /// Sets (or replaces) the rider's single active delivery.
  ///
  /// Re-asserting the same order is idempotent. When a *different*
  /// order arrives while one is active, the incoming order replaces it
  /// — the backend only ever surfaces one open order, so a replacement
  /// means the previous one went terminal server-side (admin
  /// intervention) and this device missed the event; its transient
  /// bookkeeping is dropped with it.
  void setActiveDelivery(DeliveryOrder order) {
    final DeliveryOrder? previous = _activeOrder;
    if (previous != null && previous.orderId != order.orderId) {
      AppLogger.warn(
        LogTopic.state,
        'Active delivery replaced: ${previous.orderId} -> ${order.orderId} '
        '(server surfaced a different open order)',
      );
    }
    _activeOrder = order;
    _busy = false;
    if (previous == null || previous.orderId != order.orderId) {
      _collectedPayment = null;
    }
    notifyListeners();
  }

  /// Clears the active delivery entirely (completion acknowledged,
  /// order gone). In the single-order world there is nothing to
  /// advance to — the rider simply becomes available for the next
  /// offer.
  void clearActiveDelivery() {
    if (_activeOrder == null && !_busy) {
      _collectedPayment = null;
      return;
    }
    _activeOrder = null;
    _busy = false;
    _collectedPayment = null;
    notifyListeners();
  }

  /// Removes the active delivery when [orderId] matches it (used when
  /// an order is cancelled/removed rather than delivered). No-ops for
  /// any other id.
  void remove(String orderId) {
    if (_activeOrder?.orderId != orderId) return;
    _activeOrder = null;
    _busy = false;
    _collectedPayment = null;
    notifyListeners();
  }

  /// Applies an externally received [next] status to the active order.
  ///
  /// If the active order's id doesn't match [orderId] the call is a
  /// no-op (the event is for an order this controller isn't tracking).
  ///
  /// Non-terminal transitions are validated by [AssignmentStateMachine.apply];
  /// illegal ones are rejected and logged without mutating state — that
  /// guard exists for the rider's own step-by-step actions (R9). A
  /// *terminal* [next] (DELIVERED/CANCELLED) is always applied instead,
  /// bypassing the walk check: an admin can mark an order delivered or
  /// cancel it from the dashboard without the rider's local state ever
  /// having stepped through the intermediate stages, and the server's
  /// word on a terminal outcome is authoritative. Terminal outcomes
  /// remove the order immediately (no completion summary can be pending
  /// for an externally-forced terminal state).
  void applyExternalStatus(String orderId, AssignmentStatus next) {
    final DeliveryOrder? order = _activeOrder;
    if (order == null || order.orderId != orderId) return;

    final AssignmentStatus resolved = AssignmentStateMachine.isTerminal(next)
        ? next
        : AssignmentStateMachine.apply(
            order.assignmentStatus,
            next,
            orderId: orderId,
          );

    if (resolved == order.assignmentStatus) {
      // Either idempotent (same status) or illegal (rejected). Either way
      // the state did not change, so no notification is needed.
      return;
    }

    _activeOrder = order.copyWith(assignmentStatus: resolved);
    notifyListeners();

    if (AssignmentStateMachine.isTerminal(resolved)) {
      remove(orderId);
    }
  }

  // ---------------------------------------------------------------------------
  // Pickup (R13)
  // ---------------------------------------------------------------------------

  /// Marks the active order as picked up at the store.
  ///
  /// On success: drives the assignment through
  /// `ACCEPTED -> IN_TRANSIT` via [AssignmentStateMachine.apply] so the
  /// monotonic-walk invariant (R9) holds. Does NOT emit `order:track`
  /// — that emit happens on accept (R10.3). Callers should switch the
  /// `LocationProfile` to in-transit after this returns success
  /// (R13.4); this controller does not own the location profile.
  ///
  /// On `ORDER_NOT_AVAILABLE`: surfaces [DeliveryResultStale] so the
  /// caller can refetch `/delivery/orders` (R13.5).
  Future<DeliveryResult> markPickedUp(String orderId) async {
    return _runAction('markPickedUp', orderId, () async {
      final DeliveryRepository repository = _requireRepository();
      await repository.markPickedUp(orderId);
      _applyLocalTransition(orderId, AssignmentStatus.inTransit);
      final DeliveryOrder? o = _activeOrder;
      if (o == null || o.orderId != orderId) {
        return _genericSuccess(orderId);
      }
      return DeliveryResultSuccess(
        orderEarning: o.riderEarning,
        customerName: o.customerAddress.name.isNotEmpty
            ? o.customerAddress.name
            : o.customerAddress.address,
        orderNumber: o.orderNumber,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Cancel delivery (customer refused / unreachable)
  // ---------------------------------------------------------------------------

  /// Cancels the active order when the customer refuses the order at
  /// the door or can't be reached at the drop location.
  ///
  /// Applies the terminal transition `ACCEPTED/IN_TRANSIT ->
  /// CANCELLED`, emits `order:untrack`, and removes it so the rider can
  /// immediately go back online. Returns `true` on success.
  Future<bool> cancelDelivery(String orderId, String reason) async {
    final DeliveryRepository? repository = _repository;
    if (repository == null || _busy || _activeOrder?.orderId != orderId) {
      return false;
    }
    _busy = true;
    notifyListeners();
    try {
      await repository.cancelDelivery(orderId, reason);
      _socket?.emit(SocketEvents.orderUntrack, <String, dynamic>{
        'orderId': orderId,
      });
      _onTerminalExternal(orderId);
      return true;
    } catch (e, stack) {
      AppLogger.warn(
        LogTopic.state,
        'cancelDelivery($orderId) failed',
        error: e,
        stackTrace: stack,
      );
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Deliver directly (no OTP / proof step)
  // ---------------------------------------------------------------------------

  /// Marks the active order as delivered immediately — no OTP or
  /// proof-photo verification. COD collection (if any) has already
  /// happened via [recordCollectedPayment] before this is called.
  Future<DeliveryResult> deliverDirect(
    String orderId, {
    double? cashCollected,
    double? upiCollected,
  }) async {
    return _runAction('deliverDirect', orderId, () async {
      final DeliveryRepository repository = _requireRepository();
      await repository.markDelivered(
        orderId,
        cashCollected: cashCollected,
        upiCollected: upiCollected,
      );
      return _completeDelivery(orderId);
    });
  }

  // ---------------------------------------------------------------------------
  // Deliver via proof photo (R15)
  // ---------------------------------------------------------------------------

  /// Uploads [file] as proof and marks the active order as delivered.
  ///
  /// Two-step flow per R15.3:
  /// 1. `POST /delivery/orders/:id/proof` returns the public URL.
  /// 2. `PATCH /delivery/orders/:id/deliver` with `proofPhotoUrl: url`.
  ///
  /// Surfaces [DeliveryResultProofFailed] when step 1 fails so the
  /// proof sheet can keep the preview and offer a retry (R15.4).
  /// Step-2 errors are surfaced via the standard mapping (stale /
  /// generic).
  Future<DeliveryResult> deliverWithProof(
    String orderId,
    File file, {
    double? cashCollected,
    double? upiCollected,
  }) async {
    final DeliveryRepository? repository = _repository;
    if (repository == null) {
      return const DeliveryResultFailure('Network unavailable');
    }
    if (_busy) {
      return const DeliveryResultFailure('Action already in progress');
    }
    _busy = true;
    notifyListeners();

    try {
      final String url;
      try {
        url = await repository.uploadProof(orderId, file);
      } catch (e, stack) {
        AppLogger.warn(
          LogTopic.state,
          'deliverWithProof.upload($orderId) failed',
          error: e,
          stackTrace: stack,
        );
        return const DeliveryResultProofFailed();
      }

      if (url.isEmpty) {
        return const DeliveryResultProofFailed();
      }

      try {
        await repository.markDelivered(
          orderId,
          proofPhotoUrl: url,
          cashCollected: cashCollected,
          upiCollected: upiCollected,
        );
        return _completeDelivery(orderId);
      } on OrderNotAvailableException catch (e) {
        AppLogger.info(
          LogTopic.state,
          'deliverWithProof($orderId): order not available — ${e.message}',
        );
        return DeliveryResultStale(message: e.message);
      } on ApiException catch (e) {
        return _mapDeliverError(e) ?? DeliveryResultFailure(e.message);
      }
    } catch (e, stack) {
      AppLogger.warn(
        LogTopic.state,
        'deliverWithProof($orderId) unexpected error',
        error: e,
        stackTrace: stack,
      );
      return DeliveryResultFailure(_describeError(e));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Deliver in demo mode (R16)
  // ---------------------------------------------------------------------------

  /// Marks the active order as delivered with `demoMode: true`. The
  /// caller MUST gate this method by `Env.current.enableDevAffordances`
  /// so production builds never invoke it (R16.3).
  ///
  /// Surfaces the backend's error message verbatim when the route
  /// returns `demo mode disabled` (R16.4).
  Future<DeliveryResult> deliverWithDemoMode(String orderId) async {
    return _runAction('deliverWithDemoMode', orderId, () async {
      final DeliveryRepository repository = _requireRepository();
      await repository.markDelivered(orderId, demoMode: true);
      return _completeDelivery(orderId);
    }, mapBackendCode: _mapDeliverError);
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Runs [action] guarded by the busy flag, with consistent listener
  /// notification and stale-order / generic error mapping.
  ///
  /// [mapBackendCode] is consulted before the generic
  /// [DeliveryResultFailure] fallback so action-specific codes
  /// (`INVALID_OTP`, `OTP_EXPIRED`, `DEMO_MODE_DISABLED`) can be
  /// translated by the caller.
  Future<DeliveryResult> _runAction(
    String name,
    String orderId,
    Future<DeliveryResult> Function() action, {
    DeliveryResult? Function(ApiException error)? mapBackendCode,
  }) async {
    if (_repository == null) {
      return const DeliveryResultFailure('Network unavailable');
    }
    if (_busy) {
      return const DeliveryResultFailure('Action already in progress');
    }
    _busy = true;
    notifyListeners();

    try {
      return await action();
    } on OrderNotAvailableException catch (e) {
      AppLogger.info(
        LogTopic.state,
        '$name($orderId): order not available — ${e.message}',
      );
      return DeliveryResultStale(message: e.message);
    } on ApiException catch (e, stack) {
      AppLogger.warn(
        LogTopic.state,
        '$name($orderId) failed: ${e.backendCode ?? 'no-code'} ${e.message}',
        error: e,
        stackTrace: stack,
      );
      final DeliveryResult? mapped = mapBackendCode?.call(e);
      if (mapped != null) return mapped;
      return DeliveryResultFailure(e.message);
    } catch (e, stack) {
      AppLogger.warn(
        LogTopic.state,
        '$name($orderId) unexpected error',
        error: e,
        stackTrace: stack,
      );
      return DeliveryResultFailure(_describeError(e));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Maps the deliver-specific backend codes to typed results. Returns
  /// `null` so [_runAction] falls back to a generic
  /// [DeliveryResultFailure].
  static DeliveryResult? _mapDeliverError(ApiException error) {
    final String? code = error.backendCode?.toUpperCase();
    if (code == 'INVALID_OTP') {
      return DeliveryResultInvalidOtp(message: error.message);
    }
    if (code == 'OTP_EXPIRED') {
      return DeliveryResultOtpExpired(message: error.message);
    }
    return null;
  }

  /// Applies `IN_TRANSIT -> DELIVERED` to the active order, emits
  /// `order:untrack`, and returns a [DeliveryResultSuccess] populated
  /// from the just-completed order. Does NOT clear the active order —
  /// the completion sheet reads it before calling [clearActiveDelivery].
  DeliveryResultSuccess _completeDelivery(String orderId) {
    final DeliveryOrder? before = _activeOrder;
    _applyLocalTransition(orderId, AssignmentStatus.delivered);
    _socket?.emit(SocketEvents.orderUntrack, <String, dynamic>{
      'orderId': orderId,
    });
    final DeliveryOrder? after = _activeOrder?.orderId == orderId
        ? _activeOrder
        : before;
    if (after == null) {
      return _genericSuccess(orderId);
    }
    return DeliveryResultSuccess(
      orderEarning: after.riderEarning,
      customerName: after.customerAddress.name.isNotEmpty
          ? after.customerAddress.name
          : after.customerAddress.address,
      orderNumber: after.orderNumber,
    );
  }

  /// Locally drives the active order through [next] using the state
  /// machine. Same monotonic-walk guard as [applyExternalStatus] but
  /// without triggering the auto-remove on terminal — the action paths
  /// keep the order around for the completion summary.
  void _applyLocalTransition(String orderId, AssignmentStatus next) {
    final DeliveryOrder? order = _activeOrder;
    if (order == null || order.orderId != orderId) return;

    final AssignmentStatus resolved = AssignmentStateMachine.apply(
      order.assignmentStatus,
      next,
      orderId: orderId,
    );
    if (resolved == order.assignmentStatus) return;
    _activeOrder = order.copyWith(assignmentStatus: resolved);
    notifyListeners();
  }

  DeliveryRepository _requireRepository() {
    final DeliveryRepository? repo = _repository;
    if (repo == null) {
      // Reached only by tests that wire the controller without a
      // repository and then drive a network action; surfaced via the
      // outer `_runAction` guard.
      throw StateError('Network unavailable');
    }
    return repo;
  }

  /// Builds a fallback [DeliveryResultSuccess] when the order has been
  /// replaced between the API call and this method (e.g. a concurrent
  /// cancellation). The home dashboard refresh will fill in real values
  /// on the next refresh.
  DeliveryResultSuccess _genericSuccess(String orderId) {
    return DeliveryResultSuccess(
      orderEarning: 0,
      customerName: '',
      orderNumber: orderId,
    );
  }

  /// Called when the active order reaches a terminal status via an
  /// external (socket) event or an in-controller cancel. Removes it
  /// immediately.
  void _onTerminalExternal(String orderId) {
    if (_activeOrder?.orderId != orderId) return;
    _activeOrder = null;
    _busy = false;
    _collectedPayment = null;
    notifyListeners();
  }

  static String _describeError(Object error) {
    final String s = error.toString();
    if (s.length > 200) return '${s.substring(0, 200)}...';
    return s;
  }
}
