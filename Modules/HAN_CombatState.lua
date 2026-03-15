-- Modules/HAN_CombatState.lua
local ADDON_NAME = ...
local HT = _G.HAN_Tools
local addon = CreateFrame("Frame")
local defaults = {
	point = "CENTER", relativePoint = "CENTER", x = 0, y = -180,
	unlocked = false, testMode = false,
	startDuration = 1.0, labelSize = 20, timerSize = 18, textAlign = "CENTER",
	animationEnabled = true, slideOffsetX = -10,
	fadeInDuration = 0.2, fadeOutDuration = 0.2,
	startColor  = {1.0, 0.82, 0.10, 1.0},
	combatColor = {1.0, 0.85, 0.05, 1.0},
	timerColor  = {1.0, 1.0,  1.0,  1.0},
}
local db
local isInCombat        = false
local combatStartTime   = 0
local elapsedAccumulator = 0
local settingsCategory
local COMBAT_TEXT   = "전투중"
local FRAME_WIDTH   = 260
local FRAME_HEIGHT  = 78
local CONTENT_WIDTH = 170
local alignmentChoices = {
	{ key = "LEFT",   label = "왼쪽 정렬"   },
	{ key = "CENTER", label = "가운데 정렬" },
	{ key = "RIGHT",  label = "오른쪽 정렬" },
}
-- =========================================================
-- DB
-- =========================================================
local function DeepCopy(src)
	local t = {}
	for k, v in pairs(src) do
		if type(v) == "table" then
			local sub = {}
			for kk, vv in pairs(v) do sub[kk] = vv end
			t[k] = sub
		else
			t[k] = v
		end
	end
	return t
end
local function InitDB()
	HT.db.combatstate = HT.db.combatstate or {}
	db = HT.db.combatstate
	for k, v in pairs(defaults) do
		if db[k] == nil then
			db[k] = type(v) == "table" and DeepCopy(v) or v
		elseif type(v) == "table" and type(db[k]) ~= "table" then
			db[k] = DeepCopy(v)
		end
	end
end
-- =========================================================
-- Frame
-- =========================================================
local frame = CreateFrame("Frame", "HAN_CombatStateFrame", UIParent)
frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(false)   -- [FIX] 잠금 상태에서는 마우스 캡처 불필요 → 잠금해제 시 true로 전환
frame:RegisterForDrag("LeftButton")
frame:Hide()

local content = CreateFrame("Frame", nil, frame)
content:SetSize(CONTENT_WIDTH, FRAME_HEIGHT)
content:SetPoint("CENTER", frame, "CENTER", 0, 0)

local label = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
label:SetShadowOffset(1, -1); label:SetShadowColor(0, 0, 0, 1)

local timerText = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
timerText:SetShadowOffset(1, -1); timerText:SetShadowColor(0, 0, 0, 1)
-- =========================================================
-- Layout / Position
-- =========================================================
local function ApplyPosition()
	frame:ClearAllPoints()
	frame:SetPoint(db.point, UIParent, db.relativePoint, db.x, db.y)
end
local function SaveCurrentPosition()
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	db.point         = point         or "CENTER"
	db.relativePoint = relativePoint or "CENTER"
	db.x = math.floor((x or 0) + 0.5)
	db.y = math.floor((y or 0) + 0.5)
end
local function ApplyFonts()
	label:SetFont(STANDARD_TEXT_FONT, db.labelSize, "OUTLINE")
	timerText:SetFont(STANDARD_TEXT_FONT, db.timerSize, "OUTLINE")
end
local function ApplyDoubleLineLayout()
	local align = db.textAlign or "CENTER"
	label:ClearAllPoints(); timerText:ClearAllPoints()
	label:SetWidth(CONTENT_WIDTH); timerText:SetWidth(CONTENT_WIDTH)
	label:SetJustifyH(align);      timerText:SetJustifyH(align)
	if align == "LEFT" then
		label:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -10)
		timerText:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -40)
	elseif align == "RIGHT" then
		label:SetPoint("TOPRIGHT",  content, "TOPRIGHT",  0, -10)
		timerText:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -40)
	else
		label:SetPoint("TOP",    content, "TOP", 0, -10)
		timerText:SetPoint("TOP", content, "TOP", 0, -40)
	end
