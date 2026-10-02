--!strict
--[=[
	@class Zone2D

	A zone defined by a part's horizontal footprint. Tracked models fire `Entered` and
	`Exited` as their `PrimaryPart` moves in and out of the footprint, with an optional
	height cap and an above-only mode.

	```lua
	local zone = Zone2D.new(workspace.ShopFloor, { MaxHeight = 20 })
	zone:TrackPlayers()

	zone.Entered:Connect(function(character)
		print(character.Name, "entered")
	end)
	```
]=]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Janitor = require(script.Parent.Janitor)
local Signal = require(script.Parent.Signal)

local Zone2D = {}
Zone2D.__index = Zone2D

--[=[
	@interface ZoneOptions
	@within Zone2D
	.MaxHeight number? -- Maximum distance from the part's centre along its up axis.
	.AboveOnly boolean? -- Only count points on or above the part's centre plane.
]=]
export type ZoneOptions = {
	MaxHeight: number?,
	AboveOnly: boolean?,
}

export type Zone2D = typeof(setmetatable(
	{} :: {
		Entered: Signal.Signal<Model>,
		Exited: Signal.Signal<Model>,
		_part: BasePart,
		_halfSize: Vector3,
		_maxHeight: number?,
		_aboveOnly: boolean,
		_trackedModels: { [Model]: true },
		_insideSet: { [Model]: true },
		_janitor: typeof(Janitor.new()),
		_destroyed: boolean,
	},
	Zone2D
))

local function resolveOptions(options: ZoneOptions?): (number?, boolean)
	if not options then
		return nil, false
	end
	return options.MaxHeight, options.AboveOnly == true
end

local function isWithinBounds(localPos: Vector3, halfSize: Vector3, maxHeight: number?, aboveOnly: boolean): boolean
	if math.abs(localPos.X) > halfSize.X or math.abs(localPos.Z) > halfSize.Z then
		return false
	end

	if aboveOnly and localPos.Y < 0 then
		return false
	end

	local height = if aboveOnly then localPos.Y else math.abs(localPos.Y)
	return not maxHeight or height <= maxHeight
end

--[=[
	@prop Entered Signal<Model>
	@within Zone2D
	Fires when a tracked model's `PrimaryPart` enters the zone.
]=]

--[=[
	@prop Exited Signal<Model>
	@within Zone2D
	Fires when a tracked model leaves the zone, is untracked while inside, or leaves the workspace.
]=]

--[=[
	Checks whether a world position is inside a part's footprint without creating a zone.
	@within Zone2D
	@param part BasePart
	@param position Vector3
	@param options ZoneOptions?
	@return boolean
]=]
function Zone2D.IsPointInside(part: BasePart, position: Vector3, options: ZoneOptions?): boolean
	local localPos = part.CFrame:PointToObjectSpace(position)
	local maxHeight, aboveOnly = resolveOptions(options)
	return isWithinBounds(localPos, part.Size * 0.5, maxHeight, aboveOnly)
end

--[=[
	Creates a zone from a part's footprint. The zone checks tracked models every Heartbeat.
	@within Zone2D
	@param part BasePart
	@param options ZoneOptions?
	@return Zone2D
]=]
function Zone2D.new(part: BasePart, options: ZoneOptions?): Zone2D
	local janitor = Janitor.new()
	local maxHeight, aboveOnly = resolveOptions(options)

	local self = setmetatable({
		Entered = janitor:Add(Signal.new()) :: Signal.Signal<Model>,
		Exited = janitor:Add(Signal.new()) :: Signal.Signal<Model>,
		_part = part,
		_halfSize = part.Size * 0.5,
		_maxHeight = maxHeight,
		_aboveOnly = aboveOnly,
		_trackedModels = {} :: { [Model]: true },
		_insideSet = {} :: { [Model]: true },
		_janitor = janitor,
		_destroyed = false,
	}, Zone2D)

	janitor:Add(RunService.Heartbeat:Connect(function()
		self:_update()
	end))

	return self
