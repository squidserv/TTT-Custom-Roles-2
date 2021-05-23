---- Traitor equipment menu

local GetTranslation = LANG.GetTranslation
local GetPTranslation = LANG.GetParamTranslation

-- create ClientConVars
local numColsVar = CreateClientConVar("ttt_bem_cols", 4, true, false, "Sets the number of columns in the Traitor/Detective menu's item list.")
local numRowsVar = CreateClientConVar("ttt_bem_rows", 5, true, false, "Sets the number of rows in the Traitor/Detective menu's item list.")
local itemSizeVar = CreateClientConVar("ttt_bem_size", 64, true, false, "Sets the item size in the Traitor/Detective menu's item list.")
local showCustomVar = CreateClientConVar("ttt_bem_marker_custom", 1, true, false, "Should custom items get a marker?")
local showFavoriteVar = CreateClientConVar("ttt_bem_marker_fav", 1, true, false, "Should favorite items get a marker?")
local showSlotVar = CreateClientConVar("ttt_bem_marker_slot", 1, true, false, "Should items get a slot-marker?")

-- Buyable weapons are loaded automatically. Buyable items are defined in
-- equip_items_shd.lua

-- override preexisting weapons
local canBuyList = {
    weapon_ttt_health_station = {ROLE_TRAITOR, ROLE_HYPNOTIST, ROLE_IMPERSONATOR},
    weapon_vadim_defib = {ROLE_HYPNOTIST, ROLE_IMPERSONATOR}
}

local Equipment = nil
function GetEquipmentForRole(role, extra)
    -- start with all the non-weapon goodies
    local tbl = table.Copy(EquipmentItems)

    -- find buyable weapons to load info from
    for k, v in pairs(weapons.GetList()) do
        if v and (v.CanBuy or canBuyList[WEPS.GetClass(v)]) then
            local data = v.EquipMenuData or {}
            local base = {
                id = WEPS.GetClass(v),
                name = v.PrintName or "Unnamed",
                limited = v.LimitedStock,
                kind = v.Kind or WEAPON_NONE,
                slot = (v.Slot or 0) + 1,
                material = v.Icon or "vgui/ttt/icon_id",
                -- the below should be specified in EquipMenuData, in which case
                -- these values are overwritten
                type = "Type not specified",
                model = "models/weapons/w_bugbait.mdl",
                desc = "No description specified."
            };

            -- Force material to nil so that model key is used when we are
            -- explicitly told to do so (ie. material is false rather than nil).
            if data.modelicon then
                base.material = nil
            end

            table.Merge(base, data)

            -- add this buyable weapon to all relevant equipment tables
            if v.CanBuy then
                for _, r in pairs(v.CanBuy) do
                    table.insert(tbl[r], base)
                    if extra then
                        if r == ROLE_DETECTIVE and (role == ROLE_DEPUTY or role == ROLE_IMPERSONATOR) then
                            table.insert(tbl[role], base)
                        end
                    end
                end
            end

            if canBuyList[WEPS.GetClass(v)] then
                for _, r in pairs(canBuyList[WEPS.GetClass(v)]) do
                    if not table.HasValue(tbl[r], base) then
                        table.insert(tbl[r], base)
                    end
                end
            end
        end
    end

    -- mark custom items
    for r, is in pairs(tbl) do
        for _, i in pairs(is) do
            if i and i.id then
                i.custom = not table.HasValue(DefaultEquipment[r], i.id)
            end
        end
    end

    Equipment = tbl

    return Equipment and Equipment[role] or {}
end

local function ItemIsWeapon(item) return not tonumber(item.id) end
local function CanCarryWeapon(item) return LocalPlayer():CanCarryType(item.kind) end

local color_bad = Color(220, 60, 60, 255)
local color_good = Color(255, 255, 255, 255)

