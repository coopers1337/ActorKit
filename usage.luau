local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ActorKit = require(ReplicatedStorage.ActorKit)

local pool = ActorKit.Pool.new(ServerStorage.NpcWorker, 16)
pool:WaitReady()

pool:Send("Think", npcModel, targetPosition)
pool:SendKeyed(npcId, "Steer", npcId, direction)
pool:Broadcast("Reset")
