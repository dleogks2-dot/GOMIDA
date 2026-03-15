-- Modules/Resource.lua
local ADDON_NAME = ...
local HT = _G.HAN_Tools or {}; _G.HAN_Tools = HT
-- =========================================================
-- Defaults
-- =========================================================
local defaults = {
	enabled=true, fontSize=32, unlocked=false,
	point="CENTER", relativePoint="CENTER", x=0, y=-150,
	useAbsoluteValue=true, fontColor={1,1,1},
	useCondition=false, conditionPct=50, conditionValueAbs=50, conditionValuePct=50,
	conditionColor={0.7,0.2,1.0}, useConditionSize=false, conditionFontSize=40,
	useConditionSound=false, conditionSoundCooldown=1.0, conditionSoundChannel="Master",
	conditionSoundKey="IG_MAINMENU_OPEN", conditionSoundKitID=850,
	conditionSoundSource="soundkit", conditionSoundFile="",
}
local db, frame
local Options = {}
-- =========================================================
-- 전문화별 자원 설정 테이블 { isAbsolute, PowerType }
-- =========================================================
local P = Enum.PowerType
local SPEC_CONFIG = {
	-- 전사
	[71]={true,P.Rage},         [72]={true,P.Rage},          [73]={true,P.Rage},
	-- 성기사
	[65]={false,P.Mana},        [66]={true,P.HolyPower},     [70]={true,P.HolyPower},
	-- 사냥꾼
	[253]={true,P.Focus},       [254]={true,P.Focus},         [255]={true,P.Focus},
	-- 도적
	[259]={true,P.ComboPoints}, [260]={true,P.ComboPoints},   [261]={true,P.ComboPoints},
	-- 사제
	[256]={false,P.Mana},       [257]={false,P.Mana},         [258]={true,P.Insanity},
	-- 죽음의 기사
	[250]={true,P.RunicPower},  [251]={true,P.RunicPower},    [252]={true,P.RunicPower},
	-- 주술사
	[262]={true,P.Maelstrom},   [263]={false,P.Mana},         [264]={false,P.Mana},
	-- 흑마법사
	[265]={true,P.SoulShards},  [266]={true,P.SoulShards},    [267]={true,P.SoulShards},
	-- 수도사
	[268]={true,P.Energy},      [269]={true,P.Chi},           [270]={false,P.Mana},
	-- 드루이드
	[102]={true,P.LunarPower},  [103]={true,P.ComboPoints},   [104]={true,P.Rage},    [105]={false,P.Mana},
	-- 악마사냥꾼
	[577]={true,P.Fury},        [581]={true,P.Pain},
	-- 마법사
	[62]={true,P.ArcaneCharges},[63]={false,P.Mana},          [64]={false,P.Mana},
	-- 에보커
	[1467]={true,P.Essence},    [1468]={false,P.Mana},        [1473]={false,P.Mana},
}
-- =========================================================
-- Utils
-- =========================================================
local function CopyColorTable(src) return { src[1], src[2], src[3] } end
local function EnsureColorTable(tbl, fallback)
	if type(tbl) ~= "table" then return CopyColorTable(fallback) end
	return { tonumber(tbl[1]) or fallback[1], tonumber(tbl[2]) or fallback[2], tonumber(tbl[3]) or fallback[3] }
end
local function ClampNumber(v, minV, maxV)
	v = tonumber(v); return v and math.max(minV, math.min(maxV, v)) or nil
end
local function Round(v)
	v = tonumber(v); if not v then return 0 end
	return math.floor(v + 0.5) * (v >= 0 and 1 or -1) -- 음수 포함 반올림
end
local VALID_CHANNELS = { Master=true, SFX=true, Dialog=true, Music=true, Ambience=true }
local function NormalizeChannel(ch)
	ch = tostring(ch or "")
	return VALID_CHANNELS[ch] and ch or "Master"
end
-- =========================================================
-- Condition Value (mode-aware)
-- =========================================================
local function GetConditionValue()
	if db.useAbsoluteValue then
		return tonumber(db.conditionValueAbs) or defaults.conditionValueAbs
	end
	return ClampNumber(db.conditionValuePct, 0, 100) or defaults.conditionValuePct
end
local function SetConditionValue(v)
	v = tonumber(v)
	if db.useAbsoluteValue then
		db.conditionValueAbs = v or defaults.conditionValueAbs
		db.conditionPct = db.conditionValueAbs
	else
		v = ClampNumber(v, 0, 100) or defaults.conditionValuePct
		db.conditionValuePct = v; db.conditionPct = v
	end
