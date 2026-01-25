#SingleInstance Force
#NoEnv
#UseHook
SetWorkingDir %A_ScriptDir%
SetBatchLines -1

global TimerRunning := false
global Minutes := 3
global Seconds := 0
global GuiVisible := false
global TimerDisplay, EndTimeDisplay
global AlarmPlaying := false
global TimerPaused := false
global AlarmGuiVisible := false
global AdjustingUp := false
global AdjustingDown := false
global Blinking := false
global BlinkState := false
global PauseBlink := false
global PauseBlinkState := false
global TimerX := 100
global TimerY := 100
global ConfigFile := A_ScriptDir . "\gui_state\timer_config.ini"
global SettingsFile := A_ScriptDir . "\settings\settings.txt"
global WindowsKeyHeld := false
global ShortcutExecuted := false  ; Track if shortcut was executed
global AdjustStartTime := 0
global AdjustSpeed := 200
global LastAdjustTime := 0
global LastSpeedTier := 0
global PreviousWindow := 0
global LastSetMinutes := 3  ; Track last manually set time
global Resetting := false

; Default settings (will be loaded from file)
global ToggleKey := "``"
global PauseKey := "Enter"
global UpKey := "Up"
global DownKey := "Down"
global ResetKey := "Backspace"
global AlarmVolume := 100
global AlarmMessage := "Beep, Beep turn it off nigga."

Menu, Tray, Icon, %A_ScriptDir%\icon\timebomb.ico

; Create directories if they don't exist
FileCreateDir, %A_ScriptDir%\gui_state
FileCreateDir, %A_ScriptDir%\settings
FileCreateDir, %A_ScriptDir%\icon
FileCreateDir, %A_ScriptDir%\sounds

LoadSettings()
LoadPosition()

~LWin::
~RWin::
; Only set WindowsKeyHeld if a shortcut was executed
if (ShortcutExecuted) {
    WindowsKeyHeld := true
}
return

~LWin Up::
~RWin Up::
WindowsKeyHeld := false
ShortcutExecuted := false  ; Reset the flag

; Only start timer when Win key is released AND conditions are met
if (GuiVisible && !TimerPaused && !AdjustingUp && !AdjustingDown && !Resetting) {
    TimerRunning := true
}

; Handle resetting state
if (Resetting) {
    Resetting := false
    ; Timer will start only if not paused and Win key released
    if (!TimerPaused) {
        TimerRunning := true
    }
}
return

