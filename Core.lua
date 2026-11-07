--[[
  NepoCleanse - core

  Watches only the people you choose: everyone on your friends list, plus a list of names
  you add yourself. It is switched on inside dungeons, raids and battlegrounds and fully
  off everywhere else (no events, no timers, nothing on screen).

  Work is done when the game says a watched person's auras changed (UNIT_AURA), not on a
  timer: each change marks that person, and marked people are read again at most ten
  times a second. Range is checked four times a second, only while something is listed.
]]

NepoCleanse = {}
local R = NepoCleanse

BINDING_HEADER_NEPOCLEANSE = "NepoCleanse"
BINDING_NAME_NEPOCLEANSE_CLEANSE = "Remove the first debuff in range"
BINDING_NAME_NEPOCLEANSE_OPTIONS = "Open or close the settings"

local _, playerClass = UnitClass("player")

------------------------------------------------------------------------------
-- data
------------------------------------------------------------------------------
-- spells that remove each kind of debuff, best first ("Snare" is Hand of Freedom)
local SPELLS = {
	PALADIN = { Magic = { "Cleanse" }, Poison = { "Cleanse", "Purify" }, Disease = { "Cleanse", "Purify" }, Snare = { "Hand of Freedom" } },
	DRUID = { Curse = { "Remove Curse" }, Poison = { "Abolish Poison", "Cure Poison" } },
	PRIEST = { Magic = { "Dispel Magic" }, Disease = { "Abolish Disease", "Cure Disease" } },
	SHAMAN = { Poison = { "Cure Poison" }, Disease = { "Cure Disease" } },
	MAGE = { Curse = { "Remove Lesser Curse" } },
	WARLOCK = { Magic = { "Devour Magic" } },
}

R.TYPE_COLOR = {
	Magic = { .2, .6, 1 }, Curse = { .6, 0, 1 }, Disease = { .6, .4, 0 }, Poison = { 0, .6, 0 }, Snare = { .8, 0, 0 },
}

R.CLASS_COLOR = {
	WARRIOR = "c79c6e", DRUID = "ff7d0a", PALADIN = "f58cba", WARLOCK = "9482c9", MAGE = "69ccf0",
	PRIEST = "ffffff", ROGUE = "fff569", HUNTER = "abd473", SHAMAN = "0070de",
}

-- never shown (from Rinse: harmful to remove, harmless, or wanted)
R.DEFAULT_IGNORE = {
	"Curse of Recklessness", "Delusions of Jin'do", "Dread of Outland", "Curse of Legion", "Phase Shifted",
	"Unstable Mana", "Seed of Corruption", "Mutating Injection", "Sanctum Mind Decay", "Wyvern Sting",
	"Poison Mushroom", "Gastronomic Guilt", "Icicles", "Arcane Overload", "Dreamless Sleep",
	"Greater Dreamless Sleep", "Songflower Serenade", "Mol'dar's Moxie", "Fengus' Ferocity", "Slip'kik's Savvy",
	"Thunderfury", "Magma Shackles",
}

-- not shown on these classes only (from Rinse)
R.CLASS_IGNORE = {
	WARRIOR = { "Ancient Hysteria", "Ignite Mana", "Tainted Mind", "Moroes Curse", "Curse of Manascale" },
	ROGUE = { "Silence", "Ancient Hysteria", "Ignite Mana", "Tainted Mind", "Smoke Bomb", "Screams of the Past",
		"Moroes Curse", "Curse of Manascale" },
	WARLOCK = { "Rift Entanglement" },
}

-- shown first (from Rinse)
R.DEFAULT_FIRST = {
	"Tranquilizing Poison", "Wyrmkins Venom", "Slowing Poison", "Mana Buildup", "Enveloped Flames",
	"Poison Charge", "Arcane Focus", "Freezing Chill",
}

-- slows and roots a paladin can remove with Hand of Freedom
local SNARES = {
	["Hamstring"] = true, ["Wing Clip"] = true, ["Mind Flay"] = true, ["Web"] = true, ["Web Explosion"] = true,
	["Enveloping Web"] = true, ["Encasing Webs"] = true, ["Surge of Mana"] = true, ["Hooked Net"] = true,
}

local ABOLISH_ICON = {
	Poison = "Interface\\Icons\\Spell_Nature_NullifyPoison_02",
	Disease = "Interface\\Icons\\Spell_Nature_NullifyDisease",
}

