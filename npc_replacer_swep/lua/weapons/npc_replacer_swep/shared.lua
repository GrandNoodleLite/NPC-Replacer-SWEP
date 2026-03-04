if SERVER then
    AddCSLuaFile()

    util.AddNetworkString("npc_replacer_request_data")
    util.AddNetworkString("npc_replacer_send_data")
    util.AddNetworkString("npc_replacer_set_current")
    util.AddNetworkString("npc_replacer_save")
    util.AddNetworkString("npc_replacer_delete")
    util.AddNetworkString("npc_replacer_copy_mode")

    hook.Add("PlayerInitialSpawn", "npc_replacer_init", function(ply)
        ply.npc_replacer_saves = util.JSONToTable(ply:GetPData("npc_replacer_saves", "{}")) or {}
        ply.npc_replacer_current = util.JSONToTable(ply:GetPData("npc_replacer_current", "{}")) or {}
        ply.npc_replacer_in_copy_mode = false
    end)

    net.Receive("npc_replacer_request_data", function(len, ply)
        local data = {
            current = ply.npc_replacer_current,
            saves = ply.npc_replacer_saves
        }
        net.Start("npc_replacer_send_data")
        net.WriteTable(data)
        net.Send(ply)
    end)

    net.Receive("npc_replacer_set_current", function(len, ply)
        local cfg = net.ReadTable()
        if cfg.model == "" then cfg.model = nil end
        -- Preserve "none" as a valid weapon value; only clear empty strings
        if cfg.weapon == "" then cfg.weapon = nil end
        if cfg.health == "" or cfg.health == "0" then cfg.health = nil end
        -- Dissolve type: default to "1" (Heavy) if empty or missing
        if cfg.dissolve == "" then cfg.dissolve = nil end
        ply.npc_replacer_current = cfg
        ply:SetPData("npc_replacer_current", util.TableToJSON(ply.npc_replacer_current))
    end)

    net.Receive("npc_replacer_save", function(len, ply)
        local name = net.ReadString()
        local cfg = net.ReadTable()
        if cfg.model == "" then cfg.model = nil end
        if cfg.weapon == "" then cfg.weapon = nil end
        if cfg.health == "" or cfg.health == "0" then cfg.health = nil end
        if cfg.dissolve == "" then cfg.dissolve = nil end
        ply.npc_replacer_saves[name] = cfg
        ply:SetPData("npc_replacer_saves", util.TableToJSON(ply.npc_replacer_saves))
    end)

    net.Receive("npc_replacer_delete", function(len, ply)
        local name = net.ReadString()
        ply.npc_replacer_saves[name] = nil
        ply:SetPData("npc_replacer_saves", util.TableToJSON(ply.npc_replacer_saves))
    end)

    net.Receive("npc_replacer_copy_mode", function(len, ply)
        ply.npc_replacer_in_copy_mode = net.ReadBool()
    end)
end

