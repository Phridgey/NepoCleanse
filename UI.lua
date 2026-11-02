--[[
  NepoCleanse - what you see

  1. The list: one row per person with a debuff you can remove. Click a row to remove it.
     Shift + right-click a row to stop showing that debuff. Drag the title to move it.
     Unused rows are made see-through instead of hidden, which is much cheaper.

  2. The settings window (/nepocleanse): People, Debuffs and General pages, each list with a
     search box at the top.
]]

local R = NepoCleanse
local MAXROWS, ROWH, WIDTH = 15, 20, 230
local FLAT = "Interface\\Buttons\\WHITE8X8"

local function Backdrop(f, a)
	f:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
	f:SetBackdropColor(.06, .06, .08, a or .85)
	f:SetBackdropBorderColor(0, 0, 0, 1)
end

local function Text(parent, font, size, justify)
	local t = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	if size then t:SetFont(STANDARD_TEXT_FONT, size) end
	t:SetJustifyH(justify or "LEFT")
	return t
end

local function Hex(c) return "|cff" .. (c or "ffffff") end

local function Say(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffNepoCleanse:|r " .. msg) end

------------------------------------------------------------------------------
-- 1. the list
------------------------------------------------------------------------------
local frame, header, body, rows

local function RGB(hex)
	return tonumber(string.sub(hex, 1, 2), 16) / 255, tonumber(string.sub(hex, 3, 4), 16) / 255,
		tonumber(string.sub(hex, 5, 6), 16) / 255
end

-- the title bar shows when switched on, and always while unlocked (so it can be dragged)
local function HeaderShown() return R.db.header or not R.db.locked end
local function HeaderHeight() return HeaderShown() and R.db.headerHeight or 0 end

local function SavePosition()
	local point, _, rel, x, y = frame:GetPoint(1)
	R.db.pos = { point, rel, x, y }
end

local function BuildList()
	local db = R.db
	frame = CreateFrame("Frame", "NepoCleanseFrame", UIParent)
	frame:SetWidth(WIDTH)
	frame:SetHeight(16)
	frame:SetFrameStrata("MEDIUM")
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	if db.pos then
		frame:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", -300, 0)
	end
	frame:SetScale(db.scale)

	header = CreateFrame("Button", nil, frame)
	header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
	header:SetHeight(16)
	header:RegisterForDrag("LeftButton")
	header:RegisterForClicks("RightButtonUp")
	header.bg = header:CreateTexture(nil, "BACKGROUND")
	header.bg:SetAllPoints(header)
	header.bg:SetTexture(FLAT)
	header.line = header:CreateTexture(nil, "ARTWORK")
	header.line:SetTexture(FLAT)
	header.line:SetHeight(1)
	header.line:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
	header.line:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
	header.title = Text(header, nil, 10)
	header.title:SetPoint("LEFT", header, "LEFT", 5, 0)
	header.count = Text(header, nil, 10, "RIGHT")
	header.count:SetPoint("RIGHT", header, "RIGHT", -5, 0)

	body = CreateFrame("Frame", nil, frame)
	body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
	body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	body:SetFrameLevel(frame:GetFrameLevel())
	Backdrop(body, .7)
	header:SetScript("OnDragStart", function() if not R.db.locked then frame:StartMoving() end end)
	header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() SavePosition() end)
	header:SetScript("OnClick", function() NepoCleanse_ToggleOptions() end)
	header:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_TOP")
		GameTooltip:AddLine("NepoCleanse")
		GameTooltip:AddLine("Drag to move (unless locked). Right-click for settings.", 1, 1, 1, 1)
		GameTooltip:Show()
	end)
	header:SetScript("OnLeave", function() GameTooltip:Hide() end)

	rows = {}
	for i = 1, MAXROWS do
		local row = CreateFrame("Button", nil, frame)
		row:SetHeight(ROWH)
		row:SetFrameLevel(body:GetFrameLevel() + 1)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetHighlightTexture(FLAT)
		row:GetHighlightTexture():SetVertexColor(1, 1, 1, .08)

		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints(row)
		row.bg:SetTexture(FLAT)
		row.bar = row:CreateTexture(nil, "ARTWORK")
		row.bar:SetTexture(FLAT)
		row.bar:SetWidth(3)
		row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
		row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetWidth(ROWH - 4)
		row.icon:SetHeight(ROWH - 4)
		row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
		row.icon:SetTexCoord(.08, .92, .08, .92)
		row.stacks = Text(row, "NumberFontNormalSmall", nil, "RIGHT")
		row.stacks:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 2, -1)
		row.who = Text(row, nil, 11)
		row.who:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
		row.who:SetWidth(85)
		row.what = Text(row, nil, 10, "RIGHT")
		row.what:SetPoint("LEFT", row.who, "RIGHT", 2, 0)
		row.what:SetPoint("RIGHT", row, "RIGHT", -5, 0)
		row.what:SetHeight(ROWH)

		row:SetScript("OnClick", function()
			local e = this.entry
			if not e then return end
			if arg1 == "RightButton" then
				if IsShiftKeyDown() then
					R.db.ignore[e.debuff] = true
					Say("no longer showing " .. e.debuff .. ". Undo it on the Debuffs page (/nepocleanse).")
					R.ScanAll()
				end
			else
				R.Cleanse(e)
			end
		end)
		row:SetScript("OnEnter", function()
			local e = this.entry
			if not e then return end
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:SetUnitDebuff(e.unit, e.index)
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Click: remove it.  Shift + right-click: stop showing it.", .6, .8, 1, 1)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)

		row:SetAlpha(0)
		row:EnableMouse(false)
		rows[i] = row
	end
	frame:Hide()
end

function R.Refresh()
	if not frame or not frame:IsShown() then return end
	local db = R.db
	local n = getn(R.entries)
	local shown = n
	if shown > db.rows then shown = db.rows end
	for i = 1, MAXROWS do
		local row = rows[i]
		local e = i <= shown and R.entries[i]
		if e then
			row.entry = e
			local c = R.TYPE_COLOR[e.type] or R.TYPE_COLOR.Magic
			row.bar:SetVertexColor(c[1], c[2], c[3], 1)
			row.bg:SetVertexColor(c[1], c[2], c[3], .18)
			row.icon:SetTexture(e.icon)
			row.stacks:SetText(e.stacks and e.stacks > 1 and e.stacks or "")
			row.who:SetText(Hex(R.CLASS_COLOR[e.class]) .. e.name .. "|r")
			row.what:SetText((e.first and "|cffffd100" or "|cffcccccc") .. e.debuff .. "|r")
			row:SetAlpha(e.inRange == false and .35 or 1)
			row:EnableMouse(true)
		else
			row.entry = nil
			row:SetAlpha(0)
			row:EnableMouse(false)
		end
	end
	frame:SetHeight(HeaderHeight() + shown * ROWH + (shown > 0 and 1 or 0))
	body:SetAlpha(shown > 0 and 1 or 0)
	if not db.headerCount then
		header.count:SetText("")
	elseif n > shown then
		header.count:SetText("|cffff9900+" .. (n - shown) .. " more|r")
	elseif n > 0 then
		header.count:SetText(n)
	else
		header.count:SetText(db.headerEmptyText and "|cff666666nothing to remove|r" or "")
	end
	-- nothing to show, locked, and "hide when empty" on: show nothing at all
	local quiet = n == 0 and db.locked and db.hideEmpty
	frame:SetAlpha(quiet and 0 or 1)
	header:EnableMouse(HeaderShown() and not quiet)
end

function R.OnActiveChanged()
	if not frame then return end
	if R.active then
		frame:Show()
		R.Refresh()
	else
		frame:Hide()
	end
	if R.RefreshOptions then R.RefreshOptions() end
end

function R.ApplyLook()
	if not frame then return end
	local db = R.db
	frame:SetScale(db.scale)
	local hh = HeaderHeight()
	if HeaderShown() then
		header:SetHeight(hh)
		header:SetAlpha(1)
	else
		header:SetHeight(1)   -- keeps the rows anchored; the bar itself is see-through
		header:SetAlpha(0)
	end
	local r, g, b = RGB(db.headerColor)
	header.bg:SetVertexColor(.06, .06, .08, db.headerAlpha)
	header.line:SetVertexColor(r, g, b, .8)
	if db.headerLine then header.line:Show() else header.line:Hide() end
	header.title:SetFont(STANDARD_TEXT_FONT, db.headerFont)
	header.count:SetFont(STANDARD_TEXT_FONT, db.headerFont)
	local title = db.headerTitle and ("|cff" .. db.headerColor .. (db.title ~= "" and db.title or "NepoCleanse") .. "|r") or ""
	if not db.locked then title = title .. " |cff888888(drag me)|r" end
	header.title:SetText(title)
	for i = 1, MAXROWS do
		local row = rows[i]
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -hh - (i - 1) * ROWH)
		row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -hh - (i - 1) * ROWH)
	end
	R.Refresh()
