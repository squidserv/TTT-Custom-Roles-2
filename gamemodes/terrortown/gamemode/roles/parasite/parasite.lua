AddCSLuaFile()

local hook = hook
local ipairs = ipairs
local IsValid = IsValid
local net = net
local pairs = pairs
local player = player
local table = table
local timer = timer
local util = util

local GetAllPlayers = player.GetAll

util.AddNetworkString("TTT_ParasiteInfect")

-------------
-- CONVARS --
-------------

local parasite_infection_time = CreateConVar("ttt_parasite_infection_time", 45, FCVAR_NONE, "The time it takes in seconds for the parasite to fully infect someone", 0, 300)
local parasite_infection_transfer = CreateConVar("ttt_parasite_infection_transfer", 0)
local parasite_infection_transfer_reset = CreateConVar("ttt_parasite_infection_transfer_reset", 1)
local parasite_infection_suicide_mode = CreateConVar("ttt_parasite_infection_suicide_mode", 0, FCVAR_NONE, "The way to handle when a player infected by the parasite kills themselves. 0 - Do nothing. 1 - Respawn the parasite. 2 - Respawn the parasite ONLY IF the infected player killed themselves with a console command like \"kill\"", 0, 2)
local parasite_respawn_mode = CreateConVar("ttt_parasite_respawn_mode", 0, FCVAR_NONE, "The way in which the parasite respawns. 0 - Take over host. 1 - Respawn at the parasite's body. 2 - Respawn at a random location.", 0, 2)
local parasite_respawn_health = CreateConVar("ttt_parasite_respawn_health", 100, FCVAR_NONE, "The health on which the parasite respawns", 0, 100)
local parasite_announce_infection = CreateConVar("ttt_parasite_announce_infection", 0)

hook.Add("TTTSyncGlobals", "Parasite_TTTSyncGlobals", function()
    SetGlobalInt("ttt_parasite_infection_time", parasite_infection_time:GetInt())
    SetGlobalBool("ttt_parasite_enabled", GetConVar("ttt_parasite_enabled"):GetBool())
end)

--------------
-- HAUNTING --
--------------

local deadParasites = {}
hook.Add("TTTPrepareRound", "Parasite_TTTPrepareRound", function()
    for _, v in pairs(GetAllPlayers()) do
        v:SetNWBool("ParasiteInfected", false)
        v:SetNWBool("ParasiteInfecting", false)
        v:SetNWString("ParasiteInfectingTarget", nil)
        v:SetNWInt("ParasiteInfectionProgress", 0)
        timer.Remove(v:Nick() .. "ParasiteInfectionProgress")
        timer.Remove(v:Nick() .. "ParasiteInfectingSpectate")
    end
    deadParasites = {}
end)

local function ResetPlayer(ply)
    -- If this player is infecting someone else, make sure to clear them of the infection too
    if ply:GetNWBool("ParasiteInfecting", false) then
        local sid = ply:GetNWString("ParasiteInfectingTarget", nil)
        if sid then
            local target = player.GetBySteamID64(sid)
            if IsPlayer(target) then
                target:SetNWBool("ParasiteInfected", false)
            end
        end
    end
    ply:SetNWBool("ParasiteInfecting", false)
    ply:SetNWString("ParasiteInfectingTarget", nil)
    ply:SetNWInt("ParasiteInfectionProgress", 0)
    timer.Remove(ply:Nick() .. "ParasiteInfectionProgress")
    timer.Remove(ply:Nick() .. "ParasiteInfectingSpectate")
end

hook.Add("TTTPlayerRoleChanged", "Parasite_TTTPlayerRoleChanged", function(ply, oldRole, newRole)
    if oldRole == ROLE_PARASITE and oldRole ~= newRole then
        ResetPlayer(ply)
    end
end)

hook.Add("TTTPlayerSpawnForRound", "Parasite_TTTPlayerSpawnForRound", function(ply, dead_only)
    ResetPlayer(ply)
end)

-- Un-haunt the device owner if they used their device on the parasite
hook.Add("TTTPlayerDefibRoleChange", "Parasite_TTTPlayerDefibRoleChange", function(ply, tgt)
    if tgt:IsParasite() and tgt:GetNWString("ParasiteInfectingTarget", nil) == ply:SteamID64() then
        ply:SetNWBool("ParasiteInfected", false)
    end
end)

