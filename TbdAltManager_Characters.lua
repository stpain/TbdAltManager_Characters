

local addonName, addon = ...;

local playerUnitToken = "player";


--Global namespace for the module so addons can interact with it
TbdAltManager_Characters = {}

--Callback registry
TbdAltManager_Characters.CallbackRegistry = CreateFromMixins(CallbackRegistryMixin)
TbdAltManager_Characters.CallbackRegistry:OnLoad()
TbdAltManager_Characters.CallbackRegistry:GenerateCallbackEvents({
    "Character_OnAdded",
    "Character_OnChanged",
    "Character_OnRemoved",

    "DataProvider_OnInitialized",
})



local characterDefaults = {
    uid = "",
    level = -1,
    class = -1,
    guild = "",
    guildRank = -1,
    hearthstoneLocation = "",
    lastLogin = -1,
    xp = -1,
    xpMax = -1,
    xpRested = -1,
    faction = "",
    race = -1,
    daysPlayed = -1,
    gold = -1,
    zone = "",
    subZone = "",
    averageItemLevels = {1,1,1},
    currentSpecialization = -1,
}

local characterDefaultsToRemove = {

}

--Main DataProvider for the module
local CharacterDataProvider = CreateFromMixins(DataProviderMixin)

function CharacterDataProvider:InsertCharacter(characterUID)

    local character = self:FindElementDataByPredicate(function(characterData)
        return (characterData.uid == characterUID)
    end)

    if not character then        
        local newCharacter = {}
        for k, v in pairs(characterDefaults) do
            newCharacter[k] = v
        end

        newCharacter.uid = characterUID

        self:Insert(newCharacter)
        TbdAltManager_Characters.CallbackRegistry:TriggerEvent("Character_OnAdded")
    end
end

function CharacterDataProvider:FindCharacterByUID(characterUID)
    return self:FindElementDataByPredicate(function(character)
        return (character.uid == characterUID)
    end)
end

function CharacterDataProvider:UpdateDefaultKeys()
    for _, character in self:EnumerateEntireRange() do
        for k, v in pairs(characterDefaults) do
            if character[k] == nil then
                character[k] = v;
            end
        end
    end
end







--Expose some api via the namespace
TbdAltManager_Characters.Api = {}

function TbdAltManager_Characters.Api.EnumerateCharacters()
    return CharacterDataProvider:EnumerateEntireRange()
end

function TbdAltManager_Characters.Api.GetCharacterDataByUID(characterUID, key)
    local character = CharacterDataProvider:FindElementDataByPredicate(function(character)
        return (character.uid == characterUID)
    end)
    if key and character[key] then
        return character[key]
    else
        return character
    end
end

function TbdAltManager_Characters.Api.DeleteCharacterByCharacterUID(characterUID)
    CharacterDataProvider:RemoveByPredicate(function(character)
        return (character.uid == characterUID)
    end)
    TbdAltManager_Characters.CallbackRegistry:TriggerEvent("Character_OnRemoved", characterUID)
end








local eventsToRegister = {
    "ADDON_LOADED",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_LEVEL_CHANGED",
    "HEARTHSTONE_BOUND",
    "PLAYER_UPDATE_RESTING",
    "PLAYER_XP_UPDATE",
    "PLAYER_MONEY",
    "ZONE_CHANGED",
    "PLAYER_SPECIALIZATION_CHANGED",
}

--Frame to setup event listening
local CharacterEventFrame = CreateFrame("Frame")
for _, event in ipairs(eventsToRegister) do
    CharacterEventFrame:RegisterEvent(event)
end
CharacterEventFrame:SetScript("OnEvent", function(self, event, ...)
    if self[event] then
        self[event](self, ...)
    end
end)

function CharacterEventFrame:SetKeyValue(key, value)
    if self.character then
        self.character[key] = value;
        TbdAltManager_Characters.CallbackRegistry:TriggerEvent("Character_OnChanged", self.character)
        --print("triggered event")
    end
end

function CharacterEventFrame:ADDON_LOADED(...)
    if (... == addonName) then
        if TbdAltManager_Characters_SavedVariables == nil then

            CharacterDataProvider:Init({})
            TbdAltManager_Characters_SavedVariables = CharacterDataProvider:GetCollection()
    
        else
    
            local data = TbdAltManager_Characters_SavedVariables
            CharacterDataProvider:Init(data)
            TbdAltManager_Characters_SavedVariables = CharacterDataProvider:GetCollection()
    
        end

        CharacterDataProvider:UpdateDefaultKeys()

        if not CharacterDataProvider:IsEmpty() then
            TbdAltManager_Characters.CallbackRegistry:TriggerEvent("DataProvider_OnInitialized")
        end
    end
