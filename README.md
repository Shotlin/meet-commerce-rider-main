# Freashcut Rider

Delivery-partner (rider) app for the Meet Commerce / FreshCuts platform.

- Project title: **Meet Commerce – Rider Main**
- Local folder: `meet-commerce-rider-main`
- Flutter package: `meet_commerce_rider_main`
- Android namespace / application id: `com.meetcommerce.rider`
- iOS bundle id: `com.meetcommerce.rider`
- Display name: **Freashcut Rider**

## Backend

The app talks to the Meet Commerce backend:

- REST: `https://api.fc.opslin.com/api/v1`
- Socket.IO: `https://api.fc.opslin.com`

Both are resolved through `lib/core/config/env.dart` and can be overridden per
build without editing source:

```bash
# Point the app at the locally running Meet Commerce backend (Docker)
flutter run \
  --dart-define=FLAVOR=dev \
  --dart-define=API_BASE_URL=http://localhost:4500/api/v1 \
  --dart-define=SOCKET_BASE_URL=http://localhost:4500
```

No secrets live in this repository. Map-provider credentials are brokered by
the backend (see `lib/core/maps/`), never embedded in the app binary.

## Toolchain

Flutter is pinned with FVM (`.fvmrc` → `3.41.9`), matching the rest of the
Meet Commerce apps:

```bash
fvm install
fvm flutter pub get
```

## Running

```bash
# debug on the first available device (dev flavor)
./run.sh

# pick a device explicitly
./run.sh -d <device-id>

# staging flavor
./run.sh staging

# release build
./run.sh release
```

## Build flavors

Three flavors exist and share the same commands:

| Flavor | Android application id | App name |
|---|---|---|
| dev | `com.meetcommerce.rider.dev` | Freashcut Rider Dev |
| staging | `com.meetcommerce.rider.staging` | Freashcut Rider Staging |
| prod | `com.meetcommerce.rider` | Freashcut Rider |

```bash
flutter run --flavor dev --dart-define=FLAVOR=dev
flutter build apk --flavor prod --dart-define=FLAVOR=prod --release
```

`FLAVOR=dev` enables developer-only affordances (OTP echo on the OTP screen,
demo delivery completion). Those affordances are compiled out of staging and
production builds and must never be visible there.

## Project layout

```text
lib/
  app/                  # router, bootstrap, top-level shell
  core/                 # config, network, realtime, storage, location,
                        # notifications, theme, maps, utils
  features/
    auth/               # phone OTP login, session restore
    onboarding/         # rider approval + document upload
    home/               # rider shell + dashboard
    delivery/           # offers, accept/reject, active delivery, maps
    earnings/           # today/week/month earnings + payouts
    history/            # paginated delivery history
    profile/            # profile + settings + logout
  shared/widgets/       # design-system widgets
```

## Maps

The production map / navigation stack for this app is **Ola Maps** (see the
rebuild plan's Big Phase 12). The current `flutter_map` + raster tile rendering
is interim and is removed once the Ola implementation is proven on Android and
iOS. Ola credentials are never embedded in the app.

## Push notifications

Firebase Cloud Messaging is wired, but `lib/firebase_options.dart` and
`android/app/google-services.json` currently hold **placeholder** values because
no Meet Commerce Firebase project is registered for `com.meetcommerce.rider`
yet. Firebase initialization failure is non-fatal, so the app runs without push
until the real configuration is added.

## Tests

```bash
flutter analyze
flutter test
```

Property-based tests for domain invariants live under `test/properties/` and
use [`glados`](https://pub.dev/packages/glados).
