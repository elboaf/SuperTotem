-- SuperTotem.lua
-- Main script for SuperTotem addon with SuperWoW totem detection and range checking

-- SavedVariables table -- populated by WoW before ADDON_LOADED fires.
-- Do NOT read SuperTotemDB here; it is nil at script load time.
-- All initialisation happens in OnEvent -> ADDON_LOADED below.
SuperTotemDB = SuperTotemDB or {};

local settings = {
    DEBUG_MODE = false,
    FOLLOW_ENABLED = false,
    CHAIN_HEAL_ENABLED = false,
    HEALTH_THRESHOLD = 90,
    STRATHOLME_MODE = false,
    ZG_MODE = false,
    HYBRID_MODE = false,
    PET_HEALING_ENABLED = false,
    AUTO_SHIELD_MODE = false,
    SHIELD_TYPE = "Water Shield",
    STRICT_MODE = true,
    EARTH_TOTEM = "Strength of Earth Totem",
    FIRE_TOTEM = "Flametongue Totem",
    AIR_TOTEM = "Windfury Totem",
    WATER_TOTEM = "Mana Spring Totem",
    FOLLOW_TARGET_NAME = nil,
    FOLLOW_TARGET_UNIT = "party1",
    -- Fallback totems: auto-captured when a cooldown totem is selected
    EARTH_TOTEM_FB = nil,
    FIRE_TOTEM_FB  = nil,
    AIR_TOTEM_FB   = nil,
    FALLBACK_ENABLED = true,
};

-- Totems that have a cooldown exceeding their lifetime.
-- When one of these is selected, the previous totem is saved as an implicit fallback.
local COOLDOWN_TOTEM_CD = {
    ["Grounding Totem"]  = 15,
    ["Fire Nova Totem"]  = 15,
    ["Earthbind Totem"]  = 20,
};

local SPELL_ID_LOOKUP = {
    ["Water Shield"] = 51536,
    ["Lightning Shield"] = 10432,
    ["Earth Shield"] = 51526,
    ["Strength of Earth"] = 10441,
    ["Stoneskin"] = 10405,
    ["Flametongue Totem"] = 16388,
    ["Frost Resistance"] = 10476,
    ["Fire Resistance"] = 10535,
    ["Windfury Totem"] = 51367,
    ["Grace of Air"] = 10626,
    ["Nature Resistance"] = 10599,
    ["Windwall Totem"] = 15108,
    ["Mana Spring"] = 10494,
    ["Healing Stream"] = 10461,
};

local SPELL_NAME_BY_ID = {};
for name, id in pairs(SPELL_ID_LOOKUP) do
    SPELL_NAME_BY_ID[id] = name;
end

local superwowEnabled = SUPERWOW_VERSION and true or false
local totemUnitIds = {}
local totemPositions = { air=nil, fire=nil, earth=nil, water=nil }
local RANGE_CHECK_INTERVAL = 2.0
local lastRangeCheckTime = 0
local TOTEM_RANGE = 30

local TOTEM_RANGE_OVERRIDE = {
    ["Searing Totem"] = 20,
    ["Magma Totem"]   = 8,
};

local function HasBuff(buffName, unit)
    if not buffName or not unit then return false end
    local spellId = SPELL_ID_LOOKUP[buffName];
    if not spellId or spellId == 0 then return false end
    for i = 1, 32 do
        local texture, index, buffSpellId = UnitBuff(unit, i);
        if not texture then break end
        if buffSpellId and buffSpellId == spellId then return true end
    end
    return false;
end

local function GetDistance(x1, y1, x2, y2)
    if not x1 or not y1 or not x2 or not y2 then return nil end
    return sqrt((x2-x1)^2 + (y2-y1)^2)
end

local TOTEM_DEFINITIONS = {
    ["Strength of Earth Totem"] = { buff="Strength of Earth", element="earth" },
    ["Stoneskin Totem"]         = { buff="Stoneskin",          element="earth" },
    ["Tremor Totem"]            = { buff=nil,                  element="earth" },
    ["Stoneclaw Totem"]         = { buff=nil,                  element="earth" },
    ["Earthbind Totem"]         = { buff=nil,                  element="earth" },
    ["Flametongue Totem"]       = { buff="Flametongue Totem",  element="fire"  },
    ["Frost Resistance Totem"]  = { buff="Frost Resistance",   element="fire"  },
    ["Fire Nova Totem"]         = { buff=nil,                  element="fire"  },
    ["Searing Totem"]           = { buff=nil,                  element="fire"  },
    ["Magma Totem"]             = { buff=nil,                  element="fire"  },
    ["Windfury Totem"]          = { buff="Windfury Totem",     element="air"   },
    ["Grace of Air Totem"]      = { buff="Grace of Air",       element="air"   },
    ["Nature Resistance Totem"] = { buff="Nature Resistance",  element="air"   },
    ["Grounding Totem"]         = { buff=nil,                  element="air"   },
    ["Sentry Totem"]            = { buff=nil,                  element="air"   },
    ["Windwall Totem"]          = { buff="Windwall Totem",     element="air"   },
    ["Tranquil Air Totem"]      = { buff=nil,                  element="air"   },
    ["Mana Spring Totem"]       = { buff="Mana Spring",        element="water" },
    ["Healing Stream Totem"]    = { buff="Healing Stream",     element="water" },
    ["Fire Resistance Totem"]   = { buff="Fire Resistance",    element="water" },
    ["Poison Cleansing Totem"]  = { buff=nil,                  element="water" },
    ["Disease Cleansing Totem"] = { buff=nil,                  element="water" },
};

-- Reverse lookup: texture path (lowercase) -> totem name
-- Used by the UseAction hook since vanilla has no GetActionType/GetActionInfo
local TOTEM_TEXTURE_TO_NAME = {
    ["interface\\icons\\spell_nature_earthbindtotem"]        = "Strength of Earth Totem",
    ["interface\\icons\\spell_nature_stoneskintotem"]        = "Stoneskin Totem",
    ["interface\\icons\\spell_nature_tremortotem"]           = "Tremor Totem",
    ["interface\\icons\\spell_nature_stoneclawtotem"]        = "Stoneclaw Totem",
    ["interface\\icons\\spell_nature_strengthofearthtotem02"]= "Earthbind Totem",
    ["interface\\icons\\spell_nature_guardianward"]          = "Flametongue Totem",
    ["interface\\icons\\spell_frostresistancetotem_01"]      = "Frost Resistance Totem",
    ["interface\\icons\\spell_fire_sealoffire"]              = "Fire Nova Totem",
    ["interface\\icons\\spell_fire_searingtotem"]            = "Searing Totem",
    ["interface\\icons\\spell_fire_selfdestruct"]            = "Magma Totem",
    ["interface\\icons\\spell_nature_windfury"]              = "Windfury Totem",
    ["interface\\icons\\spell_nature_invisibilitytotem"]     = "Grace of Air Totem",
    ["interface\\icons\\spell_nature_natureresistancetotem"] = "Nature Resistance Totem",
    ["interface\\icons\\spell_nature_groundingtotem"]        = "Grounding Totem",
    ["interface\\icons\\spell_nature_removecurse"]           = "Sentry Totem",
    ["interface\\icons\\spell_nature_earthbind"]             = "Windwall Totem",
    ["interface\\icons\\spell_nature_brilliance"]            = "Tranquil Air Totem",
    ["interface\\icons\\spell_nature_manaregentotem"]        = "Mana Spring Totem",
    ["interface\\icons\\inv_spear_04"]                       = "Healing Stream Totem",
    ["interface\\icons\\spell_fireresistancetotem_01"]       = "Fire Resistance Totem",
    ["interface\\icons\\spell_nature_poisoncleansingtotem"]  = "Poison Cleansing Totem",
    ["interface\\icons\\spell_nature_diseasecleansingtotem"] = "Disease Cleansing Totem",
    ["interface\\icons\\spell_shaman_totemrecall"]           = "Totemic Recall",
};

local SHIELD_DEFINITIONS = {
    ["Water Shield"]     = { spellId=51536 },
    ["Lightning Shield"] = { spellId=10432 },
    ["Earth Shield"]     = { spellId=51526 },
};

local lastTotemRecallTime = 0;
local lastAllTotemsActiveTime = 0;
local lastActiveMessageTime = 0;
local lastTotemCastTime = 0;
local lastFireNovaCastTime = 0;
local FIRE_NOVA_DURATION = 5;
local pendingTotems = {};
local TOTEM_VERIFICATION_TIME = 3;
local TOTEM_CAST_DELAY = 0.35;
local lastShieldCheckTime = 0;
local SHIELD_CHECK_INTERVAL = 1.0;

-- External cast detection: updates totemState when a totem/recall is cast from
-- outside Backpacker (keybind, macro, other addon). Totem drops are validated
-- by SuperWoW GUID confirmation before the bar timer starts. Totemic Recall
-- is gated on its fixed 6 second cooldown.
local function PrintMessage(message)
    if settings.DEBUG_MODE then
        DEFAULT_CHAT_FRAME:AddMessage("SuperTotem: "..message);
    end
end

local lastShieldMessageTime = 0;
local SHIELD_MESSAGE_COOLDOWN = 1;
local function PrintShieldMessage(msg)
    local now = GetTime();
    if now - lastShieldMessageTime >= SHIELD_MESSAGE_COOLDOWN then
        lastShieldMessageTime = now;
        DEFAULT_CHAT_FRAME:AddMessage("SuperTotem: "..msg);
    end
end

local bpInternalCast = false;

local function BPCast(spellName, onSelf)
    bpInternalCast = true;
    CastSpellByName(spellName, onSelf);
    bpInternalCast = false;
end

-- Forward declarations
local OnExternalTotemCast;
local OnExternalTotemicRecall;

local function HandleExternalSpellName(spellName)
    if not spellName then return end
    local cleanName = string.gsub(spellName, "%(.+%)", "");
    cleanName = string.gsub(cleanName, "^%s*(.-)%s*$", "%1");

    -- Exact match first
    local resolvedName = nil;
    if TOTEM_DEFINITIONS[cleanName] then
        resolvedName = cleanName;
    elseif cleanName == "Totemic Recall" then
        -- handled below
    else
        -- Fuzzy fallback: handles Roman numeral rank suffixes (e.g. "Magma Totem IV")
        -- and any subtle whitespace/encoding differences.
        -- Check both directions: table key starts with input, or input starts with table key.
        local lowerClean = string.lower(cleanName);
        for k in pairs(TOTEM_DEFINITIONS) do
            local lowerK = string.lower(k);
            if lowerK == lowerClean or
               string.find(lowerClean, lowerK, 1, true) == 1 or
               string.find(lowerK, lowerClean, 1, true) == 1 then
                resolvedName = k;
                break;
            end
        end
    end

    if resolvedName then
        if settings.DEBUG_MODE then
            PrintMessage("External totem attempt: ");
        end
        OnExternalTotemCast(resolvedName);
    elseif cleanName == "Totemic Recall" then
        if settings.DEBUG_MODE then
            DEFAULT_CHAT_FRAME:AddMessage("SuperTotem: External Totemic Recall attempt", 1, 1, 0);
        end
        OnExternalTotemicRecall();
    elseif settings.DEBUG_MODE then
        -- Non-totem spells are expected and not worth logging
    end
end

-- Hook CastSpellByName: catches /cast macros and direct API calls
local _origCastSpellByName = CastSpellByName;
CastSpellByName = function(spellName, onSelf)
    if not bpInternalCast then HandleExternalSpellName(spellName) end
    _origCastSpellByName(spellName, onSelf);
end

-- Hook CastSpell: catches spellbook casts
-- spellbookTabNum is the book type; BOOKTYPE_SPELL = "spell"
local _origCastSpell = CastSpell;
CastSpell = function(spellId, spellbookTabNum)
    if not bpInternalCast and spellbookTabNum == BOOKTYPE_SPELL then
        local spellName = GetSpellName(spellId, BOOKTYPE_SPELL);
        HandleExternalSpellName(spellName);
    end
    _origCastSpell(spellId, spellbookTabNum);
end

-- Hook UseAction: catches action bar addon clicks (BartenderII, etc.)
-- vanilla has no GetActionType/GetActionInfo so we identify the spell via texture
local _origUseAction = UseAction;
UseAction = function(slotId, checkCursor, onSelf)
    if not bpInternalCast then
        local texture = GetActionTexture(slotId);
        if texture then
            local spellName = TOTEM_TEXTURE_TO_NAME[string.lower(texture)];
            if spellName then
                if settings.DEBUG_MODE then
                    PrintMessage("External totem attempt (UseAction): ");
                end
                if spellName == "Totemic Recall" then
                    OnExternalTotemicRecall();
                else
                    OnExternalTotemCast(spellName);
                end
            end
        end
    end
    _origUseAction(slotId, checkCursor, onSelf);
end

local function InitializeTotemState()
    return {
        { element="air",   spell=settings.AIR_TOTEM,   buff=TOTEM_DEFINITIONS[settings.AIR_TOTEM]   and TOTEM_DEFINITIONS[settings.AIR_TOTEM].buff,   locallyVerified=false, serverVerified=false, localVerifyTime=0, unitId=nil },
        { element="fire",  spell=settings.FIRE_TOTEM,  buff=TOTEM_DEFINITIONS[settings.FIRE_TOTEM]  and TOTEM_DEFINITIONS[settings.FIRE_TOTEM].buff,  locallyVerified=false, serverVerified=false, localVerifyTime=0, unitId=nil },
        { element="earth", spell=settings.EARTH_TOTEM, buff=TOTEM_DEFINITIONS[settings.EARTH_TOTEM] and TOTEM_DEFINITIONS[settings.EARTH_TOTEM].buff, locallyVerified=false, serverVerified=false, localVerifyTime=0, unitId=nil },
        { element="water", spell=settings.WATER_TOTEM, buff=TOTEM_DEFINITIONS[settings.WATER_TOTEM] and TOTEM_DEFINITIONS[settings.WATER_TOTEM].buff, locallyVerified=false, serverVerified=false, localVerifyTime=0, unitId=nil },
    };
end

local totemState = InitializeTotemState();

local swFrame = CreateFrame("Frame")
swFrame:RegisterEvent("UNIT_MODEL_CHANGED")

