local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local TeleportSystem = {}

-- Configuration
local TELEPORT_DURATION = 1.5 -- Seconds for teleport to complete
local PATHFINDING_TIMEOUT = 1 -- Seconds to wait for pathfinding
local HEIGHT_OFFSET = 3 -- How many studs above the target position to arrive

-- Local player reference
local localPlayer = Players.LocalPlayer
local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
localPlayer.CharacterAdded:Connect(function(newChar)
    character = newChar
end)

-- Helper function to check if a position is safe
local function isPositionSafe(position)
    local rayOrigin = position + Vector3.new(0, 10, 0)
    local rayDirection = Vector3.new(0, -20, 0)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {character}
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    
    local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
    
    if raycastResult then
        local material = raycastResult.Material
        return not (material == Enum.Material.Water or material == Enum.Material.Air)
    end
    return false
end

-- Tween teleport method
local function tweenTeleport(targetCFrame)
    if not character or not character:FindFirstChild("HumanoidRootPart") then return false end
    
    local humanoidRootPart = character.HumanoidRootPart
    local startTime = tick()
    
    -- Create a tween
    local tweenInfo = TweenInfo.new(
        TELEPORT_DURATION,
        Enum.EasingStyle.Linear,
        Enum.EasingDirection.InOut
    )
    
    local tween = TweenService:Create(humanoidRootPart, tweenInfo, {CFrame = targetCFrame})
    tween:Play()
    
    -- Wait for tween to complete or character to change
    while tick() - startTime < TELEPORT_DURATION do
        if not character or not character:FindFirstChild("HumanoidRootPart") or humanoidRootPart ~= character.HumanoidRootPart then
            tween:Cancel()
            return false
        end
        RunService.Heartbeat:Wait()
    end
    
    -- Ensure final position is correct
    if character and character:FindFirstChild("HumanoidRootPart") then
        character.HumanoidRootPart.CFrame = targetCFrame
    end
    
    return true
end

-- Pathfinding teleport method
local function pathfindTeleport(targetPosition)
    if not character or not character:FindFirstChild("Humanoid") then return false end
    
    local humanoid = character.Humanoid
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return false end
    
    -- Calculate path
    local path = PathfindingService:CreatePath({
        AgentRadius = humanoid.HipHeight,
        AgentHeight = 5, -- Standard humanoid height
        AgentCanJump = true,
        WaypointSpacing = 4
    })
    
    path:ComputeAsync(humanoidRootPart.Position, targetPosition)
    
    if path.Status ~= Enum.PathStatus.Success then return false end
    
    local waypoints = path:GetWaypoints()
    if #waypoints == 0 then return false end
    
    local startTime = tick()
    local totalDistance = 0
    local previousPosition = humanoidRootPart.Position
    
    -- Calculate total path distance for timing
    for i, waypoint in ipairs(waypoints) do
        if i > 1 then
            totalDistance += (waypoints[i].Position - waypoints[i-1].Position).Magnitude
        end
    end
    
    if totalDistance <= 0 then return false end
    
    -- Move along path
    for i, waypoint in ipairs(waypoints) do
        if i == 1 then continue end
        
        local segmentDistance = (waypoint.Position - waypoints[i-1].Position).Magnitude
        local segmentTime = (segmentDistance / totalDistance) * TELEPORT_DURATION
        
        humanoid:MoveTo(waypoint.Position)
        
        local segmentStart = tick()
        while (tick() - segmentStart) < segmentTime do
            if not character or not character:FindFirstChild("HumanoidRootPart") then
                humanoid:MoveTo(humanoidRootPart.Position) -- Cancel movement
                return false
            end
            RunService.Heartbeat:Wait()
        end
    end
    
    -- Ensure final position is correct
    if character and character:FindFirstChild("HumanoidRootPart") then
        character.HumanoidRootPart.CFrame = CFrame.new(targetPosition)
    end
    
    return true
end

-- Main teleport function
function TeleportSystem.teleport(targetPosition)
    if not character or not targetPosition then return false end
    
    -- Check if position is safe
    if not isPositionSafe(targetPosition) then
        return false
    end
    
    -- Adjust target position with height offset
    local adjustedPosition = Vector3.new(
        targetPosition.X,
        targetPosition.Y + HEIGHT_OFFSET,
        targetPosition.Z
    )
    
    local targetCFrame = CFrame.new(adjustedPosition)
    
    -- First try pathfinding
    local success = pathfindTeleport(adjustedPosition)
    
    -- If pathfinding fails, fall back to tween
    if not success then
        success = tweenTeleport(targetCFrame)
    end
    
    return success
end

return TeleportSystem