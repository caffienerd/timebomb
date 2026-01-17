#SingleInstance Force
#NoEnv
#UseHook
SetWorkingDir %A_ScriptDir%
SetBatchLines -1

; Global variables for both applications
global AppMode := "timer" ; "timer" or "stopwatch"
global TimerRunning := false
global StopwatchRunning := false
global TimerMinutes := 3
global TimerSeconds := 0
global StopwatchMinutes := 0
global StopwatchSeconds := 0
global GuiVisible := false
global TimerDisplay, StopwatchDisplay, EndTimeDisplay, StartTimeDisplay
global AlarmPlaying := false
global TimerPaused := false
global StopwatchPaused := false
global AlarmGuiVisible := false
global AdjustingUp := false
global AdjustingDown := false
global Blinking := false
global BlinkState := false
global PauseBlink := false
global PauseBlinkState := false
global TimerX := 100
global TimerY := 100
global StopwatchX := 300
global StopwatchY := 100
global ConfigFile := A_ScriptDir . "\gui_state\timebomb_config.ini"
global SettingsFile := A_ScriptDir . "\settings\settings.txt"
global WindowsKeyHeld := false
global ShortcutExecuted := false
global AdjustStartTime := 0
global AdjustSpeed := 200
global LastAdjustTime := 0
global LastSpeedTier := 0
global PreviousWindow := 0
global LastSetMinutes := 3
global Resetting := false
global LastTickTime := 0
global StartTime := ""

; Default settings
global ToggleKey := "``"
global PauseKey := "Enter"
global UpKey := "Up"
global DownKey := "Down"
global ResetKey := "Backspace"
global ModeSwitchKey := "esc"
global AlarmVolume := 100
global AlarmMessage := "Beep, Beep turn it off."

Menu, Tray, Icon, %A_ScriptDir%\icon\timebomb.ico

; Create directories if they don't exist
FileCreateDir, %A_ScriptDir%\gui_state
FileCreateDir, %A_ScriptDir%\settings
FileCreateDir, %A_ScriptDir%\icon
FileCreateDir, %A_ScriptDir%\sounds
FileCreateDir, %A_ScriptDir%\logs

LoadSettings()
LoadPosition()

~LWin::
~RWin::
; Only set WindowsKeyHeld if a shortcut was executed
if (ShortcutExecuted) {
    WindowsKeyHeld := true
    ; Stop stopwatch timer when Windows key is held
    if (GuiVisible && AppMode = "stopwatch" && StopwatchRunning && !StopwatchPaused) {
        SetTimer, UpdateStopwatch, Off
    }
}
return

~LWin Up::
~RWin Up::
WindowsKeyHeld := false
ShortcutExecuted := false

; Handle timer start when Win key is released
if (GuiVisible && AppMode = "timer" && !TimerPaused && !AdjustingUp && !AdjustingDown && !Resetting) {
    TimerRunning := true
}

; Handle stopwatch start when Win key is released
if (GuiVisible && AppMode = "stopwatch" && !StopwatchPaused && !Resetting) {
    StopwatchRunning := true
    ; Reset LastTickTime and restart timer when Windows key is released
    LastTickTime := A_TickCount
    SetTimer, UpdateStopwatch, 10
}

; Handle resetting state
if (Resetting) {
    Resetting := false
    if (AppMode = "timer" && !TimerPaused) {
        TimerRunning := true
    }
    if (AppMode = "stopwatch" && !StopwatchPaused) {
        StopwatchRunning := true
    }
}
return

CreateSettingsFile() {
    if !FileExist(SettingsFile) {
        FileAppend,
(
; TimeBomb Settings Configuration
; Edit the values below to customize your timer/stopwatch

; KEYBOARD SHORTCUTS (use AutoHotkey key names)
; Available keys: a-z, 0-9, F1-F12, Enter, Space, Tab, Backspace, Delete, etc.
; Special keys: Up, Down, Left, Right, Home, End, PgUp, PgDn
; Note: All shortcuts use Win + [key]

ToggleKey=``
PauseKey=Enter  
UpKey=Up
DownKey=Down
ResetKey=Backspace
ModeSwitchKey=Z

; ALARM SETTINGS
AlarmVolume=100
AlarmMessage=Beep, Beep turn it off.

; INSTRUCTIONS:
; - Save this file after making changes
; - Restart the application to apply new settings
; - Use AutoHotkey key names for shortcuts
; - Volume range: 0-100
; - Keep message under 50 characters for best display
), %SettingsFile%
    }
}