end

function Zone2D._update(self: Zone2D): ()
	if self._destroyed then
		return
	end

	local part = self._part
	if not part:IsDescendantOf(workspace) then
		return
	end

	local halfSize = self._halfSize
	local maxHeight = self._maxHeight
	local aboveOnly = self._aboveOnly
	local partCFrame = part.CFrame

	for model in self._trackedModels do
		if not model:IsDescendantOf(workspace) then
			self._trackedModels[model] = nil
			if self._insideSet[model] then
				self._insideSet[model] = nil
				self.Exited:Fire(model)
			end
			continue
		end

		local primaryPart = model.PrimaryPart
		if not primaryPart then
			continue
		end

		local localPos = partCFrame:PointToObjectSpace(primaryPart.Position)
		local inside = isWithinBounds(localPos, halfSize, maxHeight, aboveOnly)

		if inside and not self._insideSet[model] then
			self._insideSet[model] = true
			self.Entered:Fire(model)
		elseif not inside and self._insideSet[model] then
			self._insideSet[model] = nil
			self.Exited:Fire(model)
		end
	end
end

--[=[
	Checks whether a world position is inside this zone.
	@within Zone2D
	@param position Vector3
	@return boolean
]=]
function Zone2D:IsInside(position: Vector3): boolean
	local localPos = self._part.CFrame:PointToObjectSpace(position)
	return isWithinBounds(localPos, self._halfSize, self._maxHeight, self._aboveOnly)
end

--[=[
	Tracks a model to detect when it enters/exits the zone.
	The model must be parented to workspace. Detection begins once it has a PrimaryPart.
	@within Zone2D
	@param model Model
]=]
function Zone2D:TrackModel(model: Model): ()
	if self._destroyed then
		return
	end
	self._trackedModels[model] = true
end

--[=[
	Stops tracking a model. If the model was inside the zone, it will fire the Exited event.
	@within Zone2D
	@param model Model
]=]
function Zone2D:UntrackModel(model: Model): ()
	if not self._trackedModels[model] then
		return
	end

	self._trackedModels[model] = nil

	if self._insideSet[model] then
		self._insideSet[model] = nil
		self.Exited:Fire(model)
	end
end

--[=[
	Convenience function to track all player characters. Automatically tracks new players and characters as they are added.
	@within Zone2D
]=]
function Zone2D:TrackPlayers(): ()
	if self._destroyed then
		return
	end

	local janitor = self._janitor

	local function onCharacterAdded(_, character: Model)
		self:TrackModel(character)
	end

	local function onCharacterRemoving(_player: Player, character: Model)
		self:UntrackModel(character)
	end

	local function onPlayerAdded(player: Player)
		janitor:Add(player.CharacterAdded:Connect(function(character: Model)
			onCharacterAdded(player, character)
		end))

		janitor:Add(player.CharacterRemoving:Connect(function(character: Model)
			onCharacterRemoving(player, character)
		end))

		if player.Character then
			onCharacterAdded(player, player.Character)
		end
	end

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	janitor:Add(Players.PlayerAdded:Connect(onPlayerAdded))

	janitor:Add(Players.PlayerRemoving:Connect(function(player: Player)
		if player.Character then
			onCharacterRemoving(player, player.Character)
		end
	end))
end

--[=[
	Returns a list of all models currently inside the zone.
	@within Zone2D
	@return { Model }
]=]
function Zone2D:GetModelsInside(): { Model }
	local models: { Model } = {}
	for model in self._insideSet do
		table.insert(models, model)
	end
	return models
end

--[=[
	Destroys the Zone2D instance and disconnects all connections. After calling this, the instance should not be used.
	@within Zone2D
]=]
function Zone2D:Destroy(): ()
	if self._destroyed then
		return
	end
	self._destroyed = true

	self._janitor:Destroy()
	table.clear(self._trackedModels)
	table.clear(self._insideSet)
end

return Zone2D