end
-- =========================================================
-- DB Init
-- [FIX 1] ADDON_LOADED 시점에 UnitName이 nil일 수 있음 → "__pending" 임시 저장,
--         PLAYER_ENTERING_WORLD에서 실제 캐릭터 키로 자동 마이그레이션.
-- =========================================================
local function GetPlayerKey()
	local p, r = UnitName("player"), GetRealmName()
	return (p and p ~= "" and r and r ~= "") and (p.."-"..r) or nil
end
local function InitializeDB(playerKey)
	HT.db = HT.db or {}
	HT.db.resource = HT.db.resource or {}
	local key = playerKey or "__pending"
	if playerKey and HT.db.resource["__pending"] and not HT.db.resource[playerKey] then
		HT.db.resource[playerKey] = HT.db.resource["__pending"]
		HT.db.resource["__pending"] = nil
	end
	HT.db.resource[key] = HT.db.resource[key] or {}
	db = HT.db.resource[key]
	for k, v in pairs(defaults) do
		if db[k] == nil then db[k] = type(v) == "table" and CopyColorTable(v) or v end
	end
	db.fontColor      = EnsureColorTable(db.fontColor, defaults.fontColor)
	db.conditionColor = EnsureColorTable(db.conditionColor, defaults.conditionColor)
	db.fontSize           = tonumber(db.fontSize)           or defaults.fontSize
	db.x                  = tonumber(db.x)                  or defaults.x
	db.y                  = tonumber(db.y)                  or defaults.y
	db.conditionPct       = tonumber(db.conditionPct)       or defaults.conditionPct
	db.conditionFontSize  = tonumber(db.conditionFontSize)  or defaults.conditionFontSize
	db.useConditionSound  = not not db.useConditionSound
	db.conditionSoundCooldown = tonumber(db.conditionSoundCooldown) or defaults.conditionSoundCooldown
	db.conditionSoundChannel  = NormalizeChannel(db.conditionSoundChannel)
	db.conditionSoundKitID    = tonumber(db.conditionSoundKitID)    or defaults.conditionSoundKitID
	db.conditionSoundKey      = tostring(db.conditionSoundKey       or defaults.conditionSoundKey)
	db.conditionSoundSource   = (db.conditionSoundSource == "file") and "file" or "soundkit"
	db.conditionSoundFile     = tostring(db.conditionSoundFile      or defaults.conditionSoundFile)
	db.conditionValueAbs = tonumber(db.conditionValueAbs)
	db.conditionValuePct = tonumber(db.conditionValuePct)
	if not db.conditionValueAbs then db.conditionValueAbs = (db.useAbsoluteValue and db.conditionPct) or defaults.conditionValueAbs end
	if not db.conditionValuePct then db.conditionValuePct = ((not db.useAbsoluteValue) and db.conditionPct) or defaults.conditionValuePct end
	db.conditionValuePct = ClampNumber(db.conditionValuePct, 0, 100) or defaults.conditionValuePct
	db.conditionPct = GetConditionValue()
end
-- =========================================================
-- Position save
-- =========================================================
local function SavePositionFromFrame()
	if not frame then return end
	local ok, point, _, relativePoint, x, y = pcall(function() return frame:GetPoint(1) end)
	if not ok then return end
	db.point = point or db.point; db.relativePoint = relativePoint or db.relativePoint
	db.x = Round(x or db.x); db.y = Round(y or db.y)
	if Options.ed_x then Options.ed_x:Refresh() end
	if Options.ed_y then Options.ed_y:Refresh() end
end
-- =========================================================
-- Sound
-- =========================================================
local SOUND_FOLDER = "Interface\\AddOns\\HAN_Tools\\Sound\\"
local function GetSoundFilePath()
	local f = db.conditionSoundFile
	return (f and f ~= "") and (SOUND_FOLDER..f) or nil
end
local function ResolveSoundKitID()
	if db.conditionSoundKey and db.conditionSoundKey ~= "" and type(SOUNDKIT) == "table" then
		local id = SOUNDKIT[db.conditionSoundKey]
		if type(id) == "number" and id > 0 then return id, db.conditionSoundKey end
	end
	local kit = tonumber(db.conditionSoundKitID)
	return (kit and kit > 0) and kit or nil, ""
end
-- 숫자(SoundKitID) 또는 문자열(파일경로) 모두 처리하는 통합 미리듣기
local function PlaySoundPreview(v)
	local ch = NormalizeChannel(db.conditionSoundChannel)
	if type(v) == "number" and v > 0 then
		local ok, r = pcall(PlaySound, v, ch); return ok and r and true or false
	elseif type(v) == "string" and v ~= "" then
		local ok, r = pcall(PlaySoundFile, v, ch); return ok and r and true or false
	end
	return false
