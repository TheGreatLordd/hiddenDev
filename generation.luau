--!strict

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

-- frequency controls noise scale (higher = smoother terrain)
const frequency = 45

-- maximum height of terrain in voxel units
const maxHeight = 80

-- world grid size in X/Z direction
const size = 100

-- voxel resolution in studs
const blockSize = 5

-- exponent curve that biases terrain toward lower values
const heightCurve = 2.2

-- how many blocks of terrain are rendered below surface
const renderDepth = 5

-- folder where generated voxel parts are stored
const terrainFolder: Folder = Workspace.Voxels
local treeModel: Model = ServerStorage.Tree

-- minimum spacing between trees to prevent clustering
const treeMinDistance = 3

local seed = math.random(-math.huge, math.huge)
local random = Random.new(seed)

-- biome thresholds 
const seaLevel = 0.15
const sandLevel = 0.25
const grassLevel = 0.55
const mountainTopLevel = 0.75

-- tree placement rules using noise
const treeThreshold = 0.45
const treeDensity = 0.06 -- 6% global spawn chance

local terrain = Workspace.Terrain :: Terrain

-- precomputed sea height in voxel units
-- avoids recalculating every frame
const seaHeight = math.floor(seaLevel * maxHeight)

-- center of grid used for player spawn positioning
const gridCenterX = math.floor(size / 2)
const gridCenterZ = math.floor(size / 2)

-- stores per-column terrain height data
type ColumnData = {
	normalizedHeight: number,
	blockHeight: number
}

-- full 2D heightmap cache for fast lookup during generation
type TerrainMap = {
	[number]: {
		[number]: ColumnData
	}
}

-- runtime data passed through voxel generation pipeline
type BlockData = {
	part: Part,
	voxelX: number,
	voxelY: number,
	voxelZ: number,
	normalizedHeight: number,
	blockHeight: number,
	heightLevel: number?
}

-- atmospheric effect added globally for visual depth/fog
local atmosphere = Instance.new("Atmosphere")
atmosphere.Density = 0.45
atmosphere.Offset = 0.2
atmosphere.Parent = game.Lighting

-- converts world position into procedural height using Perlin noise
-- maps noise from -1, 1 to 0, 1 then applies curve shaping
local function sampleHeight(worldX: number, worldZ: number): (number, number)
	local rawNoise = math.noise(worldX / frequency, worldZ / frequency, seed)

	-- normalize noise range
	local normalizedHeight = (rawNoise + 1) / 2

	-- curve shaping to create more lowlands than peaks
	normalizedHeight = math.pow(normalizedHeight, heightCurve)

	-- convert normalized height into voxel height
	local blockHeight = math.floor(normalizedHeight * maxHeight)

	return normalizedHeight, blockHeight
end

-- applies underground block variation based on depth
-- used to simulate dirt/stone layering
local function applyUndergroundMaterial(blockData: BlockData, depth: number)
	local part = blockData.part

	if depth == 0 then
		return
	elseif depth <= 2 then
		part.Color = Color3.fromRGB(32, 255, 58) -- upper dirt layer (debug/placeholder tone)
	else
		part.Color = Color3.fromRGB(255, 49, 252) -- deeper stone layer (debug/placeholder tone)
	end
end

-- adds slight randomness to grass coloring for natural variation
local function applyGrassVariation(blockData: BlockData)
	local part = blockData.part

	local variation = random:NextInteger(-20, 20)
	part.Color = Color3.fromRGB(46, 139 + variation, 87)

	-- marks biome state for potential future systems
	blockData.heightLevel = grassLevel
end

-- determines surface biome color based on height bands
-- each band represents a different terrain type
local function applyBiomeColor(normalizedHeight: number, blockData: BlockData, blockY: number): ()
	local part = blockData.part

	if normalizedHeight < seaLevel then
		-- ocean biome
		part.Color = Color3.fromRGB(0, 0, 255)
		blockData.heightLevel = seaLevel

	elseif normalizedHeight < sandLevel then
		-- beach biome
		part.Color = Color3.fromRGB(237, 201, 175)
		blockData.heightLevel = sandLevel

	elseif normalizedHeight < grassLevel then
		-- grass biome with variation
		applyGrassVariation(blockData)

	elseif normalizedHeight < mountainTopLevel then
		-- rocky terrain biome
		part.Color = Color3.fromRGB(128, 128, 128)
		blockData.heightLevel = mountainTopLevel

	else
		-- snow bime
		part.Color = Color3.fromRGB(255, 255, 255)
		blockData.heightLevel = mountainTopLevel
	end
