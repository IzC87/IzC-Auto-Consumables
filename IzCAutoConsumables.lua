-- Globals Section
local IzCAutoConsumables_BandageMacroName = "IzCBandage";
local IzCAutoConsumables_FoodMacroName = "IzCFood";
local IzCAutoConsumables_DrinkMacroName = "IzCDrink";
local IzCAutoConsumables_BuffFoodMacroName = "IzCBuffFood";
local IzCAutoConsumables_PotionMacroName = "IzCPotion";
local IzCAutoConsumables_ManaPotionMacroName = "IzCManaPotion";

local IzCAutoConsumables_TargetTrigger = GetTime();
local IzCAutoConsumables_TriggerWaitTime = 2;

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
workerFrame:RegisterEvent("PLAYER_ENTERING_WORLD");

-- Saved Settings
IzCAutoConsumables_SavedVars = IzCAutoConsumables_SavedVars or {}

function IzCAutoConsumables_UpdateMacros()

    -- Get a list of the best usable consumables
    local bestConsumable = IzCAutoConsumables_GetBestConsumables();

    for k,v in pairs(bestConsumable) do
        IzCAutoConsumables_PrintDebug(v.ItemName);
        IzCAutoConsumables_UpdateMacro(k, v.ItemName);
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

                if IzCAutoConsumables_SavedVars.EatRawFish or (string.find(item["itemName"], "Raw") == nil and item["itemName"] ~= "Raw Black Truffle") then
                        
                    _,_,_,_,_,itemType,itemSubType=GetItemInfo(item["itemName"])
                        
                    if itemType == "Consumable" and itemSubType == "Consumable" then

                        hiddenToolTip:ClearLines()
                        hiddenToolTip:SetHyperlink(item["hyperlink"])

                        local possibleMatch = {}
                        possibleMatch.ItemName = item["itemName"];
                        possibleMatch.ItemStackCount = tonumber(item["stackCount"]);
                        
                        for i=1,hiddenToolTip:NumLines() do
                            
                            local mytext = getglobal("hiddenToolTipTextLeft" .. i)
                            local text = nil
                            
                            if mytext ~= nil then
                                text = mytext:GetText()
                            end
                            
                            if text ~= nil then
                                if string.match(text, 'Requires Level') then
                                    possibleMatch.LevelRequired = tonumber(string.match(text, '%d+'));
                                end
                                
                                if string.match(text, 'Requires First Aid') then
                                    possibleMatch.LevelRequired = tonumber(string.match(text, '%d+'));
                                end

                                if string.find(text, "Must remain seated") then
                                    if string.find(text, "become well fed and gain") and string.find(text, "Stamina and Spirit for") then
                                        possibleMatch.Consumable = IzCAutoConsumables_BuffFoodMacroName;
                                        IzCAutoConsumables_PrintDebug("Buff Food: "..item["itemName"])
                                    elseif string.match(text, 'Use: Restores %d+ mana over') then
                                        possibleMatch.Consumable = IzCAutoConsumables_DrinkMacroName;
                                        IzCAutoConsumables_PrintDebug("Drink: "..item["itemName"])
                                    else
                                        possibleMatch.Consumable = IzCAutoConsumables_FoodMacroName;
                                        IzCAutoConsumables_PrintDebug("Food: "..item["itemName"])
                                    end
                                elseif string.match(text, 'Use: Restores %d+ to %d+ health') then
                                    possibleMatch.Consumable = IzCAutoConsumables_PotionMacroName;
                                    IzCAutoConsumables_PrintDebug("Potion: "..item["itemName"])
                                elseif string.match(text, 'Use: Restores %d+ to %d+ mana') then
                                    possibleMatch.Consumable = IzCAutoConsumables_ManaPotionMacroName;
                                    IzCAutoConsumables_PrintDebug("Potion: "..item["itemName"])
                                elseif string.match(text, 'Use: Heals %d+ damage over') then
                                    possibleMatch.Consumable = IzCAutoConsumables_BandageMacroName;
                                    IzCAutoConsumables_PrintDebug("Bandage: "..item["itemName"])
                                end
                            end
                        end
                        
                        if not possibleMatch.LevelRequired then
                            possibleMatch.LevelRequired = 1
                        end

                        --#region
                        if possibleMatch.LevelRequired and possibleMatch.Consumable and possibleMatch.ItemStackCount then

                            IzCAutoConsumables_PrintDebug("Found possible Consumable: "..possibleMatch.ItemName)

                            if (possibleMatch.LevelRequired <= UnitLevel("Player")) or (possibleMatch.Consumable == IzCAutoConsumables_BandageMacroName) then

                                if not bestConsumables[possibleMatch.Consumable] then

                                    IzCAutoConsumables_PrintDebug("No consumable set for: "..possibleMatch.Consumable.." updating it with "..possibleMatch.ItemName)
                                    bestConsumables[possibleMatch.Consumable] = possibleMatch;

                                elseif IzCAutoConsumables_SavedVars.PrioConjured and string.match(bestConsumables[possibleMatch.Consumable].ItemName, 'Conjured') then
                                    -- Do Nothing
                                    IzCAutoConsumables_PrintDebug("Prioritize Conjured food "..possibleMatch.ItemName.." For Consumable: "..possibleMatch.Consumable)

                                elseif IzCAutoConsumables_SavedVars.PrioConjured and string.match(possibleMatch.ItemName, 'Conjured') then
                                    bestConsumables[possibleMatch.Consumable] = possibleMatch;
                                    IzCAutoConsumables_PrintDebug("2 - Prioritize Conjured food "..possibleMatch.ItemName.." For Consumable: "..possibleMatch.Consumable)

                                elseif bestConsumables[possibleMatch.Consumable].ItemName ~= possibleMatch.ItemName then

                                    if bestConsumables[possibleMatch.Consumable].LevelRequired < possibleMatch.LevelRequired then

                                        IzCAutoConsumables_PrintDebug("Consumable for: "..possibleMatch.Consumable.." is a higher level than current best updating it with "..possibleMatch.ItemName)

                                        bestConsumables[possibleMatch.Consumable] = possibleMatch;
                                    elseif bestConsumables[possibleMatch.Consumable].ItemStackCount > possibleMatch.ItemStackCount and bestConsumables[possibleMatch.Consumable].LevelRequired <= possibleMatch.LevelRequired then

                                        IzCAutoConsumables_PrintDebug("Consumable for: "..possibleMatch.Consumable.." is a bigger stack than current best updating it with "..possibleMatch.ItemName)
                                        bestConsumables[possibleMatch.Consumable] = possibleMatch;

                                    end

                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return bestConsumables;