end
-- 폰트·정렬 등 외형 설정이 바뀔 때만 호출
local function ApplyVisualSettings()
	ApplyFonts()
	ApplyDoubleLineLayout()
end
-- =========================================================
-- Utils
-- =========================================================
local function FormatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end
local function HardStopFade()
	UIFrameFadeRemoveFrame(frame); frame:SetAlpha(1)
end
-- =========================================================
-- Animation
-- =========================================================
local function PlayFadeInWithSlide()
	HardStopFade()
	ApplyPosition()
	if not db.animationEnabled then
		frame:SetAlpha(1); frame:Show(); return
	end
	frame:ClearAllPoints()
	frame:SetPoint(db.point, UIParent, db.relativePoint, db.x + (db.slideOffsetX or -10), db.y)
	frame:SetAlpha(0); frame:Show()
	UIFrameFadeIn(frame, db.fadeInDuration or 0.2, 0, 1)
	-- 다음 프레임에 올바른 위치로 복귀 (슬라이드 시작점 → 목표점)
	C_Timer.After(0, function()
		if not frame:IsShown() then return end
		frame:ClearAllPoints()
		frame:SetPoint(db.point, UIParent, db.relativePoint, db.x, db.y)
	end)
end
local function PlayFadeOutThen(callback)
	HardStopFade()
	if not db.animationEnabled then
		frame:SetAlpha(1); frame:Hide()
		if callback then callback() end
		return
	end
	frame:SetAlpha(1)
	UIFrameFadeOut(frame, db.fadeOutDuration or 0.2, 1, 0)
	C_Timer.After(db.fadeOutDuration or 0.2, function()
		if isInCombat then frame:SetAlpha(1); frame:Show(); return end
		frame:SetAlpha(1); frame:Hide()
		if callback then callback() end
	end)
end
-- =========================================================
-- Display
-- =========================================================
-- [FIX] 텍스트·색상만 갱신. ApplyPosition/Fonts/Layout 은 RefreshShownState 에서 담당.
local function ShowCombatState()
	local elapsed = GetTimePreciseSec() - combatStartTime
	local c1, c2  = db.combatColor, db.timerColor
	label:SetText(COMBAT_TEXT)
	label:SetTextColor(c1[1], c1[2], c1[3], c1[4])
	timerText:SetText(FormatTime(elapsed))
	timerText:SetTextColor(c2[1], c2[2], c2[3], c2[4])
	frame:Show()
end
-- 상태 전환 또는 1초 틱 시 호출: 위치·폰트 적용 후 텍스트 갱신
local function RefreshShownState()
	ApplyPosition()
	ApplyFonts()
	if isInCombat then
		ShowCombatState()
	else
		frame:Hide()
	end
end
-- =========================================================
-- Preview (잠금해제) 모드
-- =========================================================
local function StartPreviewMode()
	db.unlocked = true; db.testMode = true
	isInCombat       = true
	combatStartTime  = GetTimePreciseSec()
	elapsedAccumulator = 0
	frame:EnableMouse(true)   -- [FIX] 드래그 가능하도록 마우스 활성화
	RefreshShownState()
	PlayFadeInWithSlide()
end
local function StopPreviewMode()
	db.unlocked = false; db.testMode = false
	isInCombat       = false
	combatStartTime  = 0
	elapsedAccumulator = 0
	frame:EnableMouse(false)  -- [FIX] 잠금 시 마우스 비활성화
	PlayFadeOutThen(function() frame:Hide() end)
end
-- =========================================================
-- Combat
-- =========================================================
local function EnterCombat()
	isInCombat       = true
	db.testMode      = false
	combatStartTime  = GetTimePreciseSec()
	elapsedAccumulator = 0
	RefreshShownState()
	PlayFadeInWithSlide()
end
local function LeaveCombat()
	isInCombat       = false
	combatStartTime  = 0
	elapsedAccumulator = 0
	if db.unlocked then
		StartPreviewMode()
	elseif frame:IsShown() then   -- [FIX] 이미 숨겨진 프레임에 페이드아웃 애니메이션 방지
		PlayFadeOutThen(function() frame:Hide() end)
	end
