MyLoot = MyLoot or {}

-- =========================
-- SEND HELPER
-- =========================
local function Send(msg)
  C_ChatInfo.SendAddonMessage("MYLOOT", msg, "RAID")
end

MyLoot._msgQueue = MyLoot._msgQueue or {}
MyLoot._sending = false
MyLoot._clientBuffer = {}

function MyLoot.QueueMessage(prefix, msg, channel, target)
  table.insert(MyLoot._msgQueue, {
    prefix = prefix,
    msg = msg,
    channel = channel,
    target = target
  })

  MyLoot.ProcessQueue()
end

function MyLoot.ProcessQueue()
  if MyLoot._sending then return end
  if #MyLoot._msgQueue == 0 then return end

  MyLoot._sending = true

  local data = table.remove(MyLoot._msgQueue, 1)

  if data.target then
    C_ChatInfo.SendAddonMessage(data.prefix, data.msg, data.channel, data.target)
  else
    C_ChatInfo.SendAddonMessage(data.prefix, data.msg, data.channel)
  end

  C_Timer.After(0.05, function()
    MyLoot._sending = false
    MyLoot.ProcessQueue()
  end)
end

function MyLoot.AddItem(itemLink)
  local boss = MyLoot.GetSelectedBoss()
  if not boss then return end

  -- ID GENERIERUNG
  boss._sessionCounter = (boss._sessionCounter or 0) + 1
  local session = boss._sessionCounter


  local itemID = itemLink:match("item:(%d+)")
  local uid = itemID .. "-" .. session

  local loot = {
    uid = uid,
    session = session,
    itemLink = itemLink,
    assignedTo = nil,
    type = nil,
    status = "new",
    ui = {
      selectedPlayer = nil,
      selectedType = "MS"
    }
  }

  table.insert(boss.items, loot)

  -- SYNC + PRIO
  MyLoot.SendNewItem(loot)

  return loot
end


function MyLoot.SendClientLoot(link, uid)
  local encoded = link:gsub(":", ";"):gsub("|", "!")

  if not uid then
    return
  end

  local msg = "CLIENT_LOOT:" .. uid .. ":" .. encoded
  MyLoot.QueueMessage("MYLOOT_SYNC", msg, "RAID")
end

-- =========================
-- LOOT HANDLING
-- =========================

-- Erkennt Loot-Vergaben aus dem deutschen WoW-Chat
-- Unterstützte Muster:
--   "[Spieler] gewinnt [Item]. (Bedarf)"   → MS
--   "[Spieler] gewinnt [Item]. (Gier)"     → OS
--   "[Spieler] gewinnt [Item]. (Transmog)" → Transmog
--   "[Item] geht an [Spieler]."            → MS (Master Looter)
--   "Du hast geplündert: [Item]."          → eigener Loot

local LOOT_TYPE_MAP = {
  ["Bedarf"]   = "MS",
  ["Gier"]     = "OS",
  ["Transmog"] = "Transmog",
}

-- Debug-Modus: nur lokal sichtbar, nie im Raid-Chat
-- Toggle mit /wrtdebug
local function LootDebug(msg)
  if MyLootDB.lootDebug then
    print("|cff00ccff[WRT Debug]|r " .. msg)
  end
end

