local ADDON_NAME = ...
local HT = _G.HAN_Tools
-- =========================================================
-- 1. 전문화 목록 (조건 선택용)
-- =========================================================
local ALL_SPECS = {
    { id =  71, label = "전사 - 무기" }, { id =  72, label = "전사 - 분노" }, { id =  73, label = "전사 - 방어" },
    { id =  65, label = "성기사 - 신성" }, { id =  66, label = "성기사 - 보호" }, { id =  70, label = "성기사 - 징벌" },
    { id = 253, label = "사냥꾼 - 야수" }, { id = 254, label = "사냥꾼 - 사격" }, { id = 255, label = "사냥꾼 - 생존" },
    { id = 259, label = "도적 - 암살" }, { id = 260, label = "도적 - 무법" }, { id = 261, label = "도적 - 잠행" },
    { id = 256, label = "사제 - 수양" }, { id = 257, label = "사제 - 신성" }, { id = 258, label = "사제 - 암흑" },
    { id = 250, label = "죽기 - 혈기" }, { id = 251, label = "죽기 - 냉기" }, { id = 252, label = "죽기 - 부정" },
    { id = 262, label = "주술사 - 정기" }, { id = 263, label = "주술사 - 고양" }, { id = 264, label = "주술사 - 복원" },
    { id = 265, label = "흑마 - 고통" }, { id = 266, label = "흑마 - 악마" }, { id = 267, label = "흑마 - 파괴" },
    { id = 268, label = "수도사 - 운무" }, { id = 269, label = "수도사 - 풍운" }, { id = 270, label = "수도사 - 양조" },
    { id = 102, label = "드루이드 - 조화" }, { id = 103, label = "드루이드 - 야성" }, { id = 104, label = "드루이드 - 수호" }, { id = 105, label = "드루이드 - 회복" },
    { id = 577, label = "악마사냥꾼 - 황폐" }, { id = 581, label = "악마사냥꾼 - 복수" },
    { id =  62, label = "마법사 - 비전" }, { id =  63, label = "마법사 - 화염" }, { id =  64, label = "마법사 - 냉기" },
    { id = 1467, label = "에보커 - 황폐" }, { id = 1468, label = "에보커 - 보존" }, { id = 1473, label = "에보커 - 증강" },
}
-- =========================================================
-- 2. 기본값 및 시스템 상태 (State & Defaults)
-- =========================================================
local SOUND_PATH = "Interface\\AddOns\\HAN_TOOLS\\Sounds\\alert.ogg"
local defaults = {
    enabled       = true,
    unlocked      = false,
    point         = "CENTER",
    relativePoint = "CENTER",
    x             = 0,
    y             = -150,
    fontSize      = 32,
    fontColor     = { 1.0, 1.0, 1.0 },
    useCondition      = false,
    conditionValue    = 50,
    conditionColor    = { 1.0, 0.2, 0.2 },
    conditionFontSize = 40,
    useConditionSize  = false,
    conditionSpecs    = {},
    useSound          = false,
    soundCooldown     = 2.0,
}
local db
local frame
local Options = {}
-- 클래스/특성별 엣지 케이스 및 상태 객체
local state = {
    powerType    = nil,
    isStagger    = false,
    isPartial    = false,
    isDK         = false,
    -- 비전 마법사: 아케인 차지(위) + 마나%(아래) 동시 표시
    isDualResource = false,
    subPowerType   = nil,
}
-- =========================================================
-- 4. 유틸
-- =========================================================
local function SafeNum(v)
    if v == nil then return nil end
    local ok, n = pcall(function() return v + 0 end)
    return (ok and type(n) == "number") and n or nil
end
local function CopyColor(t) return { t[1] or 1, t[2] or 1, t[3] or 1 } end
local function EnsureColor(t, fallback)
    if type(t) ~= "table" then return CopyColor(fallback) end
    return { tonumber(t[1]) or fallback[1], tonumber(t[2]) or fallback[2], tonumber(t[3]) or fallback[3] }
end
local function Round(v)
    v = tonumber(v) or 0
    return v >= 0 and math.floor(v + 0.5) or -math.floor(-v + 0.5)
end
local function GetCurrentSpecID()
    local idx = GetSpecialization and GetSpecialization()
    if not idx then return nil end
    return GetSpecializationInfo(idx)
