--!strict
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

const frequency = 45
const maxHeight = 80
const size = 100
const blockSize = 5
const heightCurve = 2.2
const renderDepth = 5

const terrainFolder: Folder = Workspace.Voxels
const treeModel: Model = ServerStorage.Tree
const treeMinDistance = 3

const seed = math.random(-math.huge, math.huge)
local random = Random.new(seed)

const seaLevel = 0.15
const sandLevel = 0.25
const mountainTopLevel = 0.75 
const grassLevel = 0.55

const treeThreshold = 0.45
const treeDensity = 0.06 --6% chance

const terrain = Workspace.Terrain :: Terrain
const seaHeight = math.floor(seaLevel * maxHeight)

const gridCenterX = math.floor(size / 2)
const gridCenterZ = math.floor(size / 2)

type ColumnData = { normalizedHeight: number, blockHeight: number }
type TerrainMap = { [number]: { [number]: ColumnData } }

type BlockData = {
	part: Part,
	voxelX: number,
	voxelY: number,
	voxelZ: number,
	normalizedHeight: number,
	blockHeight: number,
	heightLevel: number?
}

local atmosphere = Instance.new("Atmosphere")
atmosphere.Density = 0.45
atmosphere.Offset = 0.2
atmosphere.Parent = game.Lighting

local function sampleHeight(worldX: number, worldZ: number): (number, number)
	local rawNoise = math.noise(worldX / frequency, worldZ / frequency, seed)
	local normalizedHeight = (rawNoise + 1) / 2
	
	normalizedHeight = math.pow(normalizedHeight, heightCurve)
	local blockHeight = math.floor(normalizedHeight * maxHeight)
	
	return normalizedHeight, blockHeight
end

local function applyUndergroundMaterial(blockData: BlockData, depth: number)
	local part = blockData.part
	
	if depth == 0 then
		return
	elseif depth <= 2 then
		part.Color = Color3.fromRGB(32, 255, 58) 
	else
		part.Color = Color3.fromRGB(255, 49, 252) 
	end
end



local function applyGrassVariation(blockData: BlockData)
	local part = blockData.part
	local variation = random:NextInteger(-20, 20)
	part.Color = Color3.fromRGB(46, 139 + variation, 87)
	
	blockData.heightLevel = grassLevel
end

local function applyBiomeColor(normalizedHeight: number, blockData: BlockData, blockY: number): ()
	local part = blockData.part
	
	if normalizedHeight < seaLevel then
		part.Color = Color3.fromRGB(0, 0, 255)
		blockData.heightLevel = seaLevel
		
	elseif normalizedHeight < sandLevel then
		part.Color = Color3.fromRGB(237, 201, 175)
		blockData.heightLevel = sandLevel
		
	elseif normalizedHeight < grassLevel then
		applyGrassVariation(blockData)
	elseif normalizedHeight < mountainTopLevel then
		part.Color = Color3.fromRGB(128, 128, 128)
		blockData.heightLevel = mountainTopLevel
		
	else
		part.Color = Color3.fromRGB(255, 255, 255)
		blockData.heightLevel = mountainTopLevel
	end
end
local map: TerrainMap = {}
for worldX = 1, size do
	map[worldX] = {}
	
	for worldZ = 1, size do
		local normalizedHeight, blockHeight = sampleHeight(worldX, worldZ)
		map[worldX][worldZ] = { normalizedHeight = normalizedHeight, blockHeight = blockHeight }
	end
end

local function applyWater(blockData: BlockData)
	if blockData.blockHeight >= seaHeight then
		return
	end
	
	for y = blockData.blockHeight + 1, seaHeight do
		local waterCFrame = CFrame.new(blockData.voxelX * blockSize, y * blockSize, blockData.voxelZ * blockSize)
		local waterSize = Vector3.new(blockSize, blockSize, blockSize)
		
		terrain:FillBlock(waterCFrame, waterSize, Enum.Material.Water)
	end
end

local function determineTreeSpawn(worldX: number, worldZ: number, block: Part, height: number, targetCFrame: CFrame): boolean
	
	local sampleX = (worldX + 0.1) / frequency
	local sampleZ = (worldZ + 0.1) / frequency
	
	local RawProbability = math.noise(sampleX, sampleZ, seed)
	local normalizedProbability = math.clamp(RawProbability + 0.5, 0, 1)
	
	if not (normalizedProbability > treeThreshold) then return false end 
	if math.random() > treeDensity then return false end 
	if block:FindFirstChild("Tree") then return false end 
	if height <= seaLevel then return false end 
	if height <= sandLevel then return false end 
	
	local tree: Model = treeModel:Clone()
	local spawnCFrame = targetCFrame * CFrame.new(0, (block.Size.Y / 2) + 2.45, 0)
	
	tree:PivotTo(spawnCFrame)
	tree.Parent = block
	block.Name = "Tree Root" 
	return true
