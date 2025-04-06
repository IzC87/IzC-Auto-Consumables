-- Globals Section
local addonName, L = ...;
local MacroNames = {
    Bandage = "IzCBandage",
    Food = "IzCFood",
    Drink = "IzCDrink",
    BuffFood = "IzCBuffFood",
    Potion = "IzCPotion",
    ManaPotion = "IzCManaPotion",
    Healthstone = "IzCHealthstone",
    Grenade = "IzCGrenade"
}

local IzCAutoConsumables_TargetTrigger = GetTime();
local IzCAutoConsumables_TriggerWaitTime = 1;

local IzCAutoConsumables_ItemPlaceHolder = "PLACEHOLDER"
local IzCAutoConsumables_BaseMacro = "#showtooltip []" .. IzCAutoConsumables_ItemPlaceHolder .. ";\n"..
                                           "/use " .. IzCAutoConsumables_ItemPlaceHolder;

-- Create Tooltip
local hiddenToolTip = CreateFrame("GameTooltip", "hiddenToolTip", UIParent, "GameTooltipTemplate")
hiddenToolTip:SetOwner(UIParent, "ANCHOR_NONE")

-- Create a frame to handle events
local IzC_AC = CreateFrame("Frame", "IzCAutoConsumables_IzC_AC");
IzC_AC:SetScript("OnEvent", function(self, event, ...) IzC_AC:EventHandler(event, ...); end);

-- register events
IzC_AC:RegisterEvent("BAG_UPDATE");
IzC_AC:RegisterEvent("ADDON_LOADED");

IzCAutoConsumables_SavedVars = {}
IzC_Cache = {}
local init = true;
function IzC_AC:UpdateMacros()
    if init then
        init = false;
        for k,v in pairs(MacroNames) do
            if (IzCAutoConsumables_SavedVars[v] ~= true) then
                local macroExists = GetMacroBody(v);
                if not macroExists then
                    IzC_AC:PrintDebug("No macro for "..v.." creating it");
                    CreateMacro(v, "INV_MISC_QUESTIONMARK", " ", nil)
                end
            end
        end
    end


    -- Get a list of the best usable consumables
    local bestConsumable = IzC_AC:CheckBags();

    for k,v in pairs(bestConsumable) do
        IzC_AC:PrintDebug(v.ItemName);

        if (not IzCAutoConsumables_SavedVars[k]) then
            IzC_AC:UpdateMacro(k, v.ItemName);
        end
    end
end

function IzC_AC:UpdateMacro(macroName, itemName)
    local macroExists = GetMacroBody(macroName);
    if not macroExists then
        IzC_AC:PrintDebug("No macro for "..macroName.." creating it");
        CreateMacro(macroName, "INV_MISC_QUESTIONMARK", IzC_AC:GetMacroBody(itemName), false)
    elseif not string.match(macroExists, ("%[%]" .. itemName .. ";")) then
        IzC_AC:PrintDebug("Updating macro for "..macroName);
        EditMacro(macroName, nil, nil, IzC_AC:GetMacroBody(itemName), true, nil);
    end

    -- IzC_AC:PrintDebug(IzC_AC:GetMacroBody(itemName));
end

function IzC_AC:GetMacroBody(itemName)
    return string.gsub(IzCAutoConsumables_BaseMacro, IzCAutoConsumables_ItemPlaceHolder, itemName)
end

function IzC_AC:GetItemFromCache(item)
    -- No item found
    if item == nil then
        return;
    end

    -- Item is not even a consumable
    _,_,_,_,_,itemType,itemSubType=GetItemInfo(item["itemName"])
    if (itemType ~= L["Consumable"] or itemSubType ~= L["Consumable"]) and (itemType ~= L["Trade Goods"] or itemSubType ~= L["Explosives"]) then
        print(itemType, itemSubType);
        IzC_AC:PrintDebug(item["itemName"].." is not a consumable");
        return;
    end

    -- We have it cached, get the cached item and set StackCount
    if (IzC_Cache[item.ItemID] ~= nil) then
        local itemCache = IzC_Cache[item.ItemID];
        itemCache.ItemStackCount = tonumber(item["stackCount"]);
        return itemCache;
    end

    local matchedItem = nil;
    -- Fake it if it's a Healthstone
    if (string.find(item.itemName, L["Healthstone"])) then
        matchedItem = {
            ItemName = item.itemName,
            LevelRequired = 1,
            Amount = 1,
            Consumable = MacroNames.Healthstone,
            ItemStackCount = 1;
        }
    else
        -- Get item info from tooltip
        matchedItem = IzC_AC:GetPossibleMatchFromTooltip(item)
    end

    -- No tooltip match found
    if not matchedItem then
        return;
    end

    -- Set level to 1 if we didnt find anything
    if not matchedItem.LevelRequired then
        matchedItem.LevelRequired = 1
    end

    -- Create object for cache
    local itemCache = {
        ItemName = item.itemName,
        LevelRequired = matchedItem.LevelRequired,
        Amount = matchedItem.Amount,
        Consumable = matchedItem.Consumable,
        ItemStackCount = tonumber(item["stackCount"]);
    }

    -- Save it to cache
    IzC_Cache[item.itemID] = itemCache;

    return itemCache;