LoadSettings() {
    CreateSettingsFile()
    
    ; Read settings from file
    Loop, Read, %SettingsFile%
    {
        if (RegExMatch(A_LoopReadLine, "^ToggleKey=(.+)$", Match))
            ToggleKey := Match1
        else if (RegExMatch(A_LoopReadLine, "^PauseKey=(.+)$", Match))
            PauseKey := Match1
        else if (RegExMatch(A_LoopReadLine, "^UpKey=(.+)$", Match))
            UpKey := Match1
        else if (RegExMatch(A_LoopReadLine, "^DownKey=(.+)$", Match))
            DownKey := Match1
        else if (RegExMatch(A_LoopReadLine, "^ResetKey=(.+)$", Match))
            ResetKey := Match1
        else if (RegExMatch(A_LoopReadLine, "^ModeSwitchKey=(.+)$", Match))
            ModeSwitchKey := Match1
        else if (RegExMatch(A_LoopReadLine, "^AlarmVolume=(.+)$", Match))
            AlarmVolume := Match1
        else if (RegExMatch(A_LoopReadLine, "^AlarmMessage=(.+)$", Match))
            AlarmMessage := Match1
    }
    
    ; Set up hotkeys
    Hotkey, #%ToggleKey%, ToggleApp
    Hotkey, #%PauseKey%, PauseApp
    Hotkey, #%UpKey%, AdjustUp
    Hotkey, #%UpKey% Up, AdjustUpRelease
    Hotkey, #%DownKey%, AdjustDown
    Hotkey, #%DownKey% Up, AdjustDownRelease
    Hotkey, #%ResetKey%, ResetApp
    Hotkey, #%ModeSwitchKey%, SwitchMode
    return
}

SwitchMode:
ShortcutExecuted := true

; If GUI is not visible, just switch mode internally
if (!GuiVisible) {
    if (AppMode = "timer") {
        AppMode := "stopwatch"
        SoundPlay, %A_ScriptDir%\sounds\switch_stopwatch.wav
    } else {
        AppMode := "timer"
        SoundPlay, %A_ScriptDir%\sounds\switch_timer.wav
    }
    SavePosition()
    return
}

; Save current state if GUI is visible
SavePosition()

; Stop all timers
SetTimer, UpdateTimer, Off
SetTimer, UpdateStopwatch, Off
SetTimer, BlinkTimer, Off
SetTimer, PauseBlinkTimer, Off
SetTimer, AcceleratedAdjustUp, Off
SetTimer, AcceleratedAdjustDown, Off

; Stop alarm if playing
if (AlarmPlaying) {
    SetTimer, LoopAlarm, Off
    SoundPlay, *
    AlarmPlaying := false
    if (AlarmGuiVisible) {
        Gui, Alarm:Destroy
        AlarmGuiVisible := false
    }
}

; Destroy GUI
Gui, 1:Destroy
GuiVisible := false

; Switch mode and play appropriate sound
if (AppMode = "timer") {
    AppMode := "stopwatch"
    SoundPlay, %A_ScriptDir%\sounds\switch_stopwatch.wav
} else {
    AppMode := "timer"
    SoundPlay, %A_ScriptDir%\sounds\switch_timer.wav
}

; Reset states for new mode
TimerRunning := false
StopwatchRunning := false
TimerPaused := false
StopwatchPaused := false
PauseBlink := false
Blinking := false
WindowsKeyHeld := false
AdjustingUp := false
AdjustingDown := false
Resetting := false

; Initialize fresh state based on new mode
if (AppMode = "timer") {
    TimerMinutes := 3
    TimerSeconds := 0
    LastSetMinutes := 3
    CreateTimerGui()
    GuiVisible := true
    TimerRunning := true
    SetTimer, UpdateTimer, 1000
} else {
    StopwatchMinutes := 0
    StopwatchSeconds := 0
    LastTickTime := 0
    StartTime := GetCurrentTime()
    CreateStopwatchGui()
    GuiVisible := true
    StopwatchRunning := true
    SetTimer, UpdateStopwatch, 10
}
return