end
local function ConditionMatchesSpec()
    if not db.useCondition then return false end
    local specs = db.conditionSpecs
    if not specs or not next(specs) then return true end
    local specID = GetCurrentSpecID()
    return specID and specs[specID] == true or false
end
-- =========================================================
-- 5. DB 초기화
-- =========================================================
local function InitializeDB()
    HT.db = HT.db or {}
    HT.db.resource = HT.db.resource or {}
    for k, v in pairs(defaults) do
        if HT.db.resource[k] == nil then
            if k == "conditionSpecs" then
                HT.db.resource[k] = {}
            elseif type(v) == "table" then
                HT.db.resource[k] = CopyColor(v)
            else
                HT.db.resource[k] = v
            end
        end
    end
    db = HT.db.resource
    db.fontColor = EnsureColor(db.fontColor, defaults.fontColor)
    db.conditionColor = EnsureColor(db.conditionColor, defaults.conditionColor)
    db.fontSize = tonumber(db.fontSize) or defaults.fontSize
    db.conditionFontSize = tonumber(db.conditionFontSize) or defaults.conditionFontSize
    db.x = tonumber(db.x) or defaults.x
    db.y = tonumber(db.y) or defaults.y
    db.conditionValue = tonumber(db.conditionValue) or defaults.conditionValue
    db.soundCooldown = tonumber(db.soundCooldown) or defaults.soundCooldown
    db.conditionSpecs = type(db.conditionSpecs) == "table" and db.conditionSpecs or {}
    db.useConditionSize = not not db.useConditionSize
    db.useSound = not not db.useSound
    db.useCondition = not not db.useCondition
end
-- =========================================================
-- 6. 사운드
-- =========================================================
local lastSoundTime = 0
local function TryPlaySound()
    if not db.useSound then return end
    local now = GetTime()
    if (now - lastSoundTime) < (db.soundCooldown or 2.0) then return end
    lastSoundTime = now
    pcall(function() PlaySoundFile(SOUND_PATH, "Master") end)
end
-- =========================================================
-- 7. 자원 식별 및 읽기 (The Knowledge Engine)
-- =========================================================
local function SetupPowerTypes()
    local _, class = UnitClass("player")
    local spec = GetSpecialization and GetSpecialization() or 1
    state.powerType      = UnitPowerType("player") -- Default Fallback
    state.isStagger      = false
    state.isPartial      = false
    state.isDK           = (class == "DEATHKNIGHT")
    state.isDualResource = false
    state.subPowerType   = nil

    if class == "EVOKER" then
        state.powerType = Enum.PowerType.Essence
    elseif class == "PALADIN" then
        state.powerType = Enum.PowerType.HolyPower
    elseif class == "MAGE" then
        if spec == 1 then
            -- 비전: 아케인 차지(위) + 마나%(아래) 동시 표시
            state.powerType      = Enum.PowerType.ArcaneCharges
            state.isDualResource = true
            state.subPowerType   = Enum.PowerType.Mana
        end
        -- 화염(2), 냉기(3): 기본값(Mana) 그대로 사용
    elseif class == "WARLOCK" then
        state.powerType = Enum.PowerType.SoulShards
        if spec == 3 then state.isPartial = true end
    elseif class == "DRUID" then
        if spec == 2 then state.powerType = Enum.PowerType.ComboPoints end
    elseif class == "MONK" then
        if spec == 3 then
            state.powerType = Enum.PowerType.Chi
        elseif spec == 1 then
            state.isStagger = true
        end
    elseif class == "ROGUE" then
        state.powerType = Enum.PowerType.ComboPoints
    end
end
local function GetPowerValues()
    -- 1. 예외 케이스: 양조 수도사 시간차 (Stagger)
    if state.isStagger then
        local maxHealth = SafeNum(UnitHealthMax("player"))
        if maxHealth and maxHealth > 0 then
            local stagger = SafeNum(UnitStagger("player")) or 0
            local pct = (stagger / maxHealth) * 100
            return pct, maxHealth, true
        end
        return 0, 100, true
    end
    -- 2. 예외 케이스: 죽음의 기사 룬 (Runes)
    if state.isDK then
        local count = 0
        for i = 1, 6 do
            local _, _, ready = GetRuneCooldown(i)
            if ready then count = count + 1 end
        end
        return count, 6, false
    end
    -- 3. 표준 & 2차 자원 (Standard & Secondary)
    local pType = state.powerType or UnitPowerType("player")
    local isMana = (pType == Enum.PowerType.Mana)
    local cur = SafeNum(UnitPower("player", pType, state.isPartial))
    local max = SafeNum(UnitPowerMax("player", pType))
    if not cur or not max then return nil, nil, isMana end
    -- 파괴 흑마법사 소수점 영혼 조각 처리
    if state.isPartial then
        local mod = UnitPowerDisplayMod(pType)
        if mod and mod > 0 then
            cur = cur / mod
            max = max / mod
        end
        return cur, max, false
    end
    -- 마나: 단순 퍼센트 계산
    if isMana then
        local pct = (max > 0) and (cur / max * 100) or 0
        return pct, max, true
    end
    return cur, max, false