end

-- read everyone again (after a settings change)
function R.ScanAll()
	for i = getn(R.entries), 1, -1 do table.remove(R.entries, i) end
	R.RebuildUnits()
end

------------------------------------------------------------------------------
-- 2. settings window parts
------------------------------------------------------------------------------
local win, pages, navButtons = nil, {}, {}

local function SearchBox(parent, name, hint, onChange)
	local eb = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
	eb:SetAutoFocus(false)
	eb:SetHeight(20)
	eb.hint = Text(eb, "GameFontDisableSmall")
	eb.hint:SetPoint("LEFT", eb, "LEFT", 2, 0)
	eb.hint:SetText(hint)
	local function hintShown()
		if eb:GetText() == "" and not eb.focused then eb.hint:Show() else eb.hint:Hide() end
	end
	eb:SetScript("OnEditFocusGained", function() this.focused = true hintShown() end)
	eb:SetScript("OnEditFocusLost", function() this.focused = false hintShown() end)
	eb:SetScript("OnEscapePressed", function() this:ClearFocus() end)
	eb:SetScript("OnTextChanged", function() hintShown() if onChange then onChange() end end)
	return eb
end

local function SmallButton(parent, label, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetWidth(width or 60)
	b:SetHeight(18)
	b:SetText(label)
	if b.SetTextFontObject then b:SetTextFontObject(GameFontHighlightSmall) end
	b:SetScript("OnClick", onClick)
	return b
end

-- a scrolling list; items are { text, tag, dot = {r,g,b}, grey, b1 = {label, fn}, b2 = {label, fn} }
local listCount = 0
local function MakeList(parent, numRows)
	listCount = listCount + 1
	local L = { rows = {}, items = {} }
	local box = CreateFrame("Frame", nil, parent)
	Backdrop(box, .5)
	L.box = box
	local scroll = CreateFrame("ScrollFrame", "NepoCleanseListScroll" .. listCount, box, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -2)
	scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -24, 2)
	L.scroll = scroll
	for i = 1, numRows do
		local r = CreateFrame("Frame", nil, box)
		r:SetHeight(20)
		r:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -2 - (i - 1) * 20)
		r:SetPoint("RIGHT", box, "RIGHT", -26, 0)
		r.stripe = r:CreateTexture(nil, "BACKGROUND")
		r.stripe:SetAllPoints(r)
		r.stripe:SetTexture(FLAT)
		r.stripe:SetVertexColor(1, 1, 1, math.mod(i, 2) == 0 and .03 or 0)
		r.dot = r:CreateTexture(nil, "ARTWORK")
		r.dot:SetTexture(FLAT)
		r.dot:SetWidth(6)
		r.dot:SetHeight(6)
		r.dot:SetPoint("LEFT", r, "LEFT", 2, 0)
		r.text = Text(r, nil, 11)
		r.text:SetPoint("LEFT", r, "LEFT", 13, 0)
		r.b2 = SmallButton(r, "", 52)
		r.b2:SetPoint("RIGHT", r, "RIGHT", 0, 0)
		r.b1 = SmallButton(r, "", 52)
		r.b1:SetPoint("RIGHT", r.b2, "LEFT", -2, 0)
		r.down = SmallButton(r, "Down", 40)
		r.down:SetPoint("RIGHT", r.b1, "LEFT", -2, 0)
		r.up = SmallButton(r, "Up", 30)
		r.up:SetPoint("RIGHT", r.down, "LEFT", -2, 0)
		r.top = SmallButton(r, "Top", 34)
		r.top:SetPoint("RIGHT", r.up, "LEFT", -2, 0)
		r.top:SetScript("OnClick", function() local it = this:GetParent().item if it and it.toTop then it.toTop(it) end end)
		r.up:SetScript("OnClick", function() local it = this:GetParent().item if it and it.move then it.move(it, -1) end end)
		r.down:SetScript("OnClick", function() local it = this:GetParent().item if it and it.move then it.move(it, 1) end end)
		r.tag = Text(r, "GameFontDisableSmall", 10, "RIGHT")
		r.tag:SetPoint("RIGHT", r.b1, "LEFT", -6, 0)
		r.b1:SetScript("OnClick", function() local it = this:GetParent().item if it and it.b1 then it.b1[2](it) end end)
		r.b2:SetScript("OnClick", function() local it = this:GetParent().item if it and it.b2 then it.b2[2](it) end end)
		L.rows[i] = r
	end
	function L.Update()
		local n = getn(L.items)
		FauxScrollFrame_Update(scroll, n, numRows, 20)
		local off = FauxScrollFrame_GetOffset(scroll)
		for i = 1, numRows do
			local r, it = L.rows[i], L.items[i + off]
			r.item = it
			if it then
				r.text:SetText(it.text)
				if it.grey then r.text:SetTextColor(.5, .5, .5) else r.text:SetTextColor(1, 1, 1) end
				r.tag:SetText(it.tag or "")
				if it.dot then r.dot:SetVertexColor(it.dot[1], it.dot[2], it.dot[3], 1) else r.dot:SetVertexColor(0, 0, 0, 0) end
				if it.b1 then r.b1:SetText(it.b1[1]) r.b1:Show() else r.b1:Hide() end
				if it.b2 then r.b2:SetText(it.b2[1]) r.b2:Show() else r.b2:Hide() end
				r.tag:ClearAllPoints()
				if it.move then
					r.up:Show() r.down:Show() r.top:Show()
					r.tag:SetPoint("RIGHT", r.top, "LEFT", -6, 0)
				else
					r.up:Hide() r.down:Hide() r.top:Hide()
					r.tag:SetPoint("RIGHT", r.b1, "LEFT", -6, 0)
				end
				if it.move and it.first then r.up:Disable() r.top:Disable() else r.up:Enable() r.top:Enable() end
				if it.move and it.last then r.down:Disable() else r.down:Enable() end
				r:Show()
			else
				r:Hide()
			end
		end
		if L.empty then
			if n == 0 then L.empty:Show() else L.empty:Hide() end
		end
	end
	L.empty = Text(box, "GameFontDisableSmall", 11, "CENTER")
	L.empty:SetPoint("CENTER", box, "CENTER", -10, 0)
	L.empty:SetText("Nothing matches.")
	scroll:SetScript("OnVerticalScroll", function() FauxScrollFrame_OnVerticalScroll(20, L.Update) end)
	return L