end
-- =========================================================
-- Settings helpers
-- =========================================================
local function ResetPosition()
	db.point = defaults.point; db.relativePoint = defaults.relativePoint
	db.x = defaults.x;         db.y = defaults.y
	RefreshShownState()
end
local function OpenSettingsCategory()
	if settingsCategory and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(settingsCategory:GetID())
	end
end
-- =========================================================
-- Frame scripts
-- =========================================================
frame:SetScript("OnDragStart", function(self)
	if not db.unlocked then return end; self:StartMoving()
end)
frame:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing(); SaveCurrentPosition()
end)
frame:SetScript("OnUpdate", function(_, elapsed)
	if not isInCombat then return end
	elapsedAccumulator = elapsedAccumulator + elapsed
	if elapsedAccumulator >= 1.0 then
		elapsedAccumulator = 0
		RefreshShownState()
	end
end)
-- =========================================================
-- Settings Panel helpers
-- =========================================================
local function CreateLabel(parent, text, x, y)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); fs:SetText(text)
	return fs
end
local function CreateCheckButton(parent, labelText, initialValue, onClick, x, y)
	local btn = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
	btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	btn:SetChecked(initialValue)
	if btn.Text then btn.Text:SetText(labelText) end
	btn:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
	return btn
end
local function CreateSlider(parent, labelText, minVal, maxVal, step, initialValue, onChanged, x, y)
	local labelFS   = CreateLabel(parent, labelText, x, y)
	local valueText = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	valueText:SetPoint("LEFT", labelFS, "RIGHT", 10, 0)
	valueText:SetText(step == 1 and tostring(initialValue) or string.format("%.1f", initialValue))
	local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
	slider:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -12)
	slider:SetWidth(220); slider:SetMinMaxValues(minVal, maxVal)
	slider:SetValueStep(step); slider:SetObeyStepOnDrag(true); slider:SetValue(initialValue)
	slider:SetScript("OnValueChanged", function(_, value)
		if step == 1 then
			value = math.floor(value + 0.5); valueText:SetText(tostring(value))
		else
			value = math.floor(value * 10 + 0.5) / 10; valueText:SetText(string.format("%.1f", value))
		end
		onChanged(value)
	end)
	return slider
end
local function GetAlignLabelByKey(key)
	for _, info in ipairs(alignmentChoices) do
		if info.key == key then return info.label end
	end
	return "가운데 정렬"
end
local function BuildAlignmentDropdown(parent, x, y)
	local labelFS = CreateLabel(parent, "글자 정렬", x, y)
	local dropdown = CreateFrame("Frame", "HAN_CombatAlignmentDropdown", parent, "UIDropDownMenuTemplate")
	dropdown:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", -16, -6)
	UIDropDownMenu_SetWidth(dropdown, 140)
	UIDropDownMenu_Initialize(dropdown, function(self, level)
		for _, item in ipairs(alignmentChoices) do
			local info = UIDropDownMenu_CreateInfo()
			info.text    = item.label
			info.checked = (db.textAlign == item.key)
			info.func = function()
				db.textAlign = item.key
				UIDropDownMenu_SetSelectedName(dropdown, item.label)
				ApplyDoubleLineLayout()   -- [FIX] 레이아웃만 재적용, 전체 Refresh 불필요
				RefreshShownState()
			end
			UIDropDownMenu_AddButton(info, level)
		end
	end)
	UIDropDownMenu_SetSelectedName(dropdown, GetAlignLabelByKey(db.textAlign))
	return dropdown