-- Event snooper: registers all unit events and logs any that fire for our totem unitIds.
-- Only active when DEBUG_MODE is on. Helps identify which events fire on totem death/destroy.
local snoop = CreateFrame("Frame")
local SNOOP_EVENTS = {
    "UNIT_MODEL_CHANGED", "UNIT_HEALTH", "UNIT_DIED", "UNIT_DESTROYED",
    "UNIT_FLAGS", "UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE",
    "UNIT_PORTRAIT_UPDATE", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
};
for _, ev in ipairs(SNOOP_EVENTS) do snoop:RegisterEvent(ev) end
snoop:SetScript("OnEvent", function()
    if not settings.DEBUG_MODE then return end
    if not superwowEnabled then return end
    local unitId = arg1
    if not unitId then return end
    for i, totem in ipairs(totemState) do
        if totem.unitId and totem.unitId == unitId then
            DEFAULT_CHAT_FRAME:AddMessage(
                "SuperTotem [snoop] "..event.." on "..unitId..
                " ("..tostring(UnitName(unitId))..")", 1, 0.8, 0);
        end
    end
end)
swFrame:SetScript("OnEvent", function()
    if not superwowEnabled then return end
    local unitId = arg1
    if not unitId then return end
    local unitName = UnitName(unitId)
    if not unitName then return end
    if string.find(unitName, "Totem") and UnitName(unitId.."owner") == UnitName("player") then
        if settings.DEBUG_MODE then
            DEFAULT_CHAT_FRAME:AddMessage("SuperTotem: SuperWoW detected our totem: "..unitName, 0,1,0)
        end
        local tx, ty = UnitPosition(unitId)
        for i, totem in ipairs(totemState) do
            if totem.locallyVerified and not totem.serverVerified then
                local expectedName = totem.spell
                if expectedName and string.find(unitName, expectedName, 1, true) then
                    totemState[i].serverVerified = true
                    totemState[i].unitId = unitId
                    if tx and ty then totemPositions[totem.element] = { x=tx, y=ty } end
                    if ST_TotemBar_StartTimer then
                        local elCap = string.upper(string.sub(totem.element,1,1))..string.sub(totem.element,2);
                        ST_TotemBar_StartTimer(elCap, totem.spell);
                    end
                    if ST_TotemBar_RefreshIcons then ST_TotemBar_RefreshIcons() end
                    if settings.DEBUG_MODE then
                        DEFAULT_CHAT_FRAME:AddMessage("SuperTotem: Matched "..totem.element.." totem via SuperWoW", 0,1,0)
                    end
                    break
                end
            end
        end
    end
end)

local function GetTotemIndexByElement(element)
    for i, totem in ipairs(totemState) do
        if totem.element == element then return i end
    end
    return nil
end

local function CheckTotemRange()
    if not superwowEnabled then return false end
    local currentTime = GetTime()
    if currentTime - lastRangeCheckTime < RANGE_CHECK_INTERVAL then return false end
    lastRangeCheckTime = currentTime
    local px, py = UnitPosition("player")
    if not px or not py then return false end
    local outOfRange = false
    for element, pos in pairs(totemPositions) do
        if pos and pos.x and pos.y then
            local spellName = nil
            for i, totem in ipairs(totemState) do
                if totem.element == element then spellName = totem.spell; break end
            end
            local effectiveRange = (spellName and TOTEM_RANGE_OVERRIDE[spellName]) or TOTEM_RANGE
            local dist = GetDistance(px, py, pos.x, pos.y)
            if dist and dist > effectiveRange then
                for i, totem in ipairs(totemState) do
                    if totem.element == element then
                        totemState[i].locallyVerified = false
                        totemState[i].serverVerified = false
                        totemState[i].unitId = nil
                        totemPositions[element] = nil
                        outOfRange = true
                        break
                    end
                end
            end
        end
    end
    if outOfRange then
        DEFAULT_CHAT_FRAME:AddMessage("Totems: OUT OF RANGE - redropping", 1, 0.5, 0)
    end
    return outOfRange
end

local lastShieldSetMessageTime = 0;
local SHIELD_SET_MESSAGE_COOLDOWN = 1;
local function PrintShieldSetMessage(msg)
    local now = GetTime();
    if now - lastShieldSetMessageTime >= SHIELD_SET_MESSAGE_COOLDOWN then
        lastShieldSetMessageTime = now;
        DEFAULT_CHAT_FRAME:AddMessage("SuperTotem: "..msg);
    end
end

local function CheckAndRefreshShield()
    if not settings.AUTO_SHIELD_MODE then return false end
    local currentTime = GetTime();
    if currentTime - lastShieldCheckTime < SHIELD_CHECK_INTERVAL then return false end
    lastShieldCheckTime = currentTime;
    local shieldSpell = settings.SHIELD_TYPE;
    if not shieldSpell then return false end

    -- Detect active shield purely by spellId via HasBuff -- no charge counting
    local shieldActive = HasBuff(shieldSpell, "player");
    if not shieldActive then
        BPCast(shieldSpell);
        PrintShieldMessage(shieldSpell.." not active -- casting");
        lastTotemCastTime = currentTime;
        return true;
    end
    return false;
end

local function ToggleSetting(settingName, displayName)
    settings[settingName] = not settings[settingName];
    SuperTotemDB[settingName] = settings[settingName];
    PrintMessage(displayName..(settings[settingName] and " enabled." or " disabled."));
end

local function ResetTotemState()
    for i, totem in ipairs(totemState) do
        totemState[i].locallyVerified = false;
        totemState[i].serverVerified  = false;
        totemState[i].localVerifyTime = 0;
        totemState[i].unitId = nil;
    end
    totemPositions = { air=nil, fire=nil, earth=nil, water=nil }
    lastAllTotemsActiveTime = 0;
    PrintMessage("Totem state reset.");
end

local function ResetWaterTotemState()
    for i, totem in ipairs(totemState) do
        if totem.element == "water" then
            totemState[i].locallyVerified = false;
            totemState[i].serverVerified  = false;
            totemState[i].localVerifyTime = 0;
            totemState[i].unitId = nil;
            totemPositions.water = nil;
            break;
        end
    end
    lastAllTotemsActiveTime = 0;
    PrintMessage("Water totem state reset.");
end

local function DropTotems()
    local currentTime = GetTime();
    if superwowEnabled and CheckTotemRange() then lastAllTotemsActiveTime = 0 end
    if CheckAndRefreshShield() then return end
    if currentTime - lastTotemCastTime < TOTEM_CAST_DELAY then return end

    local function IsOnCooldown(spellName)
        local start, duration = GetSpellCooldown(spellName);
        if not start or not duration then return false end
        return duration > 0 and (start + duration) > currentTime;
    end

    local function GetFallback(element)
        if element == "air"   then return settings.AIR_TOTEM_FB   end
        if element == "fire"  then return settings.FIRE_TOTEM_FB  end
        if element == "earth" then return settings.EARTH_TOTEM_FB end
        return nil;
    end

    for i, totem in ipairs(totemState) do
        local configuredSpell;
        if totem.element == "air" then
            configuredSpell = settings.AIR_TOTEM;
        elseif totem.element == "fire" then
            configuredSpell = settings.FIRE_TOTEM;
        elseif totem.element == "earth" then
            configuredSpell = settings.EARTH_TOTEM;
        elseif totem.element == "water" then
            if settings.STRATHOLME_MODE then configuredSpell = "Disease Cleansing Totem"
            elseif settings.ZG_MODE then     configuredSpell = "Poison Cleansing Totem"
            else                             configuredSpell = settings.WATER_TOTEM end
        end

        -- In strict mode, a verified totem that isn't the configured spell gets
        -- reset so PHASE 2 recasts it. Exception: if the slot is running the
        -- fallback because the primary is on cooldown, leave it alone.
        if totem.locallyVerified and totem.spell ~= configuredSpell then
            local fb = settings.FALLBACK_ENABLED and GetFallback(totem.element);
            local runningFallback = fb and totem.spell == fb and configuredSpell and IsOnCooldown(configuredSpell);
            if settings.STRICT_MODE and not runningFallback then
                PrintMessage("Strict mode: replacing "..tostring(totem.spell).." with "..tostring(configuredSpell));
                totemState[i].locallyVerified = false;
                totemState[i].serverVerified  = false;
                totemState[i].localVerifyTime = 0;
                totemState[i].unitId          = nil;
                totemPositions[totem.element] = nil;
                totemState[i].spell = configuredSpell;
                totemState[i].buff  = configuredSpell and TOTEM_DEFINITIONS[configuredSpell] and TOTEM_DEFINITIONS[configuredSpell].buff;
            end
            -- non-strict: leave totem.spell as-is, PHASE 2 will skip it (locallyVerified=true)
        elseif not totem.locallyVerified then
            -- Slot is empty/unverified - update to configured spell unless the primary
            -- is on cooldown and we'll be dropping the fallback instead.
            local fb = settings.FALLBACK_ENABLED and GetFallback(totem.element);
            local willUseFallback = fb and configuredSpell and IsOnCooldown(configuredSpell);
            if not willUseFallback then
                totemState[i].spell = configuredSpell;
                totemState[i].buff  = configuredSpell and TOTEM_DEFINITIONS[configuredSpell] and TOTEM_DEFINITIONS[configuredSpell].buff;
            end
        end
    end

    if settings.AUTO_SHIELD_MODE and not HasBuff(settings.SHIELD_TYPE, 'player') then
        BPCast(settings.SHIELD_TYPE);
        PrintMessage("Casting "..settings.SHIELD_TYPE..".");
        lastTotemCastTime = currentTime;
        return;
    end

    local cleansingTotemSpell = nil;
    if settings.STRATHOLME_MODE then cleansingTotemSpell = "Disease Cleansing Totem"
    elseif settings.ZG_MODE then      cleansingTotemSpell = "Poison Cleansing Totem" end

    if cleansingTotemSpell and UnitAffectingCombat("player") then
        local otherTotemsActive = true;
        for i, totem in ipairs(totemState) do
            if totem.element ~= "water" and not totem.serverVerified then
                otherTotemsActive = false; break;
            end
        end
        if otherTotemsActive then
            for i, totem in ipairs(totemState) do
                if totem.element == "water" then
                    totemState[i].locallyVerified = false; totemState[i].serverVerified = false;
                    totemState[i].localVerifyTime = 0;    totemState[i].unitId = nil;
                    totemPositions.water = nil;
                    PrintMessage("COMBAT: Preparing "..cleansingTotemSpell.." for mass dispel.");
                    break;
                end
            end
        end
    end

    -- PHASE 1: expired totem check
    local hadExpiredTotems = false;
    if superwowEnabled then
        for i, totem in ipairs(totemState) do
            if totem.unitId then
                if not UnitExists(totem.unitId) then
                    PrintMessage(totem.element.." totem expired/destroyed");
                    totemState[i].serverVerified = false; totemState[i].locallyVerified = false;
                    totemState[i].unitId = nil; totemPositions[totem.element] = nil;
                    hadExpiredTotems = true;
                else
                    if UnitName(totem.unitId.."owner") ~= UnitName("player") then
                        PrintMessage(totem.element.." totem no longer belongs to us");
                        totemState[i].serverVerified = false; totemState[i].locallyVerified = false;
                        totemState[i].unitId = nil; totemPositions[totem.element] = nil;
                        hadExpiredTotems = true;
                    end
                end
            elseif totem.locallyVerified and not totem.unitId then
                PrintMessage(totem.element.." locallyVerified but no unitId - resetting");
                totemState[i].serverVerified = false; totemState[i].locallyVerified = false;
                totemPositions[totem.element] = nil;
                hadExpiredTotems = true;
            end
        end
    else
        for i, totem in ipairs(totemState) do
            if totem.locallyVerified and totem.serverVerified then
                if totem.buff and not HasBuff(totem.buff, 'player') then
                    PrintMessage(totem.buff.." has expired - resetting.");
                    totemState[i].locallyVerified = false; totemState[i].serverVerified = false;
                    totemState[i].localVerifyTime = 0;
                    hadExpiredTotems = true;
                end
            end
        end
    end

    if hadExpiredTotems and lastAllTotemsActiveTime > 0 then
        PrintMessage("Expired totems detected - resetting recall cooldown.");
        lastAllTotemsActiveTime = 0;
    end

    -- PHASE 2: drop missing totems
    for i, totem in ipairs(totemState) do
        local isCleansingTotem = false
        if settings.STRATHOLME_MODE and totem.element == "water" and totem.spell == "Disease Cleansing Totem" then isCleansingTotem = true
        elseif settings.ZG_MODE and totem.element == "water" and totem.spell == "Poison Cleansing Totem" then isCleansingTotem = true end

        if isCleansingTotem then
            BPCast(totem.spell);
            if ST_TotemBar_StartTimer then
                local el = string.upper(string.sub(totem.element,1,1))..string.sub(totem.element,2);
                ST_TotemBar_StartTimer(el, totem.spell);
            end
            PrintMessage("Casting "..totem.spell.." (forced recast for cleanse pulse).");
            totemState[i].locallyVerified = true; totemState[i].localVerifyTime = currentTime;
            totemState[i].unitId = nil; totemPositions.water = nil;
            lastTotemCastTime = currentTime; return;
        elseif not totem.locallyVerified then
            if not totem.spell or totem.spell == "" then
                totemState[i].locallyVerified = true; totemState[i].serverVerified = true;
                PrintMessage("Skipping "..totem.element.." totem (disabled)");
            elseif IsOnCooldown(totem.spell) then
                local fb = settings.FALLBACK_ENABLED and GetFallback(totem.element);
                if fb and not IsOnCooldown(fb) then
                    -- Primary is on cooldown; drop fallback instead
                    BPCast(fb);
                    if ST_TotemBar_StartTimer then
                        local el = string.upper(string.sub(totem.element,1,1))..string.sub(totem.element,2);
                        ST_TotemBar_StartTimer(el, fb);
                    end
                    PrintMessage("Primary "..totem.spell.." on cooldown, casting fallback "..fb..".");
                    totemState[i].spell = fb;
                    totemState[i].buff  = TOTEM_DEFINITIONS[fb] and TOTEM_DEFINITIONS[fb].buff;
                    totemState[i].locallyVerified = true; totemState[i].localVerifyTime = currentTime;
                    totemState[i].unitId = nil; totemPositions[totem.element] = nil;
                    lastTotemCastTime = currentTime; return;
                else
                    -- No fallback or fallback also on cooldown: leave unverified, continue to next slot
                    PrintMessage("Skipping "..totem.spell.." (on cooldown, no fallback ready)");
                end
            else
                BPCast(totem.spell);
                if ST_TotemBar_StartTimer then
                    local el = string.upper(string.sub(totem.element,1,1))..string.sub(totem.element,2);
                    ST_TotemBar_StartTimer(el, totem.spell);
                end
                PrintMessage("Casting "..totem.spell..".");
                totemState[i].locallyVerified = true; totemState[i].localVerifyTime = currentTime;
                totemState[i].unitId = nil; totemPositions[totem.element] = nil;
                lastTotemCastTime = currentTime; return;
            end
        end
    end

    local allLocallyVerified = true;
    for i, totem in ipairs(totemState) do
        if not totem.locallyVerified then allLocallyVerified = false; break end
    end
    if allLocallyVerified and lastAllTotemsActiveTime == 0 then
        PrintMessage("All totems locally verified. Waiting for confirmation...");
    end

    -- PHASE 3: verify totems
    local allServerVerified = true;
    local needsFastDropRestart = false;

    if superwowEnabled then
        for i, totem in ipairs(totemState) do
            if totem.locallyVerified and not totem.serverVerified then
                if totem.unitId then
                    if UnitExists(totem.unitId) and UnitName(totem.unitId.."owner") == UnitName("player") then
                        PrintMessage(totem.element.." totem confirmed via SuperWoW")
                        totemState[i].serverVerified = true
                    else
                        PrintMessage(totem.element.." unitId invalid - resetting")
                        totemState[i].unitId = nil; totemState[i].serverVerified = false;
                        totemState[i].locallyVerified = false; totemState[i].localVerifyTime = 0;
                        totemPositions[totem.element] = nil;
                        allServerVerified = false; needsFastDropRestart = true;
                    end
                else
                    local t = currentTime - totem.localVerifyTime;
                    if t > TOTEM_VERIFICATION_TIME then
                        PrintMessage(totem.element.." totem missing after "..string.format("%.1f",t).."s - resetting.");
                        totemState[i].locallyVerified = false; totemState[i].serverVerified = false;
                        totemState[i].localVerifyTime = 0;    totemState[i].unitId = nil;
                        totemPositions[totem.element] = nil;
                        allServerVerified = false; needsFastDropRestart = true;
                    else
                        PrintMessage(totem.element.." waiting for SuperWoW ("..string.format("%.1f",TOTEM_VERIFICATION_TIME-t).."s)");
                        allServerVerified = false;
                    end
                end
            end
            if not totem.serverVerified then allServerVerified = false end
        end
    else
        for i, totem in ipairs(totemState) do
            if totem.locallyVerified and not totem.serverVerified then
                if totem.buff then
                    if HasBuff(totem.buff, 'player') then
                        PrintMessage(totem.buff.." confirmed active.");
                        totemState[i].serverVerified = true;
                    else
                        local t = currentTime - totem.localVerifyTime;
                        if t > TOTEM_VERIFICATION_TIME then
                            PrintMessage(totem.buff.." missing after "..string.format("%.1f",t).."s - resetting.");
                            totemState[i].locallyVerified = false; totemState[i].serverVerified = false;
                            totemState[i].localVerifyTime = 0;
                            allServerVerified = false; needsFastDropRestart = true;
                        else
                            PrintMessage(totem.buff.." not yet confirmed ("..string.format("%.1f",TOTEM_VERIFICATION_TIME-t).."s)");
                            allServerVerified = false;
                        end
                    end
                else
                    local t = currentTime - totem.localVerifyTime;
                    local resetInterval = 1.0;
                    if totem.spell == "Tremor Totem" or totem.spell == "Poison Cleansing Totem" or totem.spell == "Disease Cleansing Totem" then
                        resetInterval = 0.5;
                    end
                    if t > resetInterval then
                        PrintMessage(totem.spell.." assumed expired - resetting.");
                        totemState[i].locallyVerified = false; totemState[i].serverVerified = false;
                        totemState[i].localVerifyTime = 0;
                        allServerVerified = false; needsFastDropRestart = true;
                    else
                        PrintMessage(totem.spell.." waiting ("..string.format("%.1f",resetInterval-t).."s)");
                        allServerVerified = false;
                    end
                end
            end
            if not totem.serverVerified then allServerVerified = false end
        end
    end

    -- PHASE 4: all verified, nothing left to do
    if allServerVerified then
        PrintMessage("All totems are active.");
        if lastAllTotemsActiveTime == 0 then
            lastAllTotemsActiveTime = currentTime;
            if currentTime - lastActiveMessageTime >= 1.0 then
                lastActiveMessageTime = currentTime;
                DEFAULT_CHAT_FRAME:AddMessage("Totems: ACTIVE", 1, 0, 0);
            end
        end
    else
        lastAllTotemsActiveTime = 0;
    end
