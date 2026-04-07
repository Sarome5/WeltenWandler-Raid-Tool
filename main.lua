MyLoot = MyLoot or {}
MyLoot.VERSION = "0.1.0"
MyLoot.GITHUB  = "https://github.com/Sarome5/WeltenWandler-Raid-Tool"

local ADDON_PREFIX = "MYLOOT"

-- =========================
-- INIT
-- =========================
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_LOOT")
frame:RegisterEvent("LOOT_READY")
frame:RegisterEvent("LOOT_CLOSED")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("ENCOUNTER_START")
frame:RegisterEvent("ENCOUNTER_END")

MyLoot.isEncounterActive = false
MyLoot.isBossActive = false
MyLoot.hasLootedBoss = false

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
    for _, loot in ipairs(boss.items) do

      -- Item senden
      local msg = "LOOT_NEW:" .. bossIndex .. ":" .. loot.session .. ":" .. loot.itemLink
      C_ChatInfo.SendAddonMessage("MYLOOT_SYNC", msg, "RAID")

      -- Status senden
      local syncMsg = "LOOT_SYNC:" .. loot.session .. ":" .. (loot.assignedTo or "nil") .. ":" .. (loot.type or "nil")
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
    return false
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
  if MyLootDropdown then
    MyLootDropdown:Hide()
  end
  local ui = MyLoot.UI
  if not ui:IsShown() then return end

  local view = MyLoot.currentView

  -- ScrollFrames verstecken wenn nicht aktiv
  if ui.prioListFrame then
    ui.prioListFrame:SetShown(view == "prio")
  end
  if ui.importFrame then
    ui.importFrame:SetShown(view == "import")
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

    -- Texte leeren
    for _, region in ipairs({p:GetRegions()}) do
      if region:IsObjectType("FontString") then
        region:SetText("")
      end
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

    local txt = ui.prioPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    txt:SetPoint("CENTER")
    txt:SetText("Raid View (coming soon)")

  elseif view == "stats" then

    local txt = ui.prioPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    txt:SetPoint("CENTER")
    txt:SetText("Stats View (coming soon)")

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

SLASH_MYLOOTTEST1 = "/loottest"
SlashCmdList["MYLOOTTEST"] = function()
  local item = select(2, GetItemInfo(19019)) or "|cff0070dd|Hitem:19019:::::::::::::|h[???]|h|r"

  local boss = MyLoot.GetSelectedBoss()

  if boss then
    table.insert(boss.items, {
      itemLink = item,
      assignedTo = nil,
      type = nil
    })
  end

  table.insert(MyLootDB.raid.bosses, {
    bossName = "Boss 2",
    items = {}
  })

  -- Dummy Prio
  MyLoot.SetDummyPrio(item)

  MyLootDB.activeItem = item
  MyLoot.Render()
end

SLASH_MYLOOTRESET1 = "/wrtreset"
SlashCmdList["MYLOOTRESET"] = function()
  MyLootDB = {
  ["items"] = {
  },
  ["role"] = "user",
  ["raid"] = {
  ["ffaItems"] = {
  },
  ["superprioEnabled"] = true,
  ["bosses"] = {
  {
  ["bossName"] = "Test Boss",
  ["items"] = {
  },
  },
  },
  ["prioData"] = {
  },
  },
  ["selectedBossIndex"] = 1,
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
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    MyLoot.UpdateRole()
    C_ChatInfo.SendAddonMessage("MYLOOT_SYNC", "REQUEST_SYNC", "RAID")

  elseif event == "LOOT_READY" then
    if not MyLoot.isEncounterActive then
      return
    end

    if MyLoot.hasLootedBoss then
      return
    end

    MyLoot.hasLootedBoss = true

    MyLoot._seenLoot = {}
    MyLoot.HandleLootOpened()

  elseif event == "LOOT_CLOSED" then
    if MyLoot.isBossActive then

      MyLoot.isEncounterActive = false
      MyLoot.isBossActive = false

      local boss = MyLoot.GetSelectedBoss()
      if boss then
        boss._lootInitialized = false
        boss._slotUIDs = nil
        boss._lootUIDCounter = nil
      end
    end

  elseif event == "CHAT_MSG_LOOT" then
    MyLoot.HandleLoot(...)

  elseif event == "CHAT_MSG_ADDON" then
    local prefix, msg, channel, sender = ...

    -- bestehendes System
    MyLoot.HandleMessage(prefix, msg)

    if prefix == "MYLOOT_SYNC" then
      MyLoot.HandleSyncMessage(msg, sender)
    end

  elseif event == "ENCOUNTER_START" then
    local encounterID, encounterName = ...

    MyLoot.isEncounterActive = true
    MyLoot.isBossActive = true
    MyLoot.hasLootedBoss = false


  elseif event == "ENCOUNTER_END" then
    local encounterID, encounterName, difficultyID, groupSize, success = ...

    if success == 1 then
      MyLoot.AddBoss(encounterName, difficultyID)
    end
  end
end)


SLASH_MYLOOTSYNC1 = "/sync"
SlashCmdList["MYLOOTSYNC"] = function()
  MyLoot.BroadcastFullState()
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