ToggleApp:
ShortcutExecuted := true
if (GuiVisible) {
    ; Clean shutdown - stop everything
    SavePosition()
    
    ; Stop all timers
    SetTimer, UpdateTimer, Off
    SetTimer, UpdateStopwatch, Off
    SetTimer, BlinkTimer, Off
    SetTimer, PauseBlinkTimer, Off
    SetTimer, AcceleratedAdjustUp, Off
    SetTimer, AcceleratedAdjustDown, Off
    
    ; Stop alarm if playing
    if (AlarmPlaying) {
        SetTimer, LoopAlarm, Off
        SoundPlay, *
        AlarmPlaying := false
        if (AlarmGuiVisible) {
            Gui, Alarm:Destroy
            AlarmGuiVisible := false
        }
    }
    
    ; Destroy GUI and reset state
    Gui, 1:Destroy
    GuiVisible := false
    TimerRunning := false
    StopwatchRunning := false
    TimerPaused := false
    StopwatchPaused := false
    PauseBlink := false
    Blinking := false
    WindowsKeyHeld := false
    AdjustingUp := false
    AdjustingDown := false
    Resetting := false
} else {
    ; Fresh start
    if (AppMode = "timer") {
        TimerMinutes := 3
        TimerSeconds := 0
        LastSetMinutes := 3
        TimerRunning := false
        TimerPaused := false
        PauseBlink := false
        Blinking := false
        WindowsKeyHeld := false
        AdjustingUp := false
        AdjustingDown := false
        Resetting := false
        
        SoundPlay, %A_ScriptDir%\sounds\start.wav
        CreateTimerGui()
        GuiVisible := true
        TimerRunning := true
        SetTimer, UpdateTimer, 1000
    } else {
        StopwatchMinutes := 0
        StopwatchSeconds := 0
        LastTickTime := A_TickCount
        StartTime := GetCurrentTime()
        StopwatchRunning := false
        StopwatchPaused := false
        PauseBlink := false
        WindowsKeyHeld := false
        Resetting := false
        
        SoundPlay, %A_ScriptDir%\sounds\start.wav
        CreateStopwatchGui()
        GuiVisible := true
        StopwatchRunning := true
        SetTimer, UpdateStopwatch, 10
    }
}
return

PauseApp:
ShortcutExecuted := true
if (GuiVisible) {
    if (AppMode = "timer" && !AlarmPlaying) {
        if (TimerPaused) {
            TimerPaused := false
            PauseBlink := false
            SetTimer, PauseBlinkTimer, Off
            Gui, Font, s24 c23FF23, DS-Digital Bold
            GuiControl, Font, TimerDisplay
            SoundPlay, %A_ScriptDir%\sounds\play.wav, 1
        } else {
            TimerPaused := true
            TimerRunning := false
            PauseBlink := true
            PauseBlinkState := false
            SetTimer, PauseBlinkTimer, 450
            SoundPlay, %A_ScriptDir%\sounds\pause.wav, 1
        }
    } else if (AppMode = "stopwatch") {
        if (StopwatchPaused) {
            StopwatchPaused := false
            PauseBlink := false
            SetTimer, PauseBlinkTimer, Off
            UpdateDisplayColors(true)
            ; Reset LastTickTime when resuming so we don't count paused time
            LastTickTime := A_TickCount
            SetTimer, UpdateStopwatch, 10
            SoundPlay, %A_ScriptDir%\sounds\play.wav, 1
        } else {
            StopwatchPaused := true
            StopwatchRunning := false
            ; STOP the timer completely when paused
            SetTimer, UpdateStopwatch, Off
            PauseBlink := true
            PauseBlinkState := false
            SetTimer, PauseBlinkTimer, 450
            SoundPlay, %A_ScriptDir%\sounds\pause.wav, 1
        }
    }
}
return