function MyLoot.TryAutoAssignFromChat(msg)
  LootDebug("Chat: " .. msg)

  local itemLink = msg:match("|Hitem:.-|h.-|h")
  if not itemLink then
    LootDebug("Kein Item-Link gefunden → ignoriert")
    return
  end

  local player   = nil
  local lootType = "MS"

  -- Muster 1: "Ihr erhaltet Beute: [Item]" → eigener Charakter (kein Loot-Typ)
  if msg:find("Ihr erhaltet Beute:") then
    player   = UnitName("player")
    lootType = nil
    LootDebug("Muster 1 (Selbst): " .. player)

  -- Muster 2: "[Spieler] erhält Beute: [Item]" → anderer Spieler
  elseif msg:find("erhält Beute:") then
    player = msg:match("^(.+) erhält Beute:")
    if player then player = player:match("^%s*(.-)%s*$") end
    LootDebug("Muster 2 (Anderer): " .. tostring(player))

  -- Muster 3: "[Spieler] gewinnt [Item] (Bedarf/Gier/Transmog)" → Würfelsystem
  else
    local winner, rollType = msg:match("^(.+) gewinnt .+%((.-)%)")
    if winner then
      player   = winner:match("^%s*(.-)%s*$")
      lootType = LOOT_TYPE_MAP[rollType] or "MS"
      LootDebug("Muster 3 (Würfel): " .. tostring(player) .. " / " .. tostring(rollType) .. " → " .. lootType)
    else
      LootDebug("Kein Muster erkannt für: " .. msg)
    end
  end

  if not player or player == "" then return end

  -- Vollständigen Hitem-String extrahieren (inkl. BonusIDs)
  local chatItemString = itemLink:match("Hitem:([^|]+)")
  local chatItemID     = itemLink:match("item:(%d+)")
  if not chatItemID then return end

  local assigned = false

  -- Schritt 1: exakter Match auf Hitem-String (BonusID-sicher)
  for _, boss in ipairs(MyLootDB.raid.bosses) do
    for _, loot in ipairs(boss.items) do
      if loot.status ~= "assigned" and loot.itemLink then
        local lootItemString = loot.itemLink:match("Hitem:([^|]+)")
        if lootItemString == chatItemString then
          loot.assignedTo = player
          loot.type       = lootType
          loot.status     = "updated"
          assigned = true
          break
        end
      end
    end
    if assigned then break end
  end

  -- Schritt 2: Fallback auf Base-ItemID (falls BonusID-String abweicht)
  if not assigned then
    for _, boss in ipairs(MyLootDB.raid.bosses) do
      for _, loot in ipairs(boss.items) do
        if loot.status ~= "assigned" and loot.itemLink then
          local lootItemID = loot.itemLink:match("item:(%d+)")
          if lootItemID == chatItemID then
            loot.assignedTo = player
            loot.type       = lootType
            loot.status     = "updated"
            assigned = true
            break
          end
        end
      end
      if assigned then break end
    end
  end

  MyLoot.Render()
end

function MyLoot.SendNewItem(loot)
  local bossIndex = MyLootDB.selectedBossIndex or 1
  local encoded = loot.itemLink:gsub(":", ";")
  local boss = MyLoot.GetSelectedBoss()
  local raidID = MyLootDB.raid.raidID or "local"

  local globalUID = raidID .. "-" .. bossIndex .. "-" .. (boss.killID or 1) .. "-" .. loot.uid

  local msg = "LOOT_NEW:" .. bossIndex .. ":" .. loot.session .. ":" .. globalUID .. ":" .. encoded

  MyLoot.QueueMessage("MYLOOT_SYNC", msg, "RAID")

end

function MyLoot.HandleLoot(msg)
  MyLoot.TryAutoAssignFromChat(msg)
end

function MyLoot.HandleLootOpened()
  MyLoot._isLooting = true

  local boss = MyLoot.GetSelectedBoss()
  if not boss then return end
  if not boss._lootInitialized then
    boss._slotUIDs = {}
    boss._lootUIDCounter = 0
    boss._lootInitialized = true
  end

  boss._slotUIDs = boss._slotUIDs or {}

  local numItems = GetNumLootItems()

  for i = 1, numItems do
    local link = GetLootSlotLink(i)

    if link and link:find("|Hitem:") then
      local _, _, quality = GetItemInfo(link)

      if not quality then
        -- Item-Daten noch nicht geladen → nachladen und nochmal versuchen
        local item = Item:CreateFromItemLink(link)
        item:ContinueOnItemLoad(function()
          MyLoot.HandleLootOpened()
        end)
      elseif quality >= 3 then


        local itemID = link:match("item:(%d+)")
        local uid = boss._slotUIDs[i]

        if not uid then
          boss._lootUIDCounter = (boss._lootUIDCounter or 0) + 1
          uid = itemID .. "-" .. boss._lootUIDCounter
          boss._slotUIDs[i] = uid
        end

        local exists = false
        for _, existing in ipairs(boss.items) do
          if existing.uid == uid then
            exists = true
            break
          end
        end

        if not exists then
          if MyLootDB.role == "raidlead" then
            table.insert(boss.items, {
              uid = uid,
              itemLink = link,
              slot = i,
              processed = false,
              session = nil,
              assignedTo = nil,
              type = nil,
              status = "new",
              ui = {
                selectedPlayer = nil,
                selectedType = "MS"
              }
            })
          else
            MyLoot.SendClientLoot(link, uid)
          end
        end

      end
    end

  end

  MyLoot.ProcessLootTable()
  C_Timer.After(1, function()
    MyLoot._isLooting = false
  end)
  if MyLootDB.role ~= "raidlead" then
    MyLoot.QueueMessage("MYLOOT_SYNC", "CLIENT_DONE", "RAID")
  end