end

local function Matches(s, q)
	return q == "" or string.find(string.lower(s), q, 1, true) ~= nil
end

local function Query(eb) return string.lower(eb:GetText() or "") end

------------------------------------------------------------------------------
-- People page
------------------------------------------------------------------------------
local people = {}
local function BuildPeople(p)
	-- two lists; the one whose tab is selected is the one in use
	people.tabs = {}
	local labels = { "My list", "Raid list" }
	for i = 1, 2 do
		local b = SmallButton(p, labels[i], 100, function()
			R.SetProfile(this.profile)
			people.search:SetText("")
			people.Update()
		end)
		b.profile = i
		b:SetPoint("TOPLEFT", p, "TOPLEFT", (i - 1) * 102, 0)
		people.tabs[i] = b
	end
	people.summary = Text(p, nil, 11)
	people.summary:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -24)
	people.summary:SetPoint("RIGHT", p, "RIGHT", 0, 0)
	people.search = SearchBox(p, "NepoCleansePeopleSearch", "Search names...", function() people.Update() end)
	people.search:SetPoint("TOPLEFT", p, "TOPLEFT", 6, -40)
	people.search:SetPoint("RIGHT", p, "RIGHT", 0, 0)
	people.list = MakeList(p, 12)
	people.list.box:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -64)
	people.list.box:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 30)

	people.add = SearchBox(p, "NepoCleansePeopleAdd", "Add a name...", nil)
	people.add:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 6, 2)
	people.add:SetWidth(110)
	local function addIt()
		R.AddName(people.add:GetText())
		people.add:SetText("")
		people.add:ClearFocus()
		people.Update()
	end
	people.add:SetScript("OnEnterPressed", addIt)
	local addB = SmallButton(p, "Add", 50, addIt)
	addB:SetPoint("LEFT", people.add, "RIGHT", 6, 0)
	local tgtB = SmallButton(p, "Add target", 80, function()
		if UnitExists("target") and UnitIsPlayer("target") and UnitIsFriend("player", "target") then
			local _, class = UnitClass("target")
			R.NoteClass(UnitName("target"), class)
			R.AddName(UnitName("target"))
			people.Update()
		else
			Say("target a friendly player first.")
		end
	end)
	tgtB:SetPoint("LEFT", addB, "RIGHT", 4, 0)
	local frB = SmallButton(p, "Add all friends", 110, function()
		local added = R.AddFriends()
		Say(added > 0 and ("added " .. added .. " friends to the bottom of your list.") or "all your friends are already on your list.")
		people.Update()
	end)
	frB:SetPoint("LEFT", tgtB, "RIGHT", 4, 0)
	people.mine = { people.add, addB, tgtB, frB }

	people.import = SmallButton(p, "Import raid", 110, function()
		local n, tanks = R.ImportRaid()
		if n == 0 then
			Say("you're not in a raid or party, so there was no one to import.")
		else
			Say("Raid list replaced with " .. n .. " people" .. (tanks > 0 and (", " .. tanks .. " main tank(s) at the top.")
				or ". No main tanks are marked (pfUI tank or CT_RaidAssist), so it starts with paladins."))
		end
		people.Update()
	end)
	people.import:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 3)

	function people.Update()
		local q = Query(people.search)
		local inGroup = {}
		for _, name in pairs(R.units) do inGroup[name] = true end
		local profile = R.db.profile
		for i = 1, 2 do
			if i == profile then people.tabs[i]:LockHighlight() else people.tabs[i]:UnlockHighlight() end
		end
		for i = 1, getn(people.mine) do
			if profile == 1 then people.mine[i]:Show() else people.mine[i]:Hide() end
		end
		if profile == 2 then people.import:Show() else people.import:Hide() end
		local tanks = R.MainTanks()
		local list = R.List()
		local n = getn(list)
		local items = {}
		for i = 1, n do
			local name = list[i]
			if Matches(name, q) then
				local class = R.db.classes[name]
				table.insert(items, { text = "|cffffd100" .. i .. ".|r  " .. Hex(R.CLASS_COLOR[class] or "bbbbbb") .. name .. "|r",
					name = name,
					tag = (tanks[name] and "|cffc79c6emain tank|r" or "") .. (tanks[name] and inGroup[name] and ", " or "")
						.. (inGroup[name] and "in group" or ""),
					dot = inGroup[name] and { .2, 1, .2 } or { .35, .35, .35 },
					first = i == 1, last = i == n,
					move = function(it, step) R.MoveName(it.name, step) people.Update() end,
					toTop = function(it) R.MoveToTop(it.name) people.Update() end,
					b2 = { "Remove", function(it) R.RemoveName(it.name) people.Update() end } })
			end
		end
		people.list.items = items
		if q ~= "" then
			people.list.empty:SetText("No one matches.")
		elseif profile == 2 then
			people.list.empty:SetText("Empty. Join a raid and press Import raid.")
		else
			people.list.empty:SetText("No one yet. Add names below.")
		end
		people.list.Update()
		people.summary:SetText("|cff33ff33In use.|r Only these |cffffffff" .. n .. "|r people are watched, top first. Green dot = in your group.")
	end
