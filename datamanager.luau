local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local DataManager = {}

DataManager.Profiles = {}
DataManager.PlayerInventories = {}
DataManager.GlobalWorldItems = {}

--Various types
type ToolConfig = {
	InstanceName: string,
	DisplayName: string,
	Icon: string,
	UseAnimation: Animation,

	Damage: number,
	Reach: number,
	EquippedSlot: string,
	Cooldown: number,
	StackSize: number,
	ToolType: string,
	PickaxeTier: number?,
}

type ArmorConfig = {
	InstanceName: string,
	DisplayName: string,
	BaseID: number,
	Protection: number,
	EquippedSlot: number
}

export type InventoryObject = {
	Player: Player,
	Character: Model,
	HRP: Part,
	PlayerInventory: DataManager.PlayerInventory,

	UpdateClient: (self: InventoryObject) -> (),
	SyncInventory: (self: InventoryObject) -> (),
	AddItem: (self: InventoryObject, itemID: number, quantity: number, toolConfig: table?, armorConfig: table?, toolInstance: Instance?) -> (),
	RemoveItem: (self: InventoryObject, itemID: number, quantity: number) -> (),
	PickupItem: (self: InventoryObject, itemID: number) -> (),
	DropItem: (self: InventoryObject, itemID: number, quantity: number) -> (),
	HasItem: (self: InventoryObject, itemID: number, quantity: number) -> (),
	GetItemQuantity: (self: InventoryObject, itemID: number) -> (),
	GetTotalQuantity: (self: InventoryObject) -> (),
	GetItemsByCategory: (self: InventoryObject, category: string) -> FilteredData?,
	GetInventoryItems: (self: InventoryObject) -> (),
	GetInventoryTools: (self: InventoryObject) -> (),
	GetInventoryArmor: (self: InventoryObject) -> (),
	ReturnTotalMaterialsCount: (self: InventoryObject) -> number,
	ClearInventory: (self: InventoryObject) -> (),
}

export type PlayerInventory = {
	Items: {[number]: number},
	Tools: {[string]: ToolConfig},
	Armor: {[string]: ArmorConfig}
}

--Retrieve player data
function DataManager.GetData(player: Players)
	local playerInventory = DataManager.PlayerInventories[player.UserId]
	if not playerInventory then return nil end
	return playerInventory :: PlayerInventory
end

--Sync inventory from data
function DataManager.SyncInventory(player: Player)
	local profile = DataManager.Profiles[player]
	local invObj: InventoryObject = DataManager.PlayerInventories[player.UserId]
	if not profile or not invObj then return end

	local playerTools = invObj.PlayerInventory.Tools
	local playerItems = invObj.PlayerInventory.Items

	for itemID, qty in playerItems do
		profile.Data.PlayerItems[tostring(itemID)] = qty
	end

	for itemIDStr, _ in profile.Data.PlayerItems do
		local id = tonumber(itemIDStr)
		if not playerItems[id] then
			profile.Data.PlayerItems[itemIDStr] = nil
		end
	end

	profile.Data.PlayerTools = {}
	for guid, toolData in playerTools do
		profile.Data.PlayerTools[guid] = {
			BaseID       = toolData.BaseID,
			InstanceName = toolData.InstanceName,
			DisplayName  = toolData.DisplayName,
			Damage       = toolData.Damage,
			Reach        = toolData.Reach,
			Cooldown     = toolData.Cooldown,
			EquippedSlot = toolData.EquippedSlot,
			ToolType     = toolData.ToolType,
			PickaxeTier  = toolData.PickaxeTier,
		}
	end
end

--Retrieve amount of an item a player has from , data
function DataManager.ReturnItemAmount(player: Player, itemID: number)
	itemID = tonumber(itemID)
	local invObj: InventoryObject = DataManager.PlayerInventories[player.UserId]
	local playerInventory: PlayerInventory = invObj.PlayerInventory
	if not playerInventory then warn(`PlayerInventory missing in invObject: {invObj} for {player}. Expected Inv; got {playerInventory}`) return end

	if not itemID then warn(`ItemID argument is missing. Required player and ID. Expected itemId:Number; got {itemID}. Invalid id or misshaped type.`) return end

	local itemAmount = playerInventory.Items[itemID] or 0
	return itemAmount