end


function MyLoot.ProcessLootTable()
  local boss = MyLoot.GetSelectedBoss()
  if not boss then return end

  for _, loot in ipairs(boss.items) do
    if not loot.processed then

      if MyLootDB.role == "raidlead" then
        loot.processed = true

        loot.session = (boss._sessionCounter or 0) + 1
        boss._sessionCounter = loot.session

        if not loot.uid then
          local itemID = loot.itemLink:match("item:(%d+)")
          loot.uid = itemID .. "-" .. loot.session
        end

        MyLoot.SendNewItem(loot)

      else
        if not loot.session then
          loot.processed = true
          MyLoot.SendClientLoot(loot.itemLink, loot.uid)
        end
      end

    end
  end

  MyLoot.Render()
end
-- =========================
-- API FUNKTION
-- =========================

function MyLoot.SyncLootToServer(loot)
  local boss = MyLoot.GetSelectedBoss()
  local raidID = MyLootDB.raid.raidID or "local"

  local data = {
    raidID = raidID,
    boss = boss and boss.bossName,
    kill = boss and boss.killID,
    uid = loot.uid,
    item = loot.itemLink,
    player = loot.assignedTo,
    type = loot.type,
    session = loot.session
  }

  local json = string.format(
    '{"type":"loot_assigned","raidID":"%s","boss":"%s","uid":"%s","item":"%s","player":"%s","lootType":"%s"}',
    raidID or "",
    boss and boss.bossName or "",
    loot.uid or "",
    loot.itemLink or "",
    loot.assignedTo or "",
    loot.type or ""
  )

end


-- =========================
-- DROPDOWN (SPIELER)
-- =========================