-- Creates tabel of labels showing the status of ordering prerequisites
local function PreqLabels(parent, x, y)
    local tbl = {}

    -- coins icon
    tbl.credits = vgui.Create("DLabel", parent)
    tbl.credits:SetPos(x, y)

    tbl.credits.img = vgui.Create("DImage", parent)
    tbl.credits.img:SetSize(32, 32)
    tbl.credits.img:CopyPos(tbl.credits)
    tbl.credits.img:MoveLeftOf(tbl.credits)
    tbl.credits.img:SetImage("vgui/ttt/equip/coin.png")

    tbl.credits.Check = function(s, sel)
        local credits = LocalPlayer():GetCredits()
        return credits > 0, " " .. credits, GetPTranslation("equip_cost", { num = credits })
    end

    -- carry icon
    tbl.owned = vgui.Create("DLabel", parent)
    tbl.owned:CopyPos(tbl.credits)
    tbl.owned:MoveRightOf(tbl.credits, y * 3)

    tbl.owned.img = vgui.Create("DImage", parent)
    tbl.owned.img:SetSize(32, 32)
    tbl.owned.img:CopyPos(tbl.owned)
    tbl.owned.img:MoveLeftOf(tbl.owned)
    tbl.owned.img:SetImage("vgui/ttt/equip/briefcase.png")

    tbl.owned.Check = function(s, sel)
        if ItemIsWeapon(sel) and (not CanCarryWeapon(sel)) then
            return false, "X", GetPTranslation("equip_carry_slot", { slot = sel.slot })
        elseif (not ItemIsWeapon(sel)) and LocalPlayer():HasEquipmentItem(sel.id) then
            return false, "X", GetTranslation("equip_carry_own")
        else
            return true, "✔", GetTranslation("equip_carry")
        end
    end

    -- stock icon
    tbl.bought = vgui.Create("DLabel", parent)
    tbl.bought:CopyPos(tbl.owned)
    tbl.bought:MoveRightOf(tbl.owned, y * 3)

    tbl.bought.img = vgui.Create("DImage", parent)
    tbl.bought.img:SetSize(32, 32)
    tbl.bought.img:CopyPos(tbl.bought)
    tbl.bought.img:MoveLeftOf(tbl.bought)
    tbl.bought.img:SetImage("vgui/ttt/equip/package.png")

    tbl.bought.Check = function(s, sel)
        if sel.limited and LocalPlayer():HasBought(tostring(sel.id)) then
            return false, "X", GetTranslation("equip_stock_deny")
        else
            return true, "✔", GetTranslation("equip_stock_ok")
        end
    end

    for k, pnl in pairs(tbl) do
        pnl:SetFont("DermaLarge")
    end

    return function(selected)
        local allow = true
        for k, pnl in pairs(tbl) do
            local result, text, tooltip = pnl:Check(selected)
            pnl:SetTextColor(result and color_good or color_bad)
            pnl:SetText(text)
            pnl:SizeToContents()
            pnl:SetTooltip(tooltip)
            pnl.img:SetImageColor(result and color_good or color_bad)
            pnl.img:SetTooltip(tooltip)
            allow = allow and result
        end
        return allow
    end
end

-- quick, very basic override of DPanelSelect
local PANEL = {}
local function DrawSelectedEquipment(pnl)
    surface.SetDrawColor(255, 200, 0, 255)
    surface.DrawOutlinedRect(0, 0, pnl:GetWide(), pnl:GetTall())
end

function PANEL:SelectPanel(pnl)
    self.BaseClass.SelectPanel(self, pnl)
    if pnl then
        pnl.PaintOver = DrawSelectedEquipment
    end
end
vgui.Register("EquipSelect", PANEL, "DPanelSelect")

local SafeTranslate = LANG.TryTranslation

local color_darkened = Color(255, 255, 255, 80)

local color_slot = {
    [ROLE_TRAITOR] = COLOR_TRAITOR,
    [ROLE_DETECTIVE] = COLOR_DETECTIVE,
    [ROLE_HYPNOTIST] = COLOR_SPECIAL_TRAITOR,
    [ROLE_DEPUTY] = COLOR_SPECIAL_INNOCENT,
    [ROLE_IMPERSONATOR] = COLOR_SPECIAL_TRAITOR
}

