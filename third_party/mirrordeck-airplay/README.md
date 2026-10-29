> This is the retained upstream MirrorDeck README. This reduced vendor directory supplies only the native AirPlay dependency; follow the [project README](../../README.md) for iphone-use-pro installation and operation.

# MirrorDeck AirPlay core subset

Retained native/ and vendor/UxPlay from egarl004/mirrordeck for iphone-use-pro. Unused original application, WDA bootstrap, web UI, packaging and spike code removed. UxPlay source revision: 546820c723b0539ff6ba0f6eefc590b26dc55322, with local dns_sd.c Wi-Fi interface binding patch. Build from this directory with ./native/build.sh; do not fetch or overwrite the bundled patched source. See LICENSE and licenses/ for original notices. Native build updates the single bridge header in the root Sources/CMirrorBridge/include directory.
