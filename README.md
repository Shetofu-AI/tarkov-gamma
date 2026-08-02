# TarkovGamma

Per-window gamma correction for Escape From Tarkov. The correction is applied only while the game window is focused, and the display returns to its default ramp the moment you alt-tab out.

Tools like RivaTuner can apply a colour scheme, but it stays on the whole desktop until you switch it back by hand. This script binds the correction to window focus instead.

## What it does

- Applies a saved gamma ramp when `EscapeFromTarkov.exe` becomes the active window
- Restores a linear ramp as soon as focus leaves the game, when the game exits, and when the script exits
- Touches only the monitor the game window lives on — other displays are never modified
- Re-applies the ramp every 2 seconds while the game is focused, because Unity resets the gamma ramp on display mode changes and wipes any external correction
- Stores several named profiles and remembers which one is active across restarts

## Requirements

- Windows
- [AutoHotkey v2](https://www.autohotkey.com/)
- A display that is not running in HDR mode — `SetDeviceGammaRamp` is a no-op under HDR

## Install

1. Put `TarkovGamma.ahk` anywhere you like
2. Run it with AutoHotkey v2
3. For autostart, drop a shortcut into `shell:startup` pointing at `AutoHotkey64.exe "<path>\TarkovGamma.ahk"`

The script has no profiles on first run and will keep the display linear until you create one.

## Hotkeys

| Hotkey | Action |
| --- | --- |
| `Ctrl+1` … `Ctrl+9` | Select profile by position in the ini file |
| `Ctrl+Alt+X` | Next profile |
| `Ctrl+Alt+G` | Overwrite the active profile with the ramp currently on screen |
| `Ctrl+Alt+P` | Pause — stop touching the gamma at all |

`Ctrl+N` is registered only for numbers that actually have a profile, so unused ones stay free for other software.

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
Active=Tarkov

[Neutral]
R=0,257,514,...,65535
G=0,257,514,...,65535
B=0,257,514,...,65535

[Tarkov]
R=0,0,0,...,61952
G=...
B=...
```

Section order defines the `Ctrl+N` numbering. Rename, reorder or delete profiles by editing the file; the script reads it at startup.

## Notes

- **Do not leave RivaTuner running** if you bind its schemes to `Ctrl+1`/`Ctrl+2`/`Ctrl+3`. It claims those combinations through `RegisterHotKey`, which is exclusive, and this script will silently never see them. Forcing a low-level hook (`$^1`) takes them back, but a plain registration is more reliable in anti-cheat protected fullscreen games.
- Notifications are deliberately absent. A Windows toast can pull focus away from a fullscreen game, which would immediately drop the correction. Feedback goes to the tray icon tooltip and a checkmark in the tray menu.
- The script only reads and writes the display gamma ramp through GDI. It does not touch the game process.

## License

MIT
