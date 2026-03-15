-- Modules/Resource.lua
local ADDON_NAME = ...
-- HAN_Tools 테이블 보장
local HT = _G.HAN_Tools
if not HT then
	_G.HAN_Tools = {}
	HT = _G.HAN_Tools
end
-- =========================================================
-- Defaults
-- =========================================================
local defaults = {
	enabled = true,
	fontSize = 32,
	unlocked = false,
	point = "CENTER",
	relativePoint = "CENTER",
	x = 0,
	y = -150,
	useAbsoluteValue = true, -- true: 절대값, false: %
	fontColor = { 1.0, 1.0, 1.0 },
	useCondition = false,
	-- legacy(호환): 현재 모드의 기준치를 미러
	conditionPct = 50,
	-- 모드별 기준치 저장
	conditionValueAbs = 50, -- 절대값 기준치
	conditionValuePct = 50, -- % 기준치(0~100)
	conditionColor = { 0.7, 0.2, 1.0 },
	-- 기준치 달성 시 글자 크기 변경(듀얼 FontString)
	useConditionSize = false,
	conditionFontSize = 40,
	-- 기준치 달성 시 효과음
	useConditionSound = false,
	conditionSoundCooldown = 1.0,      -- 초
	conditionSoundChannel = "Master",  -- "Master","SFX","Dialog","Music","Ambience"
	-- 선택된 사운드(두 방식 모두 지원)
	conditionSoundKey = "IG_MAINMENU_OPEN", -- SOUNDKIT 키 기반 선택(권장)
	conditionSoundKitID = 850,              -- fallback 숫자
	-- 사운드 소스: "soundkit" = SOUNDKIT ID, "file" = OGG 파일
	conditionSoundSource = "soundkit",
	conditionSoundFile = "",                -- "알림1.ogg" 등 파일명만 저장
}
local db
local frame
local Options = {}
-- =========================================================
-- Utils
-- =========================================================
local function CopyColorTable(src) return { src[1], src[2], src[3] } end
local function EnsureColorTable(tbl, fallback)
	if type(tbl) ~= "table" then return CopyColorTable(fallback) end
	return {
		tonumber(tbl[1]) or fallback[1],
		tonumber(tbl[2]) or fallback[2],
		tonumber(tbl[3]) or fallback[3],
	}
end
local function ClampNumber(v, minV, maxV)
	v = tonumber(v); if not v then return nil end
	if v < minV then v = minV end
	if v > maxV then v = maxV end
	return v
end
local function Round(v)
	v = tonumber(v); if not v then return 0 end
	if v >= 0 then return math.floor(v + 0.5) end
	return -math.floor((-v) + 0.5)
end
local function SafeNumber(v)
	if v == nil then return nil end
	local ok, n = pcall(function() return v + 0 end)
	if ok and type(n) == "number" then return n end
	return nil
end
local function NormalizeChannel(ch)
	if not ch then return "Master" end
	ch = tostring(ch)
	if ch == "Master" or ch == "SFX" or ch == "Dialog" or ch == "Music" or ch == "Ambience" then
		return ch
	end
	return "Master"
end
-- =========================================================
-- Condition Value (mode-aware)
-- =========================================================
local function GetConditionValue()
	if db.useAbsoluteValue then
		return tonumber(db.conditionValueAbs) or defaults.conditionValueAbs
	end
	return ClampNumber(tonumber(db.conditionValuePct) or defaults.conditionValuePct, 0, 100) or defaults.conditionValuePct
end
local function SetConditionValue(v)
	v = tonumber(v)
	if db.useAbsoluteValue then
		db.conditionValueAbs = v or defaults.conditionValueAbs
		db.conditionPct = db.conditionValueAbs -- legacy mirror
	else
		v = ClampNumber(v, 0, 100) or defaults.conditionValuePct
		db.conditionValuePct = v
		db.conditionPct = v -- legacy mirror
	end
end
-- =========================================================
-- DB Init
-- [FIX 1] UnitName/GetRealmName은 ADDON_LOADED 시점에 nil일 수 있음.
--         "__pending" 키로 임시 저장 후, PLAYER_ENTERING_WORLD에서
--         실제 캐릭터 키로 자동 마이그레이션.
-- =========================================================
local function GetPlayerKey()
	local player = UnitName("player")
	local realm  = GetRealmName()
	if player and player ~= "" and realm and realm ~= "" then
		return player .. "-" .. realm
	end
	return nil