end
-- =========================================================
-- Settings Panel
-- =========================================================
local function CreateSettingsPanel()
	local panel = CreateFrame("Frame")
	panel.name = "전투 상태 표시"
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", 16, -16); title:SetText("전투 상태 표시 설정")
	local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	sub:SetText("전투 진입 및 타이머 렌더링에 관한 세부 설정을 조정합니다.")
	CreateCheckButton(panel, "잠금해제 (위치 이동 + 미리보기)", db.unlocked, function(checked)
		if checked then StartPreviewMode() else StopPreviewMode() end
	end, 20, -70)
	CreateCheckButton(panel, "애니메이션 사용", db.animationEnabled, function(checked)
		db.animationEnabled = checked; RefreshShownState()
	end, 20, -105)
	CreateSlider(panel, "전투 시작 표시 시간", 0.5, 3.0, 0.1, db.startDuration,
		function(v) db.startDuration = v end, 20, -160)
	CreateSlider(panel, "상태 글자 크기", 10, 36, 1, db.labelSize, function(v)
		db.labelSize = v; ApplyVisualSettings(); RefreshShownState()
	end, 20, -255)
	CreateSlider(panel, "타이머 글자 크기", 10, 36, 1, db.timerSize, function(v)
		db.timerSize = v; ApplyVisualSettings(); RefreshShownState()
	end, 20, -350)
	BuildAlignmentDropdown(panel, 320, -70)
	CreateSlider(panel, "슬라이드 거리", -50, 50, 1, db.slideOffsetX, function(v)
		db.slideOffsetX = v; RefreshShownState()
	end, 320, -160)
	CreateSlider(panel, "페이드 인 시간", 0.0, 1.0, 0.1, db.fadeInDuration, function(v)
		db.fadeInDuration = v
	end, 320, -255)
	CreateSlider(panel, "페이드 아웃 시간", 0.0, 1.0, 0.1, db.fadeOutDuration, function(v)
		db.fadeOutDuration = v
	end, 320, -350)
	local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	resetBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 320, -445)
	resetBtn:SetSize(140, 26); resetBtn:SetText("위치 초기화")
	resetBtn:SetScript("OnClick", function() ResetPosition() end)
	local info = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	info:SetPoint("TOPLEFT", panel, "TOPLEFT", 320, -485)
	info:SetWidth(260); info:SetJustifyH("LEFT")
	info:SetText("잠금해제를 켜면 테스트모드가 함께 실행되며 드래그로 위치를 옮길 수 있습니다.")
	if Settings and Settings.RegisterCanvasLayoutSubcategory and HT and HT.OptionsCategoryID then
		local category = Settings.RegisterCanvasLayoutSubcategory(HT.OptionsCategoryID, panel, panel.name)
		settingsCategory = category
	end
end
-- =========================================================
-- Slash commands
-- =========================================================
SLASH_HANCOMBATSTATE1 = "/hcs"
SlashCmdList["HANCOMBATSTATE"] = function(msg)
	msg = (msg or ""):lower()
	if     msg == "unlock"              then StartPreviewMode(); print("|cffffd100HAN_CombatState|r 잠금해제 켜짐")
	elseif msg == "lock"                then StopPreviewMode();  print("|cffffd100HAN_CombatState|r 잠금해제 꺼짐")
	elseif msg == "reset"               then ResetPosition();    print("|cffffd100HAN_CombatState|r 위치 초기화 완료")
	elseif msg == "config" or msg == "options" then OpenSettingsCategory()
	else   print("|cffffd100HAN_CombatState|r 명령어: /hcs unlock, /hcs lock, /hcs reset, /hcs config")
	end
end
-- =========================================================
-- Events
-- =========================================================
addon:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if (...) ~= ADDON_NAME then return end
		InitDB(); ApplyPosition(); ApplyVisualSettings(); CreateSettingsPanel()
	elseif event == "PLAYER_REGEN_DISABLED" then
		if db.unlocked then db.testMode = false end
		EnterCombat()
	elseif event == "PLAYER_REGEN_ENABLED" then
		LeaveCombat()
	elseif event == "PLAYER_ENTERING_WORLD" then
		if db.unlocked then
			StartPreviewMode()
		elseif UnitAffectingCombat("player") or InCombatLockdown() then
			EnterCombat()
		else
			LeaveCombat()
		end
	end
end)
addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_REGEN_DISABLED")
addon:RegisterEvent("PLAYER_REGEN_ENABLED")
addon:RegisterEvent("PLAYER_ENTERING_WORLD")