end

-- HEALING
local function ExecuteQuickHeal()
    if QuickHeal then QuickHeal() else RunMacroText("/qh") end
end
local function ExecuteQuickChainHeal()
    if QuickChainHeal then QuickChainHeal() else RunMacroText("/qh chainheal") end
end
local function SortByHealth(a, b)
    return (UnitHealth(a)/UnitHealthMax(a)) < (UnitHealth(b)/UnitHealthMax(b))
end

local function HealPartyMembers()
    local lowHealthMembers = {};
    local function CheckHealth(unit)
        if UnitExists(unit) and not UnitIsDeadOrGhost(unit) and UnitIsConnected(unit) then
            local hp = (UnitHealth(unit)/UnitHealthMax(unit))*100;
            if hp < settings.HEALTH_THRESHOLD then table.insert(lowHealthMembers, unit) end
        end
    end
    CheckHealth("player");
    local numRaid = GetNumRaidMembers();
    if numRaid > 0 then
        for i=1,numRaid do CheckHealth("raid"..i) end
    else
        for i=1,GetNumPartyMembers() do CheckHealth("party"..i) end
    end
    if settings.PET_HEALING_ENABLED then
        if UnitExists("pet") and not UnitIsDeadOrGhost("pet") then
            if (UnitHealth("pet")/UnitHealthMax("pet"))*100 < settings.HEALTH_THRESHOLD then
                table.insert(lowHealthMembers, "pet")
            end
        end
        if numRaid > 0 then
            for i=1,numRaid do
                local pu = "raidpet"..i;
                if UnitExists(pu) and not UnitIsDeadOrGhost(pu) then
                    if (UnitHealth(pu)/UnitHealthMax(pu))*100 < settings.HEALTH_THRESHOLD then
                        table.insert(lowHealthMembers, pu)
                    end
                end
            end
        else
            for i=1,GetNumPartyMembers() do
                local pu = "partypet"..i;
                if UnitExists(pu) and not UnitIsDeadOrGhost(pu) then
                    if (UnitHealth(pu)/UnitHealthMax(pu))*100 < settings.HEALTH_THRESHOLD then
                        table.insert(lowHealthMembers, pu)
                    end
                end
            end
        end
    end
    table.sort(lowHealthMembers, SortByHealth);
    local n = 0; for _ in pairs(lowHealthMembers) do n=n+1 end
    if n >= 2 and settings.CHAIN_HEAL_ENABLED then
        ExecuteQuickChainHeal()
    elseif n >= 1 then
        ExecuteQuickHeal()
    else
        if settings.FOLLOW_ENABLED then
            if settings.FOLLOW_TARGET_NAME then
                FollowByName(settings.FOLLOW_TARGET_NAME, true)
            elseif GetNumPartyMembers() > 0 then
                FollowUnit("party1")
            end
        end
        if settings.HYBRID_MODE then
            local followTarget = nil;
            if settings.FOLLOW_TARGET_NAME then
                local nr = GetNumRaidMembers();
                if nr > 0 then
                    for i=1,nr do
                        if UnitExists("raid"..i) and UnitName("raid"..i)==settings.FOLLOW_TARGET_NAME then followTarget="raid"..i; break end
                    end
                else
                    for i=1,GetNumPartyMembers() do
                        if UnitExists("party"..i) and UnitName("party"..i)==settings.FOLLOW_TARGET_NAME then followTarget="party"..i; break end
                    end
                end
            else
                followTarget = "party1"
            end
            if followTarget and UnitExists(followTarget) and not UnitIsDeadOrGhost(followTarget) and UnitIsConnected(followTarget) then
                if UnitName(followTarget.."target") then
                    AssistUnit(followTarget);
                    BPCast("Chain Lightning");
                    BPCast("Fire Nova Totem");
                    if ST_TotemBar_StartTimer then ST_TotemBar_StartTimer("Fire","Fire Nova Totem") end
                    lastFireNovaCastTime = GetTime();
                    BPCast("Lightning Bolt");
                else
                    FollowUnit(followTarget)
                end
            end
        end
    end
end

-- TOTEM SETTERS
local function SetEarthTotem(totemName, displayName)
    if not totemName or totemName == "" then
        settings.EARTH_TOTEM = nil; SuperTotemDB.EARTH_TOTEM = "none";
        settings.EARTH_TOTEM_FB = nil; SuperTotemDB.EARTH_TOTEM_FB = "none";
        for i,totem in ipairs(totemState) do
            if totem.element=="earth" then
                totemState[i].spell=nil; totemState[i].locallyVerified=false;
                totemState[i].serverVerified=false; totemState[i].localVerifyTime=0;
                totemState[i].unitId=nil; totemPositions.earth=nil; break;
            end
        end
        lastAllTotemsActiveTime=0;
        PrintMessage("Earth totem disabled.");
        if ST_TotemBar_RefreshIcons then ST_TotemBar_RefreshIcons() end
    elseif TOTEM_DEFINITIONS[totemName] then
        -- If switching to a cooldown totem, save the previous totem as fallback.
        -- If switching to a normal totem, clear any fallback.
        if COOLDOWN_TOTEM_CD[totemName] then
            if settings.EARTH_TOTEM and not COOLDOWN_TOTEM_CD[settings.EARTH_TOTEM] then
                settings.EARTH_TOTEM_FB = settings.EARTH_TOTEM;
                SuperTotemDB.EARTH_TOTEM_FB = settings.EARTH_TOTEM_FB;
            end
        else
            settings.EARTH_TOTEM_FB = nil; SuperTotemDB.EARTH_TOTEM_FB = "none";
        end
        settings.EARTH_TOTEM = totemName; SuperTotemDB.EARTH_TOTEM = totemName;
        for i,totem in ipairs(totemState) do
            if totem.element=="earth" then
                if totem.spell ~= totemName then
                    totemState[i].spell=totemName;
                    totemState[i].locallyVerified=false; totemState[i].serverVerified=false;
                    totemState[i].localVerifyTime=0; totemState[i].unitId=nil; totemPositions.earth=nil;
                    lastAllTotemsActiveTime=0;
                end
                break;
            end
        end
        PrintMessage("Earth totem set to "..displayName.."."); 
        if ST_TotemBar_RefreshIcons then ST_TotemBar_RefreshIcons() end
    else
        PrintMessage("Unknown earth totem: ");
    end
end

local function SetFireTotem(totemName, displayName)
    if not totemName or totemName == "" then
        settings.FIRE_TOTEM = nil; SuperTotemDB.FIRE_TOTEM = "none";
        settings.FIRE_TOTEM_FB = nil; SuperTotemDB.FIRE_TOTEM_FB = "none";
        for i,totem in ipairs(totemState) do
            if totem.element=="fire" then
                totemState[i].spell=nil; totemState[i].locallyVerified=false;
                totemState[i].serverVerified=false; totemState[i].localVerifyTime=0;
                totemState[i].unitId=nil; totemPositions.fire=nil; break;
            end
        end
        lastAllTotemsActiveTime=0;
        PrintMessage("Fire totem disabled.");
        if ST_TotemBar_RefreshIcons then ST_TotemBar_RefreshIcons() end
    elseif TOTEM_DEFINITIONS[totemName] then
        if COOLDOWN_TOTEM_CD[totemName] then
            if settings.FIRE_TOTEM and not COOLDOWN_TOTEM_CD[settings.FIRE_TOTEM] then
                settings.FIRE_TOTEM_FB = settings.FIRE_TOTEM;
                SuperTotemDB.FIRE_TOTEM_FB = settings.FIRE_TOTEM_FB;
            end
        else
            settings.FIRE_TOTEM_FB = nil; SuperTotemDB.FIRE_TOTEM_FB = "none";
        end
        settings.FIRE_TOTEM = totemName; SuperTotemDB.FIRE_TOTEM = totemName;
        for i,totem in ipairs(totemState) do
            if totem.element=="fire" then
                if totem.spell ~= totemName then
                    totemState[i].spell=totemName;
                    totemState[i].locallyVerified=false; totemState[i].serverVerified=false;
                    totemState[i].localVerifyTime=0; totemState[i].unitId=nil; totemPositions.fire=nil;
                    lastAllTotemsActiveTime=0;
                end
                break;
            end
        end
        PrintMessage("Fire totem set to "..displayName.."."); 
        if ST_TotemBar_RefreshIcons then ST_TotemBar_RefreshIcons() end
        if ST_TotemBar_RefreshFireSlider then ST_TotemBar_RefreshFireSlider() end
    else
        PrintMessage("Unknown fire totem: ");
    end
end

local function SetAirTotem(totemName, displayName)
    if not totemName or totemName == "" then
        settings.AIR_TOTEM = nil; SuperTotemDB.AIR_TOTEM = "none";
        settings.AIR_TOTEM_FB = nil; SuperTotemDB.AIR_TOTEM_FB = "none";
        for i,totem in ipairs(totemState) do
            if totem.element=="air" then
                totemState[i].spell=nil; totemState[i].locallyVerified=false;
                totemState[i].serverVerified=false; totemState[i].localVerifyTime=0;
                totemState[i].unitId=nil; totemPositions.air=nil; break;
            end
        end
        lastAllTotemsActiveTime=0;
        PrintMessage("Air totem disabled.");
        if ST_TotemBar_RefreshIcons then ST_TotemBar_RefreshIcons() end
    elseif TOTEM_DEFINITIONS[totemName] then
        if COOLDOWN_TOTEM_CD[totemName] then
            if settings.AIR_TOTEM and not COOLDOWN_TOTEM_CD[settings.AIR_TOTEM] then
                settings.AIR_TOTEM_FB = settings.AIR_TOTEM;
                SuperTotemDB.AIR_TOTEM_FB = settings.AIR_TOTEM_FB;
            end
        else
            settings.AIR_TOTEM_FB = nil; SuperTotemDB.AIR_TOTEM_FB = "none";
        end
        settings.AIR_TOTEM = totemName; SuperTotemDB.AIR_TOTEM = totemName;
        for i,totem in ipairs(totemState) do
            if totem.element=="air" then
                if totem.spell ~= totemName then
                    totemState[i].spell=totemName;
                    totemState[i].locallyVerified=false; totemState[i].serverVerified=false;
                    totemState[i].localVerifyTime=0; totemState[i].unitId=nil; totemPositions.air=nil;
                    lastAllTotemsActiveTime=0;
                end
                break;
            end
        end
        PrintMessage("Air totem set to "..displayName.."."); 
        if ST_TotemBar_RefreshIcons then ST_TotemBar_RefreshIcons() end
    else
        PrintMessage("Unknown air totem: ");
    end
end

local function SetWaterTotem(totemName, displayName)
    if not totemName or totemName == "" then
        settings.WATER_TOTEM = nil; SuperTotemDB.WATER_TOTEM = "none";
        for i,totem in ipairs(totemState) do
            if totem.element=="water" then
                totemState[i].spell=nil; totemState[i].locallyVerified=false;
                totemState[i].serverVerified=false; totemState[i].localVerifyTime=0;
                totemState[i].unitId=nil; totemPositions.water=nil; break;
            end
        end
        lastAllTotemsActiveTime=0;
        PrintMessage("Water totem disabled.");
        if ST_TotemBar_RefreshIcons then ST_TotemBar_RefreshIcons() end
    elseif TOTEM_DEFINITIONS[totemName] then
        settings.WATER_TOTEM = totemName; SuperTotemDB.WATER_TOTEM = totemName;
        for i,totem in ipairs(totemState) do
            if totem.element=="water" then
                if totem.spell ~= totemName then
                    totemState[i].spell=totemName;
                    totemState[i].locallyVerified=false; totemState[i].serverVerified=false;
                    totemState[i].localVerifyTime=0; totemState[i].unitId=nil; totemPositions.water=nil;
                    lastAllTotemsActiveTime=0;
                end
                break;
            end
        end
        PrintMessage("Water totem set to "..displayName.."."); 
        if ST_TotemBar_RefreshIcons then ST_TotemBar_RefreshIcons() end
    else
        PrintMessage("Unknown water totem: ");
    end