end
local function TryPlayThresholdSound(self)
	if not db.useConditionSound then return end
	local now = GetTime and GetTime() or 0
	local cd  = tonumber(db.conditionSoundCooldown) or 1.0
	if self._lastSoundTime and now > 0 and (now - self._lastSoundTime) < cd then return end
	if db.conditionSoundSource == "file" then
		PlaySoundPreview(GetSoundFilePath())
	else
		local id = ResolveSoundKitID()
		if id then PlaySoundPreview(id) end
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
	frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	frame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
	frame:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
	frame._lastAbove = nil; frame._lastSoundTime = nil
	frame._coreOnEvent(frame, "Enable", "player")
end
local function Core_Disable()
	if not frame or not frame._coreEnabled then return end
	frame._coreEnabled = false
	frame:UnregisterAllEvents()
	frame:SetScript("OnEvent", nil); frame:SetScript("OnUpdate", nil)
	frame._lastAbove = nil; frame._lastSoundTime = nil
end
local function SetEnabled(enabled)
	db.enabled = not not enabled
	if not frame then return end
	if db.enabled then frame:Show(); Core_Enable() else Core_Disable(); frame:Hide() end
end
-- =========================================================
-- ApplySettings
-- =========================================================
local function ApplySettings()
	if not frame then return end
	SetEnabled(db.enabled)
	frame:ClearAllPoints()
	frame:SetPoint(db.point, UIParent, db.relativePoint, db.x, db.y)
	frame:EnableMouse(db.unlocked)
	if frame.bg then frame.bg[db.unlocked and "Show" or "Hide"](frame.bg) end
	local font = (NumberFontNormal and NumberFontNormal:GetFont()) or "Fonts\\2002B.TTF"
	frame.textBase:SetFont(font, db.fontSize, "OUTLINE")
	frame.textCond:SetFont(font, db.conditionFontSize, "OUTLINE")
	frame._baseColor = EnsureColorTable(db.fontColor, defaults.fontColor)
	frame._condColor = EnsureColorTable(db.conditionColor, defaults.conditionColor)
	if Options.RefreshConditionSliderSpec then Options:RefreshConditionSliderSpec() end
	if Options.RefreshSoundUI           then Options:RefreshSoundUI() end
	if db.enabled and frame._coreOnEvent then frame._coreOnEvent(frame, "ApplySettings", "player") end
