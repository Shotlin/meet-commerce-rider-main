import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/auth/application/session_controller.dart';
import '../features/auth/application/session_state.dart';
import '../features/auth/data/auth_api.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/delivery/application/active_delivery_controller.dart';
import '../features/delivery/application/active_delivery_map_controller.dart';
import '../features/delivery/application/delivery_socket_controller.dart';
import '../features/delivery/application/offers_controller.dart';
import '../features/delivery/application/pickup_session_controller.dart';
import '../features/delivery/data/delivery_api.dart';
import '../features/delivery/data/delivery_repository.dart';
import '../features/delivery/domain/rider_profile.dart';
import '../features/delivery/domain/store_info.dart';
import '../features/delivery/presentation/camera_director.dart';
import '../features/earnings/application/earnings_controller.dart';
import '../features/history/application/history_controller.dart';
import '../features/home/application/home_dashboard_controller.dart';
import '../features/home/application/online_toggle_controller.dart';
import '../features/onboarding/application/documents_controller.dart';
import '../features/onboarding/data/documents_api.dart';
import '../features/onboarding/data/documents_repository.dart';
import 'config/app_constants.dart';
import 'config/env.dart';
import 'connectivity/connectivity_watcher.dart';
import 'location/location_lifecycle_manager.dart';
import 'location/location_permission_service.dart';
import 'location/location_service.dart';
import 'location/rider_location_provider.dart';
import 'location/rider_location_publisher.dart';
import 'maps/cached_tile_provider.dart';
import 'maps/marker_assets.dart';
import 'network/api_client.dart';
import 'network/auth_interceptor.dart';
import 'permissions/camera_permission_service.dart';
import 'realtime/socket_client.dart';
import 'storage/secure_token_store.dart';
import 'utils/app_logger.dart';
import 'utils/external_nav_launcher.dart';
import 'utils/image_compressor.dart';

/// Active environment (live SHOTLIN backend, flavor-aware affordances).
final Provider<Env> envProvider = Provider<Env>((Ref ref) => Env.current);

/// Persistent secure store backing the rider's access + refresh JWTs.
///
/// Disposed when the provider is invalidated, but the underlying storage
/// is global so logout-and-back-in keeps working.
final Provider<SecureTokenStore> tokenStoreProvider =
    Provider<SecureTokenStore>((Ref ref) {
      return FlutterSecureTokenStore();
    });

/// Connectivity watcher exposing a debounced `isOffline` boolean.
final Provider<ConnectivityWatcher> connectivityWatcherProvider =
    Provider<ConnectivityWatcher>((Ref ref) {
      return ConnectivityWatcher(Connectivity());
    });

/// Internal Dio used exclusively for the refresh-and-retry path so a
/// 401 on a retried request never recurses through the auth interceptor.
final Provider<Dio> _retryDioProvider = Provider<Dio>((Ref ref) {
  final Env env = ref.watch(envProvider);
  return Dio(
    BaseOptions(
      baseUrl: env.apiBaseUrl,
      connectTimeout: AppConstants.connectTimeout,
      receiveTimeout: AppConstants.receiveTimeout,
      sendTimeout: AppConstants.sendTimeout,
      contentType: 'application/json',
      validateStatus: (int? status) =>
          status != null && status >= 200 && status < 600,
    ),
  );
});

/// Singleton Dio used for every authenticated REST call.
///
/// We construct it eagerly via [ApiClient.unauthenticated] then bolt on
/// the [AuthInterceptor] once the token store, repository, and retry
/// Dio are all resolved. Splitting it this way avoids a chicken-and-egg
/// problem (the repository needs the client; the client's interceptor
/// needs the repository).
final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((Ref ref) {
  final Env env = ref.watch(envProvider);
  final ApiClient client = ApiClient.unauthenticated(env);
  final Dio retryDio = ref.watch(_retryDioProvider);
  final SecureTokenStore tokenStore = ref.watch(tokenStoreProvider);

  client.dio.interceptors.add(
    AuthInterceptor(
      tokenStore: tokenStore,
      retryDio: retryDio,
      refresh: () async {
        // Resolved late so the provider graph can finish wiring before
        // the first 401 ever fires.
        final AuthRepository repo = ref.read<AuthRepository>(
          authRepositoryProvider,
        );
        final bool refreshed = await repo.refreshTokens();
        if (refreshed) {
          // Rotate the socket auth (R7.2) without dropping subscriptions.
          final String? newToken = tokenStore.cachedAccessToken;
          if (newToken != null && newToken.isNotEmpty) {
            ref
                .read<SocketClient>(socketClientProvider)
                .reconnectWithToken(newToken);
          }
        }
        return refreshed;
      },
    ),
  );
  return client;
});