end

function IzC_AC:GetFirstAidSkillLevel()
    for i = 1, GetNumSkillLines() do
        local skillName, _, _, skillRank, _, _, skillMaxRank = GetSkillLineInfo(i)
        if (skillName == L["First Aid"]) then
            return skillRank;
        end
    end
    return 0;
end

function IzC_AC:CheckBags()
    local bestConsumables = {};
    for bag=0,NUM_BAG_SLOTS do
        for slot=1,C_Container.GetContainerNumSlots(bag) do
            
            local item = C_Container.GetContainerItemInfo(bag,slot);
            local cachedItem = IzC_AC:GetItemFromCache(item);

            if (cachedItem) then
                IzC_AC:CheckForBestFit(cachedItem, bestConsumables);
            end
        end
    end
    return bestConsumables;
end

function IzC_AC:CheckForBestFit(cachedItem, bestConsumables)
    -- if (cachedItem.ItemName == nil) then
    --     for k,v in pairs(cachedItem) do
    --         print(k..": "..v)
    --     end
    -- end

    -- Item is blacklisted
    if (IzC_Blacklist[cachedItem.ItemName] ~= nil) then
        IzC_AC:PrintDebug(cachedItem.ItemName.." is Blacklisted");
        return;
    end

    -- Check level requirement, can the player even use the item?
    if cachedItem.Consumable == MacroNames.Bandage and cachedItem.LevelRequired > IzC_AC:GetFirstAidSkillLevel() then
        IzC_AC:PrintDebug("Do not allow item with higher skill req than First Aid skill. "..cachedItem.Consumable..": "..cachedItem.LevelRequired);
        return;
    elseif cachedItem.Consumable ~= MacroNames.Bandage and cachedItem.LevelRequired > UnitLevel("Player") then
        IzC_AC:PrintDebug("Do not allow item with higher level req than player. Except Bandage "..cachedItem.Consumable..": "..cachedItem.LevelRequired);
        return;
    end

    -- No raw fish if the setting is toggled
    if IzCAutoConsumables_SavedVars.IzC_IAC_EatRawFish == false and string.find(cachedItem.ItemName, L["Raw"]) ~= nil and cachedItem.ItemName ~= L["Raw Black Truffle"] then
        IzC_AC:PrintDebug("No raw fish: "..cachedItem.ItemName);
        return;
    end

    -- Prioritize Conjured Items
    if IzCAutoConsumables_SavedVars.IzC_IAC_PrioConjured then
        if string.match(cachedItem.ItemName, L['Conjured']) then
            IzC_AC:PrintDebug("Prioritize Conjured food "..cachedItem.ItemName.." For Consumable: "..cachedItem.Consumable)
            bestConsumables[cachedItem.Consumable] = cachedItem;
            return;
        end

    -- Keep conjured if already selected before
        if bestConsumables[cachedItem.Consumable] and string.match(bestConsumables[cachedItem.Consumable].ItemName, L['Conjured']) then
            IzC_AC:PrintDebug("Prioritize already selected Conjured food "..bestConsumables[cachedItem.Consumable].ItemName.." over "..cachedItem.ItemName.." For Consumable: "..cachedItem.Consumable)
            return;
        end
    end

    -- Prioritize Festival Dumplings
    if (IzCAutoConsumables_SavedVars.IzC_IAC_PrioFestivalDumplings) then
        if (string.match(cachedItem.ItemName, L['Festival Dumplings'])) then
            IzC_AC:PrintDebug("Prioritize Festival Dumplings")

            local exitEarly = false;

            if (IzCAutoConsumables_SavedVars.IzC_IAC_PrioConjured == false or not bestConsumables[MacroNames.Food] or (IzCAutoConsumables_SavedVars.IzC_IAC_PrioConjured and bestConsumables[MacroNames.Food] and not string.match(bestConsumables[MacroNames.Food].ItemName, L['Conjured']))) then
                IzC_AC:PrintDebug("Prioritize Festival Dumplings for Food")
                bestConsumables[MacroNames.Food] = cachedItem;
                exitEarly = true;
            end

            if (IzCAutoConsumables_SavedVars.IzC_IAC_PrioConjured == false or not bestConsumables[MacroNames.Drink] or (IzCAutoConsumables_SavedVars.IzC_IAC_PrioConjured and bestConsumables[MacroNames.Drink] and not string.match(bestConsumables[MacroNames.Drink].ItemName, L['Conjured']))) then
                IzC_AC:PrintDebug("Prioritize Festival Dumplings for Food")
                bestConsumables[MacroNames.Drink] = cachedItem;
                exitEarly = true;
            end

            if (exitEarly == true) then
                return;
            end
        end

        -- Keep Festival Dumplings if already selected before
        if bestConsumables[cachedItem.Consumable] and string.match(bestConsumables[cachedItem.Consumable].ItemName, L['Festival Dumplings']) then
            IzC_AC:PrintDebug("Prioritize already selected Festival Dumplings food "..bestConsumables[cachedItem.Consumable].ItemName.." over "..cachedItem.ItemName.." For Consumable: "..cachedItem.Consumable)
            return;
        end
    end

    -- Prioritize Enriched Manna Biscuit
    if (IzCAutoConsumables_SavedVars.IzC_IAC_PrioMannaBiscuit) then
        if (string.match(cachedItem.ItemName, L['Enriched Manna Biscuit'])) then
            IzC_AC:PrintDebug("Prioritize Enriched Manna Biscuit")

            local exitEarly = false;

            if (IzCAutoConsumables_SavedVars.IzC_IAC_PrioConjured == false or not bestConsumables[MacroNames.Food] or (IzCAutoConsumables_SavedVars.IzC_IAC_PrioConjured and bestConsumables[MacroNames.Food] and not string.match(bestConsumables[MacroNames.Food].ItemName, L['Conjured']))) then
                IzC_AC:PrintDebug("Prioritize Enriched Manna Biscuit for Food")
                bestConsumables[MacroNames.Food] = cachedItem;
                exitEarly = true;
            end

            if (IzCAutoConsumables_SavedVars.IzC_IAC_PrioConjured == false or not bestConsumables[MacroNames.Drink] or (IzCAutoConsumables_SavedVars.IzC_IAC_PrioConjured and bestConsumables[MacroNames.Drink] and not string.match(bestConsumables[MacroNames.Drink].ItemName, L['Conjured']))) then
                IzC_AC:PrintDebug("Prioritize Enriched Manna Biscuit for Food")
                bestConsumables[MacroNames.Drink] = cachedItem;
                exitEarly = true;
            end

            if (exitEarly == true) then
                return;
            end
        end

        -- Keep Enriched Manna Biscuit if already selected before
        if bestConsumables[cachedItem.Consumable] and string.match(bestConsumables[cachedItem.Consumable].ItemName, L['Enriched Manna Biscuit']) then
            IzC_AC:PrintDebug("Prioritize already selected Enriched Manna Biscuit food "..bestConsumables[cachedItem.Consumable].ItemName.." over "..cachedItem.ItemName.." For Consumable: "..cachedItem.Consumable)
            return;
        end
    end

    if (not bestConsumables[cachedItem.Consumable]) then
        bestConsumables[cachedItem.Consumable] = cachedItem;
        return;
    end

    if bestConsumables[cachedItem.Consumable].Amount and cachedItem.Amount and bestConsumables[cachedItem.Consumable].Amount < cachedItem.Amount then
        IzC_AC:PrintDebug("Higher amount consumable: "..cachedItem.ItemName.." is better than: "..bestConsumables[cachedItem.Consumable].ItemName);
        bestConsumables[cachedItem.Consumable] = cachedItem;
        return;
    end

    if (not bestConsumables[cachedItem.Consumable].Amount or not cachedItem.Amount) and bestConsumables[cachedItem.Consumable].LevelRequired < cachedItem.LevelRequired then
        IzC_AC:PrintDebug("Higher level consumable: "..cachedItem.ItemName.." is better than: "..bestConsumables[cachedItem.Consumable].ItemName);
        bestConsumables[cachedItem.Consumable] = cachedItem;
        return;
    end

    if bestConsumables[cachedItem.Consumable].ItemStackCount > cachedItem.ItemStackCount and ((bestConsumables[cachedItem.Consumable].Amount and cachedItem.Amount and bestConsumables[cachedItem.Consumable].Amount <= cachedItem.Amount) or (bestConsumables[cachedItem.Consumable].LevelRequired <= cachedItem.LevelRequired)) then
        IzC_AC:PrintDebug("Consumable for: "..cachedItem.Consumable.." is a bigger stack than current best updating it with "..cachedItem.ItemName)
        bestConsumables[cachedItem.Consumable] = cachedItem;
        return;
    end