end
-- =========================================================
-- Create tracker frame + Core OnEvent
-- =========================================================
local function CreateResourceTracker()
	if frame then return end
	frame = CreateFrame("Frame", "HAN_Tools_ResourceCore", UIParent)
	frame:SetSize(100, 50); frame:SetClampedToScreen(true); frame:SetMovable(true)
	frame:SetPoint(db.point, UIParent, db.relativePoint, db.x, db.y)
	frame.bg = frame:CreateTexture(nil, "BACKGROUND")
	frame.bg:SetAllPoints(); frame.bg:SetColorTexture(0,1,0,0.3); frame.bg:Hide()
	frame.textBase = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	frame.textBase:SetPoint("CENTER"); frame.textBase:SetText("0")
	frame.textCond = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	frame.textCond:SetPoint("CENTER"); frame.textCond:SetText("0"); frame.textCond:SetTextColor(0,0,0,0)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self) if db.unlocked then self:StartMoving() end end)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePositionFromFrame() end)
	frame:SetScript("OnMouseUp", function(_, btn)
		if btn == "RightButton" and Settings and Settings.OpenToCategory and Options.categoryID then
			Settings.OpenToCategory(Options.categoryID)
		end
	end)
	frame._coreOnEvent = function(self, event, unit)
		-- PLAYER_ENTERING_WORLD는 secure context에서 발생 → UnitPower taint 방지를 위해 딜레이
		if event == "PLAYER_ENTERING_WORLD" then
			C_Timer.After(0.5, function()
				if self._coreEnabled then self._coreOnEvent(self, "PLAYER_SPECIALIZATION_CHANGED", "player") end
			end)
			return
		elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
			unit = "player"
		end
		if unit and unit ~= "player" then return end
		if not db.enabled then return end
		local pType     = UnitPowerType("player")
		local threshold = GetConditionValue()
		local isAbsolute = db.useAbsoluteValue
		-- [FIX 4] SPEC_CONFIG 테이블 조회 (elseif 체인 제거)
		local si = GetSpecialization and GetSpecialization()
		if si then
			local cfg = SPEC_CONFIG[GetSpecializationInfo(si)]
			if cfg then isAbsolute, pType = cfg[1], cfg[2] end
		end
		-- 1) 텍스트 표시 (절대값 or %)
		local curForSound
		if isAbsolute then
			local cur = UnitPower("player", pType)
			self.textBase:SetText(cur); self.textCond:SetText(cur)
			curForSound = cur
		else
			-- [FIX 4] UnitPower/UnitPowerMax 단순 계산 (커브 의존 제거)
			local cur = UnitPower("player", pType)
			local max = UnitPowerMax("player", pType)
			local p   = (max and max > 0) and math.floor(cur / max * 100 + 0.5) or 0
			self.textBase:SetFormattedText("%d%%", p); self.textCond:SetFormattedText("%d%%", p)
			curForSound = p
		end
		-- 2) 조건부 색/크기
		-- [FIX 5] C_CurveUtil 의존 제거 → 단순 임계값 비교
		local base = self._baseColor or defaults.fontColor
		local cond = self._condColor or defaults.conditionColor
		local rB,gB,bB = base[1],base[2],base[3]
		local rC,gC,bC = cond[1],cond[2],cond[3]
		if db.useCondition and curForSound ~= nil then
			local above = curForSound >= threshold
			if above and db.useConditionSize then
				self.textBase:SetTextColor(0,0,0,0); self.textCond:SetTextColor(rC,gC,bC,1)
			elseif above then
				self.textBase:SetTextColor(rC,gC,bC,1); self.textCond:SetTextColor(0,0,0,0)
			else
				self.textBase:SetTextColor(rB,gB,bB,1); self.textCond:SetTextColor(0,0,0,0)
			end
		else
			self.textBase:SetTextColor(rB,gB,bB,1); self.textCond:SetTextColor(0,0,0,0)
		end
		-- 3) 기준치 상향 돌파 시 사운드
		if db.useConditionSound and curForSound ~= nil then
			local above = curForSound >= threshold
			if self._lastAbove == nil then
				self._lastAbove = above
			else
				if not self._lastAbove and above then TryPlayThresholdSound(self) end
				self._lastAbove = above
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
	c:SetSize(260, 60); c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	c.minV, c.maxV, c.step = minV, maxV, step
	local t = c:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	t:SetPoint("TOP"); t:SetText(labelText); t:SetTextColor(1, 0.82, 0)
	local s = CreateFrame("Slider", nil, c, "UISliderTemplate")
	s:SetSize(200, 15); s:SetPoint("TOP", t, "BOTTOM", 0, -10)
	local eb = CreateFrame("EditBox", nil, c, "InputBoxTemplate")
	eb:SetSize(70, 20); eb:SetPoint("TOP", s, "BOTTOM", 0, -2)
	eb:SetAutoFocus(false); eb:SetJustifyH("CENTER")
	local syncing = false
	local function Sync(val)
		if syncing then return end; syncing = true
		val = ClampNumber(val, c.minV, c.maxV) or getter()
		if c.step > 0 then val = math.floor(val / c.step + 0.5) * c.step end
		s:SetValue(val); eb:SetText(tostring(val)); eb:SetCursorPosition(0)
		setter(val); ApplySettings(); syncing = false
	end
	function c:SetLabel(l) t:SetText(l) end
	function c:SetRange(mn, mx, st)
		c.minV, c.maxV = mn, mx
		if st then c.step = st end
		s:SetMinMaxValues(mn, mx); s:SetValueStep(c.step); s:SetObeyStepOnDrag(true)
		c:Refresh()
	end
	function c:Refresh()
		syncing = true
		local v = getter(); s:SetValue(v); eb:SetText(tostring(v)); eb:SetCursorPosition(0)
		syncing = false
	end
	s:SetMinMaxValues(minV, maxV); s:SetValueStep(step); s:SetObeyStepOnDrag(true)
	s:SetScript("OnValueChanged", function(_, v) Sync(v) end)
	eb:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Sync(tonumber(self:GetText())) end)
	eb:SetScript("OnEditFocusLost", function(self) Sync(tonumber(self:GetText())) end)
	c:HookScript("OnShow", function() c:Refresh() end)
	eb:HookScript("OnShow", function() c:Refresh() end)
	c:Refresh(); return c