end
-- =========================================================
-- 8. 디스플레이 업데이트
-- =========================================================
local prevAbove = nil
local function UpdateDisplay(self)
    if not db.enabled then return end
    local value, max, showAsPct = GetPowerValues()
    if value == nil then return end
    -- 포맷팅
    local textVal
    if showAsPct then
        textVal = string.format("%.0f%%", value)
    elseif state.isPartial then
        textVal = string.format("%.1f", value)
    else
        textVal = tostring(value)
    end
    self.textBase:SetText(textVal)
    self.textCond:SetText(textVal)
    -- 보조 자원 표시 (비전 마법사: 마나%)
    if state.isDualResource and state.subPowerType then
        local subCur = SafeNum(UnitPower("player", state.subPowerType))
        local subMax = SafeNum(UnitPowerMax("player", state.subPowerType))
        local subPct = (subCur and subMax and subMax > 0) and (subCur / subMax * 100) or 0
        self.textSub:SetText(string.format("%.0f%%", subPct))
        local bC = db.fontColor
        self.textSub:SetTextColor(bC[1], bC[2], bC[3], 0.75)
    else
        self.textSub:SetText("")
        self.textSub:SetTextColor(0, 0, 0, 0)
    end
    -- 조건 판정
    local condActive = ConditionMatchesSpec() and (value >= (tonumber(db.conditionValue) or 0))
    local bC = db.fontColor
    local cC = db.conditionColor
    if condActive then
        self.textBase:SetTextColor(0, 0, 0, 0)
        self.textCond:SetTextColor(cC[1], cC[2], cC[3], 1)
        if db.useConditionSize then
            self.textCond:SetFont(self._font, db.conditionFontSize, "OUTLINE")
        end
    else
        self.textBase:SetTextColor(bC[1], bC[2], bC[3], 1)
        self.textCond:SetTextColor(0, 0, 0, 0)
        self.textBase:SetFont(self._font, db.fontSize, "OUTLINE")
    end
    -- 사운드 트리거
    if db.useCondition and ConditionMatchesSpec() then
        local isAbove = (value >= (tonumber(db.conditionValue) or 0))
        if prevAbove == false and isAbove then
            TryPlaySound()
        end
        prevAbove = isAbove
    else
        prevAbove = nil
    end
end
-- =========================================================
-- 9. ApplySettings
-- =========================================================
local function GetFont()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    return (LSM and LSM:Fetch("font", LSM:GetDefault("font"))) or "Fonts\\2002B.TTF"
end
local function ApplySettings()
    if not frame then return end
    frame:ClearAllPoints()
    frame:SetPoint(db.point or "CENTER", UIParent, db.relativePoint or "CENTER", db.x or 0, db.y or 0)
    frame:EnableMouse(db.unlocked)
    if frame.bg then
        if db.unlocked then frame.bg:Show() else frame.bg:Hide() end
    end
    local font = GetFont()
    frame._font = font
    local subFontSize = math.max(8, math.floor(db.fontSize * 0.75))
    frame.textBase:SetFont(font, db.fontSize, "OUTLINE")
    frame.textCond:SetFont(font, db.conditionFontSize, "OUTLINE")
    frame.textSub:SetFont(font, subFontSize, "OUTLINE")
    -- 이중 자원(비전 마법사): 위쪽 차지 / 아래쪽 마나
    frame.textBase:ClearAllPoints()
    frame.textCond:ClearAllPoints()
    frame.textSub:ClearAllPoints()
    if state.isDualResource then
        local topOffset = math.floor(db.fontSize / 2) + 4
        local botOffset = math.floor(subFontSize / 2) + 4
        frame.textBase:SetPoint("CENTER", frame, "CENTER", 0,  topOffset)
        frame.textCond:SetPoint("CENTER", frame, "CENTER", 0,  topOffset)
        frame.textSub:SetPoint ("CENTER", frame, "CENTER", 0, -botOffset)
        frame:SetHeight(math.max(50, db.fontSize + subFontSize + 16))
    else
        frame.textBase:SetPoint("CENTER")
        frame.textCond:SetPoint("CENTER")
        frame.textSub:SetPoint ("CENTER")
        frame:SetHeight(50)
    end
    if db.enabled then frame:Show() else frame:Hide() end
