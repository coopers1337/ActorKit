# Benchmark

This benchmark runs the same heavy job three ways:

- **Serial:** one thread, one job after another
- **Pool, each:** one message per job sent to an ActorKit pool (`Send`)
- **Pool, batch:** one message per worker, each carrying a chunk of jobs (`SendBatch`)

It shows how much ActorKit helps on your machine, where it stops helping, and how much batching saves.

## Setup

Create these four scripts:

| Script | Type | Location |
| --- | --- | --- |
| `ActorKit` | ModuleScript | `ReplicatedStorage` |
| `BenchWork` | ModuleScript | `ReplicatedStorage` |
| `BenchWorker` | Script | `ServerStorage` |
| `Benchmark` | Script | `ServerScriptService` |

### `BenchWork`

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

`--!native` turns on native code generation. Serial and pool runs both use it, so the comparison stays fair.

### `BenchWorker`

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

### `Benchmark`

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

## How it works

- Every job runs the same math loop, so serial and pool do identical work.
- Each setup runs once as a warm-up, then 7 timed rounds. The median is reported.
- Workers count finished jobs in a `SharedTable`. The last one fires a `BindableEvent` through `ActorKit.serial`, and the timer stops there.
- The pool is created and made ready before timing starts, so setup cost isn't counted.
- "Each" sends 256 messages. "Batch" sends one message per worker, so a pool of 16 gets 16 messages instead of 256.

## Results

Machine: Intel Core i7-10750H (6 cores, 12 threads), 16 GB RAM  
Where it ran: Studio / live server

### Run 1: ActorKit v1

One message per job, no native codegen.

| Setup | Time (ms) | Speedup |
| --- | --- | --- |
| Serial | 251.7 | x1.00 |
| Pool 1 | 276.3 | x0.91 |
| Pool 4 | 66.3 | x3.80 |
| Pool 16 | 47.7 | x5.28 |
| Pool 64 | 45.2 | x5.56 |

### Run 2: ActorKit v2

Fill this in from the output window. The serial time will differ from Run 1 because of `--!native`, so compare milliseconds as well as speedups.

| Setup | Each (ms) | Each speedup | Batch (ms) | Batch speedup |
| --- | --- | --- | --- | --- |
| Serial | 209.8 | x1.00 | 209.8 | x1.00 |
| Pool 1 | 212.9 | x0.99 | 208.3 | x1.01 |
| Pool 4 | 56.3 | x3.72 | 54.8 | x3.83 |
| Pool 16 | 40.4 | x5.19 | 46.6 | x4.51 |
| Pool 64 | 37.5 | x5.59 | 37.1 | x5.65 |

What Run 2 showed:

- **Native codegen helped.** Serial dropped from 251.7 ms to 209.8 ms, and Pool 64 dropped from 45.2 ms to about 37 ms.
- **Batching made little difference at this job size.** Each job takes about 0.8 ms, so message cost is small next to the work. Pool 1 "each" is only 3 ms slower than serial across 256 messages.
- **Pool 16 batch was slower than Pool 16 each** (46.6 ms vs 40.4 ms). This is a single run, so treat it as unexplained until repeated.
- **The ceiling is the same as before.** Speedup tops out near x5.6 on 6 cores.

## How to read it

- **Pool 1 each is about the same as serial, or slower.** One worker means no parallelism, and you pay for messaging. That is expected.
- **Batch only helps when messages are a real part of the cost.** When each job is heavy, the work dominates and "each" and "batch" land within a few percent. Lower `ITERATIONS` to see the difference.
- **Speedup grows, then flattens.** It stops near your CPU's core count. On a 6-core CPU, expect it to level off around x5 to x6 however many Actors you add.
- **Compare Run 1 and Run 2 in milliseconds.** If serial time drops in Run 2, that is native codegen at work, and it speeds up every row.
- **Studio numbers run lower than a live server.** Studio has extra overhead, so treat it as a rough guide.

## Things to try

- **Lower `ITERATIONS`** to 200 or so. At some point "each" becomes slower than serial because each message costs more than the work it carries. "Batch" should hold up longer, which shows what batching buys you on small jobs.
- **Raise `JOBS`** to see how each approach handles a bigger queue.
- **Remove `--!native`** from `BenchWork` and rerun to measure native codegen on its own.
- **Swap `BenchWork.burn`** for your own real workload, like a raycast batch or pathing math, to get numbers that mean something for your game.
