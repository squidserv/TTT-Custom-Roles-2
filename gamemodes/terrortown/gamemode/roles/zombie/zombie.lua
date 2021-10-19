AddCSLuaFile()

local plymeta = FindMetaTable("Player")

-------------
-- CONVARS --
-------------

CreateConVar("ttt_zombie_round_chance", 0.1)
local zombies_are_monsters = CreateConVar("ttt_zombies_are_monsters", "0")
local zombies_are_traitors = CreateConVar("ttt_zombies_are_traitors", "0")
local zombie_show_target_icon = CreateConVar("ttt_zombie_show_target_icon", "0")
local zombie_damage_penalty = CreateConVar("ttt_zombie_damage_penalty", "0.5")
local zombie_damage_reduction = CreateConVar("ttt_zombie_damage_reduction", "0")
local zombie_prime_only_weapons = CreateConVar("ttt_zombie_prime_only_weapons", "1")
local zombie_prime_speed_bonus = CreateConVar("ttt_zombie_prime_speed_bonus", "0.35")
local zombie_thrall_speed_bonus = CreateConVar("ttt_zombie_thrall_speed_bonus", "0.15")
local zombie_vision_enable = CreateConVar("ttt_zombie_vision_enable", "0")

hook.Add("TTTSyncGlobals", "Zombie_TTTSyncGlobals", function()
    SetGlobalBool("ttt_zombies_are_monsters", zombies_are_monsters:GetBool())
    SetGlobalBool("ttt_zombies_are_traitors", zombies_are_traitors:GetBool())
    SetGlobalBool("ttt_zombie_show_target_icon", zombie_show_target_icon:GetBool())
    SetGlobalBool("ttt_zombie_vision_enable", zombie_vision_enable:GetBool())
    SetGlobalFloat("ttt_zombie_prime_speed_bonus", zombie_prime_speed_bonus:GetFloat())
    SetGlobalFloat("ttt_zombie_thrall_speed_bonus", zombie_thrall_speed_bonus:GetFloat())
end)

-----------
-- PRIME --
-----------

function plymeta:SetZombiePrime(p) self:SetNWBool("zombie_prime", p) end

-----------------
-- ROLE STATUS --
-----------------

hook.Add("TTTBeginRound", "Zombie_RoleFeatures_PrepareRound", function()
    for _, v in pairs(player.GetAll()) do
        if v:IsZombie() then
            v:SetZombiePrime(true)
        end
    end
end)

hook.Add("TTTPrepareRound", "Zombie_RoleFeatures_PrepareRound", function()
    for _, v in pairs(player.GetAll()) do
        v:SetNWBool("IsZombifying", false)
        -- Keep previous naming scheme for backwards compatibility
        v:SetNWBool("zombie_prime", false)
    end
end)

ROLE_MOVE_ROLE_STATE[ROLE_ZOMBIE] = function(ply, target, keep_on_source)
    if ply:IsZombiePrime() then
        if not keep_on_source then ply:SetZombiePrime(false) end
        target:SetZombiePrime(true)
    end
end

----------------
-- WIN CHECKS --
----------------

hook.Add("TTTCheckForWin", "Zombie_TTTCheckForWin", function()
    -- Only run the win check if the zombies win by themselves (or with the Mad Scientist)
    if not INDEPENDENT_ROLES[ROLE_ZOMBIE] then return end

    local zombie_alive = false
    local other_alive = false
    for _, v in ipairs(player.GetAll()) do
        if v:Alive() and v:IsTerror() then
            if v:IsZombie() or v:IsMadScientist() then
                zombie_alive = true
            elseif not v:ShouldActLikeJester() then
                other_alive = true
            end
        end
    end

    if zombie_alive and not other_alive then
        return WIN_ZOMBIE
    elseif zombie_alive then
        return WIN_NONE
    end
end)

hook.Add("TTTPrintResultMessage", "Zombie_TTTPrintResultMessage", function(type)
    if type == WIN_ZOMBIE then
        local plural = ROLE_STRINGS_PLURAL[ROLE_ZOMBIE]
        LANG.Msg("win_zombies", { role = plural })
        ServerLog("Result: " .. plural .. " win.\n")
    end
end)

-----------
-- KARMA --
-----------

-- Reduce karma if a zombie hurts or kills an ally
hook.Add("TTTKarmaShouldGivePenalty", "Zombie_TTTKarmaShouldGivePenalty", function(attacker, victim)
    if attacker:IsZombie() then
        return victim:IsZombieAlly()
    end
end)

