MyLoot = MyLoot or {}
MyLoot.VERSION = C_AddOns and C_AddOns.GetAddOnMetadata("WeltenWandler_Raid_Tool", "Version")
             or GetAddOnMetadata and GetAddOnMetadata("WeltenWandler_Raid_Tool", "Version")
             or "?"
MyLoot.GITHUB  = "https://github.com/Sarome5/WeltenWandler-Raid-Tool"

local ADDON_PREFIX = "MYLOOT"

-- =========================
-- INIT
-- =========================
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("LOOT_READY")
frame:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
frame:RegisterEvent("LOOT_HISTORY_UPDATE_DROP")
frame:RegisterEvent("LOOT_CLOSED")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("ENCOUNTER_START")
frame:RegisterEvent("ENCOUNTER_END")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")

MyLoot.isEncounterActive        = false
MyLoot.isBossActive             = false
MyLoot.hasLootedBoss            = false
MyLoot._activeLootBossIndex     = nil   -- eingefroren bei ENCOUNTER_END, unabhängig vom Dropdown
MyLoot._activeEncounterID       = nil   -- eingefroren bei ENCOUNTER_END für UID-Generierung
MyLoot._awaitingLootAssignment  = false -- true zwischen ENCOUNTER_END (Kill) und nächstem ENCOUNTER_START

-- Addon-Nutzer Versionserkennung
MyLoot._addonUsers       = {}    -- { [playerName] = version }
MyLoot._outdatedNotified = false -- Veraltungswarnung nur einmal pro Session anzeigen

