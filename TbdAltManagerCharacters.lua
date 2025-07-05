

local addonName, TbdAltManagerCharacters = ...;

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

local baseProfessionIDs = {
    [164] = "Blacksmithing",
    [165] = "Leatherworking",
    [171] = "Alchemy",
    [182] = "Herbalism",
    [185] = "Cooking",
    [186] = "Mining",
    [197] = "Tailoring",
    [202] = "Engineering",
    [333] = "Enchanting",
    [356] = "Fishing",
    [393] = "Skinning",
    [755] = "Jewelcrafting",
    [773] = "Inscription",
    [129] = "First Aid"
}

local characterDefaults = {
    uid = "",
    level = -1,
    class = -1,
    guild = "",
    guildRank = -1,
    hearthstoneLocation = "",
    lastLogin = 1,
    lastLogout = 1,
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
    profession1 = false,
    profession2 = false,
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
    if character and key and character[key] then
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
    --"LEARNED_SPELL_IN_SKILL_LINE",
    "SKILL_LINES_CHANGED",
    --"TRAINER_UPDATE"
    "PLAYER_LEAVING_WORLD",
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

function CharacterEventFrame:InitializeCharacter(isInitial, isReload)
   
    local account = "Default"
    local realm = GetRealmName()
    local name = UnitName(playerUnitToken)

    self.characterUID = string.format("%s.%s.%s", account, realm, name)

    CharacterDataProvider:InsertCharacter(self.characterUID)

    self.character = CharacterDataProvider:FindCharacterByUID(self.characterUID)

    if isInitial then
        self:SetKeyValue("lastLogin", time())
    end

    self:SetKeyValue("level", UnitLevel(playerUnitToken))

    local raceID = select(3, UnitRace(playerUnitToken))
    self:SetKeyValue("race", raceID)

    local faction = C_CreatureInfo.GetFactionInfo(raceID)
    self:SetKeyValue("faction", faction)

    self:SetKeyValue("hearthstoneLocation", GetBindLocation())

    self:SetKeyValue("gold", GetMoney())

    local classID = select(3, UnitClass(playerUnitToken))
    self:SetKeyValue("class", classID)

    self:SetKeyValue("gender", UnitSex(playerUnitToken))

    self:UpdatePlayerProfessions()

    self:SetKeyValue("xp", UnitXP(playerUnitToken))
    self:SetKeyValue("xpMax", UnitXPMax(playerUnitToken))
    self:SetKeyValue("xpRested", GetXPExhaustion())

    local avgItemLevel, avgItemLevelEquipped, avgItemLevelPvp = GetAverageItemLevel()
    self:SetKeyValue("averageItemLevels", {
        [1] = avgItemLevel,
        [2] = avgItemLevelEquipped,
        [3] = avgItemLevelPvp
    })

    if WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then
     
    else
        local specIndex = GetSpecialization()
        if specIndex then
            local id, name, description, icon, role, primaryStat = GetSpecializationInfo(specIndex)
            self:SetKeyValue("currentSpecialization", id)
        end
    end


    if ViragDevTool_AddData then
        ViragDevTool_AddData(TbdAltManager_Characters_SavedVariables, addonName)
    end
end

function CharacterEventFrame:ResetCharacterData(characterUID)
    local character = CharacterDataProvider:FindCharacterByUID(characterUID)
    if character then
        for k, v in pairs(characterDefaults) do
            character[k] = v
        end
        self:ScanTradeskills()
        TbdAltManager_Characters.CallbackRegistry:TriggerEvent("Character_OnChanged")
    end
end

function CharacterEventFrame:SetKeyValue(key, value)
    if self.character then
        self.character[key] = value;
        TbdAltManager_Characters.CallbackRegistry:TriggerEvent("Character_OnChanged", self.character)
        --print("triggered event")
    end
end

-- function CharacterEventFrame:SetTradeskill(id)
--     if self.character.profession1 == id then
--         if self.character.profession2 == id then
            
--         else
--             self.character.profession2 = id
--             TbdAltManager_Characters.CallbackRegistry:TriggerEvent("Character_OnChanged", self.character)
--         end
--     else
--         self.character.profession1 = id
--         TbdAltManager_Characters.CallbackRegistry:TriggerEvent("Character_OnChanged", self.character)
--     end
-- end

function CharacterEventFrame:UpdatePlayerProfessions()

    if WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then
        
    else
        local prof1, prof2, archaeology, fishing, cooking = GetProfessions()

        if prof1 then
            self:SetKeyValue("profession1", select(7, GetProfessionInfo(prof1)))
        else
            self:SetKeyValue("profession1", false)
        end
        if prof2 then
            self:SetKeyValue("profession2", select(7, GetProfessionInfo(prof2)))
        else
            self:SetKeyValue("profession2", false)
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

function CharacterEventFrame:PLAYER_ENTERING_WORLD(...)
    local isInitial, isReload = ...;
    C_Timer.After(1.0, function()
        self:InitializeCharacter(isInitial, isReload)
    end)
end

function CharacterEventFrame:PLAYER_SPECIALIZATION_CHANGED()
    local specIndex = GetSpecialization()
    if specIndex then
        local id, name, description, icon, role, primaryStat = GetSpecializationInfo(specIndex)
        self:SetKeyValue("currentSpecialization", id)
    end
end

-- function CharacterEventFrame:LEARNED_SPELL_IN_SKILL_LINE(...)
--     local spellID, spellbookIndex, isGuild = ...;
--     local profID = select(7, GetProfessionInfo(spellbookIndex))
--     if baseProfessionIDs[profID] then
--         self:SetTradeskill(profID)
--     end
-- end

function CharacterEventFrame:SKILL_LINES_CHANGED(...)
    self:UpdatePlayerProfessions()
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

function CharacterEventFrame:PLAYER_LEAVING_WORLD(...)
    self:SetKeyValue("lastLogout", time())
end

















--[[

    Character row template

]]

local roleIcons = {
    DAMAGER = "UI-LFG-RoleIcon-DPS-Micro",
    TANK = "UI-LFG-RoleIcon-Tank-Micro",
    HEALER = "UI-LFG-RoleIcon-Healer-Micro",
    RANGED = "UI-LFG-RoleIcon-RangedDPS-Micro",
}


TbdAltManagerCharacterModuleListviewItemMixin = {}
function TbdAltManagerCharacterModuleListviewItemMixin:OnLoad()
    TbdAltManager_Characters.CallbackRegistry:RegisterCallback("Character_OnChanged", self.OnCharacterDataChanged, self)

    -- local mask = self.classIcon:CreateMaskTexture()
    -- mask:SetAllPoints(self.classIcon:GetNormalTexture())
    -- mask:SetTexture("Interface/CHARACTERFRAME/TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    -- self.classIcon:GetNormalTexture():AddMaskTexture(mask)
end


function TbdAltManagerCharacterModuleListviewItemMixin:OnUpdate(seconds)
    self:UpdateSessionTime()
end

function TbdAltManagerCharacterModuleListviewItemMixin:OnMouseDown(hardwareButton)

end

function TbdAltManagerCharacterModuleListviewItemMixin:SetDataBinding(binding, height)
    self:SetHeight(height)
    self.character = binding;
    self:Update()

    self.Profession1:SetHeight(height / 2)
    self.Profession2:SetHeight(height / 2)
end

function TbdAltManagerCharacterModuleListviewItemMixin:OnCharacterDataChanged(character)
    if self.character and (self.character.uid == character.uid) then
        self.character = character
        self:Update()
    end
end

function TbdAltManagerCharacterModuleListviewItemMixin:Update()

    --raceicon128-draenei-female

    if self.character then

        if self.character.faction then
            if self.character.faction.name == "Horde" then
                local r, g, b = PLAYER_FACTION_COLOR_HORDE:GetRGB()
                self.PortraitBorder:SetVertexColor(r, g, b)
            else
                local r, g, b = PLAYER_FACTION_COLOR_ALLIANCE:GetRGB()
                self.PortraitBorder:SetVertexColor(r, g, b)
            end
        end

        if self.character.gender and self.character.race then
            local raceInfo = C_CreatureInfo.GetRaceInfo(self.character.race)

            local gender = self.character.gender == 3 and "female" or "male"
            local race = raceInfo.raceName:lower():gsub(" ", "")

            if raceInfo.raceName:lower():find("lightforged", nil, true) then
                race = "lightforged";
            end

            if WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then
                self.Portrait:SetAtlas(string.format("raceicon-%s-%s", race, gender))
            else
                self.Portrait:SetAtlas(string.format("raceicon128-%s-%s", race, gender))
            end

        end

        local account, realm, name = strsplit(".", self.character.uid)

        self.Name:SetText(string.format("%s\n[%s]", name, realm))

        self.Level:SetText(string.format("R: %d", self.character.xpRested))

        self.LevelBar:SetMinMaxValues(1, self.character.xpMax)
        self.LevelBar:SetValue(self.character.xp)
        self.LevelBar.level:SetText(string.format("%d [%0.1f%%]", self.character.level, (self.character.xp / self.character.xpMax) * 100))

        self.LevelBar:SetScript("OnEnter", function()
            GameTooltip:SetOwner(self.LevelBar, "ANCHOR_RIGHT")
            GameTooltip:AddLine("XP")
            GameTooltip:AddLine(string.format("This level: %d / %d", self.character.xp, self.character.xpMax))
            if type(self.character.xpRested) == "number" and (self.character.xpRested > 0) then
                GameTooltip:AddLine(string.format("Rested: %d [%d]", self.character.xpRested, math.floor(self.character.xpRested / 2)))
            end
            GameTooltip:AddLine(" ")
            --GameTooltip:AddLine(L.CHARACTER_XP_TOOLTIP)
            GameTooltip:Show()
        end)
        self.LevelBar:SetScript("OnLeave", function()
            GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
        end)

        self.Ilvl:SetText(string.format("%d / %d\nPvP %d", self.character.averageItemLevels[2], self.character.averageItemLevels[1], self.character.averageItemLevels[3]))
        
        if self.character.class then
            local class, classString, classID = GetClassInfo(self.character.class)
            if class then
                if (self.character.currentSpecialization > 0) and (self.character.level > 9) then
                local id, specName, description, icon, role, isRecommended, isAllowed = GetSpecializationInfoForSpecID(self.character.currentSpecialization)
                self.Class:SetText(string.format("%s %s", specName, class))
                    self.ClassIcon.Icon:SetTexture(icon)
                    self.ClassIcon:SetScript("OnEnter", function()
                        GameTooltip:SetOwner(self.ClassIcon, "ANCHOR_RIGHT")
                        GameTooltip:AddLine(specName)
                        GameTooltip:AddLine(description, 1,1,1)
                        GameTooltip:AddLine(_G[role])
                        GameTooltip:Show()
                    end)
                    self.ClassIcon.RoleIcon:SetAtlas(roleIcons[role])
                else
                    self.Class:SetText(class)
                    self.ClassIcon.Icon:SetAtlas(string.format("classicon-%s", classString:lower()))
                end
            end
            if classString then
                local r, g, b = RAID_CLASS_COLORS[classString]:GetRGB()
                self.Background:SetColorTexture(r, g, b, 0.1)
                self.ClassIcon.Border:SetVertexColor(r, g, b, 1)
            end
        end

        self.Location:SetText( string.format("%s\n%s", self.character.zone, self.character.subZone))

        self.SessionTimes:SetText(TbdAltsManager.Api.SecondsFormatter:Format(time() - self.character.lastLogin))
        -- self.SessionTimes:SetText(string.format("%s %s\n%s %s",
        --     CreateAtlasMarkup("poi-door-right", 14, 14),
        --     date(TbdAltsManager.Constants.DateFormat, self.character.lastLogin),
        --     CreateAtlasMarkup("poi-door-left", 14, 14),
        --     date(TbdAltsManager.Constants.DateFormat, self.character.lastLogout),
        --     TbdAltsManager.Api.SecondsFormatter:Format(time() - self.character.lastLogout)
        -- ))

        if self.character.profession1 and (self.character.profession1 > 0) then
            local profession1 = C_TradeSkillUI.GetProfessionInfoBySkillLineID(self.character.profession1)
            if profession1 and profession1.professionName then
                self.Profession1:SetText(profession1.professionName)
            end
        else
            self.Profession1:SetText("")
        end

        if self.character.profession2 and (self.character.profession2 > 0) then
            local profession2 = C_TradeSkillUI.GetProfessionInfoBySkillLineID(self.character.profession2)
            if profession2 and profession2.professionName then
                self.Profession2:SetText(profession2.professionName)
            end
        else
            self.Profession2:SetText("")
        end

        if self.character.gold > 0 then
            self.Gold:SetText(C_CurrencyInfo.GetCoinTextureString(self.character.gold, 14))
        end
    end

end

function TbdAltManagerCharacterModuleListviewItemMixin:UpdateSessionTime()
    if self.character then
        if CharacterEventFrame.characterUID == self.character.uid then
            self.SessionTimes:SetText(DIM_GREEN_FONT_COLOR:WrapTextInColorCode(TbdAltsManager.Api.SecondsFormatter:Format(time() - self.character.lastLogin)))
        else
            self.SessionTimes:SetText(TbdAltsManager.Api.SecondsFormatter:Format(time() - self.character.lastLogin))
        end
    end
end


function TbdAltManagerCharacterModuleListviewItemMixin:ResetDataBinding()
    self.Profession1:SetText(" ")
    self.Profession2:SetText(" ")
end















TbdAltManagerCharactersMixin = {
    name = "Characters",
    menuEntry = {
        height = 40,
        template = "TbdAltManagerSideBarListviewItemTemplate",
        initializer = function(frame)
            frame.Label:SetText("Characters")
            frame.Icon:SetAtlas("charactercreate-gendericon-female-selected")
            frame:SetScript("OnMouseUp", function()
                TbdAltsManager.Api.SelectModule("Characters")
            end)
            TbdAltsManager.Api.SetupSideMenuItem(frame, true, false)
        end,
    }
}

function TbdAltManagerCharactersMixin:OnLoad()
    TbdAltsManager.Api.RegisterModule(self)

    self:SetNewDataProvider()

    self:SetupSortButtons()

    TbdAltManager_Characters.CallbackRegistry:RegisterCallback("DataProvider_OnInitialized", self.InitializeCharacters, self)
    TbdAltManager_Characters.CallbackRegistry:RegisterCallback("Character_OnAdded", self.InitializeCharacters, self)
    TbdAltManager_Characters.CallbackRegistry:RegisterCallback("Character_OnRemoved", self.Character_OnRemoved, self)
    TbdAltManager_Characters.CallbackRegistry:RegisterCallback("Character_OnChanged", self.OnCharacterDataChanged, self)
end




function TbdAltManagerCharactersMixin:OnShow()
    self:InitializeCharacters()
end

function TbdAltManagerCharactersMixin:OnCharacterDataChanged()
    self.dataProvider:Sort()
end

function TbdAltManagerCharactersMixin:SetNewDataProvider()
    self.dataProvider = CreateFromMixins(DataProviderMixin)
    self.dataProvider:Init({})
    --self.dataProvider:SetSortComparator(TbdAltManager.Api.SortCharactersFunc)
    self.listview.scrollView:SetDataProvider(self.dataProvider)
end


-- function TbdAltManagerCharactersMixin:OnCharacterDataChanged(character)
--     local elementData = self.dataProvider:FindElementDataByPredicate(function(data)
--         return data.uid == character.uid
--     end)

--     if elementData then
--         local frame = self.listview.scrollView:FindFrame(elementData)
--         if frame and frame.Update then
--             frame:Update()
--         end
--     end
-- end

function TbdAltManagerCharactersMixin:Character_OnRemoved(characterUID)
    self.dataProvider:RemoveByPredicate(function(character)
        return (character.uid == characterUID)
    end)
end

function TbdAltManagerCharactersMixin:InitializeCharacters()

    self:SetNewDataProvider()

    if TbdAltManager_Characters and TbdAltManager_Characters.Api then
        for k, character in TbdAltManager_Characters.Api.EnumerateCharacters() do
            self.dataProvider:Insert(character)
        end
        self.dataProvider:Sort()
    end
end

function TbdAltManagerCharactersMixin:SetupSortButtons()

    local function sortLevel(order)
        if order == 1 then
            return function(a, b)
                return a.level > b.level;
            end
        elseif order == 2 then
            return function(a, b)
                return a.level < b.level;
            end
        elseif order == 3 then
            return function(a, b)
                return a.xpRested > b.xpRested;
            end
        elseif order == 4 then
            return function(a, b)
                return a.xpRested < b.xpRested;
            end
        end
    end
  
    self.sortLevel.order = 1
    self.sortLevel:SetScript("OnClick", function(button)
        button.order = button.order + 1;
        if button.order == 5 then
            button.order = 1;
        end
        if button.order > 2 then
            button:SetText("Rested")
        else
            button:SetText(LEVEL)
        end
        self.dataProvider:SetSortComparator(sortLevel(button.order))
        self.dataProvider:Sort()
    end)

    local function sortItemLevel(order)
        return function(a, b)
            return a.averageItemLevels[order] > b.averageItemLevels[order];
        end
    end
    
    self.sortItemLevel.order = 1
    self.sortItemLevel:SetScript("OnClick", function(button)
        button.order = button.order + 1;
        if button.order == 4 then
            button.order = 1;
        end
        self.dataProvider:SetSortComparator(sortItemLevel(button.order))
        self.dataProvider:Sort()
    end)

    local function sortClass(order)
        if order == 1 then
            return function(a, b)
                return a.class < b.class
            end

        elseif order == 2 then
            return function(a, b)
                return a.class > b.class
            end
        end
    end

    self.sortClass.order = 1;
    self.sortClass:SetScript("OnClick", function(button)
        button.order = button.order + 1;
        if button.order == 3 then
            button.order = 1;
        end
        self.dataProvider:SetSortComparator(sortClass(button.order))
        self.dataProvider:Sort()
    end)

    local function sortTradeSkills(order)
        if order == 1 then
            return function(a, b)
                if a.profession1 and b.profession1 and a.profession2 and b.profession2 then
                    
                end
                return a.class < b.class
            end

        elseif order == 2 then
            return function(a, b)
                return a.class > b.class
            end
        end
    end

    self.sortTradeSkills.order = 1;
    self.sortTradeSkills:SetScript("OnClick", function(button)
        button.order = button.order + 1;
        if button.order == 3 then
            button.order = 1;
        end
        self.dataProvider:SetSortComparator(sortTradeSkills(button.order))
        self.dataProvider:Sort()
    end)

    local function sortLocation(order)
        if order == 1 then
            return function(a, b)
                if a.zone == b.zone then
                    return a.subZone < b.subZone
                else
                    return a.zone < b.zone
                end
            end
        else
            return function(a, b)
                if a.zone == b.zone then
                    return a.subZone > b.subZone
                else
                    return a.zone > b.zone
                end
            end
        end
    end

    self.sortLocation.order = 1;
    self.sortLocation:SetScript("OnClick", function(button)
        button.order = button.order + 1;
        if button.order == 3 then
            button.order = 1;
        end
        self.dataProvider:SetSortComparator(sortLocation(button.order))
        self.dataProvider:Sort()
    end)

    local function sortLastLogin(order)
        if order == 1 then
            return function(a, b)
                return a.lastLogin > b.lastLogin
            end
        else
            return function(a, b)
                return a.lastLogin < b.lastLogin
            end
        end
    end

    self.sortLastLogin.order = 1;
    self.sortLastLogin:SetScript("OnClick", function(button)
        button.order = button.order + 1;
        if button.order == 3 then
            button.order = 1;
        end
        self.dataProvider:SetSortComparator(sortLastLogin(button.order))
        self.dataProvider:Sort()
    end)

end