------------------------------------------------------------------------------
-- settings
------------------------------------------------------------------------------
local DEFAULTS = {
	dungeons = true, raids = true, battlegrounds = true, everywhere = false,
	includeMe = false, skipAbolish = true, sound = true, locked = false,
	rows = 6, scale = 1,
	-- title bar
	header = true, headerTitle = true, headerCount = true, headerEmptyText = true, headerLine = true,
	hideEmpty = true, title = "NepoCleanse", headerHeight = 16, headerFont = 10, headerAlpha = .85,
	headerColor = "66ccff",
	-- window
	width = 230, rowHeight = 20, listAlpha = .7, windowAlpha = 1,
}

local db
local function Defaults()
	NepoCleanseDB = NepoCleanseDB or {}
	db = NepoCleanseDB
	for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
	db.whitelist = db.whitelist or {}   -- list 1, "My list"
	db.raidlist = db.raidlist or {}     -- list 2, "Raid list"
	db.profile = db.profile or 1
	db.classes = db.classes or {}
	if not db.ignore then
		db.ignore = {}
		for i = 1, getn(R.DEFAULT_IGNORE) do db.ignore[R.DEFAULT_IGNORE[i]] = true end
	end
	if not db.first then
		db.first = {}
		for i = 1, getn(R.DEFAULT_FIRST) do db.first[R.DEFAULT_FIRST[i]] = true end
	end
	R.db = db
end

------------------------------------------------------------------------------
-- state
------------------------------------------------------------------------------
R.active = false
R.friends = {}        -- name -> true
R.watched = {}        -- name -> "friend" / "list" / "me"
R.units = {}          -- unit token -> name, for watched people in the group
R.entries = {}        -- what is listed: { unit, name, class, debuff, type, icon, stacks, index, first, seen, inRange }
R.seen = {}           -- debuff name -> type, for the "seen" list in the settings
local usable = {}     -- debuff type -> spell name
local dirty = {}      -- unit -> true when its auras changed
local anyDirty = false
local nameCache = {}  -- spell id -> name (SuperWoW)
local order = 0

local scanTip = CreateFrame("GameTooltip", "NepoCleanseScanTip", nil, "GameTooltipTemplate")
scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function Lower(s) return s and string.lower(s) end

------------------------------------------------------------------------------
-- who is watched
------------------------------------------------------------------------------
function R.RebuildWatched()
	for k in pairs(R.watched) do R.watched[k] = nil end
	local list = R.List()
	for i = 1, getn(list) do R.watched[list[i]] = "list" end
	if db.includeMe then R.watched[UnitName("player")] = "me" end
	R.RebuildUnits()
end

-- class names as the friends list gives them ("Rogue") -> "ROGUE"
local CLASS_TOKEN = {}
for token in pairs(R.CLASS_COLOR) do
	CLASS_TOKEN[string.upper(token)] = token
end
function R.NoteClass(name, class)
	if name and class then
		class = CLASS_TOKEN[string.upper(class)] or class
		if R.CLASS_COLOR[class] then db.classes[name] = class end
	end
end

-- the friends list is only a starting point: the first time it is read, everyone on it is
-- added to your list. After that, your list is yours ("Add all friends" adds any new ones).
function R.ReadFriends()
	for k in pairs(R.friends) do R.friends[k] = nil end
	local n = GetNumFriends()
	for i = 1, n do
		local name, _, class = GetFriendInfo(i)
		if name then
			R.friends[name] = true
			R.NoteClass(name, class)
		end
	end
	if not db.seeded and n > 0 then
		db.seeded = true
		R.AddFriends()
	end
	if R.RefreshOptions then R.RefreshOptions() end
end

function R.AddFriends()
	local added = 0
	for i = 1, GetNumFriends() do
		local name = GetFriendInfo(i)
		if name then
			local there = false
			for j = 1, getn(db.whitelist) do if db.whitelist[j] == name then there = true break end end
			if not there then table.insert(db.whitelist, name) added = added + 1 end
		end
	end
	if added > 0 and db.profile == 1 then R.RebuildWatched() end
	return added
end

function R.RebuildUnits()
	for k in pairs(R.units) do R.units[k] = nil end
	local function add(unit)
		-- in a raid you are also one of raid1-40: keep only "player", so you get one row
		if unit ~= "player" and UnitIsUnit(unit, "player") then return end
		local name = UnitName(unit)
		if name and R.watched[name] then
			R.units[unit] = name dirty[unit] = true anyDirty = true
			local _, class = UnitClass(unit)
			R.NoteClass(name, class)
		end
	end
	add("player")
	if GetNumRaidMembers() > 0 then
		for i = 1, 40 do add("raid" .. i) end
	else
		for i = 1, 4 do add("party" .. i) end
	end
	-- drop rows of people who left
	for i = getn(R.entries), 1, -1 do
		local e = R.entries[i]
		if R.units[e.unit] ~= e.name then table.remove(R.entries, i) end
	end
	if R.Refresh then R.Refresh() end