ResetApp:
ShortcutExecuted := true
if (GuiVisible || AlarmPlaying) {
    ; Stop all timers and sounds first
    SetTimer, UpdateTimer, Off
    SetTimer, UpdateStopwatch, Off
    SetTimer, BlinkTimer, Off
    SetTimer, PauseBlinkTimer, Off
    SetTimer, AcceleratedAdjustUp, Off
    SetTimer, AcceleratedAdjustDown, Off
    
    ; If alarm is playing, stop it
    if (AlarmPlaying) {
        SetTimer, LoopAlarm, Off
        SoundPlay, *
        AlarmPlaying := false
        if (AlarmGuiVisible) {
            Gui, Alarm:Destroy
            AlarmGuiVisible := false
        }
    }
    
    ; Destroy existing main GUI
    if (GuiVisible) {
        Gui, 1:Destroy
        GuiVisible := false
    }
    
    ; Reset state based on mode
    if (AppMode = "timer") {
        TimerMinutes := LastSetMinutes
        TimerSeconds := 0
        TimerRunning := false
        TimerPaused := false
        PauseBlink := false
        Blinking := false
        WindowsKeyHeld := false
        AdjustingUp := false
        AdjustingDown := false
        Resetting := true
    } else {
        StopwatchMinutes := 0
        StopwatchSeconds := 0
        LastTickTime := A_TickCount
        StartTime := GetCurrentTime()
        StopwatchRunning := false
        StopwatchPaused := false
        PauseBlink := false
        WindowsKeyHeld := false
        Resetting := true
    }
    
    ; Play reset sound
    SoundPlay, %A_ScriptDir%\sounds\reset.wav
    
    ; Create fresh GUI
    if (AppMode = "timer") {
        CreateTimerGui()
        SetTimer, UpdateTimer, 1000
    } else {
        CreateStopwatchGui()
        SetTimer, UpdateStopwatch, 10
    }
    GuiVisible := true
    
    ; Update display
    if (AppMode = "timer") {
        UpdateTimerDisplay()
    } else {
        UpdateStopwatchDisplay()
    }
}
return

LoadPosition() {
    IniRead, SavedTimerX, %ConfigFile%, TimerPosition, X, 100
    IniRead, SavedTimerY, %ConfigFile%, TimerPosition, Y, 100
    IniRead, SavedStopwatchX, %ConfigFile%, StopwatchPosition, X, 300
    IniRead, SavedStopwatchY, %ConfigFile%, StopwatchPosition, Y, 100
    IniRead, SavedLastSetMinutes, %ConfigFile%, Timer, LastSetMinutes, 3
    IniRead, SavedAppMode, %ConfigFile%, General, Mode, timer
    
    if (SavedTimerX >= 0 && SavedTimerY >= 0 && SavedTimerX <= A_ScreenWidth && SavedTimerY <= A_ScreenHeight) {
        TimerX := SavedTimerX
        TimerY := SavedTimerY
    }
    
    if (SavedStopwatchX >= 0 && SavedStopwatchY >= 0 && SavedStopwatchX <= A_ScreenWidth && SavedStopwatchY <= A_ScreenHeight) {
        StopwatchX := SavedStopwatchX
        StopwatchY := SavedStopwatchY
    }
    
    LastSetMinutes := SavedLastSetMinutes
    AppMode := SavedAppMode
}

SavePosition() {
    if (GuiVisible) {
        if (AppMode = "timer") {
            WinGetPos, CurrentX, CurrentY, , , TimerOverlay
            if (CurrentX != "" && CurrentY != "") {
                IniWrite, %CurrentX%, %ConfigFile%, TimerPosition, X
                IniWrite, %CurrentY%, %ConfigFile%, TimerPosition, Y
                TimerX := CurrentX
                TimerY := CurrentY
            }
        } else {
            WinGetPos, CurrentX, CurrentY, , , StopwatchOverlay
            if (CurrentX != "" && CurrentY != "") {
                IniWrite, %CurrentX%, %ConfigFile%, StopwatchPosition, X
                IniWrite, %CurrentY%, %ConfigFile%, StopwatchPosition, Y
                StopwatchX := CurrentX
                StopwatchY := CurrentY
            }
        }
    }
    IniWrite, %LastSetMinutes%, %ConfigFile%, Timer, LastSetMinutes
    IniWrite, %AppMode%, %ConfigFile%, General, Mode
}

