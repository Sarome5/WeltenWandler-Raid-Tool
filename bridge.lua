MyLootBridge = MyLootBridge or {}
MyLootBridge.outgoing = MyLootBridge.outgoing or {}

function MyLoot.SendToBridge(type, data)
  table.insert(MyLootBridge.outgoing, {
    type = type,
    data = data,
    timestamp = time()
  })

  print("→ Bridge:", type)
end