end

-- the list in use (1 = My list, 2 = Raid list)
function R.List() return db.profile == 2 and db.raidlist or db.whitelist end

function R.SetProfile(p)
	db.profile = p
	R.RebuildWatched()
	R.Resort()
end

-- Raid list: everyone in the raid (or party), you included, main tanks first, then paladins,
-- priests and shamans, then everyone else by class. Replaces the old Raid list.
local IMPORT_ORDER = { PALADIN = 1, PRIEST = 2, SHAMAN = 3, WARRIOR = 4, DRUID = 5, ROGUE = 6, HUNTER = 7,
	MAGE = 8, WARLOCK = 9 }
function R.MainTanks()
	local tanks, n = {}, 0
	if type(CT_RA_MainTanks) == "table" then
		for _, name in pairs(CT_RA_MainTanks) do
			if type(name) == "string" and not tanks[name] then n = n + 1 tanks[name] = n end
		end
	end
	if pfUI and pfUI.uf and pfUI.uf.raid and type(pfUI.uf.raid.tankrole) == "table" then
		for name, on in pairs(pfUI.uf.raid.tankrole) do
			if on and not tanks[name] then n = n + 1 tanks[name] = n end
		end
	end
	return tanks, n
end

function R.ImportRaid()
	local people = {}
	local function add(name, class)
		if name then
			R.NoteClass(name, class)
			table.insert(people, { name = name, class = db.classes[name] or "" })
		end
	end
	local nr = GetNumRaidMembers()
	if nr > 0 then
		for i = 1, nr do
			local name, _, _, _, _, class = GetRaidRosterInfo(i)
			add(name, class)
		end
	else
		local _, myClass = UnitClass("player")
		add(UnitName("player"), myClass)
		for i = 1, GetNumPartyMembers() do
			local _, class = UnitClass("party" .. i)
			add(UnitName("party" .. i), class)
		end
	end
	if getn(people) == 0 then return 0, 0 end
	local tanks, nt = R.MainTanks()
	table.sort(people, function(a, b)
		local ta, tb = tanks[a.name], tanks[b.name]
		if ta or tb then
			if ta and tb then return ta < tb end
			return ta and true or false
		end
		local ca, cb = IMPORT_ORDER[a.class] or 99, IMPORT_ORDER[b.class] or 99
		if ca ~= cb then return ca < cb end
		return a.name < b.name
	end)
	for i = getn(db.raidlist), 1, -1 do table.remove(db.raidlist, i) end
	local tanksFound = 0
	for i = 1, getn(people) do
		table.insert(db.raidlist, people[i].name)
		if tanks[people[i].name] then tanksFound = tanksFound + 1 end
	end
	if db.profile == 2 then R.RebuildWatched() R.Resort() end
	return getn(people), tanksFound
end

function R.AddName(name)
	if not name or name == "" then return end
	name = string.upper(string.sub(name, 1, 1)) .. string.lower(string.sub(name, 2))
	local list = R.List()
	for i = 1, getn(list) do if list[i] == name then return end end
	table.insert(list, name)
	R.RebuildWatched()
end

function R.MoveToTop(name)
	local list = R.List()
	for i = 2, getn(list) do
		if list[i] == name then
			table.remove(list, i)
			table.insert(list, 1, name)
			R.Resort()
			return
		end
	end
end

-- your list is in priority order: 1 is looked after first
function R.MoveName(name, step)
	local list = R.List()
	for i = 1, getn(list) do
		if list[i] == name then
			local j = i + step
			if j >= 1 and j <= getn(list) then
				list[i], list[j] = list[j], list[i]
				R.Resort()
			end
			return
		end
	end
end

function R.RemoveName(name)
	local list = R.List()
	for i = getn(list), 1, -1 do
		if list[i] == name then table.remove(list, i) end
	end
	R.RebuildWatched()
end

------------------------------------------------------------------------------
-- spells
------------------------------------------------------------------------------
function R.ReadSpells()
	for k in pairs(usable) do usable[k] = nil end
	local mine = SPELLS[playerClass]
	if not mine then return end
	local have = {}
	for tab = 1, GetNumSpellTabs() do
		local _, _, offset, n = GetSpellTabInfo(tab)
		for id = offset + 1, offset + n do
			local name = GetSpellName(id, "spell")
			if name then have[name] = id end
		end
	end
	for kind, list in pairs(mine) do
		for i = 1, getn(list) do
			if have[list[i]] then usable[kind] = list[i] break end
		end
	end
end

