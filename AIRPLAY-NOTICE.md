# Source and license notices

iphone-use-pro is a wireless derivative of [iPhone Use](https://github.com/xhoantran/iphone-use) and [MirrorDeck](https://github.com/egarl004/mirrordeck). The combined project is distributed under GPL-3.0-only; independently licensed components retain their original terms and copyright notices.

| Included source | Origin / recorded revision | License notice |
| --- | --- | --- |
| Original iPhone Use app, BLE HID, HTTP and MCP foundation | xhoantran/iphone-use, original checkout bc0fe36e78ec5a3af095c813574e3a8b7bbea4dd | [MIT, NewWave AI](licenses/iPhoneUse-MIT.txt) |
| AirPlayReceiver.swift, VideoPipeline.swift and native bridge adaptation | egarl004/mirrordeck, original checkout 015987740094194f184e6f590871e47e60dce617 | [GPL-3.0](licenses/MirrorDeck-GPL-3.0.txt) |
| Bundled UxPlay protocol core, playfair and llhttp | FDH2/UxPlay, 546820c723b0539ff6ba0f6eefc590b26dc55322 | See bundled LICENSE files and [component notices](third_party/mirrordeck-airplay/licenses/NOTICE.md) |

The revisions record the source checkouts used during development; this repository includes local modifications. Local additions include Wi-Fi interface selection for DNS-SD, strict AirPlay capture, frame decoding integration, synchronized BLE state, bounded HTTP parsing, explicit phone matching, screenshot scaling, adaptive frame waiting and install/start scripts. Upstream source headers are retained.

Native source is included at `third_party/mirrordeck-airplay/native` and `third_party/mirrordeck-airplay/vendor/UxPlay`. Build with `./scripts/setup.sh`; it compiles a replaceable `libMirrorCore.dylib` and bundles it in `build/iPhoneUse.app/Contents/Frameworks/`. No WebDriverAgent is fetched or installed. Build dependencies are obtained with Homebrew; see their own licenses.

This repository distributes source, not a signed/notarized binary release. Keep the license texts and corresponding source when redistributing. AirPlay is an Apple technology; this project is not affiliated with or endorsed by Apple.
