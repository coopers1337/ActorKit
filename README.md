# ActorKit

A small helper for running Roblox code on multiple threads without setting up Actors by hand.

You give it a worker script and a number. It makes that many Actors, hands out jobs, and gets out of your way.

## Install

1. Put `ActorKit` (a ModuleScript) in `ReplicatedStorage`.
2. Make a worker `Script` and keep it in `ServerStorage`. This is the template that gets cloned.

## Quick start

**Server script**

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ActorKit = require(ReplicatedStorage.ActorKit)

local pool = ActorKit.Pool.new(ServerStorage.NpcWorker, 16)
pool:WaitReady()

pool:Send("Think", npcModel, targetPosition)
```

**Worker script (`NpcWorker`)**

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActorKit = require(ReplicatedStorage.ActorKit)

ActorKit.serve(script:GetActor() :: Actor, {
	Think = function(npcModel: Model, targetPosition: Vector3)
		local offset = targetPosition - npcModel:GetPivot().Position
		ActorKit.serial(function()
			npcModel:PivotTo(npcModel:GetPivot() + offset.Unit)
		end)
	end,
})
```

Do the heavy math in parallel. Wrap anything that changes instances in `ActorKit.serial`.

## API

### `ActorKit.Pool.new(template, size, parent?)`

Clones `template` into `size` Actors and returns a pool. `parent` defaults to `ServerScriptService` on the server and `PlayerScripts` on the client.

### `pool:Send(topic, ...)`

Sends a job to the next Actor in line. Good default for work that doesn't care who handles it.

### `pool:SendKeyed(key, topic, ...)`

Same key, same Actor, every time. Use it when one entity (an NPC, a player) should always be handled by the same worker.

### `pool:Broadcast(topic, ...)`

Sends the message to every Actor. Good for resets and config changes.

### `pool:WaitReady()`

Yields until every worker has called `serve`. Call it once after creating the pool, before sending anything.

### `pool:Destroy()`

Destroys all the Actors.

### `ActorKit.serve(actor, handlers, parallel?)`

Used inside a worker. `handlers` is a table of `topic = function`. Handlers run in parallel by default. Pass `false` as the third argument to run them in serial. Returns a function that disconnects everything.

### `ActorKit.serial(callback, ...)`

Switches to the serial phase, runs `callback`, then goes back to parallel. Returns whatever the callback returns. If the callback errors, the error is rethrown after switching back.

Call it from parallel code only.

## Good to know

- Parallel code can't change instances. That's what `serial` is for.
- Message arguments are copied between Actors. Send IDs or a `SharedTable` instead of big tables.
- Every Actor has its own Luau VM, so module state is not shared between workers.
- Functions can't be sent in messages.
- Tiny jobs aren't worth it. Messaging has a cost, so save this for work that's actually heavy.
- Use `require` before switching to parallel. `require` doesn't work in a desynchronized phase.

## Good fits

- NPC decisions and steering
- Hit validation with raycasts
- Procedural generation
- Lots of distance or visibility checks per frame

## License

Use it however you like.
