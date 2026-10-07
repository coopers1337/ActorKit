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