SaveLastSetTime() {
    IniWrite, %LastSetMinutes%, %ConfigFile%, Timer, LastSetMinutes
}

ClearLastSetTime() {
    IniDelete, %ConfigFile%, Timer, LastSetMinutes
    LastSetMinutes := 3
}

CreateTimerGui() {
    Gui, +AlwaysOnTop +ToolWindow -Caption +Border +E0x08000000 +E0x00000080
    Gui, Color, 404045
    Gui, Font, s24 c23FF23, DS-Digital Bold
    Gui, Add, Text, x5 y5 w120 h30 vTimerDisplay Center, % FormatTime(TimerMinutes, TimerSeconds)
    GuiControlGet, TimerPos, Pos, TimerDisplay
    centerX := (142 - TimerPosW) // 2
    GuiControl, Move, TimerDisplay, x%centerX%
    Gui, Font, s11 cA0FFA0 w700, Arial
    Gui, Add, Text, x5 y40 w170 h20 vEndTimeDisplay Center, % "Ends at: " GetEndTime(TimerMinutes, TimerSeconds)
    GuiControlGet, EndTimePos, Pos, EndTimeDisplay
    centerX := (140 - EndTimePosW) // 2
    GuiControl, Move, EndTimeDisplay, x%centerX%
    
    Gui, Show, x%TimerX% y%TimerY% w140 h60 NoActivate, TimerOverlay
    Gui, +LastFound
    WinSet, Transparent, 235
    OnMessage(0x201, "WM_LBUTTONDOWN")
    OnMessage(0x202, "WM_LBUTTONUP")
}

CreateStopwatchGui() {
    Gui, +AlwaysOnTop +ToolWindow -Caption +Border +E0x08000000 +E0x00000080
    Gui, Color, 404045
    
    ; Match timer GUI dimensions
    guiWidth := 140
    guiHeight := 60
    
    ; Time string only (no milliseconds)
    timeText := FormatTime(StopwatchMinutes, StopwatchSeconds)

    ; === Main Time (HH:MM:SS) - Centered like timer ===
    Gui, Font, s24 c23FF23, DS-Digital Bold
    Gui, Add, Text, x5 y5 w130 h30 vStopwatchDisplay Center, %timeText%
    
    ; Center it properly like the timer
    GuiControlGet, StopwatchPos, Pos, StopwatchDisplay
    centerX := (guiWidth - StopwatchPosW) // 2
    GuiControl, Move, StopwatchDisplay, x%centerX%

    ; Start time display (always centered under)
    Gui, Font, s11 cA0FFA0 w700, Arial
    FormatTime, currentTime, , HH:mm:ss
    startTimeText := "Started: " . currentTime
    Gui, Add, Text, x0 y40 w%guiWidth% h20 vStartTimeDisplay Center, %startTimeText%
    
    ; Show GUI
    Gui, Show, x%StopwatchX% y%StopwatchY% w%guiWidth% h%guiHeight% NoActivate, StopwatchOverlay
    
    Gui, +LastFound
    WinSet, Transparent, 235
    OnMessage(0x201, "WM_LBUTTONDOWN")
    OnMessage(0x202, "WM_LBUTTONUP")
}

CenterStopwatchControls() {
    guiWidth := 140
    
    ; Get actual sizes of the controls after they're rendered
    GuiControlGet, stopwatchPos, Pos, StopwatchDisplay
    GuiControlGet, msPos, Pos, MillisecondsDisplay
    
    ; Calculate total width including gap between controls
    gap := 1  ; Small gap between main time and milliseconds
    totalWidth := stopwatchPosW + gap + msPosW
    
    ; Calculate starting X position to center the entire group
    startX := (guiWidth - totalWidth) // 2
    
    ; Position main time display
    GuiControl, Move, StopwatchDisplay, x%startX% y5
    
    ; Position milliseconds display right next to main time, aligned with baseline
    msX := startX + stopwatchPosW + gap
    msY := 5 + 7  ; Offset down slightly to align with baseline of main text
    GuiControl, Move, MillisecondsDisplay, x%msX% y%msY%
}

