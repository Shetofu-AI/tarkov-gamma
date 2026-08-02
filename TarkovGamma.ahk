#Requires AutoHotkey v2.0
#SingleInstance Force

GAME_PROCESS := "EscapeFromTarkov.exe"
PROFILE_FILE := A_ScriptDir . "\TarkovGamma.ini"
SETTINGS_SECTION := "Profiles"
POLL_INTERVAL := 70
REAPPLY_INTERVAL := 2000
RAMP_BYTES := 1536
MAX_HOTKEY_PROFILES := 9

TraySetIcon("shell32.dll", 175)

linearRamp := BuildLinearRamp()
profileNames := LoadProfileNames()
activeProfile := LoadActiveProfile()
gameRamp := LoadProfile(activeProfile)
automationIsEnabled := true
gammaIsApplied := false
targetDevice := ""
lastApplyTick := 0

BuildTrayMenu()
RegisterProfileHotkeys()
RefreshIconTip()
OnExit(RestoreOnExit)
SetTimer(RefreshGammaState, POLL_INTERVAL)

RefreshGammaState() {
    global automationIsEnabled, gammaIsApplied, targetDevice, lastApplyTick
    if (!automationIsEnabled)
        return
    gameWindow := FindGameWindow()
    if (gameWindow) {
        device := GetWindowDevice(gameWindow)
        if (gammaIsApplied && device != targetDevice)
            ApplyRamp(targetDevice, linearRamp)
        if (!gammaIsApplied || device != targetDevice || A_TickCount - lastApplyTick > REAPPLY_INTERVAL) {
            ApplyRamp(device, gameRamp)
            targetDevice := device
            gammaIsApplied := true
            lastApplyTick := A_TickCount
        }
        return
    }
    if (!gammaIsApplied)
        return
    ApplyRamp(targetDevice, linearRamp)
    gammaIsApplied := false
}

FindGameWindow() {
    global GAME_PROCESS
    try {
        if (WinGetProcessName("A") = GAME_PROCESS)
            return WinExist("A")
    }
    catch {
        return 0
    }
    return 0
}

GetWindowDevice(hwnd) {
    monitor := DllCall("user32\MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr")
    info := Buffer(104, 0)
    NumPut("uint", 104, info, 0)
    if (!DllCall("user32\GetMonitorInfoW", "ptr", monitor, "ptr", info))
        return ""
    return StrGet(info.Ptr + 40, 32, "UTF-16")
}

ApplyRamp(device, ramp) {
    if (device = "")
        return false
    hdc := DllCall("gdi32\CreateDCW", "wstr", "DISPLAY", "wstr", device, "ptr", 0, "ptr", 0, "ptr")
    if (!hdc)
        return false
    result := DllCall("gdi32\SetDeviceGammaRamp", "ptr", hdc, "ptr", ramp, "int")
    DllCall("gdi32\DeleteDC", "ptr", hdc)
    return result != 0
}

ReadRamp(device) {
    global RAMP_BYTES
    hdc := DllCall("gdi32\CreateDCW", "wstr", "DISPLAY", "wstr", device, "ptr", 0, "ptr", 0, "ptr")
    if (!hdc)
        return 0
    ramp := Buffer(RAMP_BYTES, 0)
    result := DllCall("gdi32\GetDeviceGammaRamp", "ptr", hdc, "ptr", ramp, "int")
    DllCall("gdi32\DeleteDC", "ptr", hdc)
    if (!result)
        return 0
    return ramp
}

BuildLinearRamp() {
    global RAMP_BYTES
    ramp := Buffer(RAMP_BYTES, 0)
    loop 256 {
        index := A_Index - 1
        value := Min(65535, index * 257)
        loop 3 {
            NumPut("ushort", value, ramp, ((A_Index - 1) * 256 + index) * 2)
        }
    }
    return ramp
}

LoadProfileNames() {
    global PROFILE_FILE, SETTINGS_SECTION
    names := []
    sections := IniRead(PROFILE_FILE, , , "")
    for section in StrSplit(sections, "`n", "`r") {
        if (section != "" && section != SETTINGS_SECTION)
            names.Push(section)
    }
    return names
}

LoadActiveProfile() {
    global PROFILE_FILE, SETTINGS_SECTION, profileNames
    if (!profileNames.Length)
        return ""
    stored := IniRead(PROFILE_FILE, SETTINGS_SECTION, "Active", "")
    for name in profileNames {
        if (name = stored)
            return stored
    }
    return profileNames[1]
}

LoadProfile(name) {
    global PROFILE_FILE, RAMP_BYTES
    if (name = "")
        return BuildLinearRamp()
    ramp := Buffer(RAMP_BYTES, 0)
    for channelIndex, channelName in ["R", "G", "B"] {
        raw := IniRead(PROFILE_FILE, name, channelName, "")
        if (raw = "")
            return BuildLinearRamp()
        values := StrSplit(raw, ",")
        if (values.Length != 256)
            return BuildLinearRamp()
        for valueIndex, value in values {
            NumPut("ushort", Integer(value), ramp, ((channelIndex - 1) * 256 + valueIndex - 1) * 2)
        }
    }
    return ramp
}