local function GetRaidMembers()
  local members = {}

  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local name = select(1, GetRaidRosterInfo(i))
      if name then members[#members + 1] = name end
    end

  elseif IsInGroup() then
    for i = 1, GetNumGroupMembers() - 1 do
      local name = UnitName("party"..i)
      if name then members[#members + 1] = name end
    end

    members[#members + 1] = UnitName("player")

  else
    members[#members + 1] = UnitName("player")
    members[#members + 1] = "Test1"
    members[#members + 1] = "Test2"
  end

  return members
end

local playerDropdown = CreateFrame("Frame", "MyLootPlayerDropdown", UIParent, "UIDropDownMenuTemplate")
UIDropDownMenu_SetDisplayMode(playerDropdown, "MENU")

function MyLoot.ShowWinnerDropdown(index, anchor)

  local members = GetRaidMembers()

  UIDropDownMenu_Initialize(playerDropdown, function(self, level)
    for _, name in ipairs(members) do
      local info = UIDropDownMenu_CreateInfo()

      info.text = name

      info.func = function()
        local boss = MyLoot.GetSelectedBoss()
        local loot = boss.items[index]

        loot.ui = loot.ui or {}
        loot.ui.selectedPlayer = name

        MyLoot.Render()
      end

      UIDropDownMenu_AddButton(info)
    end
  end)

  ToggleDropDownMenu(1, nil, playerDropdown, anchor, 0, 0)
end

-- =========================
-- RENDER LOOT LISTE
-- =========================
function MyLoot.RenderLoot()
  local ui     = MyLoot.UI
  local y      = -10
  local isLead = MyLootDB.role == "raidlead"

  local boss = MyLoot.GetSelectedBoss()
  if not boss then return end

  for _, loot in ipairs(boss.items) do
    local itemLink = loot.itemLink
    if not itemLink or not itemLink:find("|Hitem:") then end
    if itemLink and itemLink:find("|Hitem:") then

      -- Item-Daten
      local name, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemLink)
      if not name then
        local item = Item:CreateFromItemLink(itemLink)
        if not item:IsItemDataCached() then
          item:ContinueOnItemLoad(function() MyLoot.Render() end)
        end
        name = itemLink:match("%[(.-)%]") or "Item"
      end

      -- Item Button
      local btn = CreateFrame("Button", nil, ui.bottomPanel, "BackdropTemplate")
      btn:SetSize(280, 26)
      btn:SetPoint("TOPLEFT", 0, y)
      btn:EnableMouse(true)
      btn:RegisterForClicks("LeftButtonUp")
      btn:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 8 })

      local function UpdateColor(self, hover)
        if MyLootDB.activeItem == itemLink then
          self:SetBackdropColor(0.4, 0.35, 0.1, 0.9)
        elseif loot.assignedTo then
          self:SetBackdropColor(0, 0.35, 0, 0.7)
        elseif hover then
          self:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
        else
          self:SetBackdropColor(0, 0, 0, 0.3)
        end
      end
      UpdateColor(btn, false)

      local icon = btn:CreateTexture(nil, "ARTWORK")
      icon:SetSize(20, 20)
      icon:SetPoint("LEFT", 5, 0)
      if texture then icon:SetTexture(texture) end

      local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      nameText:SetPoint("LEFT", 30, 0)
      nameText:SetPoint("RIGHT", -5, 0)
      nameText:SetJustifyH("LEFT")
      nameText:SetWordWrap(false)
      nameText:SetText(name)

      btn:SetScript("OnClick", function()
        MyLootDB.activeItem = itemLink
        MyLoot.Render()
      end)
      btn:SetScript("OnEnter", function(self)
        UpdateColor(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(itemLink)
        GameTooltip:Show()
      end)
      btn:SetScript("OnLeave", function(self)
        UpdateColor(self, false)
        GameTooltip:Hide()
      end)

      -- Vergabe-Anzeige (rechts neben Item)
      local infoFrame = CreateFrame("Frame", nil, ui.bottomPanel)
      infoFrame:SetSize(300, 26)
      infoFrame:SetPoint("LEFT", btn, "RIGHT", 8, 0)

      if loot.assignedTo then
        -- Gewinner aus Chat erkannt
        local classColor = MyLootDB.knownClasses and MyLootDB.knownClasses[loot.assignedTo]
        local colorStr = classColor and RAID_CLASS_COLORS[classColor] and RAID_CLASS_COLORS[classColor].colorStr or "ffffffff"

        local assignTxt = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        assignTxt:SetPoint("LEFT", 0, 0)
        assignTxt:SetText("|c" .. colorStr .. loot.assignedTo .. "|r")

        if loot.type then
          local typeLabels = { MS = "Bedarf", OS = "Gier", DE = "Transmog", Transmog = "Transmog" }
          local label = typeLabels[loot.type] or loot.type
          local typeTxt = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
          typeTxt:SetPoint("LEFT", 140, 0)
          typeTxt:SetTextColor(1, 0.82, 0)
          typeTxt:SetText(label)
        end


      else
        -- Noch nicht vergeben
        local waitTxt = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        waitTxt:SetPoint("LEFT", 0, 0)
        waitTxt:SetText("—")
      end

      y = y - 32
    end
  end
end

function MyLoot.HandleSyncMessage(msg, sender)

  -- =========================
  -- JOIN SYNC REQUEST
  -- =========================
  if msg == "REQUEST_SYNC" then
    if MyLootDB.role ~= "raidlead" then return end

    for bossIndex, boss in ipairs(MyLootDB.raid.bosses) do
      for _, loot in ipairs(boss.items) do

        local encoded = loot.itemLink:gsub(":", ";")
        local raidID = MyLootDB.raid.raidID or "local"
        local globalUID = raidID .. "-" .. bossIndex .. "-" .. (boss.killID or 1) .. "-" .. loot.uid

        local msg = "LOOT_NEW:" .. bossIndex .. ":" .. loot.session .. ":" .. globalUID .. ":" .. encoded
        MyLoot.QueueMessage("MYLOOT_SYNC", msg, "WHISPER", sender)

        local syncMsg = "LOOT_SYNC:" .. loot.session .. ":" .. (loot.assignedTo or "nil") .. ":" .. (loot.type or "nil")
        MyLoot.QueueMessage("MYLOOT_SYNC", syncMsg, "WHISPER", sender)

      end
    end

    return
  end

  -- eigene Nachrichten ignorieren
  local playerName = UnitName("player")
  local fullPlayerName = playerName .. "-" .. GetNormalizedRealmName()

  if sender == fullPlayerName then return end
  local cmd, rest = msg:match("^([^:]+):(.+)$")

  if not cmd then
    cmd = msg
  end

  if cmd == "LOOT_NEW" then
    local bossIndex, session, uid, itemLink = rest:match("^(%d+):(%d+):([^:]+):(.+)$")

    if not itemLink then
      bossIndex, session, itemLink = rest:match("^(%d+):(%d+):(.+)$")
      uid = "fallback-" .. session
    end
    itemLink = itemLink:gsub(";", ":")
    session = tonumber(session)
    bossIndex = tonumber(bossIndex)

    local boss = MyLootDB.raid.bosses[bossIndex]

    if not boss then
      boss = {
        bossName = "Boss " .. bossIndex,
        items = {}
      }

      MyLootDB.raid.bosses[bossIndex] = boss
    end

    local itemID = itemLink:match("item:(%d+)")

    local exists = false

    for _, l in ipairs(boss.items) do
      if l.uid == uid then
        exists = true
        break
      end
    end

    if not exists then
      table.insert(boss.items, {
        uid = uid,
        session = session,
        itemLink = itemLink,
        assignedTo = nil,
        type = nil,
        status = "synced",
        processed = true,
        ui = {
          selectedPlayer = nil,
          selectedType = "MS"
        }
      })

    else
    end

  elseif cmd == "CLIENT_LOOT" then
    if MyLootDB.role ~= "raidlead" then return end


    local uid, encoded = rest:match("^([^:]+):(.+)$")
    local itemLink = encoded:gsub("!", "|"):gsub(";", ":")

    local boss = MyLoot.GetSelectedBoss()
    boss._clientBuffer = boss._clientBuffer or {}

    table.insert(boss._clientBuffer, {
      uid = uid,
      itemLink = itemLink
    })


  elseif cmd == "CLIENT_DONE" then
    if MyLootDB.role ~= "raidlead" then return end


    local boss = MyLoot.GetSelectedBoss()
    if not boss then return end

    for _, data in ipairs(boss._clientBuffer or {}) do
      local uid = data.uid
      local itemLink = data.itemLink

      local exists = false
      for _, existing in ipairs(boss.items) do
        if existing.uid == uid then
          exists = true
          break
        end
      end

      if not exists then
        table.insert(boss.items, {
          uid = uid,
          itemLink = itemLink,
          slot = -1,
          processed = false,
          session = nil,
          assignedTo = nil,
          type = nil,
          status = "new",
          ui = {
            selectedPlayer = nil,
            selectedType = "MS"
          }
        })
      end
    end
    boss._clientBuffer = {}
    MyLoot._clientBuffer = {}
    MyLoot.ProcessLootTable()


  elseif cmd == "LOOT_SYNC" then
    local session, player, type = strsplit(":", rest)
    session = tonumber(session)

    for _, boss in ipairs(MyLootDB.raid.bosses) do
      for _, loot in ipairs(boss.items) do
        if loot.session == session then
          loot.assignedTo = (player ~= "nil") and player or nil
          loot.type = (type ~= "nil") and type or nil
          loot.status = "synced"
          break
        end
      end
    end
  end

  MyLoot.Render()
end