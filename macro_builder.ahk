; =================================================================
; MacroBuilder (MB)
; AutoHotkey v2.0 - 多群組畫面顏色偵測與點擊、按鍵與等待巨集編輯與執行器
; 懸浮齒輪 UI、獨立執行圖示、GDI 雙層進度條、拉桿控制
; =================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
SendMode("Input")
SetKeyDelay(-1, -1)
SetMouseDelay(-1)
SetWinDelay(-1)
SetControlDelay(-1)

; === 系統管理員權限提升與容錯備援 ===
if !A_IsAdmin {
    try {
        if !A_IsCompiled
            Run '*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"'
        else
            Run '*RunAs "' A_ScriptFullPath '"'
        ExitApp()
    } catch {
        ; 若系統停用 UAC 或權限提升失敗，降級為普通權限繼續執行
    }
}

; === 禁用 Win11 邊緣手勢干擾 ===
DisableWin11EdgeActions() {
    try RegWrite(0, "REG_DWORD", "HKCU\Software\Policies\Microsoft\Windows\EdgeUI", "AllowEdgeSwipe")
    try RegWrite(0, "REG_DWORD", "HKLM\SOFTWARE\Policies\Microsoft\Windows\EdgeUI", "AllowEdgeSwipe")
    try RegWrite("0", "REG_SZ", "HKCU\Control Panel\Desktop", "DockMoving")
    try RegWrite(0, "REG_DWORD", "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced", "EnableSnapAssist")
}
DisableWin11EdgeActions()

#w::return
#n::return
#a::return
#z::return

; =================================================================
; [全域變數與資料結構]
; =================================================================
global MacroGroups := []         ; 巨集群組陣列
global RunningGroupIdx := 0      ; 當前執行中群組索引 (0 為無執行)
global ActiveEditGroupIdx := 1   ; 編輯器中當前選取的群組索引
global StopMacroRequested := false

global ConfigFile := A_ScriptDir . "\macro_config.ini"

; 主懸浮 UI 變數
global MyGui := ""
global IsAlwaysOnTop := true
global GuiX := 0, GuiY := 0, GuiH := 34, GuiOpacity := 240
global ProgressBarWidth := 500
global ProgressPic := ""
global hCurrentProgressBmp := 0
global GearBtn := "", ExitBtn := ""
global GroupBtns := []          ; 動態群組執行按鈕控制項陣列

; 編輯器 UI 變數
global MacroEditGui := ""
global DDLGroupSelect := ""
global MacroLV := ""
global LoopCountSlider := "", LoopCountLabel := ""

; 單一編輯視窗唯一性鎖定變數
global ActiveBoxGuiHwnd := 0
global ActiveColorEditCtrlDlg := ""
global ActiveStepEditDlg := ""

; 豐富彩色 Unicode 圖示清單
global IconPresets := [
    "⚔️", "⚡️", "🚗", "🎖️", "🏆",
    "🎰", "⚙️", "🎯", "🛡️", "🔥",
    "💎", "⭐", "🚀", "👑", "🎮",
    "🔑", "🛠️", "🧭", "🍀", "⏱️"
]

; 按鍵分類字典
global KeyCategories := Map(
    "🔤 字母鍵 (A - Z)", [
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J",
        "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T",
        "U", "V", "W", "X", "Y", "Z"
    ],
    "🔢 數字鍵 (0 - 9 & 數字盤)", [
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "Numpad0", "Numpad1", "Numpad2", "Numpad3", "Numpad4",
        "Numpad5", "Numpad6", "Numpad7", "Numpad8", "Numpad9",
        "NumpadDot", "NumpadEnter", "NumpadAdd", "NumpadSub", "NumpadMult", "NumpadDiv"
    ],
    "⚙️ 功能鍵 (控制/導航/F鍵/修飾)", [
        "Space", "Enter", "Escape", "Tab", "Backspace", "Delete",
        "Up", "Down", "Left", "Right", "Home", "End", "PgUp", "PgDn",
        "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
        "Shift", "Ctrl", "Alt", "LWin", "RWin", "CapsLock", "PrintScreen", "Insert"
    ]
)

; 輔助安全擷取 6 碼 HEX 色碼
GetFirstHexColor(str) {
    if RegExMatch(str, "i)(?:0x)?([0-9a-f]{6})", &m)
        return m[1]
    return "00FFFF"
}

; =================================================================
; [通用時間階梯與格式化 (毫秒 ➔ 秒 ➔ 分 ➔ 時)]
; - 按住時間拉桿 / 等待拉桿 / 逾時拉桿：最久 10 分鐘 (0~900ms 毫秒微調，1秒~10分 每格 1 秒)
; - 完成延遲拉桿：最久 1 分鐘 (0~900ms 毫秒微調，1秒~60秒 每格 1 秒)
; =================================================================
InitHoldTimeStepTable() {
    tbl := []
    for ms in [0, 20, 40, 60, 80, 100, 150, 200, 250, 300, 350, 400, 450, 500, 600, 700, 800, 900]
        tbl.Push(ms)
    sec := 1
    while (sec <= 600) { ; 600 秒 = 10 分鐘
        tbl.Push(sec * 1000)
        sec++
    }
    return tbl
}

InitDelayTimeStepTable() {
    tbl := []
    for ms in [0, 20, 40, 60, 80, 100, 150, 200, 250, 300, 350, 400, 450, 500, 600, 700, 800, 900]
        tbl.Push(ms)
    sec := 1
    while (sec <= 60) { ; 60 秒 = 1 分鐘
        tbl.Push(sec * 1000)
        sec++
    }
    return tbl
}

global HoldTimeTable := InitHoldTimeStepTable()
global DelayTimeTable := InitDelayTimeStepTable()
global TimeStepTable := HoldTimeTable

FormatDurationText(ms) {
    if (ms <= 0)
        return "0毫秒"
    if (ms < 1000)
        return Format("{}毫秒", ms)
    if (ms < 60000) {
        remMs := Mod(ms, 1000)
        if (remMs == 0)
            return Format("{}秒", ms // 1000)
        else
            return Format("{:.1f}秒", ms / 1000)
    }
    if (ms < 3600000) {
        min := ms // 60000
        remMs := ms - min * 60000
        remSec := remMs // 1000
        extraMs := Mod(remMs, 1000)
        
        if (remSec == 0 && extraMs == 0)
            return Format("{}分", min)
        else if (extraMs == 0)
            return Format("{}分{}秒", min, remSec)
        else
            return Format("{}分{:.1f}秒", min, remMs / 1000)
    }
    hr := ms // 3600000
    remMs := ms - hr * 3600000
    min := remMs // 60000
    remSec := (remMs - min * 60000) // 1000
    
    if (min == 0 && remSec == 0)
        return Format("{}小時", hr)
    else if (remSec == 0)
        return Format("{}小時{}分", hr, min)
    else
        return Format("{}小時{}分{}秒", hr, min, remSec)
}

MsToTimeStep(ms, tbl := "") {
    global TimeStepTable
    targetTbl := (tbl != "") ? tbl : TimeStepTable
    bestIdx := 1
    minDiff := Abs(targetTbl[1] - ms)
    for idx, val in targetTbl {
        diff := Abs(val - ms)
        if (diff < minDiff) {
            minDiff := diff
            bestIdx := idx
        }
    }
    return bestIdx
}

TimeStepToMs(stepIdx, tbl := "") {
    global TimeStepTable
    targetTbl := (tbl != "") ? tbl : TimeStepTable
    if (stepIdx < 1)
        return targetTbl[1]
    if (stepIdx > targetTbl.Length)
        return targetTbl[targetTbl.Length]
    return targetTbl[stepIdx]
}

; =================================================================
; [WM_LBUTTONDOWN 懸浮列拖曳與拉桿精確等比例點選/滑動控制]
; =================================================================
OnWM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    global ActiveBoxGuiHwnd, MyGui
    if (ActiveBoxGuiHwnd && hwnd == ActiveBoxGuiHwnd) {
        PostMessage(0xA1, 2, 0, hwnd)
        return 0
    } else if (MyGui != "" && hwnd == MyGui.Hwnd) {
        PostMessage(0xA1, 2, 0, hwnd)
        return 0
    }
    
    try {
        cls := WinGetClass(hwnd)
    } catch {
        cls := ""
    }
    if (cls == "msctls_trackbar32") {
        ctrlObj := GuiCtrlFromHwnd(hwnd)
        if (ctrlObj) {
            guiHwnd := ctrlObj.Gui.Hwnd
            CoordMode("Mouse", "Screen")
            MouseGetPos(&mX, &mY)
            
            ; 透過 ScreenToClient 取得控制項自身的精確像素座標
            pt := Buffer(8, 0)
            NumPut("int", mX, pt, 0), NumPut("int", mY, pt, 4)
            DllCall("user32\ScreenToClient", "Ptr", hwnd, "Ptr", pt)
            relativeX := NumGet(pt, 0, "Int")
            currVal := ctrlObj.Value
            
            ; 取得控制點的精確像素範圍 (TBM_GETTHUMBRECT = 0x0419)
            thumbRect := Buffer(16, 0)
            SendMessage(0x0419, 0, thumbRect, hwnd)
            tLeft := NumGet(thumbRect, 0, "Int")
            tRight := NumGet(thumbRect, 8, "Int")
            
            ; 1. 若點在控制點本體 (Thumb) 上，交由系統原生拖曳處理 (無任何跳躍)
            if (relativeX >= tLeft && relativeX <= tRight) {
                return
            }
            
            ; 取得軌道精確像素範圍 (TBM_GETCHANNELRECT = 0x041A)
            chanRect := Buffer(16, 0)
            SendMessage(0x041A, 0, chanRect, hwnd)
            cLeft := NumGet(chanRect, 0, "Int")
            cRight := NumGet(chanRect, 8, "Int")
            channelWidth := cRight - cLeft
            
            if (channelWidth > 0) {
                minVal := SendMessage(0x0401, 0, 0, hwnd)
                maxVal := SendMessage(0x0402, 0, 0, hwnd)
                if (maxVal > minVal) {
                    CalcSafeStep(dist) {
                        if (dist <= 20)
                            return 1 ; 近距離微調嚴格保證只跳 1 格
                        else if (dist <= 50)
                            return Max(1, Min(5, Round((dist - 20) / 6))) ; 中距離步進 1 ~ 5 格
                        else
                            return Max(5, Min(20, Round(((dist / channelWidth) * (maxVal - minVal)) * 0.05))) ; 遠距離步進最大 20 格
                    }
                    
                    ; 2. 計算點擊處對應的目標數值
                    pctTarget := (relativeX - cLeft) / (cRight - cLeft)
                    pctTarget := Min(1.0, Max(0.0, pctTarget))
                    targetVal := Round(minVal + pctTarget * (maxVal - minVal))
                    
                    isMovingRight := (relativeX > tRight)
                    
                    ; 點擊瞬間執行單次安全微調步進 (點一次保證只走 1 格，絕不瞬移)
                    if (isMovingRight) {
                        distPx := relativeX - tRight
                        ctrlObj.Value := Min(targetVal, currVal + CalcSafeStep(distPx))
                    } else {
                        distPx := tLeft - relativeX
                        ctrlObj.Value := Max(targetVal, currVal - CalcSafeStep(distPx))
                    }
                    PostMessage(0x0114, 4, hwnd, guiHwnd)
                    
                    ; 3. 若按住不放，持續以步進前進，直到數值抵達游標目標 (重合) 後無縫切換為拖曳
                    holdTicks := 0
                    isCaptured := (ctrlObj.Value == targetVal)
                    
                    while GetKeyState("LButton", "P") {
                        Sleep(20)
                        MouseGetPos(&curX, &curY)
                        ptCurrent := Buffer(8, 0)
                        NumPut("int", curX, ptCurrent, 0), NumPut("int", curY, ptCurrent, 4)
                        DllCall("user32\ScreenToClient", "Ptr", hwnd, "Ptr", ptCurrent)
                        curRelX := NumGet(ptCurrent, 0, "Int")
                        
                        if (isCaptured) {
                            ; 已經步進追上游標，進入與直接點住拉柄相同的即時拖曳模式
                            pct := (curRelX - cLeft) / (cRight - cLeft)
                            pct := Min(1.0, Max(0.0, pct))
                            dragVal := Round(minVal + pct * (maxVal - minVal))
                            if (ctrlObj.Value != dragVal) {
                                ctrlObj.Value := dragVal
                                PostMessage(0x0114, 4, hwnd, guiHwnd)
                            }
                        } else {
                            ; 尚未追上，更新當前目標與拉柄位置
                            curPctTarget := (curRelX - cLeft) / (cRight - cLeft)
                            curPctTarget := Min(1.0, Max(0.0, curPctTarget))
                            curTargetVal := Round(minVal + curPctTarget * (maxVal - minVal))
                            
                            SendMessage(0x0419, 0, thumbRect, hwnd)
                            curTLeft := NumGet(thumbRect, 0, "Int")
                            curTRight := NumGet(thumbRect, 8, "Int")
                            
                            holdTicks++
                            if (holdTicks > 6) {
                                if (curRelX > curTRight) {
                                    distPx := curRelX - curTRight
                                    stepVal := CalcSafeStep(distPx)
                                    ctrlObj.Value := Min(curTargetVal, ctrlObj.Value + stepVal)
                                    PostMessage(0x0114, 4, hwnd, guiHwnd)
                                    if (ctrlObj.Value >= curTargetVal)
                                        isCaptured := true
                                } else if (curRelX < curTLeft) {
                                    distPx := curTLeft - curRelX
                                    stepVal := CalcSafeStep(distPx)
                                    ctrlObj.Value := Max(curTargetVal, ctrlObj.Value - stepVal)
                                    PostMessage(0x0114, 4, hwnd, guiHwnd)
                                    if (ctrlObj.Value <= curTargetVal)
                                        isCaptured := true
                                } else {
                                    isCaptured := true
                                }
                            }
                        }
                    }
                    return 0
                }
            }
        }
    }
}
OnMessage(0x0201, OnWM_LBUTTONDOWN)