UpdateStopwatchDisplay() {
    ; Only update if GUI is visible to prevent flickering
    if (GuiVisible) {
        ; Update only the main time display (no milliseconds)
        GuiControl,, StopwatchDisplay, % FormatTime(StopwatchMinutes, StopwatchSeconds)
    }
}

UpdateStopwatchSecondsOnly() {
    ; Update only the main time display (no milliseconds)
    if (GuiVisible) {
        GuiControl,, StopwatchDisplay, % FormatTime(StopwatchMinutes, StopwatchSeconds)
    }
}

UpdateDisplayColors(visible) {
    if (visible) {
        GuiControl, Show, StopwatchDisplay
    } else {
        GuiControl, Hide, StopwatchDisplay
    }
}

CheckAndRecreateGui() {
    ; Check if we need to recreate GUI due to digit count change
    static lastDigitCount := 2  ; Start with 2 digits (01, 02, etc.)
    currentDigitCount := (StopwatchMinutes >= 100) ? 3 : 2  ; Either 2 digits (01-99) or 3 digits (100+)
    
    if (currentDigitCount != lastDigitCount && GuiVisible) {
        ; Save position before destroying
        WinGetPos, currentX, currentY, , , StopwatchOverlay
        if (currentX != "" && currentY != "") {
            StopwatchX := currentX
            StopwatchY := currentY
        }
        
        ; Destroy and recreate with new layout
        Gui, 1:Destroy
        CreateStopwatchGui()
        lastDigitCount := currentDigitCount
    }
}


; Add this function anywhere in your script (I recommend after the CreateStopwatchGui function):

GetCurrentTime() {
    ; Get current time in HH:mm:ss format
    FormatTime, currentTime, , HH:mm:ss
    return currentTime
}

GetEndTime(addMins, addSecs) {
    EnvGet, TimeZoneKey, HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\TimeZoneInformation\TimeZoneKeyName
    if (TimeZoneKey != "India Standard Time") {
        UTCnow := A_NowUTC
        UTCnow += 5, Hours
        UTCnow += 30, Minutes
    } else {
        UTCnow := A_Now
    }
    UTCnow += %addMins%, Minutes
    UTCnow += %addSecs%, Seconds
    FormatTime, endTime, %UTCnow%, HH:mm:ss
    return endTime
}

FormatTime(min, sec) {
    if (min >= 100) {
        return Format("{:03d}:{:02d}", min, sec)  ; 3 digits with leading zeros: 100, 101, 102...
    } else {
        return Format("{:02d}:{:02d}", min, sec)  ; 2 digits with leading zeros: 01, 02, 03... 11, 12...
    }
}

GetAdjustDelay(holdTime) {
    if (holdTime < 0.35) {
        return 250
    } else if (holdTime < 0.9) {
        return 120
    } else if (holdTime < 1.5) {
        return 40
    } else if (holdTime < 2.0) {
        return 20
    } else {
        return 1
    }
}

UpdateTimer:
if (TimerRunning && !TimerPaused && !WindowsKeyHeld && !Resetting && (TimerMinutes > 0 || TimerSeconds > 0)) {
    TimerSeconds--
    if (TimerSeconds < 0) {
        TimerMinutes--
        TimerSeconds := 59
    }
    if (TimerMinutes = 0 && TimerSeconds = 10 && !Blinking) {
        Blinking := true
        SetTimer, BlinkTimer, 500
    }
    UpdateTimerDisplay()
} else if (TimerMinutes = 0 && TimerSeconds = 0 && !TimerPaused && !WindowsKeyHeld && !Resetting && TimerRunning) {
    TimerRunning := false
    SetTimer, UpdateTimer, Off
    SetTimer, BlinkTimer, Off
    Blinking := false
    Gui, Font, s24 cFF0000, DS-Digital Bold
    GuiControl, Font, TimerDisplay
    TimerPaused := true
    AlarmPlaying := true
    SetTimer, LoopAlarm, 1000
    SoundPlay, %A_ScriptDir%\sounds\alarm.wav
    CreateAlarmGui()
} else {
    ; ALWAYS update the "Ends at" display regardless of timer state
    GuiControl,, EndTimeDisplay, % "Ends at: " GetEndTime(TimerMinutes, TimerSeconds)
}
return