local function DoParasiteRespawnWithoutBody(parasite, hide_messages)
    if not hide_messages then
        parasite:PrintMessage(HUD_PRINTCENTER, "You have drained your host of energy and created a new body.")
    end
    -- Introduce a slight delay to prevent player getting stuck as a spectator
    timer.Create(parasite:Nick() .. "ParasiteRespawn", 0.1, 1, function()
        local body = parasite.server_ragdoll or parasite:GetRagdollEntity()
        parasite:SpawnForRound(true)
        SafeRemoveEntity(body)

        local health = parasite_respawn_health:GetInt()
        parasite:SetHealth(health)
    end)
end

local function DoParasiteRespawn(parasite, attacker, hide_messages)
    if parasite:IsParasite() and not parasite:Alive() then
        attacker:SetNWBool("ParasiteInfected", false)
        parasite:SetNWBool("ParasiteInfecting", false)
        parasite:SetNWString("ParasiteInfectingTarget", nil)
        parasite:SetNWInt("ParasiteInfectionProgress", 0)
        timer.Remove(parasite:Nick() .. "ParasiteInfectionProgress")
        timer.Remove(parasite:Nick() .. "ParasiteInfectingSpectate")

        local parasiteBody = parasite.server_ragdoll or parasite:GetRagdollEntity()

        local respawnMode = parasite_respawn_mode:GetInt()
        if respawnMode == PARASITE_RESPAWN_HOST then
            if not hide_messages then
                parasite:PrintMessage(HUD_PRINTCENTER, "You have taken control of your host.")
            end

            parasite:SpawnForRound(true)
            parasite:SetPos(attacker:GetPos())
            parasite:SetEyeAngles(Angle(0, attacker:GetAngles().y, 0))

            local weaps = attacker:GetWeapons()
            local currentWeapon = "weapon_zm_improvised"
            if attacker:GetActiveWeapon() then
                currentWeapon = WEPS.GetClass(attacker:GetActiveWeapon())
            end
            attacker:StripAll()
            parasite:StripAll()
            for _, v in ipairs(weaps) do
                local wep_class = WEPS.GetClass(v)
                parasite:Give(wep_class)
            end
            parasite:SelectWeapon(currentWeapon)
        elseif respawnMode == PARASITE_RESPAWN_BODY then
            if IsValid(parasiteBody) then
                if not hide_messages then
                    parasite:PrintMessage(HUD_PRINTCENTER, "You have drained your host of energy and regenerated your old body.")
                end
                parasite:SpawnForRound(true)
                parasite:SetPos(FindRespawnLocation(parasiteBody:GetPos()) or parasiteBody:GetPos())
                parasite:SetEyeAngles(Angle(0, parasiteBody:GetAngles().y, 0))
            else
                DoParasiteRespawnWithoutBody(parasite, hide_messages)
            end
        elseif respawnMode == PARASITE_RESPAWN_RANDOM then
            DoParasiteRespawnWithoutBody(parasite, hide_messages)
        end

        local health = parasite_respawn_health:GetInt()
        parasite:SetHealth(health)
        SafeRemoveEntity(parasiteBody)
        if attacker:Alive() then
            attacker:Kill()
        end
        if not hide_messages then
            attacker:PrintMessage(HUD_PRINTCENTER, "Your parasite has drained you of your energy.")
            attacker:PrintMessage(HUD_PRINTTALK, "Your parasite has drained you of your energy.")
        end
    end
end

local function ShouldParasiteRespawnBySuicide(mode, victim, attacker, dmginfo)
    -- Any cause of suicide
    if mode == PARASITE_SUICIDE_RESPAWN_ALL then
        return victim == attacker
    -- Only if they killed themselves via a command (in this case they would be the inflictor)
    elseif mode == PARASITE_SUICIDE_RESPAWN_CONSOLE then
        local inflictor = dmginfo:GetInflictor()
        return victim == attacker and IsValid(inflictor) and victim == inflictor
    end

    return false
end

local function HandleParasiteInfection(attacker, victim, keep_progress)
    attacker:SetNWBool("ParasiteInfected", true)
    victim:SetNWBool("ParasiteInfecting", true)
    victim:SetNWString("ParasiteInfectingTarget", attacker:SteamID64())
    if not keep_progress then
        victim:SetNWInt("ParasiteInfectionProgress", 0)
    end
    timer.Create(victim:Nick() .. "ParasiteInfectionProgress", 1, 0, function()
        -- Make sure the victim is still in the correct spectate mode
        local spec_mode = victim:GetObserverMode()
        if spec_mode ~= OBS_MODE_CHASE and spec_mode ~= OBS_MODE_IN_EYE then
            victim:Spectate(OBS_MODE_CHASE)
        end

        local progress = victim:GetNWInt("ParasiteInfectionProgress", 0) + 1
        if progress >= parasite_infection_time:GetInt() then -- respawn the parasite
            DoParasiteRespawn(victim, attacker)
        else
            victim:SetNWInt("ParasiteInfectionProgress", progress)
        end
    end)

    -- Lock the victim's view on their attacker
    timer.Create(victim:Nick() .. "ParasiteInfectingSpectate", 1, 1, function()
        victim:SetRagdollSpec(false)
        victim:Spectate(OBS_MODE_CHASE)
        victim:SpectateEntity(attacker)
    end)
