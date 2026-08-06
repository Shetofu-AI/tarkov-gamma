#Requires AutoHotkey v2.0
#SingleInstance Force

GAME_PROCESS := "EscapeFromTarkov.exe"
PROFILE_FILE := A_ScriptDir . "\TarkovGamma.ini"
DEFAULT_PROFILE_FILE := A_ScriptDir . "\TarkovGamma.default.ini"
SETTINGS_SECTION := "Profiles"
POLL_INTERVAL := 70
PROCESS_POLL_INTERVAL := 1000
LOG_POLL_INTERVAL := 500
LOG_RESCAN_INTERVAL := 3000
REAPPLY_INTERVAL := 2000
RAMP_BYTES := 1536
MAX_HOTKEY_PROFILES := 9
RAID_STARTED_MARKER := "|application|GameStarted:"
MENU_ENTERED_MARKER := "|application|Init: pstrGameVersion"

TraySetIcon("shell32.dll", 175)

EnsureProfileFile()
linearRamp := BuildLinearRamp()
profileNames := LoadProfileNames()
activeProfile := LoadActiveProfile()
startupProfile := LoadStartupProfile()
gameRamp := LoadProfile(activeProfile)
raidOnly := LoadRaidOnly()
logsRoot := LoadLogsRoot()
automationIsEnabled := true
gammaIsApplied := false
gameIsRunning := ProcessExist(GAME_PROCESS) != 0
raidIsActive := false
logFile := 0
logPath := ""
logPending := ""
lastLogScanTick := 0
targetDevice := ""
lastApplyTick := 0

BuildTrayMenu()
RegisterProfileHotkeys()
RefreshIconTip()
OnExit(RestoreOnExit)
SetTimer(RefreshGammaState, POLL_INTERVAL)
SetTimer(WatchGameProcess, PROCESS_POLL_INTERVAL)
SetTimer(WatchRaidLog, LOG_POLL_INTERVAL)

WatchGameProcess() {
    global GAME_PROCESS, gameIsRunning, startupProfile, activeProfile
    isRunning := ProcessExist(GAME_PROCESS) != 0
    if (isRunning && !gameIsRunning && startupProfile != "" && startupProfile != activeProfile)
        SelectProfile(startupProfile)
    gameIsRunning := isRunning
}