end

-- MODE TOGGLES
local function ToggleAntiDiseaseMode()
    if settings.ZG_MODE then
        settings.ZG_MODE=false; SuperTotemDB.ZG_MODE=false;
        PrintMessage("Anti-Poison mode disabled.");
    end
    ToggleSetting("STRATHOLME_MODE","Anti-Disease mode");
    ResetWaterTotemState();
    if ST_TotemBar_UpdateMode then ST_TotemBar_UpdateMode() end
end

local function ToggleAntiPoisonMode()
    if settings.STRATHOLME_MODE then
        settings.STRATHOLME_MODE=false; SuperTotemDB.STRATHOLME_MODE=false;
        PrintMessage("Anti-Disease mode disabled.");
    end
    ToggleSetting("ZG_MODE","Anti-Poison mode");
    ResetWaterTotemState();
    if ST_TotemBar_UpdateMode then ST_TotemBar_UpdateMode() end
end

local function ToggleHybridMode()
    ToggleSetting("HYBRID_MODE","Hybrid mode");
    if settings.HYBRID_MODE then
        settings.HEALTH_THRESHOLD=80; SuperTotemDB.HEALTH_THRESHOLD=80;
        PrintMessage("Healing threshold set to 80% for hybrid mode.");
    else
        settings.HEALTH_THRESHOLD=90; SuperTotemDB.HEALTH_THRESHOLD=90;
        PrintMessage("Healing threshold reset to 90%.");
    end
end

local function SetTotemCastDelay(delay)
    delay = tonumber(delay);
    if delay and delay >= 0 then
        TOTEM_CAST_DELAY = delay;
        PrintMessage("Totem cast delay set to "..delay.." seconds."); 
    else
        PrintMessage("Invalid delay.");
    end
end

local function TogglePetHealing()    ToggleSetting("PET_HEALING_ENABLED","Pet healing mode") end
local function ToggleAutoShieldMode()
    ToggleSetting("AUTO_SHIELD_MODE","Auto Shield Cast");
end

local function SetWaterShield()
    settings.SHIELD_TYPE="Water Shield"; SuperTotemDB.SHIELD_TYPE="Water Shield";
end
local function SetLightningShield()
    settings.SHIELD_TYPE="Lightning Shield"; SuperTotemDB.SHIELD_TYPE="Lightning Shield";
end
local function SetEarthShield()
    settings.SHIELD_TYPE="Earth Shield"; SuperTotemDB.SHIELD_TYPE="Earth Shield";
end

local function ReportTotemsToParty()
    local function Fmt(s)
        if not s or type(s)~="string" then return "Unknown" end
        if string.find(s," Totem$") then return string.sub(s,1,-7) end
        return s
    end
    local air   = settings.AIR_TOTEM   or "Windfury Totem"
    local earth = settings.EARTH_TOTEM or "Strength of Earth Totem"
    local fire  = settings.FIRE_TOTEM  or "Flametongue Totem"
    local water = settings.WATER_TOTEM or "Mana Spring Totem"
    if settings.STRATHOLME_MODE then water="Disease Cleansing Totem"
    elseif settings.ZG_MODE then     water="Poison Cleansing Totem" end
    local list = { Fmt(air), Fmt(fire), Fmt(earth), Fmt(water) }
    local msg = "Current Totems: "..table.concat(list,", ")
    SendChatMessage(msg,"PARTY")
    DEFAULT_CHAT_FRAME:AddMessage("SuperTotem: "..msg)
end

-- DEBUG SLASH COMMANDS
SLASH_STCHECKSUPERWOW1="/stchecksw";
SlashCmdList["STCHECKSUPERWOW"]=function()
    if superwowEnabled then
        DEFAULT_CHAT_FRAME:AddMessage("=== SuperWoW Detected === v"..tostring(SUPERWOW_VERSION));
        for i,totem in ipairs(totemState) do
            local s="Inactive"
            if totem.unitId then s=UnitExists(totem.unitId) and "Active" or "Expired"
            elseif totem.serverVerified then s="Verified"
            elseif totem.locallyVerified then s="Pending" end
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s: %s (Unit: %s)",totem.element,s,totem.unitId or "none"))
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("=== SuperWoW NOT Detected === Using fallback buff detection");
    end
end

SLASH_STTOTEMPOS1="/sttotempos";
SlashCmdList["STTOTEMPOS"]=function()
    DEFAULT_CHAT_FRAME:AddMessage("=== Totem Positions ===");
    local px,py=UnitPosition("player")
    if px and py then DEFAULT_CHAT_FRAME:AddMessage("Player: "..math.floor(px)..","..math.floor(py)) end
    for element,pos in pairs(totemPositions) do
        if pos and pos.x and pos.y then
            local dist=GetDistance(px,py,pos.x,pos.y)
            DEFAULT_CHAT_FRAME:AddMessage(string.format("%s: %d,%d (%.1f yds) - %s",
                element,math.floor(pos.x),math.floor(pos.y),dist or 0,
                (dist and dist>TOTEM_RANGE) and "OUT OF RANGE" or "In range"))
        else
            DEFAULT_CHAT_FRAME:AddMessage(element..": No position data")
        end
    end
end

SLASH_STCHECKBUFFS1="/stcheckbuffs";
SlashCmdList["STCHECKBUFFS"]=function()
    DEFAULT_CHAT_FRAME:AddMessage("=== Buffs ===");
    for i=1,32 do
        local texture,index,spellId=UnitBuff("player",i);
        if not texture then DEFAULT_CHAT_FRAME:AddMessage("Total: "..(i-1)); break end
        DEFAULT_CHAT_FRAME:AddMessage(string.format("#%d: ID=%d Name=%s",i,spellId or 0,SPELL_NAME_BY_ID[spellId] or "Unknown"))
    end
end

-- Public API
SuperTotem = SuperTotem or {};
SuperTotem.API = {
    GetTotem = function(element) return settings[string.upper(element).."_TOTEM"] end,
    SetTotem = function(element, totemName)
        local el=string.lower(element)
        if     el=="earth" then SetEarthTotem(totemName,totemName)
        elseif el=="fire"  then SetFireTotem(totemName,totemName)
        elseif el=="air"   then SetAirTotem(totemName,totemName)
        elseif el=="water" then SetWaterTotem(totemName,totemName)
        end
    end,
};

local function PrintUsage()
    DEFAULT_CHAT_FRAME:AddMessage("SuperTotem commands:");
    DEFAULT_CHAT_FRAME:AddMessage("  /stheal /stbuff /stfirebuff /stdebug");
    DEFAULT_CHAT_FRAME:AddMessage("  /stf (follow) /stl (set follow target) /stchainheal");
    DEFAULT_CHAT_FRAME:AddMessage("  /stantidisease /stantipoison /sthybrid /stdelay /stpets /stauto");
    DEFAULT_CHAT_FRAME:AddMessage("  /stws /stls /stes (shield type)");
    DEFAULT_CHAT_FRAME:AddMessage("  /streport /stmenu");
    DEFAULT_CHAT_FRAME:AddMessage("  EARTH: /stsoe /stss /sttremor /ststoneclaw /stearthbind");
    DEFAULT_CHAT_FRAME:AddMessage("  FIRE:  /stft /stfrr /stfirenova /stsearing /stmagma");
    DEFAULT_CHAT_FRAME:AddMessage("  AIR:   /stwf /stgoa /stnr /stgrounding /stsentry /stwindwall /sttranquil");
    DEFAULT_CHAT_FRAME:AddMessage("  WATER: /stms /sths /stfr /stpoison /stdisease");
end

SLASH_STHEAL1="/stheal"; SlashCmdList["STHEAL"]=HealPartyMembers;

local function DropFireTotem()
    local currentTime = GetTime();
    if currentTime - lastTotemCastTime < TOTEM_CAST_DELAY then return end
    local fireSpell = settings.FIRE_TOTEM;
    if not fireSpell or fireSpell=="" then DEFAULT_CHAT_FRAME:AddMessage("SuperTotem: No fire totem configured."); return end
    if currentTime - lastFireNovaCastTime < FIRE_NOVA_DURATION then return end

    if superwowEnabled then
        local px,py = UnitPosition("player")
        local pos = totemPositions["fire"]
        if px and py and pos and pos.x and pos.y then
            local effectiveRange = TOTEM_RANGE_OVERRIDE[fireSpell] or TOTEM_RANGE
            local dist = GetDistance(px,py,pos.x,pos.y)
            if dist and dist > effectiveRange then
                for i,totem in ipairs(totemState) do
                    if totem.element=="fire" then
                        totemState[i].locallyVerified=false; totemState[i].serverVerified=false;
                        totemState[i].unitId=nil; totemPositions["fire"]=nil; break
                    end
                end
            end
        end
    end

    local fireActive = false;
    for i,totem in ipairs(totemState) do
        if totem.element=="fire" then
            if superwowEnabled then
                if totem.unitId and UnitExists(totem.unitId) then fireActive=true end
            else
                if totem.buff and HasBuff(totem.buff,"player") then fireActive=true
                elseif totem.locallyVerified and totem.serverVerified then fireActive=true end
            end
            break
        end
    end
    if fireActive then return end

    BPCast(fireSpell);
    if ST_TotemBar_StartTimer then ST_TotemBar_StartTimer("Fire",fireSpell) end
    for i,totem in ipairs(totemState) do
        if totem.element=="fire" then
            totemState[i].spell=fireSpell; totemState[i].locallyVerified=true;
            totemState[i].localVerifyTime=currentTime; totemState[i].serverVerified=false;
            totemState[i].unitId=nil; totemPositions.fire=nil; break
        end
    end
    lastTotemCastTime = currentTime;
end

SLASH_STBUFF1="/stbuff";           SlashCmdList["STBUFF"]=DropTotems;
SLASH_STFIREBUFF1="/stfirebuff";   SlashCmdList["STFIREBUFF"]=DropFireTotem;
SLASH_STDEBUG1="/stdebug";         SlashCmdList["STDEBUG"]=function() ToggleSetting("DEBUG_MODE","Debug mode") end
SLASH_STF1="/stf";                 SlashCmdList["STF"]=function() ToggleSetting("FOLLOW_ENABLED","Follow functionality") end
SLASH_STCHAINHEAL1="/stchainheal"; SlashCmdList["STCHAINHEAL"]=function() ToggleSetting("CHAIN_HEAL_ENABLED","Chain Heal functionality") end
SLASH_STANTIDISEASE1="/stantidisease"; SlashCmdList["STANTIDISEASE"]=ToggleAntiDiseaseMode;
SLASH_STANTIPOISON1="/stantipoison";   SlashCmdList["STANTIPOISON"]=ToggleAntiPoisonMode;
SLASH_STHYBRID1="/sthybrid";       SlashCmdList["STHYBRID"]=ToggleHybridMode;
SLASH_STDELAY1="/stdelay";         SlashCmdList["STDELAY"]=SetTotemCastDelay;
SLASH_STPETS1="/stpets";           SlashCmdList["STPETS"]=TogglePetHealing;
SLASH_STAUTO1="/stauto";           SlashCmdList["STAUTO"]=ToggleAutoShieldMode;

SLASH_STL1="/stl";
SlashCmdList["STL"]=function()
    if UnitExists("target") and UnitIsPlayer("target") then
        local n=UnitName("target"); settings.FOLLOW_TARGET_NAME=n; SuperTotemDB.FOLLOW_TARGET_NAME=n;
        PrintMessage("Follow target set to ");
    else
        PrintMessage("No valid player target selected.");
    end
end

SLASH_STWATERSHIELD1="/stwatershield"; SLASH_STWATERSHIELD2="/stws"; SlashCmdList["STWATERSHIELD"]=SetWaterShield;
SLASH_STLIGHTNINGSHIELD1="/stlightningshield"; SLASH_STLIGHTNINGSHIELD2="/stls"; SlashCmdList["STLIGHTNINGSHIELD"]=SetLightningShield;
SLASH_STEARTHSHIELD1="/stearthshield"; SLASH_STEARTHSHIELD2="/stes"; SlashCmdList["STEARTHSHIELD"]=SetEarthShield;

SLASH_STSOE1="/stsoe";       SlashCmdList["STSOE"]=function() SetEarthTotem("Strength of Earth Totem","Strength of Earth") end
SLASH_STSS1="/stss";         SlashCmdList["STSS"]=function() SetEarthTotem("Stoneskin Totem","Stoneskin") end
SLASH_STTREMOR1="/sttremor"; SlashCmdList["STTREMOR"]=function() SetEarthTotem("Tremor Totem","Tremor") end
SLASH_STSTONECLAW1="/ststoneclaw"; SlashCmdList["STSTONECLAW"]=function() SetEarthTotem("Stoneclaw Totem","Stoneclaw") end
SLASH_STEARTHBIND1="/stearthbind"; SlashCmdList["STEARTHBIND"]=function() SetEarthTotem("Earthbind Totem","Earthbind") end

SLASH_STFT1="/stft";         SlashCmdList["STFT"]=function() SetFireTotem("Flametongue Totem","Flametongue") end
SLASH_STFRR1="/stfrr";       SlashCmdList["STFRR"]=function() SetFireTotem("Frost Resistance Totem","Frost Resistance") end
SLASH_STFIRENOVA1="/stfirenova"; SlashCmdList["STFIRENOVA"]=function() SetFireTotem("Fire Nova Totem","Fire Nova") end
SLASH_STSEARING1="/stsearing"; SlashCmdList["STSEARING"]=function() SetFireTotem("Searing Totem","Searing") end
SLASH_STMAGMA1="/stmagma";   SlashCmdList["STMAGMA"]=function() SetFireTotem("Magma Totem","Magma") end

SLASH_STWF1="/stwf";         SlashCmdList["STWF"]=function() SetAirTotem("Windfury Totem","Windfury") end
SLASH_STGOA1="/stgoa";       SlashCmdList["STGOA"]=function() SetAirTotem("Grace of Air Totem","Grace of Air") end
SLASH_STNR1="/stnr";         SlashCmdList["STNR"]=function() SetAirTotem("Nature Resistance Totem","Nature Resistance") end
SLASH_STGROUNDING1="/stgrounding"; SlashCmdList["STGROUNDING"]=function() SetAirTotem("Grounding Totem","Grounding") end
SLASH_STSENTRY1="/stsentry"; SlashCmdList["STSENTRY"]=function() SetAirTotem("Sentry Totem","Sentry") end
SLASH_STWINDWALL1="/stwindwall"; SlashCmdList["STWINDWALL"]=function() SetAirTotem("Windwall Totem","Windwall") end
SLASH_STTRANQUIL1="/sttranquil"; SlashCmdList["STTRANQUIL"]=function() SetAirTotem("Tranquil Air Totem","Tranquil Air") end