end
local function InitializeDB(playerKey)
	HT.db = HT.db or {}
	HT.db.resource = HT.db.resource or {}
	local key = playerKey or "__pending"
	-- 실제 키가 생겼을 때 __pending 데이터를 마이그레이션
	if playerKey and HT.db.resource["__pending"] and not HT.db.resource[playerKey] then
		HT.db.resource[playerKey] = HT.db.resource["__pending"]
		HT.db.resource["__pending"] = nil
	end
	HT.db.resource[key] = HT.db.resource[key] or {}
	db = HT.db.resource[key]
	for k, v in pairs(defaults) do
		if db[k] == nil then
			if type(v) == "table" then
				db[k] = CopyColorTable(v)
			else
				db[k] = v
			end
		end
	end
	db.fontColor = EnsureColorTable(db.fontColor, defaults.fontColor)
	db.conditionColor = EnsureColorTable(db.conditionColor, defaults.conditionColor)
	db.fontSize = tonumber(db.fontSize) or defaults.fontSize
	db.x = tonumber(db.x) or defaults.x
	db.y = tonumber(db.y) or defaults.y
	db.conditionPct = tonumber(db.conditionPct) or defaults.conditionPct
	db.conditionFontSize = tonumber(db.conditionFontSize) or defaults.conditionFontSize
	db.useConditionSound = not not db.useConditionSound
	db.conditionSoundCooldown = tonumber(db.conditionSoundCooldown) or defaults.conditionSoundCooldown
	db.conditionSoundChannel = NormalizeChannel(db.conditionSoundChannel)
	db.conditionSoundKitID = tonumber(db.conditionSoundKitID) or defaults.conditionSoundKitID
	db.conditionSoundKey = tostring(db.conditionSoundKey or defaults.conditionSoundKey)
	db.conditionSoundSource = (db.conditionSoundSource == "file") and "file" or "soundkit"
	db.conditionSoundFile = tostring(db.conditionSoundFile or defaults.conditionSoundFile)
	-- 모드별 기준치 마이그레이션
	db.conditionValueAbs = tonumber(db.conditionValueAbs)
	db.conditionValuePct = tonumber(db.conditionValuePct)
	if db.conditionValueAbs == nil then
		db.conditionValueAbs = (db.useAbsoluteValue and db.conditionPct) or defaults.conditionValueAbs
	end
	if db.conditionValuePct == nil then
		db.conditionValuePct = ((not db.useAbsoluteValue) and db.conditionPct) or defaults.conditionValuePct
	end
	db.conditionValuePct = ClampNumber(db.conditionValuePct, 0, 100) or defaults.conditionValuePct
	db.conditionPct = GetConditionValue()
end
-- =========================================================
-- Position save
-- =========================================================
local function SavePositionFromFrame()
	if not frame then return end
	local ok, point, _, relativePoint, x, y = pcall(function()
		return frame:GetPoint(1)
	end)
	if not ok then return end
	db.point = point or db.point
	db.relativePoint = relativePoint or db.relativePoint
	db.x = Round(x or db.x)
	db.y = Round(y or db.y)
	if Options.ed_x and Options.ed_x.Refresh then Options.ed_x:Refresh() end
	if Options.ed_y and Options.ed_y.Refresh then Options.ed_y:Refresh() end
end
-- =========================================================
-- Sound
-- =========================================================
local SOUND_FOLDER = "Interface\\AddOns\\HAN_Tools\\Sound\\"
local function GetSoundFilePath()
	local file = db.conditionSoundFile
	if not file or file == "" then return nil end
	return SOUND_FOLDER .. file
end
local function ResolveSoundKitID()
	if db.conditionSoundKey and db.conditionSoundKey ~= "" and type(SOUNDKIT) == "table" then
		local id = SOUNDKIT[db.conditionSoundKey]
		if type(id) == "number" and id > 0 then
			return id, db.conditionSoundKey
		end
	end
	local kit = tonumber(db.conditionSoundKitID)
	if kit and kit > 0 then
		return kit, ""
	end
	return nil, ""
end
local function PlaySoundPreviewByID(id)
	if not id or id <= 0 then return false end
	local ch = NormalizeChannel(db.conditionSoundChannel)
	local ok, willPlay = pcall(function() return PlaySound(id, ch) end)
	if ok then return willPlay and true or false end
	return false
end
local function PlaySoundPreviewByFile(path)
	if not path or path == "" then return false end
	local ch = NormalizeChannel(db.conditionSoundChannel)
	local ok, willPlay = pcall(function() return PlaySoundFile(path, ch) end)
	if ok then return willPlay and true or false end
	return false
end
local function TryPlayThresholdSound(self)
	if not db.useConditionSound then return end
	local now = GetTime and GetTime() or 0
	local cd = tonumber(db.conditionSoundCooldown) or 1.0
	if self._lastSoundTime and now > 0 and (now - self._lastSoundTime) < cd then
		return
	end
	local ch = NormalizeChannel(db.conditionSoundChannel)
	if db.conditionSoundSource == "file" then
		local path = GetSoundFilePath()
		if path then pcall(function() PlaySoundFile(path, ch) end) end
	else
		local id = ResolveSoundKitID()
		if not id then return end
		pcall(function() PlaySound(id, ch) end)
	end
	self._lastSoundTime = now
end
-- =========================================================
-- Enable / Disable
-- =========================================================
local function Core_Enable()
	if not frame or frame._coreEnabled then return end
	frame._coreEnabled = true
	frame:SetScript("OnEvent", frame._coreOnEvent)
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	-- [FIX 3] PLAYER_SPECIALIZATION_CHANGED 등록 추가
	frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	frame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
	frame:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
	frame._lastAbove    = nil
	frame._lastSoundTime = nil
	frame._coreOnEvent(frame, "Enable", "player")
end
local function Core_Disable()
	if not frame or not frame._coreEnabled then return end
	frame._coreEnabled = false
	frame:UnregisterAllEvents()
	frame:SetScript("OnEvent", nil)
	frame:SetScript("OnUpdate", nil)
	frame._lastAbove    = nil
	frame._lastSoundTime = nil
end
local function SetEnabled(enabled)
	db.enabled = not not enabled
	if not frame then return end
	if db.enabled then
		frame:Show()
		Core_Enable()
	else
		Core_Disable()
		frame:Hide()
	end