/// Auth-only Dio surface used by [AuthApi].
final Provider<AuthApi> authApiProvider = Provider<AuthApi>((Ref ref) {
  return AuthApi(ref.watch(apiClientProvider));
});

/// High-level repository wrapping [AuthApi] and [SecureTokenStore].
final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>((Ref ref) {
      return AuthRepository(
        api: ref.watch(authApiProvider),
        tokenStore: ref.watch(tokenStoreProvider),
      );
    });

/// Login-flow controller for the PhoneLogin / OTP screens.
final ChangeNotifierProvider<AuthController> authControllerProvider =
    ChangeNotifierProvider<AuthController>((Ref ref) {
      return AuthController(repository: ref.watch(authRepositoryProvider));
    });

/// Image compressor used for rider document and proof-photo uploads
/// (R4.4, R15.2).
///
/// Production builds use the default constructor; tests override the
/// provider with a compressor pointed at a deterministic temp dir so
/// they don't depend on the platform's image pipeline.
final Provider<ImageCompressor> imageCompressorProvider =
    Provider<ImageCompressor>((Ref ref) => ImageCompressor());

/// Documents API for rider verification document upload and retrieval.
///
/// Compression runs inside the API client (it has to: the upload is a
/// single multipart call) so the repository above stays a thin
/// pass-through. Tests override [imageCompressorProvider] to keep
/// unit tests deterministic.
final Provider<DocumentsApi> documentsApiProvider = Provider<DocumentsApi>((
  Ref ref,
) {
  return DocumentsApi(
    client: ref.watch(apiClientProvider),
    compressor: ref.watch(imageCompressorProvider),
  );
});

/// High-level repository wrapping [DocumentsApi].
final Provider<DocumentsRepository> documentsRepositoryProvider =
    Provider<DocumentsRepository>((Ref ref) {
      return DocumentsRepository(ref.watch(documentsApiProvider));
    });

/// Application-layer controller for the rider document onboarding
/// flow. ChangeNotifier-based to match the rest of the app's
/// Riverpod 3 + legacy `ChangeNotifierProvider` integration.
final ChangeNotifierProvider<DocumentsController> documentsControllerProvider =
    ChangeNotifierProvider<DocumentsController>((Ref ref) {
      return DocumentsController(
        repository: ref.watch(documentsRepositoryProvider),
      );
    });

/// App-startup session controller used by the router redirect.
final ChangeNotifierProvider<SessionController> sessionControllerProvider =
    ChangeNotifierProvider<SessionController>((Ref ref) {
      final SessionController controller = SessionController(
        apiClient: ref.watch(apiClientProvider),
        authRepository: ref.watch(authRepositoryProvider),
        tokenStore: ref.watch(tokenStoreProvider),
      );
      controller.linkAuthController(
        ref.read<AuthController>(authControllerProvider),
      );
      return controller;
    });

/// Socket.IO client for realtime communication with the backend.
///
/// The [SocketClient] is created up-front but does NOT auto-connect.
/// Connection is driven by [SocketLifecycleManager] which watches the
/// session state.
///
/// Token rotation is handled by the auth interceptor calling
/// [SocketClient.reconnectWithToken] after a successful refresh
/// (R7.2).
final Provider<SocketClient> socketClientProvider = Provider<SocketClient>((
  Ref ref,
) {
  final Env env = ref.watch(envProvider);
  final SocketClient client = SocketClient.io(socketBaseUrl: env.socketBaseUrl);
  ref.onDispose(client.dispose);
  return client;
});