------------
-- DAMAGE --
------------

hook.Add("ScalePlayerDamage", "Zombie_ScalePlayerDamage", function(ply, hitgroup, dmginfo)
    local att = dmginfo:GetAttacker()
    -- Only apply damage scaling after the round starts
    if IsPlayer(att) and GetRoundState() >= ROUND_ACTIVE then
        -- Monsters take less bullet damage
        if dmginfo:IsBulletDamage() and ply:IsZombie() then
            local reduction = zombie_damage_reduction:GetFloat()
            dmginfo:ScaleDamage(1 - reduction)
        end

        -- Zombies do less damage when using non-claw weapons
        if att:IsZombie() and att:GetActiveWeapon():GetClass() ~= "weapon_zom_claws" then
            local penalty = zombie_damage_penalty:GetFloat()
            dmginfo:ScaleDamage(1 - penalty)
        end
    end
end)

hook.Add("EntityTakeDamage", "Zombie_EntityTakeDamage", function(ent, dmginfo)
    if not IsValid(ent) then return end

    local att = dmginfo:GetAttacker()
    if GetRoundState() >= ROUND_ACTIVE and ent:IsPlayer() then
        -- No zombie team killing
        -- This can be funny, but it can also be used by frustrated players who didn't appreciate being zombified
        if ent:IsZombie() and IsPlayer(att) and att:IsZombieAlly() then
            dmginfo:ScaleDamage(0)
            dmginfo:SetDamage(0)
        end
    end
end)

-- Zombies don't take fall damage
hook.Add("OnPlayerHitGround", "Zombie_OnPlayerHitGround", function(ply, in_water, on_floater, speed)
    if ply:IsZombie() and GetRoundState() >= ROUND_ACTIVE then
        return true
    end
end)

------------------
-- ROLE WEAPONS --
------------------

-- Make sure the vampire keeps their appropriate weapons
hook.Add("TTTPlayerAliveThink", "Zombie_TTTPlayerAliveThink", function(ply)
    if not IsValid(ply) or ply:IsSpec() or GetRoundState() ~= ROUND_ACTIVE then return end

    if ply:IsZombie() then
        if ply.GetActiveWeapon and IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() == "weapon_zom_claws" then
            ply:SetColor(Color(70, 100, 25, 255))
            ply:SetRenderMode(RENDERMODE_NORMAL)
        elseif ply:GetRenderMode() ~= RENDERMODE_TRANSALPHA then
            ply:SetColor(Color(255, 255, 255, 255))
            ply:SetRenderMode(RENDERMODE_TRANSALPHA)
        end

        -- Strip all non-claw weapons for non-prime zombies if that feature is enabled
        -- Strip individual weapons instead of all because otherwise the player will have their claws added and removed constantly
        if zombie_prime_only_weapons:GetBool() and not ply:GetZombiePrime() then
            local weapons = ply:GetWeapons()
            for _, v in pairs(weapons) do
                local weapclass = WEPS.GetClass(v)
                if weapclass ~= "weapon_zom_claws" then
                    ply:StripWeapon(weapclass)
                end
            end
        end

        -- If this zombie doesn't have claws, give them claws
        if not ply:HasWeapon("weapon_zom_claws") then
            ply:Give("weapon_zom_claws")
        end
    elseif ply:GetRenderMode() ~= RENDERMODE_TRANSALPHA then
        ply:SetColor(Color(255, 255, 255, 255))
        ply:SetRenderMode(RENDERMODE_TRANSALPHA)
    end
end)

-- Handle role weapon assignment
hook.Add("PlayerLoadout", "Zombie_PlayerLoadout", function(ply)
    if not IsPlayer(ply) or not ply:Alive() or ply:IsSpec() or not ply:IsZombie() or GetRoundState() ~= ROUND_ACTIVE then return end

    if not ply:HasWeapon("weapon_zom_claws") then
        ply:Give("weapon_zom_claws")
    end
end)

-- Only allow the zombie to pick up zombie-specific weapons
hook.Add("PlayerCanPickupWeapon", "Zombie_Weapons_PlayerCanPickupWeapon", function(ply, wep)
    if not IsValid(wep) or not IsValid(ply) then return end
    if ply:IsSpec() then return false end

    if wep:GetClass() == "weapon_zom_claws" then
        return ply:IsZombie()
    end

    if zombie_prime_only_weapons:GetBool() and ply:IsZombie() and not ply:IsZombiePrime() and GetRoundState() == ROUND_ACTIVE then
        return false
    end
end)