# Benchmark

This benchmark compares the same heavy job run two ways:

- **Serial:** one thread, one job after another
- **Pool:** the same jobs sent to an ActorKit pool of different sizes

It shows how much ActorKit helps on your machine and where it stops helping.

No numbers are included here on purpose. Speed depends on your CPU, so run it and fill in your own results below.

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

### `BenchWorker`

```lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActorKit = require(ReplicatedStorage.ActorKit)
local BenchWork = require(ReplicatedStorage.BenchWork)

ActorKit.serve(script:GetActor() :: Actor, {
	Run = function(progress: SharedTable, finished: BindableEvent, iterations: number, jobs: number)
		BenchWork.burn(iterations)
		if SharedTable.increment(progress, "done", 1) + 1 == jobs then
			ActorKit.serial(function()
				finished:Fire()
			end)
		end
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

local function runPool(pool: ActorKit.Pool): number
	local progress = SharedTable.new({ done = 0 })
	local finished = Instance.new("BindableEvent")
	local start = os.clock()
	for _ = 1, JOBS do
		pool:Send("Run", progress, finished, ITERATIONS, JOBS)
	end
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

local serialTime = measure(runSerial)
print(string.format("serial     %8.1f ms", serialTime * 1000))

for _, size in POOL_SIZES do
	local pool = ActorKit.Pool.new(ServerStorage.BenchWorker, size)
	pool:WaitReady()
	local poolTime = measure(function()
		return runPool(pool)
	end)
	pool:Destroy()
	print(string.format("pool %-5d %8.1f ms   x%.2f", size, poolTime * 1000, serialTime / poolTime))
end
```

## How it works

- Every job runs the same math loop, so serial and pool do identical work.
- Each setup runs once as a warm-up, then 7 timed rounds. The median is reported.
- Workers count finished jobs in a `SharedTable`. The last one fires a `BindableEvent` through `ActorKit.serial`, and the timer stops there.
- The pool is created and made ready before timing starts, so setup cost isn't counted.

## Results

Fill this in from the output window.

Machine: Intel Core i7-10750H (6 cores, 12 threads), 16 GB RAM  
Where it ran: Studio

| Setup | Time (ms) | Speedup |
| --- | --- | --- |
| Serial | 251.7 | x1.00 |
| Pool 1 | 276.3 | x0.91 |
| Pool 4 | 66.3 | x3.80 |
| Pool 16 | 47.7 | x5.28 |
| Pool 64 | 45.2 | x5.56 |

## How to read it

- **Pool 1 is about the same as serial, or a bit slower.** One worker means no parallelism, and you pay for messaging. That is expected.
- **Speedup should grow, then flatten.** It stops growing around your CPU's core count. Past that, extra Actors only help with load balancing.
- **Pool 64 may match Pool 16.** More Actors than cores won't add speed.
- **Studio numbers run lower than a live server.** Studio has extra overhead, so treat it as a rough guide.

## Things to try

- **Lower `ITERATIONS`** to 200 or so. At some point the pool becomes slower than serial because each message costs more than the work it carries. That is the point where parallel stops being worth it.
- **Raise `JOBS`** to see how the pool handles a bigger queue.
- **Swap `BenchWork.burn`** for your own real workload, like a raycast batch or pathing math, to get numbers that mean something for your game.