end

------------------------------------------------------------------------------
-- Debuffs page
------------------------------------------------------------------------------
local debuffs = { mode = "all" }
local MODES = { { "all", "All" }, { "ignored", "Hidden" }, { "first", "Shown first" }, { "seen", "Seen" } }

local function BuildDebuffs(p)
	local x = 0
	debuffs.tabs = {}
	for i = 1, getn(MODES) do
		local m = MODES[i]
		local b = SmallButton(p, m[2], 78, function()
			debuffs.mode = this.mode
			debuffs.Update()
		end)
		b.mode = m[1]
		b:SetPoint("TOPLEFT", p, "TOPLEFT", x, 0)
		x = x + 80
		debuffs.tabs[i] = b
	end
	debuffs.search = SearchBox(p, "NepoCleanseDebuffSearch", "Search debuffs...", function() debuffs.Update() end)
	debuffs.search:SetPoint("TOPLEFT", p, "TOPLEFT", 6, -22)
	debuffs.search:SetPoint("RIGHT", p, "RIGHT", 0, 0)
	debuffs.list = MakeList(p, 12)
	debuffs.list.box:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -46)
	debuffs.list.box:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 30)

	debuffs.add = SearchBox(p, "NepoCleanseDebuffAdd", "Hide a debuff by name...", nil)
	debuffs.add:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 6, 2)
	debuffs.add:SetWidth(200)
	local function addIt()
		local t = debuffs.add:GetText()
		if t and t ~= "" then R.db.ignore[t] = true R.ScanAll() end
		debuffs.add:SetText("")
		debuffs.add:ClearFocus()
		debuffs.Update()
	end
	debuffs.add:SetScript("OnEnterPressed", addIt)
	SmallButton(p, "Hide", 50, addIt):SetPoint("LEFT", debuffs.add, "RIGHT", 6, 0)
	SmallButton(p, "Reset lists", 80, function()
		R.db.ignore = nil
		R.db.first = nil
		NepoCleanse_ResetLists()
		R.ScanAll()
		debuffs.Update()
		Say("hidden and shown-first lists are back to the starting set.")
	end):SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 3)

	function debuffs.Update()
		local db, q, mode = R.db, Query(debuffs.search), debuffs.mode
		for i = 1, getn(debuffs.tabs) do
			local b = debuffs.tabs[i]
			if b.mode == mode then b:LockHighlight() else b:UnlockHighlight() end
		end
		local names = {}
		for n in pairs(db.ignore) do names[n] = true end
		for n in pairs(db.first) do names[n] = true end
		for n in pairs(R.seen) do names[n] = true end
		local items = {}
		for n in pairs(names) do
			local hidden, first, seen = db.ignore[n], db.first[n], R.seen[n]
			local keep = (mode == "all") or (mode == "ignored" and hidden) or (mode == "first" and first)
				or (mode == "seen" and seen)
			if keep and Matches(n, q) then
				local tag
				if hidden then tag = "hidden" elseif first then tag = "|cffffd100shown first|r" else tag = "shown" end
				if seen then tag = tag .. ", seen (" .. seen .. ")" end
				local c = seen and R.TYPE_COLOR[seen]
				table.insert(items, { text = n, grey = hidden, tag = tag, dot = c,
					b1 = { hidden and "Show" or "Hide", function(it)
						if R.db.ignore[it.text] then R.db.ignore[it.text] = nil else R.db.ignore[it.text] = true end
						R.ScanAll() debuffs.Update()
					end },
					b2 = { first and "Normal" or "First", function(it)
						if R.db.first[it.text] then R.db.first[it.text] = nil else R.db.first[it.text] = true end
						R.ScanAll() debuffs.Update()
					end } })
			end
		end
		-- class rules (fixed): only on the All and Hidden pages
		if mode == "all" or mode == "ignored" then
			for class, list in pairs(R.CLASS_IGNORE) do
				for i = 1, getn(list) do
					if Matches(list[i], q) then
						table.insert(items, { text = list[i], grey = true,
							tag = "hidden on " .. Hex(R.CLASS_COLOR[class]) .. string.lower(class) .. "s|r only" })
					end
				end
			end
		end
		table.sort(items, function(a, b)
			if a.text == b.text then return (a.b1 and 1 or 0) > (b.b1 and 1 or 0) end
			return a.text < b.text
		end)
		debuffs.list.items = items
		debuffs.list.empty:SetText(mode == "seen" and q == "" and "Nothing seen yet this session." or "Nothing matches.")
		debuffs.list.Update()
	end