end

function IzCAutoConsumables_PrintDebug(message)
    if IzCAutoConsumables_SavedVars.Debug == true then
        DEFAULT_CHAT_FRAME:AddMessage(message);
    end
end


-----------------------
---- Event Handler ----
-----------------------
function IzCAutoConsumables_EventHandler(event, ...)
    
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

    IzCAutoConsumables_UpdateMacros();
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

local function OnSettingChanged(setting, value)
    -- This callback will be invoked whenever a setting is modified.
    print("Setting changed:", setting:GetVariable(), value)
end

local category = Settings.RegisterVerticalLayoutCategory("IzC Auto Consumables")

local function CreateCheckBox(variable, name, tooltip, category, defaultValue)
    local function GetValue()
        return IzCAutoConsumables_SavedVars[variable] or defaultValue
    end

    local function SetValue(value)
        IzCAutoConsumables_SavedVars[variable] = value
    end

    local setting = Settings.RegisterProxySetting(category, variable, type(defaultValue), name, defaultValue, GetValue, SetValue)
    setting:SetValueChangedCallback(OnSettingChanged)

    Settings.CreateCheckbox(category, setting, tooltip)
end

do
    CreateCheckBox("PrioConjured", "Prioritize Conjured Food", "Prioritize using Conjured consumables regardless of their level.", category, true)
    CreateCheckBox("EatRawFish", "Eat raw fish", "Whether or not we should allow eating of raw fish or not.", category, false)
    CreateCheckBox("Debug", "Debug Mode", "Print debug statements?", category, false)
end

Settings.RegisterAddOnCategory(category)