function R.CanRemove(kind) return usable[kind] ~= nil end

------------------------------------------------------------------------------
-- reading debuffs
------------------------------------------------------------------------------
local function DebuffName(unit, i, spellId)
	if spellId and SpellInfo then
		local n = nameCache[spellId]
		if not n then n = SpellInfo(spellId) nameCache[spellId] = n end
		if n then return n end
	end
	NepoCleanseScanTipTextLeft1:SetText("")
	scanTip:SetUnitDebuff(unit, i)
	return NepoCleanseScanTipTextLeft1:GetText()
end

local function HasAbolish(unit, kind)
	local icon = ABOLISH_ICON[kind]
	if not icon then return false end
	for i = 1, 32 do
		local b = UnitBuff(unit, i)
		if not b then return false end
		if b == icon then return true end
	end
	return false
end

local function ClassIgnores(class, name)
	local list = R.CLASS_IGNORE[class]
	if not list then return false end
	for i = 1, getn(list) do if list[i] == name then return true end end
	return false
end

-- read one person again: keep the most important debuff we can remove
local function ScanUnit(unit)
	local name = R.units[unit]
	for i = getn(R.entries), 1, -1 do
		if R.entries[i].unit == unit then table.remove(R.entries, i) end
	end
	if not name or not UnitExists(unit) or UnitIsDeadOrGhost(unit) then return end
	local _, class = UnitClass(unit)
	local best
	for i = 1, 16 do
		local icon, stacks, kind, spellId = UnitDebuff(unit, i)
		if not icon then break end
		local dname = DebuffName(unit, i, spellId)
		if dname and SNARES[dname] then kind = "Snare" end
		if kind and dname then
			if not R.seen[dname] then R.seen[dname] = kind end
			if usable[kind] and not db.ignore[dname] and not ClassIgnores(class, dname)
				and not (db.skipAbolish and HasAbolish(unit, kind)) then
				local first = db.first[dname] and true or false
				if not best or (first and not best.first) then
					best = { unit = unit, name = name, class = class, debuff = dname, type = kind,
						icon = icon, stacks = stacks or 1, index = i, first = first }
				end
			end
		end
	end
	if best then
		order = order + 1
		best.seen = order
		table.insert(R.entries, best)
	end
end

-- order: people on your list by their place in it, then friends; within that,
-- "shown first" debuffs, then whoever got their debuff earliest
local rank = {}
local function SortEntries()
	for k in pairs(rank) do rank[k] = nil end
	local list = R.List()
	for i = 1, getn(list) do rank[list[i]] = i end
	table.sort(R.entries, function(a, b)
		local ra, rb = rank[a.name] or 1000, rank[b.name] or 1000
		if ra ~= rb then return ra < rb end
		if a.first ~= b.first then return a.first end
		return a.seen < b.seen
	end)
end

function R.Resort()
	SortEntries()
	if R.Refresh then R.Refresh() end
end

------------------------------------------------------------------------------
-- range (same checks as Rinse, cheapest first)
------------------------------------------------------------------------------
local hasUnitXP = pcall(UnitXP, "nop", "nop")
function R.InRange(unit)
	local near
	if UnitIsFriend("player", unit) and not UnitCanAttack("player", unit) then
		if hasUnitXP then
			near = UnitXP("distanceBetween", "player", unit) < 30
		elseif SUPERWOW_VERSION and UnitPosition then
			local x, y, z = UnitPosition("player")
			local ux, uy, uz = UnitPosition(unit)
			if ux then
				local dx, dy, dz = ux - x, uy - y, uz - z
				near = dx * dx + dy * dy + dz * dz <= 1089
			end
		else
			near = CheckInteractDistance(unit, 4)
		end
	else
		near = CheckInteractDistance(unit, 4)
	end
	if not near then return false end
	if hasUnitXP then return UnitXP("inSight", "player", unit) and true or false end
	return UnitIsVisible(unit) and true or false
end

------------------------------------------------------------------------------
-- removing
------------------------------------------------------------------------------
function R.Cleanse(e)
	if not e or not UnitExists(e.unit) then return false end
	local spell = usable[e.type]
	if not spell then return false end
	if not R.InRange(e.unit) then
		if db.sound then PlaySoundFile("Sound\\Interface\\Error.wav") end
		return false
	end
	if SUPERWOW_VERSION then
		CastSpellByName(spell, e.unit)
	else
		local selfcast = GetCVar("autoselfcast")
		local hadTarget = UnitExists("target")
		local same = hadTarget and UnitIsUnit("target", e.unit)
		SetCVar("autoselfcast", 0)
		if not same then TargetUnit(e.unit) end
		if UnitExists("target") and UnitIsUnit("target", e.unit) then CastSpellByName(spell) end
		if not same then
			if hadTarget then TargetLastTarget() else ClearTarget() end
		end
		SetCVar("autoselfcast", selfcast)
	end
	return true
