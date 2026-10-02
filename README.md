# Zone2D

[Documentation](https://breezy1214.github.io/Zone2D/)

Zone2D is a lightweight zone module for Roblox. It turns a `BasePart` into a zone by checking whether a point falls inside the part's X/Z footprint, measured in the part's own space so rotated parts work. By default the zone extends infinitely up and down. You can cap it with `MaxHeight` or restrict it to the space above the part with `AboveOnly`.

Tracked models are checked once per `Heartbeat` against their `PrimaryPart` position, and `Entered`/`Exited` fire on transitions. It does not use touch events or spatial queries.

## Installation

Add the package to your [Wally](https://wally.run) manifest:

```toml
[dependencies]
Zone2D = "breezy1214/zone2d@0.1.0"
```

## Quick Start

```lua
local Zone2D = require(Path.To.Zone2D)

local zone = Zone2D.new(workspace.Zones.Spawn, { MaxHeight = 50 })
zone:TrackPlayers()

zone.Entered:Connect(function(character: Model)
	print(character.Name, "entered")
end)

zone.Exited:Connect(function(character: Model)
	print(character.Name, "left")
end)

-- Later
zone:Destroy()
```

Zones are Janitor/Trove friendly because they expose `Destroy`:

```lua
local zone = janitor:Add(Zone2D.new(part))
```

## Options

```lua
export type ZoneOptions = {
	MaxHeight: number?,
	AboveOnly: boolean?,
}
```

| Option | Default | Effect |
| --- | --- | --- |
| `MaxHeight` | `nil` (unbounded) | Maximum vertical distance from the part's center, in the part's local Y. |
| `AboveOnly` | `false` | Points below the part's center are outside. Combined with `MaxHeight`, the zone spans `0..MaxHeight` above the center. |

## API

### `Zone2D.new(part: BasePart, options: ZoneOptions?): Zone2D`

Creates a zone from `part` and starts the per-`Heartbeat` update. The part's size is read once at construction. While the part is not a descendant of `workspace`, updates are paused.

### `Zone2D.IsPointInside(part: BasePart, position: Vector3, options: ZoneOptions?): boolean`

A static check that doesn't create a zone. Use it for one-off tests.

### `zone:IsInside(position: Vector3): boolean`

Returns whether `position` is inside this zone, using its options.

### `zone:TrackModel(model: Model)`

Starts tracking `model`. Detection begins once the model has a `PrimaryPart`. A model that leaves `workspace` is untracked automatically, and `Exited` fires if it was inside.

### `zone:UntrackModel(model: Model)`

Stops tracking `model`. Fires `Exited` if it was inside.

### `zone:TrackPlayers()`

Tracks every current and future player character, and untracks characters on `CharacterRemoving` or `PlayerRemoving`.

### `zone:GetModelsInside(): { Model }`

Returns the tracked models that are currently inside.

### `zone.Entered: Signal<Model>` / `zone.Exited: Signal<Model>`

These fire when a tracked model's `PrimaryPart` crosses into or out of the zone.

### `zone:Destroy()`

Disconnects everything, destroys the signals, and clears tracked state. It is safe to call more than once.

## License

MIT