; =================================================================
; [WM_MOUSEWHEEL 滑鼠滾輪即時微調拉桿數值]
; =================================================================
OnWM_MOUSEWHEEL(wParam, lParam, msg, hwnd) {
    MouseGetPos(, , , &ctrlHwnd, 2)
    if (!ctrlHwnd)
        return
    try {
        cls := WinGetClass(ctrlHwnd)
    } catch {
        cls := ""
    }
    if (cls == "msctls_trackbar32") {
        ctrlObj := GuiCtrlFromHwnd(ctrlHwnd)
        if (ctrlObj) {
            delta := (wParam >> 16) > 0x7FFF ? (wParam >> 16) - 0x10000 : (wParam >> 16)
            minVal := SendMessage(0x0401, 0, 0, ctrlHwnd)
            maxVal := SendMessage(0x0402, 0, 0, ctrlHwnd)
            stepSize := GetKeyState("Shift", "P") ? 10 : 1
            if (delta > 0) {
                ctrlObj.Value := Min(maxVal, ctrlObj.Value + stepSize)
            } else if (delta < 0) {
                ctrlObj.Value := Max(minVal, ctrlObj.Value - stepSize)
            }
            PostMessage(0x0114, 4, ctrlHwnd, ctrlObj.Gui.Hwnd)
            return 0
        }
    }
}
OnMessage(0x020A, OnWM_MOUSEWHEEL)

; =================================================================
; [安全獲取有效 GUI 句柄 Helper]
; =================================================================
GetMacroEditGuiHwnd() {
    global MacroEditGui, MyGui
    try {
        if (MacroEditGui != "" && WinExist("ahk_id " . MacroEditGui.Hwnd))
            return MacroEditGui.Hwnd
    }
    try {
        if (MyGui != "" && WinExist("ahk_id " . MyGui.Hwnd))
            return MyGui.Hwnd
    }
    return 0
}

GetBoxPos(guiObj, &gX, &gY, &gW, &gH) {
    try {
        if WinExist("ahk_id " . guiObj.Hwnd) {
            WinGetPos(&gX, &gY, &gW, &gH, "ahk_id " . guiObj.Hwnd)
            return true
        }
    }
    gX := 0, gY := 0, gW := 0, gH := 0
    return false
}

ShowBoxGui(boxGui, x, y, w, h) {
    boxGui.Show("X" x " Y" y " W" Max(1, w) " H" Max(1, h) " NoActivate")
}

; =================================================================
; [預設資料初始化]
; =================================================================
InitDefaultGroups() {
    global MacroGroups
    if (MacroGroups.Length == 0) {
        MacroGroups.Push({
            name: "預設群組 1",
            icon: "⚔️",
            visible: 1,
            loopCount: 1,
            steps: []
        })
    }
}

GetVisibleGroupCount() {
    global MacroGroups
    cnt := 0
    for grp in MacroGroups {
        if (!grp.HasOwnProp("visible") || grp.visible)
            cnt++
    }
    return cnt
}

; =================================================================
; [主懸浮 UI 建立]
; =================================================================
BuildMainGui() {
    global MyGui, ProgressPic, GearBtn, ExitBtn, GroupBtns, MacroGroups, RunningGroupIdx, IsAlwaysOnTop
    global GuiX, GuiY, GuiH, GuiOpacity, ProgressBarWidth
    
    if (MyGui != "") {
        try {
            if WinExist("ahk_id " . MyGui.Hwnd)
                MyGui.Destroy()
        }
        MyGui := ""
    }
    
    IsAlwaysOnTop := true
    MyGui := Gui("-Caption -Border +ToolWindow +AlwaysOnTop")
    MyGui.BackColor := "010101"
    MyGui.SetFont("s13 bold cWhite", "Segoe UI Emoji")
    
    GroupBtns := []
    
    ; 1. 最左側：⚙ 設定按鈕
    GearBtn := MyGui.Add("Text", "x3 y3 w32 h28 Center +0x200 Background010101", "⚙️")
    GearBtn.OnEvent("Click", (*) => ToggleMacroEditGui())
    
    ; 2. 中間：動態繪製設為「顯示」群組的獨立執行圖示按鈕
    currX := 38
    MakeGroupClickFn(grpIdx) {
        return (*) => ToggleGroupExecution(grpIdx)
    }
    
    for idx, grp in MacroGroups {
        isVis := !grp.HasOwnProp("visible") || grp.visible
        if (isVis) {
            btnText := (RunningGroupIdx == idx) ? "⏹" : grp.icon
            btn := MyGui.Add("Text", "x" currX " y3 w32 h28 Center +0x200 Background010101", btnText)
            
            btn.OnEvent("Click", MakeGroupClickFn(idx))
            GroupBtns.Push({ btn: btn, grpIdx: idx })
            
            currX += 35
        }
    }
    
    ; 3. 右側：⏏ 離開按鈕
    ExitBtn := MyGui.Add("Text", "x" currX " y3 w32 h28 Center +0x200 Background010101", "⏏")
    ExitBtn.OnEvent("Click", (*) => (StopMacro(), MyGui.Destroy(), ExitApp()))
    
    currX += 35
    
    ; 4. GDI 進度條 (位於所有按鈕右側)
    ProgressPic := MyGui.Add("Picture", "x" currX " y3 w" . ProgressBarWidth . " h28 -Border +Hidden", "")
    try DllCall("uxtheme\SetWindowTheme", "Ptr", ProgressPic.Hwnd, "Str", "", "Str", "")
    
    ; 右鍵選單支援
    MyGui.OnEvent("ContextMenu", (*) => ShowContextMenu())
    
    ; 顯示無邊框懸浮 UI
    totalW := (RunningGroupIdx > 0) ? (currX + ProgressBarWidth + 5) : currX
    MyGui.Show("X" GuiX " Y" GuiY " W" totalW " H" GuiH " NoActivate")
    WinSetTransparent(GuiOpacity, MyGui.Hwnd)
}

ShowContextMenu() {
    global MyGui
    mainMenu := Menu()
    mainMenu.Add("⚙ 開啟巨集編輯器", (*) => ToggleMacroEditGui())
    mainMenu.Add()
    mainMenu.Add("📥 匯入 INI 設定檔", (*) => ImportMacroConfig())
    mainMenu.Add("📤 匯出 INI 備份檔", (*) => ExportMacroConfig())
    mainMenu.Add()
    mainMenu.Add("⏏ 離開程式", (*) => (StopMacro(), MyGui.Destroy(), ExitApp()))
    mainMenu.Show()
}

UpdateMainGuiButtons() {
    global GroupBtns, MacroGroups, RunningGroupIdx
    for item in GroupBtns {
        idx := item.grpIdx
        if (idx <= MacroGroups.Length) {
            item.btn.Value := (RunningGroupIdx == idx) ? "⏹" : MacroGroups[idx].icon
        }
    }
}