end
local function CreateColorPickerRow(parent, label, x, y, getter, setter)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y); fs:SetText(label)
	local swBg = parent:CreateTexture(nil, "BACKGROUND")
	swBg:SetSize(22, 22); swBg:SetPoint("TOPLEFT", parent, "TOPLEFT", x+140, y+2)
	swBg:SetColorTexture(0.3, 0.3, 0.3)
	local sw = parent:CreateTexture(nil, "ARTWORK")
	sw:SetSize(18, 18); sw:SetPoint("CENTER", swBg)
	local function Refresh() local c=EnsureColorTable(getter(),{1,1,1}); sw:SetColorTexture(c[1],c[2],c[3],1) end
	Refresh()
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetSize(80, 22); btn:SetPoint("LEFT", swBg, "RIGHT", 12, 0); btn:SetText("변경")
	btn:SetScript("OnClick", function()
		local c=EnsureColorTable(getter(),{1,1,1}); local pr,pg,pb=c[1],c[2],c[3]
		local function AC(r,g,b) setter({r,g,b}); Refresh(); ApplySettings() end
		if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
			ColorPickerFrame:Hide()
			ColorPickerFrame:SetupColorPickerAndShow({
				r=pr, g=pg, b=pb, hasOpacity=false,
				swatchFunc=function() local r,g,b=ColorPickerFrame:GetColorRGB(); AC(r,g,b) end,
				cancelFunc=function() AC(pr,pg,pb) end,
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
		if type(k)=="string" and type(v)=="number" and v>0 then list[#list+1]={key=k,id=v} end
	end
	table.sort(list, function(a,b) return a.key~=b.key and a.key<b.key or a.id<b.id end)
	return list
end
local function EnsureSoundPopup()
	if Options.soundPopup then return end
	local popup = CreateFrame("Frame", nil, Options.frame, "BackdropTemplate")
	popup:SetSize(520, 380); popup:SetFrameStrata("DIALOG"); popup:SetClampedToScreen(true)
	popup:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
		tile=true, tileSize=32, edgeSize=32, insets={left=11,right=12,top=12,bottom=11} })
	popup:Hide()
	tinsert(UISpecialFrames, popup:GetName() or "HAN_Tools_SoundPopup")
	local title = popup:CreateFontString(nil,"ARTWORK","GameFontNormalLarge")
	title:SetPoint("TOPLEFT",16,-16); title:SetText("효과음 선택 (SOUNDKIT)")
	local close = CreateFrame("Button",nil,popup,"UIPanelCloseButton"); close:SetPoint("TOPRIGHT",-6,-6)
	local search = CreateFrame("EditBox",nil,popup,"InputBoxTemplate")
	search:SetSize(220,22); search:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-12)
	search:SetAutoFocus(false); search:SetJustifyH("LEFT"); search:SetText("")
	search:SetScript("OnEscapePressed", function(self) self:ClearFocus(); popup:Hide() end)
	local sf = CreateFrame("ScrollFrame",nil,popup,"UIPanelScrollFrameTemplate")
	sf:SetPoint("TOPLEFT",search,"BOTTOMLEFT",0,-12); sf:SetPoint("BOTTOMRIGHT",-30,18)
	local child = CreateFrame("Frame",nil,sf); child:SetSize(1,1); sf:SetScrollChild(child)
	popup._rows = {}
	local function SetSelectionFromRow(key, id)
		db.conditionSoundKey = key or ""; db.conditionSoundKitID = tonumber(id) or db.conditionSoundKitID
		if Options.RefreshSoundUI then Options:RefreshSoundUI() end; ApplySettings()
	end
	local function RefreshRows()
		local filter = popup._filtered or {}
		for i=1,#popup._rows do popup._rows[i]:Hide() end
		local selId, selKey = ResolveSoundKitID()
		local y, rowH = -4, 24
		for i=1,#filter do
			local item = filter[i]
			local row = popup._rows[i]
			if not row then
				row = CreateFrame("Button", nil, child)
				row:SetSize(460,rowH); row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD")
				row.text = row:CreateFontString(nil,"ARTWORK","GameFontNormal")
				row.text:SetPoint("LEFT",4,0); row.text:SetJustifyH("LEFT")
				row.play = CreateFrame("Button",nil,row); row.play:SetSize(18,18); row.play:SetPoint("RIGHT",-6,0)
				row.play.tex = row.play:CreateTexture(nil,"ARTWORK"); row.play.tex:SetAllPoints()
				row.play.tex:SetTexture("Interface\\COMMON\\VoiceChat-Speaker")
				row.play:SetScript("OnClick", function(s) PlaySoundPreview(s:GetParent()._id) end)
				row:SetScript("OnClick", function(s) SetSelectionFromRow(s._key, s._id); popup:Hide() end)
				popup._rows[i] = row
			end
			row._key, row._id = item.key, item.id
			local sel = (selId == item.id) or (selKey ~= "" and selKey == item.key)
			row.text:SetTextColor(sel and 0.2 or 1, sel and 1 or 0.82, sel and 0.2 or 0)
			row.text:SetText(string.format("%s  (ID: %d)", item.key, item.id))
			row:SetPoint("TOPLEFT", 4, y); row:Show(); y = y - rowH
		end
		child:SetHeight(math.max(1, -y+20))
	end
	local debounce
	local function ApplyFilter()
		local q = tostring(search:GetText() or ""):lower()
		if q == "" then popup._filtered = popup._catalog; RefreshRows(); return end
		local out = {}
		for _, item in ipairs(popup._catalog) do
			if tostring(item.key):lower():find(q,1,true) or tostring(item.id):find(q,1,true) then
				out[#out+1] = item
			end
		end
		popup._filtered = out; RefreshRows()
	end
	search:SetScript("OnTextChanged", function()
		if debounce then debounce:Cancel() end
		debounce = C_Timer.NewTimer(0.12, function() if popup:IsShown() then ApplyFilter() end end)
	end)
	popup:SetScript("OnShow", function()
		popup._catalog = BuildSoundCatalog(); popup._filtered = popup._catalog
		search:SetText(""); RefreshRows()
	end)
	Options.soundPopup = popup
end
-- =========================================================
-- Build Options Panel (Scrollable)
-- =========================================================
local function BuildOptionsPanel()
	if Options.frame then return end
	local f = CreateFrame("Frame", "HAN_Tools_ResourceOptions", UIParent)
	f.name = "자원 추적 (%)"; Options.frame = f
	local scroll = CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT",0,-8); scroll:SetPoint("BOTTOMRIGHT",-26,8)
	local content = CreateFrame("Frame",nil,scroll); content:SetSize(1,1); scroll:SetScrollChild(content)
	local title = content:CreateFontString(nil,"ARTWORK","GameFontNormalLarge")
	title:SetPoint("TOPLEFT",16,-16); title:SetText("HAN TOOLS: 자원 추적기 (색/크기/사운드)")
	local y = -60
	-- 체크박스 헬퍼 (content/y 클로저 활용)
	local function MakeCheck(optKey, label, getter, setter, yGap)
		local cb = CreateFrame("CheckButton",nil,content,"UICheckButtonTemplate")
		cb:SetPoint("TOPLEFT",16,y); cb.Text:SetText(label); cb:SetChecked(getter())
		cb:SetScript("OnClick", function(self) setter(self:GetChecked()); ApplySettings() end)
		Options[optKey] = cb; y = y - (yGap or 30)
	end
	MakeCheck("cb_enabled",  "사용",                         function() return db.enabled end,          SetEnabled)
	MakeCheck("cb_unlock",   "잠금 해제 (마우스 드래그)",      function() return db.unlocked end,         function(v) db.unlocked = v end, 40)
	MakeCheck("cb_absolute", "백분율(%) 대신 절대 수치 표시",  function() return db.useAbsoluteValue end, function(v) db.useAbsoluteValue=v; db.conditionPct=GetConditionValue() end, 60)
	Options.ed_x = CreateSliderOption(content,"X 좌표",16,y,-2000,2000,1, function() return db.x end, function(v) db.x=v end)
	Options.ed_y = CreateSliderOption(content,"Y 좌표",310,y,-2000,2000,1, function() return db.y end, function(v) db.y=v end)
	y = y - 70
	Options.ed_fontSize = CreateSliderOption(content,"기본 글자 크기",16,y,10,128,1, function() return db.fontSize end, function(v) db.fontSize=v end)
	y = y - 60
	Options.cp_fontColor = CreateColorPickerRow(content,"기본 글자 색상",16,y, function() return db.fontColor end, function(v) db.fontColor=EnsureColorTable(v,defaults.fontColor) end)
	y = y - 50
	MakeCheck("cb_condition",     "기준치 기능 사용(색/크기)",     function() return db.useCondition end,     function(v) db.useCondition=v end, 40)
	Options.ed_conditionPct = CreateSliderOption(content,"기준 수치",16,y,0,1000,1, GetConditionValue, SetConditionValue)
	Options.cp_conditionColor = CreateColorPickerRow(content,"조건 달성 색상",310,y,
		function() return db.conditionColor end,
		function(v) db.conditionColor=EnsureColorTable(v,defaults.conditionColor) end)
	y = y - 80
	MakeCheck("cb_conditionSize", "기준치 달성 시 글자 크기 변경", function() return db.useConditionSize end, function(v) db.useConditionSize=v end, 40)
	Options.ed_conditionFontSize = CreateSliderOption(content,"조건 글자 크기",16,y,10,128,1, function() return db.conditionFontSize end, function(v) db.conditionFontSize=v end)
	y = y - 80
	MakeCheck("cb_sound", "기준치 상향 돌파 시 효과음", function() return db.useConditionSound end, function(v) db.useConditionSound=v end, 40)
	Options.ed_soundCooldown = CreateSliderOption(content,"효과음 쿨다운(초)",16,y,0,10,0.1,
		function() return tonumber(db.conditionSoundCooldown) or defaults.conditionSoundCooldown end,
		function(v) db.conditionSoundCooldown=v end)
	y = y - 70
	Options.soundSelectBtn = CreateFrame("Button",nil,content,"UIPanelButtonTemplate")
	Options.soundSelectBtn:SetSize(360,24); Options.soundSelectBtn:SetPoint("TOPLEFT",16,y)
	Options.soundSelectBtn:SetText("효과음: (선택)")
	Options.soundSelectBtn:SetScript("OnClick", function()
		EnsureSoundPopup()
		Options.soundPopup:ClearAllPoints()
		Options.soundPopup:SetPoint("TOPLEFT",Options.soundSelectBtn,"BOTTOMLEFT",-8,-8)
		Options.soundPopup:Show()
	end)
	Options.soundPreviewBtn = CreateFrame("Button",nil,content,"UIPanelButtonTemplate")
	Options.soundPreviewBtn:SetSize(90,24); Options.soundPreviewBtn:SetPoint("LEFT",Options.soundSelectBtn,"RIGHT",10,0)
	Options.soundPreviewBtn:SetText("미리듣기")
	Options.soundPreviewBtn:SetScript("OnClick", function() PlaySoundPreview(ResolveSoundKitID()) end)
	y = y - 40
	Options.soundChannelBtn = CreateFrame("Button",nil,content,"UIPanelButtonTemplate")
	Options.soundChannelBtn:SetSize(180,24); Options.soundChannelBtn:SetPoint("TOPLEFT",16,y)
	Options.soundChannelBtn:SetText("채널: "..NormalizeChannel(db.conditionSoundChannel))
	Options.soundChannelBtn:SetScript("OnClick", function()
		local order = {"Master","SFX","Dialog","Music","Ambience"}
		local cur = NormalizeChannel(db.conditionSoundChannel); local idx = 1
		for i=1,#order do if order[i]==cur then idx=i break end end
		idx = idx%#order + 1; db.conditionSoundChannel = order[idx]
		Options.soundChannelBtn:SetText("채널: "..NormalizeChannel(db.conditionSoundChannel)); ApplySettings()
	end)
	Options.ed_soundKit = CreateSliderOption(content,"SoundKit ID(직접)",310,y+6,0,200000,1,
		function() return tonumber(db.conditionSoundKitID) or defaults.conditionSoundKitID end,
		function(v) db.conditionSoundKitID=v; db.conditionSoundKey="" end)
	y = y - 90
	-- 사운드 소스 전환 버튼
	Options.soundSourceBtn = CreateFrame("Button",nil,content,"UIPanelButtonTemplate")
	Options.soundSourceBtn:SetSize(200,24); Options.soundSourceBtn:SetPoint("TOPLEFT",16,y)
	Options.soundSourceBtn:SetText(db.conditionSoundSource=="file" and "소스: OGG 파일" or "소스: SOUNDKIT")
	Options.soundSourceBtn:SetScript("OnClick", function()
		db.conditionSoundSource = db.conditionSoundSource=="file" and "soundkit" or "file"
		if Options.RefreshSoundUI then Options:RefreshSoundUI() end; ApplySettings()
	end)
	y = y - 34
	-- OGG 파일명 입력
	Options.fileLabel = content:CreateFontString(nil,"ARTWORK","GameFontNormal")
	Options.fileLabel:SetPoint("TOPLEFT",16,y); Options.fileLabel:SetText("OGG 파일명 (HAN_Tools\\Sound\\ 폴더 내):")
	Options.fileLabel:SetTextColor(1,0.82,0)
	y = y - 20
	Options.fileEditBox = CreateFrame("EditBox",nil,content,"InputBoxTemplate")
	Options.fileEditBox:SetSize(320,22); Options.fileEditBox:SetPoint("TOPLEFT",16,y)
	Options.fileEditBox:SetAutoFocus(false); Options.fileEditBox:SetJustifyH("LEFT")
	Options.fileEditBox:SetText(db.conditionSoundFile or "")
	Options.fileEditBox:SetScript("OnEnterPressed", function(self)
		db.conditionSoundFile = self:GetText():trim(); self:ClearFocus()
		if Options.RefreshSoundUI then Options:RefreshSoundUI() end; ApplySettings()
	end)
	Options.fileEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	Options.filePreviewBtn = CreateFrame("Button",nil,content,"UIPanelButtonTemplate")
	Options.filePreviewBtn:SetSize(90,22); Options.filePreviewBtn:SetPoint("LEFT",Options.fileEditBox,"RIGHT",10,0)
	Options.filePreviewBtn:SetText("미리듣기")
	Options.filePreviewBtn:SetScript("OnClick", function()
		local file = Options.fileEditBox:GetText():trim()
		if file == "" then print("|cFFFF4444[HAN_Tools]|r 파일명을 입력하세요."); return end
		db.conditionSoundFile = file
		local path = GetSoundFilePath()
		if path and not PlaySoundPreview(path) then
			print("|cFFFF4444[HAN_Tools]|r 파일을 찾을 수 없습니다: "..path)
		end
	end)
	y = y - 34
	local helpText = content:CreateFontString(nil,"ARTWORK","GameFontHighlightSmall")
	helpText:SetPoint("TOPLEFT",16,y); helpText:SetWidth(480); helpText:SetJustifyH("LEFT")
	helpText:SetText("|cFF888888예시: alert.ogg, ding.ogg\n경로: Interface\\AddOns\\HAN_Tools\\Sound\\파일명.ogg\n.ogg 확장자를 포함해서 입력하세요.|r")
	y = y - 50
	-- 옵션 메서드
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
		local isFile = db.conditionSoundSource == "file"
		if isFile then
			local file = db.conditionSoundFile or ""
			self.soundSelectBtn:SetText(file ~= "" and ("효과음: "..file.." (OGG 파일)") or "효과음: (OGG 파일 미선택)")
		else
			local id, key = ResolveSoundKitID()
			self.soundSelectBtn:SetText(id and (key~="" and ("효과음: "..key.." (ID:"..id..")") or ("효과음: Custom ID:"..id)) or "효과음: (없음)")
		end
		if self.soundChannelBtn then self.soundChannelBtn:SetText("채널: "..NormalizeChannel(db.conditionSoundChannel)) end
		if self.soundSourceBtn  then self.soundSourceBtn:SetText(isFile and "소스: OGG 파일" or "소스: SOUNDKIT") end
		if self.fileEditBox then
			local vis = isFile and "Show" or "Hide"
			self.fileEditBox[vis](self.fileEditBox); self.filePreviewBtn[vis](self.filePreviewBtn)
			if self.fileLabel then self.fileLabel[vis](self.fileLabel) end
		end
	end
	function Options:RefreshAll()
		if self.cb_enabled      then self.cb_enabled:SetChecked(db.enabled)            end
		if self.cb_unlock       then self.cb_unlock:SetChecked(db.unlocked)             end
		if self.cb_absolute     then self.cb_absolute:SetChecked(db.useAbsoluteValue)   end
		if self.cb_condition    then self.cb_condition:SetChecked(db.useCondition)      end
		if self.cb_conditionSize then self.cb_conditionSize:SetChecked(db.useConditionSize) end
		if self.cb_sound        then self.cb_sound:SetChecked(db.useConditionSound)     end
		for _, k in ipairs({"ed_x","ed_y","ed_fontSize","ed_conditionPct","ed_conditionFontSize","ed_soundCooldown","ed_soundKit"}) do
			if self[k] then self[k]:Refresh() end
		end
		if self.fileEditBox then self.fileEditBox:SetText(db.conditionSoundFile or "") end
		self:RefreshConditionSliderSpec(); self:RefreshSoundUI()
	end
	content:SetHeight(math.max(600, -y+60))
	f:SetScript("OnShow", function() C_Timer.After(0.05, function() if Options.RefreshAll then Options:RefreshAll() end end) end)
	if Settings and Settings.RegisterCanvasLayoutSubcategory and HT and HT.OptionsCategoryID then
		local cat = Settings.RegisterCanvasLayoutSubcategory(HT.OptionsCategoryID, f, f.name)
		Options.categoryID = cat:GetID()
	end
end
-- =========================================================
-- Events
-- =========================================================
local EventFrame = CreateFrame("Frame")
EventFrame:RegisterEvent("ADDON_LOADED")
EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
EventFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		InitializeDB(GetPlayerKey())
		CreateResourceTracker(); BuildOptionsPanel(); ApplySettings()
	elseif event == "PLAYER_ENTERING_WORLD" then
		local key = GetPlayerKey()
		if key then InitializeDB(key) end
	end
end)
