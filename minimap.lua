MyLoot = MyLoot or {}

-- =========================
-- MINIMAP BUTTON (LibDBIcon)
-- =========================

local LDB     = LibStub("LibDataBroker-1.1")
local DBIcon  = LibStub("LibDBIcon-1.0")

local dataObject = LDB:NewDataObject("WeltenWandlerRaidTool", {
  type  = "launcher",
  label = "WeltenWandler Raid Tool",
  icon  = "Interface/AddOns/WeltenWandler_Raid_Tool/textures/minimap_icon.tga",

  OnClick = function(_, mouseButton)
    if mouseButton == "LeftButton" then
      local ui = MyLoot.UI
      ui:SetShown(not ui:IsShown())

      if ui:IsShown() then
        C_ChatInfo.SendAddonMessage("MYLOOT_SYNC", "REQUEST_SYNC", "RAID")
        if MyLootDB.role == "raidlead" then
          MyLoot.BroadcastFullState()
        end
      end

      MyLoot.Render()
    end
  end,

  OnTooltipShow = function(tt)
    tt:AddLine("WeltenWandler Raid Tool", 1, 0.82, 0)
    tt:AddLine("Linksklick: Fenster öffnen/schließen", 0.8, 0.8, 0.8)
    tt:AddLine("Ziehen: Position anpassen", 0.8, 0.8, 0.8)
  end,
})

-- =========================
-- INIT (nach PLAYER_LOGIN)
-- =========================
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
  -- Alte Position-Daten migrieren (minimapAngle / minimapX+Y → minimapDB)
  MyLootDB.minimapDB = MyLootDB.minimapDB or {}

  if MyLootDB.minimapAngle then
    MyLootDB.minimapDB.minimapPos = MyLootDB.minimapAngle % 360
    MyLootDB.minimapAngle = nil
  end

  if MyLootDB.minimapX then
    local angle = math.deg(math.atan2(MyLootDB.minimapY or 0, MyLootDB.minimapX)) % 360
    MyLootDB.minimapDB.minimapPos = angle
    MyLootDB.minimapX = nil
    MyLootDB.minimapY = nil
  end

  DBIcon:Register("WeltenWandlerRaidTool", dataObject, MyLootDB.minimapDB)
end)