end
-- =========================================================
-- 10. 프레임 생성 및 이벤트 바인딩
-- =========================================================
local function CreateTracker()
    if frame then return end
    frame = CreateFrame("Frame", "HAN_Tools_Resource", UIParent)
    frame:SetSize(120, 50)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0, 0.8, 0, 0.25)
    frame.bg:Hide()
    frame.textBase = frame:CreateFontString(nil, "OVERLAY")
    frame.textBase:SetPoint("CENTER")
    frame.textBase:SetFont("Fonts\\2002B.TTF", 32, "OUTLINE")
    frame.textBase:SetText("--")
    frame.textCond = frame:CreateFontString(nil, "OVERLAY")
    frame.textCond:SetPoint("CENTER")
    frame.textCond:SetFont("Fonts\\2002B.TTF", 40, "OUTLINE")
    frame.textCond:SetTextColor(0, 0, 0, 0)
    -- 보조 자원 텍스트 (비전 마법사 마나 등)
    frame.textSub = frame:CreateFontString(nil, "OVERLAY")
    frame.textSub:SetPoint("CENTER")
    frame.textSub:SetFont("Fonts\\2002B.TTF", 24, "OUTLINE")
    frame.textSub:SetTextColor(0, 0, 0, 0)
    frame.textSub:SetText("")
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if db.unlocked then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local _, point, _, relativePoint, x, y = self:GetPoint(1)
        db.point = point or db.point
        db.relativePoint = relativePoint or db.relativePoint
        db.x = Round(x or db.x)
        db.y = Round(y or db.y)
        if Options.sl_x then Options.sl_x:Refresh() end
        if Options.sl_y then Options.sl_y:Refresh() end
    end)
    frame:SetScript("OnMouseUp", function(_, btn)
        if btn == "RightButton" and Options.categoryID then
            Settings.OpenToCategory(Options.categoryID)
        end
    end)
    local evFrame = CreateFrame("Frame")
    evFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    evFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    evFrame:RegisterEvent("RUNE_POWER_UPDATE")
    evFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    evFrame:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    evFrame:RegisterUnitEvent("UNIT_AURA", "player")
    evFrame:SetScript("OnEvent", function(self, event, arg1)
        if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" then
            SetupPowerTypes()
            ApplySettings()
            UpdateDisplay(frame)
        elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_DISPLAYPOWER" then
            if not state.isStagger and not state.isDK then UpdateDisplay(frame) end
        elseif event == "RUNE_POWER_UPDATE" then
            if state.isDK then UpdateDisplay(frame) end
        elseif event == "UNIT_AURA" then
            if state.isStagger then UpdateDisplay(frame) end
        end
    end)
end
-- =========================================================
-- 11. 옵션 UI 헬퍼
-- =========================================================
local function MakeSlider(parent, label, x, y, minV, maxV, step, getter, setter)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(260, 60)
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local lbl = c:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lbl:SetPoint("TOP", 0, 0); lbl:SetText(label); lbl:SetTextColor(1, 0.82, 0)
    local sl = CreateFrame("Slider", nil, c, "UISliderTemplate")
    sl:SetSize(200, 15); sl:SetPoint("TOP", lbl, "BOTTOM", 0, -8)
    sl:SetMinMaxValues(minV, maxV); sl:SetValueStep(step); sl:SetObeyStepOnDrag(true)
    local eb = CreateFrame("EditBox", nil, c, "InputBoxTemplate")
    eb:SetSize(70, 20); eb:SetPoint("TOP", sl, "BOTTOM", 0, -2); eb:SetAutoFocus(false); eb:SetJustifyH("CENTER")
    local busy = false
    local function Sync(val)
        if busy then return end
        busy = true
        val = math.max(minV, math.min(maxV, tonumber(val) or getter()))
        val = math.floor(val / step + 0.5) * step
        sl:SetValue(val); eb:SetText(tostring(val)); eb:SetCursorPosition(0)
        setter(val); ApplySettings(); busy = false
    end
    sl:SetScript("OnValueChanged", function(_, v) Sync(v) end)
    eb:SetScript("OnEnterPressed", function(s) s:ClearFocus(); Sync(tonumber(s:GetText())) end)
    eb:SetScript("OnEditFocusLost", function(s) Sync(tonumber(s:GetText())) end)
    function c:Refresh()
        busy = true
        local v = getter()
        sl:SetValue(v); eb:SetText(tostring(v)); eb:SetCursorPosition(0)
        busy = false
    end
    c:HookScript("OnShow", function() c:Refresh() end); c:Refresh()
    return c