end
-- =========================================================
-- ApplySettings
-- =========================================================
local function ApplySettings()
	if not frame then return end
	SetEnabled(db.enabled)
	frame:ClearAllPoints()
	frame:SetPoint(db.point, UIParent, db.relativePoint, db.x, db.y)
	if db.unlocked then
		frame:EnableMouse(true)
		if frame.bg then frame.bg:Show() end
	else
		frame:EnableMouse(false)
		if frame.bg then frame.bg:Hide() end
	end
	local defaultFont = (NumberFontNormal and NumberFontNormal:GetFont()) or "Fonts\\2002B.TTF"
	frame.textBase:SetFont(defaultFont, db.fontSize, "OUTLINE")
	frame.textCond:SetFont(defaultFont, db.conditionFontSize, "OUTLINE")
	frame._baseColor = EnsureColorTable(db.fontColor, defaults.fontColor)
	frame._condColor = EnsureColorTable(db.conditionColor, defaults.conditionColor)
	if Options and Options.RefreshConditionSliderSpec then
		Options:RefreshConditionSliderSpec()
	end
	if Options and Options.RefreshSoundUI then
		Options:RefreshSoundUI()
	end
	if db.enabled and frame._coreOnEvent then
		frame._coreOnEvent(frame, "ApplySettings", "player")
	end
end
-- =========================================================
-- Create tracker frame
-- =========================================================
local function CreateResourceTracker()
	if frame then return end
	frame = CreateFrame("Frame", "HAN_Tools_ResourceCore", UIParent)
	frame:SetSize(100, 50)
	frame:SetPoint(db.point, UIParent, db.relativePoint, db.x, db.y)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame.bg = frame:CreateTexture(nil, "BACKGROUND")
	frame.bg:SetAllPoints()
	frame.bg:SetColorTexture(0, 1, 0, 0.3)
	frame.bg:Hide()
	frame.textBase = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	frame.textBase:SetPoint("CENTER")
	frame.textBase:SetText("0")
	frame.textCond = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	frame.textCond:SetPoint("CENTER")
	frame.textCond:SetText("0")
	frame.textCond:SetTextColor(0, 0, 0, 0)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) if db.unlocked then self:StartMoving() end end)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePositionFromFrame() end)
	frame:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" and Settings and Settings.OpenToCategory and Options.categoryID then
			Settings.OpenToCategory(Options.categoryID)
		end
	end)
	-- =========================================================
	-- Core OnEvent
	-- [FIX 2] PLAYER_ENTERING_WORLD의 arg1은 boolean(isInitialLogin)이므로
	--         기존 "if unit and unit ~= 'player'" 가드에서 true로 판정되어
	--         즉시 return되던 버그 수정. spec 관련 이벤트를 상단에서 먼저
	--         처리하고 unit을 "player"로 보정한 뒤 표시 로직을 계속 실행.
	-- [FIX 4] % 계산: EnsurePercentCurve / CurveConstants.ScaleTo100 제거
	--         → UnitPower / UnitPowerMax * 100 단순 계산으로 대체
	-- [FIX 5] 조건 색상: C_CurveUtil 없을 때 conditionColor 미적용 버그 수정
	--         → 단순 임계값 비교(isAbove)로 완전 대체
	-- =========================================================
	frame._coreOnEvent = function(self, event, unit)
		-- [FIX 2] spec 변경/진입 이벤트: 먼저 처리하고 unit을 보정
		if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" then
			unit = "player"
		end
		if unit and unit ~= "player" then return end
		if not db.enabled then return end
		local pType = UnitPowerType("player")
		local threshold = GetConditionValue()
		local isAbsolute = db.useAbsoluteValue
		local specIndex = GetSpecialization and GetSpecialization()
		if specIndex then
			local specID = GetSpecializationInfo(specIndex)
			-- ── 전사 ──
			if     specID == 71 then isAbsolute = true;  pType = Enum.PowerType.Rage
			elseif specID == 72 then isAbsolute = true;  pType = Enum.PowerType.Rage
			elseif specID == 73 then isAbsolute = true;  pType = Enum.PowerType.Rage
			-- ── 성기사 ──
			elseif specID == 65 then isAbsolute = false; pType = Enum.PowerType.Mana
			elseif specID == 66 then isAbsolute = true;  pType = Enum.PowerType.HolyPower
			elseif specID == 70 then isAbsolute = true;  pType = Enum.PowerType.HolyPower
			-- ── 사냥꾼 ──
			elseif specID == 253 then isAbsolute = true; pType = Enum.PowerType.Focus
			elseif specID == 254 then isAbsolute = true; pType = Enum.PowerType.Focus
			elseif specID == 255 then isAbsolute = true; pType = Enum.PowerType.Focus
			-- ── 도적 ──
			elseif specID == 259 then isAbsolute = true; pType = Enum.PowerType.ComboPoints
			elseif specID == 260 then isAbsolute = true; pType = Enum.PowerType.ComboPoints
			elseif specID == 261 then isAbsolute = true; pType = Enum.PowerType.ComboPoints
			-- ── 사제 ──
			elseif specID == 256 then isAbsolute = false; pType = Enum.PowerType.Mana
			elseif specID == 257 then isAbsolute = false; pType = Enum.PowerType.Mana
			elseif specID == 258 then isAbsolute = true;  pType = Enum.PowerType.Insanity
			-- ── 죽음의 기사 ──
			elseif specID == 250 then isAbsolute = true; pType = Enum.PowerType.RunicPower
			elseif specID == 251 then isAbsolute = true; pType = Enum.PowerType.RunicPower
			elseif specID == 252 then isAbsolute = true; pType = Enum.PowerType.RunicPower
			-- ── 주술사 ──
			elseif specID == 262 then isAbsolute = true;  pType = Enum.PowerType.Maelstrom
			elseif specID == 263 then isAbsolute = false; pType = Enum.PowerType.Mana
			elseif specID == 264 then isAbsolute = false; pType = Enum.PowerType.Mana
			-- ── 흑마법사 ──
			elseif specID == 265 then isAbsolute = true; pType = Enum.PowerType.SoulShards
			elseif specID == 266 then isAbsolute = true; pType = Enum.PowerType.SoulShards
			elseif specID == 267 then isAbsolute = true; pType = Enum.PowerType.SoulShards
			-- ── 수도사 ──
			elseif specID == 268 then isAbsolute = true;  pType = Enum.PowerType.Energy
			elseif specID == 269 then isAbsolute = true;  pType = Enum.PowerType.Chi
			elseif specID == 270 then isAbsolute = false; pType = Enum.PowerType.Mana
			-- ── 드루이드 ──
			elseif specID == 102 then isAbsolute = true;  pType = Enum.PowerType.LunarPower
			elseif specID == 103 then isAbsolute = true;  pType = Enum.PowerType.ComboPoints
			elseif specID == 104 then isAbsolute = true;  pType = Enum.PowerType.Rage
			elseif specID == 105 then isAbsolute = false; pType = Enum.PowerType.Mana
			-- ── 악마사냥꾼 ──
			elseif specID == 577 then isAbsolute = true; pType = Enum.PowerType.Fury
			elseif specID == 581 then isAbsolute = true; pType = Enum.PowerType.Pain
			-- ── 마법사 ──
			elseif specID == 62 then isAbsolute = true;  pType = Enum.PowerType.ArcaneCharges
			elseif specID == 63 then isAbsolute = false; pType = Enum.PowerType.Mana
			elseif specID == 64 then isAbsolute = false; pType = Enum.PowerType.Mana
			-- ── 에보커 ──
			elseif specID == 1467 then isAbsolute = true;  pType = Enum.PowerType.Essence
			elseif specID == 1468 then isAbsolute = false; pType = Enum.PowerType.Mana
			elseif specID == 1473 then isAbsolute = false; pType = Enum.PowerType.Mana
			end
		end
		-- 1) 텍스트 표시
		local curForSound = nil
		if isAbsolute then
			local cur = UnitPower("player", pType)
			self.textBase:SetText(cur)
			self.textCond:SetText(cur)
			curForSound = SafeNumber(cur)
		else
			-- [FIX 4] UnitPower / UnitPowerMax 단순 나눗셈 (커브 의존 완전 제거)
			local cur = UnitPower("player", pType)
			local max = UnitPowerMax("player", pType)
			local p = (max and max > 0) and math.floor(cur / max * 100 + 0.5) or 0
			self.textBase:SetFormattedText("%d%%", p)
			self.textCond:SetFormattedText("%d%%", p)
			curForSound = p
		end
		-- 2) 조건부 색/크기
		-- [FIX 5] C_CurveUtil 의존 완전 제거 → 단순 임계값 비교
		local base = self._baseColor or defaults.fontColor
		local cond = self._condColor or defaults.conditionColor
		local rB, gB, bB = base[1], base[2], base[3]
		local rC, gC, bC = cond[1], cond[2], cond[3]
		if db.useCondition and curForSound ~= nil then
			local isAbove = (curForSound >= threshold)
			if isAbove and db.useConditionSize then
				-- 크기 변경 모드: base 투명 → cond(큰 폰트) 표시
				self.textBase:SetTextColor(0, 0, 0, 0)
				self.textCond:SetTextColor(rC, gC, bC, 1)
			elseif isAbove then
				-- 색상만 변경
				self.textBase:SetTextColor(rC, gC, bC, 1)
				self.textCond:SetTextColor(0, 0, 0, 0)
			else
				self.textBase:SetTextColor(rB, gB, bB, 1)
				self.textCond:SetTextColor(0, 0, 0, 0)
			end
		else
			self.textBase:SetTextColor(rB, gB, bB, 1)
			self.textCond:SetTextColor(0, 0, 0, 0)
		end
		-- 3) 기준치 상향 돌파 시 사운드
		if db.useConditionSound and curForSound ~= nil then
			local isAbove = (curForSound >= threshold)
			if self._lastAbove == nil then
				self._lastAbove = isAbove
			else
				if (not self._lastAbove) and isAbove then
					TryPlayThresholdSound(self)
				end
				self._lastAbove = isAbove
			end
		else
			self._lastAbove = nil
		end
	end