CreateSettingsFile() {
    if !FileExist(SettingsFile) {
        FileAppend,
(
; Timer Settings Configuration
; Edit the values below to customize your timer

; KEYBOARD SHORTCUTS (use AutoHotkey key names)
; Available keys: a-z, 0-9, F1-F12, Enter, Space, Tab, Backspace, Delete, etc.
; Special keys: Up, Down, Left, Right, Home, End, PgUp, PgDn
; Note: All shortcuts use Win + [key]

ToggleKey=``
PauseKey=Enter  
UpKey=Up
DownKey=Down
ResetKey=Backspace

; ALARM SETTINGS
AlarmVolume=100
AlarmMessage=Beep, Beep turn it off nigga.

; INSTRUCTIONS:
; - Save this file after making changes
; - Restart the timer application to apply new settings
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
        else if (RegExMatch(A_LoopReadLine, "^AlarmVolume=(.+)$", Match))
            AlarmVolume := Match1
        else if (RegExMatch(A_LoopReadLine, "^AlarmMessage=(.+)$", Match))
            AlarmMessage := Match1
    }
    
    ; Set up hotkeys
    Hotkey, #%ToggleKey%, ToggleTimer
    Hotkey, #%PauseKey%, PauseTimer
    Hotkey, #%UpKey%, AdjustUp
    Hotkey, #%UpKey% Up, AdjustUpRelease
    Hotkey, #%DownKey%, AdjustDown
    Hotkey, #%DownKey% Up, AdjustDownRelease
    Hotkey, #%ResetKey%, ResetTimer
    return
}

ToggleTimer:
ShortcutExecuted := true  ; Mark that shortcut was executed
if (GuiVisible) {
    ; Clean shutdown - stop everything
    SavePosition()
    ClearLastSetTime()  ; Clear when manually closing
    
    ; Stop all timers
    SetTimer, UpdateTimer, Off
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
    TimerPaused := false
    PauseBlink := false
    Blinking := false
    WindowsKeyHeld := false
    AdjustingUp := false
    AdjustingDown := false
    Resetting := false
} else {
    ; Fresh start - reset everything to defaults
    Minutes := 3
    Seconds := 0
    LastSetMinutes := 3  ; Reset to default
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
}
return

PauseTimer:
ShortcutExecuted := true  ; Mark that shortcut was executed
if (GuiVisible && !AlarmPlaying) {
    if (TimerPaused) {
        TimerPaused := false
        PauseBlink := false
        SetTimer, PauseBlinkTimer, Off
        ; NEVER set TimerRunning = true here - only Win key release should do that
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
}
return

ResetTimer:
ShortcutExecuted := true  ; Mark that shortcut was executed
if (GuiVisible || AlarmPlaying) {  ; Allow reset even when alarm is playing
    
    ; Stop all timers and sounds first
    SetTimer, UpdateTimer, Off
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
    
    ; Reset all state variables
    Minutes := LastSetMinutes
    Seconds := 0
    TimerRunning := false
    TimerPaused := false
    PauseBlink := false
    Blinking := false
    WindowsKeyHeld := false
    AdjustingUp := false
    AdjustingDown := false
    Resetting := true  ; Set resetting flag
    
    ; Play reset sound
    SoundPlay, %A_ScriptDir%\sounds\reset.wav
    
    ; Create fresh GUI
    CreateTimerGui()
    GuiVisible := true
    
    ; Set up timer for updates
    SetTimer, UpdateTimer, 1000
    
    ; Update display with reset time
    UpdateDisplay()
}
return

LoadPosition() {
    IniRead, SavedX, %ConfigFile%, Position, X, 100
    IniRead, SavedY, %ConfigFile%, Position, Y, 100
    IniRead, SavedLastSetMinutes, %ConfigFile%, Timer, LastSetMinutes, 3
    
    if (SavedX >= 0 && SavedY >= 0 && SavedX <= A_ScreenWidth && SavedY <= A_ScreenHeight) {
        TimerX := SavedX
        TimerY := SavedY
    }
    
    LastSetMinutes := SavedLastSetMinutes
}

SavePosition() {
    if (GuiVisible) {
        WinGetPos, CurrentX, CurrentY, , , TimerOverlay
        if (CurrentX != "" && CurrentY != "") {
            IniWrite, %CurrentX%, %ConfigFile%, Position, X
            IniWrite, %CurrentY%, %ConfigFile%, Position, Y
            TimerX := CurrentX
            TimerY := CurrentY
        }
    }
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
    Gui, Add, Text, x5 y5 w120 h30 vTimerDisplay Center, % FormatTime(Minutes, Seconds)
    GuiControlGet, TimerPos, Pos, TimerDisplay
    centerX := (142 - TimerPosW) // 2
    GuiControl, Move, TimerDisplay, x%centerX%
    Gui, Font, s11 cA0FFA0 w700, Arial
    Gui, Add, Text, x5 y40 w170 h20 vEndTimeDisplay Center, % "Ends at: " GetEndTime(Minutes, Seconds)
    GuiControlGet, EndTimePos, Pos, EndTimeDisplay
    centerX := (140 - EndTimePosW) // 2
    GuiControl, Move, EndTimeDisplay, x%centerX%
    
    Gui, Show, x%TimerX% y%TimerY% w140 h60 NoActivate, TimerOverlay
    Gui, +LastFound
    WinSet, Transparent, 235
    OnMessage(0x201, "WM_LBUTTONDOWN")
    OnMessage(0x202, "WM_LBUTTONUP")
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
    return Format("{:02d}:{:02d}", min, sec)
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
if (TimerRunning && !TimerPaused && !WindowsKeyHeld && !Resetting && (Minutes > 0 || Seconds > 0)) {
    Seconds--
    if (Seconds < 0) {
        Minutes--
        Seconds := 59
    }
    if (Minutes = 0 && Seconds = 10 && !Blinking) {
        Blinking := true
        SetTimer, BlinkTimer, 500
    }
    GuiControl,, TimerDisplay, % FormatTime(Minutes, Seconds)
    GuiControl,, EndTimeDisplay, % "Ends at: " GetEndTime(Minutes, Seconds)
} else if (Minutes = 0 && Seconds = 0 && !TimerPaused && !WindowsKeyHeld && !Resetting && TimerRunning) {
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
    ; This ensures dynamic updating when Win key is held, paused, adjusting, etc.
    GuiControl,, EndTimeDisplay, % "Ends at: " GetEndTime(Minutes, Seconds)
}
return

PauseBlinkTimer:
if (PauseBlink) {
    PauseBlinkState := !PauseBlinkState
    if (PauseBlinkState) {
        Gui, Font, s24 c23FF23, DS-Digital Bold
    } else {
        Gui, Font, s24 c404045, DS-Digital Bold
    }
    GuiControl, Font, TimerDisplay
}
return

BlinkTimer:
if (Blinking && (Minutes = 0 && Seconds <= 10)) {
    BlinkState := !BlinkState
    color := BlinkState ? "cFF0000" : "c23FF23"
    Gui, Font, s24 %color%, DS-Digital Bold
    GuiControl, Font, TimerDisplay
} else if (Blinking && (Minutes > 0 || Seconds > 10)) {
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

ResetButtonPressed() {
    ; Stop all timers and sounds first
    SetTimer, LoopAlarm, Off
    SetTimer, UpdateTimer, Off
    SetTimer, BlinkTimer, Off
    SetTimer, PauseBlinkTimer, Off
    SetTimer, AcceleratedAdjustUp, Off
    SetTimer, AcceleratedAdjustDown, Off
    
    ; Stop alarm and close alarm GUI
    SoundPlay, *
    AlarmPlaying := false
    Gui, Alarm:Destroy
    AlarmGuiVisible := false
    
    ; Destroy existing main GUI if it exists
    if (GuiVisible) {
        Gui, 1:Destroy
        GuiVisible := false
    }
    
    ; Reset all state variables (NO Windows key tracking stuff)
    Minutes := LastSetMinutes
    Seconds := 0
    TimerRunning := true  ; Start immediately, no waiting for Win key
    TimerPaused := false
    PauseBlink := false
    Blinking := false
    WindowsKeyHeld := false
    AdjustingUp := false
    AdjustingDown := false
    Resetting := false  ; No resetting flag needed
    
    ; Play reset sound
    SoundPlay, %A_ScriptDir%\sounds\reset.wav
    
    ; Create fresh GUI
    CreateTimerGui()
    GuiVisible := true
    
    ; Start the timer immediately
    SetTimer, UpdateTimer, 1000
    
    ; Update display with reset time
    UpdateDisplay()
}

DelayedReset:
    ; This is no longer needed, remove this function
return

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
ShortcutExecuted := true  ; Mark that shortcut was executed
if (GuiVisible && !TimerPaused) {
    if (!AdjustingUp) {
        AdjustingUp := true
        TimerRunning := false
        AdjustStartTime := A_TickCount
        LastAdjustTime := A_TickCount
        LastSpeedTier := 0
        if (Minutes < 999) {
            Minutes++
            LastSetMinutes := Minutes  ; Track the adjusted time
            Seconds := 0
            SoundPlay, %A_ScriptDir%\sounds\adjust.wav, 1
            UpdateDisplay()
            ResetBlinkingIfNeeded()
            SaveLastSetTime()  ; Save to config
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
ShortcutExecuted := true  ; Mark that shortcut was executed
if (GuiVisible && !TimerPaused) {
    if (!AdjustingDown) {
        AdjustingDown := true
        TimerRunning := false
        AdjustStartTime := A_TickCount
        LastAdjustTime := A_TickCount
        LastSpeedTier := 0
        if (Minutes > 1) {
            Minutes--
            LastSetMinutes := Minutes  ; Track the adjusted time
            Seconds := 0
            SoundPlay, %A_ScriptDir%\sounds\adjust.wav, 1
            UpdateDisplay()
            ResetBlinkingIfNeeded()
            SaveLastSetTime()  ; Save to config
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

UpdateDisplay() {
    GuiControl,, TimerDisplay, % FormatTime(Minutes, Seconds)
    GuiControl,, EndTimeDisplay, % "Ends at: " GetEndTime(Minutes, Seconds)
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

AcceleratedAdjustUp:
if (!AdjustingUp || Minutes >= 999) {
    SetTimer, AcceleratedAdjustUp, Off
    return
}
HoldTime := (A_TickCount - AdjustStartTime) / 1000.0
AdjustDelay := GetAdjustDelay(HoldTime)

if (A_TickCount - LastAdjustTime >= AdjustDelay) {
    Minutes++
    LastSetMinutes := Minutes
    Seconds := 0
    LastAdjustTime := A_TickCount
    UpdateDisplay()
    ResetBlinkingIfNeeded()
    SaveLastSetTime()
}
return

AcceleratedAdjustDown:
if (!AdjustingDown || Minutes <= 1) {
    SetTimer, AcceleratedAdjustDown, Off
    return
}
HoldTime := (A_TickCount - AdjustStartTime) / 1000.0
AdjustDelay := GetAdjustDelay(HoldTime)

if (A_TickCount - LastAdjustTime >= AdjustDelay) {
    Minutes--
    LastSetMinutes := Minutes
    Seconds := 0
    LastAdjustTime := A_TickCount
    UpdateDisplay()
    ResetBlinkingIfNeeded()
    SaveLastSetTime()
}
return

ResetBlinkingIfNeeded() {
    if (Blinking && (Minutes > 0 || Seconds > 10)) {
        Blinking := false
        SetTimer, BlinkTimer, Off
        Gui, Font, s24 c23FF23, DS-Digital Bold
        GuiControl, Font, TimerDisplay
    }
}

GuiClose:
SavePosition()
ClearLastSetTime()  ; Clear when manually closing
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
return