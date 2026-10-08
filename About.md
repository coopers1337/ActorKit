# About ActorKit

## What it is

ActorKit is a small ModuleScript that makes parallel code in Roblox easier to set up and cheaper to run.

Roblox lets you run code on several threads using Actors. It works well, but the setup is the same every time, and sending one message per job gets expensive fast. ActorKit handles the setup and gives you batching to cut the message cost.

## What it does

- Creates a group of Actors (a pool) from one worker script
- Hands out jobs one at a time, by key, or in batches
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

ActorKit turns that into a few calls to remember: `Pool.new`, `Send`, `SendBatch`, `serve`, and `serial`.

Three parts do more than save typing:

- **`SendBatch`** splits a list of jobs into one chunk per worker and sends each chunk as a single message. One message per worker costs far less than one message per job.
- **`SendKeyed`** sends the same key to the same worker every time, so one NPC or entity is never handled by two threads at once.
- **`serial`** switches back to the parallel phase even if your code errors, so a failed write can't leave a thread stuck in the wrong phase.

## How fast is it

Speed has a ceiling: your CPU's core count. A pool can't go much past that, however many Actors you make.

One measured run on an Intel Core i7-10750H (6 cores), sending one message per job with ActorKit v1:

| Setup | Speedup over serial |
| --- | --- |
| Pool 1 | x0.91 |
| Pool 4 | x3.80 |
| Pool 16 | x5.28 |
| Pool 64 | x5.56 |

Pool 1 is slower than serial because of messaging cost, and the curve flattens near the 6-core limit. Batching and native codegen target exactly those two limits. See `Benchmark.md` to measure them yourself.

Ways to get more speed, from biggest to smallest:

1. **Do less work.** A cheaper algorithm beats more threads.
2. **Batch your sends.** Use `SendBatch` instead of calling `Send` in a loop.
3. **Turn on native codegen** with `--!native` on hot scripts. It mostly helps tight numeric loops.
4. **Call `serial` once per batch**, not once per job.
5. **Send IDs or a `SharedTable`**, not big tables. Message arguments are copied.

## What you can do with it

| Use case | How it helps |
| --- | --- |
| NPC AI | Spread pathing, target picking, and steering across workers |
| Hit validation | Run raycasts and checks in parallel, then apply damage in `serial` |
| Procedural generation | Build terrain chunks or noise in parallel, then write results in `serial` |
| Spatial queries | Run many distance or visibility checks without blocking the main thread |
| Heavy math | Offload anything that doesn't touch instances until the end |

## What it does not do

- It doesn't beat your core count. Past that point, only cheaper work helps.
- It doesn't remove Roblox's limits. Parallel code still can't change instances, and that is what `serial` is for.
- It doesn't share state between workers. Each Actor has its own Luau VM, so module state is separate.
- It doesn't make small jobs worth parallelizing. Messages are copied between Actors, so tiny jobs can cost more than they save.

## When to use it

Use it when you have many workers doing real work, like a crowd of NPCs or a lot of validation per second.

Skip it when you have one or two Actors, or the work is light. Plain Actors are simpler there.

## Where to go next

- `README.md` has install steps, the full API, and examples.
- `Benchmark.md` has a script to measure serial, per-job sends, and batched sends on your own machine.
