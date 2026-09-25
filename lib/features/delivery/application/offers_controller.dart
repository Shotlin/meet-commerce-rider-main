import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/realtime/socket_client.dart';
import '../../../core/realtime/socket_events.dart';
import '../../../core/utils/app_logger.dart';
import '../data/delivery_api.dart' show RejectReason;
import '../data/delivery_repository.dart';
import '../domain/assignment_status.dart';
import '../domain/delivery_order.dart';
import 'assignment_state_machine.dart';

/// Discriminated outcome of [OffersController.acceptOffer] /
/// [OffersController.rejectOffer].
@immutable
sealed class OfferActionResult {
  /// Const constructor.
  const OfferActionResult();
}

/// The action succeeded.
@immutable
class OfferActionSuccess extends OfferActionResult {
  /// Constructs a success.
  const OfferActionSuccess();
}

/// Accept failed because the order was already taken (HTTP 409 /
/// `ORDER_NOT_AVAILABLE`).
@immutable
class OfferAlreadyTaken extends OfferActionResult {
  /// Constructs the result with a user-facing [message].
  const OfferAlreadyTaken({
    this.message = 'Order was already taken by another rider',
  });

  /// Copy surfaced to the user.
  final String message;
}

/// Generic failure (network, server, validation). Carries a
/// user-facing [message] for the toast / inline error.
@immutable
class OfferActionFailure extends OfferActionResult {
  /// Constructs the failure with [message].
  const OfferActionFailure(this.message);

  /// Copy surfaced to the user.
  final String message;
}

/// Manages the list of active [DeliveryOrder] offers (status
/// `ASSIGNED`) and their accept/reject lifecycle.
///
/// Pure-Dart [ChangeNotifier]: no Riverpod, no widgets, so unit tests
/// can drive it without a test pumper.
///
/// State transitions go through [AssignmentStateMachine.apply] to
/// enforce R9.2 (illegal transitions are rejected and logged); offers
/// that reach a terminal state are removed from the list.
class OffersController extends ChangeNotifier {
  /// Wires the controller to its collaborators.
  ///
  /// [repository] and [socket] are required for the network-side
  /// methods ([acceptOffer], [rejectOffer]). Pure consumers (tests
  /// driving only [upsertOffer] / [applyStatus]) can pass any
  /// fakes — neither method is used by the local-only paths.
  OffersController({
    required DeliveryRepository repository,
    required SocketClient socket,
  }) : _repository = repository,
       _socket = socket;

  /// Convenience constructor for tests that drive only the local
  /// list operations and do not touch the network. Pass real
  /// dependencies in production.
  @visibleForTesting
  OffersController.local({DeliveryRepository? repository, SocketClient? socket})
    : _repository = repository,
      _socket = socket;

  final DeliveryRepository? _repository;
  final SocketClient? _socket;

  final List<DeliveryOrder> _offers = <DeliveryOrder>[];
  final Set<String> _busyOrderIds = <String>{};

  /// An unmodifiable view of the current offers list.
  List<DeliveryOrder> get offers => List<DeliveryOrder>.unmodifiable(_offers);

  /// Whether [orderId] currently has an accept/reject network call in
  /// flight. Used by the offer sheet to disable the buttons while
  /// the network call is pending.
  bool isBusy(String orderId) => _busyOrderIds.contains(orderId);