-- Gibt true zurück wenn Version a neuer ist als Version b ("1.0.12" > "1.0.11")
function MyLoot.IsVersionNewer(a, b)
  local function parse(v)
    local t = {}
    for n in tostring(v):gmatch("%d+") do t[#t+1] = tonumber(n) end
    return t
  end
  local pa, pb = parse(a), parse(b)
  for i = 1, math.max(#pa, #pb) do
    local na, nb = pa[i] or 0, pb[i] or 0
    if na > nb then return true end
    if na < nb then return false end
  end
  return false
end

-- Sendet eigene Version an alle Raid/Party-Mitglieder
function MyLoot.BroadcastHello()
  local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
  if channel then
    C_ChatInfo.SendAddonMessage("MYLOOT_SYNC", "HELLO:" .. (MyLoot.VERSION or "?"), channel)
  end
  -- Immer eigenen Eintrag aktualisieren
  local self = UnitName("player")
  if self then MyLoot._addonUsers[self] = MyLoot.VERSION or "?" end
end

C_ChatInfo.RegisterAddonMessagePrefix("MYLOOT")
C_ChatInfo.RegisterAddonMessagePrefix("MYLOOT_SYNC")

-- =========================
-- DATABASE
-- =========================
MyLootDB = MyLootDB or {}

MyLootDB.items = MyLootDB.items or {}
MyLootDB.activeItem = MyLootDB.activeItem or nil
MyLootDB.winner = MyLootDB.winner or nil
MyLootDB.role = MyLootDB.role or "user"
MyLootDB.selectedBossIndex = MyLootDB.selectedBossIndex or 1

MyLootDB.raid = MyLootDB.raid or {}
MyLootDB.raid.raidID = MyLootDB.raid.raidID or "local_test_raid"
MyLootDB.raid.startedAt = MyLootDB.raid.startedAt or time()
MyLootDB.raid.superprioEnabled = MyLootDB.raid.superprioEnabled ~= false
MyLootDB.raid.prioData = MyLootDB.raid.prioData or {}
MyLootDB.raid.ffaItems = MyLootDB.raid.ffaItems or {}
MyLootDB.raid.bosses = MyLootDB.raid.bosses or {}



function MyLoot.GetSelectedBoss()
  local raid = MyLootDB.raid
  if not raid or not raid.bosses or #raid.bosses == 0 then return nil end

  local index = MyLootDB.selectedBossIndex or 1

  -- Index korrigieren falls außerhalb der Liste
  if index > #raid.bosses then
    index = #raid.bosses
    MyLootDB.selectedBossIndex = index
  end

  return raid.bosses[index]
end

function MyLoot.BroadcastFullState()
  if MyLootDB.role ~= "raidlead" then return end

  for bossIndex, boss in ipairs(MyLootDB.raid.bosses) do
    -- Boss-Info vorab senden
    local bossInfoMsg = "SYNC_BOSS:" .. bossIndex .. ":" .. (boss.bossName or "") .. ":" .. (boss.difficulty or "")
    C_ChatInfo.SendAddonMessage("MYLOOT_SYNC", bossInfoMsg, "RAID")

    for _, loot in ipairs(boss.items) do
      -- Item senden
      local msg = "LOOT_NEW:" .. bossIndex .. ":" .. loot.session .. ":" .. loot.itemLink
      C_ChatInfo.SendAddonMessage("MYLOOT_SYNC", msg, "RAID")

      -- Status senden (Format: LOOT_SYNC:bossIndex:session:player:type)
      local syncMsg = "LOOT_SYNC:" .. bossIndex .. ":" .. loot.session .. ":" .. (loot.assignedTo or "nil") .. ":" .. (loot.type or "nil")
      C_ChatInfo.SendAddonMessage("MYLOOT_SYNC", syncMsg, "RAID")
    end
  end

end


-- =========================
-- VIEWS
-- =========================

MyLoot.currentView = "loot"


-- =========================
-- ROLE SYSTEM
-- =========================
function MyLoot.IsRaidLead()
  -- Solo → immer Raidlead
  if not IsInGroup() then
    return true
  end

  return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

function MyLoot.UpdateRole()
  if MyLoot.IsRaidLead() then
    MyLootDB.role = "raidlead"
  else
    MyLootDB.role = "user"  --user
  end
end

-- =========================
-- UI BASE
-- =========================
local ui = CreateFrame("Frame", "MyLootUI", UIParent, "BackdropTemplate")
MyLoot.UI = ui

local dropdown = CreateFrame("Frame", "MyLootDropdown", UIParent, "BackdropTemplate")

dropdown:SetFrameStrata("FULLSCREEN_DIALOG")
dropdown:SetFrameLevel(9999)
dropdown:SetSize(200, 200)
dropdown:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
dropdown:SetBackdropColor(0, 0, 0, 0.95)
dropdown:Hide()

dropdown.buttons = {}

ui:SetSize(900, 650)
ui:SetPoint("CENTER")
ui:SetMovable(true)
ui:EnableMouse(true)
ui:RegisterForDrag("LeftButton")

ui:SetScript("OnDragStart", ui.StartMoving)
ui:SetScript("OnDragStop", ui.StopMovingOrSizing)

-- Alle offenen Dropdowns schließen wenn das Fenster versteckt wird
ui:SetScript("OnHide", function()
  if MyLootDropdown then MyLootDropdown:Hide() end
  if ui.statsTabButtons then
    for _, b in ipairs(ui.statsTabButtons) do
      if b._popup then b._popup:Hide() end
    end
  end
end)

ui:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
ui:SetBackdropColor(0, 0, 0, 0.9)
ui:Hide()

-- ESC schließt das Fenster
table.insert(UISpecialFrames, "MyLootUI")

-- X-Button zum Schließen
local closeBtn = CreateFrame("Button", nil, ui, "UIPanelCloseButton")
closeBtn:SetSize(26, 26)
closeBtn:SetPoint("TOPRIGHT", ui, "TOPRIGHT", -4, -4)
closeBtn:SetScript("OnClick", function()
  ui:Hide()
end)

-- Titel
ui.title = ui:CreateFontString(nil, "OVERLAY", "GameFontNormal")
ui.title:SetPoint("TOP", 0, -10)
ui.title:SetText("WeltenWandler Raid Tools")

-- Sidebar
local sidebar = CreateFrame("Frame", nil, ui, "BackdropTemplate")
sidebar:SetSize(160, 580)
sidebar:SetPoint("TOPLEFT", ui, "TOPLEFT", 10, -40)

-- Content
local content = CreateFrame("Frame", nil, ui)
content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 10, 0)
content:SetSize(700, 580)
ui.content = content

-- Panels
ui.topPanel = CreateFrame("Frame", nil, content)
ui.topPanel:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
ui.topPanel:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
ui.topPanel:SetHeight(80)
ui.topPanel:SetPoint("TOP", 0, 0)

ui.prioPanel = CreateFrame("Frame", nil, content)
ui.prioPanel:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -90)
ui.prioPanel:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -90)
ui.prioPanel:SetHeight(180)
ui.prioPanel:SetPoint("TOP", ui.topPanel, "BOTTOM", 0, -10)

