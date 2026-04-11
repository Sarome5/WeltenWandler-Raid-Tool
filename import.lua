MyLoot = MyLoot or {}

-- =========================
-- IMPORT SYSTEM
-- =========================

local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local function Base64Decode(data)
  data = string.gsub(data, '[^'..b..'=]', '')
  return (data:gsub('.', function(x)
      if (x == '=') then return '' end
      local r,f='',(b:find(x)-1)
      for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
      return r
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
      if (#x ~= 8) then return '' end
      local c=0
      for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
      return string.char(c)
    end))
end

-- =========================
-- PRIO BUILDER
-- =========================

-- Baut aus der flachen prios-Liste zwei Lookup-Tabellen:
--
-- prioData[characterName][itemID] = priority
--   → für prio_view.lua (was hat Spieler X auf der Liste?)
--
-- itemPrioData[itemID][priority] = { "Char1", "Char2", ... }
-- itemPrioData[itemID].superprio = { "Char3", ... }
--   → für loot.lua (wer will dieses Item?)

local function BuildPrioTables(prios, superprioEnabled)
  local prioData     = {}  -- player-centric
  local itemPrioData = {}  -- item-centric

  -- Schritt 1: Zählen wie oft ein Spieler dasselbe Item gewählt hat
  -- (Superprio = selbes Item auf allen 3 Slots)
  local itemCount = {}  -- itemCount[character][itemID] = Anzahl

  for _, entry in ipairs(prios) do
    local char   = entry.character
    local itemID = entry.itemID

    itemCount[char] = itemCount[char] or {}
    itemCount[char][itemID] = (itemCount[char][itemID] or 0) + 1
  end

  -- Schritt 2: Klassen cachen + Tabellen befüllen
  MyLootDB.knownClasses = MyLootDB.knownClasses or {}

  for _, entry in ipairs(prios) do
    local char     = entry.character
    local itemID   = entry.itemID
    local priority = entry.priority

    -- Klasse cachen (UNKNOWN ignorieren)
    if entry.wowClass and entry.wowClass ~= "UNKNOWN" then
      MyLootDB.knownClasses[char] = entry.wowClass
    end

    -- player-centric
    prioData[char] = prioData[char] or {}

    -- item-centric setup
    itemPrioData[itemID] = itemPrioData[itemID] or {
      [1] = {}, [2] = {}, [3] = {}, superprio = {}
    }

    local isSuperprio = superprioEnabled
                     and itemCount[char]
                     and itemCount[char][itemID] == 3

    if isSuperprio then
      -- Nur einmal in superprio eintragen (beim ersten Eintrag)
      if priority == 1 then
        prioData[char][itemID] = "superprio"
        table.insert(itemPrioData[itemID].superprio, char)
      end
    else
      prioData[char][itemID] = priority
      table.insert(itemPrioData[itemID][priority], char)
    end
  end

  return prioData, itemPrioData
end

-- =========================
-- IMPORT ENTRY POINT
-- =========================

-- =========================
-- AUTO-IMPORT AUS RAID DATA
-- =========================

-- Lädt die Prioliste automatisch aus WRT_RaidData wenn der Raid live ist.
-- Wird bei PLAYER_LOGIN aufgerufen wenn noch keine Prioliste geladen ist.
-- Ein manueller Import via /wrtimport überschreibt dies immer.
function MyLoot.AutoImportFromRaidData()
  local data = WRT_RaidData
  if not data or not data.raids or #data.raids == 0 then return false end

  -- Raid mit vollständiger Prioliste finden (zeitlich nächster zu jetzt)
  local now = time()
  local target = nil
  for _, raid in ipairs(data.raids) do
    if raid.prioList and #raid.prioList > 0 then
      if not target then
        target = raid
      else
        local distNew = math.abs((raid.scheduledAt   or 0) - now)
        local distOld = math.abs((target.scheduledAt or 0) - now)
        if distNew < distOld then target = raid end
      end
    end
  end

  if not target then return false end

  local superprioEnabled = target.superPrio == true
  local prioData, itemPrioData = BuildPrioTables(target.prioList, superprioEnabled)

  MyLootDB.raid.raidID           = target.raidID
  MyLootDB.raid.raidName         = target.raidName
  MyLootDB.raid.difficulty       = target.difficulty
  MyLootDB.raid.superprioEnabled = superprioEnabled
  MyLootDB.raid.prioData         = prioData
  MyLootDB.raid.itemPrioData     = itemPrioData
  MyLootDB.raid.importedAt       = now

  local playerCount = 0
  for _ in pairs(prioData) do playerCount = playerCount + 1 end
  print(string.format("|cff00ccff[WRT]|r Prioliste automatisch geladen: %d Spieler (%s).",
    playerCount, target.raidName or "?"))

  MyLoot.Render()
  return true
end


function MyLoot.ImportString(importString)
  if not importString or importString == "" then
    print("|cffff4444WRT:|r Import leer")
    return
  end

  -- Optionalen Prefix entfernen
  importString = importString:gsub("^WRT:", "")

  local decoded = Base64Decode(importString)

  if not decoded or decoded == "" then
    print("|cffff4444WRT:|r Decode fehlgeschlagen")
    return
  end

  -- Lua-Tabelle aus String laden
  local ok, data = pcall(function()
    return loadstring("return " .. decoded)()
  end)

  if not ok or type(data) ~= "table" then
    print("|cffff4444WRT:|r Parse fehlgeschlagen – ungültiges Format")
    return
  end

  if type(data.prios) ~= "table" then
    print("|cffff4444WRT:|r Fehlende 'prios' Liste im Import")
    return
  end

  -- =========================
  -- DATEN ÜBERNEHMEN
  -- =========================

  local superprioEnabled = data.superprio == true

  local prioData, itemPrioData = BuildPrioTables(data.prios, superprioEnabled)

  MyLootDB.raid.raidID            = data.raidID or "imported"
  MyLootDB.raid.raidName          = data.raidName or ""
  MyLootDB.raid.difficulty        = data.difficulty or ""
  MyLootDB.raid.superprioEnabled  = superprioEnabled
  MyLootDB.raid.prioData          = prioData
  MyLootDB.raid.itemPrioData      = itemPrioData
  MyLootDB.raid.importedAt        = time()

  -- Statistik ausgeben
  local playerCount = 0
  for _ in pairs(prioData) do playerCount = playerCount + 1 end

  local itemCount = 0
  for _ in pairs(itemPrioData) do itemCount = itemCount + 1 end

  print("|cff00ff00WRT:|r Import erfolgreich!")
  print("|cff00ff00WRT:|r Raid:|r " .. (data.raidName or "?") .. " [" .. (data.difficulty or "?") .. "]")
  print("|cff00ff00WRT:|r " .. playerCount .. " Spieler, " .. itemCount .. " Items importiert")
  if superprioEnabled then
    print("|cffffff00WRT:|r Superprio ist aktiv")
  end

  MyLoot.Render()
end
