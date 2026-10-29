# Local AirPlay + Bluetooth experiment

The app receives H.264 screen frames over AirPlay and uses the existing BLE HID connection for input. Strict `airplay` mode never starts USB capture. `airplay-bootstrap` keeps USB available only while waiting for an AirPlay stream, then prefers the decoded AirPlay source; status identifies the actual source as `usb` or `airplay`. Audio is discarded. This is a local prototype for one unlocked portrait iPhone, not an Apple-certified AirPlay implementation.

## Build

The bundled `third_party/mirrordeck-airplay` checkout supplies the native receiver source and bundled UxPlay revision 546820c723b0539ff6ba0f6eefc590b26dc55322 (no WebDriverAgent). Build it with `./native/build.sh` there. Dependencies: cmake, pkgconf, openssl@3, libplist. Then in this repository run `CODESIGN_IDENTITY=- ./scripts/build-app.sh`. This build was verified on macOS 27.0.1; the local native dependency may require that OS.

## Start

Quit any previous instance of this app, then:

```sh
open --env IPHONE_USE_SCREEN=airplay build/iPhoneUse.app
```

Allow the app's Bluetooth and Local Network prompts. On the iPhone, choose **Control Center → Screen Mirroring → iPhone Use Wireless**. Keep AssistiveTouch enabled and the existing BLE HID connection active. For this first implementation keep both devices on the same local network. USB can be disconnected once a decoded AirPlay frame is visible. The HTTP API remains on `127.0.0.1:7390` only; the AirPlay receiver advertises on the local network while this app is running. Use only with your selected phone and stop the app when finished.

`GET /status` reports `transport: airplay` for a device only after a decoded frame arrives. This is distinct from BLE subscription readiness. Validate both, then perform a benign action and inspect a fresh screenshot with USB disconnected.

The USB capture source remains available with IPHONE_USE_SCREEN unset; the superseded prebuilt USB fallback was removed in 0.3.0. No login item or automatic launch has been added.

See AIRPLAY-NOTICE.md and licenses/ for the derived component's source and licensing. Future distribution must preserve all applicable licenses.

## Agent-assisted first connection while USB is present

Use `IPHONE_USE_SCREEN=airplay-bootstrap` to keep the existing USB/BLE path for navigating Control Center. After selecting iPhone Use Wireless, release USB video capture with `curl -X POST http://127.0.0.1:7390/capture/usb/pause`. Simultaneous USB capture prevented the first wireless video stream in the local test; releasing it allowed H.264 frames. Keep USB capture paused after AirPlay becomes active. `POST /capture/usb/resume` is an explicit fallback when no AirPlay stream exists.

Receiving AirPlay frames with the cable connected is not proof of cable-free networking: physically unplug USB and verify a fresh screenshot plus a benign input action before claiming wireless completion.

## Wi-Fi only advertisement

After unplugging USB, select the newly advertised receiver to establish a fresh network session. The local UxPlay DNS-SD adapter accepts `IPHONE_USE_AIRPLAY_INTERFACE=en0` to advertise only on this Mac's Wi-Fi interface. The app also accepts `IPHONE_USE_AIRPLAY_NAME` so a fresh receiver name can avoid a sender's previous USB-scoped service cache. Current launch:

```sh
open --env IPHONE_USE_SCREEN=airplay --env IPHONE_USE_AIRPLAY_INTERFACE=en0 --env 'IPHONE_USE_AIRPLAY_NAME=iPhone Use Wireless WiFi' build/iPhoneUse.app
```

Check the Wi-Fi interface name on other Macs; this machine uses en0. No USB capture runs in this mode. The first cable-connected session was not cable-free: its link-local interface disappeared when unplugged. Reconnecting through the Wi-Fi-only service resolved this in the test below.

## Verified cable-free test — 2026-10-16

With USB physically unplugged, strict AirPlay mode and en0-only advertisement received a fresh 498×1080 H.264 stream. BLE input returned home, opened Spotlight, searched Calculator, launched it, and performed 12×9=108; a fresh decoded screenshot confirmed the result. No WDA was used. Rapid batched pointer taps dropped inputs in this test; use sequential actions with observed screen transitions. Long-running stability and disconnect/reconnect behavior remain untested. The app was left running for the user.

Keyboard follow-up: `POST /key` with `{"key":"eject"}` now sends Consumer Eject (0x00B8) to try toggling the iOS software keyboard. Build and phone behavior verified: after reconnection, a focused WeChat input had no software keyboard; sending Eject immediately displayed it (2026-10-16 12:56). This is a toggle, not automatic display on every focus. AssistiveTouch Show Onscreen Keyboard was enabled but did not resolve the issue by itself.