end

------------------------------------------------------------------------------
-- General page
------------------------------------------------------------------------------
local general = {}
local checkCount = 0
local function Check(p, label, key, x, y, after)
	checkCount = checkCount + 1
	local name = "NepoCleanseCheck" .. checkCount
	local c = CreateFrame("CheckButton", name, p, "OptionsCheckButtonTemplate")
	c:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
	c:SetWidth(24)
	c:SetHeight(24)
	c:SetHitRectInsets(0, 0, 0, 0)   -- only the box itself is clickable, not the words
	getglobal(name .. "Text"):SetText(label)
	c:SetScript("OnShow", function() this:SetChecked(R.db[key] and 1 or nil) end)
	c:SetScript("OnClick", function()
		R.db[key] = this:GetChecked() and true or false
		if after then after() end
	end)
	return c
end

local sliderCount = 0
local function Slider(p, label, key, lo, hi, step, x, y, fmt, after)
	sliderCount = sliderCount + 1
	local name = "NepoCleanseSlider" .. sliderCount
	local s = CreateFrame("Slider", name, p, "OptionsSliderTemplate")
	s:SetPoint("TOPLEFT", p, "TOPLEFT", x, y)
	s:SetWidth(150)
	s:SetMinMaxValues(lo, hi)
	s:SetValueStep(step)
	getglobal(name .. "Low"):SetText("")
	getglobal(name .. "High"):SetText("")
	local function label_()
		getglobal(name .. "Text"):SetText(label .. ": " .. string.format(fmt, R.db[key]))
	end
	s:SetScript("OnShow", function() this:SetValue(R.db[key]) label_() end)
	s:SetScript("OnValueChanged", function()
		R.db[key] = this:GetValue()
		label_()
		if after then after() end
	end)
	return s