-- BEM helper functions

function CreateFavTable()
    if not sql.TableExists("ttt_bem_fav") then
        local query = "CREATE TABLE ttt_bem_fav (guid TEXT, role TEXT, weapon_id TEXT)"
        sql.Query(query)
    else
        print("ALREADY EXISTS")
    end
end

function AddFavorite(guid, role, weapon_id)
    local query = "INSERT INTO ttt_bem_fav VALUES('" .. guid .. "','" .. role .. "','" .. weapon_id .. "')"
    sql.Query(query)
end

function RemoveFavorite(guid, role, weapon_id)
    local query = "DELETE FROM ttt_bem_fav WHERE guid = '" .. guid .. "' AND role = '" .. role .. "' AND weapon_id = '" .. weapon_id .. "'"
    sql.Query(query)
end

function GetFavorites(guid, role)
    local query = "SELECT weapon_id FROM ttt_bem_fav WHERE guid = '" .. guid .. "' AND role = '" .. role .. "'"
    local result = sql.Query(query)
    return result
end

function IsFavorite(favorites, weapon_id)
    for _, value in pairs(favorites) do
        local dbid = value["weapon_id"]
        if (dbid == tostring(weapon_id)) then
            return true
        end
    end
    return false
end

-- Create the buy menu

local eqframe = nil
local function TraitorMenuPopup()
    local numCols = numColsVar:GetInt()
    local numRows = numRowsVar:GetInt()
    local itemSize = itemSizeVar:GetInt()

    -- margin
    local m = 5
    -- item list width
    local dlistw = ((itemSize + 2) * numCols) - 2 + 15
    local dlisth = ((itemSize + 2) * numRows) - 2 + 15
    -- right column width
    local diw = 270
    -- frame size
    local w = dlistw + diw + (m * 4)
    local h = dlisth + 75

    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:IsActiveSpecial() then
        return
    end

    -- Close any existing traitor menu
    if eqframe and IsValid(eqframe) then eqframe:Close() end

    local credits = ply:GetCredits()
    local can_order = credits > 0

    local dframe = vgui.Create("DFrame")

    dframe:SetSize(w, h)
    dframe:Center()
    dframe:SetTitle(GetTranslation("equip_title"))
    dframe:SetVisible(true)
    dframe:ShowCloseButton(true)
    dframe:SetMouseInputEnabled(true)
    dframe:SetDeleteOnClose(true)

    local m = 5

    local dsheet = vgui.Create("DPropertySheet", dframe)

    -- Add a callback when switching tabs
    local oldfunc = dsheet.SetActiveTab
    dsheet.SetActiveTab = function(self, new)
        if self.m_pActiveTab ~= new and self.OnTabChanged then
            self:OnTabChanged(self.m_pActiveTab, new)
        end
        oldfunc(self, new)
    end

    dsheet:SetPos(0, 0)
    dsheet:StretchToParent(m, m + 25, m, m)
    local padding = dsheet:GetPadding()

    local dequip = vgui.Create("DPanel", dsheet)
    dequip:SetPaintBackground(false)
    dequip:StretchToParent(padding, padding, padding, padding)

    -- Determine if we already have equipment
    local owned_ids = {}
    for _, wep in ipairs(ply:GetWeapons()) do
        if IsValid(wep) and wep:IsEquipment() then
            table.insert(owned_ids, wep:GetClass())
        end
    end

    -- Stick to one value for no equipment
    if #owned_ids == 0 then
        owned_ids = nil
    end

    --- Construct icon listing
    local dlist = vgui.Create("EquipSelect", dequip)
    dlist:SetPos(0, 0)
    dlist:SetSize(dlistw, dlisth)
    dlist:EnableVerticalScrollbar(true)
    dlist:EnableHorizontal(true)

    local items = GetEquipmentForRole(ply:GetRole(), ply:GetNWBool("HasPromotion", false))

    local to_select = nil

    -- temp table for sorting
    local paneltablefav = {}
    local paneltable = {}
    for i = 1, 9 do
        paneltablefav[i] = {}
        paneltable[i] = {}
    end

    for k, item in pairs(items) do
        local ic = nil

        -- Create icon panel
        if item.material then
            ic = vgui.Create("LayeredIcon", dlist)

            if item.custom and showCustomVar:GetBool() then
                -- Custom marker icon
                local marker = vgui.Create("DImage")
                marker:SetImage("vgui/ttt/custom_marker")
                marker.PerformLayout = function(s)
                    s:AlignBottom(2)
                    s:AlignRight(2)
                    s:SetSize(16, 16)
                end
                marker:SetTooltip(GetTranslation("equip_custom"))

                ic:AddLayer(marker)

                ic:EnableMousePassthrough(marker)
            end

            -- Favorites marker icon
            ic.favorite = false
            local favorites = GetFavorites(ply:SteamID(), ply:GetRole())
            if favorites then
                if IsFavorite(favorites, item.id) then
                    ic.favorite = true
                    if showFavoriteVar:GetBool() then
                        local star = vgui.Create("DImage")
                        star:SetImage("icon16/star.png")
                        star.PerformLayout = function(s)
                            s:AlignTop(2)
                            s:AlignRight(2)
                            s:SetSize(12, 12)
                        end
                        star:SetTooltip("Favorite")
                        ic:AddLayer(star)
                        ic:EnableMousePassthrough(star)
                    end
                end
            end

            -- Slot marker icon
            ic.slot = 1
            if ItemIsWeapon(item) and showSlotVar:GetBool() then
                local slot = vgui.Create("SimpleIconLabelled")
                slot:SetIcon("vgui/ttt/slot_cap")
                slot:SetIconColor(color_slot[ply:GetRole()] or COLOR_GREY)
                slot:SetIconSize(16)

                slot:SetIconText(item.slot)

                slot:SetIconProperties(COLOR_WHITE,
                        "DefaultBold",
                        { opacity = 220, offset = 1 },
                        { 9, 8 })

                ic:AddLayer(slot)
                ic:EnableMousePassthrough(slot)
            end

            ic:SetIconSize(itemSize)
            ic:SetIcon(item.material)
        elseif item.model then
            ic = vgui.Create("SpawnIcon", dlist)
            ic:SetModel(item.model)
        else
            ErrorNoHalt("Equipment item does not have model or material specified: " .. tostring(item) .. "\n")
        end

        ic.item = item

        local tip = SafeTranslate(item.name) .. " (" .. SafeTranslate(item.type) .. ")"
        ic:SetTooltip(tip)

        -- If we cannot order this item, darken it
        if ((not can_order) or
                -- already owned
                table.HasValue(owned_ids, item.id) or
                (tonumber(item.id) and ply:HasEquipmentItem(tonumber(item.id))) or
                -- already carrying a weapon for this slot
                (ItemIsWeapon(item) and (not CanCarryWeapon(item))) or
                -- already bought the item before
                (item.limited and ply:HasBought(tostring(item.id)))) then

            ic:SetIconColor(color_darkened)
        end

        if ic.favorite then
            paneltablefav[ic.slot or 1][k] = ic
        else
            paneltable[ic.slot or 1][k] = ic
        end
    end

    -- add favorites first
    for i = 1, 9 do
        for _, panel in pairs(paneltablefav[i]) do
            dlist:AddPanel(panel)
        end
    end
    -- non favorites second
    for i = 1, 9 do
        for _, panel in pairs(paneltable[i]) do
            dlist:AddPanel(panel)
        end
    end

    local bw, bh = 100, 25

    local dih = h - bh - m * 5
    local dinfobg = vgui.Create("DPanel", dequip)
    dinfobg:SetPaintBackground(false)
    dinfobg:SetSize(diw - m, dih)
    dinfobg:SetPos(dlistw + m, 0)

    local dinfo = vgui.Create("ColoredBox", dinfobg)
    dinfo:SetColor(Color(90, 90, 95))
    dinfo:SetPos(0, 0)
    dinfo:StretchToParent(0, 0, m * 2, 105)

    local dfields = {}
    for _, k in pairs({ "name", "type", "desc" }) do
        dfields[k] = vgui.Create("DLabel", dinfo)
        dfields[k]:SetTooltip(GetTranslation("equip_spec_" .. k))
        dfields[k]:SetPos(m * 3, m * 2)
        dfields[k]:SetWidth(diw - m * 6)
    end

    dfields.name:SetFont("TabLarge")

    dfields.type:SetFont("DermaDefault")
    dfields.type:MoveBelow(dfields.name)

    dfields.desc:SetFont("DermaDefaultBold")
    dfields.desc:SetContentAlignment(7)
    dfields.desc:MoveBelow(dfields.type, 1)

    local dhelp = vgui.Create("DPanel", dinfobg)
    dhelp:SetPaintBackground(false)
    dhelp:SetSize(diw, 64)
    dhelp:MoveBelow(dinfo, m)

    local update_preqs = PreqLabels(dhelp, m * 7, m * 2)

    dhelp:SizeToContents()

    local dconfirm = vgui.Create("DButton", dinfobg)
    dconfirm:SetPos(0, dih - bh * 2)
    dconfirm:SetSize(bw, bh)
    dconfirm:SetDisabled(true)
    dconfirm:SetText(GetTranslation("equip_confirm"))

    dsheet:AddSheet(GetTranslation("equip_tabtitle"), dequip, "icon16/bomb.png", false, false, GetTranslation("equip_tooltip_main"))

    -- Item control
    if ply:HasEquipmentItem(EQUIP_RADAR) then
        local dradar = RADAR.CreateMenu(dsheet, dframe)
        dsheet:AddSheet(GetTranslation("radar_name"), dradar, "icon16/magnifier.png", false, false, GetTranslation("equip_tooltip_radar"))
    end

    if ply:HasEquipmentItem(EQUIP_DISGUISE) then
        local ddisguise = DISGUISE.CreateMenu(dsheet)
        dsheet:AddSheet(GetTranslation("disg_name"), ddisguise, "icon16/user.png", false, false, GetTranslation("equip_tooltip_disguise"))
    end

    -- Weapon/item control
    if IsValid(ply.radio) or ply:HasWeapon("weapon_ttt_radio") then
        local dradio = TRADIO.CreateMenu(dsheet)
        dsheet:AddSheet(GetTranslation("radio_name"), dradio, "icon16/transmit.png", false, false, GetTranslation("equip_tooltip_radio"))
    end

    -- Credit transferring
    if credits > 0 then
        local dtransfer = CreateTransferMenu(dsheet)
        dsheet:AddSheet(GetTranslation("xfer_name"), dtransfer, "icon16/group_gear.png", false, false, GetTranslation("equip_tooltip_xfer"))
    end

    hook.Run("TTTEquipmentTabs", dsheet)

    -- couple panelselect with info
    dlist.OnActivePanelChanged = function(self, _, new)
        for k, v in pairs(new.item) do
            if dfields[k] then
                dfields[k]:SetText(SafeTranslate(v))
                dfields[k]:SizeToContents()
            end
        end

        -- Trying to force everything to update to
        -- the right size is a giant pain, so just
        -- force a good size.
        dfields.desc:SetTall(70)

        can_order = update_preqs(new.item)

        dconfirm:SetDisabled(not can_order)
    end

    -- select first
    dlist:SelectPanel(to_select or dlist:GetItems()[1])

    -- prep confirm action
    dconfirm.DoClick = function()
        local pnl = dlist.SelectedPanel
        if not pnl or not pnl.item then return end
        local choice = pnl.item
        RunConsoleCommand("ttt_order_equipment", choice.id)
        dframe:Close()
    end

    -- update some basic info, may have changed in another tab
    -- specifically the number of credits in the preq list
    dsheet.OnTabChanged = function(s, old, new)
        if not IsValid(new) then return end

        if new:GetPanel() == dequip then
            can_order = update_preqs(dlist.SelectedPanel.item)
            dconfirm:SetDisabled(not can_order)
        end
    end

    local dcancel = vgui.Create("DButton", dframe)
    dcancel:SetPos(w - 13 - bw, h - bh - 16)
    dcancel:SetSize(bw, bh)
    dcancel:SetDisabled(false)
    dcancel:SetText(GetTranslation("close"))
    dcancel.DoClick = function() dframe:Close() end

    --add as favorite button
    dfav = vgui.Create("DButton", dinfobg)
    dfav:SetPos(0, dih - bh * 2)
    dfav:MoveRightOf(dconfirm)
    dfav:SetSize(bh, bh)
    dfav:SetDisabled(false)
    dfav:SetText("")
    dfav:SetImage("icon16/star.png")
    dfav.DoClick = function()
        local ply = LocalPlayer()
        local role = ply:GetRole()
        local guid = ply:SteamID()
        local pnl = dlist.SelectedPanel
        if not pnl or not pnl.item then return end
        local choice = pnl.item
        local weapon = choice.id
        CreateFavTable()
        if pnl.favorite then
            RemoveFavorite(guid, role, weapon)
        else
            AddFavorite(guid, role, weapon)
        end
    end

    dframe:MakePopup()
    dframe:SetKeyboardInputEnabled(false)

    eqframe = dframe