SLASH_STMS1="/stms";         SlashCmdList["STMS"]=function() SetWaterTotem("Mana Spring Totem","Mana Spring") end
SLASH_STHS1="/sths";         SlashCmdList["STHS"]=function() SetWaterTotem("Healing Stream Totem","Healing Stream") end
SLASH_STFR1="/stfr";         SlashCmdList["STFR"]=function() SetWaterTotem("Fire Resistance Totem","Fire Resistance") end
SLASH_STPOISON1="/stpoison"; SlashCmdList["STPOISON"]=function() SetWaterTotem("Poison Cleansing Totem","Poison Cleansing") end
SLASH_STDISEASE1="/stdisease"; SlashCmdList["STDISEASE"]=function() SetWaterTotem("Disease Cleansing Totem","Disease Cleansing") end

SLASH_ST1="/st"; SLASH_ST2="/supertotem"; SlashCmdList["ST"]=PrintUsage;
SLASH_STREPORT1="/streport"; SlashCmdList["STREPORT"]=ReportTotemsToParty;

OnExternalTotemCast = function(spellName)
    local def = TOTEM_DEFINITIONS[spellName];
    if not def then return end
    local currentTime = GetTime();
    for i, totem in ipairs(totemState) do
        if totem.element == def.element then
            -- If already server-verified with the same spell, this is likely a spam
            -- attempt -- ignore it. A genuine cast would destroy the old totem first
            -- and SuperWoW will reset serverVerified via UnitExists checks.
            -- But if it's a different spell, allow it through as a genuine replacement.
            if totem.serverVerified and totem.spell == spellName then
                if settings.DEBUG_MODE then
                    PrintMessage("External totem spam ignored - ");
                end
                return;
            end
            totemState[i].spell = spellName;
            totemState[i].buff  = def.buff;
            totemState[i].locallyVerified = true;
            totemState[i].localVerifyTime = currentTime;
            totemState[i].serverVerified  = false;
            totemState[i].unitId = nil;
            totemPositions[def.element] = nil;
            break;
        end
    end
    lastTotemCastTime = currentTime;
    lastAllTotemsActiveTime = 0;
    -- Do NOT start the bar timer or refresh icons here -- wait for SuperWoW
    -- GUID confirmation in UNIT_MODEL_CHANGED so we only update on a real cast.
    if settings.DEBUG_MODE then
        DEFAULT_CHAT_FRAME:AddMessage("SuperTotem: External totem pending SuperWoW: "..spellName, 1, 1, 0);
    end
end

OnExternalTotemicRecall = function()
    local now = GetTime();
    if now - lastTotemRecallTime < 6 then
        if settings.DEBUG_MODE then
            DEFAULT_CHAT_FRAME:AddMessage("SuperTotem: Ignoring Totemic Recall - still on cooldown", 1, 0.3, 0.3);
        end
        return;
    end
    lastTotemRecallTime = now;
    lastAllTotemsActiveTime = 0;
    ResetTotemState();
    if ST_TotemBar_StopAllTimers then ST_TotemBar_StopAllTimers() end
    DEFAULT_CHAT_FRAME:AddMessage("Totems: RECALLED", 0, 1, 0);
end

local function OnEvent()
    if event=="VARIABLES_LOADED" then
        -- Merge saved values over defaults, with type-safe fallbacks
        local db = SuperTotemDB;
        settings.DEBUG_MODE          = db.DEBUG_MODE          or false;
        settings.FOLLOW_ENABLED      = db.FOLLOW_ENABLED      or false;
        settings.CHAIN_HEAL_ENABLED  = db.CHAIN_HEAL_ENABLED  or false;
        settings.HEALTH_THRESHOLD    = db.HEALTH_THRESHOLD    or 90;
        settings.STRATHOLME_MODE     = db.STRATHOLME_MODE     or false;
        settings.ZG_MODE             = db.ZG_MODE             or false;
        settings.HYBRID_MODE         = db.HYBRID_MODE         or false;
        settings.PET_HEALING_ENABLED = db.PET_HEALING_ENABLED or false;
        settings.AUTO_SHIELD_MODE    = db.AUTO_SHIELD_MODE    or false;
        settings.SHIELD_TYPE         = db.SHIELD_TYPE         or "Water Shield";
        settings.STRICT_MODE         = db.STRICT_MODE ~= false;
        local function loadTotem(val, default)
            if val == "none" then return nil end
            return val or default;
        end
        settings.EARTH_TOTEM = loadTotem(db.EARTH_TOTEM, "Strength of Earth Totem");
        settings.FIRE_TOTEM  = loadTotem(db.FIRE_TOTEM,  "Flametongue Totem");
        settings.AIR_TOTEM   = loadTotem(db.AIR_TOTEM,   "Windfury Totem");
        settings.WATER_TOTEM = loadTotem(db.WATER_TOTEM,  "Mana Spring Totem");
        settings.EARTH_TOTEM_FB = loadTotem(db.EARTH_TOTEM_FB, nil);
        settings.FIRE_TOTEM_FB  = loadTotem(db.FIRE_TOTEM_FB,  nil);
        settings.AIR_TOTEM_FB   = loadTotem(db.AIR_TOTEM_FB,   nil);
        settings.FALLBACK_ENABLED = db.FALLBACK_ENABLED ~= false;
        settings.FOLLOW_TARGET_NAME  = db.FOLLOW_TARGET_NAME;
        settings.FOLLOW_TARGET_UNIT  = db.FOLLOW_TARGET_UNIT  or "party1";

        -- Persist defaults back so new keys are written on first logout
        db.DEBUG_MODE          = settings.DEBUG_MODE;
        db.FOLLOW_ENABLED      = settings.FOLLOW_ENABLED;
        db.CHAIN_HEAL_ENABLED  = settings.CHAIN_HEAL_ENABLED;
        db.HEALTH_THRESHOLD    = settings.HEALTH_THRESHOLD;
        db.STRATHOLME_MODE     = settings.STRATHOLME_MODE;
        db.ZG_MODE             = settings.ZG_MODE;
        db.HYBRID_MODE         = settings.HYBRID_MODE;
        db.PET_HEALING_ENABLED = settings.PET_HEALING_ENABLED;
        db.AUTO_SHIELD_MODE    = settings.AUTO_SHIELD_MODE;
        db.SHIELD_TYPE         = settings.SHIELD_TYPE;
        db.STRICT_MODE         = settings.STRICT_MODE;
        db.EARTH_TOTEM         = settings.EARTH_TOTEM or db.EARTH_TOTEM or "none";
        db.FIRE_TOTEM          = settings.FIRE_TOTEM  or db.FIRE_TOTEM  or "none";
        db.AIR_TOTEM           = settings.AIR_TOTEM   or db.AIR_TOTEM   or "none";
        db.WATER_TOTEM         = settings.WATER_TOTEM or db.WATER_TOTEM or "none";
        db.EARTH_TOTEM_FB      = settings.EARTH_TOTEM_FB or db.EARTH_TOTEM_FB or "none";
        db.FIRE_TOTEM_FB       = settings.FIRE_TOTEM_FB  or db.FIRE_TOTEM_FB  or "none";
        db.AIR_TOTEM_FB        = settings.AIR_TOTEM_FB   or db.AIR_TOTEM_FB   or "none";
        db.FALLBACK_ENABLED    = settings.FALLBACK_ENABLED;
        db.FOLLOW_TARGET_NAME  = settings.FOLLOW_TARGET_NAME;
        db.FOLLOW_TARGET_UNIT  = settings.FOLLOW_TARGET_UNIT;

        -- Load range values
        TOTEM_RANGE = db.TOTEM_RANGE or 30;
        db.TOTEM_RANGE = TOTEM_RANGE;
        TOTEM_RANGE_OVERRIDE["Searing Totem"] = db.SEARING_RANGE or 20;
        TOTEM_RANGE_OVERRIDE["Magma Totem"]   = db.MAGMA_RANGE   or 8;
        db.SEARING_RANGE = TOTEM_RANGE_OVERRIDE["Searing Totem"];
        db.MAGMA_RANGE   = TOTEM_RANGE_OVERRIDE["Magma Totem"];

        totemState = InitializeTotemState();

        -- Refresh UI to reflect loaded settings
        if ST_TotemBar_RefreshIcons   then ST_TotemBar_RefreshIcons()   end
        if ST_TotemBar_RefreshToggles then ST_TotemBar_RefreshToggles() end
        if ST_TotemBar_RefreshFireSlider then ST_TotemBar_RefreshFireSlider() end
        if ST_RangeSlider_Refresh     then ST_RangeSlider_Refresh()     end
        if ST_TotemBar_RefreshFallbackBadges then ST_TotemBar_RefreshFallbackBadges() end

        if SUPERWOW_VERSION then
            superwowEnabled=true
            DEFAULT_CHAT_FRAME:AddMessage("SuperTotem: SuperWoW v"..tostring(SUPERWOW_VERSION).." detected.");
        else
            superwowEnabled=false
            DEFAULT_CHAT_FRAME:AddMessage("SuperTotem: SuperWoW not detected - using fallback buff detection.");
        end
        DEFAULT_CHAT_FRAME:AddMessage("SuperTotem: Loaded.");
    end
end
local f=CreateFrame("Frame");
f:RegisterEvent("VARIABLES_LOADED");
f:SetScript("OnEvent",OnEvent);
PrintUsage();

-- =============================================================
-- TOTEM BAR  (/bpmenu)
-- =============================================================

local function SetFallbackTotem(element, totemName)
    local el = string.lower(element);
    if el == "air" then
        settings.AIR_TOTEM_FB = totemName; SuperTotemDB.AIR_TOTEM_FB = totemName or "none";
    elseif el == "fire" then
        settings.FIRE_TOTEM_FB = totemName; SuperTotemDB.FIRE_TOTEM_FB = totemName or "none";
    elseif el == "earth" then
        settings.EARTH_TOTEM_FB = totemName; SuperTotemDB.EARTH_TOTEM_FB = totemName or "none";
    end
    PrintMessage("Fallback "..el.." totem set to "..(totemName or "none")..".");
    if ST_TotemBar_RefreshFallbackBadges then ST_TotemBar_RefreshFallbackBadges() end
end