end

-- precomputes full terrain heightmap for fast voxel lookup
local map: TerrainMap = {}

for worldX = 1, size do
	map[worldX] = {}

	for worldZ = 1, size do
		local normalizedHeight, blockHeight = sampleHeight(worldX, worldZ)

		map[worldX][worldZ] = {
			normalizedHeight = normalizedHeight,
			blockHeight = blockHeight
		}
	end
end

-- fills vertical space with water up to sea level
local function applyWater(blockData: BlockData)
	if blockData.blockHeight >= seaHeight then
		return
	end

	for y = blockData.blockHeight + 1, seaHeight do
		local waterCFrame = CFrame.new(
			blockData.voxelX * blockSize,
			y * blockSize,
			blockData.voxelZ * blockSize
		)

		local waterSize = Vector3.new(blockSize, blockSize, blockSize)

		terrain:FillBlock(waterCFrame, waterSize, Enum.Material.Water)
	end
end

-- handles procedural tree spawning using noise + probability filters
-- ensures biome correctness and spacing constraints
local function determineTreeSpawn(worldX: number, worldZ: number, block: Part, height: number, targetCFrame: CFrame): boolean

	local sampleX = (worldX + 0.1) / frequency
	local sampleZ = (worldZ + 0.1) / frequency

	local rawProbability = math.noise(sampleX, sampleZ, seed)
	local normalizedProbability = math.clamp(rawProbability + 0.5, 0, 1)

	-- validate spawn conditions
	if not (normalizedProbability > treeThreshold) then return false end
	if math.random() > treeDensity then return false end
	if height <= seaLevel then return false end
	if height <= sandLevel then return false end
	if height >= mountainTopLevel then return false end

	-- spawn tree model at calculated surface position
	local tree: Model = treeModel:Clone()

	local spawnCFrame = targetCFrame * CFrame.new(0, (block.Size.Y / 2) + 2.45, 0)

	tree:PivotTo(spawnCFrame)
	tree.Parent = block

	block.Name = "Tree Root"
	return true
end

-- checks surrounding positions to prevent tree clustering
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

-- main voxel generation pipeline
-- builds world column-by-column with surface optimization
local function generateVoxels()

	local spawnedParts: { Part } = {}
	local spawnedCFrames: { CFrame } = {}

	-- tracks tree placement for spacing rules
	local treeGrid: {[number]: { [number]: boolean }} = {}

	local function hasTree(x: number, z: number): boolean
		if x < 1 or x > size or z < 1 or z > size then
			return true
		end

		return treeGrid[x] and treeGrid[x][z] or false
	end

	-- iterate full terrain grid
	for worldX = 1, size do
		for worldZ = 1, size do

			local column: ColumnData = map[worldX][worldZ]

			-- generate voxel column from surface downward
			for blockY = column.blockHeight, 0, -1 do

				local isWithinRenderDepth = blockY >= column.blockHeight - renderDepth

				-- only generate near surface layers 
				if isWithinRenderDepth then

					local block: Part = Instance.new("Part")
					block.Anchored = true
					block.Size = Vector3.new(blockSize, blockSize, blockSize)

					local targetCFrame = CFrame.new(
						worldX * blockSize,
						blockY * blockSize,
						worldZ * blockSize
					)

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

					-- surface only logic
					if blockData.voxelY == blockData.blockHeight then

						local neighborTreesList = getNeighborTrees(blockData.voxelX, blockData.voxelZ, hasTree)
						local tooClose = table.find(neighborTreesList, true) ~= nil

						if not tooClose then
							if determineTreeSpawn(
								blockData.voxelX,
								blockData.voxelZ,
								blockData.part,
								blockData.normalizedHeight,
								targetCFrame
							) then
								if not treeGrid[blockData.voxelX] then
									treeGrid[blockData.voxelX] = {}
								end

								treeGrid[blockData.voxelX][blockData.voxelZ] = true
							end
						end

						applyWater(blockData)
					end

					-- applies biome coloring for surface rendering
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
