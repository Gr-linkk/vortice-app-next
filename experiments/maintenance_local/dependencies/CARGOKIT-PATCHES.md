# Cargokit integration adjustment

The vendored Cargokit scaffold comes from flutter_rust_bridge codegen 2.13.0.
Its copyright headers and combined MIT/Apache license are retained.

`gradle/plugin.gradle` respects Flutter's selected target platforms instead of
unconditionally adding Android x86/x64 emulator targets to every debug build.
NEXT-011 packages Android ARM64 for the physical phone. Explicit emulator
selection can still build that architecture; unused libraries are not built
as a side effect of a phone build. Linux configuration is unchanged.