end

local function Heading(p, text, y)
	local t = Text(p, "GameFontNormal")
	t:SetPoint("TOPLEFT", p, "TOPLEFT", 0, y)
	t:SetText(text)
	return t
end

local function BuildGeneral(p)
	local function where() R.UpdateActive() general.Update() end
	Heading(p, "Where it runs", 0)
	Check(p, "Dungeons", "dungeons", 0, -16, where)
	Check(p, "Raids", "raids", 110, -16, where)
	Check(p, "Battlegrounds", "battlegrounds", 200, -16, where)
	Check(p, "Everywhere, also outside instances", "everywhere", 0, -38, where)
	general.status = Text(p, nil, 11)
	general.status:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -66)
	general.status:SetPoint("RIGHT", p, "RIGHT", 0, 0)

	Heading(p, "What it shows", -90)
	Check(p, "Watch me too", "includeMe", 0, -106, function() R.RebuildWatched() end)
	Check(p, "Skip poison/disease already being cured by Abolish", "skipAbolish", 0, -128, function() R.ScanAll() end)
	general.spells = Text(p, "GameFontDisableSmall", 11)
	general.spells:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -156)
	general.spells:SetPoint("RIGHT", p, "RIGHT", 0, 0)

	Heading(p, "Look and sound", -182)
	Check(p, "Play a sound when a new debuff shows up", "sound", 0, -198)
	Check(p, "Lock the list in place", "locked", 0, -220, function() R.ApplyLook() end)
	Slider(p, "Rows", "rows", 1, MAXROWS, 1, 6, -262, "%d", function() R.Refresh() end)
	Slider(p, "Size", "scale", .6, 1.6, .05, 176, -262, "%.2f", function() R.ApplyLook() end)

	local keys = Text(p, "GameFontDisableSmall", 10)
	keys:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 4, 4)
	keys:SetPoint("RIGHT", p, "RIGHT", 0, 0)
	keys:SetText("A key for \"remove the first debuff in range\" can be set in the game's Key Bindings, under NepoCleanse. /nepocleanse go does the same in a macro.")

	function general.Update()
		local db = R.db
		local inside, kind = IsInInstance()
		local where_
		if not inside then where_ = "outside an instance"
		elseif kind == "pvp" then where_ = "in a battleground"
		elseif kind == "raid" then where_ = "in a raid"
		else where_ = "in a dungeon" end
		general.status:SetText("Right now you are " .. where_ .. ", so NepoCleanse is "
			.. (R.active and "|cff33ff33running|r." or "|cff888888resting|r (using nothing)."))
		local parts = {}
		for _, kind_ in ipairs({ "Magic", "Curse", "Poison", "Disease", "Snare" }) do
			if R.CanRemove(kind_) then table.insert(parts, kind_ == "Snare" and "slows (Hand of Freedom)" or string.lower(kind_)) end
		end
		general.spells:SetText(getn(parts) > 0 and ("You can remove: " .. table.concat(parts, ", ") .. ".")
			or "Your class has no removal spells, so NepoCleanse stays off.")
	end