ui.bottomPanel = CreateFrame("Frame", nil, content)
ui.bottomPanel:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -280)
ui.bottomPanel:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -280)
ui.bottomPanel:SetHeight(300)
ui.bottomPanel:SetPoint("TOP", ui.prioPanel, "BOTTOM", 0, -10)

-- =========================
-- MODERN SIDEBAR BUTTON
-- =========================
MyLoot.SidebarButtons = {}

local function CreateSidebarEntry(text, yOffset, onClick)
  local btn = CreateFrame("Button", nil, sidebar)

  btn:SetSize(150, 30)
  btn:SetPoint("TOPLEFT", 5, yOffset)

  -- TEXT
  local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("LEFT", 10, 0)
  label:SetText(text)

  -- HIGHLIGHT BAR (links)
  local highlight = btn:CreateTexture(nil, "BACKGROUND")
  highlight:SetColorTexture(1, 0.82, 0, 0.8) -- gold
  highlight:SetSize(3, 30)
  highlight:SetPoint("LEFT", 0, 0)
  highlight:Hide()

  btn.highlight = highlight

  -- HOVER BG
  local hover = btn:CreateTexture(nil, "BACKGROUND")
  hover:SetColorTexture(1, 1, 1, 0.25)
  hover:SetAllPoints()
  hover:Hide()

  -- EVENTS
  btn:SetScript("OnEnter", function()
    hover:Show()
  end)

  btn:SetScript("OnLeave", function()
    hover:Hide()
  end)

  btn:SetScript("OnMouseDown", function(self)
    -- reset alle
    for _, b in ipairs(MyLoot.SidebarButtons) do
      b.highlight:Hide()
    end

    -- aktiven markieren
    self.highlight:Show()

    if onClick then onClick() end
  end)

  table.insert(MyLoot.SidebarButtons, btn)

  return btn
end

CreateSidebarEntry("Loot", -10, function()
  MyLoot.ShowView("loot")
end)

CreateSidebarEntry("Prio", -50, function()
  MyLoot.ShowView("prio")
end)

CreateSidebarEntry("Raid", -90, function()
  MyLoot.ShowView("raid")
end)

CreateSidebarEntry("Stats", -130, function()
  MyLoot.ShowView("stats")
end)

CreateSidebarEntry("Import", -170, function()
  MyLoot.ShowView("import")
end)


MyLoot.SidebarButtons[1].highlight:Show()

-- =========================
-- SIDEBAR BORDER
-- =========================
local border = ui:CreateTexture(nil, "BACKGROUND")
border:SetColorTexture(1, 1, 1, 0.8)

border:SetWidth(0.5)
border:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
border:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 0, 0)

-- Versionsanzeige unten links in der Sidebar
local versionLabel = sidebar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
versionLabel:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 8, 8)
versionLabel:SetText("v" .. MyLoot.VERSION)


function MyLoot.ShowView(view)
  MyLoot.currentView = view

  local mapping = {
    loot   = 1,
    prio   = 2,
    raid   = 3,
    stats  = 4,
    import = 5,
  }

  -- alle resetten
  for _, b in ipairs(MyLoot.SidebarButtons) do
    b.highlight:Hide()
  end

  -- aktiven setzen
  local idx = mapping[view]
  if idx and MyLoot.SidebarButtons[idx] then
    MyLoot.SidebarButtons[idx].highlight:Show()
  end

  MyLoot.Render()
end


-- =========================
-- BOSS FUNKTION
-- =========================

local DIFFICULTY_NAMES = {
  -- Aktuelle Raids (flexibel)
  [14] = "Normal",
  [15] = "Heroisch",
  [16] = "Mythisch",
  [17] = "LFR",
  -- Alte 10/25er Raids
  [3]  = "10 Normal",
  [4]  = "25 Normal",
  [5]  = "10 Heroisch",
  [6]  = "25 Heroisch",
  -- 5er Dungeons
  [1]  = "Normal",
  [2]  = "Heroisch",
  [23] = "Mythisch",
  -- Timewalking
  [24] = "Timewalking",
  [33] = "Timewalking",
}