end
local function MakeColorPicker(parent, label, x, y, getter, setter)
    local lbl = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); lbl:SetText(label)
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(22, 22); bg:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 150, y + 2); bg:SetColorTexture(0.3, 0.3, 0.3)
    local sw = parent:CreateTexture(nil, "ARTWORK")
    sw:SetSize(18, 18); sw:SetPoint("CENTER", bg)
    local function Refresh() local c = getter(); sw:SetColorTexture(c[1], c[2], c[3]) end
    Refresh()
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(60, 22); btn:SetPoint("LEFT", bg, "RIGHT", 8, 0); btn:SetText("변경")
    btn:SetScript("OnClick", function()
        local c = getter()
        local pr, pg, pb = c[1], c[2], c[3]
        if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:Hide()
            ColorPickerFrame:SetupColorPickerAndShow({
                r = pr, g = pg, b = pb, hasOpacity = false,
                swatchFunc = function() local r, g, b = ColorPickerFrame:GetColorRGB(); setter({ r, g, b }); Refresh(); ApplySettings() end,
                cancelFunc = function() setter({ pr, pg, pb }); Refresh(); ApplySettings() end,
            })
        end
    end)
    return { Refresh = Refresh }
end
local function MakeCheck(parent, label, x, y, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); cb.Text:SetText(label); cb:SetChecked(getter())
    cb:SetScript("OnClick", function(self) setter(self:GetChecked()); ApplySettings() end)
    function cb:Refresh() self:SetChecked(getter()) end
    return cb