end
-- =========================================================
-- Options UI helpers
-- =========================================================
local function CreateSliderOption(parent, labelText, x, y, minV, maxV, step, getter, setter)
	local c = CreateFrame("Frame", nil, parent)
	c:SetSize(260, 60)
	c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	c.minV, c.maxV, c.step = minV, maxV, step
	local t = c:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	t:SetPoint("TOP", c, "TOP", 0, 0)
	t:SetText(labelText)
	t:SetTextColor(1, 0.82, 0)
	local s = CreateFrame("Slider", nil, c, "UISliderTemplate")
	s:SetSize(200, 15)
	s:SetPoint("TOP", t, "BOTTOM", 0, -10)
	local eb = CreateFrame("EditBox", nil, c, "InputBoxTemplate")
	eb:SetSize(70, 20)
	eb:SetPoint("TOP", s, "BOTTOM", 0, -2)
	eb:SetAutoFocus(false)
	eb:SetJustifyH("CENTER")
	local syncing = false
	local function UpdateValues(val)
		if syncing then return end
		syncing = true
		val = ClampNumber(val, c.minV, c.maxV) or getter()
		if c.step and c.step > 0 then
			val = math.floor((val / c.step) + 0.5) * c.step
		end
		s:SetValue(val)
		eb:SetText(tostring(val))
		eb:SetCursorPosition(0)
		setter(val)
		ApplySettings()
		syncing = false
	end
	function c:SetLabel(newLabel) t:SetText(newLabel) end
	function c:SetRange(newMin, newMax, newStep)
		c.minV = newMin
		c.maxV = newMax
		if newStep then c.step = newStep end
		s:SetMinMaxValues(c.minV, c.maxV)
		s:SetValueStep(c.step)
		s:SetObeyStepOnDrag(true)
		c:Refresh()
	end
	s:SetMinMaxValues(c.minV, c.maxV)
	s:SetValueStep(c.step)
	s:SetObeyStepOnDrag(true)
	s:SetScript("OnValueChanged", function(_, value) UpdateValues(value) end)
	eb:SetScript("OnEnterPressed", function(self) self:ClearFocus(); UpdateValues(tonumber(self:GetText())) end)
	eb:SetScript("OnEditFocusLost", function(self) UpdateValues(tonumber(self:GetText())) end)
	function c:Refresh()
		syncing = true
		local val = getter()
		s:SetValue(val)
		eb:SetText(tostring(val))
		eb:SetCursorPosition(0)
		syncing = false
	end
	c:HookScript("OnShow", function() c:Refresh() end)
	eb:HookScript("OnShow", function() c:Refresh() end)
	c:Refresh()
	return c
