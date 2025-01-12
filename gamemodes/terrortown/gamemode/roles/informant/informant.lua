AddCSLuaFile()

local hook = hook
local IsValid = IsValid
local pairs = pairs

local GetAllPlayers = player.GetAll

-------------
-- CONVARS --
-------------

local informant_share_scans = CreateConVar("ttt_informant_share_scans", "1")
local informant_can_scan_jesters = CreateConVar("ttt_informant_can_scan_jesters", "0")
local informant_can_scan_glitches = CreateConVar("ttt_informant_can_scan_glitches", "0")

hook.Add("TTTSyncGlobals", "Informant_TTTSyncGlobals", function()
    SetGlobalBool("ttt_informant_share_scans", informant_share_scans:GetBool())
    SetGlobalBool("ttt_informant_can_scan_jesters", informant_can_scan_jesters:GetBool())
    SetGlobalBool("ttt_informant_can_scan_glitches", informant_can_scan_glitches:GetBool())
end)

------------------
-- ROLE WEAPONS --
------------------

-- Only allow the informant to pick up informant-specific weapons
hook.Add("PlayerCanPickupWeapon", "Informant_Weapons_PlayerCanPickupWeapon", function(ply, wep)
    if not IsValid(wep) or not IsValid(ply) then return end
    if ply:IsSpec() then return false end

    if wep:GetClass() == "weapon_inf_scanner" then
        return ply:IsInformant()
    end
end)

----------------
-- ROLE STATE --
----------------

local function HasInformant()
    for _, v in ipairs(GetAllPlayers()) do
        if v:IsInformant() then
            return true
        end
    end
    return false
end

local function SetDefaultScanState(ply)
    if ply:IsDetectiveTeam() then
        -- If the detective's role is not known, only skip the team scan
        if GetConVar("ttt_detective_hide_special_mode"):GetInt() >= SPECIAL_DETECTIVE_HIDE_FOR_ALL then
            ply:SetNWInt("TTTInformantScanStage", INFORMANT_SCANNED_TEAM)
        -- Otherwise skip the team and role scan
        else
            ply:SetNWInt("TTTInformantScanStage", INFORMANT_SCANNED_ROLE)
        end
    -- Handle traitor logic specially so we don't expose roles when there is a glitch
    elseif (ply:IsTraitorTeam() and not ply:IsInformant()) or ply:IsGlitch() then
        if GetGlobalBool("ttt_glitch_round", false) then
            ply:SetNWInt("TTTInformantScanStage", INFORMANT_SCANNED_TEAM)
        else
            ply:SetNWInt("TTTInformantScanStage", INFORMANT_SCANNED_ROLE)
        end
    -- Skip the team scanning stage for any role whose team is already known by a traitor
    elseif ply:IsJesterTeam() then
        ply:SetNWInt("TTTInformantScanStage", INFORMANT_SCANNED_TEAM)
    else
        ply:SetNWInt("TTTInformantScanStage", INFORMANT_UNSCANNED)
    end
end

hook.Add("TTTBeginRound", "Informant_TTTBeginRound", function()
    if not HasInformant() then return end

    for _, v in pairs(GetAllPlayers()) do
        SetDefaultScanState(v)
    end
end)

------------------
-- ROLE CHANGES --
------------------

hook.Add("TTTPlayerRoleChanged", "Informant_TTTPlayerRoleChanged", function(ply, oldRole, newRole)
    if oldRole == newRole then return end
    if GetRoundState() ~= ROUND_ACTIVE then return end
    if not HasInformant() then return end

    if ply:GetNWInt("TTTInformantScanStage", INFORMANT_UNSCANNED) > INFORMANT_UNSCANNED then
        local share = GetGlobalBool("ttt_informant_share_scans", true)
        for _, v in pairs(GetAllPlayers()) do
            if v:IsActiveInformant() then
                v:PrintMessage(HUD_PRINTTALK, ply:Nick() .. " has changed roles. You will need to rescan them.")
            elseif v:IsActiveTraitorTeam() and share then
                v:PrintMessage(HUD_PRINTTALK, ply:Nick() .. " has changed roles. The " .. ROLE_STRINGS[ROLE_INFORMANT] .. " will need to rescan them.")
            end
        end
    end

    SetDefaultScanState(ply)
end)