function MyLoot.AddBoss(name, difficultyID)
  local raid = MyLootDB.raid
  if not raid then return end

  local diffLabel = DIFFICULTY_NAMES[difficultyID] or ("Diff " .. (difficultyID or "?"))

  -- Prüfen ob Boss auf dieser Schwierigkeit schon existiert → dann neuer Kill
  for i, b in ipairs(raid.bosses) do
    if b.bossName == name and b.difficulty == diffLabel then
      b.killID = (b.killID or 1) + 1
      b.items = {}
      b._slotUIDs = {}
      b._lootUIDCounter = 0
      b._sessionCounter = 0

      MyLootDB.selectedBossIndex = i

      MyLoot.Render()
      return
    end
  end

  -- Neuer Eintrag (neuer Boss oder neue Schwierigkeit)
  local boss = {
    bossName = name,
    difficulty = diffLabel,
    items = {},
    timestamp = time(),
    killID = 1,
    bossID = name,
  }

  table.insert(raid.bosses, boss)

  MyLootDB.selectedBossIndex = #raid.bosses

  MyLoot.Render()
end


-- =========================
-- MAIN RENDER
-- =========================
function MyLoot.Render()
  if MyLootDropdown then MyLootDropdown:Hide() end
  local ui = MyLoot.UI
  -- Alle Stats-Dropdowns schließen (unabhängig von View/Sichtbarkeit)
  if ui.statsTabButtons then
    for _, b in ipairs(ui.statsTabButtons) do
      if b._popup then b._popup:Hide() end
    end
  end
  if not ui:IsShown() then return end

  local view = MyLoot.currentView

  -- ScrollFrames verstecken wenn nicht aktiv
  if ui.prioListFrame then
    ui.prioListFrame:SetShown(view == "prio")
  end
  if ui.importFrame then
    ui.importFrame:SetShown(view == "import")
  end
  if ui.statsScrollFrame then
    ui.statsScrollFrame:SetShown(view == "stats")
  end
  if ui.raidScrollFrame then
    ui.raidScrollFrame:SetShown(view == "raid")
  end

  -- Icon nur im Loot-Tab sichtbar
  if ui.activeItemIcon then
    ui.activeItemIcon:SetShown(view == "loot")
  end

  -- Panels leeren
  for _, p in ipairs({ui.topPanel, ui.prioPanel, ui.bottomPanel}) do

    -- Frames entfernen
    for _, c in ipairs({p:GetChildren()}) do
      c:Hide()
      c:ClearAllPoints()
    end

    -- Regions ausblenden (Texte leeren, Texturen verstecken)
    for _, region in ipairs({p:GetRegions()}) do
      if region:IsObjectType("FontString") then
        region:SetText("")
      end
      region:Hide()
    end

  end

 
  -- =========================
  -- VIEW SWITCH
  -- =========================
  if view == "loot" then
    
    MyLoot.RenderTopBar()
    MyLoot.RenderItemPrio()
    MyLoot.RenderLoot()

  elseif view == "prio" then

    MyLoot.RenderPrioList()

  elseif view == "raid" then

    MyLoot.RenderRaidView()

  elseif view == "stats" then

    MyLoot.RenderStatsView()

  elseif view == "import" then

    MyLoot.RenderImportView()

  end
end


-- =========================
-- COMMANDS
-- =========================
SLASH_WRT1 = "/wrt"
SlashCmdList["WRT"] = function()
  ui:SetShown(not ui:IsShown())

  if ui:IsShown() then
    C_ChatInfo.SendAddonMessage("MYLOOT_SYNC", "REQUEST_SYNC", "RAID")

    if MyLootDB.role == "raidlead" then
      MyLoot.BroadcastFullState()
    end
  end

  MyLoot.Render()
end


SLASH_MYLOOTRESET1 = "/wrtreset"
SlashCmdList["MYLOOTRESET"] = function()
  local savedMinimapDB = MyLootDB.minimapDB  -- Position beibehalten
  MyLootDB = {
    ["items"]            = {},
    ["role"]             = "user",
    ["raid"]             = {
      ["ffaItems"]         = {},
      ["superprioEnabled"] = true,
      ["bosses"]           = {},
      ["prioData"]         = {},
    },
    ["selectedBossIndex"] = 1,
    ["minimapDB"]         = savedMinimapDB or {},
  }
  ReloadUI()
end

SLASH_WRTIMPORT1 = "/wrtimport"
SlashCmdList["WRTIMPORT"] = function(msg)
  MyLoot.ImportString(msg)
end