// ---------------------------------------------------------------------------
// Delivery feature providers
// ---------------------------------------------------------------------------

/// Delivery API surface used by [DeliveryRepository].
final Provider<DeliveryApi> deliveryApiProvider = Provider<DeliveryApi>((
  Ref ref,
) {
  return DeliveryApi(ref.watch(apiClientProvider));
});

/// High-level repository wrapping [DeliveryApi].
final Provider<DeliveryRepository> deliveryRepositoryProvider =
    Provider<DeliveryRepository>((Ref ref) {
      return DeliveryRepository(ref.watch(deliveryApiProvider));
    });

/// Async notifier that fetches and caches the rider's profile.
///
/// Fetches on first read. Callers can call `ref.invalidate(riderProfileProvider)`
/// to force a refresh (e.g. after toggling online or uploading a document).
final AsyncNotifierProvider<_RiderProfileNotifier, RiderProfile>
riderProfileProvider =
    AsyncNotifierProvider<_RiderProfileNotifier, RiderProfile>(
      _RiderProfileNotifier.new,
    );

class _RiderProfileNotifier extends AsyncNotifier<RiderProfile> {
  @override
  Future<RiderProfile> build() async {
    final DeliveryRepository repo = ref.watch(deliveryRepositoryProvider);
    return repo.getProfile();
  }
}

/// Async notifier that fetches the store-info coordinates once and
/// caches them.
///
/// Used by the active-delivery map screen to backfill missing store
/// coordinates on the order payload (R12.4). Callers can
/// `ref.invalidate(storeInfoProvider)` to force a refetch.
final AsyncNotifierProvider<_StoreInfoNotifier, StoreInfo> storeInfoProvider =
    AsyncNotifierProvider<_StoreInfoNotifier, StoreInfo>(
      _StoreInfoNotifier.new,
    );

class _StoreInfoNotifier extends AsyncNotifier<StoreInfo> {
  @override
  Future<StoreInfo> build() async {
    final DeliveryRepository repo = ref.watch(deliveryRepositoryProvider);
    return repo.getStoreInfo();
  }
}

// ---------------------------------------------------------------------------
// External navigation (R12.8, R30.4)
// ---------------------------------------------------------------------------

/// Singleton [ExternalNavigationLauncher] used by the active-delivery
/// sheets to launch Google Maps directions.
///
/// Production code uses [DefaultUrlLauncherDelegate]; tests override
/// the provider with a recording delegate so they can assert on the
/// launched URL without touching the platform.
final Provider<ExternalNavigationLauncher> externalNavLauncherProvider =
    Provider<ExternalNavigationLauncher>(
      (Ref ref) => const ExternalNavigationLauncher(),
    );

/// Pluggable URL-launcher delegate used by sheets that open `tel:` /
/// `mailto:` URIs without going through the navigation helper.
final Provider<UrlLauncherDelegate> urlLauncherDelegateProvider =
    Provider<UrlLauncherDelegate>(
      (Ref ref) => const DefaultUrlLauncherDelegate(),
    );

// ---------------------------------------------------------------------------
// Location feature providers
// ---------------------------------------------------------------------------

/// Singleton [LocationPermissionService] for checking and requesting
/// device location permission (R6, R29).
final Provider<LocationPermissionService> locationPermissionServiceProvider =
    Provider<LocationPermissionService>((Ref ref) {
      return LocationPermissionService();
    });

/// Singleton [CameraPermissionService] for checking and requesting camera
/// permission before opening the QR pickup scanner.
final Provider<CameraPermissionService> cameraPermissionServiceProvider =
    Provider<CameraPermissionService>((Ref ref) {
      return CameraPermissionService();
    });

/// Singleton [LocationService] that wraps Geolocator with profile-driven
/// stream settings (R17.1–R17.3).
///
/// Disposed when the provider is invalidated so the active stream
/// subscription is cancelled.
final Provider<LocationService> locationServiceProvider =
    Provider<LocationService>((Ref ref) {
      final LocationService service = LocationService();
      ref.onDispose(service.dispose);
      return service;
    });

