# Bundled libraries

These are unmodified upstream Lua sources, downloaded on 2026-11-14. They are
included in the repository and release package so the minimap button and broker
launcher work without other addons. LibStub shares libraries with other addons
and selects the newest loaded version.

Load order: LibStub → CallbackHandler → LibDataBroker → LibDBIcon.
Upstream copyright and license notices in the files are retained; these libraries
are third-party code, not covered by Profession Tooltip's own license.

| Library | Source | SHA-256 |
|---|---|---|
| LibStub | https://repos.wowace.com/wow/libstub/trunk/LibStub.lua | `7ba7300471327c0de1b3e42a4edfd62cbad79bd30100d6377736d2c1080e9b96` |
| CallbackHandler-1.0 | https://repos.wowace.com/wow/callbackhandler/trunk/CallbackHandler-1.0/CallbackHandler-1.0.lua | `8ab5d51799e8c67b6d17b523b3c191ff63ad24e081134ab8ac7d188ce69701b9` |
| LibDataBroker-1.1 | https://github.com/tekkub/libdatabroker-1-1/blob/master/LibDataBroker-1.1.lua | `f3d4758f2060215492c9764b1d7dc2a336826d4cd253cd54ff9ff7c6d78f04e2` |
| LibDBIcon-1.0 (minor 57) | https://repos.wowace.com/wow/libdbicon-1-0/trunk/LibDBIcon-1.0/LibDBIcon-1.0.lua | `cafa823dfb9f216eb476af4bcd2fad4c25c718f39b7565fa1c924dbebac41f91` |

`UI/MinimapButton.lua` migrates the old `minimap.angle` to `minimap.minimapPos`
only if no LibDBIcon position exists. LibDBIcon then saves drag positions directly
in that table. The settings window's `minimap.show` is mirrored to LibDBIcon's
`minimap.hide`. The TOC continues to provide the addon compartment entry, so the
library must not register a second one.
