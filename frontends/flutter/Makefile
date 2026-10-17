.NOTPARALLEL:

# This frontend is frozen on the Flutter SDK pinned in `.fvmrc`, managed by FVM (https://fvm.app).
# Always go through `fvm` (`fvm flutter ...`, `fvm dart ...`) -- a bare `flutter`/`dart` on PATH is
# whatever version happens to be installed, which can't resolve this pubspec. First time:
#   install FVM (https://fvm.app/docs/getting_started/installation), then `make fvm_install`.
# Every target below depends on `fvm_ready`, which fails with that same instruction if either is missing.
.PHONY: test fvm_check fvm_ready fvm_install

fvm_check:
	@command -v fvm >/dev/null || { echo "fvm is not installed. Install it (https://fvm.app/docs/getting_started/installation), then run 'make fvm_install'." >&2; exit 1; }

# Downloads the Flutter SDK version pinned in `.fvmrc` into the (gitignored) `.fvm/` directory.
fvm_install: fvm_check
	fvm install

fvm_ready: fvm_check
	@test -d .fvm/flutter_sdk || { echo "The pinned Flutter SDK isn't installed yet. Run 'make fvm_install'." >&2; exit 1; }

run: fvm_ready
	fvm flutter run

build: build_web

build_web: fvm_ready
	fvm flutter build web --web-renderer canvaskit --release --base-href /flutter/

test: fvm_ready
	fvm flutter test


# Local Flutter FE dev targets
protos: protos_prepare protos_generate
# Pinned to match this project's `protobuf`/`grpc` package majors (see pubspec.yaml)
# and the Dart SDK bundled with the locked Flutter version (see .fvmrc). Newer
# protoc_plugin releases (22.0.0+) generate code using the `$_setField`/`$_clearField`
# API, which only exists in protobuf >=4.1.0 - that needs Dart >=3.6, too new for
# this frozen frontend's pinned SDK. protoc_plugin must also be activated with
# `fvm dart` (not bare `dart`), or it builds against whatever Flutter happens to
# be ambient on PATH instead of the pinned SDK.
protos_prepare: fvm_ready
	fvm dart pub global activate protoc_plugin 21.1.2
protos_generate: fvm_ready
	mkdir -p lib/generated
	PATH="$(CURDIR)/.fvm/flutter_sdk/bin:$(HOME)/.pub-cache/bin:$$PATH" protoc --dart_out=grpc:lib/generated -I../../protos ../../protos/*.proto google/protobuf/timestamp.proto google/protobuf/field_mask.proto google/protobuf/empty.proto

routegen_watch: fvm_ready
	fvm flutter packages pub run build_runner watch
routegen_regenerate: routegen_delete routegen_generate
routegen_delete:
	- rm lib/router/router.gr.dart
routegen_generate: fvm_ready
	fvm flutter packages pub run build_runner build