// ---------------------------------------------------------------------------
// Offers / active delivery / socket controllers
// ---------------------------------------------------------------------------

/// Tracks the rider's active delivery (single `ACCEPTED` / `IN_TRANSIT`
/// order). Plain [ChangeNotifier] so it stays unit-testable in pure
/// Dart.
///
/// Wired with the live [DeliveryRepository] and [SocketClient] so the
/// pickup / deliver action methods (Tasks 10.1–10.5) can drive the
/// REST + socket lifecycle end-to-end.
final ChangeNotifierProvider<ActiveDeliveryController>
activeDeliveryControllerProvider =
    ChangeNotifierProvider<ActiveDeliveryController>((Ref ref) {
      return ActiveDeliveryController(
        repository: ref.watch<DeliveryRepository>(deliveryRepositoryProvider),
        socket: ref.watch<SocketClient>(socketClientProvider),
      );
    });

/// Session-local QR-pickup verification progress for the rider's single
/// active order — layered on top of [activeDeliveryControllerProvider],
/// not a replacement for it.
final ChangeNotifierProvider<PickupSessionController>
pickupSessionControllerProvider =
    ChangeNotifierProvider<PickupSessionController>((Ref ref) {
      return PickupSessionController();
    });

// ---------------------------------------------------------------------------
// Active delivery map (R12, R25)
// ---------------------------------------------------------------------------

/// Shared [MarkerAssets] instance. The active-delivery map screen
/// warms the descriptors for the device's pixel ratio on first
/// frame; subsequent screen mounts reuse the cached bitmaps (R25.5).
final Provider<MarkerAssets> markerAssetsProvider = Provider<MarkerAssets>(
  (Ref ref) => MarkerAssets(),
);

/// On-device interim raster tile cache for the Flutter map renderer.
///
/// INTERIM ONLY — removed in Big Phase 12 when Ola Maps becomes the
/// production map/navigation stack.
final Provider<CachedTileProvider> cachedTileProviderProvider =
    Provider<CachedTileProvider>((Ref ref) {
      final Env env = ref.watch(envProvider);
      final CachedTileProvider provider = CachedTileProvider(
        userAgent: 'meetcommerce-rider-app/0.1.0 (${env.flavor.name})',
        tileUrlTemplate: env.tileUrlTemplate,
      );
      return provider;
    });

/// Long-lived publisher that pumps rider GPS samples into
/// [riderLocationNotifierProvider]'s notifier. The map screen
/// kicks `start()` on mount so the rider marker shows up
/// without waiting for the rider to manually toggle online.
final Provider<RiderLocationPublisher> riderLocationPublisherProvider =
    Provider<RiderLocationPublisher>((Ref ref) {
      final RiderLocationPublisher publisher = RiderLocationPublisher(
        notifier: ref.watch(riderLocationNotifierProvider),
        locationService: ref.watch(locationServiceProvider),
      );
      ref.onDispose(publisher.dispose);
      return publisher;
    });

/// Central location lifecycle manager.
///
/// Owns the GPS stream, permission gate, map-notifier writes, and
/// backend uploads. Wire [onWentOnline] / [onWentOffline] from the
/// home screen's toggle handler so the stream starts/stops
/// automatically with the rider's online state.
final Provider<LocationLifecycleManager> locationLifecycleManagerProvider =
    Provider<LocationLifecycleManager>((Ref ref) {
      final LocationLifecycleManager manager = LocationLifecycleManager(
        riderLocationNotifier: ref.watch(riderLocationNotifierProvider),
        locationService: ref.watch(locationServiceProvider),
        permissionService: ref.watch(locationPermissionServiceProvider),
        socket: ref.watch(socketClientProvider),
        deliveryApi: ref.watch(deliveryApiProvider),
      );
      ref.onDispose(manager.dispose);
      return manager;
    });