end

function NepoCleanse_CleanseNext()
	if not R.active then return end
	for i = 1, getn(R.entries) do
		local e = R.entries[i]
		if e.inRange ~= false and R.Cleanse(e) then return end
	end
end

------------------------------------------------------------------------------
-- switching on and off
------------------------------------------------------------------------------
local f = CreateFrame("Frame", "NepoCleanseCore")

local function ShouldBeActive()
	if db.everywhere then return true end
	local inside, kind = IsInInstance()
	if not inside then return false end
	if kind == "pvp" then return db.battlegrounds end
	if kind == "raid" then return db.raids end
	if kind == "party" then return db.dungeons end
	-- an older client without the kind: a raid group means a raid
	if GetNumRaidMembers() > 0 then return db.raids end
	return db.dungeons
end

local WORK_EVENTS = { "UNIT_AURA", "RAID_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "SPELLS_CHANGED" }

function R.UpdateActive()
	local want = ShouldBeActive() and next(usable) ~= nil
	if want == R.active then return end
	R.active = want
	if want then
		for i = 1, getn(WORK_EVENTS) do f:RegisterEvent(WORK_EVENTS[i]) end
	else
		for i = 1, getn(WORK_EVENTS) do f:UnregisterEvent(WORK_EVENTS[i]) end
		for i = getn(R.entries), 1, -1 do table.remove(R.entries, i) end
		for k in pairs(dirty) do dirty[k] = nil end
		anyDirty = false
	end
	if R.OnActiveChanged then R.OnActiveChanged() end
end

f:RegisterEvent("VARIABLES_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("FRIENDLIST_UPDATE")   -- rare; keeps class colours and the starting list
f:SetScript("OnEvent", function()
	if event == "VARIABLES_LOADED" then
		Defaults()
		if R.BuildUI then R.BuildUI() end
	elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
		if not db then Defaults() end
		if R.BuildUI then R.BuildUI() end
		R.ReadSpells()
		if not R.askedFriends then R.askedFriends = true ShowFriends() end
		R.RebuildWatched()
		R.UpdateActive()
		if R.active then R.RebuildUnits() end
	elseif event == "UNIT_AURA" then
		if R.units[arg1] then dirty[arg1] = true anyDirty = true end
	elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
		R.RebuildUnits()
	elseif event == "FRIENDLIST_UPDATE" then
		R.ReadFriends()
	elseif event == "SPELLS_CHANGED" then
		R.ReadSpells()
	end
end)

-- reading marked people (10 a second at most) and range (4 a second, only with rows)
local sinceScan, sinceRange = 0, 0
f:SetScript("OnUpdate", function()
	if not R.active then return end
	sinceScan = sinceScan + arg1
	sinceRange = sinceRange + arg1
	if anyDirty and sinceScan >= .1 then
		sinceScan = 0
		anyDirty = false
		local before = getn(R.entries)
		for unit in pairs(dirty) do
			dirty[unit] = nil
			ScanUnit(unit)
		end
		SortEntries()
		if getn(R.entries) > before and db.sound then PlaySoundFile("Sound\\Doodad\\BellTollTribal.wav") end
		sinceRange = 1
		if R.Refresh then R.Refresh() end
	end
	if sinceRange >= .25 and getn(R.entries) > 0 then
		sinceRange = 0
		local changed = false
		for i = 1, getn(R.entries) do
			local e = R.entries[i]
			local r = R.InRange(e.unit)
			if r ~= e.inRange then e.inRange = r changed = true end
		end
		if changed and R.Refresh then R.Refresh() end
	end
end)

------------------------------------------------------------------------------
-- /nepocleanse
------------------------------------------------------------------------------
SLASH_NEPOCLEANSE1 = "/nepocleanse"
SLASH_NEPOCLEANSE2 = "/nc"
SlashCmdList["NEPOCLEANSE"] = function(msg)
	msg = string.lower(msg or "")
	if msg == "on" then
		db.everywhere = true
	elseif msg == "off" or msg == "auto" then
		db.everywhere = false
	elseif msg == "go" then
		return NepoCleanse_CleanseNext()
	else
		return NepoCleanse_ToggleOptions()
	end
	R.UpdateActive()
	DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffNepoCleanse:|r " .. (db.everywhere and "on everywhere" or "on in dungeons, raids and battlegrounds only")
		.. (R.active and " (active now)" or " (resting now)"))
end
