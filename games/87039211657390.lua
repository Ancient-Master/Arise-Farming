local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local LocalPlayer = playersService.LocalPlayer

local vape = shared.vape
local entitylib = vape.Libraries.entity
local targetinfo = vape.Libraries.targetinfo
local sessioninfo = vape.Libraries.sessioninfo
local playersService = cloneref(game:GetService('Players'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local LocalPlayer = playersService.LocalPlayer


local test = vape.Categories.Combat:CreateModule({
    Name = 'Test',
    Function = function(callback)
       a = callback
        while a do
            task.wait()
        require(replicatedStorage.SharedModules.WeaponsModule).Click({["KeyCode"] = Enum.KeyCode.ButtonX}, false, nil, true) 
    end
    end,
    Tooltip = 'This is a test module'
})