end

--Add item to data & inventory
function DataManager.AddItem(player: Player, itemID, quantity: number, detailedConfig, itemConfig, GUID: string?)
	local invObj: InventoryObject = DataManager.PlayerInventories[player.UserId]
	local playerInventory: PlayerInventory = invObj.PlayerInventory

	if not playerInventory then return end
	
	local isTool = itemConfig.CATEGORY_TYPE == "Tool"
	local isArmor = itemConfig.CATEGORY_TYPE == "Armor"

	if isTool then
		playerInventory.Tools[GUID] = {
			BaseID = itemID,
			InstanceName = detailedConfig.InstanceName or "",
			DisplayName = detailedConfig.DisplayName or "",
			Damage = detailedConfig.Damage or 0,
			Reach = detailedConfig.Reach or 0,
			Cooldown = detailedConfig.Cooldown or 0,
			EquippedSlot = detailedConfig.EquippedSlot or 0,
			ToolType = detailedConfig.ToolType or "",
			PickaxeTier = detailedConfig.PickaxeTier or 0,
		}
		DataManager.SyncInventory(player)
		return
	end

	if isArmor then
		playerInventory.Armor[GUID] = {
			InstanceName = detailedConfig.InstanceName or "",
			DisplayName = detailedConfig.DisplayName or "",
			BaseID = itemID,
			Protection = detailedConfig.Protection,
			EquippedSlot = detailedConfig.EquippedSlot
		}
		DataManager.SyncInventory(player)
		return
	end

	local finalQty = quantity or 0
	if not playerInventory.Items[itemID] then
		playerInventory.Items[itemID] = 0
	end

	playerInventory.Items[itemID] += finalQty
	DataManager.SyncInventory(player)
end

--Remove item from data & inventory
function DataManager.RemoveItem(player: Player, itemID, quantity: number?, toolConfig: ToolConfig?, armorConfig: ArmorConfig?, GUID: string?)
	local invObj: InventoryObject = DataManager.PlayerInventories[player.UserId]
	local playerInventory: PlayerInventory = invObj.PlayerInventory

	if not playerInventory then return end

	local currentItemsQty = playerInventory.Items[itemID] or 0

	if toolConfig then
		if playerInventory.Tools and playerInventory.Tools[GUID] then
			playerInventory.Tools[GUID] = nil
			DataManager.SyncInventory(player)
		end
		return
	end

	if armorConfig then
		if playerInventory.Armor and playerInventory.PlayerInventory.Armor[GUID] then
			playerInventory.Armor[GUID] = nil
			DataManager.SyncInventory(player)
		end
		return
	end

	local finalQty = quantity or 0
	if not playerInventory.Items[itemID] then
		playerInventory.PlayerInventory.Items[itemID] = 0
	end

	playerInventory.Items[itemID] -= finalQty
	if playerInventory.Items[itemID] <= 0 then
		playerInventory.Items[itemID] = nil
	end

	DataManager.SyncInventory(player)
end

--Update item
function DataManager.UpdateItem(player: Player, GUID: string, updates: {EquippedSlot: number?, Damage: number?})
	local profile = DataManager.Profiles[player]
	local invObj: InventoryObject = DataManager.PlayerInventories[player.UserId]
	local playerInventory: PlayerInventory = invObj.PlayerInventory
	if not playerInventory or not profile then return end
	local playerTools = playerInventory.Tools
	if not playerTools then return end

	local tool = playerTools[GUID]
	if not tool then
		warn(`Attempted to Updated missing tool GUID: {GUID} for player: {player.UserId}`)
		return
	end

	if updates.EquippedSlot ~= nil then
		tool.EquippedSlot = updates.EquippedSlot
		profile.Data.PlayerTools[GUID].EquippedSlot = updates.EquippedSlot
	end

	if updates.Damage ~= nil then
		tool.Damage = updates.Damage
		profile.Data.PlayerTools[GUID].Damage = updates.Damage
	end

	DataManager.SyncInventory(player)
end

return DataManager
