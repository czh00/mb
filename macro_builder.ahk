; =================================================================
; MacroBuilder (MB) v1.0.0
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

; === 系統管理員權限提升與容錯備援 (若關閉 UAC 或拒絕授權仍能繼續運行) ===
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

; 主懸浮 UI 變數與 Z 軸置頂控制
global MyGui := ""
global IsAlwaysOnTop := true     ; 預設允許使用者自由切換 Z 軸置頂狀態
global GuiX := 0, GuiY := 0, GuiH := 34, GuiOpacity := 240
global ProgressBarWidth := 500
global ProgressPic := ""
global hCurrentProgressBmp := 0
global GearBtn := "", PinBtn := "", ExitBtn := ""
global GroupBtns := []          ; 動態群組執行按鈕控制項陣列

; 編輯器 UI 變數
global MacroEditGui := ""
global GroupTabCtrls := []
global MacroLV := ""
global LoopCountSlider := "", LoopCountLabel := ""

; 單一編輯視窗唯一性鎖定變數 (Singleton Editor Locks)
global ActiveBoxGuiHwnd := 0
global ActiveColorEditCtrlDlg := ""
global ActiveStepEditDlg := ""

; 豐富彩色 Unicode 圖示矩陣 (Color Segoe UI Emoji)
global IconPresets := [
    "⚔️", "⚡️", "🚗", "🎖️", "🏆",
    "🎰", "⚙️", "🎯", "🛡️", "🔥",
    "💎", "⭐", "🚀", "👑", "🎮",
    "🔑", "🛠️", "🧭", "🍀", "⏱️"
]

; =================================================================
; [WM_LBUTTONDOWN 點擊圈選框即可自由拖動]
; =================================================================
OnWM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    global ActiveBoxGuiHwnd
    if (ActiveBoxGuiHwnd && hwnd == ActiveBoxGuiHwnd) {
        PostMessage(0xA1, 2, 0, hwnd) ; WM_NCLBUTTONDOWN + HTCAPTION
    }
}
OnMessage(0x0201, OnWM_LBUTTONDOWN)

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