end

function IzC_AC:GetPossibleMatchFromTooltip(item)
    local possibleMatch = {};
    possibleMatch.ItemName = item["itemName"];

    hiddenToolTip:ClearLines()
    hiddenToolTip:SetHyperlink(item["hyperlink"])

    for i=1,hiddenToolTip:NumLines() do
        
        local mytext = getglobal("hiddenToolTipTextLeft" .. i)
        local text = nil
        
        if mytext ~= nil then
            text = mytext:GetText()
        end
        
        if text ~= nil then
            if string.match(text, L['Requires Level']) then
                possibleMatch.LevelRequired = tonumber(string.match(text, '%d+'));
            elseif string.match(text, L['Requires First Aid']) then
                possibleMatch.LevelRequired = tonumber(string.match(text, '%d+'));
            end
            
            if string.find(text, L["Must remain seated"]) then
                possibleMatch.Amount = tonumber(string.match(text, '%d+'));
                if (string.find(text, L["become well fed and gain"]) and string.find(text, L["Stamina and Spirit for"])) or string.find(text, L["increases your Stamina by"]) then
                    possibleMatch.Consumable = MacroNames.BuffFood;
                    IzC_AC:PrintDebug("Buff Food: "..item["itemName"])
                    return possibleMatch;
                elseif string.match(text, L['Use: Restores %d+ mana over']) then
                    possibleMatch.Consumable = MacroNames.Drink;
                    IzC_AC:PrintDebug("Drink: "..item["itemName"])
                    return possibleMatch;
                else
                    possibleMatch.Consumable = MacroNames.Food;
                    IzC_AC:PrintDebug("Food: "..item["itemName"])
                    return possibleMatch;
                end
            elseif string.match(text, L['Use: Restores %d+ to %d+ health']) then
                possibleMatch.Amount = tonumber(string.match(text, '%d+'));
                possibleMatch.Consumable = MacroNames.Potion;
                IzC_AC:PrintDebug("Potion: "..item["itemName"])
                return possibleMatch;
            elseif string.match(text, L['Use: Restores %d+ to %d+ mana']) then
                possibleMatch.Amount = tonumber(string.match(text, '%d+'));
                possibleMatch.Consumable = MacroNames.ManaPotion;
                IzC_AC:PrintDebug("Mana Potion: "..item["itemName"])
                return possibleMatch;
            elseif string.match(text, L['Use: Heals %d+ damage over']) then
                possibleMatch.Amount = tonumber(string.match(text, '%d+'));
                possibleMatch.Consumable = MacroNames.Bandage;
                IzC_AC:PrintDebug("Bandage: "..item["itemName"])
                return possibleMatch;
            elseif string.match(text, L['Inflicts %d+ to %d+ Fire damage']) then
                possibleMatch.Amount = tonumber(string.match(text, '%d+'));
                possibleMatch.Consumable = MacroNames.Grenade;
                IzC_AC:PrintDebug("Grenade: "..item["itemName"])
                return possibleMatch;
            end
        end
    end