RefreshGammaState() {
    global automationIsEnabled, gammaIsApplied, targetDevice, lastApplyTick
    if (!automationIsEnabled)
        return
    gameWindow := FindGameWindow()
    if (gameWindow && GammaIsAllowed()) {
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

GammaIsAllowed() {
    global raidOnly, logPath, raidIsActive
    if (!raidOnly || logPath = "")
        return true
    return raidIsActive
}

WatchRaidLog() {
    global raidOnly, logsRoot, gameIsRunning, logFile, logPath, lastLogScanTick, LOG_RESCAN_INTERVAL
    if (!raidOnly || logsRoot = "")
        return
    if (!gameIsRunning) {
        CloseRaidLog()
        return
    }
    if (A_TickCount - lastLogScanTick > LOG_RESCAN_INTERVAL) {
        lastLogScanTick := A_TickCount
        latest := FindLatestLog(logsRoot)
        if (latest != "" && latest != logPath)
            OpenRaidLog(latest)
    }
    if (!logFile)
        return
    if (logFile.Pos >= logFile.Length)
        return
    ReadRaidLog()
}

OpenRaidLog(path) {
    global logFile, logPath, logPending
    stream := FileOpen(path, "r", "UTF-8")
    if (!IsObject(stream))
        return
    CloseRaidLog()
    logFile := stream
    logPath := path
    logPending := stream.Read()
    FlushRaidLog()
}

CloseRaidLog() {
    global logFile, logPath, logPending, raidIsActive
    if (logFile)
        logFile.Close()
    logFile := 0
    logPath := ""
    logPending := ""
    raidIsActive := false
}

ReadRaidLog() {
    global logFile, logPending
    logPending .= logFile.Read()
    FlushRaidLog()
}

FlushRaidLog() {
    global logPending
    lineBreak := InStr(logPending, "`n", , -1)
    if (!lineBreak)
        return
    ApplyRaidMarkers(SubStr(logPending, 1, lineBreak))
    logPending := SubStr(logPending, lineBreak + 1)
}

ApplyRaidMarkers(text) {
    global RAID_STARTED_MARKER, MENU_ENTERED_MARKER, raidIsActive
    for line in StrSplit(text, "`n", "`r") {
        if (InStr(line, RAID_STARTED_MARKER)) {
            raidIsActive := true
        }
        else if (InStr(line, MENU_ENTERED_MARKER)) {
            raidIsActive := false
        }
    }
}

FindLatestLog(root) {
    newestFolder := ""
    newestFolderTime := ""
    loop files root . "\*", "D" {
        if (newestFolderTime = "" || A_LoopFileTimeModified > newestFolderTime) {
            newestFolderTime := A_LoopFileTimeModified
            newestFolder := A_LoopFilePath
        }
    }
    if (newestFolder = "")
        return ""
    newestLog := ""
    newestLogTime := ""
    loop files newestFolder . "\*application_*.log" {
        if (newestLogTime = "" || A_LoopFileTimeModified > newestLogTime) {
            newestLogTime := A_LoopFileTimeModified
            newestLog := A_LoopFilePath
        }
    }
    return newestLog
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

EnsureProfileFile() {
    global PROFILE_FILE, DEFAULT_PROFILE_FILE
    if (FileExist(PROFILE_FILE) || !FileExist(DEFAULT_PROFILE_FILE))
        return
    FileCopy(DEFAULT_PROFILE_FILE, PROFILE_FILE)
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

LoadStartupProfile() {
    global PROFILE_FILE, SETTINGS_SECTION, profileNames
    stored := IniRead(PROFILE_FILE, SETTINGS_SECTION, "Startup", "")
    for name in profileNames {
        if (name = stored)
            return stored
    }
    return ""
}

LoadRaidOnly() {
    global PROFILE_FILE, SETTINGS_SECTION
    return IniRead(PROFILE_FILE, SETTINGS_SECTION, "RaidOnly", "1") != "0"
}

LoadLogsRoot() {
    global PROFILE_FILE, SETTINGS_SECTION
    configured := IniRead(PROFILE_FILE, SETTINGS_SECTION, "LogsRoot", "")
    if (configured != "")
        return DirExist(configured) ? configured : ""
    return FindInstalledLogsRoot()
}

FindInstalledLogsRoot() {
    uninstallKeys := ["HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
        , "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"]
    for uninstallKey in uninstallKeys {
        loop reg uninstallKey, "K" {
            entry := A_LoopRegKey . "\" . A_LoopRegName
            if (RegRead(entry, "DisplayName", "") != "Escape from Tarkov")
                continue
            logs := RegRead(entry, "InstallLocation", "") . "\Logs"
            if (DirExist(logs))
                return logs
        }
    }
    return ""
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
        Hotkey("^!" . A_Index, SelectProfileByIndex, A_Index <= profileNames.Length ? "On" : "Off")
    }
}

BuildTrayMenu() {
    global profileNames, activeProfile, automationIsEnabled, raidOnly, MAX_HOTKEY_PROFILES
    A_TrayMenu.Delete()
    for index, name in profileNames {
        label := name . (index <= MAX_HOTKEY_PROFILES ? "`tCtrl+Alt+" . index : "")
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
    A_TrayMenu.Add("Только в рейде", ToggleRaidOnly)
    A_TrayMenu.Add("Пауза`tCtrl+Alt+P", ToggleAutomation)
    A_TrayMenu.Add("Сбросить гамму сейчас", ResetAllMonitors)
    A_TrayMenu.Add("Выход", (*) => ExitApp())
    if (raidOnly)
        A_TrayMenu.Check("Только в рейде")
    if (!automationIsEnabled)
        A_TrayMenu.Check("Пауза`tCtrl+Alt+P")
}

ToggleRaidOnly(*) {
    global raidOnly, PROFILE_FILE, SETTINGS_SECTION
    raidOnly := !raidOnly
    IniWrite(raidOnly ? "1" : "0", PROFILE_FILE, SETTINGS_SECTION, "RaidOnly")
    A_TrayMenu.ToggleCheck("Только в рейде")
    if (!raidOnly)
        CloseRaidLog()
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