end

local function getNeighborTrees(worldX: number, worldZ: number, hasTree: (number, number) -> (boolean)): { boolean }
	local neighboringTrees = {
		hasTree(worldX + treeMinDistance, worldZ),
		hasTree(worldX - treeMinDistance, worldZ),
		hasTree(worldX, worldZ + treeMinDistance),
		hasTree(worldX, worldZ - treeMinDistance),
		hasTree(worldX + treeMinDistance, worldZ + treeMinDistance),
		hasTree(worldX - treeMinDistance, worldZ - treeMinDistance),
		hasTree(worldX + treeMinDistance, worldZ - treeMinDistance),
		hasTree(worldX - treeMinDistance, worldZ + treeMinDistance),
	}
	
	return neighboringTrees
end

local function playerAdded(player: Player)
	local character = player.Character or player.CharacterAdded:Wait()
	local hrp = character:FindFirstChild("HumanoidRootPart") :: Part
	assert(hrp, `Hrp not found for player: {player.Name}`)
	
	local column = map[gridCenterX][gridCenterZ]
	local centerHeight = column.blockHeight
	
	local rayOrigin = Vector3.new(gridCenterX * blockSize, 1000, gridCenterZ * blockSize)
	local rayDirection = Vector3.new(0, -3000, 0)
	local result = workspace:Raycast(rayOrigin, rayDirection)
	local groundY = result and result.Position.Y or 0
	
	hrp.CFrame = CFrame.new(gridCenterX * blockSize, groundY + 10, gridCenterZ * blockSize)
end

local function generateVoxels()
	local spawnedParts: { Part } = {}
	local spawnedCFrames: { CFrame } = {}
	
	local treeGrid: {[number]: { [number]: boolean }} = {}
	
	local function hasTree(x: number, z: number): boolean
		if x < 1 or x > size or z < 1 or z > size then
			return true 
		end
		
		return if treeGrid[x] and treeGrid[x][z] then true else false
	end
	
	for worldX = 1, size do
		for worldZ = 1, size do
			local column: ColumnData = map[worldX][worldZ]
			
			for blockY = column.blockHeight, 0, -1 do
				
				local isWithinRenderDepth = blockY >= column.blockHeight - renderDepth
				if isWithinRenderDepth then
					
					local block: Part = Instance.new("Part")
					block.Anchored = true
					block.Size = Vector3.new(blockSize, blockSize, blockSize)
					
					local targetCFrame = CFrame.new(worldX * blockSize, blockY * blockSize, worldZ * blockSize)
					block.CFrame = targetCFrame
					
					local depth = column.blockHeight - blockY
					
					local blockData: BlockData = {
						part = block,
						voxelX = worldX,
						voxelY = blockY,
						voxelZ = worldZ,
						normalizedHeight = column.normalizedHeight,
						blockHeight = column.blockHeight,
					}
					
					if blockData.voxelY == blockData.blockHeight then
						local neighborTreesList = getNeighborTrees(blockData.voxelX, blockData.voxelZ, hasTree)
						local tooClose = table.find(neighborTreesList, true) ~= nil
						
						if not tooClose then
							if determineTreeSpawn(blockData.voxelX, blockData.voxelZ, blockData.part, blockData.normalizedHeight, targetCFrame) then
								if not treeGrid[blockData.voxelX] then 
									treeGrid[blockData.voxelX] = {} 
								end 
								
								treeGrid[blockData.voxelX][blockData.voxelZ] = true
							end
						end
						
						applyWater(blockData)
					end
					
					applyBiomeColor(blockData.normalizedHeight, blockData, blockY)
					
					
					table.insert(spawnedParts, blockData.part)
					table.insert(spawnedCFrames, targetCFrame)
				end
			end
		end
	end
	
	workspace:BulkMoveTo(spawnedParts :: {Instance}, spawnedCFrames, Enum.BulkMoveMode.FireAllEvents)
	
	for _, block: Part in spawnedParts do
		block.Parent = terrainFolder
	end
	
end


Players.PlayerAdded:Connect(playerAdded)
generateVoxels()