end

function IzC_AC:PrintDebug(message)
    if IzCAutoConsumables_SavedVars.IzC_IAC_Debug == true then
        DEFAULT_CHAT_FRAME:AddMessage(message);
    end
end

-----------------------
---- Event Handler ----
-----------------------
function IzC_AC:EventHandler(event, arg1, ...)

    if (event == "ADDON_LOADED") then
        if (arg1 == addonName) then

            IzCAutoConsumables_SavedVars = setmetatable(IzCAutoConsumables_SavedVars or {}, { __index = IzCAutoConsumables_Defaults })

            IzC_AC:CheckSettings();

            IzC_Cache = setmetatable(IzC_Cache or {}, { __index = {} })
            IzC_Blacklist = setmetatable(IzC_Blacklist or {}, { __index = {} })
            
            IzCAutoConsumables_TargetTrigger = GetTime() + IzCAutoConsumables_TriggerWaitTime + 4;
            IzC_AC:RegisterOnUpdate()
            IzC_AC:TryUnregisterEvent("ADDON_LOADED");

            IzC_AC:CreateSettings();
            return;
        end
    end

    IzC_AC:PrintDebug(event)

    -- Don't do anything if player is in combat
    if UnitAffectingCombat("player") then
        IzC_AC:TryRegisterEvent("PLAYER_REGEN_ENABLED");
        IzC_AC:TryUnregisterEvent("BAG_UPDATE");

        IzC_AC:PrintDebug("Player is in combat, skipping event");
        return;
    end

    IzC_AC:TryRegisterEvent("BAG_UPDATE");
    IzC_AC:TryUnregisterEvent("PLAYER_REGEN_ENABLED");

    IzCAutoConsumables_TargetTrigger = GetTime() + IzCAutoConsumables_TriggerWaitTime;
    IzC_AC:RegisterOnUpdate()