end
local function CreateColorPickerRow(parent, label, x, y, getter, setter)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	fs:SetText(label)
	local swatchBg = parent:CreateTexture(nil, "BACKGROUND")
	swatchBg:SetSize(22, 22)
	swatchBg:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 140, y + 2)
	swatchBg:SetColorTexture(0.3, 0.3, 0.3)
	local swatch = parent:CreateTexture(nil, "ARTWORK")
	swatch:SetSize(18, 18)
	swatch:SetPoint("CENTER", swatchBg, "CENTER", 0, 0)
	local function Refresh()
		local c = EnsureColorTable(getter(), { 1, 1, 1 })
		swatch:SetColorTexture(c[1], c[2], c[3], 1)
	end
	Refresh()
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetSize(80, 22)
	btn:SetPoint("LEFT", swatchBg, "RIGHT", 12, 0)
	btn:SetText("변경")
	btn:SetScript("OnClick", function()
		local c = EnsureColorTable(getter(), { 1, 1, 1 })
		local pr, pg, pb = c[1], c[2], c[3]
		local function ApplyColor(r, g, b)
			setter({ r, g, b }); Refresh(); ApplySettings()
		end
		if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
			ColorPickerFrame:Hide()
			ColorPickerFrame:SetupColorPickerAndShow({
				r = pr, g = pg, b = pb,
				hasOpacity = false,
				swatchFunc = function()
					local r, g, b = ColorPickerFrame:GetColorRGB()
					ApplyColor(r, g, b)
				end,
				cancelFunc = function() ApplyColor(pr, pg, pb) end,
			})
		end
	end)
	return { Refresh = Refresh }