; =================================================================
; [GDI 進度條繪製]
; =================================================================
RenderProgressBarBitmap(loopPercent, totalPercent, text, w := 500, h := 28) {
    global hCurrentProgressBmp, ProgressPic
    if (!ProgressPic)
        return
        
    hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
    hdcMem := DllCall("gdi32\CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
    hbm := DllCall("gdi32\CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", w, "Int", h, "Ptr")
    hbmOld := DllCall("gdi32\SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")
    
    ; 1. 面板底色 0x010101
    hBrushBg := DllCall("gdi32\CreateSolidBrush", "UInt", 0x010101, "Ptr")
    rectBg := Buffer(16, 0)
    NumPut("int", 0, rectBg, 0), NumPut("int", 0, rectBg, 4)
    NumPut("int", w, rectBg, 8), NumPut("int", h, rectBg, 12)
    DllCall("user32\FillRect", "Ptr", hdcMem, "Ptr", rectBg, "Ptr", hBrushBg)
    DllCall("gdi32\DeleteObject", "Ptr", hBrushBg)
    
    ; 2. 總進度黃條 (0x00FFFF)
    if (totalPercent > 0) {
        totalW := Integer(w * Min(1.0, Max(0.0, totalPercent / 100)))
        if (totalW > 0) {
            hBrushTotal := DllCall("gdi32\CreateSolidBrush", "UInt", 0x00FFFF, "Ptr")
            rectTotal := Buffer(16, 0)
            NumPut("int", 0, rectTotal, 0), NumPut("int", 0, rectTotal, 4)
            NumPut("int", totalW, rectTotal, 8), NumPut("int", 5, rectTotal, 12)
            DllCall("user32\FillRect", "Ptr", hdcMem, "Ptr", rectTotal, "Ptr", hBrushTotal)
            DllCall("gdi32\DeleteObject", "Ptr", hBrushTotal)
        }
    }
    
    ; 3. 當前步驟水藍條 (0xFFC080)
    if (loopPercent > 0) {
        loopW := Integer(w * Min(1.0, Max(0.0, loopPercent / 100)))
        if (loopW > 0) {
            hBrushLoop := DllCall("gdi32\CreateSolidBrush", "UInt", 0xFFC080, "Ptr")
            rectLoop := Buffer(16, 0)
            NumPut("int", 0, rectLoop, 0), NumPut("int", (totalPercent > 0 ? 5 : 0), rectLoop, 4)
            NumPut("int", loopW, rectLoop, 8), NumPut("int", h, rectLoop, 12)
            DllCall("user32\FillRect", "Ptr", hdcMem, "Ptr", rectLoop, "Ptr", hBrushLoop)
            DllCall("gdi32\DeleteObject", "Ptr", hBrushLoop)
        }
    }
    
    ; 4. 立體陰影 + 亮白正面文字
    if (text != "") {
        DllCall("gdi32\SetBkMode", "Ptr", hdcMem, "Int", 1)
        hFont := DllCall("gdi32\CreateFontW", "Int", -15, "Int", 0, "Int", 0, "Int", 0, "Int", 700, "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 1, "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 0, "Str", "Microsoft JhengHei", "Ptr")
        hFontOld := DllCall("gdi32\SelectObject", "Ptr", hdcMem, "Ptr", hFont, "Ptr")
        
        ; 黑色陰影
        DllCall("gdi32\SetTextColor", "Ptr", hdcMem, "UInt", 0x000000)
        rectShadow := Buffer(16, 0)
        NumPut("int", 9, rectShadow, 0), NumPut("int", 5, rectShadow, 4)
        NumPut("int", w + 1, rectShadow, 8), NumPut("int", h + 1, rectShadow, 12)
        DllCall("user32\DrawTextW", "Ptr", hdcMem, "Str", text, "Int", -1, "Ptr", rectShadow, "UInt", 0x24)

        ; 白色文字
        DllCall("gdi32\SetTextColor", "Ptr", hdcMem, "UInt", 0xFFFFFF)
        rectText := Buffer(16, 0)
        NumPut("int", 8, rectText, 0), NumPut("int", 4, rectText, 4)
        NumPut("int", w, rectText, 8), NumPut("int", h, rectText, 12)
        DllCall("user32\DrawTextW", "Ptr", hdcMem, "Str", text, "Int", -1, "Ptr", rectText, "UInt", 0x24)
        
        DllCall("gdi32\SelectObject", "Ptr", hdcMem, "Ptr", hFontOld)
        DllCall("gdi32\DeleteObject", "Ptr", hFont)
    }
    
    DllCall("gdi32\SelectObject", "Ptr", hdcMem, "Ptr", hbmOld)
    DllCall("gdi32\DeleteDC", "Ptr", hdcMem)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
    
    if (hCurrentProgressBmp) {
        DllCall("gdi32\DeleteObject", "Ptr", hCurrentProgressBmp)
    }
    hCurrentProgressBmp := hbm
    ProgressPic.Value := "HBITMAP:" . hbm
}

; =================================================================
; [多群組巨集編輯與管理介面 GUI (使用下拉選單切換群組)]
; =================================================================
GetGroupDisplayList() {
    global MacroGroups
    list := []
    for idx, grp in MacroGroups {
        isVis := !grp.HasOwnProp("visible") || grp.visible
        visTag := isVis ? "" : " [隱藏]"
        list.Push(Format("{}. {} {}{}", idx, grp.icon, grp.name, visTag))
    }
    return list
}

ToggleMacroEditGui() {
    global MacroEditGui, DDLGroupSelect, MacroLV, LoopCountSlider, LoopCountLabel, MacroGroups, ActiveEditGroupIdx, MyGui, IsAlwaysOnTop
    
    if (MacroEditGui != "") {
        try {
            if WinExist("ahk_id " . MacroEditGui.Hwnd)
                MacroEditGui.Destroy()
        }
        MacroEditGui := ""
        return
    }
    
    ownerHwnd := (MyGui != "" && WinExist("ahk_id " . MyGui.Hwnd)) ? MyGui.Hwnd : 0
    ownerOpt := (ownerHwnd > 0) ? (" +Owner" . ownerHwnd) : ""
    topOpt := IsAlwaysOnTop ? " +AlwaysOnTop" : " -AlwaysOnTop"
    
    MacroEditGui := Gui("-MaximizeBox" . ownerOpt . topOpt, "⚙ 巨集編輯與管理介面")
    MacroEditGui.BackColor := "0x121212"
    MacroEditGui.SetFont("s10 bold cWhite", "Microsoft JhengHei")
    MacroEditGui.OnEvent("Close", (*) => (MacroEditGui := ""))
    
    ; 頂部：群組選擇下拉選單與操作按鈕列
    MacroEditGui.Add("Text", "x15 y16 w75 h25 cWhite", "選擇群組:")
    
    groupList := GetGroupDisplayList()
    chooseIdx := (ActiveEditGroupIdx <= groupList.Length) ? ActiveEditGroupIdx : 1
    DDLGroupSelect := MacroEditGui.Add("DropDownList", "x95 y12 w250 Background0x2A2A2A c0x00FFFF Choose" . chooseIdx, groupList)
    DDLGroupSelect.OnEvent("Change", (ctrl, *) => SwitchActiveGroup(ctrl.Value))
    
    btnAddGrp := MacroEditGui.Add("Button", "x355 y10 w75 h32 Background0x008800", "➕ 新增")
    btnAddGrp.OnEvent("Click", (*) => PromptAddGroup())
    
    btnEditGrp := MacroEditGui.Add("Button", "x435 y10 w75 h32 Background0x282828", "✏ 重命名")
    btnEditGrp.OnEvent("Click", (*) => PromptEditGroup())
    
    btnDelGrp := MacroEditGui.Add("Button", "x515 y10 w75 h32 Background0x882222", "🗑 刪除")
    btnDelGrp.OnEvent("Click", (*) => DeleteActiveGroup())
    
    ; 中間：步驟清單 ListView
    lvY := 52
    MacroLV := MacroEditGui.Add("ListView", "x15 y" lvY " w580 h240 Background0x1E1E1E cWhite +Grid -Multi", ["序號", "動作類型", "詳細內容", "執行參數"])
    MacroLV.ModifyCol(1, 50)
    MacroLV.ModifyCol(2, 130)
    MacroLV.ModifyCol(3, 250)
    MacroLV.ModifyCol(4, 135)
    MacroLV.OnEvent("DoubleClick", (*) => EditSelectedStep())
    
    RefreshMacroListView()
    
    ; 動作按鈕列
    actY := lvY + 248
    btnAddColor := MacroEditGui.Add("Button", "x15 y" actY " w105 h35 Background0x282828", "🎯 圈選顏色")
    btnAddColor.OnEvent("Click", (*) => PromptAddColorDetect())
    
    btnAddKey := MacroEditGui.Add("Button", "x125 y" actY " w90 h35 Background0x282828", "⌨️ +按鍵")
    btnAddKey.OnEvent("Click", (*) => PromptAddKeyPress())
    
    btnAddWait := MacroEditGui.Add("Button", "x220 y" actY " w85 h35 Background0x282828", "⏱ +等待")
    btnAddWait.OnEvent("Click", (*) => PromptAddWait())
    
    btnAddLoopGoto := MacroEditGui.Add("Button", "x310 y" actY " w100 h35 Background0x282828", "🔁 +步驟循環")
    btnAddLoopGoto.OnEvent("Click", (*) => PromptAddLoopGoto())
    
    btnEditStep := MacroEditGui.Add("Button", "x415 y" actY " w60 h35 Background0x006699", "✏ 編輯")
    btnEditStep.OnEvent("Click", (*) => EditSelectedStep())
    
    btnDelStep := MacroEditGui.Add("Button", "x480 y" actY " w55 h35 Background0x882222", "🗑 刪除")
    btnDelStep.OnEvent("Click", (*) => DeleteSelectedStep())
    
    btnUp := MacroEditGui.Add("Button", "x540 y" actY " w32 h35", "▲")
    btnUp.OnEvent("Click", (*) => MoveStep(-1))
    
    btnDown := MacroEditGui.Add("Button", "x575 y" actY " w32 h35", "▼")
    btnDown.OnEvent("Click", (*) => MoveStep(1))
    
    ; 底部：當前群組循環數 Slider (最左邊 0 為無限次) 與 匯入/匯出/儲存按鈕
    botY := actY + 45
    curLoop := (ActiveEditGroupIdx <= MacroGroups.Length) ? MacroGroups[ActiveEditGroupIdx].loopCount : 1
    
    MacroEditGui.Add("Text", "x15 y" (botY + 5) " w120 h25 cWhite", "🔁 當前群組循環數:")
    LoopCountLabel := MacroEditGui.Add("Text", "x138 y" (botY + 5) " w75 h25 c0x00FFFF", (curLoop == 0 ? "無限次 (∞)" : curLoop . " 次"))
    LoopCountSlider := MacroEditGui.Add("Slider", "x215 y" botY " w140 h30 Range0-999 Thick20 Tooltip AltSubmit", curLoop)
    LoopCountSlider.OnEvent("Change", (ctrl, *) => (
        (ActiveEditGroupIdx <= MacroGroups.Length) ? (MacroGroups[ActiveEditGroupIdx].loopCount := ctrl.Value) : 0,
        LoopCountLabel.Value := (ctrl.Value == 0 ? "無限次 (∞)" : ctrl.Value . " 次")
    ))
    
    btnImport := MacroEditGui.Add("Button", "x365 y" botY " w70 h35 Background0x282828", "📥 匯入")
    btnImport.OnEvent("Click", (*) => ImportMacroConfig())
    
    btnExport := MacroEditGui.Add("Button", "x440 y" botY " w70 h35 Background0x282828", "📤 匯出")
    btnExport.OnEvent("Click", (*) => ExportMacroConfig())
    
    btnSave := MacroEditGui.Add("Button", "x515 y" botY " w80 h35 Background0x008800", "💾 儲存")
    btnSave.OnEvent("Click", (*) => (SaveMacroConfig(), ToggleMacroEditGui()))
    
    winH := botY + 48
    MacroEditGui.Show("w610 h" winH)
}

RebuildMacroEditGui() {
    global MacroEditGui
    if (MacroEditGui != "") {
        try {
            if WinExist("ahk_id " . MacroEditGui.Hwnd)
                MacroEditGui.Destroy()
        }
        MacroEditGui := ""
    }
    ToggleMacroEditGui()
}

SwitchActiveGroup(idx) {
    global ActiveEditGroupIdx, MacroGroups, DDLGroupSelect, LoopCountSlider, LoopCountLabel
    if (idx > 0 && idx <= MacroGroups.Length) {
        ActiveEditGroupIdx := idx
        
        if (DDLGroupSelect) {
            try DDLGroupSelect.Choose(idx)
        }
        
        RefreshMacroListView()
        if (LoopCountSlider) {
            cnt := MacroGroups[idx].loopCount
            LoopCountSlider.Value := cnt
            LoopCountLabel.Value := (cnt == 0 ? "無限次 (∞)" : cnt . " 次")
        }
    }
}

; =================================================================
; [圖示與群組設定 Modal (使用下拉選單挑選圖示)]
; =================================================================
PromptAddGroup() {
    global MacroGroups, ActiveEditGroupIdx, IconPresets
    ShowGroupDialog("➕ 新增巨集群組", "新群組 " . (MacroGroups.Length + 1), "⚔️", 1, (name, icon, visible) => (
        MacroGroups.Push({
            name: name,
            icon: icon,
            visible: visible,
            loopCount: 1,
            steps: []
        }),
        ActiveEditGroupIdx := MacroGroups.Length,
        BuildMainGui(),
        RebuildMacroEditGui()
    ))
}

PromptEditGroup() {
    global MacroGroups, ActiveEditGroupIdx
    if (ActiveEditGroupIdx < 1 || ActiveEditGroupIdx > MacroGroups.Length)
        return
        
    curGrp := MacroGroups[ActiveEditGroupIdx]
    curVis := curGrp.HasOwnProp("visible") ? curGrp.visible : 1
    ShowGroupDialog("✏ 重命名/圖示/顯示設定", curGrp.name, curGrp.icon, curVis, (name, icon, visible) => (
        curGrp.name := name,
        curGrp.icon := icon,
        curGrp.visible := visible,
        BuildMainGui(),
        RebuildMacroEditGui()
    ))
}

ShowGroupDialog(titleText, defaultName, defaultIcon, defaultVisible, callback) {
    global IconPresets, IsAlwaysOnTop
    
    ownerHwnd := GetMacroEditGuiHwnd()
    ownerOpt := (ownerHwnd > 0) ? (" +Owner" . ownerHwnd) : ""
    topOpt := IsAlwaysOnTop ? " +AlwaysOnTop" : " -AlwaysOnTop"
    
    dlg := Gui("-MaximizeBox" . ownerOpt . topOpt, titleText)
    dlg.BackColor := "0x1A1A1A"
    dlg.SetFont("s10 bold cWhite", "Microsoft JhengHei")
    
    dlg.Add("Text", "x20 y18 w85 h25 cWhite", "群組名稱:")
    nameEdit := dlg.Add("Edit", "x110 y15 w255 h26 Background0x2A2A2A c0x00FFFF", defaultName)
    
    ; 圖示下拉選單
    dlg.Add("Text", "x20 y56 w85 h25 cWhite", "選擇圖示:")
    
    iconIdx := 1
    for idx, ic in IconPresets {
        if (ic == defaultIcon) {
            iconIdx := idx
            break
        }
    }
    
    dlg.SetFont("s12 bold cWhite", "Segoe UI Emoji")
    ddlIcon := dlg.Add("DropDownList", "x110 y52 w255 Background0x2A2A2A c0x00FFFF Choose" . iconIdx, IconPresets)
    
    dlg.SetFont("s10 bold cWhite", "Microsoft JhengHei")
    cbVisible := dlg.AddCheckBox("x20 y94 w345 h25 " . (defaultVisible ? "Checked" : ""), "👁 顯示於主懸浮列 (取消勾選則隱藏此群組按鈕)")
    
    btnOK := dlg.Add("Button", "x20 y130 w345 h36 Background0x008800", "確認儲存設定")
    btnOK.OnEvent("Click", (*) => (
        finalName := Trim(nameEdit.Value) != "" ? Trim(nameEdit.Value) : "巨集群組",
        finalIcon := ddlIcon.Text != "" ? ddlIcon.Text : "⚔️",
        finalVis := cbVisible.Value ? 1 : 0,
        dlg.Destroy(),
        callback.Call(finalName, finalIcon, finalVis)
    ))
    
    dlg.Show("w385 h180")
}

DeleteActiveGroup() {
    global MacroGroups, ActiveEditGroupIdx
    if (MacroGroups.Length <= 1) {
        MsgBox("至少必須保留一個巨集群組！", "提示", "262192")
        return
    }
    
    if (ActiveEditGroupIdx >= 1 && ActiveEditGroupIdx <= MacroGroups.Length) {
        MacroGroups.RemoveAt(ActiveEditGroupIdx)
        ActiveEditGroupIdx := Min(ActiveEditGroupIdx, MacroGroups.Length)
        BuildMainGui()
        RebuildMacroEditGui()
    }
}

RefreshMacroListView() {
    global MacroLV, MacroGroups, ActiveEditGroupIdx
    if (!MacroLV || ActiveEditGroupIdx < 1 || ActiveEditGroupIdx > MacroGroups.Length)
        return
        
    MacroLV.Delete()
    steps := MacroGroups[ActiveEditGroupIdx].steps
    for idx, step in steps {
        if (step.type == "color_detect") {
            tolVal := step.HasOwnProp("tolerance") ? step.tolerance : 20
            invVal := step.HasOwnProp("invert") && step.invert
            aType := step.HasOwnProp("actionType") ? step.actionType : 0
            pKey := step.HasOwnProp("pressKey") ? step.pressKey : "Space"
            hMin := step.HasOwnProp("holdMin") ? step.holdMin : 0
            hSec := step.HasOwnProp("holdSec") ? step.holdSec : 0
            toSec := step.HasOwnProp("timeoutSec") ? step.timeoutSec : 0
            toMode := step.HasOwnProp("timeoutMode") ? step.timeoutMode : 1
            jpStep := step.HasOwnProp("jumpStep") ? step.jumpStep : 1
            
            hMs := (hMin * 60 + hSec) * 1000
            hStr := (hMs > 0) ? ("(" . FormatDurationText(hMs) . ")") : ""
            
            actTitle := "🎨 顏色偵測" . (invVal ? " (反向)" : "")
            aStr := (aType == 0) ? "點擊" : ((aType == 1) ? Format("按鍵'{}'{}", pKey, hStr) : Format("點擊+按鍵'{}'{}", pKey, hStr))
            toModeStr := (toMode == 0) ? "重試" : ((toMode == 1) ? "下一步" : ("返回第" jpStep "步"))
            toInfo := (toSec > 0) ? Format(" | ⏱逾時:{}s[{}]", toSec, toModeStr) : ""
            paramText := Format("動作:{} | 色:{} | 容:{}", aStr, step.color, tolVal) . (invVal ? " | 🚫反向" : "") . toInfo
            MacroLV.Add("", idx, actTitle, "區域: (" step.x "," step.y " W:" step.w " H:" step.h ")", paramText)
        } else if (step.type == "key_press") {
            repCount := step.HasOwnProp("repeat") ? step.repeat : 1
            repStr := (repCount == 0) ? "無限" : repCount
            repInfo := (repCount == 1) ? "" : Format(" (重複 {} 次)", repStr)
            hStr := FormatDurationText(step.holdMs)
            dStr := (step.delayMs > 0) ? (" | 延遲 " . FormatDurationText(step.delayMs)) : ""
            MacroLV.Add("", idx, "⌨️ 按鍵發送", Format("按鍵: {}{}", step.key, repInfo), Format("按住: {}{}", hStr, dStr))
        } else if (step.type == "wait") {
            MacroLV.Add("", idx, "⏱ 等待秒數", "純等待延遲", FormatDurationText(step.waitMs))
        } else if (step.type == "loop_goto") {
            targetS := step.HasOwnProp("targetStep") ? step.targetStep : 1
            maxL := step.HasOwnProp("maxLoops") ? step.maxLoops : 1
            lStr := (maxL == 0) ? "無限次循環返回" : Format("循環 {} 次後推進下一步", maxL)
            MacroLV.Add("", idx, "🔁 步驟循環控制", Format("返回第 {} 步", targetS), lStr)
        }
    }
}

DeleteSelectedStep() {
    global MacroLV, MacroGroups, ActiveEditGroupIdx
    if (ActiveEditGroupIdx < 1 || ActiveEditGroupIdx > MacroGroups.Length)
        return
    row := MacroLV.GetNext()
    steps := MacroGroups[ActiveEditGroupIdx].steps
    if (row > 0 && row <= steps.Length) {
        steps.RemoveAt(row)
        RefreshMacroListView()
    } else {
        MsgBox("請先點選欲刪除的巨集步驟項！", "提示", "262192")
    }
}

MoveStep(dir) {
    global MacroLV, MacroGroups, ActiveEditGroupIdx
    if (ActiveEditGroupIdx < 1 || ActiveEditGroupIdx > MacroGroups.Length)
        return
    row := MacroLV.GetNext()
    steps := MacroGroups[ActiveEditGroupIdx].steps
    target := row + dir
    if (row > 0 && target >= 1 && target <= steps.Length) {
        item := steps[row]
        steps.RemoveAt(row)
        steps.InsertAt(target, item)
        RefreshMacroListView()
        MacroLV.Modify(target, "Select Focus")
    }
}

; =================================================================
; [動作編輯分流器 EditSelectedStep]
; =================================================================
EditSelectedStep() {
    global MacroLV, MacroGroups, ActiveEditGroupIdx
    if (ActiveEditGroupIdx < 1 || ActiveEditGroupIdx > MacroGroups.Length)
        return
    row := MacroLV.GetNext()
    steps := MacroGroups[ActiveEditGroupIdx].steps
    if (row > 0 && row <= steps.Length) {
        step := steps[row]
        if (step.type == "color_detect") {
            PromptEditColorDetect(step)
        } else if (step.type == "key_press") {
            PromptEditKeyPress(step)
        } else if (step.type == "wait") {
            PromptEditWait(step)
        } else if (step.type == "loop_goto") {
            PromptEditLoopGoto(step)
        }
    } else {
        MsgBox("請先點選欲編輯的巨集步驟項！", "提示", "262192")
    }
}

; =================================================================
; [動作 1：畫面圈選 + 主色偵測 + 編輯/測試]
; =================================================================
PromptAddColorDetect() {
    SelectScreenRegion((x, y, w, h) => ProcessColorSelection(x, y, w, h))
}

SelectScreenRegion(callback) {
    CoordMode("Mouse", "Screen")
    CoordMode("Pixel", "Screen")
    
    overlayGui := Gui("+AlwaysOnTop -Caption +ToolWindow +Owner")
    overlayGui.BackColor := "000000"
    WinSetTransparent(45, overlayGui.Hwnd)
    
    tipW := 520, tipH := 42
    tipX := Integer((A_ScreenWidth - tipW) / 2)
    tipBanner := overlayGui.Add("Text", Format("x{} y30 w{} h{} Center +0x200 Background0x008800 cWhite", tipX, tipW, tipH), "🎯 請在畫面上按住滑鼠左鍵【拖曳圈選】目標區域 (Esc 取消)")
    tipBanner.SetFont("s12 bold", "Microsoft JhengHei")
    
    borderGui := Gui("+AlwaysOnTop -Caption +ToolWindow +Owner")
    borderGui.BackColor := "0x00FFFF"
    
    overlayGui.Show("x0 y0 w" A_ScreenWidth " h" A_ScreenHeight)
    
    while !GetKeyState("LButton", "P") {
        Sleep(10)
        if GetKeyState("Esc", "P") {
            overlayGui.Destroy()
            borderGui.Destroy()
            return
        }
    }
    
    MouseGetPos(&startX, &startY)
    
    while GetKeyState("LButton", "P") {
        MouseGetPos(&curX, &curY)
        bx := Min(startX, curX)
        by := Min(startY, curY)
        bw := Abs(curX - startX)
        bh := Abs(curY - startY)
        if (bw > 2 && bh > 2) {
            borderGui.Show("x" bx " y" by " w" bw " h" bh " NoActivate")
        }
        Sleep(10)
    }
    
    MouseGetPos(&endX, &endY)
    borderGui.Destroy()
    overlayGui.Destroy()
    
    x1 := Min(startX, endX)
    y1 := Min(startY, endY)
    w := Abs(endX - startX)
    h := Abs(endY - startY)
    
    if (w < 4 || h < 4) {
        MsgBox("圈選範圍過小，請重新操作！", "提示", "262192")
        return
    }
    
    callback.Call(x1, y1, w, h)
}

ProcessColorSelection(x, y, w, h) {
    global MacroGroups, ActiveEditGroupIdx
    if (ActiveEditGroupIdx < 1 || ActiveEditGroupIdx > MacroGroups.Length)
        return
        
    domColor := GetDominantColor(x, y, w, h)
    
    newStep := {
        type: "color_detect",
        x: x,
        y: y,
        w: w,
        h: h,
        color: domColor,
        clickCenterX: Integer(x + w/2),
        clickCenterY: Integer(y + h/2),
        tolerance: 20,
        invert: 0,
        actionType: 0,
        pressKey: "Space",
        holdMin: 0,
        holdSec: 0,
        timeoutSec: 0,
        timeoutKey: "",
        timeoutMode: 1,
        jumpStep: 1
    }
    MacroGroups[ActiveEditGroupIdx].steps.Push(newStep)
    RefreshMacroListView()
    
    PromptEditColorDetect(newStep)
}

GetDominantColor(x, y, w, h) {
    CoordMode("Pixel", "Screen")
    CoordMode("Mouse", "Screen")
    Sleep(80)
    
    colorCounts := Map()
    stepX := Max(1, Floor(w / 12))
    stepY := Max(1, Floor(h / 12))
    
    maxCount := 0, dominantColor := "0xFFFFFF"
    maxNonPureCount := 0, dominantNonPureColor := ""
    
    currX := x + Integer(stepX / 2)
    while (currX < x + w) {
        currY := y + Integer(stepY / 2)
        while (currY < y + h) {
            c := PixelGetColor(currX, currY, "RGB")
            cStr := Format("0x{:06X}", c)
            count := (colorCounts.Has(cStr) ? colorCounts[cStr] : 0) + 1
            colorCounts[cStr] := count
            
            if (count > maxCount) {
                maxCount := count
                dominantColor := cStr
            }
            
            if (cStr != "0xFFFFFF" && count > maxNonPureCount) {
                maxNonPureCount := count
                dominantNonPureColor := cStr
            }
            
            currY += stepY
        }
        currX += stepX
    }
    return (dominantNonPureColor != "") ? dominantNonPureColor : dominantColor
}

; =================================================================
; [通用按鍵分類與選擇下拉選單建立 Helper]
; =================================================================
AttachKeyCategoryPicker(dlg, startY, defaultKey, allowEmpty := false) {
    global KeyCategories
    
    allKeysList := []
    if (allowEmpty)
        allKeysList.Push("(無)")
    for catName, keyArr in KeyCategories {
        for k in keyArr
            allKeysList.Push(k)
    }
    
    catNamesList := ["📋 全部按鍵清單"]
    for catName, _ in KeyCategories
        catNamesList.Push(catName)
        
    initKey := (defaultKey == "" && allowEmpty) ? "(無)" : (defaultKey != "" ? defaultKey : (allowEmpty ? "(無)" : "Space"))
    initCatIdx := 1
    for cIdx, cName in catNamesList {
        if (cIdx > 1 && KeyCategories.Has(cName)) {
            for k in KeyCategories[cName] {
                if (StrLower(k) == StrLower(initKey)) {
                    initCatIdx := cIdx
                    break 2
                }
            }
        }
    }
    
    dlg.Add("Text", "x25 y" (startY + 3) " w70 h20 cWhite", "按鍵分類:")
    ddlCat := dlg.Add("DropDownList", "x95 y" startY " w245 Background0x2A2A2A c0x00FFFF Choose" . initCatIdx, catNamesList)
    
    dlg.Add("Text", "x25 y" (startY + 33) " w70 h20 cWhite", "選擇按鍵:")
    ddlKeys := dlg.Add("DropDownList", "x95 y" (startY + 30) " w145 Background0x2A2A2A c0x00FFFF", ["Space"])
    dlg.Add("Text", "x245 y" (startY + 33) " w35 h20 c0x888888", "自訂:")
    editKey := dlg.Add("Edit", "x280 y" (startY + 30) " w60 h24 Background0x2A2A2A c0x00FFFF Center", initKey)
    
    UpdateKeyList(selectedCatName, selectKey := "") {
        keysToShow := []
        if (allowEmpty && selectedCatName == "📋 全部按鍵清單")
            keysToShow.Push("(無)")
        if (selectedCatName == "📋 全部按鍵清單") {
            for catName, keyArr in KeyCategories {
                for k in keyArr
                    keysToShow.Push(k)
            }
        } else if KeyCategories.Has(selectedCatName) {
            keysToShow := KeyCategories[selectedCatName]
        }
        ddlKeys.Delete()
        ddlKeys.Add(keysToShow)
        
        targetK := (selectKey != "") ? selectKey : editKey.Value
        matchedIdx := 0
        for idx, k in keysToShow {
            if (StrLower(k) == StrLower(targetK)) {
                matchedIdx := idx
                break
            }
        }
        if (matchedIdx > 0)
            ddlKeys.Choose(matchedIdx)
        else
            ddlKeys.Choose(1)
    }
    
    UpdateKeyList(catNamesList[initCatIdx], initKey)
    
    ddlCat.OnEvent("Change", (ctrl, *) => UpdateKeyList(ctrl.Text, editKey.Value))
    ddlKeys.OnEvent("Change", (ctrl, *) => (editKey.Value := ctrl.Text))
    
    editKey.OnEvent("Change", (ctrl, *) => (
        kVal := Trim(ctrl.Value),
        UpdateCategoryFromKey(kVal)
    ))
    
    UpdateCategoryFromKey(kVal) {
        if (kVal == "" || kVal == "(無)")
            return
        matchedCat := ""
        for cName, keyArr in KeyCategories {
            for k in keyArr {
                if (StrLower(k) == StrLower(kVal)) {
                    matchedCat := cName
                    break 2
                }
            }
        }
        if (matchedCat != "") {
            for cIdx, cName in catNamesList {
                if (cName == matchedCat) {
                    if (ddlCat.Value != cIdx) {
                        ddlCat.Choose(cIdx)
                        UpdateKeyList(cName, kVal)
                    }
                    break
                }
            }
        }
    }
    
    return {
        ddlCat: ddlCat,
        ddlKeys: ddlKeys,
        editKey: editKey,
        GetValue: (params*) => (editKey.Value == "(無)" ? "" : Trim(editKey.Value))
    }
}

; === 顏色偵測編輯與即時自動測試視窗 ===
PromptEditColorDetect(step) {
    global MacroEditGui, MyGui, ActiveBoxGuiHwnd, ActiveColorEditCtrlDlg, IsAlwaysOnTop, MacroGroups, ActiveEditGroupIdx
    
    if (ActiveColorEditCtrlDlg != "") {
        try {
            if WinExist("ahk_id " . ActiveColorEditCtrlDlg.Hwnd) {
                WinActivate("ahk_id " . ActiveColorEditCtrlDlg.Hwnd)
                return
            }
        }
        ActiveColorEditCtrlDlg := ""
    }
    
    targetColor := step.color
    curX := step.x, curY := step.y, curW := step.w, curH := step.h
    curTolerance := step.HasOwnProp("tolerance") ? step.tolerance : 20
    curInvert := step.HasOwnProp("invert") ? step.invert : 0
    
    curActionType := step.HasOwnProp("actionType") ? step.actionType : 0
    curPressKey := step.HasOwnProp("pressKey") ? step.pressKey : "Space"
    curHoldMin := step.HasOwnProp("holdMin") ? step.holdMin : 0
    curHoldSec := step.HasOwnProp("holdSec") ? step.holdSec : 0
    
    curTimeoutSec := step.HasOwnProp("timeoutSec") ? step.timeoutSec : 0
    curTimeoutKey := step.HasOwnProp("timeoutKey") ? step.timeoutKey : ""
    curTimeoutMode := step.HasOwnProp("timeoutMode") ? step.timeoutMode : 1
    
    maxSteps := (ActiveEditGroupIdx <= MacroGroups.Length) ? Max(1, MacroGroups[ActiveEditGroupIdx].steps.Length) : 1
    curJumpStep := step.HasOwnProp("jumpStep") ? Min(maxSteps, Max(1, step.jumpStep)) : 1
    
    boxGui := Gui("+AlwaysOnTop -Caption -Border +ToolWindow")
    boxGui.BackColor := "0x00FFFF"
    WinSetTransparent(120, boxGui.Hwnd)
    
    ActiveBoxGuiHwnd := boxGui.Hwnd
    ShowBoxGui(boxGui, curX, curY, curW, curH)
    
    ownerHwnd := GetMacroEditGuiHwnd()
    ownerOpt := (ownerHwnd > 0) ? (" +Owner" . ownerHwnd) : ""
    
    ctrlDlg := Gui("-MaximizeBox" . ownerOpt . " +AlwaysOnTop", "🎨 顏色偵測與觸發動作處置設定")
    ctrlDlg.BackColor := "0x1A1A1A"
    ctrlDlg.SetFont("s10 bold cWhite", "Microsoft JhengHei")
    ActiveColorEditCtrlDlg := ctrlDlg
    
    ; 頂部超大醒目狀態告示牌
    statusHeaderBar := ctrlDlg.Add("Text", "x15 y10 w350 h32 Center +0x200 Background0x333333 cWhite", "[ ⏳ 請移動或調整區域進行自動檢測 ]")
    
    ; 第二行：目標顏色預覽與採樣按鈕
    ctrlDlg.Add("Text", "x15 y48 w70 h25 cWhite", "目標顏色:")
    cleanClr := GetFirstHexColor(targetColor)
    colorPreview := ctrlDlg.Add("Text", "x85 y48 w32 h25 Background" . cleanClr, "")
    editColor := ctrlDlg.Add("Edit", "x122 y46 w95 h26 Background0x2A2A2A c0x00FFFF Uppercase", targetColor)
    
    SetSwatchColor(hexStr) {
        cHex := GetFirstHexColor(hexStr)
        try {
            colorPreview.Opt("Background" . cHex)
            colorPreview.Redraw()
        }
    }
    
    btnSample := ctrlDlg.Add("Button", "x222 y44 w68 h28 Background0x282828", "🎯 採樣")
    btnRedraw := ctrlDlg.Add("Button", "x295 y44 w70 h28 Background0x282828", "🖱 重畫")
    
    ; 區域像素座標拉桿 (X, Y, W, H 全面改為拉桿)
    ctrlDlg.Add("Text", "x15 y78 w65 h20 cWhite", "位置 X:")
    lblX := ctrlDlg.Add("Text", "x80 y78 w65 h20 c0x00FFFF", curX " px")
    sldX := ctrlDlg.Add("Slider", "x145 y76 w220 h24 Range0-" A_ScreenWidth " Thick20 Tooltip AltSubmit", curX)
    
    ctrlDlg.Add("Text", "x15 y104 w65 h20 cWhite", "位置 Y:")
    lblY := ctrlDlg.Add("Text", "x80 y104 w65 h20 c0x00FFFF", curY " px")
    sldY := ctrlDlg.Add("Slider", "x145 y102 w220 h24 Range0-" A_ScreenHeight " Thick20 Tooltip AltSubmit", curY)
    
    ctrlDlg.Add("Text", "x15 y130 w65 h20 cWhite", "寬度 W:")
    lblW := ctrlDlg.Add("Text", "x80 y130 w65 h20 c0x00FFFF", curW " px")
    sldW := ctrlDlg.Add("Slider", "x145 y128 w220 h24 Range4-" A_ScreenWidth " Thick20 Tooltip AltSubmit", curW)
    
    ctrlDlg.Add("Text", "x15 y156 w65 h20 cWhite", "高度 H:")
    lblH := ctrlDlg.Add("Text", "x80 y156 w65 h20 c0x00FFFF", curH " px")
    sldH := ctrlDlg.Add("Slider", "x145 y154 w220 h24 Range4-" A_ScreenHeight " Thick20 Tooltip AltSubmit", curH)
    
    ; 顏色容許值拉桿
    ctrlDlg.Add("Text", "x15 y182 w65 h20 cWhite", "容許值:")
    lblTolerance := ctrlDlg.Add("Text", "x80 y182 w65 h20 c0x00FFFF", curTolerance)
    sldTolerance := ctrlDlg.Add("Slider", "x145 y180 w220 h24 Range0-100 Thick20 Tooltip AltSubmit", curTolerance)
    
    ; 🚫 反向未發現才點擊 CheckBox
    cbInvert := ctrlDlg.AddCheckBox("x15 y208 w350 h24 " . (curInvert ? "Checked" : ""), "🚫 反向檢測 (畫面上未發現該顏色時才點擊)")
    
    ; === 🎯 偵測成功觸發處置 ===
    ctrlDlg.SetFont("s9 bold c0x00FFFF", "Segoe UI")
    ctrlDlg.Add("GroupBox", "x15 y235 w350 h155 c0x00FFFF", "🎯 偵測成功觸發處置 (點擊 / 按鍵與按住拉桿)")
    ctrlDlg.SetFont("s9 bold cWhite", "Microsoft JhengHei")
    
    GetActionText(v) => (v == 0) ? "0: 僅點擊中心點" : ((v == 1) ? "1: 僅按鍵按住" : "2: 點擊 + 按鍵")
    ctrlDlg.Add("Text", "x25 y255 w70 h20 cWhite", "觸發動作:")
    lblActionType := ctrlDlg.Add("Text", "x95 y255 w100 h20 c0x00FFFF", GetActionText(curActionType))
    sldActionType := ctrlDlg.Add("Slider", "x195 y253 w160 h24 Range0-2 Thick20 Tooltip AltSubmit", curActionType)
    sldActionType.OnEvent("Change", (ctrl, *) => (
        lblActionType.Value := GetActionText(ctrl.Value)
    ))
    
    pressPicker := AttachKeyCategoryPicker(ctrlDlg, 282, curPressKey, false)
    
    curHoldTotalMs := (curHoldMin * 60 + curHoldSec) * 1000
    ctrlDlg.Add("Text", "x25 y344 w70 h20 cWhite", "按住時間:")
    lblHoldTime := ctrlDlg.Add("Text", "x95 y344 w160 h20 c0x00FFFF", FormatDurationText(curHoldTotalMs))
    sldHoldTime := ctrlDlg.Add("Slider", "x25 y364 w330 h24 Range1-" TimeStepTable.Length " Thick20 Tooltip AltSubmit", MsToTimeStep(curHoldTotalMs))
    sldHoldTime.OnEvent("Change", (ctrl, *) => (
        lblHoldTime.Value := FormatDurationText(TimeStepToMs(ctrl.Value))
    ))
    
    ; === ⏰ 逾時動作與轉向控制區 ===
    ctrlDlg.SetFont("s9 bold c0x00FFFF", "Segoe UI")
    ctrlDlg.Add("GroupBox", "x15 y398 w350 h195 c0x00FFFF", "⏰ 逾時處置與轉向設定 (拉桿控制)")
    ctrlDlg.SetFont("s9 bold cWhite", "Microsoft JhengHei")
    
    curTimeoutMs := curTimeoutSec * 1000
    ctrlDlg.Add("Text", "x25 y416 w70 h20 cWhite", "逾時時間:")
    lblTimeoutSec := ctrlDlg.Add("Text", "x95 y416 w160 h20 c0x00FFFF", (curTimeoutSec == 0 ? "0毫秒 (不逾時)" : FormatDurationText(curTimeoutMs)))
    sldTimeoutSec := ctrlDlg.Add("Slider", "x25 y436 w330 h24 Range1-" TimeStepTable.Length " Thick20 Tooltip AltSubmit", MsToTimeStep(curTimeoutMs))
    sldTimeoutSec.OnEvent("Change", (ctrl, *) => (
        lblTimeoutSec.Value := (ctrl.Value == 1 ? "0毫秒 (不逾時)" : FormatDurationText(TimeStepToMs(ctrl.Value)))
    ))
    
    timeoutPicker := AttachKeyCategoryPicker(ctrlDlg, 464, curTimeoutKey, true)
    
    GetModeText(v, jP) => (v == 0) ? "0: 重試本步驟" : ((v == 1) ? "1: 推進下一步" : ("2: 返回第 " jP " 步"))
    
    ctrlDlg.Add("Text", "x25 y528 w70 h20 cWhite", "處置模式:")
    lblTimeoutMode := ctrlDlg.Add("Text", "x95 y528 w100 h20 c0x00FFFF", GetModeText(curTimeoutMode, curJumpStep))
    sldTimeoutMode := ctrlDlg.Add("Slider", "x195 y526 w160 h24 Range0-2 Thick20 Tooltip AltSubmit", curTimeoutMode)
    
    ctrlDlg.Add("Text", "x25 y558 w70 h20 cWhite", "返回步驟號:")
    lblJumpStep := ctrlDlg.Add("Text", "x95 y558 w100 h20 c0x00FFFF", "第 " curJumpStep " 步")
    sldJumpStep := ctrlDlg.Add("Slider", "x195 y556 w160 h24 Range1-" maxSteps " Thick20 Tooltip AltSubmit", curJumpStep)
    
    sldTimeoutMode.OnEvent("Change", (ctrl, *) => (
        lblTimeoutMode.Value := GetModeText(ctrl.Value, sldJumpStep.Value)
    ))
    sldJumpStep.OnEvent("Change", (ctrl, *) => (
        lblJumpStep.Value := "第 " ctrl.Value " 步",
        (sldTimeoutMode.Value == 2 ? lblTimeoutMode.Value := GetModeText(2, ctrl.Value) : 0)
    ))
    
    TestColorDetect() {
        CoordMode("Pixel", "Screen")
        foundColor := false
        tolVal := Integer(sldTolerance.Value)
        isInverted := cbInvert.Value ? true : false
        
        try boxGui.Hide()
        Sleep(60)
        
        try {
            colorList := StrSplit(targetColor, ",")
            for cItem in colorList {
                cTrim := Trim(cItem)
                if (cTrim != "") {
                    if PixelSearch(&fx, &fy, curX, curY, curX + curW, curY + curH, cTrim, tolVal) {
                        foundColor := true
                        break
                    }
                }
            }
        }
        
        try ShowBoxGui(boxGui, curX, curY, curW, curH)
        
        isSuccess := isInverted ? !foundColor : foundColor
        if (isSuccess) {
            if (isInverted) {
                statusHeaderBar.Value := Format("[ 🟢 檢測成功！(反向：未發現目標顏色) ]")
            } else {
                statusHeaderBar.Value := Format("[ 🟢 檢測成功！(容許值: {}) ]", tolVal)
            }
            statusHeaderBar.Opt("Background0x008800 c0x00FFFF")
            SoundBeep(900, 100)
        } else {
            if (isInverted) {
                statusHeaderBar.Value := Format("[ ❌ 檢測失敗 (反向：畫面上仍有目標顏色) ]")
            } else {
                statusHeaderBar.Value := Format("[ ❌ 未檢測到目標顏色 (容許值: {}) ]", tolVal)
            }
            statusHeaderBar.Opt("Background0xAA0000 cWhite")
            SoundBeep(400, 120)
        }
    }
    
    sldTolerance.OnEvent("Change", (ctrl, *) => (
        lblTolerance.Value := ctrl.Value,
        curTolerance := ctrl.Value,
        TestColorDetect()
    ))
    cbInvert.OnEvent("Click", (*) => TestColorDetect())
    
    isSliderUpdating := false
    
    OnSliderPosChanged(params*) {
        if isSliderUpdating
            return
        curX := sldX.Value
        curY := sldY.Value
        curW := Max(4, sldW.Value)
        curH := Max(4, sldH.Value)
        
        lblX.Value := curX " px"
        lblY.Value := curY " px"
        lblW.Value := curW " px"
        lblH.Value := curH " px"
        
        ShowBoxGui(boxGui, curX, curY, curW, curH)
        TestColorDetect()
    }
    
    sldX.OnEvent("Change", OnSliderPosChanged)
    sldY.OnEvent("Change", OnSliderPosChanged)
    sldW.OnEvent("Change", OnSliderPosChanged)
    sldH.OnEvent("Change", OnSliderPosChanged)
    
    isUserTyping := false
    OnColorInputChanged(params*) {
        if isUserTyping
            return
        val := Trim(editColor.Value)
        if (val != "") {
            targetColor := val
            SetSwatchColor(targetColor)
            TestColorDetect()
        }
    }
    editColor.OnEvent("Change", OnColorInputChanged)
    
    UpdateBoxPosText() {
        if (boxGui && WinExist("ahk_id " . boxGui.Hwnd)) {
            WinGetPos(&gx, &gy, , , "ahk_id " . boxGui.Hwnd)
            if (gx != curX || gy != curY) {
                curX := gx, curY := gy
                isSliderUpdating := true
                try {
                    sldX.Value := curX, lblX.Value := curX " px"
                    sldY.Value := curY, lblY.Value := curY " px"
                }
                isSliderUpdating := false
                TestColorDetect()
            }
        }
    }
    
    ReSampleColor() {
        try boxGui.Hide()
        Sleep(60)
        targetColor := GetDominantColor(curX, curY, curW, curH)
        try ShowBoxGui(boxGui, curX, curY, curW, curH)
        
        isUserTyping := true
        try editColor.Value := targetColor
        isUserTyping := false
        SetSwatchColor(targetColor)
        TestColorDetect()
    }
    btnSample.OnEvent("Click", (*) => ReSampleColor())
    
    OnRedrawRegionSelected(nx, ny, nw, nh) {
        curX := nx, curY := ny, curW := nw, curH := nh
        isSliderUpdating := true
        try {
            sldX.Value := curX, lblX.Value := curX " px"
            sldY.Value := curY, lblY.Value := curY " px"
            sldW.Value := curW, lblW.Value := curW " px"
            sldH.Value := curH, lblH.Value := curH " px"
        }
        isSliderUpdating := false
        
        ShowBoxGui(boxGui, curX, curY, curW, curH)
        ctrlDlg.Show()
        
        try boxGui.Hide()
        Sleep(60)
        targetColor := GetDominantColor(curX, curY, curW, curH)
        try ShowBoxGui(boxGui, curX, curY, curW, curH)
        
        isUserTyping := true
        try editColor.Value := targetColor
        isUserTyping := false
        SetSwatchColor(targetColor)
        TestColorDetect()
    }
    
    RedrawBox() {
        try boxGui.Hide()
        try ctrlDlg.Hide()
        SelectScreenRegion(OnRedrawRegionSelected)
    }
    btnRedraw.OnEvent("Click", (*) => RedrawBox())
    
    CloseColorDialog(params*) {
        global ActiveColorEditCtrlDlg
        ActiveBoxGuiHwnd := 0
        ActiveColorEditCtrlDlg := ""
        SetTimer(UpdateBoxPosText, 0)
        try boxGui.Destroy()
        try ctrlDlg.Destroy()
    }
    
    OnSaveColorEdit() {
        step.x := curX
        step.y := curY
        step.w := curW
        step.h := curH
        step.color := targetColor
        step.clickCenterX := Integer(curX + curW/2)
        step.clickCenterY := Integer(curY + curH/2)
        step.tolerance := Integer(sldTolerance.Value)
        step.invert := cbInvert.Value ? 1 : 0
        
        step.actionType := Integer(sldActionType.Value)
        step.pressKey := pressPicker.GetValue()
        
        totalHMs := TimeStepToMs(sldHoldTime.Value)
        step.holdMin := totalHMs // 60000
        step.holdSec := (totalHMs - step.holdMin * 60000) // 1000
        
        step.timeoutSec := TimeStepToMs(sldTimeoutSec.Value) // 1000
        step.timeoutKey := timeoutPicker.GetValue()
        step.timeoutMode := Integer(sldTimeoutMode.Value)
        step.jumpStep := Integer(sldJumpStep.Value)
        RefreshMacroListView()
        CloseColorDialog()
    }
    
    btnSave := ctrlDlg.Add("Button", "x15 y600 w350 h38 Background0x008800", "💾 儲存修改內容")
    btnSave.OnEvent("Click", (*) => OnSaveColorEdit())
    ctrlDlg.OnEvent("Close", CloseColorDialog)
    
    TestColorDetect()
    
    dlgX := Min(A_ScreenWidth - 395, curX + curW + 15)
    dlgY := Max(30, Min(A_ScreenHeight - 690, curY))
    if (dlgX + 380 > A_ScreenWidth)
        dlgX := Max(10, curX - 390)
        
    ctrlDlg.Show("X" dlgX " Y" dlgY " W380 H650")
    
    SetTimer(UpdateBoxPosText, 200)
}

; =================================================================
; [動作 2：按鍵發送 PromptEditKeyPress]
; =================================================================
PromptAddKeyPress() {
    global MacroGroups, ActiveEditGroupIdx
    if (ActiveEditGroupIdx < 1 || ActiveEditGroupIdx > MacroGroups.Length)
        return
        
    PromptEditKeyPress({ type: "key_press", key: "Space", holdMs: 80, delayMs: 0, repeat: 1, isNew: true })
}

PromptEditKeyPress(step) {
    global MacroGroups, ActiveEditGroupIdx, ActiveStepEditDlg, IsAlwaysOnTop, KeyCategories, TimeStepTable
    isNew := step.HasOwnProp("isNew") && step.isNew
    
    if (ActiveStepEditDlg != "") {
        try {
            if WinExist("ahk_id " . ActiveStepEditDlg.Hwnd) {
                WinActivate("ahk_id " . ActiveStepEditDlg.Hwnd)
                return
            }
        }
        ActiveStepEditDlg := ""
    }
    
    ownerHwnd := GetMacroEditGuiHwnd()
    ownerOpt := (ownerHwnd > 0) ? (" +Owner" . ownerHwnd) : ""
    
    dlg := Gui("-MaximizeBox" . ownerOpt . " +AlwaysOnTop", isNew ? "⌨️ 增加按鍵發送動作" : "⌨️ 編輯按鍵發送動作")
    dlg.BackColor := "0x1A1A1A"
    dlg.SetFont("s10 bold cWhite", "Microsoft JhengHei")
    ActiveStepEditDlg := dlg
    
    curKey := step.HasOwnProp("key") ? step.key : "Space"
    curHoldMs := step.HasOwnProp("holdMs") ? step.holdMs : 80
    curDelayMs := step.HasOwnProp("delayMs") ? step.delayMs : 0
    curRepeat := step.HasOwnProp("repeat") ? step.repeat : 1
    
    keyPicker := AttachKeyCategoryPicker(dlg, 14, curKey, false)
    
    ; 按住時間拉桿 (最久 10 分鐘，毫秒 ➔ 秒 ➔ 分 步進)
    holdY := 84
    initHoldStep := MsToTimeStep(curHoldMs, HoldTimeTable)
    dlg.Add("Text", "x20 y" holdY " w90 h22 cWhite", "按住時間:")
    lblHold := dlg.Add("Text", "x110 y" holdY " w200 h22 c0x00FFFF", FormatDurationText(curHoldMs))
    sldHold := dlg.Add("Slider", "x20 y" (holdY + 22) " w325 h26 Range1-" HoldTimeTable.Length " Thick20 Tooltip AltSubmit", initHoldStep)
    sldHold.OnEvent("Change", (ctrl, *) => (
        lblHold.Value := FormatDurationText(TimeStepToMs(ctrl.Value, HoldTimeTable))
    ))
    
    ; 完成後延遲拉桿 (最久 1 分鐘，毫秒 ➔ 秒 步進)
    delayY := holdY + 52
    initDelayStep := MsToTimeStep(curDelayMs, DelayTimeTable)
    dlg.Add("Text", "x20 y" delayY " w90 h22 cWhite", "完成延遲:")
    lblDelay := dlg.Add("Text", "x110 y" delayY " w200 h22 c0x00FFFF", FormatDurationText(curDelayMs))
    sldDelay := dlg.Add("Slider", "x20 y" (delayY + 22) " w325 h26 Range1-" DelayTimeTable.Length " Thick20 Tooltip AltSubmit", initDelayStep)
    sldDelay.OnEvent("Change", (ctrl, *) => (
        lblDelay.Value := FormatDurationText(TimeStepToMs(ctrl.Value, DelayTimeTable))
    ))
    
    ; 連續重複次數拉桿 (0 = 無限次)
    repY := delayY + 52
    dlg.Add("Text", "x20 y" repY " w110 h22 cWhite", "連續重複次數:")
    lblRep := dlg.Add("Text", "x130 y" repY " w150 h22 c0x00FFFF", (curRepeat == 0) ? "無限次 (∞)" : (curRepeat . " 次"))
    sldRep := dlg.Add("Slider", "x20 y" (repY + 22) " w325 h26 Range0-99 Thick20 Tooltip AltSubmit", curRepeat)
    sldRep.OnEvent("Change", (ctrl, *) => (
        lblRep.Value := (ctrl.Value == 0) ? "無限次 (∞)" : (ctrl.Value . " 次")
    ))
    
    CloseKeyDlg(params*) {
        global ActiveStepEditDlg
        ActiveStepEditDlg := ""
        try dlg.Destroy()
    }
    
    btnY := repY + 58
    if isNew {
        btnConfirm := dlg.Add("Button", "x20 y" btnY " w325 h38 Background0x008800", "✅ 確認新增按鍵動作")
        btnConfirm.OnEvent("Click", (*) => OnConfirmNewKey())
        
        OnConfirmNewKey(params*) {
            kName := keyPicker.GetValue() != "" ? keyPicker.GetValue() : "Space"
            hMs := TimeStepToMs(sldHold.Value, HoldTimeTable)
            dMs := TimeStepToMs(sldDelay.Value, DelayTimeTable)
            rCnt := Integer(sldRep.Value)
            MacroGroups[ActiveEditGroupIdx].steps.Push({ type: "key_press", key: kName, holdMs: hMs, delayMs: dMs, repeat: rCnt })
            RefreshMacroListView()
            CloseKeyDlg()
        }
    } else {
        btnSaveK := dlg.Add("Button", "x20 y" btnY " w155 h38 Background0x006600", "💾 儲存修改")
        btnSaveK.OnEvent("Click", (*) => OnSaveKeyEdit())
        
        OnSaveKeyEdit(params*) {
            step.key := keyPicker.GetValue() != "" ? keyPicker.GetValue() : "Space"
            step.holdMs := TimeStepToMs(sldHold.Value, HoldTimeTable)
            step.delayMs := TimeStepToMs(sldDelay.Value, DelayTimeTable)
            step.repeat := Integer(sldRep.Value)
            RefreshMacroListView()
            CloseKeyDlg()
        }
        
        btnAddK := dlg.Add("Button", "x185 y" btnY " w160 h38 Background0x005588", "➕ 另存新步驟")
        btnAddK.OnEvent("Click", (*) => OnSaveNewStep())
        
        OnSaveNewStep(params*) {
            kName := keyPicker.GetValue() != "" ? keyPicker.GetValue() : "Space"
            hMs := TimeStepToMs(sldHold.Value, HoldTimeTable)
            dMs := TimeStepToMs(sldDelay.Value, DelayTimeTable)
            rCnt := Integer(sldRep.Value)
            MacroGroups[ActiveEditGroupIdx].steps.Push({ type: "key_press", key: kName, holdMs: hMs, delayMs: dMs, repeat: rCnt })
            RefreshMacroListView()
            CloseKeyDlg()
        }
    }
    dlg.OnEvent("Close", (*) => CloseKeyDlg())
    
    dlg.Show("w365 h" (btnY + 52))
}

; =================================================================
; [動作 3：純等待 PromptEditWait]
; =================================================================
PromptAddWait() {
    global MacroGroups, ActiveEditGroupIdx
    if (ActiveEditGroupIdx < 1 || ActiveEditGroupIdx > MacroGroups.Length)
        return
        
    PromptEditWait({ type: "wait", waitMs: 2000, isNew: true })
}

PromptEditWait(step) {
    global MacroGroups, ActiveEditGroupIdx, ActiveStepEditDlg, IsAlwaysOnTop, TimeStepTable
    isNew := step.HasOwnProp("isNew") && step.isNew
    
    if (ActiveStepEditDlg != "") {
        try {
            if WinExist("ahk_id " . ActiveStepEditDlg.Hwnd) {
                WinActivate("ahk_id " . ActiveStepEditDlg.Hwnd)
                return
            }
        }
        ActiveStepEditDlg := ""
    }
    
    ownerHwnd := GetMacroEditGuiHwnd()
    ownerOpt := (ownerHwnd > 0) ? (" +Owner" . ownerHwnd) : ""
    
    dlg := Gui("-MaximizeBox" . ownerOpt . " +AlwaysOnTop", isNew ? "⏱ 增加等待秒數動作" : "⏱ 編輯等待秒數動作")
    dlg.BackColor := "0x1A1A1A"
    dlg.SetFont("s10 bold cWhite", "Microsoft JhengHei")
    ActiveStepEditDlg := dlg
    
    initWaitStep := MsToTimeStep(step.waitMs)
    dlg.Add("Text", "x20 y20 w90 h25 cWhite", "等待時間:")
    lblWait := dlg.Add("Text", "x110 y20 w170 h25 c0x00FFFF", FormatDurationText(step.waitMs))
    sldWait := dlg.Add("Slider", "x20 y50 w260 h30 Range1-" TimeStepTable.Length " Thick20 Tooltip AltSubmit", initWaitStep)
    sldWait.OnEvent("Change", (ctrl, *) => (
        lblWait.Value := FormatDurationText(TimeStepToMs(ctrl.Value))
    ))
    
    CloseWaitDlg(params*) {
        global ActiveStepEditDlg
        ActiveStepEditDlg := ""
        try dlg.Destroy()
    }
    
    btnConfirm := dlg.Add("Button", "x20 y95 w260 h35 Background0x008800", isNew ? "確認新增等待" : "確認儲存等待修改")
    btnConfirm.OnEvent("Click", (*) => (
        step.waitMs := TimeStepToMs(sldWait.Value),
        isNew ? MacroGroups[ActiveEditGroupIdx].steps.Push(step) : 0,
        RefreshMacroListView(),
        CloseWaitDlg()
    ))
    dlg.OnEvent("Close", CloseWaitDlg)
    
    dlg.Show("w300 h145")
}
    
; =================================================================
; [動作 4：步驟內循環轉向控制 (Loop Goto Step)]
; =================================================================
PromptAddLoopGoto() {
    global MacroGroups, ActiveEditGroupIdx
    if (ActiveEditGroupIdx < 1 || ActiveEditGroupIdx > MacroGroups.Length)
        return
        
    PromptEditLoopGoto({ type: "loop_goto", targetStep: 1, maxLoops: 5, isNew: true })
}

PromptEditLoopGoto(step) {
    global MacroGroups, ActiveEditGroupIdx, ActiveStepEditDlg, IsAlwaysOnTop
    isNew := step.HasOwnProp("isNew") && step.isNew
    
    if (ActiveStepEditDlg != "") {
        try {
            if WinExist("ahk_id " . ActiveStepEditDlg.Hwnd) {
                WinActivate("ahk_id " . ActiveStepEditDlg.Hwnd)
                return
            }
        }
        ActiveStepEditDlg := ""
    }
    
    ownerHwnd := GetMacroEditGuiHwnd()
    ownerOpt := (ownerHwnd > 0) ? (" +Owner" . ownerHwnd) : ""
    
    dlg := Gui("-MaximizeBox" . ownerOpt . " +AlwaysOnTop", isNew ? "🔁 增加步驟循環轉向動作" : "🔁 編輯步驟循環轉向動作")
    dlg.BackColor := "0x1A1A1A"
    dlg.SetFont("s10 bold cWhite", "Microsoft JhengHei")
    ActiveStepEditDlg := dlg
    
    maxSteps := (ActiveEditGroupIdx <= MacroGroups.Length) ? Max(1, MacroGroups[ActiveEditGroupIdx].steps.Length) : 1
    curTarget := step.HasOwnProp("targetStep") ? Min(maxSteps, Max(1, step.targetStep)) : 1
    curLoops := step.HasOwnProp("maxLoops") ? step.maxLoops : 5
    
    dlg.Add("Text", "x20 y18 w140 h25 cWhite", "返回目標步驟號:")
    lblTarget := dlg.Add("Text", "x160 y18 w140 h25 c0x00FFFF", "第 " curTarget " 步")
    sldTarget := dlg.Add("Slider", "x20 y45 w280 h30 Range1-" maxSteps " Thick20 Tooltip AltSubmit", curTarget)
    sldTarget.OnEvent("Change", (ctrl, *) => (
        lblTarget.Value := "第 " ctrl.Value " 步"
    ))
    
    dlg.Add("Text", "x20 y85 w140 h25 cWhite", "重複返回循環次數:")
    lblLoops := dlg.Add("Text", "x160 y85 w140 h25 c0x00FFFF", (curLoops == 0) ? "無限次 (∞)" : (curLoops . " 次"))
    sldLoops := dlg.Add("Slider", "x20 y112 w280 h30 Range0-999 Thick20 Tooltip AltSubmit", curLoops)
    sldLoops.OnEvent("Change", (ctrl, *) => (
        lblLoops.Value := (ctrl.Value == 0) ? "無限次 (∞)" : (ctrl.Value . " 次")
    ))
    
    dlg.Add("Text", "x20 y150 w280 h38 c0x888888", "說明: 執行到此步驟時會跳轉回指定步驟，累積指定次數後即會自動通過推進至下一步。")
    
    CloseLoopGotoDlg(params*) {
        global ActiveStepEditDlg
        ActiveStepEditDlg := ""
        try dlg.Destroy()
    }
    
    btnConfirm := dlg.Add("Button", "x20 y195 w280 h38 Background0x008800", isNew ? "確認新增步驟循環" : "確認儲存循環修改")
    btnConfirm.OnEvent("Click", (*) => (
        step.targetStep := Integer(sldTarget.Value),
        step.maxLoops := Integer(sldLoops.Value),
        isNew ? MacroGroups[ActiveEditGroupIdx].steps.Push(step) : 0,
        RefreshMacroListView(),
        CloseLoopGotoDlg()
    ))
    dlg.OnEvent("Close", CloseLoopGotoDlg)
    
    dlg.Show("w320 h248")
}

; =================================================================
; [設定檔 INI 讀取與儲存]
; =================================================================
SaveMacroConfig(targetPath := "") {
    global MacroGroups, ConfigFile, IsAlwaysOnTop
    saveFile := (targetPath != "") ? targetPath : ConfigFile
    try FileDelete(saveFile)
    
    IniWrite(MacroGroups.Length, saveFile, "General", "GroupCount")
    IniWrite(IsAlwaysOnTop ? 1 : 0, saveFile, "General", "AlwaysOnTop")
    
    for gIdx, grp in MacroGroups {
        grpSec := "Group_" . gIdx
        IniWrite(grp.name, saveFile, grpSec, "Name")
        IniWrite(grp.icon, saveFile, grpSec, "Icon")
        IniWrite(grp.HasOwnProp("visible") ? grp.visible : 1, saveFile, grpSec, "Visible")
        IniWrite(grp.loopCount, saveFile, grpSec, "LoopCount")
        IniWrite(grp.steps.Length, saveFile, grpSec, "StepCount")
        
        for sIdx, step in grp.steps {
            sSec := "Group_" . gIdx . "_Step_" . sIdx
            IniWrite(step.type, saveFile, sSec, "Type")
            if (step.type == "color_detect") {
                IniWrite(step.x, saveFile, sSec, "X")
                IniWrite(step.y, saveFile, sSec, "Y")
                IniWrite(step.w, saveFile, sSec, "W")
                IniWrite(step.h, saveFile, sSec, "H")
                IniWrite(step.color, saveFile, sSec, "Color")
                IniWrite(step.clickCenterX, saveFile, sSec, "CenterX")
                IniWrite(step.clickCenterY, saveFile, sSec, "CenterY")
                IniWrite(step.HasOwnProp("tolerance") ? step.tolerance : 20, saveFile, sSec, "Tolerance")
                IniWrite(step.HasOwnProp("invert") ? step.invert : 0, saveFile, sSec, "Invert")
                
                IniWrite(step.HasOwnProp("actionType") ? step.actionType : 0, saveFile, sSec, "ActionType")
                IniWrite(step.HasOwnProp("pressKey") ? step.pressKey : "Space", saveFile, sSec, "PressKey")
                IniWrite(step.HasOwnProp("holdMin") ? step.holdMin : 0, saveFile, sSec, "HoldMin")
                IniWrite(step.HasOwnProp("holdSec") ? step.holdSec : 0, saveFile, sSec, "HoldSec")
                
                IniWrite(step.HasOwnProp("timeoutSec") ? step.timeoutSec : 0, saveFile, sSec, "TimeoutSec")
                IniWrite(step.HasOwnProp("timeoutKey") ? step.timeoutKey : "", saveFile, sSec, "TimeoutKey")
                IniWrite(step.HasOwnProp("timeoutMode") ? step.timeoutMode : 1, saveFile, sSec, "TimeoutMode")
                IniWrite(step.HasOwnProp("jumpStep") ? step.jumpStep : 1, saveFile, sSec, "JumpStep")
            } else if (step.type == "key_press") {
                IniWrite(step.HasOwnProp("key") ? step.key : "Space", saveFile, sSec, "Key")
                IniWrite(step.HasOwnProp("holdMs") ? step.holdMs : 80, saveFile, sSec, "HoldMs")
                IniWrite(step.HasOwnProp("delayMs") ? step.delayMs : 0, saveFile, sSec, "DelayMs")
                IniWrite(step.HasOwnProp("repeat") ? step.repeat : 1, saveFile, sSec, "Repeat")
            } else if (step.type == "wait") {
                IniWrite(step.waitMs, saveFile, sSec, "WaitMs")
            } else if (step.type == "loop_goto") {
                IniWrite(step.HasOwnProp("targetStep") ? step.targetStep : 1, saveFile, sSec, "TargetStep")
                IniWrite(step.HasOwnProp("maxLoops") ? step.maxLoops : 1, saveFile, sSec, "MaxLoops")
            }
        }
    }
}

LoadMacroConfig(targetPath := "") {
    global MacroGroups, ConfigFile, IsAlwaysOnTop
    loadFile := (targetPath != "") ? targetPath : ConfigFile
    if !FileExist(loadFile)
        return false
        
    try {
        grpCount := Integer(IniRead(loadFile, "General", "GroupCount", "0"))
        if (grpCount <= 0)
            return false
            
        IsAlwaysOnTop := Integer(IniRead(loadFile, "General", "AlwaysOnTop", "1")) != 0
        loadedGroups := []
        Loop grpCount {
            gIdx := A_Index
            grpSec := "Group_" . gIdx
            grpName := IniRead(loadFile, grpSec, "Name", "群組 " . gIdx)
            grpIcon := IniRead(loadFile, grpSec, "Icon", "⚔️")
            grpVis := Integer(IniRead(loadFile, grpSec, "Visible", "1"))
            grpLoop := Integer(IniRead(loadFile, grpSec, "LoopCount", "1"))
            stepCount := Integer(IniRead(loadFile, grpSec, "StepCount", "0"))
            
            steps := []
            Loop stepCount {
                sIdx := A_Index
                sSec := "Group_" . gIdx . "_Step_" . sIdx
                sType := IniRead(loadFile, sSec, "Type", "")
                if (sType == "color_detect") {
                    steps.Push({
                        type: "color_detect",
                        x: Integer(IniRead(loadFile, sSec, "X", "0")),
                        y: Integer(IniRead(loadFile, sSec, "Y", "0")),
                        w: Integer(IniRead(loadFile, sSec, "W", "0")),
                        h: Integer(IniRead(loadFile, sSec, "H", "0")),
                        color: IniRead(loadFile, sSec, "Color", "0xFFFFFF"),
                        clickCenterX: Integer(IniRead(loadFile, sSec, "CenterX", "0")),
                        clickCenterY: Integer(IniRead(loadFile, sSec, "CenterY", "0")),
                        tolerance: Integer(IniRead(loadFile, sSec, "Tolerance", "20")),
                        invert: Integer(IniRead(loadFile, sSec, "Invert", "0")),
                        actionType: Integer(IniRead(loadFile, sSec, "ActionType", "0")),
                        pressKey: IniRead(loadFile, sSec, "PressKey", "Space"),
                        holdMin: Integer(IniRead(loadFile, sSec, "HoldMin", "0")),
                        holdSec: Integer(IniRead(loadFile, sSec, "HoldSec", "0")),
                        timeoutSec: Integer(IniRead(loadFile, sSec, "TimeoutSec", "0")),
                        timeoutKey: IniRead(loadFile, sSec, "TimeoutKey", ""),
                        timeoutMode: Integer(IniRead(loadFile, sSec, "TimeoutMode", "1")),
                        jumpStep: Integer(IniRead(loadFile, sSec, "JumpStep", "1"))
                    })
                } else if (sType == "key_press") {
                    steps.Push({
                        type: "key_press",
                        key: IniRead(loadFile, sSec, "Key", "Space"),
                        holdMs: Integer(IniRead(loadFile, sSec, "HoldMs", "80")),
                        delayMs: Integer(IniRead(loadFile, sSec, "DelayMs", "0")),
                        repeat: Integer(IniRead(loadFile, sSec, "Repeat", "1"))
                    })
                } else if (sType == "wait") {
                    steps.Push({
                        type: "wait",
                        waitMs: Integer(IniRead(loadFile, sSec, "WaitMs", "1000"))
                    })
                } else if (sType == "loop_goto") {
                    steps.Push({
                        type: "loop_goto",
                        targetStep: Integer(IniRead(loadFile, sSec, "TargetStep", "1")),
                        maxLoops: Integer(IniRead(loadFile, sSec, "MaxLoops", "5"))
                    })
                }
            }
            
            loadedGroups.Push({
                name: grpName,
                icon: grpIcon,
                visible: grpVis,
                loopCount: grpLoop,
                steps: steps
            })
        }
        
        if (loadedGroups.Length > 0) {
            MacroGroups := loadedGroups
            return true
        }
    }
    return false
}

ImportMacroConfig() {
    global ActiveEditGroupIdx
    selectedFile := FileSelect(1, A_ScriptDir, "📥 選擇要匯入的巨集 INI 設定檔", "INI 設定檔 (*.ini)")
    if (selectedFile == "")
        return
        
    if LoadMacroConfig(selectedFile) {
        ActiveEditGroupIdx := 1
        SaveMacroConfig()
        BuildMainGui()
        RebuildMacroEditGui()
        MsgBox("🟢 成功匯入 INI 巨集設定！`n已載入 " . MacroGroups.Length . " 個群組設定資料。", "匯入成功", "262192")
    } else {
        MsgBox("❌ 匯入失敗！`n所選 INI 檔案格式無效或未包含巨集群組與步驟資料。", "匯入錯誤", "262192")
    }
}

ExportMacroConfig() {
    selectedFile := FileSelect(16, A_ScriptDir . "\macro_backup.ini", "📤 選擇巨集 INI 匯出備份位置", "INI 設定檔 (*.ini)")
    if (selectedFile == "")
        return
        
    if !RegExMatch(selectedFile, "(?i)\.ini$")
        selectedFile .= ".ini"
        
    SaveMacroConfig(selectedFile)
    MsgBox("🟢 成功將巨集設定匯出至：`n" . selectedFile, "匯出成功", "262192")
}

; =================================================================
; [多群組獨立巨集執行引擎 (Per-Group Macro Runner)]
; =================================================================
ToggleGroupExecution(groupIdx) {
    global RunningGroupIdx
    if (RunningGroupIdx == groupIdx) {
        StopMacro()
    } else {
        StartGroupMacro(groupIdx)
    }
}

StartGroupMacro(groupIdx) {
    global RunningGroupIdx, StopMacroRequested, MacroGroups, ProgressPic, MyGui, GuiX, GuiY, GuiH, GuiOpacity, ProgressBarWidth
    
    if (groupIdx < 1 || groupIdx > MacroGroups.Length)
        return
        
    grp := MacroGroups[groupIdx]
    if (grp.steps.Length == 0) {
        MsgBox("群組【" grp.name "】的步驟清單為空！請點擊 ⚙ (齒輪圖示) 新增動作。", "提示", "262192")
        return
    }
    
    if (RunningGroupIdx > 0) {
        StopMacro()
        Sleep(100)
    }
    
    RunningGroupIdx := groupIdx
    StopMacroRequested := false
    
    UpdateMainGuiButtons()
    
    currX := 38 + (GetVisibleGroupCount() * 35) + 35
    totalW := currX + ProgressBarWidth + 5
    
    ProgressPic.Visible := true
    MyGui.Show("X" GuiX " Y" GuiY " W" totalW " H" GuiH " NoActivate")
    
    SetTimer(() => RunGroupMacroLoop(groupIdx), -10)
}

StopMacro() {
    global RunningGroupIdx, StopMacroRequested, ProgressPic, MyGui, GuiX, GuiY, GuiH, GuiOpacity, MacroGroups
    RunningGroupIdx := 0
    StopMacroRequested := true
    
    UpdateMainGuiButtons()
    
    if (ProgressPic)
        ProgressPic.Visible := false
        
    if (MyGui != "") {
        try {
            if WinExist("ahk_id " . MyGui.Hwnd) {
                currX := 38 + (GetVisibleGroupCount() * 35) + 35
                MyGui.Show("X" GuiX " Y" GuiY " W" currX " H" GuiH " NoActivate")
            }
        }
    }
}

RunGroupMacroLoop(groupIdx) {
    global RunningGroupIdx, StopMacroRequested, MacroGroups
    CoordMode("Pixel", "Screen")
    CoordMode("Mouse", "Screen")
    
    if (groupIdx < 1 || groupIdx > MacroGroups.Length)
        return
        
    grp := MacroGroups[groupIdx]
    curLoop := 1
    totalLoops := grp.loopCount
    totalLoopsStr := (totalLoops == 0) ? "∞" : totalLoops
    steps := grp.steps
    loopCounters := Map()
    
    while ((totalLoops == 0 || curLoop <= totalLoops) && !StopMacroRequested && RunningGroupIdx == groupIdx) {
        sIdx := 1
        while (sIdx <= steps.Length && !StopMacroRequested && RunningGroupIdx == groupIdx) {
            step := steps[sIdx]
            
            stepPct := (sIdx / steps.Length) * 100
            totalPct := (totalLoops == 0) ? 100 : ((curLoop / totalLoops) * 100)
            
            if (step.type == "color_detect") {
                tolVal := step.HasOwnProp("tolerance") ? step.tolerance : 20
                isInverted := step.HasOwnProp("invert") && step.invert
                
                actionType := step.HasOwnProp("actionType") ? step.actionType : 0
                pressKey := step.HasOwnProp("pressKey") ? step.pressKey : "Space"
                holdMin := step.HasOwnProp("holdMin") ? step.holdMin : 0
                holdSec := step.HasOwnProp("holdSec") ? step.holdSec : 0
                holdMs := (holdMin * 60 + holdSec) * 1000
                
                timeoutSec := step.HasOwnProp("timeoutSec") ? step.timeoutSec : 0
                timeoutKey := step.HasOwnProp("timeoutKey") ? step.timeoutKey : ""
                timeoutMode := step.HasOwnProp("timeoutMode") ? step.timeoutMode : 1
                jumpStep := step.HasOwnProp("jumpStep") ? step.jumpStep : 1
                
                invText := isInverted ? " (反向:未發現才點擊)" : ""
                toText := (timeoutSec > 0) ? Format(" [逾時:{}]", FormatDurationText(timeoutSec * 1000)) : ""
                statusText := Format("{} {} | Loop [{}/{}] Step [{}/{}]: 偵測顏色 {}{}{}...", 
                    grp.icon, grp.name, curLoop, totalLoopsStr, sIdx, steps.Length, step.color, invText, toText)
                RenderProgressBarBitmap(stepPct, totalPct, statusText)
                
                foundColor := false
                startTime := A_TickCount
                timeoutMs := timeoutSec * 1000
                
                loop {
                    if (StopMacroRequested || RunningGroupIdx != groupIdx)
                        break
                        
                    foundColor := false
                    try {
                        colorList := StrSplit(step.color, ",")
                        for cItem in colorList {
                            cTrim := Trim(cItem)
                            if (cTrim != "") {
                                if PixelSearch(&foundX, &foundY, step.x, step.y, step.x + step.w, step.y + step.h, cTrim, tolVal) {
                                    foundColor := true
                                    break
                                }
                            }
                        }
                    }
                    
                    isMatch := isInverted ? !foundColor : foundColor
                    if (isMatch) {
                        ; 1. 點擊中心點 (若 0:僅點擊 或 2:點擊+按鍵)
                        if (actionType == 0 || actionType == 2) {
                            if (isInverted) {
                                if (!foundColor && step.clickCenterX > 0)
                                    Click(step.clickCenterX, step.clickCenterY)
                            } else {
                                if (foundColor)
                                    Click(foundX, foundY)
                                else if (step.clickCenterX > 0)
                                    Click(step.clickCenterX, step.clickCenterY)
                            }
                        }
                        
                        ; 2. 發送按鍵與按住 (若 1:僅按鍵 或 2:點擊+按鍵)
                        if (actionType == 1 || actionType == 2) {
                            if (pressKey != "") {
                                Send("{" pressKey " down}")
                                if (holdMs > 0) {
                                    SleepInterruptible(holdMs)
                                } else {
                                    Sleep(100)
                                }
                                Send("{" pressKey " up}")
                            }
                        }
                        
                        Sleep(200)
                        break ; 成功匹配，結束本步驟
                    }
                    
                    ; 若已超過逾時時間且已設定逾時 > 0
                    if (timeoutMs > 0 && (A_TickCount - startTime >= timeoutMs)) {
                        statusText := Format("{} {} | Loop [{}/{}] Step [{}/{}]: ⚠️ 步驟逾時！執行處置...", grp.icon, grp.name, curLoop, totalLoopsStr, sIdx, steps.Length)
                        RenderProgressBarBitmap(stepPct, totalPct, statusText)
                        
                        ; 1. 逾時發送按鍵 (若有)
                        if (timeoutKey != "") {
                            Send("{" timeoutKey " down}")
                            Sleep(100)
                            Send("{" timeoutKey " up}")
                            Sleep(200)
                        }
                        
                        ; 2. 執行逾時處置模式
                        if (timeoutMode == 0) {
                            ; 0: 重試 (Retry)
                            startTime := A_TickCount
                            Sleep(200)
                            continue
                        } else if (timeoutMode == 1) {
                            ; 1: 下一步 (Next Step)
                            break
                        } else if (timeoutMode == 2) {
                            ; 2: 返回指定步驟 (Jump to step N)
                            sIdx := Max(1, Min(steps.Length, jumpStep)) - 1
                            break
                        }
                    }
                    
                    ; 若未設定逾時 (timeoutSec == 0)，執行一次檢測無結果後直接離開推進
                    if (timeoutMs == 0) {
                        break
                    }
                    
                    Sleep(100)
                }
                
            } else if (step.type == "key_press") {
                keyName := step.HasOwnProp("key") ? step.key : "Space"
                holdMs := step.HasOwnProp("holdMs") ? step.holdMs : 80
                delayMs := step.HasOwnProp("delayMs") ? step.delayMs : 0
                repeatCount := step.HasOwnProp("repeat") ? step.repeat : 1
                isInfiniteRep := (repeatCount == 0)
                
                repIdx := 1
                while (!StopMacroRequested && RunningGroupIdx == groupIdx && (isInfiniteRep || repIdx <= repeatCount)) {
                    repText := isInfiniteRep ? Format(" ({}/∞)", repIdx) : ((repeatCount > 1) ? Format(" ({}/{})", repIdx, repeatCount) : "")
                    holdInfo := (holdMs > 0) ? (" (按住 " . FormatDurationText(holdMs) . ")") : ""
                    statusText := Format("{} {} | Loop [{}/{}] Step [{}/{}]: 按鍵 '{}'{}{}", grp.icon, grp.name, curLoop, totalLoopsStr, sIdx, steps.Length, keyName, holdInfo, repText)
                    RenderProgressBarBitmap(stepPct, totalPct, statusText)
                    
                    Send("{" keyName " down}")
                    if (holdMs > 0)
                        SleepInterruptible(holdMs)
                    Send("{" keyName " up}")
                    
                    if (delayMs > 0) {
                        statusText := Format("{} {} | Loop [{}/{}] Step [{}/{}]: 延遲 {}...", grp.icon, grp.name, curLoop, totalLoopsStr, sIdx, steps.Length, FormatDurationText(delayMs))
                        RenderProgressBarBitmap(stepPct, totalPct, statusText)
                        SleepInterruptible(delayMs)
                    }
                    repIdx++
                }
                
            } else if (step.type == "wait") {
                statusText := Format("{} {} | Loop [{}/{}] Step [{}/{}]: 等待 {}...", grp.icon, grp.name, curLoop, totalLoopsStr, sIdx, steps.Length, FormatDurationText(step.waitMs))
                RenderProgressBarBitmap(stepPct, totalPct, statusText)
                SleepInterruptible(step.waitMs)
            } else if (step.type == "loop_goto") {
                targetS := step.HasOwnProp("targetStep") ? Max(1, Min(steps.Length, step.targetStep)) : 1
                maxL := step.HasOwnProp("maxLoops") ? step.maxLoops : 1
                
                currRunCount := loopCounters.Has(sIdx) ? loopCounters[sIdx] : 0
                if (maxL == 0) {
                    loopCounters[sIdx] := currRunCount + 1
                    statusText := Format("{} {} | Loop [{}/{}] Step [{}/{}]: 🔁 轉向跳轉至第 {} 步 ({}/∞)", grp.icon, grp.name, curLoop, totalLoopsStr, sIdx, steps.Length, targetS, currRunCount + 1)
                    RenderProgressBarBitmap(stepPct, totalPct, statusText)
                    Sleep(150)
                    sIdx := targetS - 1
                } else if (currRunCount < maxL) {
                    loopCounters[sIdx] := currRunCount + 1
                    statusText := Format("{} {} | Loop [{}/{}] Step [{}/{}]: 🔁 轉向跳轉至第 {} 步 ({}/{})", grp.icon, grp.name, curLoop, totalLoopsStr, sIdx, steps.Length, targetS, currRunCount + 1, maxL)
                    RenderProgressBarBitmap(stepPct, totalPct, statusText)
                    Sleep(150)
                    sIdx := targetS - 1 ; 跳轉至目標步驟 (迴圈末會 sIdx++)
                } else {
                    loopCounters[sIdx] := 0 ; 滿次解鎖並重置計數器，推進至下一步
                    statusText := Format("{} {} | Loop [{}/{}] Step [{}/{}]: 🔁 轉向次數已滿 ({}/{})，推進下一步", grp.icon, grp.name, curLoop, totalLoopsStr, sIdx, steps.Length, maxL, maxL)
                    RenderProgressBarBitmap(stepPct, totalPct, statusText)
                    Sleep(150)
                }
            }
            sIdx++
        }
        curLoop++
    }
    
    if (RunningGroupIdx == groupIdx) {
        StopMacro()
        if (!StopMacroRequested) {
            SoundBeep(1000, 200)
        }
    }
}

SleepInterruptible(ms) {
    global StopMacroRequested
    start := A_TickCount
    while ((A_TickCount - start < ms) && !StopMacroRequested) {
        Sleep(20)
    }
}

; =================================================================
; [腳本初始化進入點 Initialization]
; =================================================================
LoadMacroConfig()
InitDefaultGroups()
BuildMainGui()