end

function IzC_AC:CheckSettings()
    if (IzCAutoConsumables_SavedVars[MacroNames.Grenade] == nil) then
        IzCAutoConsumables_SavedVars[MacroNames.Grenade] = IzCAutoConsumables_Defaults[MacroNames.Grenade]
    end
end

function IzC_AC:TryRegisterEvent(event)
    IzC_AC:PrintDebug("Trying to Register Event: "..event)
    if IzC_AC:IsEventRegistered(event) then
        return
    end

    IzC_AC:PrintDebug("Register Event: "..event)
    IzC_AC:RegisterEvent(event);
end

function IzC_AC:TryUnregisterEvent(event)
    IzC_AC:PrintDebug("Trying to Unregister Event: "..event)
    if IzC_AC:IsEventRegistered(event) then
        IzC_AC:PrintDebug("Unregister Event: "..event)
        IzC_AC:UnregisterEvent(event);
    end
end

function IzC_AC:RegisterOnUpdate()
    IzC_AC:PrintDebug("Trying to Register OnUpdate")
    if not IzC_AC:GetScript("OnUpdate") then
        IzC_AC:PrintDebug("Register OnUpdate")
        IzC_AC:SetScript("OnUpdate", function(self, event, ...) IzC_AC:OnUpdate(event, ...); end);
    end
end

function IzC_AC:UnRegisterOnUpdate()
    IzC_AC:PrintDebug("Trying to Unregister OnUpdate")
    if IzC_AC:GetScript("OnUpdate") then
        IzC_AC:PrintDebug("Unregister OnUpdate")
        IzC_AC:SetScript("OnUpdate", nil);
    end
end

----------------------
-- OnUpdate Handler --
----------------------
function IzC_AC:OnUpdate()
    if (IzCAutoConsumables_TargetTrigger > GetTime()) or UnitAffectingCombat("player") then
        return;
    end

    IzC_AC:PrintDebug("OnUpdate runner")
    IzC_AC:UnRegisterOnUpdate();
    
    IzC_AC:UpdateMacros();
end