-- =========================
-- ADDON MESSAGE
-- =========================
function MyLoot.HandleMessage(prefix, message)
  if prefix ~= ADDON_PREFIX then return end

  local cmd, rest = message:match("^(%w+):(.+)$")

  if cmd == "SELECT" then
    MyLootDB.activeItem = rest
  elseif cmd == "ASSIGN" then
    MyLootDB.winner = rest
  end

  MyLoot.Render()
end

-- =========================
-- EVENTS
-- =========================
function MyLoot.CheckAutoReset()
  -- Prüfen ob überhaupt etwas zum Zurücksetzen vorhanden ist
  local hasBosses = MyLootDB.raid.bosses and #MyLootDB.raid.bosses > 0
  local hasPrio   = MyLootDB.raid.prioData and next(MyLootDB.raid.prioData) ~= nil
  if not hasBosses and not hasPrio then return false end

  -- Heutiger Reset-Zeitpunkt: heute 08:00 Uhr
  local now = time()
  local today = date("*t", now)
  today.hour = 8; today.min = 0; today.sec = 0
  local resetAt = time(today)

  -- Noch nicht 8 Uhr heute → kein Reset
  if now < resetAt then return false end

  -- Bereits heute nach 8 Uhr resettet → nicht erneut zurücksetzen
  if MyLootDB.lastResetAt and MyLootDB.lastResetAt >= resetAt then return false end

  -- Reset durchführen
  local bossCount = #(MyLootDB.raid.bosses or {})
  MyLootDB.raid.bosses        = {}
  MyLootDB.selectedBossIndex  = 1
  MyLootDB.raid.prioData      = {}
  MyLootDB.raid.itemPrioData  = {}
  MyLootDB.raid.importedAt    = nil
  MyLootDB.activeItem         = nil
  MyLootDB.lastResetAt        = now
  print(string.format(
    "|cff00ccff[WRT]|r Tagesreset – %d Boss-Einträge und Prioliste zurückgesetzt.",
    bossCount))
  return true