UpdateStopwatch:
if (StopwatchRunning && !StopwatchPaused && !WindowsKeyHeld && !Resetting) {
    ; Use system tick count for accurate timing
    currentTick := A_TickCount
    if (LastTickTime == 0) {
        LastTickTime := currentTick
    }
    
    ; Calculate elapsed milliseconds since last update
    elapsedMs := currentTick - LastTickTime
    if (elapsedMs >= 1000) {  ; Update every second
        LastTickTime := currentTick
        secondsToAdd := elapsedMs // 1000
        StopwatchSeconds += secondsToAdd
        
        if (StopwatchSeconds >= 60) {
            StopwatchMinutes += StopwatchSeconds // 60
            StopwatchSeconds := Mod(StopwatchSeconds, 60)
        }
        
        ; Check if we need to recreate GUI due to digit change
        CheckAndRecreateGui()
        
        ; Update display
        UpdateStopwatchSecondsOnly()
    }
}
return

PauseBlinkTimer:
if (PauseBlink) {
    PauseBlinkState := !PauseBlinkState
    if (AppMode = "timer") {
        if (PauseBlinkState) {
            Gui, Font, s24 c23FF23, DS-Digital Bold
        } else {
            Gui, Font, s24 c404045, DS-Digital Bold
        }
        GuiControl, Font, TimerDisplay
    } else {
        UpdateDisplayColors(PauseBlinkState)
    }
}
return

UpdateTimerDisplay() {
    GuiControl,, TimerDisplay, % FormatTime(TimerMinutes, TimerSeconds)
    GuiControl,, EndTimeDisplay, % "Ends at: " GetEndTime(TimerMinutes, TimerSeconds)
}



BlinkTimer:
if (Blinking && (TimerMinutes = 0 && TimerSeconds <= 10)) {
    BlinkState := !BlinkState
    color := BlinkState ? "cFF0000" : "c23FF23"
    Gui, Font, s24 %color%, DS-Digital Bold
    GuiControl, Font, TimerDisplay
} else if (Blinking && (TimerMinutes > 0 || TimerSeconds > 10)) {
    Blinking := false
    SetTimer, BlinkTimer, Off
    Gui, Font, s24 c23FF23, DS-Digital Bold
    GuiControl, Font, TimerDisplay
}
return

LoopAlarm:
if (AlarmPlaying) {
    SoundPlay, %A_ScriptDir%\sounds\alarm.wav
}
return

CreateAlarmGui() {
    Gui, Alarm:+AlwaysOnTop +ToolWindow -Caption +Border
    Gui, Alarm:Color, 404045
    Gui, Alarm:Font, s7 c23FF23, Press Start 2P
    Gui, Alarm:Add, Text, x10 y10 w290 h20 Center, %AlarmMessage%
    Gui, Alarm:Font, s7 cA0FFA0 bold
    Gui, Alarm:Add, Button, x110 y40 w90 h32 gStopAlarm, Done
    Gui, Alarm:Show, w310 h75, Clock Out
    Gui, Alarm:+LastFound
    WinSet, Transparent, 255
    OnMessage(0x201, "WM_LBUTTONDOWN_Alarm")
    AlarmGuiVisible := true
}

StopAlarm() {
    SetTimer, LoopAlarm, Off
    SoundPlay, *
    AlarmPlaying := false
    Gui, Alarm:Destroy
    AlarmGuiVisible := false
    
    ; Clear last set time when timer completes normally
    ClearLastSetTime()
    
    SavePosition()
    Gui, 1:Destroy
    GuiVisible := false
    TimerPaused := false
    PauseBlink := false
    Blinking := false
    WindowsKeyHeld := false
    AdjustingUp := false
    AdjustingDown := false
}