----------------------
--      Options     --
----------------------
function IzC_AC:CreateSettings()
    local category, layout = Settings.RegisterVerticalLayoutCategory("IzC Auto Consumables")

    local MainCategory, _ = Settings.RegisterVerticalLayoutSubcategory(category, "Prio");
    local MacrosCategory, _ = Settings.RegisterVerticalLayoutSubcategory(category, "Macros");
    local debugCategory, _ = Settings.RegisterVerticalLayoutSubcategory(category, "Debug");

    local function CreateCheckBox(variable, name, tooltip, category, defaultValue)
        local function GetValue()
            return IzCAutoConsumables_SavedVars[variable] or defaultValue
        end

        local function SetValue(value)
            IzC_AC:PrintDebug("Setting "..variable.." changed to: "..tostring(value));
            IzCAutoConsumables_SavedVars[variable] = value;
            IzC_AC:UpdateMacros();
        end

        local setting = Settings.RegisterProxySetting(category, variable, type(false), name, defaultValue, GetValue, SetValue)

        Settings.CreateCheckbox(category, setting, tooltip)
    end

    StaticPopupDialogs.AddRemoveBlacklist = {
        text = "Item Name",
        button1 = OKAY,
        button2 = CANCEL,
        OnAccept = function(self)
            local itemName = self.editBox:GetText()

            if (not itemName or itemName == "") then
                return;
            end

            if (IzC_Blacklist[itemName] == nil) then
                DEFAULT_CHAT_FRAME:AddMessage(itemName.." added to blacklist.");
                IzC_Blacklist[itemName] = true
            else
                DEFAULT_CHAT_FRAME:AddMessage(itemName.." removed from blacklist.");
                IzC_Blacklist[itemName] = nil
            end
        end,
        hasEditBox = 1,
    }

    local function CreateBlacklistListing(itemName)
        local function OnButtonClick()
            DEFAULT_CHAT_FRAME:AddMessage(itemName.." removed from blacklist.");
            IzC_Blacklist[itemName] = nil
        end

        local initializer = CreateSettingsButtonInitializer(itemName, "Remove", OnButtonClick, "Click button to remove the consumable from the ignore list", true);
        layout:AddInitializer(initializer);
    end

    do
        -- Blacklist add/remove button
        do
            local function OnButtonClick()
                StaticPopup_Show("AddRemoveBlacklist")
            end

            local initializer = CreateSettingsButtonInitializer("Ignore Consumable", "Add/Remove", OnButtonClick, "Click button to add or remove a consumable from the ignore list", true);
            layout:AddInitializer(initializer);

            for k,v in pairs(IzC_Blacklist) do
                CreateBlacklistListing(k)
            end
        end

        CreateCheckBox("IzC_IAC_PrioConjured", "Prioritize Conjured Food", "Prioritize using Conjured consumables regardless of their level.", MainCategory, false)
        CreateCheckBox("IzC_IAC_PrioFestivalDumplings", "Prioritize Festival Dumplings", "Prioritize using Festival Dumplings.", MainCategory, false)
        CreateCheckBox("IzC_IAC_PrioMannaBiscuit", "Prioritize Enriched Manna Biscuit", "Prioritize using Enriched Manna Biscuit.", MainCategory, false)
        CreateCheckBox("IzC_IAC_EatRawFish", "Eat raw fish", "Whether or not we should allow eating of raw fish.", MainCategory, false)

        CreateCheckBox(MacroNames.Healthstone, "Disable Healthstone Macro", "Whether or not we should create a macro for Healthstone.", MacrosCategory, false)
        CreateCheckBox(MacroNames.Bandage, "Disable Bandage Macro", "Whether or not we should create a macro for Bandages.", MacrosCategory, false)
        CreateCheckBox(MacroNames.Food, "Disable Food Macro", "Whether or not we should create a macro for Food.", MacrosCategory, false)
        CreateCheckBox(MacroNames.Drink, "Disable Drink Macro", "Whether or not we should create a macro for Drink.", MacrosCategory, false)
        CreateCheckBox(MacroNames.BuffFood, "Disable BuffFood Macro", "Whether or not we should create a macro for BuffFood.", MacrosCategory, false)
        CreateCheckBox(MacroNames.Potion, "Disable Potion Macro", "Whether or not we should create a macro for Potion.", MacrosCategory, false)
        CreateCheckBox(MacroNames.ManaPotion, "Disable Mana Potion Macro", "Whether or not we should create a macro for Mana Potion.", MacrosCategory, false)
        CreateCheckBox(MacroNames.Grenade, "Disable Grenade Macro", "Whether or not we should create a macro for Grenades.", MacrosCategory, false)

        CreateCheckBox("IzC_IAC_Debug", "Debug Mode", "Print debug statements?", debugCategory, false)
    end

    Settings.RegisterAddOnCategory(category)
end

IzCAutoConsumables_Defaults = {
    [MacroNames.Healthstone] = false,
    [MacroNames.Food] = false,
    [MacroNames.Bandage] = false,
    [MacroNames.Drink] = false,
    [MacroNames.BuffFood] = false,
    [MacroNames.Potion] = false,
    [MacroNames.ManaPotion] = false,
    [MacroNames.Grenade] = true,
    ["IzC_IAC_PrioConjured"] = true,
    ["IzC_IAC_PrioFestivalDumplings"] = false,
    ["IzC_IAC_PrioMannaBiscuit"] = false,
    ["IzC_IAC_EatRawFish"] = false,
    ["IzC_IAC_Debug"] = false,
}