/// Camera autopilot for the active-delivery map. One [CameraDirector]
/// per session — the screen reads it on mount and feeds it pan
/// timestamps and recenter requests.
final Provider<CameraDirector> cameraDirectorProvider =
    Provider<CameraDirector>((Ref ref) => CameraDirector());

/// Marker / polyline / phase state for the active-delivery map screen.
///
/// Lives next to the [ActiveDeliveryController] so the screen can
/// `applyOrder` whenever the active order or its assignment status
/// changes, and `updateRiderPosition` whenever a new GPS fix arrives.
final ChangeNotifierProvider<ActiveDeliveryMapController>
activeDeliveryMapControllerProvider =
    ChangeNotifierProvider<ActiveDeliveryMapController>((Ref ref) {
      return ActiveDeliveryMapController(
        markerAssets: ref.watch<MarkerAssets>(markerAssetsProvider),
      );
    });

/// Tracks the list of active offers (status `ASSIGNED`) and owns the
/// accept / reject network actions.
final ChangeNotifierProvider<OffersController> offersControllerProvider =
    ChangeNotifierProvider<OffersController>((Ref ref) {
      return OffersController(
        repository: ref.watch(deliveryRepositoryProvider),
        socket: ref.watch(socketClientProvider),
      );
    });

/// Bridges Socket.IO delivery events into the offers and
/// active-delivery controllers.
///
/// Only constructs the controller; lifecycle ([start] / [stop]) is
/// driven by [SocketLifecycleManager] in response to session state.
final Provider<DeliverySocketController> deliverySocketControllerProvider =
    Provider<DeliverySocketController>((Ref ref) {
      final DeliverySocketController controller = DeliverySocketController(
        socket: ref.watch(socketClientProvider),
        offers: ref.watch(offersControllerProvider),
        activeDelivery: ref.watch(activeDeliveryControllerProvider),
        repository: ref.watch(deliveryRepositoryProvider),
        pickupSession: ref.watch(pickupSessionControllerProvider),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

/// Eagerly-initialised lifecycle bridge that keeps the [SocketClient]
/// connected/disconnected in sync with [SessionController].
///
/// On approved/unverified session: connects the socket and starts the
/// delivery socket controller. On unauthenticated: disconnects and
/// stops listening.
final Provider<SocketLifecycleManager> socketLifecycleManagerProvider =
    Provider<SocketLifecycleManager>((Ref ref) {
      final SocketLifecycleManager manager = SocketLifecycleManager(
        session: ref.watch(sessionControllerProvider),
        socket: ref.watch(socketClientProvider),
        deliverySocket: ref.watch(deliverySocketControllerProvider),
        tokenStore: ref.watch(tokenStoreProvider),
      );
      manager.attach();
      ref.onDispose(manager.detach);
      return manager;
    });

// ---------------------------------------------------------------------------
// Earnings feature providers
// ---------------------------------------------------------------------------

/// Controller that fetches and caches earnings per period.
///
/// Lazily loads each period on first [EarningsController.loadPeriod] call.
final ChangeNotifierProvider<EarningsController> earningsControllerProvider =
    ChangeNotifierProvider<EarningsController>((Ref ref) {
      return EarningsController(api: ref.watch(deliveryApiProvider));
    });

// ---------------------------------------------------------------------------
// History feature providers
// ---------------------------------------------------------------------------

/// Controller that manages paginated delivery history state.
final ChangeNotifierProvider<HistoryController> historyControllerProvider =
    ChangeNotifierProvider<HistoryController>((Ref ref) {
      return HistoryController(api: ref.watch(deliveryApiProvider));
    });

// ---------------------------------------------------------------------------
// Home feature providers
// ---------------------------------------------------------------------------

/// Controller that fans out the five parallel dashboard fetches on the
/// home screen (R5.1, R5.3).
///
/// `ChangeNotifierProvider` keeps the controller alive across the rider
/// shell's tab switches so the cached data survives Home -> Earnings ->
/// Home navigation.
final ChangeNotifierProvider<HomeDashboardController>
homeDashboardControllerProvider =
    ChangeNotifierProvider<HomeDashboardController>((Ref ref) {
      return HomeDashboardController(
        api: ref.watch<DeliveryApi>(deliveryApiProvider),
      );
    });

/// Controller for the home screen's online/offline toggle (R6).
///
/// Reads the latest `is_approved` flag from the home dashboard
/// controller's profile cache so the documented "5xx while not
/// approved" path can route to the approval screen without a separate
/// profile fetch.
final ChangeNotifierProvider<OnlineToggleController>
onlineToggleControllerProvider = ChangeNotifierProvider<OnlineToggleController>(
  (Ref ref) {
    return OnlineToggleController(
      api: ref.watch<DeliveryApi>(deliveryApiProvider),
      permissionService: ref.watch<LocationPermissionService>(
        locationPermissionServiceProvider,
      ),
      locationService: ref.watch<LocationService>(locationServiceProvider),
      isApprovedProvider: () {
        final HomeDashboardController dashboard = ref
            .read<HomeDashboardController>(homeDashboardControllerProvider);
        return dashboard.profile?.isApproved ?? false;
      },
    );
  },
);

// ---------------------------------------------------------------------------
// Offline stream provider (R27.1 – R27.2)
// ---------------------------------------------------------------------------

/// Stream of `isOffline` booleans backed by [ConnectivityWatcher.isOffline].
///
/// Use [isOfflineStreamProvider] in widgets to react to connectivity changes.
/// Consume via `ref.watch(isOfflineStreamProvider).valueOrNull ?? false` so
/// the widget stays non-null even before the first emission.
final StreamProvider<bool> isOfflineStreamProvider = StreamProvider<bool>((
  Ref ref,
) {
  return ref.watch<ConnectivityWatcher>(connectivityWatcherProvider).isOffline;
});

// ---------------------------------------------------------------------------
// Socket lifecycle helper
// ---------------------------------------------------------------------------

/// Connects/disconnects the [SocketClient] in step with the session
/// state, and starts/stops the [DeliverySocketController].
///
/// Lives outside the [DeliverySocketController] itself so that
/// constructor stays pure (no Riverpod dependency, no session
/// awareness).
class SocketLifecycleManager {
  /// Wires the manager to its dependencies.
  SocketLifecycleManager({
    required SessionController session,
    required SocketClient socket,
    required DeliverySocketController deliverySocket,
    required SecureTokenStore tokenStore,
  }) : _session = session,
       _socket = socket,
       _deliverySocket = deliverySocket,
       _tokenStore = tokenStore;

  final SessionController _session;
  final SocketClient _socket;
  final DeliverySocketController _deliverySocket;
  final SecureTokenStore _tokenStore;

  bool _attached = false;
  bool _socketActive = false;

  /// Subscribes to [SessionController] changes and applies the current
  /// state immediately.
  void attach() {
    if (_attached) return;
    _attached = true;
    _session.addListener(_handleSessionChange);
    _handleSessionChange();
  }

  /// Detaches the listener and disconnects the socket if active.
  void detach() {
    if (!_attached) return;
    _attached = false;
    _session.removeListener(_handleSessionChange);
    if (_socketActive) {
      _socketActive = false;
      // Fire-and-forget disconnect.
      unawaited(_deliverySocket.stop());
      unawaited(_socket.disconnect());
    }
  }

  void _handleSessionChange() {
    final SessionState s = _session.state;
    final bool shouldBeOnline = s.isApproved || s.isUnverified;

    if (shouldBeOnline && !_socketActive) {
      final String? token = _tokenStore.cachedAccessToken;
      if (token == null || token.isEmpty) {
        AppLogger.warn(
          LogTopic.socket,
          'SocketLifecycleManager: session is online but no token cached',
        );
        return;
      }
      _socketActive = true;
      _deliverySocket.start();
      // Connect is async but we don't await — the status stream
      // surfaces success/failure to the UI.
      unawaited(_socket.connect(token));
    } else if (!shouldBeOnline && _socketActive) {
      _socketActive = false;
      unawaited(_deliverySocket.stop());
      unawaited(_socket.disconnect());
    }
  }
}
