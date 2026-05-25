-- Services
local TweenService = game:GetService("TweenService")

return function(model: Model, info: TweenInfo, result: CFrame)
	local cframe = Instance.new("CFrameValue")
	cframe.Value = model:GetPivot()

	cframe:GetPropertyChangedSignal("Value"):Connect(function()
		model:PivotTo(cframe.Value)
	end)

	local tween = TweenService:Create(cframe, info, { Value = result })
	tween:Play()
	tween.Completed:Connect(function()
		cframe:Destroy()
	end)
end