end
-- =========================================================
-- Sound selector popup
-- =========================================================
local function BuildSoundCatalog()
	local list = {}
	if type(SOUNDKIT) ~= "table" then return list end
	for k, v in pairs(SOUNDKIT) do
		if type(k) == "string" and type(v) == "number" and v > 0 then
			list[#list+1] = { key = k, id = v }
		end
	end
	table.sort(list, function(a, b)
		if a.key == b.key then return a.id < b.id end
		return a.key < b.key
	end)
	return list
end
local function EnsureSoundPopup()
	if Options.soundPopup then return end
	local popup = CreateFrame("Frame", nil, Options.frame, "BackdropTemplate")
	popup:SetSize(520, 380)
	popup:SetFrameStrata("DIALOG")
	popup:SetClampedToScreen(true)
	popup:SetBackdrop({
		bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
		tile=true, tileSize=32, edgeSize=32,
		insets={left=11,right=12,top=12,bottom=11}
	})
	popup:Hide()
	tinsert(UISpecialFrames, popup:GetName() or "HAN_Tools_SoundPopup")
	local title = popup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("효과음 선택 (SOUNDKIT)")
	local close = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)
	local search = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
	search:SetSize(220, 22)
	search:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	search:SetAutoFocus(false)
	search:SetJustifyH("LEFT")
	search:SetText("")
	search:SetScript("OnEscapePressed", function(self) self:ClearFocus(); popup:Hide() end)
	local sf = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
	sf:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -12)
	sf:SetPoint("BOTTOMRIGHT", -30, 18)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(1, 1)
	sf:SetScrollChild(child)
	popup._search = search
	popup._scroll = sf
	popup._child = child
	popup._rows = {}
	popup._catalog = BuildSoundCatalog()
	popup._filtered = popup._catalog
	popup._debounce = nil
	local function GetSelectedID()
		return ResolveSoundKitID()
	end
	local function SetSelectionFromRow(key, id)
		db.conditionSoundKey = key or ""
		db.conditionSoundKitID = tonumber(id) or db.conditionSoundKitID
		if Options.RefreshSoundUI then Options:RefreshSoundUI() end
		ApplySettings()
	end
	local function RefreshRows()
		local filter = popup._filtered
		for i = 1, #popup._rows do
			popup._rows[i]:Hide()
		end
		local selId, selKey = GetSelectedID()
		local y = -4
		local rowH = 24
		for i = 1, #filter do
			local item = filter[i]
			local row = popup._rows[i]
			if not row then
				row = CreateFrame("Button", nil, child)
				row:SetSize(460, rowH)
				row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
				row.text = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
				row.text:SetPoint("LEFT", 4, 0)
				row.text:SetJustifyH("LEFT")
				row.play = CreateFrame("Button", nil, row)
				row.play:SetSize(18, 18)
				row.play:SetPoint("RIGHT", -6, 0)
				row.play.tex = row.play:CreateTexture(nil, "ARTWORK")
				row.play.tex:SetAllPoints()
				row.play.tex:SetTexture("Interface\\COMMON\\VoiceChat-Speaker")
				row.play:SetScript("OnClick", function(selfBtn)
					local parentRow = selfBtn:GetParent()
					PlaySoundPreviewByID(parentRow._id)
				end)
				row:SetScript("OnClick", function(selfRow)
					SetSelectionFromRow(selfRow._key, selfRow._id)
					popup:Hide()
				end)
				popup._rows[i] = row
			end
			row._key = item.key
			row._id = item.id
			local selected = (selId == item.id) or (selKey ~= "" and selKey == item.key)
			if selected then
				row.text:SetTextColor(0.2, 1, 0.2)
			else
				row.text:SetTextColor(1, 0.82, 0)
			end
			row.text:SetText(string.format("%s  (ID: %d)", item.key, item.id))
			row:SetPoint("TOPLEFT", 4, y)
			row:Show()
			y = y - rowH
		end
		child:SetHeight(math.max(1, -y + 20))
	end
	local function ApplyFilter()
		local q = tostring(search:GetText() or ""):lower()
		if q == "" then
			popup._filtered = popup._catalog
			RefreshRows()
			return
		end
		local out = {}
		for _, item in ipairs(popup._catalog) do
			if tostring(item.key):lower():find(q, 1, true) or tostring(item.id):find(q, 1, true) then
				out[#out+1] = item
			end
		end
		popup._filtered = out
		RefreshRows()
	end
	search:SetScript("OnTextChanged", function()
		if popup._debounce then popup._debounce:Cancel() end
		popup._debounce = C_Timer.NewTimer(0.12, function()
			if popup:IsShown() then ApplyFilter() end
		end)
	end)
	popup:SetScript("OnShow", function()
		popup._catalog = BuildSoundCatalog()
		popup._filtered = popup._catalog
		search:SetText("")
		RefreshRows()
	end)
	Options.soundPopup = popup
end
-- =========================================================
-- Build Options Panel (Scrollable)
-- =========================================================
local function BuildOptionsPanel()
	if Options.frame then return end
	local f = CreateFrame("Frame", "HAN_Tools_ResourceOptions", UIParent)
	f.name = "자원 추적 (%)"
	Options.frame = f
	local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -8)
	scroll:SetPoint("BOTTOMRIGHT", -26, 8)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	Options.scroll = scroll
	Options.content = content
	local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("HAN TOOLS: 자원 추적기 (색/크기/사운드)")
	local y = -60
	Options.cb_enabled = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
	Options.cb_enabled:SetPoint("TOPLEFT", 16, y)
	Options.cb_enabled.Text:SetText("사용")
	Options.cb_enabled:SetChecked(db.enabled)
	Options.cb_enabled:SetScript("OnClick", function(self)
		SetEnabled(self:GetChecked())
		ApplySettings()
	end)
	y = y - 30
	Options.cb_unlock = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
	Options.cb_unlock:SetPoint("TOPLEFT", 16, y)
	Options.cb_unlock.Text:SetText("잠금 해제 (마우스 드래그)")
	Options.cb_unlock:SetChecked(db.unlocked)
	Options.cb_unlock:SetScript("OnClick", function(self)
		db.unlocked = self:GetChecked()
		ApplySettings()
	end)
	y = y - 40
	Options.cb_absolute = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
	Options.cb_absolute:SetPoint("TOPLEFT", 16, y)
	Options.cb_absolute.Text:SetText("백분율(%) 대신 절대 수치 표시")
	Options.cb_absolute:SetChecked(db.useAbsoluteValue)
	Options.cb_absolute:SetScript("OnClick", function(self)
		db.useAbsoluteValue = self:GetChecked()
		db.conditionPct = GetConditionValue()
		ApplySettings()
	end)
	y = y - 60
	Options.ed_x = CreateSliderOption(content, "X 좌표", 16, y, -2000, 2000, 1, function() return db.x end, function(v) db.x = v end)
	Options.ed_y = CreateSliderOption(content, "Y 좌표", 310, y, -2000, 2000, 1, function() return db.y end, function(v) db.y = v end)
	y = y - 70
	Options.ed_fontSize = CreateSliderOption(content, "기본 글자 크기", 16, y, 10, 128, 1, function() return db.fontSize end, function(v) db.fontSize = v end)
	y = y - 60
	Options.cp_fontColor = CreateColorPickerRow(content, "기본 글자 색상", 16, y, function() return db.fontColor end, function(v) db.fontColor = EnsureColorTable(v, defaults.fontColor) end)
	y = y - 50
	Options.cb_condition = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
	Options.cb_condition:SetPoint("TOPLEFT", 16, y)
	Options.cb_condition.Text:SetText("기준치 기능 사용(색/크기)")
	Options.cb_condition:SetChecked(db.useCondition)
	Options.cb_condition:SetScript("OnClick", function(self)
		db.useCondition = self:GetChecked()
		ApplySettings()
	end)
	y = y - 40
	Options.ed_conditionPct = CreateSliderOption(
		content, "기준 수치", 16, y, 0, 1000, 1,
		function() return GetConditionValue() end,
		function(v) SetConditionValue(v) end
	)
	Options.cp_conditionColor = CreateColorPickerRow(content, "조건 달성 색상", 310, y,
		function() return db.conditionColor end,
		function(v) db.conditionColor = EnsureColorTable(v, defaults.conditionColor) end
	)
	y = y - 80
	Options.cb_conditionSize = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
	Options.cb_conditionSize:SetPoint("TOPLEFT", 16, y)
	Options.cb_conditionSize.Text:SetText("기준치 달성 시 글자 크기 변경")
	Options.cb_conditionSize:SetChecked(db.useConditionSize)
	Options.cb_conditionSize:SetScript("OnClick", function(self)
		db.useConditionSize = self:GetChecked()
		ApplySettings()
	end)
	y = y - 40
	Options.ed_conditionFontSize = CreateSliderOption(content, "조건 글자 크기", 16, y, 10, 128, 1,
		function() return db.conditionFontSize end,
		function(v) db.conditionFontSize = v end
	)
	y = y - 80
	Options.cb_sound = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
	Options.cb_sound:SetPoint("TOPLEFT", 16, y)
	Options.cb_sound.Text:SetText("기준치 상향 돌파 시 효과음")
	Options.cb_sound:SetChecked(db.useConditionSound)
	Options.cb_sound:SetScript("OnClick", function(self)
		db.useConditionSound = self:GetChecked()
		ApplySettings()
	end)
	y = y - 40
	Options.ed_soundCooldown = CreateSliderOption(content, "효과음 쿨다운(초)", 16, y, 0.0, 10.0, 0.1,
		function() return tonumber(db.conditionSoundCooldown) or defaults.conditionSoundCooldown end,
		function(v) db.conditionSoundCooldown = v end
	)
	y = y - 70
	Options.soundSelectBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	Options.soundSelectBtn:SetSize(360, 24)
	Options.soundSelectBtn:SetPoint("TOPLEFT", 16, y)
	Options.soundSelectBtn:SetText("효과음: (선택)")
	Options.soundSelectBtn:SetScript("OnClick", function()
		EnsureSoundPopup()
		Options.soundPopup:ClearAllPoints()
		Options.soundPopup:SetPoint("TOPLEFT", Options.soundSelectBtn, "BOTTOMLEFT", -8, -8)
		Options.soundPopup:Show()
	end)
	Options.soundPreviewBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	Options.soundPreviewBtn:SetSize(90, 24)
	Options.soundPreviewBtn:SetPoint("LEFT", Options.soundSelectBtn, "RIGHT", 10, 0)
	Options.soundPreviewBtn:SetText("미리듣기")
	Options.soundPreviewBtn:SetScript("OnClick", function()
		local id = ResolveSoundKitID()
		PlaySoundPreviewByID(id)
	end)
	y = y - 40
	Options.soundChannelBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	Options.soundChannelBtn:SetSize(180, 24)
	Options.soundChannelBtn:SetPoint("TOPLEFT", 16, y)
	Options.soundChannelBtn:SetText("채널: " .. NormalizeChannel(db.conditionSoundChannel))
	Options.soundChannelBtn:SetScript("OnClick", function()
		local order = { "Master", "SFX", "Dialog", "Music", "Ambience" }
		local cur = NormalizeChannel(db.conditionSoundChannel)
		local idx = 1
		for i = 1, #order do if order[i] == cur then idx = i break end end
		idx = idx + 1; if idx > #order then idx = 1 end
		db.conditionSoundChannel = order[idx]
		Options.soundChannelBtn:SetText("채널: " .. NormalizeChannel(db.conditionSoundChannel))
		ApplySettings()
	end)
	Options.ed_soundKit = CreateSliderOption(content, "SoundKit ID(직접)", 310, y + 6, 0, 200000, 1,
		function() return tonumber(db.conditionSoundKitID) or defaults.conditionSoundKitID end,
		function(v)
			db.conditionSoundKitID = v
			db.conditionSoundKey = ""
		end
	)
	y = y - 90
	-- ── 사운드 소스 전환 버튼 ──
	Options.soundSourceBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	Options.soundSourceBtn:SetSize(200, 24)
	Options.soundSourceBtn:SetPoint("TOPLEFT", 16, y)
	Options.soundSourceBtn:SetText(db.conditionSoundSource == "file" and "소스: OGG 파일" or "소스: SOUNDKIT")
	Options.soundSourceBtn:SetScript("OnClick", function()
		if db.conditionSoundSource == "file" then
			db.conditionSoundSource = "soundkit"
		else
			db.conditionSoundSource = "file"
		end
		if Options.RefreshSoundUI then Options:RefreshSoundUI() end
		ApplySettings()
	end)
	y = y - 34
	-- ── OGG 파일명 입력 ──
	Options.fileLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	Options.fileLabel:SetPoint("TOPLEFT", 16, y)
	Options.fileLabel:SetText("OGG 파일명 (HAN_Tools\\Sound\\ 폴더 내):")
	Options.fileLabel:SetTextColor(1, 0.82, 0)
	y = y - 20
	Options.fileEditBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
	Options.fileEditBox:SetSize(320, 22)
	Options.fileEditBox:SetPoint("TOPLEFT", 16, y)
	Options.fileEditBox:SetAutoFocus(false)
	Options.fileEditBox:SetJustifyH("LEFT")
	Options.fileEditBox:SetText(db.conditionSoundFile or "")
	Options.fileEditBox:SetScript("OnEnterPressed", function(self)
		db.conditionSoundFile = self:GetText():trim()
		self:ClearFocus()
		if Options.RefreshSoundUI then Options:RefreshSoundUI() end
		ApplySettings()
	end)
	Options.fileEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	-- 미리듣기 버튼
	Options.filePreviewBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	Options.filePreviewBtn:SetSize(90, 22)
	Options.filePreviewBtn:SetPoint("LEFT", Options.fileEditBox, "RIGHT", 10, 0)
	Options.filePreviewBtn:SetText("미리듣기")
	Options.filePreviewBtn:SetScript("OnClick", function()
		local file = Options.fileEditBox:GetText():trim()
		if file ~= "" then
			db.conditionSoundFile = file
			local path = GetSoundFilePath()
			if path then
				local played = PlaySoundPreviewByFile(path)
				if not played then
					print("|cFFFF4444[HAN_Tools]|r 파일을 찾을 수 없습니다: " .. path)
				end
			end
		else
			print("|cFFFF4444[HAN_Tools]|r 파일명을 입력하세요.")
		end
	end)
	y = y - 34
	-- 도움말
	local helpText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	helpText:SetPoint("TOPLEFT", 16, y)
	helpText:SetWidth(480)
	helpText:SetJustifyH("LEFT")
	helpText:SetText(
		"|cFF888888예시: alert.ogg, ding.ogg\n" ..
		"경로: Interface\\AddOns\\HAN_Tools\\Sound\\파일명.ogg\n" ..
		".ogg 확장자를 포함해서 입력하세요.|r"
	)
	y = y - 50
	function Options:RefreshConditionSliderSpec()
		if not self.ed_conditionPct then return end
		if db.useAbsoluteValue then
			self.ed_conditionPct:SetLabel("기준 수치 (이 값 이상일 때 발동)")
			self.ed_conditionPct:SetRange(0, 1000, 1)
		else
			self.ed_conditionPct:SetLabel("기준 퍼센트 (0~100, 이 값 이상일 때 발동)")
			self.ed_conditionPct:SetRange(0, 100, 1)
		end
	end
	function Options:RefreshSoundUI()
		if not self.soundSelectBtn then return end
		if db.conditionSoundSource == "file" then
			local file = db.conditionSoundFile or ""
			if file ~= "" then
				self.soundSelectBtn:SetText(string.format("효과음: %s (OGG 파일)", file))
			else
				self.soundSelectBtn:SetText("효과음: (OGG 파일 미선택)")
			end
		else
			local id, key = ResolveSoundKitID()
			if id then
				if key and key ~= "" then
					self.soundSelectBtn:SetText(string.format("효과음: %s (ID:%d)", key, id))
				else
					self.soundSelectBtn:SetText(string.format("효과음: Custom ID:%d", id))
				end
			else
				self.soundSelectBtn:SetText("효과음: (없음)")
			end
		end
		if self.soundChannelBtn then
			self.soundChannelBtn:SetText("채널: " .. NormalizeChannel(db.conditionSoundChannel))
		end
		if self.soundSourceBtn then
			if db.conditionSoundSource == "file" then
				self.soundSourceBtn:SetText("소스: OGG 파일")
			else
				self.soundSourceBtn:SetText("소스: SOUNDKIT")
			end
		end
		if self.fileEditBox then
			if db.conditionSoundSource == "file" then
				self.fileEditBox:Show()
				self.filePreviewBtn:Show()
				if self.fileLabel then self.fileLabel:Show() end
			else
				self.fileEditBox:Hide()
				self.filePreviewBtn:Hide()
				if self.fileLabel then self.fileLabel:Hide() end
			end
		end
	end
	function Options:RefreshAll()
		if self.cb_enabled   then self.cb_enabled:SetChecked(db.enabled) end
		if self.cb_unlock    then self.cb_unlock:SetChecked(db.unlocked) end
		if self.cb_absolute  then self.cb_absolute:SetChecked(db.useAbsoluteValue) end
		if self.cb_condition then self.cb_condition:SetChecked(db.useCondition) end
		if self.cb_conditionSize then self.cb_conditionSize:SetChecked(db.useConditionSize) end
		if self.cb_sound     then self.cb_sound:SetChecked(db.useConditionSound) end
		if self.ed_x         then self.ed_x:Refresh() end
		if self.ed_y         then self.ed_y:Refresh() end
		if self.ed_fontSize  then self.ed_fontSize:Refresh() end
		self:RefreshConditionSliderSpec()
		if self.ed_conditionPct    then self.ed_conditionPct:Refresh() end
		if self.ed_conditionFontSize then self.ed_conditionFontSize:Refresh() end
		if self.ed_soundCooldown   then self.ed_soundCooldown:Refresh() end
		if self.ed_soundKit        then self.ed_soundKit:Refresh() end
		if self.fileEditBox        then
			self.fileEditBox:SetText(db.conditionSoundFile or "")
		end
		self:RefreshSoundUI()
	end
	content:SetHeight(math.max(600, -y + 60))
	f:SetScript("OnShow", function()
		C_Timer.After(0.05, function()
			if Options.RefreshAll then Options:RefreshAll() end
		end)
	end)
	if Settings and Settings.RegisterCanvasLayoutSubcategory and HT and HT.OptionsCategoryID then
		local category = Settings.RegisterCanvasLayoutSubcategory(HT.OptionsCategoryID, f, f.name)
		Options.categoryID = category:GetID()
	end
end
-- =========================================================
-- Events
-- =========================================================
local EventFrame = CreateFrame("Frame")
EventFrame:RegisterEvent("ADDON_LOADED")
-- [FIX 1] PLAYER_ENTERING_WORLD 등록: DB 키 마이그레이션 처리
EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
EventFrame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		-- ADDON_LOADED 시점에 UnitName이 nil일 수 있으므로 GetPlayerKey() 우선 시도,
		-- 실패하면 "__pending" 키로 임시 저장
		InitializeDB(GetPlayerKey())
		CreateResourceTracker()
		BuildOptionsPanel()
		ApplySettings()
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- 플레이어 정보가 확정된 시점: 실제 캐릭터 키로 DB 마이그레이션
		local key = GetPlayerKey()
		if key then
			InitializeDB(key)
		end
	end
end)
