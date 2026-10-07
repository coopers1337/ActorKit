# About ActorKit

## What it is

ActorKit is a small ModuleScript that makes parallel code in Roblox easier to set up.

Roblox lets you run code on several threads using Actors. It works well, but the setup is the same every time and easy to get slightly wrong. ActorKit does that setup for you.

## What it does

- Creates a group of Actors (a pool) from one worker script
- Hands out jobs to them, evenly or by key
- Waits until the workers are ready
- Lets you jump into serial code and back to parallel code in one call
- Cleans everything up when you're done

## The point

Without it, every parallel feature starts with the same chores:

1. Create N Actors and clone your worker into each one
2. Keep track of them and rotate through them
3. Wait for each worker to bind its handlers
4. Pair every `task.synchronize()` with a `task.desynchronize()`
5. Destroy everything at the end

ActorKit turns that into four things to remember: `Pool.new`, `Send`, `serve`, and `serial`.

Two parts do more than save typing:

- **`SendKeyed`** sends the same key to the same worker every time, so one NPC or entity is never handled by two threads at once.
- **`serial`** switches back to the parallel phase even if your code errors, so a failed write can't leave a thread stuck in the wrong phase.

## What you can do with it

| Use case | How it helps |
| --- | --- |
| NPC AI | Spread pathing, target picking, and steering across workers |
| Hit validation | Run raycasts and checks in parallel, then apply damage in `serial` |
| Procedural generation | Build terrain chunks or noise in parallel, then write results in `serial` |
| Spatial queries | Run many distance or visibility checks without blocking the main thread |
| Heavy math | Offload anything that doesn't touch instances until the end |

## What it does not do

- It doesn't make parallel code faster than hand-written Actors. It only removes the setup.
- It doesn't remove Roblox's limits. Parallel code still can't change instances, and that is what `serial` is for.
- It doesn't share state between workers. Each Actor has its own Luau VM, so module state is separate.
- It doesn't make small jobs worth parallelizing. Messages are copied between Actors, so tiny jobs can cost more than they save.

## When to use it

Use it when you have many workers doing real work, like a crowd of NPCs or a lot of validation per second.

Skip it when you have one or two Actors, or the work is light. Plain Actors are simpler there.

## Where to go next

See `README.md` for install steps, the full API, and examples.
