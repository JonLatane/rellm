# Rellm Flutter FE

| CI Status                                                                                                            | Information                                                                                                 |
| -------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| ![Flutter Web Build Badge](https://github.com/jonlatane/rellm/actions/workflows/flutter_web.yml/badge.svg)         | [Flutter Web Build Results](https://github.com/jonlatane/rellm/actions/workflows/flutter_web.yml)         |
| ![Flutter iOS Build Badge](https://github.com/jonlatane/rellm/actions/workflows/flutter_ios.yml/badge.svg)         | [Flutter iOS Build Results](https://github.com/jonlatane/rellm/actions/workflows/flutter_ios.yml)         |
| ![Flutter Android Build Badge](https://github.com/jonlatane/rellm/actions/workflows/flutter_android.yml/badge.svg) | [Flutter Android Build Results](https://github.com/jonlatane/rellm/actions/workflows/flutter_android.yml) |

- [Rellm Flutter FE](#rellm-flutter-fe)
  - [Toolchain: use FVM](#toolchain-use-fvm)
  - [gRPC implementation](#grpc-implementation)
  - [Routing](#routing)
  - [Building](#building)

The Flutter client for Rellm. Built mostly with `provider` and `auto_router`.

**Status:** This frontend is frozen and not actively maintained (superseded by `frontends/elm-spa` and `frontends/tamagui`). Rather than chase Flutter/Dart upgrades on unmaintained code, the SDK is pinned via [FVM](https://fvm.app/) to Flutter 3.22.1 - the latest stable release as of 2024-05-27, the last date app code in `lib/` was actually edited (older versions, including whatever was current when this README was last touched, can't resolve `pub get` against this pubspec's dependencies).

## Toolchain: use FVM
**[FVM](https://fvm.app/) is the one supported way to get a Flutter/Dart toolchain for this frontend.** Don't use a globally-installed `flutter`/`dart` -- whatever version that happens to be can't resolve this pubspec, and it will also generate subtly different protobuf code.

1. [Install FVM](https://fvm.app/docs/getting_started/installation) (or `dart pub global activate fvm`).
2. From this directory: `make fvm_install` (just `fvm install`, which reads the version from `.fvmrc` and puts the SDK in the gitignored `.fvm/flutter_sdk`).
3. Prefix every Flutter/Dart command with `fvm`: `fvm flutter pub get`, `fvm flutter run`, `fvm dart ...`. Every `make` target here already does, and fails with a pointer back to these steps if FVM or the pinned SDK is missing.
4. Point your IDE at `.fvm/flutter_sdk` (VS Code: `"dart.flutterSdkPath": ".fvm/flutter_sdk"`; IntelliJ/Android Studio: Flutter SDK path), so it uses the same SDK as the command line.

CI does the same -- see `.github/workflows/server_ci_cd.yml`, which installs the SDK pinned by `.fvmrc` rather than tracking `stable`.

## gRPC implementation
Rellm's Flutter FE uses `protoc` and [`protoc_plugin`](https://pub.dev/packages/protoc_plugin) to generate its services into `lib/generated`. See `Makefile` for the implementation.

## Routing
The Flutter FE uses `auto_route` which means modifying path definitions gets a bit weird. I've tried to make the whole system a little easier to negotiate with the
`routegen_watch`, `routegen_regenerate`, `routegen_delete`, and `routegen_generate` targets in `Makefile`.

## Building
tl;dr: `make routegen_regenerate protos_generate && fvm flutter run`.

* To rebuild auto_router routes, use `make routegen_regenerate`. This will regenerate `lib/router/router.gr.dart` from `lib/router/router.dart`.
* To rebuild proto files (in BE/Rust/Tonic land Cargo does this for us), use `make protos` (= `protos_prepare protos_generate`; also run from the repo root by plain `make`). It needs `protoc` on your PATH, and installs the pinned `protoc_plugin` through `fvm dart` for you. This will (re)generate `lib/generated/*.pb*.dart` definitions of gRPC types.