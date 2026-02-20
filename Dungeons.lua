local DUNGEON_NAME_TO_ID = {
    -- TWW Season 3
    ["Eco-Dome Al'dani"] = 542,
    ["Ara-Kara, City of Echoes"] = 503,
    ["The Dawnbreaker"] = 505,
    ["Priory of the Sacred Flame"] = 499,
    ["Operation: Floodgate"] = 525,
    ["Halls of Atonement"] = 378,
    ["Tazavesh: Streets of Wonder"] = 391,
    ["Tazavesh: So'leah's Gambit"] = 392,
	
	-- Midnight Beta
	["Magisters' Terrace"] = 558,
	["Maisara Caverns"] = 560,
	["Nexus-Point Xenas"] = 559,
	["Windrunner Spire"] = 557,
	["Algeth'ar Academy"] = 402,
	["Pit of Saron"] = 556,
	["Seat of the Triumvirate"] = 583,
	["Skyreach"] = 161,
}

local DUNGEON_ID_TO_NAME = {}
for name, id in pairs(DUNGEON_NAME_TO_ID) do
    DUNGEON_ID_TO_NAME[id] = name
end

local function GetDungeonIDByName(name)
    return DUNGEON_NAME_TO_ID[name]
end

local function GetDungeonNameByID(id)
    return DUNGEON_ID_TO_NAME[id]
end

KeyRoll.GetDungeonIDByName = GetDungeonIDByName
KeyRoll.GetDungeonNameByID = GetDungeonNameByID