end
-- =========================================================
-- 12. 옵션 패널 빌드
-- =========================================================
local function BuildOptions()
    if Options.frame then return end
    local f = CreateFrame("Frame", "HAN_Tools_ResourceOpt", UIParent)
    f.name = "자원 추적기"
    Options.frame = f
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -8); scroll:SetPoint("BOTTOMRIGHT", -26, 8)
    local c = CreateFrame("Frame", nil, scroll)
    c:SetSize(1, 1); scroll:SetScrollChild(c)
    local title = c:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16); title:SetText("HAN TOOLS — 자원 추적기")
    local y = -60
    Options.cb_enable = MakeCheck(c, "활성화", 16, y, function() return db.enabled end, function(v) db.enabled = v end)
    y = y - 30
    Options.cb_unlock = MakeCheck(c, "위치 잠금 해제 (드래그)", 16, y, function() return db.unlocked end, function(v) db.unlocked = v end)
    y = y - 40
    Options.sl_x = MakeSlider(c, "X 위치", 16, y, -2000, 2000, 1, function() return db.x end, function(v) db.x = v end)
    Options.sl_y = MakeSlider(c, "Y 위치", 310, y, -2000, 2000, 1, function() return db.y end, function(v) db.y = v end)
    y = y - 70
    Options.sl_font = MakeSlider(c, "글자 크기", 16, y, 8, 128, 1, function() return db.fontSize end, function(v) db.fontSize = v end)
    y = y - 70
    Options.cp_font = MakeColorPicker(c, "글자 색상", 16, y, function() return db.fontColor end, function(v) db.fontColor = EnsureColor(v, defaults.fontColor) end)
    y = y - 50
    local sep = c:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    sep:SetPoint("TOPLEFT", 16, y); sep:SetText("─── 조건 설정 ───")
    y = y - 30
    Options.cb_cond = MakeCheck(c, "기준치 조건 사용", 16, y, function() return db.useCondition end, function(v) db.useCondition = v end)
    y = y - 40
    Options.sl_condVal = MakeSlider(c, "기준값 (마나: %, 나머지: 실제값)", 16, y, 0, 10000, 1, function() return db.conditionValue end, function(v) db.conditionValue = v end)
    y = y - 70
    Options.cp_cond = MakeColorPicker(c, "조건 달성 색상", 16, y, function() return db.conditionColor end, function(v) db.conditionColor = EnsureColor(v, defaults.conditionColor) end)
    y = y - 50
    Options.cb_condSize = MakeCheck(c, "조건 달성 시 글자 크기도 변경", 16, y, function() return db.useConditionSize end, function(v) db.useConditionSize = v end)
    y = y - 30
    Options.sl_condFont = MakeSlider(c, "조건 달성 글자 크기", 16, y, 8, 128, 1, function() return db.conditionFontSize end, function(v) db.conditionFontSize = v end)
    y = y - 70
    local specTitle = c:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    specTitle:SetPoint("TOPLEFT", 16, y); specTitle:SetText("조건 발동 전문화 (미선택 = 모든 전문화)"); specTitle:SetTextColor(1, 0.82, 0)
    y = y - 24
    Options.specChecks = {}
    local col, colW = 0, 240
    for _, spec in ipairs(ALL_SPECS) do
        local sx = 16 + col * colW
        local cb = CreateFrame("CheckButton", nil, c, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", c, "TOPLEFT", sx, y)
        cb:SetSize(24, 24); cb.Text:SetText(spec.label); cb._specID = spec.id
        cb:SetChecked(db.conditionSpecs[spec.id] == true)
        cb:SetScript("OnClick", function(self) db.conditionSpecs[self._specID] = self:GetChecked() or nil end)
        Options.specChecks[spec.id] = cb
        col = col + 1; if col >= 2 then col = 0; y = y - 26 end
    end
    if col ~= 0 then y = y - 26 end
    y = y - 10
    local sep2 = c:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    sep2:SetPoint("TOPLEFT", 16, y); sep2:SetText("─── 사운드 설정 ───")
    y = y - 30
    Options.cb_sound = MakeCheck(c, "기준치 달성 시 효과음 재생", 16, y, function() return db.useSound end, function(v) db.useSound = v end)
    y = y - 30
    local soundDesc = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    soundDesc:SetPoint("TOPLEFT", 36, y); soundDesc:SetText("파일: HAN_TOOLS/Sounds/alert.ogg"); soundDesc:SetTextColor(0.6, 0.6, 0.6)
    y = y - 24
    Options.sl_soundCD = MakeSlider(c, "사운드 쿨다운 (초)", 16, y, 0.5, 30.0, 0.5, function() return db.soundCooldown end, function(v) db.soundCooldown = v end)
    y = y - 70
    local prevBtn = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    prevBtn:SetSize(120, 24); prevBtn:SetPoint("TOPLEFT", 16, y); prevBtn:SetText("사운드 미리듣기")
    prevBtn:SetScript("OnClick", function() pcall(function() PlaySoundFile(SOUND_PATH, "Master") end) end)
    y = y - 40
    c:SetHeight(math.max(600, -y + 60))
    f:SetScript("OnShow", function()
        C_Timer.After(0.05, function()
            if Options.cb_enable   then Options.cb_enable:Refresh()   end
            if Options.cb_unlock   then Options.cb_unlock:Refresh()   end
            if Options.cb_cond     then Options.cb_cond:Refresh()     end
            if Options.cb_condSize then Options.cb_condSize:Refresh() end
            if Options.cb_sound    then Options.cb_sound:Refresh()    end
            if Options.sl_x        then Options.sl_x:Refresh()        end
            if Options.sl_y        then Options.sl_y:Refresh()        end
            if Options.sl_font     then Options.sl_font:Refresh()     end
            if Options.sl_condVal  then Options.sl_condVal:Refresh()  end
            if Options.sl_condFont then Options.sl_condFont:Refresh() end
            if Options.sl_soundCD  then Options.sl_soundCD:Refresh()  end
            for specID, cb in pairs(Options.specChecks or {}) do
                cb:SetChecked(db.conditionSpecs[specID] == true)
            end
        end)
    end)
    if Settings and Settings.RegisterCanvasLayoutSubcategory and HT and HT.OptionsCategoryID then
        local cat = Settings.RegisterCanvasLayoutSubcategory(HT.OptionsCategoryID, f, f.name)
        Options.categoryID = cat:GetID()
    end
end
-- =========================================================
-- 13. 진입점
-- =========================================================
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        InitializeDB()
        CreateTracker()
        BuildOptions()
        SetupPowerTypes()
        ApplySettings()
        UpdateDisplay(frame)
    end
end)