; === 精準視窗位置與尺寸 Helper ===
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
; [主懸浮 UI 建立、Z軸置頂切換與右鍵選單區]
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
; [多群組頁籤 (Tab Card Grid) 矩陣與步驟編輯器 GUI]
; =================================================================
ToggleMacroEditGui() {
    global MacroEditGui, GroupTabCtrls, MacroLV, LoopCountSlider, LoopCountLabel, MacroGroups, ActiveEditGroupIdx, MyGui, IsAlwaysOnTop
    
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
    
    MacroEditGui := Gui("-MaximizeBox" . ownerOpt . topOpt, "⚙ 多群組巨集編輯與頁籤管理介面")
    MacroEditGui.BackColor := "0x121212"
    MacroEditGui.SetFont("s10 bold cWhite", "Segoe UI Emoji")
    MacroEditGui.OnEvent("Close", (*) => (MacroEditGui := ""))
    
    ; 頂部：標題與群組頁籤矩陣
    MacroEditGui.Add("Text", "x15 y12 w400 h22 c0x00FFFF", "📋 選擇巨集群組頁籤 (點擊切換當前群組):")
    
    ; 右上角群組管理按鈕列
    btnAddGrp := MacroEditGui.Add("Button", "x445 y10 w150 h32 Background0x008800", "➕ 新增巨集群組")
    btnAddGrp.OnEvent("Click", (*) => PromptAddGroup())
    
    btnEditGrp := MacroEditGui.Add("Button", "x445 y46 w73 h30 Background0x282828", "✏ 重命名")
    btnEditGrp.OnEvent("Click", (*) => PromptEditGroup())
    
    btnDelGrp := MacroEditGui.Add("Button", "x522 y46 w73 h30 Background0x882222", "🗑 刪除")
    btnDelGrp.OnEvent("Click", (*) => DeleteActiveGroup())
    
    ; 動態多欄頁籤矩陣繪製 (3欄矩陣, 使用 Text +0x200 解放彩色 Emoji 渲染)
    GroupTabCtrls := []
    MakeGroupTabClickFn(tabIdx) {
        return (*) => SwitchActiveGroup(tabIdx)
    }
    
    colCount := 3
    startX := 15, startY := 38
    tabW := 136, tabH := 36, gapX := 7, gapY := 6
    
    for idx, grp in MacroGroups {
        col := Mod(idx - 1, colCount)
        row := (idx - 1) // colCount
        
        tX := startX + col * (tabW + gapX)
        tY := startY + row * (tabH + gapY)
        
        isVis := !grp.HasOwnProp("visible") || grp.visible
        visTag := isVis ? "" : " 🙈"
        
        tabStyle := (idx == ActiveEditGroupIdx) ? "Background0x008800 c0x00FFFF" : (isVis ? "Background0x252525 cWhite" : "Background0x252525 c0x888888")
        btn := MacroEditGui.Add("Text", "x" tX " y" tY " w" tabW " h" tabH " Center +0x200 " tabStyle, grp.icon " " grp.name . visTag)
        btn.OnEvent("Click", MakeGroupTabClickFn(idx))
        
        GroupTabCtrls.Push({ ctrl: btn, idx: idx })
    }
    
    ; 計算頁籤區域高度並擺放步驟 ListView (雙擊可再次編輯步驟)
    maxRow := (MacroGroups.Length > 0) ? ((MacroGroups.Length - 1) // colCount) : 0
    lvY := Max(85, startY + (maxRow + 1) * (tabH + gapY) + 6)
    
    MacroEditGui.SetFont("s10 bold cWhite", "Microsoft JhengHei")
    MacroLV := MacroEditGui.Add("ListView", "x15 y" lvY " w580 h215 Background0x1E1E1E cWhite +Grid -Multi", ["序號", "動作類型", "詳細內容", "執行參數"])
    MacroLV.ModifyCol(1, 50)
    MacroLV.ModifyCol(2, 130)
    MacroLV.ModifyCol(3, 250)
    MacroLV.ModifyCol(4, 135)
    MacroLV.OnEvent("DoubleClick", (*) => EditSelectedStep())
    
    RefreshMacroListView()
    
    ; 動作按鈕列
    actY := lvY + 223
    btnAddColor := MacroEditGui.Add("Button", "x15 y" actY " w125 h35 Background0x282828", "🎯 圈選顏色")
    btnAddColor.OnEvent("Click", (*) => PromptAddColorDetect())
    
    btnAddWait := MacroEditGui.Add("Button", "x145 y" actY " w105 h35 Background0x282828", "⏱ +等待")
    btnAddWait.OnEvent("Click", (*) => PromptAddWait())
    
    btnAddLoopGoto := MacroEditGui.Add("Button", "x255 y" actY " w105 h35 Background0x282828", "🔁 +步驟循環")
    btnAddLoopGoto.OnEvent("Click", (*) => PromptAddLoopGoto())
    
    btnEditStep := MacroEditGui.Add("Button", "x365 y" actY " w65 h35 Background0x006699", "✏ 編輯")
    btnEditStep.OnEvent("Click", (*) => EditSelectedStep())
    
    btnDelStep := MacroEditGui.Add("Button", "x435 y" actY " w60 h35 Background0x882222", "🗑 刪除")
    btnDelStep.OnEvent("Click", (*) => DeleteSelectedStep())
    
    btnUp := MacroEditGui.Add("Button", "x505 y" actY " w40 h35", "▲")
    btnUp.OnEvent("Click", (*) => MoveStep(-1))
    
    btnDown := MacroEditGui.Add("Button", "x550 y" actY " w45 h35", "▼")
    btnDown.OnEvent("Click", (*) => MoveStep(1))
    
    ; 底部：當前群組循環數 Slider 與 匯入/匯出/儲存按鈕
    botY := actY + 45
    curLoop := (ActiveEditGroupIdx <= MacroGroups.Length) ? MacroGroups[ActiveEditGroupIdx].loopCount : 1
    
    MacroEditGui.Add("Text", "x15 y" (botY + 5) " w120 h25 cWhite", "🔁 當前群組循環數:")
    LoopCountLabel := MacroEditGui.Add("Text", "x138 y" (botY + 5) " w55 h25 c0x00FFFF", curLoop . " 次")
    LoopCountSlider := MacroEditGui.Add("Slider", "x195 y" botY " w160 h30 Range1-999 +AltSubmit ToolTip", curLoop)
    LoopCountSlider.OnEvent("Change", (ctrl, *) => (
        (ActiveEditGroupIdx <= MacroGroups.Length) ? (MacroGroups[ActiveEditGroupIdx].loopCount := ctrl.Value) : 0,
        LoopCountLabel.Value := ctrl.Value . " 次"
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
    global ActiveEditGroupIdx, MacroGroups, GroupTabCtrls, LoopCountSlider, LoopCountLabel
    if (idx > 0 && idx <= MacroGroups.Length) {
        ActiveEditGroupIdx := idx
        
        for item in GroupTabCtrls {
            grpObj := MacroGroups[item.idx]
            isVis := !grpObj.HasOwnProp("visible") || grpObj.visible
            if (item.idx == ActiveEditGroupIdx) {
                item.ctrl.Opt("+Background0x008800 +c0x00FFFF")
            } else {
                if (isVis)
                    item.ctrl.Opt("+Background0x252525 +cWhite")
                else
                    item.ctrl.Opt("+Background0x252525 +c0x888888")
            }
        }
        
        RefreshMacroListView()
        if (LoopCountSlider) {
            LoopCountSlider.Value := MacroGroups[idx].loopCount
            LoopCountLabel.Value := MacroGroups[idx].loopCount . " 次"
        }
    }
}

; =================================================================
; [圖示選擇網格 Modal (Grid Picker)]
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
    
    dlg.Add("Text", "x20 y15 w90 h25 cWhite", "群組名稱:")
    nameEdit := dlg.Add("Edit", "x110 y12 w265 h26 Background0x2A2A2A c0x00FFFF", defaultName)
    
    selectedIcon := defaultIcon
    dlg.Add("Text", "x20 y52 w90 h25 cWhite", "選擇圖示:")
    
    dlg.SetFont("s11 bold cWhite", "Segoe UI Emoji")
    selTextCtrl := dlg.Add("Text", "x110 y52 w265 h25 c0x00FFFF", "當前點選: " . selectedIcon)
    
    ; 繪製 4 列 x 5 行 彩色圖示選擇按鈕網格 (使用 Text +0x200 控制項解封彩色 Emoji 渲染)
    iconBtnItems := []
    colCount := 5
    startX := 20, startY := 82
    btnW := 67, btnH := 36, gapX := 7, gapY := 7
    
    MakeIconClickFn(icVal) {
        return (*) => (
            selectedIcon := icVal,
            selTextCtrl.Value := "當前點選: " . selectedIcon,
            UpdateIconGridSelection(iconBtnItems, selectedIcon)
        )
    }
    
    dlg.SetFont("s13 bold cWhite", "Segoe UI Emoji")
    for idx, ic in IconPresets {
        col := Mod(idx - 1, colCount)
        row := (idx - 1) // colCount
        
        btnX := startX + col * (btnW + gapX)
        btnY := startY + row * (btnH + gapY)
        
        btnText := (ic == selectedIcon) ? "✔ " . ic : ic
        btnStyle := (ic == selectedIcon) ? "Background0x008800 c0x00FFFF" : "Background0x282828 cWhite"
        btn := dlg.Add("Text", "x" btnX " y" btnY " w" btnW " h" btnH " Center +0x200 " btnStyle, btnText)
        
        btn.OnEvent("Click", MakeIconClickFn(ic))
        iconBtnItems.Push({ ctrl: btn, icon: ic })
    }
    
    UpdateIconGridSelection(btnList, targetIcon) {
        for item in btnList {
            if (item.icon == targetIcon) {
                item.ctrl.Value := "✔ " . item.icon
                item.ctrl.Opt("+Background0x008800 +c0x00FFFF")
            } else {
                item.ctrl.Value := item.icon
                item.ctrl.Opt("+Background0x282828 +cWhite")
            }
        }
    }
    
    dlg.SetFont("s10 bold cWhite", "Microsoft JhengHei")
    cbVisible := dlg.AddCheckBox("x20 y260 w363 h25 " . (defaultVisible ? "Checked" : ""), "👁 顯示於主懸浮列 (取消勾選則隱藏此群組按鈕)")
    
    btnOK := dlg.Add("Button", "x20 y295 w363 h38 Background0x008800", "確認儲存設定")
    btnOK.OnEvent("Click", (*) => (
        finalName := Trim(nameEdit.Value) != "" ? Trim(nameEdit.Value) : "巨集群組",
        finalVis := cbVisible.Value ? 1 : 0,
        dlg.Destroy(),
        callback.Call(finalName, selectedIcon, finalVis)
    ))
    
    dlg.Show("w403 h350")
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
            
            actTitle := "🎨 顏色偵測" . (invVal ? " (反向)" : "")
            aStr := (aType == 0) ? "點擊" : ((aType == 1) ? Format("按鍵'{}'({}分{}秒)", pKey, hMin, hSec) : Format("點擊+按鍵'{}'({}分{}秒)", pKey, hMin, hSec))
            toModeStr := (toMode == 0) ? "重試" : ((toMode == 1) ? "下一步" : ("返回第" jpStep "步"))
            toInfo := (toSec > 0) ? Format(" | ⏱逾時:{}s[{}]", toSec, toModeStr) : ""
            paramText := Format("動作:{} | 色:{} | 容:{}", aStr, step.color, tolVal) . (invVal ? " | 🚫反向" : "") . toInfo
            MacroLV.Add("", idx, actTitle, "區域: (" step.x "," step.y " W:" step.w " H:" step.h ")", paramText)
        } else if (step.type == "wait") {
            MacroLV.Add("", idx, "⏱ 等待秒數", "純等待延遲", (step.waitMs/1000) " 秒")
        } else if (step.type == "loop_goto") {
            targetS := step.HasOwnProp("targetStep") ? step.targetStep : 1
            maxL := step.HasOwnProp("maxLoops") ? step.maxLoops : 1
            MacroLV.Add("", idx, "🔁 步驟循環控制", Format("返回第 {} 步", targetS), Format("循環 {} 次後繼續下一步", maxL))
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
; [動作 1：畫面圈選 + 主色偵測 + 編輯/測試 (置頂高對比橫幅說明，免彈窗)]
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
    
    ; 頂部中央高對比醒目操作說明告示牌 (100% 清楚可見、絕不會被遮擋)
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
    Sleep(80) ; 充足等待 DWM 解除透光與畫框銷毀，徹底擺脫白色選框殘影噪訊！
    
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

; === 顏色偵測編輯與即時自動測試視窗 (連動 IsAlwaysOnTop 切換) ===
PromptEditColorDetect(step) {
    global MacroEditGui, MyGui, ActiveBoxGuiHwnd, ActiveColorEditCtrlDlg, IsAlwaysOnTop, MacroGroups, ActiveEditGroupIdx
    
    ; 唯一性單一編輯視窗機制：若已有顏色編輯測試視窗開啟，直接聚焦該視窗！
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
    
    ; 1. 建立 100% 乾淨極簡純水藍標記框
    boxGui := Gui("+AlwaysOnTop -Caption -Border +ToolWindow")
    boxGui.BackColor := "0x00FFFF"
    WinSetTransparent(120, boxGui.Hwnd)
    
    ActiveBoxGuiHwnd := boxGui.Hwnd
    ShowBoxGui(boxGui, curX, curY, curW, curH)
    
    ; 2. 建立編輯控制與測試 Modal 對話框 (+Owner 關聯至主編輯視窗)
    ownerHwnd := GetMacroEditGuiHwnd()
    ownerOpt := (ownerHwnd > 0) ? (" +Owner" . ownerHwnd) : ""
    
    ctrlDlg := Gui("-MaximizeBox" . ownerOpt . " +AlwaysOnTop", "🎨 顏色偵測與觸發動作處置設定")
    ctrlDlg.BackColor := "0x1A1A1A"
    ctrlDlg.SetFont("s10 bold cWhite", "Microsoft JhengHei")
    ActiveColorEditCtrlDlg := ctrlDlg
    
    ; 頂部超大醒目狀態告示牌
    statusHeaderBar := ctrlDlg.Add("Text", "x15 y10 w350 h32 Center +0x200 Background0x333333 cWhite", "[ ⏳ 請移動或調整區域進行自動檢測 ]")
    
    ; 第二行：目標顏色預覽 (左側 35px 寬純色色票區) 與 右側可自行輸入/修改的 HEX 顏色輸入框 (Edit)
    ctrlDlg.Add("Text", "x15 y48 w75 h25 cWhite", "目標顏色:")
    cleanClr := RegExReplace(targetColor, "^0[xX]")
    colorPreview := ctrlDlg.Add("Text", "x90 y48 w35 h25 Background" . cleanClr, "")
    editColor := ctrlDlg.Add("Edit", "x132 y46 w110 h26 Background0x2A2A2A c0x00FFFF Uppercase", targetColor)
    ctrlDlg.Add("Text", "x248 y48 w120 h22 c0x888888", "(可自訂HEX)")
    
    SetSwatchColor(hexStr) {
        cHex := RegExReplace(hexStr, "^0[xX]")
        if (StrLen(cHex) == 6) {
            try {
                colorPreview.Opt("Background" . cHex)
                colorPreview.Redraw()
            }
        }
    }
    
    ; 第三行：精準像素數值編輯輸入框 (X, Y, W, H 可直接修改並自動觸發檢測)
    ctrlDlg.Add("Text", "x15 y80 w18 h22 cWhite", "X:")
    editX := ctrlDlg.Add("Edit", "x33 y77 w52 h24 Background0x2A2A2A c0x00FFFF Number", curX)
    
    ctrlDlg.Add("Text", "x90 y80 w18 h22 cWhite", "Y:")
    editY := ctrlDlg.Add("Edit", "x108 y77 w52 h24 Background0x2A2A2A c0x00FFFF Number", curY)
    
    ctrlDlg.Add("Text", "x165 y80 w22 h22 cWhite", "W:")
    editW := ctrlDlg.Add("Edit", "x187 y77 w52 h24 Background0x2A2A2A c0x00FFFF Number", curW)
    
    ctrlDlg.Add("Text", "x244 y80 w20 h22 cWhite", "H:")
    editH := ctrlDlg.Add("Edit", "x264 y77 w52 h24 Background0x2A2A2A c0x00FFFF Number", curH)
    
    ; 第四行：顏色容許值 (Tolerance) 拉桿
    ctrlDlg.Add("Text", "x15 y114 w65 h25 cWhite", "容許值:")
    lblTolerance := ctrlDlg.Add("Text", "x85 y114 w55 h25 c0x00FFFF", curTolerance)
    sldTolerance := ctrlDlg.Add("Slider", "x145 y112 w220 h30 Range0-100 +AltSubmit ToolTip", curTolerance)
    
    ; 第五行：🚫 反向未發現才點擊 CheckBox
    cbInvert := ctrlDlg.AddCheckBox("x15 y146 w350 h25 " . (curInvert ? "Checked" : ""), "🚫 反向檢測 (畫面上未發現該顏色時才點擊)")
    
    ; === 🎯 偵測成功觸發處置 (點擊 / 按鍵與 0-60分/0-60秒雙拉桿) ===
    ctrlDlg.SetFont("s9 bold c0x00FFFF", "Segoe UI")
    ctrlDlg.Add("GroupBox", "x15 y175 w350 h145 c0x00FFFF", "🎯 偵測成功觸發處置 (點擊 / 按鍵與按住拉桿)")
    ctrlDlg.SetFont("s9 bold cWhite", "Microsoft JhengHei")
    
    GetActionText(v) => (v == 0) ? "0: 僅點擊中心點" : ((v == 1) ? "1: 僅按鍵按住" : "2: 點擊 + 按鍵")
    ctrlDlg.Add("Text", "x25 y196 w70 h20 cWhite", "觸發動作:")
    lblActionType := ctrlDlg.Add("Text", "x95 y196 w100 h20 c0x00FFFF", GetActionText(curActionType))
    sldActionType := ctrlDlg.Add("Slider", "x195 y194 w160 h24 Range0-2 +AltSubmit ToolTip", curActionType)
    sldActionType.OnEvent("Change", (ctrl, *) => (
        lblActionType.Value := GetActionText(ctrl.Value)
    ))
    
    ctrlDlg.Add("Text", "x25 y226 w90 h20 cWhite", "觸發發送按鍵:")
    editPressKey := ctrlDlg.Add("Edit", "x120 y223 w65 h24 Background0x2A2A2A c0x00FFFF Center", curPressKey)
    ctrlDlg.Add("Text", "x190 y226 w165 h20 c0x888888", "(如 Space/Enter/F1)")
    
    ctrlDlg.Add("Text", "x25 y256 w90 h20 cWhite", "按住時間(分):")
    lblHoldMin := ctrlDlg.Add("Text", "x120 y256 w70 h20 c0x00FFFF", curHoldMin " 分鐘")
    sldHoldMin := ctrlDlg.Add("Slider", "x195 y254 w160 h24 Range0-60 +AltSubmit ToolTip", curHoldMin)
    sldHoldMin.OnEvent("Change", (ctrl, *) => (
        lblHoldMin.Value := ctrl.Value " 分鐘"
    ))
    
    ctrlDlg.Add("Text", "x25 y286 w90 h20 cWhite", "按住時間(秒):")
    lblHoldSec := ctrlDlg.Add("Text", "x120 y286 w70 h20 c0x00FFFF", curHoldSec " 秒")
    sldHoldSec := ctrlDlg.Add("Slider", "x195 y284 w160 h24 Range0-60 +AltSubmit ToolTip", curHoldSec)
    sldHoldSec.OnEvent("Change", (ctrl, *) => (
        lblHoldSec.Value := ctrl.Value " 秒"
    ))
    
    ; === ⏰ 逾時動作與轉向控制區 (全拉桿控制 + 現有序號讀取) ===
    ctrlDlg.SetFont("s9 bold c0x00FFFF", "Segoe UI")
    ctrlDlg.Add("GroupBox", "x15 y328 w350 h145 c0x00FFFF", "⏰ 逾時處置與轉向設定 (拉桿控制)")
    ctrlDlg.SetFont("s9 bold cWhite", "Microsoft JhengHei")
    
    ctrlDlg.Add("Text", "x25 y348 w70 h20 cWhite", "逾時時間:")
    lblTimeoutSec := ctrlDlg.Add("Text", "x95 y348 w100 h20 c0x00FFFF", (curTimeoutSec == 0 ? "0 秒 (不逾時)" : curTimeoutSec " 秒"))
    sldTimeoutSec := ctrlDlg.Add("Slider", "x195 y346 w160 h24 Range0-300 +AltSubmit ToolTip", curTimeoutSec)
    sldTimeoutSec.OnEvent("Change", (ctrl, *) => (
        lblTimeoutSec.Value := (ctrl.Value == 0) ? "0 秒 (不逾時)" : ctrl.Value " 秒"
    ))
    
    ctrlDlg.Add("Text", "x25 y378 w90 h20 cWhite", "逾時發送按鍵:")
    editTimeoutKey := ctrlDlg.Add("Edit", "x120 y375 w65 h24 Background0x2A2A2A c0x00FFFF Center", curTimeoutKey)
    ctrlDlg.Add("Text", "x190 y378 w165 h20 c0x888888", "(如 Esc / Space / 空白免按)")
    
    GetModeText(v, jP) => (v == 0) ? "0: 重試本步驟" : ((v == 1) ? "1: 推進下一步" : ("2: 返回第 " jP " 步"))
    
    ctrlDlg.Add("Text", "x25 y408 w70 h20 cWhite", "處置模式:")
    lblTimeoutMode := ctrlDlg.Add("Text", "x95 y408 w100 h20 c0x00FFFF", GetModeText(curTimeoutMode, curJumpStep))
    sldTimeoutMode := ctrlDlg.Add("Slider", "x195 y406 w160 h24 Range0-2 +AltSubmit ToolTip", curTimeoutMode)
    
    ctrlDlg.Add("Text", "x25 y438 w70 h20 cWhite", "返回步驟號:")
    lblJumpStep := ctrlDlg.Add("Text", "x95 y438 w100 h20 c0x00FFFF", "第 " curJumpStep " 步")
    sldJumpStep := ctrlDlg.Add("Slider", "x195 y436 w160 h24 Range1-" maxSteps " +AltSubmit ToolTip", curJumpStep)
    
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
            if PixelSearch(&fx, &fy, curX, curY, curX + curW, curY + curH, targetColor, tolVal) {
                foundColor := true
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
    
    isUserTyping := false
    
    OnColorInputChanged(*) {
        if isUserTyping
            return
        val := Trim(editColor.Value)
        if RegExMatch(val, "^(0x)?[0-9a-fA-F]{6}$") {
            if !SubStr(val, 1, 2) == "0x"
                val := "0x" . val
            targetColor := val
            SetSwatchColor(targetColor)
            TestColorDetect()
        }
    }
    editColor.OnEvent("Change", OnColorInputChanged)
    
    OnCoordsEdited(*) {
        if isUserTyping
            return
        try {
            nx := Integer(editX.Value)
            ny := Integer(editY.Value)
            nw := Integer(editW.Value)
            nh := Integer(editH.Value)
            if (nw > 0 && nh > 0) {
                curX := nx, curY := ny, curW := nw, curH := nh
                ShowBoxGui(boxGui, curX, curY, curW, curH)
                TestColorDetect()
            }
        }
    }
    editX.OnEvent("Change", OnCoordsEdited)
    editY.OnEvent("Change", OnCoordsEdited)
    editW.OnEvent("Change", OnCoordsEdited)
    editH.OnEvent("Change", OnCoordsEdited)
    
    ; 輪詢檢測：滑鼠拖曳 boxGui 移動時自動更新座標並自動進行 1 次顏色檢測！
    UpdateBoxPosText() {
        if GetBoxPos(boxGui, &gx, &gy, &gw, &gh) {
            if (gx != curX || gy != curY) {
                curX := gx, curY := gy
                isUserTyping := true
                try editX.Value := curX
                try editY.Value := curY
                isUserTyping := false
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
    
    OnRedrawRegionSelected(nx, ny, nw, nh) {
        curX := nx, curY := ny, curW := nw, curH := nh
        isUserTyping := true
        try editX.Value := curX
        try editY.Value := curY
        try editW.Value := curW
        try editH.Value := curH
        isUserTyping := false
        
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
    
    CloseColorDialog() {
        global ActiveColorEditCtrlDlg
        ActiveBoxGuiHwnd := 0
        ActiveColorEditCtrlDlg := ""
        SetTimer(UpdateBoxPosText, 0)
        try boxGui.Destroy()
        try ctrlDlg.Destroy()
    }
    
    btnSample := ctrlDlg.Add("Button", "x15 y476 w165 h34 Background0x282828", "🎯 採樣主色")
    btnSample.OnEvent("Click", (*) => ReSampleColor())
    
    btnRedraw := ctrlDlg.Add("Button", "x200 y476 w165 h34 Background0x282828", "🖱 重新畫框")
    btnRedraw.OnEvent("Click", (*) => RedrawBox())
    
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
        step.pressKey := Trim(editPressKey.Value)
        step.holdMin := Integer(sldHoldMin.Value)
        step.holdSec := Integer(sldHoldSec.Value)
        
        step.timeoutSec := Integer(sldTimeoutSec.Value)
        step.timeoutKey := Trim(editTimeoutKey.Value)
        step.timeoutMode := Integer(sldTimeoutMode.Value)
        step.jumpStep := Integer(sldJumpStep.Value)
        RefreshMacroListView()
        CloseColorDialog()
    }
    
    btnSave := ctrlDlg.Add("Button", "x15 y516 w350 h38 Background0x008800", "💾 儲存修改內容")
    btnSave.OnEvent("Click", (*) => OnSaveColorEdit())
    ctrlDlg.OnEvent("Close", (*) => CloseColorDialog())
    
    TestColorDetect()
    
    dlgX := Min(A_ScreenWidth - 395, curX + curW + 15)
    dlgY := Max(30, Min(A_ScreenHeight - 590, curY))
    if (dlgX + 380 > A_ScreenWidth)
        dlgX := Max(10, curX - 390)
        
    ctrlDlg.Show("X" dlgX " Y" dlgY " W380 H564")
    
    SetTimer(UpdateBoxPosText, 200)
}

; =================================================================
; [動作 2：等待秒數設定拉桿]
; =================================================================
PromptAddWait() {
    global MacroGroups, ActiveEditGroupIdx
    if (ActiveEditGroupIdx < 1 || ActiveEditGroupIdx > MacroGroups.Length)
        return
        
    PromptEditWait({ type: "wait", waitMs: 2000, isNew: true })
}

PromptEditWait(step) {
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
    
    dlg := Gui("-MaximizeBox" . ownerOpt . " +AlwaysOnTop", isNew ? "⏱ 增加等待秒數動作" : "⏱ 編輯等待秒數動作")
    dlg.BackColor := "0x1A1A1A"
    dlg.SetFont("s10 bold cWhite", "Microsoft JhengHei")
    ActiveStepEditDlg := dlg
    
    curWaitVal := Round(step.waitMs / 100)
    dlg.Add("Text", "x20 y20 w120 h25 cWhite", "等待秒數時間:")
    lblWait := dlg.Add("Text", "x140 y20 w140 h25 c0x00FFFF", Format("{:.1f} 秒", curWaitVal / 10))
    sldWait := dlg.Add("Slider", "x20 y50 w260 h30 Range1-600 +AltSubmit ToolTip", curWaitVal)
    sldWait.OnEvent("Change", (ctrl, *) => (
        lblWait.Value := Format("{:.1f} 秒", ctrl.Value / 10)
    ))
    
    CloseWaitDlg() {
        global ActiveStepEditDlg
        ActiveStepEditDlg := ""
        try dlg.Destroy()
    }
    
    btnConfirm := dlg.Add("Button", "x20 y95 w260 h35 Background0x008800", isNew ? "確認新增等待" : "確認儲存等待修改")
    btnConfirm.OnEvent("Click", (*) => (
        step.waitMs := Integer(sldWait.Value * 100),
        isNew ? MacroGroups[ActiveEditGroupIdx].steps.Push(step) : 0,
        RefreshMacroListView(),
        CloseWaitDlg()
    ))
    dlg.OnEvent("Close", (*) => CloseWaitDlg())
    
    dlg.Show("w300 h145")
}
    
; =================================================================
; [動作 3：步驟內循環轉向控制 (Loop Goto Step)]
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
    curLoops := step.HasOwnProp("maxLoops") ? Max(1, step.maxLoops) : 5
    
    dlg.Add("Text", "x20 y18 w140 h25 cWhite", "返回目標步驟號:")
    lblTarget := dlg.Add("Text", "x160 y18 w140 h25 c0x00FFFF", "第 " curTarget " 步")
    sldTarget := dlg.Add("Slider", "x20 y45 w280 h30 Range1-" maxSteps " +AltSubmit ToolTip", curTarget)
    sldTarget.OnEvent("Change", (ctrl, *) => (
        lblTarget.Value := "第 " ctrl.Value " 步"
    ))
    
    dlg.Add("Text", "x20 y85 w140 h25 cWhite", "重複返回循環次數:")
    lblLoops := dlg.Add("Text", "x160 y85 w140 h25 c0x00FFFF", curLoops " 次")
    sldLoops := dlg.Add("Slider", "x20 y112 w280 h30 Range1-999 +AltSubmit ToolTip", curLoops)
    sldLoops.OnEvent("Change", (ctrl, *) => (
        lblLoops.Value := ctrl.Value " 次"
    ))
    
    dlg.Add("Text", "x20 y150 w280 h38 c0x888888", "說明: 執行到此步驟時會跳轉回指定步驟，累積指定次數後即會自動通過推進至下一步。")
    
    CloseLoopGotoDlg() {
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
    dlg.OnEvent("Close", (*) => CloseLoopGotoDlg())
    
    dlg.Show("w320 h248")
}

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
    steps := grp.steps
    loopCounters := Map()
    
    while (curLoop <= totalLoops && !StopMacroRequested && RunningGroupIdx == groupIdx) {
        sIdx := 1
        while (sIdx <= steps.Length && !StopMacroRequested && RunningGroupIdx == groupIdx) {
            step := steps[sIdx]
            
            stepPct := (sIdx / steps.Length) * 100
            totalPct := (curLoop / totalLoops) * 100
            
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
                toText := (timeoutSec > 0) ? Format(" [逾時:{}s]", timeoutSec) : ""
                statusText := Format("{} {} | Loop [{}/{}] Step [{}/{}]: 偵測顏色 {}{}{}...", 
                    grp.icon, grp.name, curLoop, totalLoops, sIdx, steps.Length, step.color, invText, toText)
                RenderProgressBarBitmap(stepPct, totalPct, statusText)
                
                foundColor := false
                startTime := A_TickCount
                timeoutMs := timeoutSec * 1000
                
                loop {
                    if (StopMacroRequested || RunningGroupIdx != groupIdx)
                        break
                        
                    foundColor := false
                    try {
                        if PixelSearch(&foundX, &foundY, step.x, step.y, step.x + step.w, step.y + step.h, step.color, tolVal) {
                            foundColor := true
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
                        statusText := Format("{} {} | Loop [{}/{}] Step [{}/{}]: ⚠️ 步驟逾時！執行處置...", grp.icon, grp.name, curLoop, totalLoops, sIdx, steps.Length)
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
                statusText := Format("{} {} | Loop [{}/{}] Step [{}/{}]: 按鍵 '{}' (按住 {:.1f}s)", grp.icon, grp.name, curLoop, totalLoops, sIdx, steps.Length, step.key, step.holdMs/1000)
                RenderProgressBarBitmap(stepPct, totalPct, statusText)
                
                Send("{" step.key " down}")
                SleepInterruptible(step.holdMs)
                Send("{" step.key " up}")
                
                if (step.delayMs > 0) {
                    statusText := Format("{} {} | Loop [{}/{}] Step [{}/{}]: 延遲 {:.1f}s...", grp.icon, grp.name, curLoop, totalLoops, sIdx, steps.Length, step.delayMs/1000)
                    RenderProgressBarBitmap(stepPct, totalPct, statusText)
                    SleepInterruptible(step.delayMs)
                }
                
            } else if (step.type == "wait") {
                statusText := Format("{} {} | Loop [{}/{}] Step [{}/{}]: 等待 {:.1f}s...", grp.icon, grp.name, curLoop, totalLoops, sIdx, steps.Length, step.waitMs/1000)
                RenderProgressBarBitmap(stepPct, totalPct, statusText)
                SleepInterruptible(step.waitMs)
            } else if (step.type == "loop_goto") {
                targetS := step.HasOwnProp("targetStep") ? Max(1, Min(steps.Length, step.targetStep)) : 1
                maxL := step.HasOwnProp("maxLoops") ? Max(1, step.maxLoops) : 1
                
                currRunCount := loopCounters.Has(sIdx) ? loopCounters[sIdx] : 0
                if (currRunCount < maxL) {
                    loopCounters[sIdx] := currRunCount + 1
                    statusText := Format("{} {} | Loop [{}/{}] Step [{}/{}]: 🔁 轉向跳轉至第 {} 步 ({}/{})", grp.icon, grp.name, curLoop, totalLoops, sIdx, steps.Length, targetS, currRunCount + 1, maxL)
                    RenderProgressBarBitmap(stepPct, totalPct, statusText)
                    Sleep(150)
                    sIdx := targetS - 1 ; 跳轉至目標步驟 (迴圈末會 sIdx++)
                } else {
                    loopCounters[sIdx] := 0 ; 滿次解鎖並重置計數器，推進至下一步
                    statusText := Format("{} {} | Loop [{}/{}] Step [{}/{}]: 🔁 轉向次數已滿 ({}/{})，推進下一步", grp.icon, grp.name, curLoop, totalLoops, sIdx, steps.Length, maxL, maxL)
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
