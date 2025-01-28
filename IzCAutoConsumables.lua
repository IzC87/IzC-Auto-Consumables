-- Globals Section
local addonName, L = ...;
local MacroNames = {
    Bandage = "IzCBandage",
    Food = "IzCFood",
    Drink = "IzCDrink",
    BuffFood = "IzCBuffFood",
    Potion = "IzCPotion",
    ManaPotion = "IzCManaPotion",
    Healthstone = "IzCHealthstone"
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
local workerFrame = CreateFrame("Frame", "IzCAutoConsumables_workerFrame");
workerFrame:SetScript("OnEvent", function(self, event, ...) IzCAutoConsumables_EventHandler(event, ...); end);

-- register events
workerFrame:RegisterEvent("BAG_UPDATE");
workerFrame:RegisterEvent("ADDON_LOADED");

IzCAutoConsumables_SavedVars = {}
local init = true;
function IzCAutoConsumables_UpdateMacros()
    if init then
        init = false;
        for k,v in pairs(MacroNames) do
            if (IzCAutoConsumables_SavedVars[v] ~= true) then
                local macroExists = GetMacroBody(v);
                if not macroExists then
                    IzCAutoConsumables_PrintDebug("No macro for "..v.." creating it");
                    CreateMacro(v, "INV_MISC_QUESTIONMARK", " ", nil)
                end
            end
        end
    end


    -- Get a list of the best usable consumables
    local bestConsumable = IzCAutoConsumables_GetBestConsumables();

    for k,v in pairs(bestConsumable) do
        IzCAutoConsumables_PrintDebug(v.ItemName);

        if (not IzCAutoConsumables_SavedVars[k]) then
            IzCAutoConsumables_UpdateMacro(k, v.ItemName);
        end
    end
end

function IzCAutoConsumables_UpdateMacro(macroName, itemName)
    local macroExists = GetMacroBody(macroName);
    if not macroExists then
        IzCAutoConsumables_PrintDebug("No macro for "..macroName.." creating it");
        CreateMacro(macroName, "INV_MISC_QUESTIONMARK", IzCAutoConsumables_GetMacroBody(itemName), false)
    elseif not string.match(macroExists, ("%[%]" .. itemName .. ";")) then
        IzCAutoConsumables_PrintDebug("Updating macro for "..macroName);
        EditMacro(macroName, nil, nil, IzCAutoConsumables_GetMacroBody(itemName), true, nil);
    end

    IzCAutoConsumables_PrintDebug(IzCAutoConsumables_GetMacroBody(itemName));
end

function IzCAutoConsumables_GetMacroBody(itemName)
    return string.gsub(IzCAutoConsumables_BaseMacro, IzCAutoConsumables_ItemPlaceHolder, itemName)
end

function IzCAutoConsumables_GetBestConsumables()
    local bestConsumables = {};
    for bag=0,NUM_BAG_SLOTS do
        for slot=1,C_Container.GetContainerNumSlots(bag) do
            
            local item = C_Container.GetContainerItemInfo(bag,slot)

            if item ~= nil then
                local possibleMatch = IzCAutoConsumables_GetPossibleMatch(item);
                if (possibleMatch == nil) then
                    
                elseif not bestConsumables[possibleMatch.Consumable] then
                    IzCAutoConsumables_PrintDebug("First find for Consumable: "..possibleMatch.Consumable)
                    bestConsumables[possibleMatch.Consumable] = possibleMatch;

                elseif IzCAutoConsumables_SavedVars.PrioConjured and string.match(possibleMatch.ItemName, L['Conjured']) then
                    IzCAutoConsumables_PrintDebug("Prioritize Conjured food "..possibleMatch.ItemName.." For Consumable: "..possibleMatch.Consumable)
                    bestConsumables[possibleMatch.Consumable] = possibleMatch;

                elseif bestConsumables[possibleMatch.Consumable].LevelRequired < possibleMatch.LevelRequired then
                    IzCAutoConsumables_PrintDebug("Higher level food: "..possibleMatch.ItemName.." is better than: "..bestConsumables[possibleMatch.Consumable].ItemName);
                    bestConsumables[possibleMatch.Consumable] = possibleMatch;

                elseif bestConsumables[possibleMatch.Consumable].ItemStackCount > possibleMatch.ItemStackCount and bestConsumables[possibleMatch.Consumable].LevelRequired <= possibleMatch.LevelRequired then
                    IzCAutoConsumables_PrintDebug("Consumable for: "..possibleMatch.Consumable.." is a bigger stack than current best updating it with "..possibleMatch.ItemName)
                    bestConsumables[possibleMatch.Consumable] = possibleMatch;
                end
            end
        end
    end
    return bestConsumables;
end

function IzCAutoConsumables_GetPossibleMatch(item)
    if IzCAutoConsumables_SavedVars.EatRawFish == false and string.find(item["itemName"], L["Raw"]) ~= nil and item["itemName"] ~= L["Raw Black Truffle"] then
        IzCAutoConsumables_PrintDebug("No raw fish: "..item["itemName"]);
        return;
    end
    
    if string.match(item["itemName"], L['Healthstone']) then
        local possibleMatch = {};
        possibleMatch.ItemName = item["itemName"];
        possibleMatch.Consumable = MacroNames.Healthstone;
        IzCAutoConsumables_PrintDebug("Healthstone")
        return possibleMatch;
    end
                        
    _,_,_,_,_,itemType,itemSubType=GetItemInfo(item["itemName"])
    if itemType ~= L["Consumable"] or itemSubType ~= L["Consumable"] then
        IzCAutoConsumables_PrintDebug(item["itemName"].." is not a consumable");
        return;
    end

    local possibleMatch = IzCAutoConsumables_GetPossibleMatchFromTooltip(item)

    if not possibleMatch then
        return;
    end

    if not possibleMatch.LevelRequired then
        possibleMatch.LevelRequired = 1
    end

    if possibleMatch.LevelRequired > UnitLevel("Player") then
        if not possibleMatch.Consumable == MacroNames.Bandage then
            IzCAutoConsumables_PrintDebug("Do not allow item with higher level req than player. Except Bandage "..possibleMatch.Consumable..": "..possibleMatch.LevelRequired);
            return;
        end
        IzCAutoConsumables_PrintDebug("Allow item with higher level req than player because Bandage "..possibleMatch.Consumable..": "..possibleMatch.LevelRequired);
    end

    return possibleMatch;
end

function IzCAutoConsumables_GetPossibleMatchFromTooltip(item)
    local possibleMatch = {};
    possibleMatch.ItemStackCount = tonumber(item["stackCount"]);
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
                if string.find(text, L["become well fed and gain"]) and string.find(text, L["Stamina and Spirit for"]) then
                    possibleMatch.Consumable = MacroNames.BuffFood;
                    IzCAutoConsumables_PrintDebug("Buff Food: "..item["itemName"])
                    return possibleMatch;
                elseif string.match(text, L['Use: Restores %d+ mana over']) then
                    possibleMatch.Consumable = MacroNames.Drink;
                    IzCAutoConsumables_PrintDebug("Drink: "..item["itemName"])
                    return possibleMatch;
                else
                    possibleMatch.Consumable = MacroNames.Food;
                    IzCAutoConsumables_PrintDebug("Food: "..item["itemName"])
                    return possibleMatch;
                end
            elseif string.match(text, L['Use: Restores %d+ to %d+ health']) then
                possibleMatch.Consumable = MacroNames.Potion;
                IzCAutoConsumables_PrintDebug("Potion: "..item["itemName"])
                return possibleMatch;
            elseif string.match(text, L['Use: Restores %d+ to %d+ mana']) then
                possibleMatch.Consumable = MacroNames.ManaPotion;
                IzCAutoConsumables_PrintDebug("Mana Potion: "..item["itemName"])
                return possibleMatch;
            elseif string.match(text, L['Use: Heals %d+ damage over']) then
                possibleMatch.Consumable = MacroNames.Bandage;
                IzCAutoConsumables_PrintDebug("Bandage: "..item["itemName"])
                return possibleMatch;
            end
        end
    end
end

function IzCAutoConsumables_PrintDebug(message)
    if IzCAutoConsumables_SavedVars.Debug == true then
        DEFAULT_CHAT_FRAME:AddMessage(message);
    end
end

-----------------------
---- Event Handler ----
-----------------------
function IzCAutoConsumables_EventHandler(event, arg1, ...)

    if (event == "ADDON_LOADED") then
        if (arg1 == addonName) then

            IzCAutoConsumables_SavedVars = setmetatable(IzCAutoConsumables_SavedVars or {}, { __index = IzCAutoConsumables_Defaults })

            IzCAutoConsumables_TargetTrigger = GetTime() + IzCAutoConsumables_TriggerWaitTime + 4;
            IzCAutoConsumables_RegisterOnUpdate()
            workerFrame:UnregisterEvent("ADDON_LOADED");
            return;
        end
    end

    IzCAutoConsumables_PrintDebug(event)

    -- Don't do anything if player is in combat
    if UnitAffectingCombat("player") then
        IzCAutoConsumables_RegisterEvent("PLAYER_REGEN_ENABLED");
        IzCAutoConsumables_UnregisterEvent("BAG_UPDATE");

        IzCAutoConsumables_PrintDebug("Player is in combat, skipping event");
        return;
    end

    IzCAutoConsumables_RegisterEvent("BAG_UPDATE");
    IzCAutoConsumables_UnregisterEvent("PLAYER_REGEN_ENABLED");

    IzCAutoConsumables_TargetTrigger = GetTime() + IzCAutoConsumables_TriggerWaitTime;
    IzCAutoConsumables_RegisterOnUpdate()
end

function IzCAutoConsumables_RegisterEvent(event)
    IzCAutoConsumables_PrintDebug("Trying to Register Event: "..event)
    if workerFrame:IsEventRegistered(event) then
        return
    end

    IzCAutoConsumables_PrintDebug("Register Event: "..event)
    workerFrame:RegisterEvent(event);
end

function IzCAutoConsumables_UnregisterEvent(event)
    IzCAutoConsumables_PrintDebug("Trying to Unregister Event: "..event)
    if workerFrame:IsEventRegistered(event) then
        IzCAutoConsumables_PrintDebug("Unregister Event: "..event)
        workerFrame:UnregisterEvent(event);
    end
end

function IzCAutoConsumables_RegisterOnUpdate()
    IzCAutoConsumables_PrintDebug("Trying to Register OnUpdate")
    if not workerFrame:GetScript("OnUpdate") then
        IzCAutoConsumables_PrintDebug("Register OnUpdate")
        workerFrame:SetScript("OnUpdate", function(self, event, ...) IzCAutoConsumables_OnUpdate(event, ...); end);
    end
end

function IzCAutoConsumables_UnRegisterOnUpdate()
    IzCAutoConsumables_PrintDebug("Trying to Unregister OnUpdate")
    if workerFrame:GetScript("OnUpdate") then
        IzCAutoConsumables_PrintDebug("Unregister OnUpdate")
        workerFrame:SetScript("OnUpdate", nil);
    end
end

----------------------
-- OnUpdate Handler --
----------------------
function IzCAutoConsumables_OnUpdate()
    if (IzCAutoConsumables_TargetTrigger > GetTime()) or UnitAffectingCombat("player") then
        return;
    end

    IzCAutoConsumables_PrintDebug("OnUpdate runner")
    IzCAutoConsumables_UnRegisterOnUpdate();
    
    IzCAutoConsumables_UpdateMacros();
end













----------------------
--      Options     --
----------------------

local category = Settings.RegisterVerticalLayoutCategory("IzC Auto Consumables")

local function CreateCheckBox(variable, name, tooltip, category, defaultValue)
    local function GetValue()
        return IzCAutoConsumables_SavedVars[variable] or defaultValue
    end

    local function SetValue(value)
        IzCAutoConsumables_PrintDebug("Setting "..variable.." changed to: "..tostring(value))
        IzCAutoConsumables_SavedVars[variable] = value
    end

    local setting = Settings.RegisterProxySetting(category, variable, type(false), name, defaultValue, GetValue, SetValue)

    Settings.CreateCheckbox(category, setting, tooltip)
end

do
    CreateCheckBox("PrioConjured", "Prioritize Conjured Food", "Prioritize using Conjured consumables regardless of their level.", category, false)
    CreateCheckBox("EatRawFish", "Eat raw fish", "Whether or not we should allow eating of raw fish.", category, false)
    
    CreateCheckBox(MacroNames.Healthstone, "Disable Healthstone Macro", "Whether or not we should create a macro for Healthstone.", category, false)
    CreateCheckBox(MacroNames.Bandage, "Disable Bandage Macro", "Whether or not we should create a macro for Bandages.", category, false)
    CreateCheckBox(MacroNames.Food, "Disable Food Macro", "Whether or not we should create a macro for Food.", category, false)
    CreateCheckBox(MacroNames.Drink, "Disable Drink Macro", "Whether or not we should create a macro for Drink.", category, false)
    CreateCheckBox(MacroNames.BuffFood, "Disable BuffFood Macro", "Whether or not we should create a macro for BuffFood.", category, false)
    CreateCheckBox(MacroNames.Potion, "Disable Potion Macro", "Whether or not we should create a macro for Potion.", category, false)
    CreateCheckBox(MacroNames.ManaPotion, "Disable Mana Potion Macro", "Whether or not we should create a macro for Mana Potion.", category, false)

    CreateCheckBox("Debug", "Debug Mode", "Print debug statements?", category, false)
end

Settings.RegisterAddOnCategory(category)

IzCAutoConsumables_Defaults = {
    [MacroNames.Healthstone] = false,
    [MacroNames.Food] = false,
    [MacroNames.Bandage] = false,
    [MacroNames.Drink] = false,
    [MacroNames.BuffFood] = false,
    [MacroNames.Potion] = false,
    [MacroNames.ManaPotion] = false,
    ["PrioConjured"] = true,
    ["EatRawFish"] = false,
    ["Debug"] = false
}