AdjustUp:
ShortcutExecuted := true
if (GuiVisible && AppMode = "timer" && !TimerPaused) {
    if (!AdjustingUp) {
        AdjustingUp := true
        TimerRunning := false
        AdjustStartTime := A_TickCount
        LastAdjustTime := A_TickCount
        LastSpeedTier := 0
        if (TimerMinutes < 999) {
            TimerMinutes++
            LastSetMinutes := TimerMinutes
            TimerSeconds := 0
            SoundPlay, %A_ScriptDir%\sounds\adjust.wav, 1
            UpdateTimerDisplay()
            ResetBlinkingIfNeeded()
            SaveLastSetTime()
        }
        SetTimer, AcceleratedAdjustUp, 50
    }
}
return

AdjustUpRelease:
if (AdjustingUp) {
    AdjustingUp := false
    SetTimer, AcceleratedAdjustUp, Off
}
return

AdjustDown:
ShortcutExecuted := true
if (GuiVisible && AppMode = "timer" && !TimerPaused) {
    if (!AdjustingDown) {
        AdjustingDown := true
        TimerRunning := false
        AdjustStartTime := A_TickCount
        LastAdjustTime := A_TickCount
        LastSpeedTier := 0
        if (TimerMinutes > 1) {
            TimerMinutes--
            LastSetMinutes := TimerMinutes
            TimerSeconds := 0
            SoundPlay, %A_ScriptDir%\sounds\adjust.wav, 1
            UpdateTimerDisplay()
            ResetBlinkingIfNeeded()
            SaveLastSetTime()
        }
        SetTimer, AcceleratedAdjustDown, 50
    }
}
return

AdjustDownRelease:
if (AdjustingDown) {
    AdjustingDown := false
    SetTimer, AcceleratedAdjustDown, Off
}
return

AcceleratedAdjustUp:
if (!AdjustingUp || TimerMinutes >= 999) {
    SetTimer, AcceleratedAdjustUp, Off
    return
}
HoldTime := (A_TickCount - AdjustStartTime) / 1000.0
AdjustDelay := GetAdjustDelay(HoldTime)

if (A_TickCount - LastAdjustTime >= AdjustDelay) {
    TimerMinutes++
    LastSetMinutes := TimerMinutes
    TimerSeconds := 0
    LastAdjustTime := A_TickCount
    UpdateTimerDisplay()
    ResetBlinkingIfNeeded()
    SaveLastSetTime()
}
return

AcceleratedAdjustDown:
if (!AdjustingDown || TimerMinutes <= 1) {
    SetTimer, AcceleratedAdjustDown, Off
    return
}
HoldTime := (A_TickCount - AdjustStartTime) / 1000.0
AdjustDelay := GetAdjustDelay(HoldTime)

if (A_TickCount - LastAdjustTime >= AdjustDelay) {
    TimerMinutes--
    LastSetMinutes := TimerMinutes
    TimerSeconds := 0
    LastAdjustTime := A_TickCount
    UpdateTimerDisplay()
    ResetBlinkingIfNeeded()
    SaveLastSetTime()
}
return

ResetBlinkingIfNeeded() {
    if (Blinking && (TimerMinutes > 0 || TimerSeconds > 10)) {
        Blinking := false
        SetTimer, BlinkTimer, Off
        Gui, Font, s24 c23FF23, DS-Digital Bold
        GuiControl, Font, TimerDisplay
    }
}

WM_LBUTTONDOWN() {
    PostMessage, 0xA1, 2
}

WM_LBUTTONUP() {
    Sleep, 50
    SavePosition()
}

WM_LBUTTONDOWN_Alarm() {
    PostMessage, 0xA1, 2, , , Alarm
}

GuiClose:
SavePosition()
if (AppMode = "timer") {
    ClearLastSetTime()  ; Clear when manually closing
}
if (AlarmGuiVisible) {
    SetTimer, LoopAlarm, Off
    SoundPlay, *
    AlarmPlaying := false
    Gui, Alarm:Destroy
    AlarmGuiVisible := false
}
SetTimer, AcceleratedAdjustUp, Off
SetTimer, AcceleratedAdjustDown, Off
Gui, 1:Destroy
GuiVisible := false
WindowsKeyHeld := false
AdjustingUp := false
AdjustingDown := false
SavePosition()
return
