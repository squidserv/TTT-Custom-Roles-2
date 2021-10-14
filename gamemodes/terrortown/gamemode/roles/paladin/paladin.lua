AddCSLuaFile()

-------------
-- CONVARS --
-------------

CreateConVar("ttt_paladin_aura_radius", "5")
CreateConVar("ttt_paladin_damage_reduction", "0.3")
CreateConVar("ttt_paladin_heal_rate", "1")
CreateConVar("ttt_paladin_protect_self", "0")
CreateConVar("ttt_paladin_heal_self", "1")

hook.Add("TTTSyncGlobals", "Paladin_TTTSyncGlobals", function()
    SetGlobalFloat("ttt_paladin_aura_radius", GetConVar("ttt_paladin_aura_radius"):GetInt() * 52.49)
    SetGlobalBool("ttt_paladin_protect_self", GetConVar("ttt_paladin_protect_self"):GetBool())
    SetGlobalBool("ttt_paladin_heal_self", GetConVar("ttt_paladin_heal_self"):GetBool())
end)

-------------------
-- ROLE FEATURES --
-------------------

hook.Add("TTTBeginRound", "Paladin_RoleFeatures_TTTBeginRound", function()
    local paladinHeal = GetConVar("ttt_paladin_heal_rate"):GetInt()
    local paladinHealSelf = GetConVar("ttt_paladin_heal_self"):GetBool()
    local paladinRadius = GetGlobalFloat("ttt_paladin_aura_radius", 262.45)
    timer.Create("paladinheal", 1, 0, function()
        for _, p in pairs(player.GetAll()) do
            if p:IsActivePaladin() then
                for _, v in pairs(player.GetAll()) do
                    if v:IsActive() and (not v:IsPaladin() or paladinHealSelf) and v:GetPos():Distance(p:GetPos()) <= paladinRadius and v:Health() < v:GetMaxHealth() then
                        local health = math.min(v:GetMaxHealth(), v:Health() + paladinHeal)
                        v:SetHealth(health)
                    end
                end
            end
        end
    end)
end)

hook.Add("TTTEndRound", "Paladin_RoleFeatures_TTTEndRound", function()
    if timer.Exists("paladinheal") then timer.Remove("paladinheal") end
end)

------------------
-- DAMAGE SCALE --
------------------

hook.Add("ScalePlayerDamage", "Paladin_ScalePlayerDamage", function(ply, hitgroup, dmginfo)
    local att = dmginfo:GetAttacker()
    if IsPlayer(att) and GetRoundState() >= ROUND_ACTIVE then
        if not ply:IsPaladin() or GetConVar("ttt_paladin_protect_self"):GetBool() then
            local withPaladin = false
            local radius = GetGlobalFloat("ttt_paladin_aura_radius", 262.45)
            for _, v in pairs(player.GetAll()) do
                if v:IsPaladin() and v:GetPos():Distance(ply:GetPos()) <= radius then
                    withPaladin = true
                    break
                end
            end
            if withPaladin and not att:IsPaladin() then
                local reduction = GetConVar("ttt_paladin_damage_reduction"):GetFloat()
                dmginfo:ScaleDamage(1 - reduction)
            end
        end
    end
end)