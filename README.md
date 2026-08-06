# TarkovGamma

Per-window gamma correction for Escape From Tarkov. The correction is applied only while the game window is focused and you are actually in a raid, and the display returns to its default ramp the moment you alt-tab out or get sent back to the main menu.

Tools like RivaTuner can apply a colour scheme, but it stays on the whole desktop until you switch it back by hand. This script binds the correction to window focus instead.

## What it does

- Applies a saved gamma ramp when `EscapeFromTarkov.exe` becomes the active window
- Restores a linear ramp as soon as focus leaves the game, when the game exits, and when the script exits
- Follows the game log to tell a raid from the menu, so the correction is live in the raid only and drops the moment you die, extract or go back to the hideout
- Drops the correction whenever the mouse cursor is visible, which is exactly when the game shows UI — inventory, looting, the map, the in-raid menu — because the interface looks wrong through a gamma curve meant for the world
- Touches only the monitor the game window lives on — other displays are never modified
- Re-applies the ramp every 2 seconds while the game is focused, because Unity resets the gamma ramp on display mode changes and wipes any external correction
- Stores several named profiles and remembers which one is active across restarts
- Switches back to a designated startup profile every time the game process launches, so a profile you picked for one raid does not silently stay for the next session

## Requirements

- Windows
- [AutoHotkey v2](https://www.autohotkey.com/)
- A display that is not running in HDR mode — `SetDeviceGammaRamp` is a no-op under HDR

## Install

1. Put `TarkovGamma.ahk` and `TarkovGamma.default.ini` in the same folder
2. Run it with AutoHotkey v2
3. For autostart, drop a shortcut into `shell:startup` pointing at `AutoHotkey64.exe "<path>\TarkovGamma.ahk"`

On first run the script copies `TarkovGamma.default.ini` to `TarkovGamma.ini` and works from that copy, so your own tweaks never collide with an update of the shipped defaults. Without the default file it simply starts with no profiles and keeps the display linear until you create one.

## Bundled profiles

| Hotkey | Profile | Curve |
| --- | --- | --- |
| `Ctrl+1` | `Default` | Linear — the untouched display ramp, the vanilla picture |
| `Ctrl+2` | `Tarkov` | Aggressive night curve: shadows stretched hard, white point pulled down to 94.5% |
| `Ctrl+3` | `Base` | Mild everyday curve: gamma 1.25, 3.5% black lift that fades out towards the highlights, white point at 98% |
| `Ctrl+4` | `Test` | RivaTuner-style curve for `Brightness -40, Contrast +10, Gamma 2.2`: midtones stretched, everything below input 27 crushed to black, white point at 70% |

`Base` is the startup profile — it gets selected automatically whenever `EscapeFromTarkov.exe` starts. It is meant as a baseline that is simply easier to read than the stock image without washing the picture out; `Tarkov` stays for genuinely dark maps.

The RivaTuner sliders map onto the ramp as `out = (1 + contrast/100) * (in ^ (1/gamma)) + brightness/100`, clamped to `[0, 1]`. Fitting that formula against a ramp captured from RivaTuner reproduces it to within a fraction of a percent above input 16, so profiles can be authored from slider values without launching RivaTuner at all.

## Hotkeys

| Hotkey | Action |
| --- | --- |
| `Ctrl+1` … `Ctrl+9` | Select profile by position in the ini file |
| `Ctrl+Alt+X` | Next profile |
| `Ctrl+Alt+G` | Overwrite the active profile with the ramp currently on screen |
| `Ctrl+Alt+P` | Pause — stop touching the gamma at all |

`Ctrl+N` is registered only for numbers that actually have a profile, so unused ones stay free for other software.

Note that `RegisterHotKey` is exclusive: while the script holds `Ctrl+1`, the game never sees that combination. In Tarkov `Ctrl` is crouch and the digits are weapon slots, so crouching and swapping to a slot switches the gamma profile instead of the weapon. Move the binding to `Ctrl+Alt+N` in `RegisterProfileHotkeys` if that gets in your way.

## Raid detection

The script tails the newest `*application_*.log` under the game's `Logs` folder and tracks two lines: `|application|GameStarted:` means the raid is live, `|application|Init: pstrGameVersion` means the client is back in the main menu — that line shows up both on game start and right after a death or extraction. While the log says "menu", the ramp stays linear even with the game focused.

The `Logs` folder is found through the `Escape from Tarkov` uninstall entry in the registry. Set `LogsRoot` in `[Profiles]` if your install is not registered there. If neither works, raid detection quietly disables itself and the correction applies whenever the game is focused, as it did before.

Turn it off with the tray menu item **Только в рейде** or `RaidOnly=0` in the ini — the correction then covers the menu and the hideout too.

## Creating a profile

1. `Ctrl+Alt+P` to pause the script
2. Dial in the correction with whatever tool you like — RivaTuner, a calibration utility, anything that writes a gamma ramp
3. Tray menu → **Новый профиль из текущей гаммы**, give it a name
4. `Ctrl+Alt+P` to resume

`Ctrl+Alt+G` does the same thing but overwrites the profile that is currently selected.

## Profile format

Profiles live in `TarkovGamma.ini` next to the script. Each profile is one section holding the full 768-entry gamma ramp — 256 comma-separated 16-bit values per channel:

```ini
[Profiles]
Active=Base
Startup=Base
RaidOnly=1

[Default]
R=0,257,514,...,65535
G=0,257,514,...,65535
B=0,257,514,...,65535

[Tarkov]
R=0,0,0,...,61952
G=...
B=...
```

Section order defines the `Ctrl+N` numbering. Rename, reorder or delete profiles by editing the file; the script reads it at startup.

`Startup` names the profile that is selected when the game process appears. Point it at another section to change the default, or delete the key to keep whatever profile was active last. `RaidOnly` and the optional `LogsRoot` control raid detection, see above.

## Notes

- **Do not leave RivaTuner running** if you bind its schemes to `Ctrl+1`/`Ctrl+2`/`Ctrl+3`. It claims those combinations through `RegisterHotKey`, which is exclusive, and this script will silently never see them. Forcing a low-level hook (`$^1`) takes them back, but a plain registration is more reliable in anti-cheat protected fullscreen games.
- Notifications are deliberately absent. A Windows toast can pull focus away from a fullscreen game, which would immediately drop the correction. Feedback goes to the tray icon tooltip and a checkmark in the tray menu.
- The script only reads and writes the display gamma ramp through GDI. It does not touch the game process.

## License

MIT