if CLIENT then
    -- =====================================================================
    -- Resolution scaling: all sizes are authored at 1080p baseline
    -- =====================================================================
    local function S(px)
        return math.Round(px * (ScrH() / 1080))
    end

    -- =====================================================================
    -- Font creation (called on load and on resolution change)
    -- =====================================================================
    local function CreateScaledFonts()
        surface.CreateFont("NPCReplacer_HUD_Title", {
            font      = "Roboto",
            size      = S(20),
            weight    = 700,
            antialias = true,
        })
        surface.CreateFont("NPCReplacer_HUD_Sub", {
            font      = "Roboto",
            size      = S(17),
            weight    = 500,
            antialias = true,
        })
        surface.CreateFont("NPCReplacer_HUD_Target", {
            font      = "Roboto",
            size      = S(17),
            weight    = 600,
            antialias = true,
        })
        surface.CreateFont("NPCReplacer_HintBubble", {
            font      = "Roboto",
            size      = S(14),
            weight    = 800,
            antialias = true,
        })
        surface.CreateFont("NPCReplacer_Tooltip", {
            font      = "Roboto",
            size      = S(13),
            weight    = 500,
            antialias = true,
        })
        surface.CreateFont("NPCReplacer_ApplyBold", {
            font      = "Roboto",
            size      = S(14),
            weight    = 800,
            antialias = true,
        })
    end

    CreateScaledFonts()

    -- Recreate fonts if the player changes resolution
    hook.Add("OnScreenSizeChanged", "npc_replacer_rescale_fonts", function()
        CreateScaledFonts()
    end)

    -- =====================================================================
    -- Dissolve-type definitions
    -- =====================================================================
    -- value = Source Engine dissolve type passed to Entity:Dissolve()
    -- "-1" is a special value meaning "no dissolve effect, just remove"
    local DISSOLVE_OPTIONS = {
        { label = "Heavy",  value = "1" },
        { label = "Energy", value = "0" },
        { label = "Light",  value = "2" },
        { label = "Core",   value = "3" },
        { label = "None",   value = "-1" },
    }

    local DISSOLVE_DEFAULT = "1"  -- Heavy

    -- Build quick lookup: value -> label
    local DISSOLVE_LABEL_FOR = {}
    for _, opt in ipairs(DISSOLVE_OPTIONS) do
        DISSOLVE_LABEL_FOR[opt.value] = opt.label
    end

    -- =====================================================================
    -- Forward declarations
    -- =====================================================================
    local copyState     = nil
    local menuFrame     = nil
    local pendingValues = nil   -- field values preserved when menu closed via X
    local lastApplied   = nil   -- what the server actually has (only set by Apply and initial load)

    local ExitCopyMode
    local OpenReplacerMenu
    local EnterCopyMode

    local FIELD_NAMES = {
        class  = "NPC Class",
        model  = "Model",
        weapon = "Weapon",
        health = "Health",
        all    = "All Fields"
    }

    -- =====================================================================
    -- ExitCopyMode
    -- =====================================================================
    ExitCopyMode = function()
        if not copyState then return end
        copyState = nil

        net.Start("npc_replacer_copy_mode")
            net.WriteBool(false)
        net.SendToServer()

        hook.Remove("PlayerBindPress", "npc_replacer_copy")
        hook.Remove("HUDPaint",        "npc_replacer_copy_hud")
        hook.Remove("Think",           "npc_replacer_copy_think")
    end

    -- =====================================================================
    -- OpenReplacerMenu
    -- =====================================================================
    OpenReplacerMenu = function(data)
        if IsValid(menuFrame) then menuFrame:Remove() end

        -- Initialise lastApplied from server data on first open
        if not lastApplied then
            lastApplied = {
                class    = (data.current or {}).class    or "",
                model    = (data.current or {}).model    or "",
                weapon   = (data.current or {}).weapon   or "",
                health   = (data.current or {}).health   or "",
                dissolve = (data.current or {}).dissolve or DISSOLVE_DEFAULT,
            }
        end

        -- Use pending (unsaved) field values if the user closed with X last time,
        -- otherwise fall back to what the server sent
        local current = pendingValues or {
            class    = (data.current or {}).class    or "",
            model    = (data.current or {}).model    or "",
            weapon   = (data.current or {}).weapon   or "",
            health   = (data.current or {}).health   or "",
            dissolve = (data.current or {}).dissolve or DISSOLVE_DEFAULT,
        }
        pendingValues = nil  -- consumed; will be re-set if they close with X again

        -- ---- Scaled layout constants (1080p baseline) ----
        local pad        = S(10)
        local rowH       = S(26)
        local rowGap     = S(6)
        local labelW     = S(120)
        local copyBtnW   = S(120)
        local btnGap     = S(6)
        local entryW     = S(280)
        local btnH       = S(30)
        local btnSpacing = S(8)
        local comboH     = S(22)

        local frameW = pad + labelW + entryW + btnGap + copyBtnW + pad

        -- Vertical layout computation
        local contentTop     = S(30)
        local numTextRows    = 4   -- class, model, weapon, health
        local textBlockH     = numTextRows * rowH + (numTextRows - 1) * rowGap
        local dissolveY      = contentTop + textBlockH + rowGap
        local dissolveRowH   = rowH
        local savesComboY    = dissolveY + dissolveRowH + rowGap + S(2)
        local btnRowY        = savesComboY + comboH + rowGap + S(2)
        local frameH         = btnRowY + btnH + pad

        local frame = vgui.Create("DFrame")
        menuFrame = frame
        frame:SetSize(frameW, frameH)
        frame:Center()
        frame:SetTitle("NPC Replacer Configuration")
        frame:MakePopup()

        -- ---- Hint bubble helper ----
        local function MakeHintBubble(parent, x, y, hintText)
            local bubble = vgui.Create("DLabel", parent)
            bubble:SetPos(x, y)
            bubble:SetSize(S(20), S(18))
            bubble:SetText("(?)")
            bubble:SetFont("NPCReplacer_HintBubble")
            bubble:SetColor(Color(100, 180, 255))
            bubble:SetContentAlignment(5)
            bubble:SetMouseInputEnabled(true)
            bubble:SetCursor("hand")

            local tooltip = nil

            bubble.OnCursorEntered = function()
                if IsValid(tooltip) then tooltip:Remove() end

                tooltip = vgui.Create("DPanel")
                tooltip:SetDrawOnTop(true)
                tooltip:SetMouseInputEnabled(false)

                surface.SetFont("NPCReplacer_Tooltip")
                local tw, th = surface.GetTextSize(hintText)
                local tipW = tw + S(16)
                local tipH = th + S(10)
                tooltip:SetSize(tipW, tipH)

                local bx, by = bubble:LocalToScreen(0, 0)
                tooltip:SetPos(bx, by + S(20))

                tooltip.Paint = function(self, w, h)
                    draw.RoundedBox(S(4), 0, 0, w, h, Color(30, 30, 30, 240))
                    surface.SetDrawColor(100, 180, 255, 180)
                    surface.DrawOutlinedRect(0, 0, w, h, 1)
                    draw.SimpleText(hintText, "NPCReplacer_Tooltip", w / 2, h / 2,
                        Color(220, 230, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end

            bubble.OnCursorExited = function()
                if IsValid(tooltip) then tooltip:Remove() end
                tooltip = nil
            end

            bubble.OnRemove = function()
                if IsValid(tooltip) then tooltip:Remove() end
            end

            return bubble
        end

        -- ---- Field row helper ----
        local function MakeRow(y, labelText, defaultVal, hintText, placeholder)
            local lbl = vgui.Create("DLabel", frame)
            lbl:SetPos(pad, y)
            lbl:SetSize(labelW, rowH)
            lbl:SetText(labelText)

            if hintText then
                surface.SetFont("DermaDefault")
                local textW = surface.GetTextSize(labelText)
                MakeHintBubble(frame, pad + textW + S(2), y + S(3), hintText)
            end

            local entry = vgui.Create("DTextEntry", frame)
            entry:SetPos(pad + labelW, y + S(2))
            entry:SetSize(entryW, rowH - S(4))
            entry:SetValue(defaultVal or "")
            if placeholder then
                entry:SetPlaceholderText(placeholder)
            end

            local btn = vgui.Create("DButton", frame)
            btn:SetPos(pad + labelW + entryW + btnGap, y + S(2))
            btn:SetSize(copyBtnW, rowH - S(4))
            btn:SetText("Copy from Target")

            return entry, btn
        end

        local y = contentTop
        local classEntry,  classCopyBtn  = MakeRow(y, "NPC Class:", current.class,
            "Must be the NPC entity class (e.g. npc_combine_s), not its display name",
            "e.g. npc_combine_s")
        y = y + rowH + rowGap
        local modelEntry,  modelCopyBtn  = MakeRow(y, "Model (optional):", current.model,
            "Full path to the .mdl file (e.g. models/combine_soldier.mdl)",
            "e.g. models/combine_soldier.mdl")
        y = y + rowH + rowGap
        local weaponEntry, weaponCopyBtn = MakeRow(y, "Weapon (optional):", current.weapon,
            "Type \"none\" to force spawning with no weapon",
            "e.g. weapon_smg1  or  none")
        y = y + rowH + rowGap
        local healthEntry, healthCopyBtn = MakeRow(y, "Health (optional):", current.health,
            nil,
            "e.g. 500")

        healthEntry:SetNumeric(true)

        -- ---- Dissolve effect dropdown ----
        local dissolveLbl = vgui.Create("DLabel", frame)
        dissolveLbl:SetPos(pad, dissolveY)
        dissolveLbl:SetSize(labelW, dissolveRowH)
        dissolveLbl:SetText("Dissolve Effect:")

        -- Hint bubble for dissolve
        surface.SetFont("DermaDefault")
        local dissolveLblW = surface.GetTextSize("Dissolve Effect:")
        MakeHintBubble(frame, pad + dissolveLblW + S(2), dissolveY + S(3),
            "Visual effect when removing an NPC (applies to both replace and dissolve-only)")

        local dissolveCombo = vgui.Create("DComboBox", frame)
        dissolveCombo:SetPos(pad + labelW, dissolveY + S(2))
        dissolveCombo:SetSize(entryW + btnGap + copyBtnW, dissolveRowH - S(4))
        dissolveCombo:SetSortItems(false)  -- preserve our defined order

        local dissolveChooseIdx = 1  -- fallback to first option (Heavy)
        for i, opt in ipairs(DISSOLVE_OPTIONS) do
            dissolveCombo:AddChoice(opt.label, opt.value)
            if opt.value == current.dissolve then
                dissolveChooseIdx = i
            end
        end

        -- Use ChooseOptionID to properly select the option (not just display text)
        dissolveCombo:ChooseOptionID(dissolveChooseIdx)

        -- ---- Saved-config combo box ----
        local savesBox = vgui.Create("DComboBox", frame)
        savesBox:SetPos(pad, savesComboY)
        savesBox:SetSize(frameW - pad * 2, comboH)
        savesBox:SetValue("Select Saved Config")
        for name in pairs(data.saves or {}) do
            savesBox:AddChoice(name)
        end

        savesBox.OnSelect = function(self, index, value)
            local sav = data.saves[value]
            if sav then
                classEntry:SetValue(sav.class or "")
                modelEntry:SetValue(sav.model or "")
                weaponEntry:SetValue(sav.weapon or "")
                healthEntry:SetValue(sav.health or "")
                -- Load saved dissolve type, default to Heavy if not present
                local savDissolve = sav.dissolve or DISSOLVE_DEFAULT
                for i, opt in ipairs(DISSOLVE_OPTIONS) do
                    if opt.value == savDissolve then
                        dissolveCombo:ChooseOptionID(i)
                        break
                    end
                end
            end
        end

        -- ---- Value collector ----
        local function GetValues()
            -- Read selected dissolve value from combo box
            local _, dissolveVal = dissolveCombo:GetSelected()
            if not dissolveVal then dissolveVal = DISSOLVE_DEFAULT end

            return {
                class    = classEntry:GetValue(),
                model    = modelEntry:GetValue(),
                weapon   = weaponEntry:GetValue(),
                health   = healthEntry:GetValue(),
                dissolve = tostring(dissolveVal),
            }
        end

        -- Track whether the menu was closed by Apply or copy mode (not X)
        local applyApplied = false

        -- ---- Copy-mode launcher ----
        local function StartCopy(field)
            local vals = GetValues()
            applyApplied = true  -- prevent OnClose from saving pending values
            frame:Close()
            pendingValues = nil  -- copy mode manages its own values
            EnterCopyMode(field, vals, data)
        end

        classCopyBtn.DoClick  = function() StartCopy("class")  end
        modelCopyBtn.DoClick  = function() StartCopy("model")  end
        weaponCopyBtn.DoClick = function() StartCopy("weapon") end
        healthCopyBtn.DoClick = function() StartCopy("health") end

        -- ---- Bottom button row (centered) ----
        local btnSpecs = {
            { key = "Apply",   w = S(80) },
            { key = "Save",    w = S(80) },
            { key = "Delete",  w = S(80) },
            { key = "Clear",   w = S(60) },
            { key = "CopyAll", text = "Copy All from Target", w = S(155) },
        }
        local totalBtnW = 0
        for _, spec in ipairs(btnSpecs) do totalBtnW = totalBtnW + spec.w end
        totalBtnW = totalBtnW + btnSpacing * (#btnSpecs - 1)
        local btnStartX = math.floor((frameW - totalBtnW) / 2)

        local buttons = {}
        local bx = btnStartX
        for _, spec in ipairs(btnSpecs) do
            local b = vgui.Create("DButton", frame)
            b:SetPos(bx, btnRowY)
            b:SetSize(spec.w, btnH)
            b:SetText(spec.text or spec.key)
            buttons[spec.key] = b
            bx = bx + spec.w + btnSpacing
        end

        -- Apply
        local applyBtn = buttons["Apply"]

        applyBtn.DoClick = function()
            local cfg = GetValues()
            net.Start("npc_replacer_set_current")
                net.WriteTable(cfg)
            net.SendToServer()
            -- Update module-level applied baseline
            lastApplied = table.Copy(cfg)
            pendingValues = nil
            applyApplied = true
            frame:Close()
        end

        -- Save
        buttons["Save"].DoClick = function()
            Derma_StringRequest(
                "Save Configuration",
                "Enter a name for this save:",
                "",
                function(name)
                    if name == "" then return end
                    local cfg = GetValues()
                    net.Start("npc_replacer_save")
                        net.WriteString(name)
                        net.WriteTable(cfg)
                    net.SendToServer()
                    data.saves[name] = cfg
                    savesBox:AddChoice(name)
                end
            )
        end

        -- Delete
        buttons["Delete"].DoClick = function()
            local selected = savesBox:GetSelected()
            if not selected then return end
            net.Start("npc_replacer_delete")
                net.WriteString(selected)
            net.SendToServer()
            data.saves[selected] = nil
            savesBox:Clear()
            savesBox:SetValue("Select Saved Config")
            for name in pairs(data.saves) do
                savesBox:AddChoice(name)
            end
        end

        -- Clear
        buttons["Clear"].DoClick = function()
            classEntry:SetValue("")
            modelEntry:SetValue("")
            weaponEntry:SetValue("")
            healthEntry:SetValue("")
            dissolveCombo:ChooseOptionID(1)  -- Reset to Heavy (first option)
            savesBox:SetValue("Select Saved Config")
        end

        -- Copy All from Target
        buttons["CopyAll"].DoClick = function() StartCopy("all") end

        -- ---- Preserve field values when closed via X ----
        frame.OnClose = function()
            if not applyApplied then
                pendingValues = GetValues()
            end
        end

        -- ---- Highlight Apply button when unapplied changes exist ----
        local function HasUnappliedChanges()
            local v = GetValues()
            return v.class    ~= (lastApplied.class    or "")
                or v.model    ~= (lastApplied.model    or "")
                or v.weapon   ~= (lastApplied.weapon   or "")
                or v.health   ~= (lastApplied.health   or "")
                or v.dissolve ~= (lastApplied.dissolve or DISSOLVE_DEFAULT)
        end

        local normalPaint    = applyBtn.Paint
        local normalFont     = applyBtn:GetFont()
        local normalTextCol  = applyBtn:GetTextColor()

        frame.Think = function(self)
            if HasUnappliedChanges() then
                applyBtn:SetFont("NPCReplacer_ApplyBold")
                applyBtn.Paint = function(btn, w, h)
                    draw.RoundedBox(S(4), 0, 0, w, h, Color(221, 18, 25))
                end
                applyBtn:SetTextColor(Color(255, 255, 255))
            else
                applyBtn:SetFont(normalFont or "DermaDefault")
                applyBtn.Paint = normalPaint
                applyBtn:SetTextColor(normalTextCol or Color(0, 0, 0))
            end
        end
    end

    -- =====================================================================
    -- EnterCopyMode
    -- =====================================================================
    EnterCopyMode = function(field, storedValues, data)
        net.Start("npc_replacer_copy_mode")
            net.WriteBool(true)
        net.SendToServer()

        local ply         = LocalPlayer()
        local startWeapon = ply:GetActiveWeapon()

        copyState = {
            field  = field,
            values = storedValues,
            data   = data
        }

        -- -----------------------------------------------------------------
        -- HUD overlay (scales every frame via S())
        -- -----------------------------------------------------------------
        hook.Add("HUDPaint", "npc_replacer_copy_hud", function()
            if not copyState then return end

            local scrW, scrH = ScrW(), ScrH()
            local fieldLabel = FIELD_NAMES[copyState.field] or copyState.field

            local tr = ply:GetEyeTrace()
            local targetText, targetCol
            if IsValid(tr.Entity) and tr.Entity:IsNPC() then
                targetText = "Target: " .. tr.Entity:GetClass()
                targetCol  = Color(100, 255, 100)
            else
                targetText = "No NPC detected — aim at an NPC"
                targetCol  = Color(255, 100, 100)
            end

            -- Measure title so box always fits
            surface.SetFont("NPCReplacer_HUD_Title")
            local titleText = "Left Click on an NPC to copy " .. fieldLabel
            local titleW = surface.GetTextSize(titleText)

            local boxW = math.max(titleW + S(40), S(400))
            local boxH = S(84)
            local boxX = math.floor((scrW - boxW) / 2)
            local boxY = math.floor(scrH * 0.13)

            draw.RoundedBox(S(8), boxX, boxY, boxW, boxH, Color(20, 20, 20, 220))
            surface.SetDrawColor(80, 180, 255, 120)
            surface.DrawOutlinedRect(boxX, boxY, boxW, boxH, 1)

            draw.SimpleText(
                titleText,
                "NPCReplacer_HUD_Title",
                scrW / 2, boxY + S(18),
                Color(220, 235, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            draw.SimpleText(
                "Right Click to cancel",
                "NPCReplacer_HUD_Sub",
                scrW / 2, boxY + S(44),
                Color(180, 180, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            draw.SimpleText(
                targetText,
                "NPCReplacer_HUD_Target",
                scrW / 2, boxY + S(66),
                targetCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end)

        -- -----------------------------------------------------------------
        -- Think: detect conditions that should exit copy mode
        -- -----------------------------------------------------------------
        hook.Add("Think", "npc_replacer_copy_think", function()
            if not copyState then return end

            local shouldCancel = false
            if not ply:Alive()                      then shouldCancel = true end
            if ply:InVehicle()                      then shouldCancel = true end
            if ply:GetActiveWeapon() ~= startWeapon then shouldCancel = true end

            if shouldCancel then
                local vals = copyState.values
                local dat  = copyState.data
                dat.current = vals
                ExitCopyMode()
            end
        end)

        -- -----------------------------------------------------------------
        -- PlayerBindPress: intercept clicks
        -- -----------------------------------------------------------------
        hook.Add("PlayerBindPress", "npc_replacer_copy", function(_, bind, pressed)
            if not copyState then return end
            if not pressed then return end

            -- LEFT CLICK
            if bind == "+attack" then
                local tr  = ply:GetEyeTrace()
                local ent = tr.Entity

                if not IsValid(ent) or not ent:IsNPC() then
                    surface.PlaySound("buttons/button10.wav")
                    chat.AddText(
                        Color(255, 40, 40),  "[NPC Replacer] ",
                        Color(255, 80, 80),  "Target NPC not detected! Look directly at an NPC and try again.")
                    return true
                end

                local npcClass  = ent:GetClass()
                local npcModel  = ent:GetModel() or ""
                local npcWeapon = ""
                local activeWep = ent:GetActiveWeapon()
                if IsValid(activeWep) then
                    npcWeapon = activeWep:GetClass()
                end
                local npcHealth = tostring(ent:GetMaxHealth())

                local newValues = table.Copy(copyState.values)
                if copyState.field == "class"  or copyState.field == "all" then newValues.class  = npcClass  end
                if copyState.field == "model"  or copyState.field == "all" then newValues.model  = npcModel  end
                if copyState.field == "weapon" or copyState.field == "all" then newValues.weapon = npcWeapon end
                if copyState.field == "health" or copyState.field == "all" then newValues.health = npcHealth end
                -- Note: dissolve effect is not copied from target NPCs (it's a SWEP preference, not an NPC property)

                local dat = copyState.data
                dat.current = newValues

                ExitCopyMode()
                OpenReplacerMenu(dat)
                return true
            end

            -- RIGHT CLICK
            if bind == "+attack2" then
                local dat = copyState.data
                dat.current = copyState.values

                ExitCopyMode()
                OpenReplacerMenu(dat)
                return true
            end
        end)
    end

    -- =====================================================================
    -- Console command & net receiver
    -- =====================================================================
    concommand.Add("npc_replacer_open_menu", function()
        if copyState then ExitCopyMode() end
        net.Start("npc_replacer_request_data")
        net.SendToServer()
    end)

    net.Receive("npc_replacer_send_data", function()
        local data = net.ReadTable()
        OpenReplacerMenu(data)
    end)
end

-- =========================================================================
-- Dissolve helper (server-side)
-- =========================================================================
-- Performs a dissolve effect on the given entity, or a plain Remove()
-- when dissolveType is -1 ("None").
-- Returns true if the entity was removed immediately (no dissolve anim).
local function DissolveOrRemove(ent, dissolveType)
    if dissolveType == -1 then
        ent:Remove()
        return true
    else
        ent:Dissolve(dissolveType)
        return false
    end
end

-- =========================================================================
-- SWEP definition
-- =========================================================================
SWEP.Author       = "Grok 4 and Claude Opus 4.6"
SWEP.Category     = "GrandNoodleLite's Weapons"
SWEP.PrintName    = "NPC Replacer"
SWEP.Instructions = "Left Click: Replace targeted NPC. Right Click: Open configuration menu. Reload: Dissolve targeted NPC."
SWEP.Base         = "weapon_base"
SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.ViewModel  = "models/weapons/v_rpg.mdl"
SWEP.WorldModel = "models/weapons/w_rocket_launcher.mdl"

SWEP.Primary.ClipSize    = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic   = false
SWEP.Primary.Ammo        = "none"

SWEP.Secondary.ClipSize    = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic   = false
SWEP.Secondary.Ammo        = "none"

function SWEP:PrimaryAttack()
    if CLIENT then return end
    self:SetNextPrimaryFire(CurTime() + 0.5)

    -- Suppress replacement while in copy-from-target mode
    if self.Owner.npc_replacer_in_copy_mode then return end

    local tr  = self.Owner:GetEyeTrace()
    local ent = tr.Entity
    if not IsValid(ent) or not ent:IsNPC() then
        self.Owner:ChatPrint("Unable to replace NPC: Not looking at an NPC")
        return
    end

    local cfg = self.Owner.npc_replacer_current
    if not cfg or not cfg.class then
        self.Owner:ChatPrint("Unable to replace NPC: No replacement configured")
        return
    end

    local npcList = list.Get("NPC")
    if not npcList[cfg.class] then
        self.Owner:ChatPrint("Unable to replace NPC: Invalid NPC class")
        return
    end

    local pos = ent:GetPos()
    local ang = ent:GetAngles()

    -- Parse dissolve type from config (default: 1 = Heavy)
    local dissolveType = 1
    if cfg.dissolve and cfg.dissolve ~= "" then
        local num = tonumber(cfg.dissolve)
        if num then dissolveType = num end
    end

    -- Parse spawn health from config (stored as string)
    local spawnHealth = nil
    if cfg.health and cfg.health ~= "" then
        local num = tonumber(cfg.health)
        if num and num > 0 then
            spawnHealth = math.floor(num)
        end
    end

    -- Determine weapon mode:
    -- "none" = explicitly no weapon, nil/empty = use defaults, anything else = specific weapon
    local noWeapon = false
    local specificWeapon = nil
    if cfg.weapon then
        if string.lower(cfg.weapon) == "none" then
            noWeapon = true
        elseif cfg.weapon ~= "" then
            specificWeapon = cfg.weapon
        end
    end

    -- Look up NPC spawn-list data for KeyValues and default weapons
    local npcListData = nil
    local npcListKeyValues = nil
    local defaultWeapons = nil
    if npcList then
        local directEntry = npcList[cfg.class]
        if directEntry and (not directEntry.Class or directEntry.Class == cfg.class) then
            npcListData = directEntry
        end
        if not npcListData then
            for _, entry in pairs(npcList) do
                if entry.Class == cfg.class then
                    npcListData = entry
                    break
                end
            end
        end
    end
    if npcListData then
        if npcListData.KeyValues then
            npcListKeyValues = npcListData.KeyValues
        end
        if not noWeapon and npcListData.Weapons then
            local valid = {}
            for _, w in ipairs(npcListData.Weapons) do
                if w and w ~= "" then table.insert(valid, w) end
            end
            if #valid > 0 then defaultWeapons = valid end
        end
    end

    local function IsSpaceClear(check_pos, mins, maxs)
        local hullTr = util.TraceHull({
            start  = check_pos,
            endpos = check_pos,
            mins   = mins,
            maxs   = maxs,
            mask   = MASK_SOLID_BRUSHONLY
        })
        return not hullTr.Hit
    end

    local function FindNearbyClearPos(original_pos, mins, maxs)
        if IsSpaceClear(original_pos, mins, maxs) then
            return original_pos
        end
        local attempts   = 20
        local max_radius = 100
        for i = 1, attempts do
            local radius     = (i / attempts) * max_radius
            local ang_offset = math.random(0, 360)
            local offset     = Vector(
                math.cos(ang_offset) * radius,
                math.sin(ang_offset) * radius, 0)
            local test_pos   = original_pos + offset
            local trace_start = test_pos + Vector(0, 0, 500)
            local dropTr = util.TraceLine({
                start  = trace_start,
                endpos = trace_start - Vector(0, 0, 1000),
                mask   = MASK_SOLID_BRUSHONLY
            })
            if dropTr.Hit then
                local ground_pos = dropTr.HitPos
                ground_pos.z = ground_pos.z - mins.z
                if IsSpaceClear(ground_pos, mins, maxs) then
                    return ground_pos
                end
            end
        end
        return nil
    end

    -- Capture config values for the closure so they don't change mid-dissolve
    local capturedCfg        = table.Copy(cfg)
    local capturedHealth     = spawnHealth
    local capturedKV         = npcListKeyValues
    local capturedDefWeapons = defaultWeapons
    local capturedNoWeapon   = noWeapon
    local capturedSpecWeapon = specificWeapon
    local capturedOwner      = self.Owner

    -- Shared spawn logic used by both dissolve and instant-remove paths
    local function SpawnReplacement()
        local temp_npc = ents.Create(capturedCfg.class)
        if capturedCfg.model then temp_npc:SetModel(capturedCfg.model) end
        local mins, maxs = temp_npc:GetCollisionBounds()
        temp_npc:Remove()

        local spawn_pos   = FindNearbyClearPos(pos, mins, maxs) or pos
        local upright_ang = Angle(0, ang.y, 0)

        local newnpc = ents.Create(capturedCfg.class)
        newnpc:SetPos(spawn_pos)
        newnpc:SetAngles(upright_ang)

        -- Apply registered KeyValues from NPC spawn list before Spawn()
        if capturedKV then
            for k, v in pairs(capturedKV) do
                if k ~= "additionalequipment" then
                    newnpc:SetKeyValue(k, v)
                end
            end
        end

        -- Weapon assignment via additionalequipment KeyValue (before Spawn)
        if capturedNoWeapon then
            -- Explicitly no weapon
        elseif capturedSpecWeapon then
            newnpc:SetKeyValue("additionalequipment", capturedSpecWeapon)
        elseif capturedDefWeapons then
            local randomWeapon = capturedDefWeapons[math.random(#capturedDefWeapons)]
            newnpc:SetKeyValue("additionalequipment", randomWeapon)
        elseif capturedKV and capturedKV["additionalequipment"] then
            newnpc:SetKeyValue("additionalequipment", capturedKV["additionalequipment"])
        end

        newnpc:Spawn()
        newnpc:Activate()
        if IsValid(capturedOwner) then
            newnpc:SetCreator(capturedOwner)
        end

        if capturedCfg.model then
            newnpc:SetModel(capturedCfg.model)
        end

        newnpc:DropToFloor()

        -- Apply custom health (compatible with VJ-Base, ZBase, and vanilla NPCs)
        if capturedHealth and IsValid(newnpc) then
            newnpc:SetMaxHealth(capturedHealth)
            newnpc:SetHealth(capturedHealth)
            newnpc.StartHealth = capturedHealth
            if newnpc.SetZBaseHealth then
                pcall(function() newnpc:SetZBaseHealth(capturedHealth) end)
            end
            local delayedNPC = newnpc
            local delayedHP  = capturedHealth
            timer.Simple(0.3, function()
                if IsValid(delayedNPC) then
                    delayedNPC:SetMaxHealth(delayedHP)
                    delayedNPC:SetHealth(delayedHP)
                    delayedNPC.StartHealth = delayedHP
                end
            end)
        end
    end

    if dissolveType == -1 then
        -- "None" dissolve: remove instantly then spawn replacement on next frame
        -- Using a brief timer ensures the old entity is fully cleaned up
        ent:Remove()
        timer.Simple(0, function()
            SpawnReplacement()
        end)
    else
        -- Dissolve effect: hook into EntityRemoved to spawn after dissolve completes
        local hookID = "npc_replacer_remove_" .. ent:EntIndex()
        hook.Add("EntityRemoved", hookID, function(removedEnt)
            if removedEnt == ent then
                hook.Remove("EntityRemoved", hookID)
                SpawnReplacement()
            end
        end)
        ent:Dissolve(dissolveType)
    end
end

function SWEP:SecondaryAttack()
    if CLIENT then return end
    self:SetNextSecondaryFire(CurTime() + 0.5)

    self.Owner:ConCommand("npc_replacer_open_menu")
end

function SWEP:Reload()
    if CLIENT then return end

    -- Don't allow dissolve while in copy mode
    if self.Owner.npc_replacer_in_copy_mode then return end

    local tr  = self.Owner:GetEyeTrace()
    local ent = tr.Entity
    if not IsValid(ent) or not ent:IsNPC() then return end

    -- Read dissolve type from current config (default: 1 = Heavy)
    local dissolveType = 1
    local cfg = self.Owner.npc_replacer_current
    if cfg and cfg.dissolve and cfg.dissolve ~= "" then
        local num = tonumber(cfg.dissolve)
        if num then dissolveType = num end
    end

    DissolveOrRemove(ent, dissolveType)
end
