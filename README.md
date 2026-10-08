# ActorKit

**Parallel workers for Roblox, without the setup.**

ActorKit is a small ModuleScript that creates a pool of Actors, hands them jobs, and cleans up after itself. You write the work. It handles the plumbing.

```lua
local pool = ActorKit.Pool.new(ServerStorage.NpcWorker, 16)
pool:WaitReady()
pool:SendBatch("Think", npcs, targetPosition)
```

---

## Contents

- [What it is](#what-it-is)
- [Why use it](#why-use-it)
- [Install](#install)
- [Quick start](#quick-start)
- [API](#api)
- [Batching](#batching)
- [What you can build](#what-you-can-build)
- [How fast is it](#how-fast-is-it)
- [Good to know](#good-to-know)
- [When to use it](#when-to-use-it)
- [Run the benchmark](#run-the-benchmark)

---

## What it is

Roblox lets you run code on several threads using Actors. It works well, but the setup is the same every time, and sending one message per job gets expensive fast.

ActorKit gives you:

- A **pool** of Actors made from one worker script
- Three ways to send jobs: one at a time, by key, or in batches
- A way to **wait until workers are ready**
- A one-call switch between **parallel and serial** code
- Cleanup when you're done

## Why use it

Without ActorKit, every parallel feature starts with the same chores:

1. Create N Actors and clone your worker into each one
2. Keep track of them and rotate through them
3. Wait for each worker to bind its handlers
4. Pair every `task.synchronize()` with a `task.desynchronize()`
5. Destroy everything at the end

ActorKit turns that into a few calls, and a few of them do more than save typing:

| Feature | What you get |
| --- | --- |
| `SendKeyed` | The same key always goes to the same worker, so one NPC is never handled by two threads at once |
| `SendBatch` | One message per worker instead of one per job |
| `serial` | Switches back to the parallel phase even if your code errors, so a failed write can't leave a thread stuck |

---

## Install

1. Put `ActorKit` (a ModuleScript) in `ReplicatedStorage`.
2. Make a worker `Script` and keep it in `ServerStorage`. This is the template that gets cloned.

> Keep the template in `ServerStorage` so only the clones run.

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

The pattern is always the same: **do the heavy math in parallel, then wrap anything that changes instances in `ActorKit.serial`.**

---

## API

| Call | What it does |
| --- | --- |
| [`Pool.new(template, size, parent?)`](#poolnewtemplate-size-parent) | Make a pool of Actors |
| [`pool:Send(topic, ...)`](#poolsendtopic-) | Send a job to the next worker in line |
| [`pool:SendKeyed(key, topic, ...)`](#poolsendkeyedkey-topic-) | Same key, same worker, every time |
| [`pool:SendBatch(topic, jobs, ...)`](#poolsendbatchtopic-jobs-) | Split a list of jobs across all workers |
| [`pool:Broadcast(topic, ...)`](#poolbroadcasttopic-) | Send to every worker |
| [`pool:WaitReady()`](#poolwaitready) | Wait until every worker is listening |
| [`pool:Destroy()`](#pooldestroy) | Destroy all the Actors |
| [`ActorKit.serve(actor, handlers, parallel?)`](#actorkitserveactor-handlers-parallel) | Bind handlers inside a worker |
| [`ActorKit.serial(callback, ...)`](#actorkitserialcallback-) | Run code in the serial phase |

### `Pool.new(template, size, parent?)`

Clones `template` into `size` Actors and returns a pool. `parent` defaults to `ServerScriptService` on the server and `PlayerScripts` on the client.

### `pool:Send(topic, ...)`

Sends a job to the next Actor in line. A good default for work that doesn't care who handles it.

### `pool:SendKeyed(key, topic, ...)`

Sends the job to the Actor that matches `key`. Use it when one entity (an NPC, a player) should always be handled by the same worker.

### `pool:SendBatch(topic, jobs, ...)`

Splits the `jobs` list into one chunk per Actor and sends each chunk as a single message. Extra arguments are passed after the chunk. The worker handler receives `(chunk, ...)`.

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

---

## Batching

Calling `Send` in a loop sends one message per job. `SendBatch` sends one message per worker, each carrying a chunk of the list.

**Server script**

```lua
local CollectionService = game:GetService("CollectionService")

local npcs = CollectionService:GetTagged("Npc")
pool:SendBatch("Think", npcs, targetPosition)
```

**Worker script**

```lua
ActorKit.serve(script:GetActor() :: Actor, {
	Think = function(npcs: { Model }, targetPosition: Vector3)
		local moves = table.create(#npcs)
		for index, npc in npcs do
			moves[index] = (targetPosition - npc:GetPivot().Position).Unit
		end
		ActorKit.serial(function()
			for index, npc in npcs do
				npc:PivotTo(npc:GetPivot() + moves[index])
			end
		end)
	end,
})
```

The worker loops over its chunk and calls `serial` **once**, not once per NPC.

---

## What you can build

| Use case | How ActorKit helps |
| --- | --- |
| NPC AI | Spread pathing, target picking, and steering across workers |
| Hit validation | Run raycasts and checks in parallel, then apply damage in `serial` |
| Procedural generation | Build terrain chunks or noise in parallel, then write results in `serial` |
| Spatial queries | Run many distance or visibility checks without blocking the main thread |
| Heavy math | Offload anything that doesn't touch instances until the end |

---

## How fast is it

A pool can't go past your CPU's core count, however many Actors you make. That is the ceiling.

Results below are from an **Intel Core i7-10750H (6 cores, 12 threads), 16 GB RAM**. Each number is the median of 7 rounds, running 256 jobs.

### ActorKit v1

One message per job, no native codegen.

| Setup | Time (ms) | Speedup |
| --- | --- | --- |
| Serial | 251.7 | x1.00 |
| Pool 1 | 276.3 | x0.91 |
| Pool 4 | 66.3 | x3.80 |
| Pool 16 | 47.7 | x5.28 |
| Pool 64 | 45.2 | x5.56 |

### ActorKit v2

Adds `SendBatch` and `--!native` on the workload.

| Setup | Each (ms) | Each speedup | Batch (ms) | Batch speedup |
| --- | --- | --- | --- | --- |
| Serial | 209.8 | x1.00 | 209.8 | x1.00 |
| Pool 1 | 212.9 | x0.99 | 208.3 | x1.01 |
| Pool 4 | 56.3 | x3.72 | 54.8 | x3.83 |
| Pool 16 | 40.4 | x5.19 | 46.6 | x4.51 |
| Pool 64 | 37.5 | x5.59 | 37.1 | x5.65 |

### What the numbers show

- **Native codegen helped.** Serial dropped from 251.7 ms to 209.8 ms, and Pool 64 dropped from 45.2 ms to about 37 ms.
- **Speedup tops out near x5.6.** That is your 6 cores. More Actors don't help past that.
- **Pool 1 is no faster than serial.** One worker means no parallelism, and messages cost a little.
- **Batching changed little at this job size.** Each job takes about 0.8 ms, so message cost is small next to the work. Batching matters more when jobs are tiny.
- **Pool 16 batch was slower than Pool 16 each.** It's one run, so treat it as unexplained until repeated.

### Getting more speed

From biggest to smallest:

1. **Do less work.** A cheaper algorithm beats more threads.
2. **Batch your sends.** Use `SendBatch` instead of calling `Send` in a loop, especially for small jobs.
3. **Turn on native codegen** with `--!native` on hot scripts. It mostly helps tight numeric loops.
4. **Call `serial` once per batch**, not once per job.
5. **Send IDs or a `SharedTable`**, not big tables. Message arguments are copied.

---

## Good to know

- Parallel code can't change instances. That is what `serial` is for.
- Message arguments are copied between Actors. Functions can't be sent.
- Each Actor has its own Luau VM, so module state is not shared between workers.
- `require` doesn't work in a desynchronized phase. Require your modules at the top of the script.
- Tiny jobs aren't worth it. Messaging has a cost, so save this for work that's actually heavy.
- Studio adds overhead, so a live server may give different numbers.

## When to use it

**Use it** when you have many workers doing real work, like a crowd of NPCs or a lot of validation per second.

**Skip it** when you have one or two Actors, or the work is light. Plain Actors are simpler there.

---

## Run the benchmark

Measure serial, per-job sends, and batched sends on your own machine.

<details>
<summary><b>Show setup and scripts</b></summary>

<br>

Create these four scripts:

| Script | Type | Location |
| --- | --- | --- |
| `ActorKit` | ModuleScript | `ReplicatedStorage` |
| `BenchWork` | ModuleScript | `ReplicatedStorage` |
| `BenchWorker` | Script | `ServerStorage` |
| `Benchmark` | Script | `ServerScriptService` |

**`BenchWork`**

```lua
--!strict
--!native

local BenchWork = {}

function BenchWork.burn(iterations: number): number
	local total = 0
	for index = 1, iterations do
		total += math.noise(index * 0.01, index * 0.02, index * 0.03)
	end
	return total
end

return BenchWork
```

**`BenchWorker`**

```lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActorKit = require(ReplicatedStorage.ActorKit)
local BenchWork = require(ReplicatedStorage.BenchWork)

local function completeJobs(progress: SharedTable, finished: BindableEvent, count: number, total: number)
	if SharedTable.increment(progress, "done", count) + count == total then
		ActorKit.serial(function()
			finished:Fire()
		end)
	end
end

ActorKit.serve(script:GetActor() :: Actor, {
	Run = function(progress: SharedTable, finished: BindableEvent, iterations: number, total: number)
		BenchWork.burn(iterations)
		completeJobs(progress, finished, 1, total)
	end,
	RunBatch = function(chunk: { number }, progress: SharedTable, finished: BindableEvent, total: number)
		for _, iterations in chunk do
			BenchWork.burn(iterations)
		end
		completeJobs(progress, finished, #chunk, total)
	end,
})
```

**`Benchmark`**

```lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ActorKit = require(ReplicatedStorage.ActorKit)
local BenchWork = require(ReplicatedStorage.BenchWork)

local JOBS = 256
local ITERATIONS = 20000
local ROUNDS = 7
local POOL_SIZES = { 1, 4, 16, 64 }

local jobs = table.create(JOBS, ITERATIONS)

local function median(samples: { number }): number
	table.sort(samples)
	return samples[(#samples + 1) // 2]
end

local function runSerial(): number
	local start = os.clock()
	for _ = 1, JOBS do
		BenchWork.burn(ITERATIONS)
	end
	return os.clock() - start
end

local function runPool(dispatch: (progress: SharedTable, finished: BindableEvent) -> ()): number
	local progress = SharedTable.new({ done = 0 })
	local finished = Instance.new("BindableEvent")
	local start = os.clock()
	dispatch(progress, finished)
	finished.Event:Wait()
	local elapsed = os.clock() - start
	finished:Destroy()
	return elapsed
end

local function measure(run: () -> number): number
	run()
	local samples = table.create(ROUNDS)
	for index = 1, ROUNDS do
		task.wait()
		samples[index] = run()
	end
	return median(samples)
end

local function sendEach(pool: ActorKit.Pool): (SharedTable, BindableEvent) -> ()
	return function(progress, finished)
		for _ = 1, JOBS do
			pool:Send("Run", progress, finished, ITERATIONS, JOBS)
		end
	end
end

local function sendBatched(pool: ActorKit.Pool): (SharedTable, BindableEvent) -> ()
	return function(progress, finished)
		pool:SendBatch("RunBatch", jobs, progress, finished, JOBS)
	end
end

local serialTime = measure(runSerial)
print(string.format("serial      %8.1f ms", serialTime * 1000))

for _, size in POOL_SIZES do
	local pool = ActorKit.Pool.new(ServerStorage.BenchWorker, size)
	pool:WaitReady()
	local eachTime = measure(function()
		return runPool(sendEach(pool))
	end)
	local batchTime = measure(function()
		return runPool(sendBatched(pool))
	end)
	pool:Destroy()
	print(string.format(
		"pool %-5d  each %7.1f ms x%.2f   batch %7.1f ms x%.2f",
		size,
		eachTime * 1000,
		serialTime / eachTime,
		batchTime * 1000,
		serialTime / batchTime
	))
end
```

**How it works**

- Every job runs the same math loop, so serial and pool do identical work.
- Each setup runs once as a warm-up, then 7 timed rounds. The median is reported.
- Workers count finished jobs in a `SharedTable`. The last one fires a `BindableEvent` through `ActorKit.serial`, and the timer stops there.
- The pool is created and made ready before timing starts, so setup cost isn't counted.
- "Each" sends 256 messages. "Batch" sends one message per worker.

**Things to try**

- Lower `ITERATIONS` to 200 or so. "Each" should fall behind serial while "batch" holds up longer. That shows what batching buys you on small jobs.
- Raise `JOBS` to test a bigger queue.
- Remove `--!native` from `BenchWork` to measure native codegen on its own.
- Swap `BenchWork.burn` for your own real workload, like a raycast batch or pathing math.

</details>

---

## License

Use it however you like.