SaveProfile(name, ramp) {
    global PROFILE_FILE
    for channelIndex, channelName in ["R", "G", "B"] {
        values := ""
        loop 256 {
            value := NumGet(ramp, ((channelIndex - 1) * 256 + A_Index - 1) * 2, "ushort")
            values .= (A_Index = 1 ? "" : ",") . value
        }
        IniWrite(values, PROFILE_FILE, name, channelName)
    }
}

SelectProfile(name) {
    global PROFILE_FILE, SETTINGS_SECTION, activeProfile, gameRamp, gammaIsApplied
    if (name = "")
        return
    activeProfile := name
    gameRamp := LoadProfile(name)
    gammaIsApplied := false
    IniWrite(name, PROFILE_FILE, SETTINGS_SECTION, "Active")
    BuildTrayMenu()
    RefreshIconTip()
}

RefreshIconTip() {
    global activeProfile, automationIsEnabled
    A_IconTip := "TarkovGamma: " . (activeProfile = "" ? "нет профилей" : activeProfile) . (automationIsEnabled ? "" : " (пауза)")
}

SelectProfileByIndex(thisHotkey) {
    global profileNames
    index := Integer(SubStr(thisHotkey, -1))
    if (index > profileNames.Length)
        return
    SelectProfile(profileNames[index])
}

CycleProfile(*) {
    global profileNames, activeProfile
    if (profileNames.Length < 2)
        return
    for index, name in profileNames {
        if (name = activeProfile) {
            SelectProfile(profileNames[index = profileNames.Length ? 1 : index + 1])
            return
        }
    }
    SelectProfile(profileNames[1])
}

CaptureCurrentRamp(*) {
    global activeProfile, gameRamp, gammaIsApplied, targetDevice
    if (activeProfile = "") {
        CreateProfile()
        return
    }
    ramp := ReadActiveMonitorRamp()
    if (!ramp)
        return
    gameRamp := ramp
    SaveProfile(activeProfile, ramp)
    gammaIsApplied := false
    targetDevice := ""
}

CreateProfile(*) {
    global profileNames
    ramp := ReadActiveMonitorRamp()
    if (!ramp)
        return
    prompt := InputBox("Имя нового профиля", "TarkovGamma", "w280 h130")
    if (prompt.Result != "OK" || Trim(prompt.Value) = "")
        return
    name := Trim(prompt.Value)
    for existing in profileNames {
        if (existing = name) {
            TrayTip("TarkovGamma", "Профиль " . name . " уже есть, используй перезапись")
            return
        }
    }
    SaveProfile(name, ramp)
    profileNames := LoadProfileNames()
    RegisterProfileHotkeys()
    SelectProfile(name)
}

ReadActiveMonitorRamp() {
    device := GetWindowDevice(WinExist("A"))
    if (device = "") {
        TrayTip("TarkovGamma", "Не определён монитор активного окна")
        return 0
    }
    ramp := ReadRamp(device)
    if (!ramp) {
        TrayTip("TarkovGamma", "Не удалось прочитать гамму " . device)
        return 0
    }
    return ramp
}

RegisterProfileHotkeys() {
    global MAX_HOTKEY_PROFILES, profileNames
    loop MAX_HOTKEY_PROFILES {
        Hotkey("^" . A_Index, SelectProfileByIndex, A_Index <= profileNames.Length ? "On" : "Off")
    }
}

BuildTrayMenu() {
    global profileNames, activeProfile, automationIsEnabled, MAX_HOTKEY_PROFILES
    A_TrayMenu.Delete()
    for index, name in profileNames {
        label := name . (index <= MAX_HOTKEY_PROFILES ? "`tCtrl+" . index : "")
        A_TrayMenu.Add(label, SelectProfileFromTray)
        if (name = activeProfile)
            A_TrayMenu.Check(label)
    }
    if (profileNames.Length)
        A_TrayMenu.Add()
    A_TrayMenu.Add("Следующий профиль`tCtrl+Alt+X", CycleProfile)
    A_TrayMenu.Add("Перезаписать активный`tCtrl+Alt+G", CaptureCurrentRamp)
    A_TrayMenu.Add("Новый профиль из текущей гаммы", CreateProfile)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Пауза`tCtrl+Alt+P", ToggleAutomation)
    A_TrayMenu.Add("Сбросить гамму сейчас", ResetAllMonitors)
    A_TrayMenu.Add("Выход", (*) => ExitApp())
    if (!automationIsEnabled)
        A_TrayMenu.Check("Пауза`tCtrl+Alt+P")
}

SelectProfileFromTray(itemName, *) {
    SelectProfile(StrSplit(itemName, "`t")[1])
}

ToggleAutomation(*) {
    global automationIsEnabled, gammaIsApplied
    automationIsEnabled := !automationIsEnabled
    A_TrayMenu.ToggleCheck("Пауза`tCtrl+Alt+P")
    if (!automationIsEnabled)
        gammaIsApplied := false
    RefreshIconTip()
}

ResetAllMonitors(*) {
    global gammaIsApplied, linearRamp
    monitorCount := MonitorGetCount()
    loop monitorCount {
        ApplyRamp(MonitorGetName(A_Index), linearRamp)
    }
    gammaIsApplied := false
}

RestoreOnExit(*) {
    ResetAllMonitors()
}

^!g::CaptureCurrentRamp()
^!p::ToggleAutomation()
^!x::CycleProfile()
