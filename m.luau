--!strict
--discord: .tgl. | roblox: iamgreat400
const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const Constants = require("../../Enums/Constants")
const playerPackets = require("../../packets/playerPackets")
const Item = require("./")

local Weapon = {}
setmetatable(Weapon, { __index = Item })
Weapon.__index = Weapon

export type WeaponData = Item.ItemData & {
    damage: number,
    maxAmmo: number,
    accuracy: number,
}

--full weapon type
export type Weapon = WeaponData & Item.Item & {
    player: Player,

    _model: Instance?,
    _motor6D: Motor6D?,
    _equipped: boolean,
    _lastUsed: number,
    _isAiming: boolean,
    _hipFireAccuracy: number,
    _random: Random,
    _currentAmmo: number,
    _slotNumber: number?,

    Reload: (self: Weapon) -> (),
    Use: (self: Weapon, rayOrigin: Vector3, rayDirection: Vector3) -> (),
    Equip: (self: Weapon) -> (),
    Unequip: (self: Weapon) -> (),
    _SetAmmo: (self: Weapon, newAmmo: number) -> (),
    Aim: (self: Weapon, toggle: boolean) -> ()
}

--variables for all weapons 
const EQUIP_DELAY = 0.5
const HIPFIRE_ACCURACY_MULTIPLIER = 0.5
const AIMING_SPEED_MULTIPLIER = 0.6
const AIMING_FOV = 55

const HEADSHOT_DAMAGE_MULT = 1.5

--Constructor for the weapon object that creates the weapon and assigns its stats based on weapondata
function Weapon.new(weaponData: WeaponData, player: Player): Weapon

    const self = setmetatable(table.clone(weaponData), Weapon) :: any 

    self.player = player

    self._model = nil
    self._motor6D = nil
    self._lastUsed = 0
    self._equipped = false 
    self._isAiming = false
    self._currentAmmo = self.maxAmmo
    self._slotNumber = nil

    self._random = Random.new()

    --shot accuracy and accuracy for if theyre hipfiring
    self.accuracy = math.clamp(self.accuracy, 0, 1)
    self._hipFireAccuracy = math.clamp((self.accuracy * HIPFIRE_ACCURACY_MULTIPLIER), 0, 1)

   
    return (self :: any) :: Weapon
end

--function that resolves the character from the person hit
const function getCharacterFromHit(instance: Instance): Model?
    if not instance or instance == workspace then
        return nil
    end

    if instance:IsA("Model") and Players:GetPlayerFromCharacter(instance) then
        return instance
    end

    return getCharacterFromHit((instance.Parent) :: Instance)
end

--function that determines if its valid to shoot the weapon, calculates if it should or not, and then raycasts to hit them and apply damage
function Weapon.Use(self: Weapon, rayOrigin: Vector3, rayDirection: Vector3)
    local plr = self.player

    if not Item.Use(self) then
        print("D - cooldown")
        return false
    end

    if not self._equipped then
        print("D- not equipped")
        return false
    end

    if self._currentAmmo <= 0 then
        print("D - no ammo")
        return false
    end
    --sanity checks to make sure theyre able to be shot, or youre able to shoot
    local character = plr.Character :: Model
    if not character then
        warn(`Character not found for {plr.Name}.`)
        return false
    end
    local hrp = character:FindFirstChild("HumanoidRootPart") :: Part
    local humanoid = character:FindFirstChild("Humanoid") :: Humanoid
    if not hrp or not humanoid then
        print("D- no hrp or hum")
        return false
    end
    
    local lookVector = hrp.CFrame.LookVector
    local shotDir = rayDirection.Unit
    local dot = lookVector:Dot(shotDir)
    if dot < -0.2 then
        print("dot fail")
        return false
    end

    --if theyre already dead, quit 
    if humanoid:GetState() == Enum.HumanoidStateType.Dead then
        self:Unequip()
        return false
    end
    --remove some ammo
    self:_SetAmmo(self._currentAmmo - 1)
    
    --another sanity check
    if rayDirection.Magnitude < 0.001 then
        print("D - mag ray check")
        return false
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character, (self._model :: Instance)}


    local direction = rayDirection.Unit * 10000
    local rayResult = workspace:Raycast(rayOrigin, direction, params)
    print(rayResult)
    if not rayResult or not rayResult.Instance then
        return false
    end


    local instanceHit = rayResult.Instance
    local characterHit = getCharacterFromHit(instanceHit) :: Model
    if not characterHit then
        return false
    end
    if not instanceHit:IsDescendantOf(characterHit) then
        return false
    end

    --get the player hit and their team, see if theyre friendly to check for friendly fire
    local playerHit = Players:GetPlayerFromCharacter(characterHit)
    local targetsTeam = playerHit and playerHit:GetAttribute("team")
    local friendlyTeam = plr:GetAttribute("team")
    if targetsTeam and friendlyTeam and targetsTeam == friendlyTeam then
        print("D- friendly fire")
        return false
    end
    if not playerHit then
        return false
    end

    local targetHumanoid = characterHit:FindFirstChild("Humanoid") :: Humanoid
    if not targetHumanoid then
        return false
    end

    --check if theyre able to be shot by rolling rng based on accuracy
    local randomNum = self._random:NextNumber()
    local accuracyThreshold = self._isAiming and self.accuracy or self._hipFireAccuracy
    if not (randomNum <= accuracyThreshold) then
        print("you are very inaccurate. random num:", randomNum)
        return false
    end

    
    local damage = self.damage
    if instanceHit.Name == "Head" and instanceHit:IsA("BasePart") then
        print("you got a headshot!")
        damage *= HEADSHOT_DAMAGE_MULT
    end
    
    --deal damage
    targetHumanoid:TakeDamage(damage)
    print(`{plr.Name} hit {playerHit.Name} for {damage}. They now have {targetHumanoid.Health} health. Last shot: {self._lastUsed}, currently on cooldown: {Item.Use(self)}`)
    return true