end

------------------------------------------------------------------------------
-- Title bar page
------------------------------------------------------------------------------
local titlebar = {}
local SWATCHES = { "66ccff", "ffd100", "33ff99", "ff7d0a", "f58cba", "ffffff", "aaaaaa", "ff4444" }

local function BuildTitleBar(p)
	local look = function() R.ApplyLook() end
	Heading(p, "Shown or hidden", 0)
	Check(p, "Show the title bar", "header", 0, -16, look)
	Check(p, "Show the name", "headerTitle", 0, -38, look)
	Check(p, "Show the count", "headerCount", 0, -60, look)
	Check(p, "Show \"nothing to remove\" when empty", "headerEmptyText", 0, -82, look)
	Check(p, "Coloured line under the bar", "headerLine", 0, -104, look)
	Check(p, "Hide everything when there is nothing to remove", "hideEmpty", 0, -126, look)
	local note = Text(p, "GameFontDisableSmall", 10)
	note:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -152)
	note:SetPoint("RIGHT", p, "RIGHT", 0, 0)
	note:SetText("While the list is unlocked the bar always shows, so you can drag it; hiding when empty also waits until it is locked.")

	Heading(p, "Look", -176)
	local nameBox = SearchBox(p, "NepoCleanseTitleText", "Name on the bar...", nil)
	nameBox:SetPoint("TOPLEFT", p, "TOPLEFT", 6, -194)
	nameBox:SetWidth(150)
	nameBox:SetScript("OnShow", function() this:SetText(R.db.title) end)
	local function saveName()
		R.db.title = nameBox:GetText() or ""
		nameBox:ClearFocus()
		R.ApplyLook()
	end
	nameBox:SetScript("OnEnterPressed", saveName)
	SmallButton(p, "Set name", 70, saveName):SetPoint("LEFT", nameBox, "RIGHT", 6, 0)

	local cl = Text(p, nil, 11)
	cl:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -224)
	cl:SetText("Colour:")
	titlebar.swatches = {}
	for i = 1, getn(SWATCHES) do
		local sw = CreateFrame("Button", nil, p)
		sw:SetWidth(18)
		sw:SetHeight(18)
		sw:SetPoint("TOPLEFT", p, "TOPLEFT", 50 + (i - 1) * 24, -220)
		sw.ring = sw:CreateTexture(nil, "BACKGROUND")
		sw.ring:SetTexture(FLAT)
		sw.ring:SetPoint("TOPLEFT", sw, "TOPLEFT", -2, 2)
		sw.ring:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT", 2, -2)
		sw.ring:SetVertexColor(1, 1, 1, 1)
		sw.fill = sw:CreateTexture(nil, "ARTWORK")
		sw.fill:SetTexture(FLAT)
		sw.fill:SetAllPoints(sw)
		sw.fill:SetVertexColor(RGB(SWATCHES[i]))
		sw.hex = SWATCHES[i]
		sw:SetScript("OnClick", function()
			R.db.headerColor = this.hex
			R.ApplyLook()
			titlebar.Update()
		end)
		titlebar.swatches[i] = sw
	end

	Slider(p, "Height", "headerHeight", 10, 28, 1, 6, -262, "%d", look)
	Slider(p, "Text size", "headerFont", 8, 16, 1, 176, -262, "%d", look)
	Slider(p, "Background", "headerAlpha", 0, 1, .05, 6, -302, "%.2f", look)

	function titlebar.Update()
		for i = 1, getn(titlebar.swatches) do
			local sw = titlebar.swatches[i]
			if sw.hex == R.db.headerColor then sw.ring:Show() else sw.ring:Hide() end
		end
	end