do
    local TOTEM_ICONS = {
        ["Strength of Earth Totem"] = "Interface\\Icons\\Spell_Nature_EarthBindTotem",
        ["Stoneskin Totem"]         = "Interface\\Icons\\Spell_Nature_StoneSkinTotem",
        ["Tremor Totem"]            = "Interface\\Icons\\Spell_Nature_TremorTotem",
        ["Stoneclaw Totem"]         = "Interface\\Icons\\Spell_Nature_StoneclawTotem",
        ["Earthbind Totem"]         = "Interface\\Icons\\Spell_Nature_StrengthOfEarthTotem02",
        ["Flametongue Totem"]       = "Interface\\Icons\\spell_nature_guardianward",
        ["Frost Resistance Totem"]  = "Interface\\Icons\\Spell_FrostResistanceTotem_01",
        ["Fire Nova Totem"]         = "Interface\\Icons\\Spell_Fire_SealOfFire",
        ["Searing Totem"]           = "Interface\\Icons\\Spell_Fire_SearingTotem",
        ["Magma Totem"]             = "Interface\\Icons\\Spell_Fire_SelfDestruct",
        ["Windfury Totem"]          = "Interface\\Icons\\spell_nature_windfury",
        ["Grace of Air Totem"]      = "Interface\\Icons\\spell_nature_invisibilitytotem",
        ["Nature Resistance Totem"] = "Interface\\Icons\\Spell_Nature_NatureResistanceTotem",
        ["Grounding Totem"]         = "Interface\\Icons\\Spell_Nature_GroundingTotem",
        ["Sentry Totem"]            = "Interface\\Icons\\Spell_Nature_RemoveCurse",
        ["Windwall Totem"]          = "Interface\\Icons\\spell_nature_earthbind",
        ["Tranquil Air Totem"]      = "Interface\\Icons\\spell_nature_brilliance",
        ["Mana Spring Totem"]       = "Interface\\Icons\\Spell_Nature_ManaRegenTotem",
        ["Healing Stream Totem"]    = "Interface\\Icons\\INV_Spear_04",
        ["Fire Resistance Totem"]   = "Interface\\Icons\\Spell_FireResistanceTotem_01",
        ["Poison Cleansing Totem"]  = "Interface\\Icons\\Spell_Nature_PoisonCleansingTotem",
        ["Disease Cleansing Totem"] = "Interface\\Icons\\Spell_Nature_DiseaseCleansingTotem",
    };
    local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Idol_03";

    local TOTEM_DURATIONS = {
        ["Strength of Earth Totem"] = 120,
        ["Stoneskin Totem"]         = 120,
        ["Tremor Totem"]            = 120,
        ["Stoneclaw Totem"]         =  15,
        ["Earthbind Totem"]         =  45,
        ["Flametongue Totem"]       = 120,
        ["Frost Resistance Totem"]  = 120,
        ["Searing Totem"]           =  55,
        ["Fire Nova Totem"]         =   5,
        ["Magma Totem"]             =  20,
        ["Windfury Totem"]          = 120,
        ["Grace of Air Totem"]      = 120,
        ["Nature Resistance Totem"] = 120,
        ["Grounding Totem"]         =  45,
        ["Sentry Totem"]            = 120,
        ["Windwall Totem"]          = 120,
        ["Tranquil Air Totem"]      = 120,
        ["Mana Spring Totem"]       =  60,
        ["Healing Stream Totem"]    = 120,
        ["Fire Resistance Totem"]   = 120,
        ["Poison Cleansing Totem"]  = 120,
        ["Disease Cleansing Totem"] = 120,
    };

    local timerState = {};

    local ELEMENTS = {
        { key="Water", r=0.30, g=0.65, b=1.00, dbKey="WATER_TOTEM",
          totems={"Mana Spring Totem","Healing Stream Totem","Fire Resistance Totem","Poison Cleansing Totem","Disease Cleansing Totem"} },
        { key="Earth", r=0.80, g=0.60, b=0.20, dbKey="EARTH_TOTEM",
          totems={"Strength of Earth Totem","Stoneskin Totem","Tremor Totem","Stoneclaw Totem","Earthbind Totem"} },
        { key="Air",   r=0.55, g=0.85, b=1.00, dbKey="AIR_TOTEM",
          totems={"Windfury Totem","Grace of Air Totem","Nature Resistance Totem","Windwall Totem","Grounding Totem","Sentry Totem","Tranquil Air Totem"} },
        { key="Fire",  r=1.00, g=0.40, b=0.10, dbKey="FIRE_TOTEM",
          totems={"Flametongue Totem","Frost Resistance Totem","Searing Totem","Fire Nova Totem","Magma Totem"} },
    };

    local function GetCurrentTotem(dbKey) return settings[dbKey] end

    local NONE_ICON = "Interface\\Icons\\spell_shadow_sacrificialshield";

    local function ApplyTotemSelection(elementKey, totemName)
        local el=string.lower(elementKey)
        if     el=="earth" then SetEarthTotem(totemName, totemName or "none")
        elseif el=="fire"  then SetFireTotem(totemName,  totemName or "none")
        elseif el=="air"   then SetAirTotem(totemName,   totemName or "none")
        elseif el=="water" then SetWaterTotem(totemName, totemName or "none")
        end
    end

    local tt = CreateFrame("GameTooltip","BP_MenuTT",UIParent,"GameTooltipTemplate");
    tt:SetOwner(UIParent,"ANCHOR_NONE");
    local function ShowSpellTip(anchor, spellName)
        tt:ClearLines(); tt:SetOwner(anchor,"ANCHOR_RIGHT");
        local i=1;
        while true do
            local n=GetSpellName(i,BOOKTYPE_SPELL); if not n then break end
            if n==spellName then tt:SetSpell(i,BOOKTYPE_SPELL); tt:Show(); return end
            i=i+1;
        end
        tt:AddLine(spellName,1,1,1); tt:Show();
    end

    -- All size constants defined together, in dependency order
    local BAR_BTN_SIZE    = 40;
    local ACTIVE_BTN_SIZE = 28;
    local FLY_BTN_SIZE    = 36;
    local FLY_PADDING     = 0;
    local FLY_ROW_H       = FLY_BTN_SIZE;
    local FLY_WIDTH       = FLY_BTN_SIZE + FLY_PADDING * 2;
    local TOGGLE_BTN_SIZE = 14;
    local SLIDER_H        = TOGGLE_BTN_SIZE + 4;
    local BAR_PADDING     = 0;
    local TOGGLE_PADDING  = 0;
    local HANDLE_H        = 0;

    local barW = BAR_BTN_SIZE * 4;
    local barH = BAR_BTN_SIZE + HANDLE_H;

    local bar = CreateFrame("Frame","ST_TotemBar",UIParent);
    bar:SetWidth(barW); bar:SetHeight(barH);
    bar:SetPoint("CENTER",UIParent,"CENTER",0,-300);
    bar:SetMovable(true); bar:EnableMouse(true); bar:SetFrameStrata("MEDIUM");
    bar:RegisterForDrag("LeftButton");
    bar:SetScript("OnDragStart", function()
        if IsShiftKeyDown() then bar:StartMoving() end
    end);
    bar:SetScript("OnDragStop", function() bar:StopMovingOrSizing() end);

    -- Unified background panel
    local barBg = CreateFrame("Frame", nil, bar);
    barBg:SetAllPoints(bar);
    local barBgTex = barBg:CreateTexture(nil, "BACKGROUND");
    barBgTex:SetAllPoints(barBg);
    barBgTex:SetTexture(0.05, 0.05, 0.05, 0);

    local flyoutFrames = {};
    local barButtons   = {};

    -- Controls (toggle buttons + sliders) that fade in on bar mouseover
    local fadeControls = {};
    local barHovered   = false;
    local FADE_SPEED   = 4.0; -- alpha units per second
    local shieldFlyout; -- forward declaration, assigned below
    local flyoutDismiss; -- forward declaration, assigned below

    local fadeFrame = CreateFrame("Frame");
    fadeFrame:SetScript("OnUpdate", function()
        local dt = arg1;
        local shouldShow = barHovered or shieldFlyout:IsShown();
        for i = 1, table.getn(fadeControls) do
            local ctrl = fadeControls[i];
            if ctrl and ctrl.GetAlpha then
                local cur = ctrl:GetAlpha();
                if shouldShow then
                    local next = cur + FADE_SPEED * dt;
                    if next >= 1 then next = 1 end
                    ctrl:SetAlpha(next);
                else
                    local next = cur - FADE_SPEED * dt;
                    if next <= 0 then next = 0 end
                    ctrl:SetAlpha(next);
                end
            end
        end
    end);

    -- bar-level enter/leave to drive fade (fires when mouse enters/leaves the whole bar region)
    bar:SetScript("OnEnter", function() barHovered = true  end);
    bar:SetScript("OnLeave", function() barHovered = false end);

    barBg:SetAlpha(0);
    fadeControls[table.getn(fadeControls)+1] = barBg;

    -- Resize the bar height depending on whether any active-totem row is visible
    local function ResizeBar()
        local anyActive = false;
        for i = 1, table.getn(ELEMENTS) do
            local bb = barButtons[ELEMENTS[i].key];
            if bb and bb.activeBtn and bb.activeBtn:IsVisible() then
                anyActive = true; break;
            end
        end
        local newH = anyActive and (BAR_BTN_SIZE + ACTIVE_BTN_SIZE + HANDLE_H)
                                 or (BAR_BTN_SIZE + HANDLE_H);
        bar:SetHeight(newH);
        barBg:SetHeight(newH);
    end

    local tickFrame = CreateFrame("Frame");
    tickFrame:SetScript("OnUpdate",function()
        local now=GetTime();
        for i=1,table.getn(ELEMENTS) do
            local el=ELEMENTS[i]; local bb=barButtons[el.key]; local ts=timerState[el.key];
            if not bb then return end

            local function SetTD(fs,layers,text,r,g,b)
                fs:SetText(text); fs:SetTextColor(r,g,b,1); fs:Show();
                for li=1,table.getn(layers) do layers[li]:SetText(text); layers[li]:Show() end
            end
            local function HideTD(fs,layers)
                fs:Hide(); for li=1,table.getn(layers) do layers[li]:Hide() end
            end
            local function TC(rem,dur)
                if rem>dur*0.5 then return 1,1,1 elseif rem>10 then return 1,0.8,0 else return 1,0.2,0.2 end
            end
            local function FT(r) if r<10 then return string.format("%.1f",r) else return string.format("%d",r) end end

            local setTotem=GetCurrentTotem(el.dbKey)
            if el.key=="Water" then
                if settings.STRATHOLME_MODE then setTotem="Disease Cleansing Totem"
                elseif settings.ZG_MODE then setTotem="Poison Cleansing Totem" end
            end
            local activeTotem=ts and ts.totemName
            -- showActive: the currently running totem differs from the configured primary
            -- (i.e. the fallback is active)
            local showActive=activeTotem and activeTotem~=setTotem

            -- If the primary is a cooldown totem and it's on cooldown, show remaining
            -- cooldown on the main icon in grey so the player knows when it's ready again.
            local function ShowCooldownOnMain()
                if not setTotem or not COOLDOWN_TOTEM_CD[setTotem] then return false end
                local start, duration = GetSpellCooldown(setTotem);
                if not start or not duration or duration == 0 then return false end
                local rem = (start + duration) - now;
                if rem <= 0 then return false end
                SetTD(bb.timer, bb.timerLayers, FT(rem), 0.55, 0.55, 0.55);
                return true;
            end

            if ts then
                -- If totemState has reset this slot (e.g. Grounding absorbed a spell,
                -- totem expired, or was destroyed), kill the timer immediately.
                local slotActive = false;
                for si=1,table.getn(totemState) do
                    local st = totemState[si];
                    if string.lower(el.key) == st.element and (st.locallyVerified or st.serverVerified) then
                        slotActive = true; break;
                    end
                end
                if not slotActive then
                    timerState[el.key]=nil; HideTD(bb.timer,bb.timerLayers)
                    if bb.activeBtn then bb.activeBtn:Hide(); ResizeBar() end
                else
                local rem=ts.duration-(now-ts.startTime)
                if ts.duration==0 or rem<=0 then
                    timerState[el.key]=nil; HideTD(bb.timer,bb.timerLayers)
                    if bb.activeBtn then bb.activeBtn:Hide(); ResizeBar() end
                else
                    local text=FT(rem); local r,g,b=TC(rem,ts.duration)
                    if showActive then
                        -- Show primary cooldown on main icon (grey), fallback in activeBtn
                        if not ShowCooldownOnMain() then
                            HideTD(bb.timer,bb.timerLayers)
                        end
                        if bb.activeBtn then
                            bb.activeIcon:SetTexture(TOTEM_ICONS[activeTotem] or FALLBACK_ICON)
                            SetTD(bb.activeTimer,bb.activeTimerLayers,text,r,g,b)
                            bb.activeBtn:Show(); ResizeBar()
                        end
                    else
                        SetTD(bb.timer,bb.timerLayers,text,r,g,b)
                        if bb.activeBtn then bb.activeBtn:Hide(); ResizeBar() end
                    end
                end
                end -- slotActive
            else
                if not ShowCooldownOnMain() then
                    HideTD(bb.timer,bb.timerLayers)
                end
                if bb.activeBtn then bb.activeBtn:Hide(); ResizeBar() end
            end
        end
    end);

    local closeScheduled={};
    local function CloseFlyout(key) if flyoutFrames[key] then flyoutFrames[key]:Hide() end; closeScheduled[key]=false end
    local function CloseAllFlyouts() for i=1,table.getn(ELEMENTS) do CloseFlyout(ELEMENTS[i].key) end end
    local function ScheduleClose(key)
        closeScheduled[key]=true; local elapsed=0;
        bar:SetScript("OnUpdate",function()
            elapsed=elapsed+arg1; if elapsed<0.12 then return end
            bar:SetScript("OnUpdate",nil)
            if closeScheduled[key] then CloseFlyout(key) end
        end)
    end
    local function CancelClose(key) closeScheduled[key]=false end

    -- BUILD COLUMNS
    for colIdx=1,table.getn(ELEMENTS) do
        local elDef=ELEMENTS[colIdx]; local elementKey=elDef.key; local dbKey=elDef.dbKey;

        local mainBtn=CreateFrame("Button",nil,bar);
        mainBtn:RegisterForDrag("LeftButton");
        mainBtn:SetScript("OnDragStart", function() if IsShiftKeyDown() then bar:StartMoving() end end);
        mainBtn:SetScript("OnDragStop", function() bar:StopMovingOrSizing() end);
        mainBtn:SetWidth(BAR_BTN_SIZE); mainBtn:SetHeight(BAR_BTN_SIZE);
        mainBtn:SetHitRectInsets(0, 0, 0, 0);
        mainBtn:SetPoint("TOPLEFT",bar,"TOPLEFT",(colIdx-1)*BAR_BTN_SIZE,0);

        local slotTex=mainBtn:CreateTexture(nil,"BACKGROUND");
        slotTex:SetTexture("Interface\\Buttons\\UI-EmptySlot"); slotTex:SetAllPoints(mainBtn);

        local barIcon=mainBtn:CreateTexture(nil,"ARTWORK");
        barIcon:SetWidth(BAR_BTN_SIZE); barIcon:SetHeight(BAR_BTN_SIZE);
        barIcon:SetPoint("CENTER",mainBtn,"CENTER",0,0);

        local hiTex=mainBtn:CreateTexture(nil,"HIGHLIGHT");
        hiTex:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); hiTex:SetAllPoints(mainBtn);
        hiTex:SetBlendMode("ADD"); mainBtn:SetHighlightTexture(hiTex);

        local timerText=mainBtn:CreateFontString(nil,"OVERLAY");
        timerText:SetFont("Fonts\\FRIZQT__.TTF",14,"THICKOUTLINE");
        timerText:SetPoint("CENTER",mainBtn,"CENTER",0,0);
        timerText:SetTextColor(1,1,1,1); timerText:Hide();
        local timerLayers={};

        local activeBtn=CreateFrame("Button",nil,bar);
        activeBtn:RegisterForDrag("LeftButton");
        activeBtn:SetScript("OnDragStart", function() if IsShiftKeyDown() then bar:StartMoving() end end);
        activeBtn:SetScript("OnDragStop", function() bar:StopMovingOrSizing() end);
        activeBtn:SetWidth(BAR_BTN_SIZE); activeBtn:SetHeight(BAR_BTN_SIZE);
        activeBtn:SetPoint("TOP",mainBtn,"BOTTOM",0,-(BAR_BTN_SIZE - SLIDER_H - HANDLE_H));

        local aSlot=activeBtn:CreateTexture(nil,"BACKGROUND");
        aSlot:SetTexture("Interface\\Buttons\\UI-EmptySlot"); aSlot:SetAllPoints(activeBtn);
        local aIcon=activeBtn:CreateTexture(nil,"ARTWORK");
        aIcon:SetWidth(BAR_BTN_SIZE); aIcon:SetHeight(BAR_BTN_SIZE);
        aIcon:SetPoint("CENTER",activeBtn,"CENTER",0,0);
        local aHi=activeBtn:CreateTexture(nil,"HIGHLIGHT");
        aHi:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); aHi:SetAllPoints(activeBtn);
        aHi:SetBlendMode("ADD"); activeBtn:SetHighlightTexture(aHi);
        local aTimer=activeBtn:CreateFontString(nil,"OVERLAY");
        aTimer:SetFont("Fonts\\FRIZQT__.TTF",10,"THICKOUTLINE");
        aTimer:SetPoint("CENTER",activeBtn,"CENTER",0,0); aTimer:SetTextColor(1,1,1,1); aTimer:Hide();
        local aTimerLayers={};
        activeBtn:SetScript("OnClick",function()
            local ts=timerState[elementKey]; if ts and ts.totemName then BPCast(ts.totemName); ST_TotemBar_StartTimer(elementKey,ts.totemName) end
        end);
        activeBtn:SetScript("OnEnter",function() local ts=timerState[elementKey]; if ts and ts.totemName then ShowSpellTip(activeBtn,ts.totemName) end end);
        activeBtn:SetScript("OnLeave",function() tt:Hide() end);
        activeBtn:Hide();

        barButtons[elementKey]={btn=mainBtn,icon=barIcon,timer=timerText,timerLayers=timerLayers,
            activeBtn=activeBtn,activeIcon=aIcon,activeTimer=aTimer,activeTimerLayers=aTimerLayers};

        -- Small corner badge showing the fallback totem icon
        local BADGE_SIZE = 18;
        local fbBadge = mainBtn:CreateTexture(nil,"OVERLAY");
        fbBadge:SetWidth(BADGE_SIZE); fbBadge:SetHeight(BADGE_SIZE);
        fbBadge:SetPoint("BOTTOMRIGHT",mainBtn,"BOTTOMRIGHT",0,0);
        fbBadge:Hide();
        barButtons[elementKey].fbBadge = fbBadge;

        -- FLYOUT
        local maxRows=table.getn(elDef.totems);
        local flyH=FLY_PADDING*2+maxRows*FLY_ROW_H;
        local fly=CreateFrame("Frame",nil,UIParent);
        fly:SetWidth(FLY_WIDTH); fly:SetHeight(flyH);
        fly:SetFrameStrata("HIGH"); fly:EnableMouse(true); fly:Hide();
        flyoutFrames[elementKey]=fly;

        local flyBg=fly:CreateTexture(nil,"BACKGROUND"); flyBg:SetTexture(0,0,0,0); flyBg:SetAllPoints(fly);
        fly:SetScript("OnLeave",function() ScheduleClose(elementKey) end);
        fly:SetScript("OnEnter",function() CancelClose(elementKey) end);

        local flyBtns={};
        for slotIdx=1,table.getn(elDef.totems) do
            local thisTotem=elDef.totems[slotIdx]; local thisSlot=slotIdx;
            local fb=CreateFrame("CheckButton",nil,fly);
            fb:SetWidth(FLY_BTN_SIZE); fb:SetHeight(FLY_BTN_SIZE);
            fb:SetPoint("TOP",fly,"TOP",0,-(FLY_PADDING+(thisSlot-1)*FLY_ROW_H));
            local fbSlot=fb:CreateTexture(nil,"BACKGROUND");
            fbSlot:SetTexture("Interface\\Buttons\\UI-EmptySlot"); fbSlot:SetAllPoints(fb);
            local fbIcon=fb:CreateTexture(nil,"ARTWORK");
            fbIcon:SetWidth(FLY_BTN_SIZE); fbIcon:SetHeight(FLY_BTN_SIZE);
            fbIcon:SetPoint("CENTER",fb,"CENTER",0,0);
            fb.icon=fbIcon; fb.totemPath=TOTEM_ICONS[thisTotem] or FALLBACK_ICON;
            local fbHi=fb:CreateTexture(nil,"HIGHLIGHT");
            fbHi:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); fbHi:SetAllPoints(fb);
            fbHi:SetBlendMode("ADD"); fb:SetHighlightTexture(fbHi);
            local fbCk=fb:CreateTexture(nil,"OVERLAY");
            fbCk:SetTexture("Interface\\Buttons\\CheckButtonHilight"); fbCk:SetAllPoints(fb);
            fbCk:SetBlendMode("ADD"); fb:SetCheckedTexture(fbCk);
            fb.totemName=thisTotem; fb.elementKey=elementKey;
            fb:RegisterForClicks("LeftButtonUp","RightButtonUp");
            fb:SetScript("OnClick",function()
                if arg1 == "RightButton" then
                    -- Right-click sets fallback only when primary is a cooldown totem
                    local primary = GetCurrentTotem(dbKey);
                    if primary and COOLDOWN_TOTEM_CD[primary] and not COOLDOWN_TOTEM_CD[thisTotem] then
                        SetFallbackTotem(elementKey, thisTotem);
                        -- Refresh checked states: uncheck all, check only the new fallback
                        for i=1,table.getn(flyBtns) do
                            flyBtns[i]:SetChecked(flyBtns[i].totemName==thisTotem and 1 or nil)
                        end
                        tt:ClearLines(); tt:SetOwner(fb,"ANCHOR_RIGHT");
                        tt:AddLine("Fallback set: "..thisTotem,0.4,1,0.4); tt:Show();
                    end
                else
                    ApplyTotemSelection(elementKey,thisTotem);
                    barButtons[elementKey].icon:SetTexture(TOTEM_ICONS[thisTotem] or FALLBACK_ICON);
                    barButtons[elementKey].icon:SetVertexColor(1, 1, 1, 1);
                    for i=1,table.getn(flyBtns) do
                        flyBtns[i]:SetChecked(flyBtns[i].totemName==thisTotem and 1 or nil)
                    end
                    if elementKey=="Fire" and ST_TotemBar_RefreshFireSlider then ST_TotemBar_RefreshFireSlider() end
                    CloseFlyout(elementKey); tt:Hide();
                end
            end);
            fb:SetScript("OnEnter",function()
                CancelClose(elementKey);
                local primary = GetCurrentTotem(dbKey);
                if primary and COOLDOWN_TOTEM_CD[primary] and not COOLDOWN_TOTEM_CD[thisTotem] then
                    tt:ClearLines(); tt:SetOwner(fb,"ANCHOR_RIGHT");
                    tt:AddLine(thisTotem,1,1,1);
                    tt:AddLine("Left-click: set primary",0.8,0.8,0.8);
                    tt:AddLine("Right-click: set as fallback",0.6,1,0.6);
                    tt:Show();
                else
                    ShowSpellTip(fb,thisTotem);
                end
            end);
            fb:SetScript("OnLeave",function() tt:Hide(); ScheduleClose(elementKey) end);
            flyBtns[thisSlot]=fb;
        end

        -- "None" button at the bottom of the flyout
        local noneSlot = table.getn(elDef.totems) + 1;
        local noneBtn = CreateFrame("CheckButton", nil, fly);
        noneBtn:SetWidth(FLY_BTN_SIZE); noneBtn:SetHeight(FLY_BTN_SIZE);
        noneBtn:SetPoint("TOP", fly, "TOP", 0, -(FLY_PADDING + (noneSlot-1) * FLY_ROW_H));
        local noneBg = noneBtn:CreateTexture(nil, "BACKGROUND");
        noneBg:SetTexture("Interface\\Buttons\\UI-EmptySlot"); noneBg:SetAllPoints(noneBtn);
        local noneIcon = noneBtn:CreateTexture(nil, "ARTWORK");
        noneIcon:SetWidth(FLY_BTN_SIZE - 8); noneIcon:SetHeight(FLY_BTN_SIZE - 8);
        noneIcon:SetPoint("CENTER", noneBtn, "CENTER", 0, 0);
        noneIcon:SetTexture(NONE_ICON);
        noneIcon:SetVertexColor(0.5, 0.5, 0.5, 1);
        local noneHi = noneBtn:CreateTexture(nil, "HIGHLIGHT");
        noneHi:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); noneHi:SetAllPoints(noneBtn);
        noneHi:SetBlendMode("ADD"); noneBtn:SetHighlightTexture(noneHi);
        local noneCk = noneBtn:CreateTexture(nil, "OVERLAY");
        noneCk:SetTexture("Interface\\Buttons\\CheckButtonHilight"); noneCk:SetAllPoints(noneBtn);
        noneCk:SetBlendMode("ADD"); noneBtn:SetCheckedTexture(noneCk);
        local noneLabel = noneBtn:CreateFontString(nil, "OVERLAY");
        noneLabel:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE");
        noneLabel:SetPoint("CENTER", noneBtn, "CENTER", 0, 0);
        noneLabel:SetTextColor(0.55, 0.55, 0.55, 1);
        noneLabel:SetText("none");
        noneBtn.totemName = nil; noneBtn.elementKey = elementKey;
        noneBtn:SetScript("OnClick", function()
            ApplyTotemSelection(elementKey, nil);
            barButtons[elementKey].icon:SetTexture(NONE_ICON);
            barButtons[elementKey].icon:SetVertexColor(0.35, 0.35, 0.35, 1);
            for i=1,table.getn(flyBtns) do flyBtns[i]:SetChecked(nil) end
            noneBtn:SetChecked(1);
            if elementKey=="Fire" and ST_TotemBar_RefreshFireSlider then ST_TotemBar_RefreshFireSlider() end
            CloseFlyout(elementKey); tt:Hide();
        end);
        noneBtn:SetScript("OnEnter", function()
            CancelClose(elementKey);
            tt:ClearLines(); tt:SetOwner(noneBtn, "ANCHOR_RIGHT");
            tt:AddLine("None", 1, 1, 1);
            tt:AddLine("Skip this element — no totem will be dropped.", 0.8, 0.8, 0.8);
            tt:Show();
        end);
        noneBtn:SetScript("OnLeave", function() tt:Hide(); ScheduleClose(elementKey) end);
        -- resize flyout to fit the extra row
        fly:SetHeight(FLY_PADDING * 2 + noneSlot * FLY_ROW_H);

        local fbSettingKey;
        if     elementKey=="Air"   then fbSettingKey="AIR_TOTEM_FB"
        elseif elementKey=="Fire"  then fbSettingKey="FIRE_TOTEM_FB"
        elseif elementKey=="Earth" then fbSettingKey="EARTH_TOTEM_FB" end

        fly:SetScript("OnShow",function()
            local cur=GetCurrentTotem(dbKey);
            local showFallback = cur and COOLDOWN_TOTEM_CD[cur];
            local fb = showFallback and fbSettingKey and settings[fbSettingKey];
            for i=1,table.getn(flyBtns) do
                local b=flyBtns[i]; b.icon:SetTexture(b.totemPath);
                if showFallback then
                    b:SetChecked(fb and b.totemName==fb and 1 or nil)
                else
                    b:SetChecked(cur and b.totemName==cur and 1 or nil)
                end
            end
            noneBtn:SetChecked(not cur and 1 or nil);
        end);

        -- HOVER open
        mainBtn:SetScript("OnEnter",function()
            barHovered = true;
            CancelClose(elementKey);
            for i=1,table.getn(ELEMENTS) do if ELEMENTS[i].key~=elementKey then CloseFlyout(ELEMENTS[i].key) end end
            fly:ClearAllPoints(); fly:SetPoint("BOTTOM",mainBtn,"TOP",0,4); fly:Show();
        end);
        mainBtn:SetScript("OnLeave",function() barHovered = false; ScheduleClose(elementKey) end);

        -- CLICK handler
        local TOGGLE_PAIRS={
            ["Fire"] ={ "Searing Totem",          "Magma Totem"          },
            ["Water"]={ "Mana Spring Totem",       "Healing Stream Totem" },
            ["Earth"]={ "Strength of Earth Totem", "Stoneskin Totem"      },
            ["Air"]  ={ "Windfury Totem",           "Grace of Air Totem"  },
        };
        mainBtn:RegisterForClicks("LeftButtonUp","RightButtonUp");
        mainBtn:SetScript("OnClick",function()
            if arg1=="RightButton" then
                local pair=TOGGLE_PAIRS[elementKey]; local cur=GetCurrentTotem(dbKey);
                if pair and (cur==pair[1] or cur==pair[2]) then
                    local next=(cur==pair[1]) and pair[2] or pair[1];
                    ApplyTotemSelection(elementKey,next);
                    barButtons[elementKey].icon:SetTexture(TOTEM_ICONS[next] or FALLBACK_ICON);
                    barButtons[elementKey].icon:SetVertexColor(1, 1, 1, 1);
                    if elementKey=="Fire" and ST_TotemBar_RefreshFireSlider then ST_TotemBar_RefreshFireSlider() end
                else
                    if fly:IsVisible() then CloseFlyout(elementKey)
                    else
                        CancelClose(elementKey);
                        for i=1,table.getn(ELEMENTS) do if ELEMENTS[i].key~=elementKey then CloseFlyout(ELEMENTS[i].key) end end
                        fly:ClearAllPoints(); fly:SetPoint("BOTTOM",mainBtn,"TOP",0,4); fly:Show();
                    end
                end
            else
                local cur=GetCurrentTotem(dbKey);
                if cur then BPCast(cur); ST_TotemBar_StartTimer(elementKey,cur)
                else DEFAULT_CHAT_FRAME:AddMessage("SuperTotem: No "..elementKey.." totem selected.") end
            end
        end);
    end

    -- SLASH
    SLASH_STMENU1="/stmenu";
    SlashCmdList["STMENU"]=function()
        if bar:IsVisible() then CloseAllFlyouts(); bar:Hide() else bar:Show() end
        PlaySound("igMainMenuOption");
    end;

    function ST_TotemBar_StartTimer(elementKey, totemName)
        local dur=TOTEM_DURATIONS[totemName];
        timerState[elementKey]={ startTime=GetTime(), duration=(dur and dur>0) and dur or 0, totemName=totemName };
    end

    function ST_TotemBar_StopAllTimers()
        for i=1,table.getn(ELEMENTS) do
            local key=ELEMENTS[i].key; timerState[key]=nil;
            local bb=barButtons[key];
            if bb then
                if bb.activeBtn then bb.activeBtn:Hide() end
                bb.timer:Hide();
                for li=1,table.getn(bb.timerLayers) do bb.timerLayers[li]:Hide() end
            end
        end
        ResizeBar();
    end

    function ST_TotemBar_UpdateMode()
        local wb=barButtons["Water"]; if not wb then return end
        if settings.STRATHOLME_MODE then
            wb.icon:SetTexture(TOTEM_ICONS["Disease Cleansing Totem"] or FALLBACK_ICON);
            wb.icon:SetVertexColor(1, 1, 1, 1);
        elseif settings.ZG_MODE then
            wb.icon:SetTexture(TOTEM_ICONS["Poison Cleansing Totem"] or FALLBACK_ICON);
            wb.icon:SetVertexColor(1, 1, 1, 1);
        else
            local cur=GetCurrentTotem("WATER_TOTEM");
            wb.icon:SetTexture(cur and TOTEM_ICONS[cur] or NONE_ICON);
            wb.icon:SetVertexColor(cur and 1 or 0.35, cur and 1 or 0.35, cur and 1 or 0.35, 1);
        end
    end

    function ST_TotemBar_RefreshIcons()
        for i=1,table.getn(ELEMENTS) do
            local el=ELEMENTS[i]; local cur=GetCurrentTotem(el.dbKey);
            barButtons[el.key].icon:SetTexture(cur and TOTEM_ICONS[cur] or NONE_ICON);
            barButtons[el.key].icon:SetVertexColor(cur and 1 or 0.35, cur and 1 or 0.35, cur and 1 or 0.35, 1);
        end
        ST_TotemBar_UpdateMode();
        ST_TotemBar_RefreshFallbackBadges();
    end

    local FB_DBKEYS = { Air="AIR_TOTEM_FB", Fire="FIRE_TOTEM_FB", Earth="EARTH_TOTEM_FB" };
    function ST_TotemBar_RefreshFallbackBadges()
        for i=1,table.getn(ELEMENTS) do
            local el=ELEMENTS[i]; local bb=barButtons[el.key];
            if bb and bb.fbBadge then
                local fbKey = FB_DBKEYS[el.key];
                local fb = fbKey and settings[fbKey];
                if fb and settings.FALLBACK_ENABLED then
                    bb.fbBadge:SetTexture(TOTEM_ICONS[fb] or FALLBACK_ICON);
                    bb.fbBadge:Show();
                else
                    bb.fbBadge:Hide();
                end
            end
        end
    end

    ST_TotemBar_RefreshIcons();

    -- --------------------------------------------------------
    -- TOGGLE BUTTONS
    -- --------------------------------------------------------
    local toggleDefs={
        { key="SR", label="*", tip=function() return settings.STRICT_MODE and "Manual totem drops will be replaced" or "Manual totem drops preserved" end, setting="STRICT_MODE",
          onToggle=function() ToggleSetting("STRICT_MODE","Strict mode") end },
        { key="ZG", label="P", tip="Spams Poison Cleansing", setting="ZG_MODE",
          onToggle=function()
              if settings.STRATHOLME_MODE then settings.STRATHOLME_MODE=false; SuperTotemDB.STRATHOLME_MODE=false end
              ToggleSetting("ZG_MODE","Anti-Poison mode"); ResetWaterTotemState();
              if ST_TotemBar_UpdateMode then ST_TotemBar_UpdateMode() end
          end },
        { key="SM", label="D", tip="Spams Disease Cleansing", setting="STRATHOLME_MODE",
          onToggle=function()
              if settings.ZG_MODE then settings.ZG_MODE=false; SuperTotemDB.ZG_MODE=false end
              ToggleSetting("STRATHOLME_MODE","Anti-Disease mode"); ResetWaterTotemState();
              if ST_TotemBar_UpdateMode then ST_TotemBar_UpdateMode() end
          end },
        { key="AS", label="S", tip="Automatic shield cast",     setting="AUTO_SHIELD_MODE",
          onToggle=function() end },
        { key="FB", label="F", tip=function() return settings.FALLBACK_ENABLED and "Fallback totem enabled" or "Fallback totem disabled" end, setting="FALLBACK_ENABLED",
          onToggle=function()
              ToggleSetting("FALLBACK_ENABLED","Fallback totem");
              if ST_TotemBar_RefreshFallbackBadges then ST_TotemBar_RefreshFallbackBadges() end
          end },
    };

    local toggleButtons={};
    local function RefreshToggleColors()
        for i=1,table.getn(toggleDefs) do
            local def=toggleDefs[i]; local btn=toggleButtons[def.key];
            if btn then
                if settings[def.setting] then btn.bg:SetTexture(0.15,0.65,0.15,0.85)
                else                          btn.bg:SetTexture(0.12,0.12,0.12,0.75) end
            end
        end
    end
    function ST_TotemBar_RefreshToggles() RefreshToggleColors() end

    for i=1,table.getn(toggleDefs) do
        local def=toggleDefs[i];
        local btn=CreateFrame("Button",nil,bar);
        btn:RegisterForDrag("LeftButton");
        btn:SetScript("OnDragStart", function() if IsShiftKeyDown() then bar:StartMoving() end end);
        btn:SetScript("OnDragStop", function() bar:StopMovingOrSizing() end);
        btn:SetWidth(TOGGLE_BTN_SIZE); btn:SetHeight(TOGGLE_BTN_SIZE);
        btn:SetPoint("TOPLEFT",bar,"BOTTOMLEFT",(i-1)*TOGGLE_BTN_SIZE,-2);
        local bg=btn:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(btn); bg:SetTexture(0.12,0.12,0.12,0.75); btn.bg=bg;
        local lbl=btn:CreateFontString(nil,"OVERLAY"); lbl:SetFont("Fonts\\FRIZQT__.TTF",8,"OUTLINE");
        lbl:SetAllPoints(btn); lbl:SetJustifyH("CENTER"); lbl:SetJustifyV("MIDDLE");
        lbl:SetTextColor(0.75,0.75,0.75,1); lbl:SetText(def.label);
        local hi=btn:CreateTexture(nil,"HIGHLIGHT"); hi:SetTexture(1,1,1,0.15); hi:SetAllPoints(btn); btn:SetHighlightTexture(hi);
        btn:SetScript("OnClick",function()
            def.onToggle();
            RefreshToggleColors();
            if tt:IsShown() then tt:ClearLines(); tt:AddLine(type(def.tip)=="function" and def.tip() or def.tip,1,1,1); tt:Show() end
        end);
        btn:SetScript("OnEnter",function() barHovered = true; tt:ClearLines(); tt:SetOwner(btn,"ANCHOR_RIGHT"); tt:AddLine(type(def.tip)=="function" and def.tip() or def.tip,1,1,1); tt:Show() end);
        btn:SetScript("OnLeave",function() barHovered = false; tt:Hide() end);
        btn:SetAlpha(0);
        fadeControls[table.getn(fadeControls)+1] = btn;
        toggleButtons[def.key]=btn;
    end
    RefreshToggleColors();

    -- --------------------------------------------------------
    -- SHIELD FLYOUT (anchored above the AS button)
    -- --------------------------------------------------------
    shieldFlyout = CreateFrame("Frame", nil, bar);
    shieldFlyout:SetFrameStrata("DIALOG");
    shieldFlyout:Hide();

    local SHIELD_OPTS = {
        { label="W", tip="Water Shield",     fn=SetWaterShield     },
        { label="L", tip="Lightning Shield", fn=SetLightningShield },
        { label="E", tip="Earth Shield",     fn=SetEarthShield     },
    };
    local FLY_BTN_SIZE = TOGGLE_BTN_SIZE;
    shieldFlyout:SetWidth(FLY_BTN_SIZE);
    shieldFlyout:SetHeight(FLY_BTN_SIZE * table.getn(SHIELD_OPTS));
    shieldFlyout:SetPoint("TOPLEFT", toggleButtons["AS"], "BOTTOMLEFT", 0, -2);
    shieldFlyout:EnableMouse(true);
    shieldFlyout:SetScript("OnEnter", function() barHovered = true end);
    shieldFlyout:SetScript("OnLeave", function() barHovered = false end);

    local flyBg = shieldFlyout:CreateTexture(nil,"BACKGROUND");
    flyBg:SetAllPoints(shieldFlyout); flyBg:SetTexture(0.08,0.08,0.08,0.92);

    for j = 1, table.getn(SHIELD_OPTS) do
        local opt = SHIELD_OPTS[j];
        local fb = CreateFrame("Button", nil, shieldFlyout);
        fb:SetWidth(FLY_BTN_SIZE); fb:SetHeight(FLY_BTN_SIZE);
        fb:SetPoint("TOPLEFT", shieldFlyout, "TOPLEFT", 0, -(j-1)*FLY_BTN_SIZE);
        local fbg = fb:CreateTexture(nil,"BACKGROUND"); fbg:SetAllPoints(fb);
        fbg:SetTexture(0.12,0.12,0.12,0.85);
        local fhi = fb:CreateTexture(nil,"HIGHLIGHT"); fhi:SetTexture(1,1,1,0.15); fhi:SetAllPoints(fb); fb:SetHighlightTexture(fhi);
        local flbl = fb:CreateFontString(nil,"OVERLAY"); flbl:SetFont("Fonts\\FRIZQT__.TTF",8,"OUTLINE");
        flbl:SetAllPoints(fb); flbl:SetJustifyH("CENTER"); flbl:SetJustifyV("MIDDLE");
        flbl:SetTextColor(0.75,0.75,0.75,1); flbl:SetText(opt.label);
        fb:SetScript("OnClick", function()
            opt.fn();
            settings.AUTO_SHIELD_MODE = true; SuperTotemDB.AUTO_SHIELD_MODE = true;
            barHovered = true;
            shieldFlyout:Hide();
            flyoutDismiss:Hide();
            RefreshToggleColors();
        end);
        fb:SetScript("OnEnter", function()
            barHovered = true;
            tt:ClearLines(); tt:SetOwner(fb,"ANCHOR_RIGHT"); tt:AddLine(opt.tip,1,1,1); tt:Show();
        end);
        fb:SetScript("OnLeave", function() barHovered = false; tt:Hide() end);
        -- Don't add to fadeControls -- flyout should stay fully opaque when visible
    end

    -- Dismiss flyout when clicking outside it
    flyoutDismiss = CreateFrame("Frame", nil, UIParent);
    flyoutDismiss:SetAllPoints(UIParent);
    flyoutDismiss:SetFrameStrata("HIGH");
    flyoutDismiss:EnableMouse(true);
    flyoutDismiss:Hide();
    flyoutDismiss:SetScript("OnMouseDown", function()
        shieldFlyout:Hide();
        flyoutDismiss:Hide();
    end);

    -- Wire AS button to show flyout on enable, hide on disable
    local asBtn = toggleButtons["AS"];
    asBtn:SetScript("OnClick", function()
        ToggleAutoShieldMode();
        RefreshToggleColors();
        if settings.AUTO_SHIELD_MODE then
            barHovered = true;
            shieldFlyout:Show();
            flyoutDismiss:Show();
        else
            shieldFlyout:Hide();
            flyoutDismiss:Hide();
        end
    end);

    -- --------------------------------------------------------
    -- GLOBAL RANGE SLIDER
    -- --------------------------------------------------------
    local toggleRowEnd = table.getn(toggleDefs) * TOGGLE_BTN_SIZE;
    local SLIDER_W     = barW - toggleRowEnd;
    local RANGE_STOPS  = { 10, 15, 20, 25, 30, 35, 40 };

    local rangeSlider=CreateFrame("Slider","ST_RangeSlider",bar);
    rangeSlider:SetOrientation("HORIZONTAL");
    rangeSlider:SetWidth(SLIDER_W); rangeSlider:SetHeight(SLIDER_H);
    rangeSlider:SetPoint("TOPLEFT",bar,"BOTTOMLEFT",toggleRowEnd,6);
    rangeSlider:SetMinMaxValues(10,40); rangeSlider:SetValueStep(1); rangeSlider:SetValue(TOTEM_RANGE);
    rangeSlider:SetBackdrop({ bgFile="Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile="Interface\\Buttons\\UI-SliderBar-Border", tile=true, tileSize=8, edgeSize=8,
        insets={left=3,right=3,top=6,bottom=6} });
    local rThumb=rangeSlider:CreateTexture(nil,"OVERLAY");
    rThumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal");
    rThumb:SetWidth(14); rThumb:SetHeight(14); rangeSlider:SetThumbTexture(rThumb);
    local rangeLabel=rangeSlider:CreateFontString(nil,"OVERLAY");
    rangeLabel:SetFont("Fonts\\FRIZQT__.TTF",8,"OUTLINE");
    rangeLabel:SetPoint("CENTER",rangeSlider,"CENTER",0,0);
    rangeLabel:SetTextColor(0.65,0.65,0.65,1); rangeLabel:SetText(TOTEM_RANGE.."y");
    rangeSlider:SetScript("OnValueChanged",function()
        local raw=rangeSlider:GetValue();
        local best,bestDist=RANGE_STOPS[1],math.abs(raw-RANGE_STOPS[1]);
        for i=2,table.getn(RANGE_STOPS) do
            local d=math.abs(raw-RANGE_STOPS[i]); if d<bestDist then best=RANGE_STOPS[i]; bestDist=d end
        end
        TOTEM_RANGE=best; SuperTotemDB.TOTEM_RANGE=best; rangeLabel:SetText(best.."y");
    end);
    function ST_RangeSlider_Refresh()
        rangeSlider:SetValue(TOTEM_RANGE-1); rangeSlider:SetValue(TOTEM_RANGE);
    end
    rangeSlider:SetScript("OnEnter",function()
        barHovered = true;
        tt:ClearLines(); tt:SetOwner(rangeSlider,"ANCHOR_RIGHT");
        tt:AddLine("Global totem range threshold",1,1,1);
        tt:AddLine("Totems beyond this distance will be re-dropped.",0.8,0.8,0.8); tt:Show();
    end);
    rangeSlider:SetScript("OnLeave",function() barHovered = false; tt:Hide() end);
    rangeSlider:SetAlpha(0);
    fadeControls[table.getn(fadeControls)+1] = rangeSlider;

    -- --------------------------------------------------------
    -- FIRE TOTEM RANGE SLIDER (Searing / Magma only)
    -- --------------------------------------------------------
    local FIRE_RANGE_STOPS = { 3, 5, 8, 10, 12, 15, 18, 20 };
    local fireRangeIniting = false;

    local fireRangeSlider=CreateFrame("Slider","BP_FireRangeSlider",bar);
    fireRangeSlider:SetOrientation("HORIZONTAL");
    fireRangeSlider:SetWidth(SLIDER_W); fireRangeSlider:SetHeight(SLIDER_H);
    fireRangeSlider:SetPoint("TOPLEFT",rangeSlider,"BOTTOMLEFT",0,6);
    fireRangeSlider:SetMinMaxValues(3,20); fireRangeSlider:SetValueStep(1);
    fireRangeSlider:SetBackdrop({ bgFile="Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile="Interface\\Buttons\\UI-SliderBar-Border", tile=true, tileSize=8, edgeSize=8,
        insets={left=3,right=3,top=6,bottom=6} });
    local fThumb=fireRangeSlider:CreateTexture(nil,"OVERLAY");
    fThumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal");
    fThumb:SetWidth(14); fThumb:SetHeight(14); fireRangeSlider:SetThumbTexture(fThumb);
    local fireRangeLabel=fireRangeSlider:CreateFontString(nil,"OVERLAY");
    fireRangeLabel:SetFont("Fonts\\FRIZQT__.TTF",8,"OUTLINE");
    fireRangeLabel:SetPoint("CENTER",fireRangeSlider,"CENTER",0,0);
    fireRangeLabel:SetTextColor(1.0,0.55,0.15,1);

    local function RefreshFireRangeSlider()
        local cur=settings.FIRE_TOTEM;
        if cur=="Searing Totem" or cur=="Magma Totem" then
            local range=TOTEM_RANGE_OVERRIDE[cur] or (cur=="Searing Totem" and 20 or 8);
            fireRangeIniting=true;
            fireRangeSlider:SetValue(range-1); fireRangeSlider:SetValue(range);
            fireRangeIniting=false;
            fireRangeLabel:SetText((cur=="Searing Totem" and "Sear: " or "Magma: ")..range.."y");
            fireRangeSlider:Show();
        else
            fireRangeSlider:Hide();
        end
    end
    function ST_TotemBar_RefreshFireSlider() RefreshFireRangeSlider() end

    fireRangeSlider:SetScript("OnValueChanged",function()
        if fireRangeIniting then return end
        local raw=fireRangeSlider:GetValue();
        local best,bestDist=FIRE_RANGE_STOPS[1],math.abs(raw-FIRE_RANGE_STOPS[1]);
        for i=2,table.getn(FIRE_RANGE_STOPS) do
            local d=math.abs(raw-FIRE_RANGE_STOPS[i]); if d<bestDist then best=FIRE_RANGE_STOPS[i]; bestDist=d end
        end
        local cur=settings.FIRE_TOTEM;
        if cur=="Searing Totem" or cur=="Magma Totem" then
            TOTEM_RANGE_OVERRIDE[cur]=best;
            if cur=="Searing Totem" then SuperTotemDB.SEARING_RANGE=best
            else                         SuperTotemDB.MAGMA_RANGE=best end
            fireRangeLabel:SetText((cur=="Searing Totem" and "Sear: " or "Magma: ")..best.."y");
        end
    end);
    fireRangeSlider:SetScript("OnEnter",function()
        barHovered = true;
        tt:ClearLines(); tt:SetOwner(fireRangeSlider,"ANCHOR_RIGHT");
        tt:AddLine("Range override: "..(settings.FIRE_TOTEM or "fire totem"),1,1,1);
        tt:AddLine("Totem will be re-dropped beyond this distance.",0.8,0.8,0.8); tt:Show();
    end);
    fireRangeSlider:SetScript("OnLeave",function() barHovered = false; tt:Hide() end);
    fireRangeSlider:Hide();
    fireRangeSlider:SetAlpha(0);
    fadeControls[table.getn(fadeControls)+1] = fireRangeSlider;

    bar:SetScript("OnShow",function()
        rangeSlider:SetValue(TOTEM_RANGE-1); rangeSlider:SetValue(TOTEM_RANGE);
        RefreshFireRangeSlider();
    end);

    -- Deferred thumb nudge for when bar is visible at load
    local thumbFrame=CreateFrame("Frame"); local thumbElapsed=0;
    thumbFrame:SetScript("OnUpdate",function()
        thumbElapsed=thumbElapsed+arg1;
        if thumbElapsed>=0.05 then
            thumbFrame:SetScript("OnUpdate",nil);
            rangeSlider:SetValue(TOTEM_RANGE-1); rangeSlider:SetValue(TOTEM_RANGE);
            RefreshFireRangeSlider();
        end
    end);

    RefreshFireRangeSlider();
    DEFAULT_CHAT_FRAME:AddMessage("SuperTotem: /stmenu ready.");
end