end
concommand.Add("ttt_cl_traitorpopup", TraitorMenuPopup)

local function ForceCloseTraitorMenu(ply, cmd, args)
    if IsValid(eqframe) then
        eqframe:Close()
    end
end
concommand.Add("ttt_cl_traitorpopup_close", ForceCloseTraitorMenu)

function GM:OnContextMenuOpen()
    local r = GetRoundState()
    if r == ROUND_ACTIVE and (not LocalPlayer():IsShopRole() or (LocalPlayer():IsDeputy() and not LocalPlayer():GetNWBool("HasPromotion", false))) then
        return
    elseif r == ROUND_POST or r == ROUND_PREP then
        CLSCORE:Toggle()
        return
    end

    if IsValid(eqframe) then
        eqframe:Close()
    else
        RunConsoleCommand("ttt_cl_traitorpopup")
    end
end

local function ReceiveEquipment()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    ply.equipment_items = net.ReadUInt(32)
end
net.Receive("TTT_Equipment", ReceiveEquipment)

local function ReceiveCredits()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    ply.equipment_credits = net.ReadUInt(8)
end
net.Receive("TTT_Credits", ReceiveCredits)

local r = 0
local function ReceiveBought()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    ply.bought = {}
    local num = net.ReadUInt(8)
    for i = 1, num do
        local s = net.ReadString()
        if s ~= "" then
            table.insert(ply.bought, s)
        end
    end

    -- This usermessage sometimes fails to contain the last weapon that was
    -- bought, even though resending then works perfectly. Possibly a bug in
    -- bf_read. Anyway, this hack is a workaround: we just request a new umsg.
    if num ~= #ply.bought and r < 10 then
        -- r is an infinite loop guard
        RunConsoleCommand("ttt_resend_bought")
        r = r + 1
    else
        r = 0
    end
end
net.Receive("TTT_Bought", ReceiveBought)

-- Player received the item he has just bought, so run clientside init
local function ReceiveBoughtItem()
    local is_item = net.ReadBit() == 1
    local id = is_item and net.ReadUInt(32) or net.ReadString()

    -- I can imagine custom equipment wanting this, so making a hook
    hook.Run("TTTBoughtItem", is_item, id)
end
net.Receive("TTT_BoughtItem", ReceiveBoughtItem)