end

hook.Add("PlayerDeath", "Parasite_PlayerDeath", function(victim, infl, attacker)
    local valid_kill = IsPlayer(attacker) and attacker ~= victim and GetRoundState() == ROUND_ACTIVE
    if valid_kill and victim:IsParasite() and not victim:IsZombifying() then
        HandleParasiteInfection(attacker, victim)

        -- Delay this message so the player can see the target update message
        if parasite_announce_infection:GetBool() then
            if attacker:ShouldDelayAnnouncements() then
                timer.Simple(3, function()
                    attacker:PrintMessage(HUD_PRINTCENTER, "You have been infected with a parasite.")
                end)
            else
                attacker:PrintMessage(HUD_PRINTCENTER, "You have been infected with a parasite.")
            end
        end
        victim:PrintMessage(HUD_PRINTCENTER, "Your attacker has been infected.")

        local sid = victim:SteamID64()
        -- Keep track of who killed this parasite
        deadParasites[sid] = {player = victim, attacker = attacker:SteamID64()}

        net.Start("TTT_ParasiteInfect")
        net.WriteString(victim:Nick())
        net.WriteString(attacker:Nick())
        net.Broadcast()
    end
end)

hook.Add("TTTSpectatorHUDKeyPress", "Parasite_TTTSpectatorHUDKeyPress", function(ply, tgt, powers)
    if ply:GetNWBool("ParasiteInfecting", false) then
        return true
    end
end)

-------------
-- RESPAWN --
-------------

hook.Add("DoPlayerDeath", "Parasite_DoPlayerDeath", function(ply, attacker, dmginfo)
    if ply:IsSpec() then return end

    if ply:GetNWBool("ParasiteInfected", false) then
        local parasiteUsers = table.GetKeys(deadParasites)
        for _, key in pairs(parasiteUsers) do
            local parasite = deadParasites[key]
            if parasite.attacker == ply:SteamID64() and IsValid(parasite.player) then
                local deadParasite = parasite.player
                local parasiteDead = deadParasite:IsParasite() and not deadParasite:Alive()
                local transfer = parasite_infection_transfer:GetBool()
                local suicideMode = parasite_infection_suicide_mode:GetInt()
                -- Transfer the infection to the new attacker if there is one, they are alive, the parasite is still alive, and the transfer feature is enabled
                if IsPlayer(attacker) and attacker:Alive() and parasiteDead and transfer then
                    deadParasites[key].attacker = attacker:SteamID64()
                    HandleParasiteInfection(attacker, deadParasite, not parasite_infection_transfer_reset:GetBool())
                    deadParasite:PrintMessage(HUD_PRINTCENTER, "Your host has been killed and your infection has spread to their killer.")
                    net.Start("TTT_ParasiteInfect")
                    net.WriteString(deadParasite:Nick())
                    net.WriteString(attacker:Nick())
                    net.Broadcast()
                elseif suicideMode > PARASITE_SUICIDE_NONE and ShouldParasiteRespawnBySuicide(suicideMode, ply, attacker, dmginfo) then
                    deadParasite:PrintMessage(HUD_PRINTCENTER, "Your host has killed themselves, allowing your infection to take over.")
                    DoParasiteRespawn(deadParasite, attacker, true)
                else
                    deadParasite:SetNWBool("ParasiteInfecting", false)
                    deadParasite:SetNWString("ParasiteInfectingTarget", nil)
                    deadParasite:SetNWInt("ParasiteInfectionProgress", 0)
                    timer.Remove(deadParasite:Nick() .. "ParasiteInfectionProgress")
                    timer.Remove(deadParasite:Nick() .. "ParasiteInfectingSpectate")
                    if parasiteDead then
                        deadParasite:PrintMessage(HUD_PRINTCENTER, "Your host has died.")
                    end
                end
            end
        end

        ply:SetNWBool("ParasiteInfected", false)
    end
end)