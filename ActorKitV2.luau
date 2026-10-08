--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local READY_ATTRIBUTE = "ActorKitReady"

export type Handler = (...any) -> ()

type PoolState = {
	actors: { Actor },
	size: number,
	cursor: number,
}

local Pool = {}
Pool.__index = Pool

export type Pool = typeof(setmetatable({} :: PoolState, Pool))

local function defaultParent(): Instance
	if RunService:IsServer() then
		return ServerScriptService
	end
	return (Players.LocalPlayer :: Player):WaitForChild("PlayerScripts")
end

function Pool.new(template: LuaSourceContainer, size: number, parent: Instance?): Pool
	assert(size >= 1, "Pool size must be at least 1")
	local container = parent or defaultParent()
	local actors = table.create(size)
	for index = 1, size do
		local actor = Instance.new("Actor")
		actor.Name = `{template.Name}_{index}`
		template:Clone().Parent = actor
		actor.Parent = container
		actors[index] = actor
	end
	return setmetatable({ actors = actors, size = size, cursor = 0 }, Pool)
end

function Pool.Send(self: Pool, topic: string, ...: any)
	local cursor = self.cursor % self.size + 1
	self.cursor = cursor
	self.actors[cursor]:SendMessage(topic, ...)
end

function Pool.SendKeyed(self: Pool, key: number, topic: string, ...: any)
	self.actors[math.floor(key) % self.size + 1]:SendMessage(topic, ...)
end

function Pool.SendBatch(self: Pool, topic: string, jobs: { any }, ...: any)
	local base = #jobs // self.size
	local extra = #jobs % self.size
	local first = 1
	for index = 1, self.size do
		local count = base + (if index <= extra then 1 else 0)
		if count == 0 then
			break
		end
		local last = first + count - 1
		self.actors[index]:SendMessage(topic, table.move(jobs, first, last, 1, table.create(count)), ...)
		first = last + 1
	end
end

function Pool.Broadcast(self: Pool, topic: string, ...: any)
	for _, actor in self.actors do
		actor:SendMessage(topic, ...)
	end
end

function Pool.WaitReady(self: Pool)
	for _, actor in self.actors do
		while not actor:GetAttribute(READY_ATTRIBUTE) do
			actor:GetAttributeChangedSignal(READY_ATTRIBUTE):Wait()
		end
	end
end

function Pool.Destroy(self: Pool)
	for _, actor in self.actors do
		actor:Destroy()
	end
	table.clear(self.actors)
	self.size = 0
end

local function serve(actor: Actor, handlers: { [string]: Handler }, parallel: boolean?): () -> ()
	local connections: { RBXScriptConnection } = {}
	for topic, handler in handlers do
		table.insert(
			connections,
			if parallel == false
				then actor:BindToMessage(topic, handler)
				else actor:BindToMessageParallel(topic, handler)
		)
	end
	actor:SetAttribute(READY_ATTRIBUTE, true)
	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
	end
end

local function finish(ok: boolean, ...: any): ...any
	task.desynchronize()
	if not ok then
		error((...), 0)
	end
	return ...
end

local function serial(callback: (...any) -> ...any, ...: any): ...any
	task.synchronize()
	return finish(pcall(callback, ...))
end

return table.freeze({
	Pool = Pool,
	serve = serve,
	serial = serial,
})