end

function CharacterEventFrame:PLAYER_ENTERING_WORLD()
    C_Timer.After(1.0, function()
        self:InitializeCharacter()
    end)
end

function CharacterEventFrame:InitializeCharacter()
    
    local account = "Default"
    local realm = GetRealmName()
    local name = UnitName(playerUnitToken)

    self.characterUID = string.format("%s.%s.%s", account, realm, name)

    CharacterDataProvider:InsertCharacter(self.characterUID)

    self.character = CharacterDataProvider:FindCharacterByUID(self.characterUID)

    self:SetKeyValue("level", UnitLevel(playerUnitToken))

    local raceID = select(3, UnitRace(playerUnitToken))
    self:SetKeyValue("race", raceID)

    --englishFaction, localizedFaction = UnitFactionGroup(unit)
    local faction = C_CreatureInfo.GetFactionInfo(raceID)
    self:SetKeyValue("faction", faction)

    self:SetKeyValue("hearthstoneLocation", GetBindLocation())

    self:SetKeyValue("gold", GetMoney())

    local classID = select(3, UnitClass(playerUnitToken))
    self:SetKeyValue("class", classID)

    self:SetKeyValue("gender", UnitSex(playerUnitToken))

    local prof1, prof2, archaeology, fishing, cooking = GetProfessions()

    if prof1 then
        self:SetKeyValue("profession1", select(7, GetProfessionInfo(prof1)))
    end
    if prof2 then
        self:SetKeyValue("profession2", select(7, GetProfessionInfo(prof2)))
    end

    if archaeology then
        self:SetKeyValue("archaeology", select(7, GetProfessionInfo(archaeology)))
    end
    if fishing then
        self:SetKeyValue("fishing", select(7, GetProfessionInfo(fishing)))
    end
    if cooking then
        self:SetKeyValue("cooking", select(7, GetProfessionInfo(cooking)))
    end

    self:SetKeyValue("xp", UnitXP(playerUnitToken))
    self:SetKeyValue("xpMax", UnitXPMax(playerUnitToken))
    self:SetKeyValue("xpRested", GetXPExhaustion())

    local avgItemLevel, avgItemLevelEquipped, avgItemLevelPvp = GetAverageItemLevel()
    self:SetKeyValue("averageItemLevels", {
        [1] = avgItemLevel,
        [2] = avgItemLevelEquipped,
        [3] = avgItemLevelPvp
    })

    local specIndex = GetSpecialization()
    if specIndex then
        local id, name, description, icon, role, primaryStat = GetSpecializationInfo(specIndex)
        self:SetKeyValue("currentSpecialization", id)
    end

    if ViragDevTool_AddData then
        ViragDevTool_AddData(TbdAltManager_Characters_SavedVariables, addonName)
    end
end

function CharacterEventFrame:PLAYER_SPECIALIZATION_CHANGED()
    local specIndex = GetSpecialization()
    if specIndex then
        local id, name, description, icon, role, primaryStat = GetSpecializationInfo(specIndex)
        self:SetKeyValue("currentSpecialization", id)
    end
end

function CharacterEventFrame:PLAYER_MONEY(...)
    self:SetKeyValue("gold", GetMoney())
end

function CharacterEventFrame:PLAYER_LEVEL_CHANGED(...)
    C_Timer.After(1.0, function()
        self:SetKeyValue("level", UnitLevel(playerUnitToken))
        self:SetKeyValue("xp", UnitXP(playerUnitToken))
        self:SetKeyValue("xpMax", UnitXPMax(playerUnitToken))
        self:SetKeyValue("xpRested", GetXPExhaustion())
    end)
end

function CharacterEventFrame:PLAYER_XP_UPDATE(...)
    local unitTarget = ...
    if unitTarget == playerUnitToken then
        self:SetKeyValue("xp", UnitXP(playerUnitToken))
        self:SetKeyValue("xpMax", UnitXPMax(playerUnitToken))
        self:SetKeyValue("xpRested", GetXPExhaustion())
    end
end

function CharacterEventFrame:ZONE_CHANGED(...)
    self:SetKeyValue("zone", GetZoneText())
    self:SetKeyValue("subZone", GetSubZoneText())
end