  /// Returns `true` when any offer has status `accepted` or
  /// `inTransit`. Used to suppress the offer bottom sheet while the
  /// rider is in an active delivery (R9.4).
  bool get hasActiveDelivery {
    for (final DeliveryOrder o in _offers) {
      if (o.assignmentStatus == AssignmentStatus.accepted ||
          o.assignmentStatus == AssignmentStatus.inTransit) {
        return true;
      }
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Local list mutations (driven by the socket controller and tests)
  // ---------------------------------------------------------------------------

  /// Adds [offer] to the list, or replaces an existing entry with the
  /// same `orderId`.
  void upsertOffer(DeliveryOrder offer) {
    final int index = _indexOf(offer.orderId);
    if (index == -1) {
      _offers.add(offer);
    } else {
      _offers[index] = offer;
    }
    notifyListeners();
  }

  /// Removes the offer with [orderId] from the list. No-op when no
  /// matching offer exists. Notifies listeners only when the list
  /// actually changes.
  void removeOffer(String orderId) {
    final int index = _indexOf(orderId);
    if (index == -1) return;
    _offers.removeAt(index);
    notifyListeners();
  }

  /// Marks the offer with [orderId] as expired. Removes it from the
  /// list (R8.4) and clears any pending busy flag. No-op when no
  /// matching offer exists.
  void markExpired(String orderId) {
    _busyOrderIds.remove(orderId);
    removeOffer(orderId);
  }

  /// Applies [status] to the offer identified by [orderId].
  ///
  /// The transition is validated by [AssignmentStateMachine.apply];
  /// illegal transitions are rejected and logged without mutating
  /// state. When the resulting status is terminal, the offer is
  /// removed from the list.
  void applyStatus(String orderId, AssignmentStatus status) {
    final int index = _indexOf(orderId);
    if (index == -1) return;

    final DeliveryOrder offer = _offers[index];
    // A terminal status is always applied even if it skips stages this
    // offer's local state never observed (e.g. an admin cancelling an
    // order before the rider ever accepted it) — see the matching note
    // on ActiveDeliveryController.applyExternalStatus.
    final AssignmentStatus resolved = AssignmentStateMachine.isTerminal(status)
        ? status
        : AssignmentStateMachine.apply(
            offer.assignmentStatus,
            status,
            orderId: orderId,
          );

    if (AssignmentStateMachine.isTerminal(resolved)) {
      _offers.removeAt(index);
      _busyOrderIds.remove(orderId);
      notifyListeners();
      return;
    }

    if (resolved != offer.assignmentStatus) {
      _offers[index] = offer.copyWith(assignmentStatus: resolved);
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Network actions
  // ---------------------------------------------------------------------------

  /// Accepts the offer identified by [orderId].
  ///
  /// On success: transitions the offer to `ACCEPTED` via the state
  /// machine, emits `order:track` so the backend starts tracking the
  /// rider, and returns [OfferActionSuccess].
  ///
  /// Surfaces [OfferAlreadyTaken] when the backend reports
  /// `ORDER_NOT_AVAILABLE` (or HTTP 409). Surfaces [OfferActionFailure]
  /// for any other error.
  Future<OfferActionResult> acceptOffer(String orderId) async {
    final DeliveryRepository? repository = _repository;
    if (repository == null) {
      return const OfferActionFailure('Network unavailable');
    }
    if (_busyOrderIds.contains(orderId)) {
      return const OfferActionFailure('Action already in progress');
    }
    _busyOrderIds.add(orderId);
    notifyListeners();

    try {
      await repository.acceptOrder(orderId);
      // Move the offer through the state machine.
      applyStatus(orderId, AssignmentStatus.accepted);
      _socket?.emit(SocketEvents.orderTrack, <String, dynamic>{
        'orderId': orderId,
      });
      return const OfferActionSuccess();
    } on OrderNotAvailableException catch (e) {
      AppLogger.info(
        LogTopic.state,
        'acceptOffer($orderId): order not available — ${e.message}',
      );
      // Remove the stale offer so it doesn't sit in the UI.
      removeOffer(orderId);
      return OfferAlreadyTaken(message: e.message);
    } on ApiConflictException catch (e) {
      AppLogger.info(
        LogTopic.state,
        'acceptOffer($orderId): 409 — ${e.message}',
      );
      removeOffer(orderId);
      return OfferAlreadyTaken(message: e.message);
    } catch (e, stack) {
      AppLogger.warn(
        LogTopic.state,
        'acceptOffer($orderId) failed',
        error: e,
        stackTrace: stack,
      );
      return OfferActionFailure(_describeError(e));
    } finally {
      _busyOrderIds.remove(orderId);
      notifyListeners();
    }
  }

  /// Rejects the offer identified by [orderId] with [reason].
  ///
  /// On success: removes the offer locally and returns
  /// [OfferActionSuccess]. The rider remains online (R11.5).
  Future<OfferActionResult> rejectOffer(
    String orderId,
    RejectReason reason,
  ) async {
    final DeliveryRepository? repository = _repository;
    if (repository == null) {
      return const OfferActionFailure('Network unavailable');
    }
    if (_busyOrderIds.contains(orderId)) {
      return const OfferActionFailure('Action already in progress');
    }
    _busyOrderIds.add(orderId);
    notifyListeners();

    try {
      await repository.rejectOrder(orderId, reason.wire);
      removeOffer(orderId);
      return const OfferActionSuccess();
    } on OrderNotAvailableException catch (e) {
      // Even though the rider rejected it, the order may already be
      // gone. Treat as success-of-a-sort: the offer is no longer
      // actionable and should disappear from the UI.
      removeOffer(orderId);
      return OfferAlreadyTaken(message: e.message);
    } catch (e, stack) {
      AppLogger.warn(
        LogTopic.state,
        'rejectOffer($orderId) failed',
        error: e,
        stackTrace: stack,
      );
      return OfferActionFailure(_describeError(e));
    } finally {
      _busyOrderIds.remove(orderId);
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  int _indexOf(String orderId) =>
      _offers.indexWhere((DeliveryOrder o) => o.orderId == orderId);

  String _describeError(Object error) {
    final String s = error.toString();
    if (s.length > 200) return '${s.substring(0, 200)}...';
    return s;
  }
}
