import 'package:flutter/foundation.dart';

import '../domain/rider_user.dart';

/// Coarse phase of the rider's session at app start.
///
/// The router maps each phase to a destination:
/// - [unknown]          -> splash (still resolving)
/// - [unauthenticated]  -> /login
/// - [unverified]       -> /approval (rider profile not approved)
/// - [approved]         -> /home (or /active if an active delivery exists)
enum SessionPhase { unknown, unauthenticated, unverified, approved }

/// Session-level state consumed by the router and the splash screen.
@immutable
class SessionState {
  /// Constructs a snapshot explicitly.
  const SessionState({required this.phase, this.user, this.errorMessage});

  /// Initial state at cold start: the bootstrap has not yet decided.
  const SessionState.unknown() : this(phase: SessionPhase.unknown);

  /// Current session phase.
  final SessionPhase phase;

  /// Authenticated rider user when [phase] is [SessionPhase.unverified]
  /// or [SessionPhase.approved].
  final RiderUser? user;

  /// Optional error copy surfaced on the splash retry screen when
  /// session restoration failed for a reason that's not a clean logout
  /// (network down, profile fetch errored).
  final String? errorMessage;

  /// True if [phase] is one of the resolved states (anything except
  /// [SessionPhase.unknown]).
  bool get isResolved => phase != SessionPhase.unknown;

  /// True if the rider is fully signed in and approved.
  bool get isApproved => phase == SessionPhase.approved;

  /// True if the rider has signed in but the rider profile is not yet
  /// approved.
  bool get isUnverified => phase == SessionPhase.unverified;

  /// True if no valid session is present.
  bool get isUnauthenticated => phase == SessionPhase.unauthenticated;

  /// Returns a copy with selected fields replaced.
  SessionState copyWith({
    SessionPhase? phase,
    RiderUser? user,
    String? errorMessage,
    bool clearUser = false,
    bool clearError = false,
  }) {
    return SessionState(
      phase: phase ?? this.phase,
      user: clearUser ? null : (user ?? this.user),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SessionState &&
        other.phase == phase &&
        other.user == user &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode => Object.hash(phase, user, errorMessage);
}