end

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    MyLoot.UpdateRole()
    -- Eigene Version eintragen + nach kurzer Verzögerung an Gruppe senden
    local self = UnitName("player")
    if self then MyLoot._addonUsers[self] = MyLoot.VERSION or "?" end
    C_Timer.After(5, MyLoot.BroadcastHello)

    local didReset = MyLoot.CheckAutoReset()
    -- REQUEST_SYNC nach einem Reset überspringen: verhindert dass andere Raidleads
    -- per LOOT_NEW die gerade gelöschten Boss-Einträge neu befüllen
    if not didReset then
      C_ChatInfo.SendAddonMessage("MYLOOT_SYNC", "REQUEST_SYNC", "RAID")
    end
    -- Prioliste automatisch aus WRT_RaidData laden:
    -- Immer importieren wenn keine Daten vorhanden, oder wenn ein anderer Raid
    -- mit prioList verfügbar ist als der aktuell gespeicherte.
    local hasExistingPrio = MyLootDB.raid.prioData and next(MyLootDB.raid.prioData) ~= nil
    local currentRaidID   = MyLootDB.raid.raidID

    local betterRaidAvailable = false
    if hasExistingPrio and WRT_RaidData and WRT_RaidData.raids then
      for _, r in ipairs(WRT_RaidData.raids) do
        if r.prioList and #r.prioList > 0 and r.raidID ~= currentRaidID then
          betterRaidAvailable = true
          break
        end
      end
    end

    if not hasExistingPrio or betterRaidAvailable then
      MyLoot.AutoImportFromRaidData()
    end

  elseif event == "LOOT_READY" then
    if not MyLoot.isEncounterActive then return end
    if MyLoot.hasLootedBoss then return end
    MyLoot.hasLootedBoss = true

    -- RCLC-Ansatz: Loot-Slots direkt lesen, kein Chat-Parsing
    MyLoot.HandleLootOpened()

  elseif event == "LOOT_CLOSED" then
    if MyLoot.isBossActive then

      MyLoot.isEncounterActive = false
      MyLoot.isBossActive = false

      -- aktiven Loot-Boss nutzen, nicht den aktuell im Dropdown gewählten
      local idx  = MyLoot._activeLootBossIndex
      local boss = idx and MyLootDB.raid.bosses[idx]
      if boss then
        boss._lootInitialized = false
        boss._slotUIDs        = nil
        boss._lootUIDCounter  = nil
      end
      -- _activeLootBossIndex bleibt bis ENCOUNTER_START gültig,
      -- damit AssignFromLootReceived auch nach LOOT_CLOSED den richtigen Boss findet
    end

  elseif event == "ENCOUNTER_LOOT_RECEIVED" then
    local encounterID, playerName, itemLink, quantity, className = ...
    MyLoot.AssignFromLootReceived(playerName, itemLink, className)

  elseif event == "LOOT_HISTORY_UPDATE_DROP" then
    local encounterID = ...
    MyLoot.UpdateRollTypes(encounterID)

  elseif event == "CHAT_MSG_ADDON" then
    local prefix, msg, channel, sender = ...

    -- bestehendes System
    MyLoot.HandleMessage(prefix, msg)

    if prefix == "MYLOOT_SYNC" then
      MyLoot.HandleSyncMessage(msg, sender)
    end

  elseif event == "PLAYER_ENTERING_WORLD" then
    -- Nach DC/Relog: Vergabe-Tracking reaktivieren, aber NUR wenn noch unvergebene Items
    -- für den aktiven Boss existieren (verhindert Re-Aktivierung nach normalem Teleport)
    if not MyLoot._awaitingLootAssignment then
      local idx  = MyLoot._activeLootBossIndex or MyLootDB.selectedBossIndex
      local boss = idx and MyLootDB.raid.bosses and MyLootDB.raid.bosses[idx]
      if boss and boss.items then
        for _, item in ipairs(boss.items) do
          if not item.assignedTo then
            MyLoot._awaitingLootAssignment = true
            break
          end
        end
      end
    end

  elseif event == "GROUP_ROSTER_UPDATE" then
    MyLoot.UpdateRole()
    -- Debounced HELLO: verhindert Spam bei schnellen Mehrfach-Updates
    if MyLoot._helloTimer then MyLoot._helloTimer:Cancel() end
    MyLoot._helloTimer = C_Timer.NewTimer(2, function()
      MyLoot.BroadcastHello()
      MyLoot._helloTimer = nil
    end)

  elseif event == "ENCOUNTER_START" then
    if not IsInRaid() then return end
    local encounterID, encounterName = ...

    MyLoot.UpdateRole()
    MyLoot.isEncounterActive        = true
    MyLoot.isBossActive             = true
    MyLoot.hasLootedBoss            = false
    MyLoot._activeLootBossIndex     = nil
    MyLoot._awaitingLootAssignment  = false


  elseif event == "ENCOUNTER_END" then
    if not IsInRaid() then return end
    local encounterID, encounterName, difficultyID, groupSize, success = ...

    if MyLootDB.lootDebug then
      print("|cff00ccff[WRT Debug]|r ENCOUNTER_END:", tostring(encounterName),
            "success=", tostring(success), "type=", type(success))
    end

    -- success kann je nach WoW-Version Integer (1/0) oder Boolean (true/false) sein
    local isKill = (success == 1 or success == true)

    if isKill then
      MyLoot.AddBoss(encounterName, difficultyID)
      MyLoot._activeLootBossIndex    = MyLootDB.selectedBossIndex
      MyLoot._activeEncounterID      = encounterID

      -- Zuweisung tracken bis alle Items vergeben oder nächster Pull
      MyLoot._awaitingLootAssignment = true
    else
      -- Wipe: Encounter-Flags zurücksetzen damit LOOT_READY nicht fälschlich feuert
      MyLoot.isEncounterActive = false
      MyLoot.isBossActive      = false
    end
  end
end)


SLASH_MYLOOTSYNC1 = "/sync"
SlashCmdList["MYLOOTSYNC"] = function()
  MyLoot.BroadcastFullState()
end

SLASH_WRTCHECK1 = "/wrtcheck"
SlashCmdList["WRTCHECK"] = function()
  -- Eigene Version senden + alle anderen anfragen
  MyLoot.BroadcastHello()
  local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
  if channel then
    C_ChatInfo.SendAddonMessage("MYLOOT_SYNC", "HELLO_REQUEST", channel)
  end
  MyLoot.ShowVersionWindow()
end

SLASH_WRTDEBUG1 = "/wrtdebug"
SlashCmdList["WRTDEBUG"] = function()
  MyLootDB.lootDebug = not MyLootDB.lootDebug
  if MyLootDB.lootDebug then
    print("|cff00ccff[WRT Debug]|r Loot-Debug |cff00ff00aktiviert|r")
  else
    print("|cff00ccff[WRT Debug]|r Loot-Debug |cffff4444deaktiviert|r")
  end
end