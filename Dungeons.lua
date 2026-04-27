local DUNGEON_NAME_TO_ID = {
    -- Midnight Season 1
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

-- Legacy mapIDs sent by older addons (e.g. Astral Keys) that differ from current season IDs
local LEGACY_ID_MAP = {
    [239] = "Seat of the Triumvirate",
    [161] = "Skyreach",
}
for legacyID, name in pairs(LEGACY_ID_MAP) do
    if not DUNGEON_ID_TO_NAME[legacyID] then
        DUNGEON_ID_TO_NAME[legacyID] = name
    end
end

local function GetDungeonIDByName(name)
    return DUNGEON_NAME_TO_ID[name]
end

local function GetDungeonNameByID(id)
    return DUNGEON_ID_TO_NAME[id]
end

KeyRoll.GetDungeonIDByName = GetDungeonIDByName
KeyRoll.GetDungeonNameByID = GetDungeonNameByID