end

------------------------------------------------------------------------------
-- the window
------------------------------------------------------------------------------
local PAGES = { { "People", BuildPeople, people }, { "Debuffs", BuildDebuffs, debuffs }, { "Title bar", BuildTitleBar, titlebar }, { "General", BuildGeneral, general } }

local function ShowPage(i)
	for j = 1, getn(PAGES) do
		local b = navButtons[j]
		if j == i then pages[j]:Show() b.sel:Show() b.edge:Show()
		else pages[j]:Hide() b.sel:Hide() b.edge:Hide() end
	end
	win.page = i
	PAGES[i][3].Update()
end

local function BuildOptions()
	win = CreateFrame("Frame", "NepoCleanseOptions", UIParent)
	win:SetWidth(520)
	win:SetHeight(400)
	win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	win:SetFrameStrata("DIALOG")
	win:SetToplevel(true)
	win:EnableMouse(true)
	win:SetMovable(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", function() this:StartMoving() end)
	win:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
	Backdrop(win, .95)
	table.insert(UISpecialFrames, "NepoCleanseOptions")

	local title = Text(win, "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", win, "TOPLEFT", 14, -12)
	title:SetText("|cff66ccffNepoCleanse|r")
	local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", win, "TOPRIGHT", 2, 2)

	local nav = CreateFrame("Frame", nil, win)
	nav:SetPoint("TOPLEFT", win, "TOPLEFT", 8, -40)
	nav:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 8, 8)
	nav:SetWidth(96)
	for i = 1, getn(PAGES) do
		local b = CreateFrame("Button", nil, nav)
		b:SetHeight(24)
		b:SetPoint("TOPLEFT", nav, "TOPLEFT", 0, -(i - 1) * 26)
		b:SetPoint("RIGHT", nav, "RIGHT", 0, 0)
		b:SetHighlightTexture(FLAT)
		b:GetHighlightTexture():SetVertexColor(1, 1, 1, .08)
		b.sel = b:CreateTexture(nil, "BACKGROUND")
		b.sel:SetAllPoints(b)
		b.sel:SetTexture(FLAT)
		b.sel:SetVertexColor(.4, .8, 1, .18)
		b.edge = b:CreateTexture(nil, "ARTWORK")
		b.edge:SetTexture(FLAT)
		b.edge:SetVertexColor(.4, .8, 1, 1)
		b.edge:SetWidth(2)
		b.edge:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
		b.edge:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
		local t = Text(b, "GameFontHighlight")
		t:SetPoint("LEFT", b, "LEFT", 10, 0)
		t:SetText(PAGES[i][1])
		b.index = i
		b:SetScript("OnClick", function() ShowPage(this.index) end)
		navButtons[i] = b

		local p = CreateFrame("Frame", nil, win)
		p:SetPoint("TOPLEFT", win, "TOPLEFT", 116, -40)
		p:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 10)
		PAGES[i][2](p)
		p:Hide()
		pages[i] = p
	end
	local sep = win:CreateTexture(nil, "ARTWORK")
	sep:SetTexture(FLAT)
	sep:SetVertexColor(1, 1, 1, .08)
	sep:SetWidth(1)
	sep:SetPoint("TOPLEFT", win, "TOPLEFT", 108, -40)
	sep:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", 108, 10)

	win:SetScript("OnShow", function() ShowPage(this.page or 1) end)
	win:Hide()
end

function R.RefreshOptions()
	if win and win:IsShown() and win.page then PAGES[win.page][3].Update() end
end

function NepoCleanse_ToggleOptions()
	if not win then BuildOptions() end
	if win:IsShown() then win:Hide() else win:Show() end
end

-- put back the starting hidden / shown-first lists
function NepoCleanse_ResetLists()
	local db = R.db
	db.ignore = {}
	for i = 1, getn(R.DEFAULT_IGNORE) do db.ignore[R.DEFAULT_IGNORE[i]] = true end
	db.first = {}
	for i = 1, getn(R.DEFAULT_FIRST) do db.first[R.DEFAULT_FIRST[i]] = true end
end

function R.BuildUI()
	if frame then return end
	BuildList()
	R.ApplyLook()
end