end
--function that sets the ammo within the weapondata of the object
function Weapon._SetAmmo(self: Weapon, newAmmo: number)
    self._currentAmmo = math.clamp(newAmmo, 0, self.maxAmmo)

    if self._slotNumber then
        playerPackets.packets.AmmoUpdate.sendTo({
            slotNumber = self._slotNumber,
            ammo = self._currentAmmo,
        }, self.player)
    end
end
--reloads the weapon
function Weapon.Reload(self: Weapon)
    self:_SetAmmo(self.maxAmmo)
end

--function that aims the weapon and changes the FOV to indicate theyre aiming
function Weapon.Aim(self: Weapon, toggle: boolean)
    local plr = self.player
    if not self._equipped then
        return
    end
    self._isAiming = toggle 

    local character: Model = plr.Character or plr.CharacterAdded:Wait()
    local humanoid = character:FindFirstChild("Humanoid") :: Humanoid
    assert(character and humanoid, `Character or humanoid not found for {plr.Name}.`) 

    humanoid.WalkSpeed = if toggle then humanoid.WalkSpeed * AIMING_SPEED_MULTIPLIER else Constants.Character.DEFAULT_WALKSPEED

    local fovChange = if toggle then AIMING_FOV else Constants.Camera.DEFAULT_FOV
    playerPackets.packets.ChangeFOV.sendTo({
        fov = fovChange,
        animate = true,
    }, plr)
end

--function that physically equips the model (using a motor6d) , applies equip cooldown, 
function Weapon.Equip(self: Weapon)
    local player = self.player
    print(`weapon manager: plr equippijng for: {player.Name}`)
    self._equipped = true 
    self._lastUsed = os.clock() + (EQUIP_DELAY - self.cooldown)


    playerPackets.packets.WeaponEquip.sendTo({
        lock = true
    }, player)

    local character = player.Character or player.CharacterAdded:Wait()
    assert(character, `The character for {player.Name} does not exist.`)
    --sanity checks
    local rightHand = character:FindFirstChild("RightHand") :: BasePart
    local rightGripAttachment = rightHand:FindFirstChild("RightGripAttachment") :: Attachment
    assert(rightHand, `The right hand for {player.Name} does not exist.`)
    assert(rightGripAttachment, `The right grip attachment was not found for {player.Name}.`)

    local weaponTemplate = ReplicatedStorage.Models.WeaponTemplates:FindFirstChild(self.ID)
    assert(weaponTemplate, `Weapon template not found in replicated storage for weapon: {self.ID}`)

    local weaponModel = weaponTemplate:Clone()
    weaponModel.Parent = character
    self._model = weaponModel
    --get the handle grip, and create the motor6d
    local handle = weaponModel:FindFirstChild("Handle")
    if not handle then
        error("Handle not found for weapon", 2)
    end
    
    local gripAttachment = handle:FindFirstChild("GripAttachment") :: Attachment
    assert(gripAttachment, `GripAttachment not found inside of item handle: {handle}, parent: {weaponModel.Name}.`)

    local motor6 = Instance.new("Motor6D")
    motor6.Name = "weaponWeld"
    motor6.Part0 = rightHand
    motor6.Part1 = handle :: BasePart
    motor6.C0 = rightGripAttachment.CFrame
    motor6.C1 = gripAttachment.CFrame
    motor6.Parent = rightHand
    --assign the motor6d to the object
    self._motor6D = motor6
end

--unequips the weapon state, and destroy the motor6d. Notify the client
function Weapon.Unequip(self: Weapon)
    self._equipped = false 

    if self._motor6D then 
        self._motor6D:Destroy()
        self._motor6D = nil
    end

    if self._model then 
        self._model:Destroy()
        self._model = nil
    end

    playerPackets.packets.WeaponEquip.sendTo({
        lock = false
    }, self.player)
end




return Weapon
