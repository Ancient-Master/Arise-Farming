local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local TeleportSystem = {}
local debugMode = true -- Set to true to see console messages

-- Configuration
local TELEPORT_DURATION = 1.5
local PATHFINDING_TIMEOUT = 1
local HEIGHT_OFFSET = 3
local MAX_TELEPORT_RETRIES = 3

-- Local references
local localPlayer = Players.LocalPlayer
local character
local humanoid
local humanoidRootPart

-- Debug logging function
local function debugPrint(...)
    if debugMode then
        print("[TeleportSystem]", ...)
    end
end

-- Initialize character references
local function initializeCharacter()
    character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    humanoid = character:WaitForChild("Humanoid")
    humanoidRootPart = character:WaitForChild("HumanoidRootPart")
    
    localPlayer.CharacterAdded:Connect(function(newChar)
        character = newChar
        humanoid = newChar:WaitForChild("Humanoid")
        humanoidRootPart = newChar:WaitForChild("HumanoidRootPart")
        debugPrint("Character changed, updated references")
    end)
    
    debugPrint("Character initialized")
end

-- Initialize immediately
initializeCharacter()

-- Enhanced position safety check
local function isPositionSafe(position)
    local rayOrigin = position + Vector3.new(0, 10, 0)
    local rayDirection = Vector3.new(0, -20, 0)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {character}
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    
    local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
    
    if not raycastResult then
        debugPrint("Position unsafe: No surface detected")
        return false
    end
    
    local unsafeMaterials = {
        Enum.Material.Water,
        Enum.Material.Air,
        Enum.Material.Ice
    }
    
    for _, mat in ipairs(unsafeMaterials) do
        if raycastResult.Material == mat then
            debugPrint("Position unsafe: Bad material ("..tostring(mat)..")")
            return false
        end
    end
    
    -- Additional check for steep slopes
    if raycastResult.Normal.Y < 0.7 then  -- About 45 degree slope
        debugPrint("Position unsafe: Too steep (normal Y:", raycastResult.Normal.Y)
        return false
    end
    
    return true
end

-- Improved tween teleport with velocity preservation
local function tweenTeleport(targetCFrame)
    if not character or not humanoidRootPart then
        debugPrint("Tween failed: No character or HRP")
        return false
    end
    
    local startCFrame = humanoidRootPart.CFrame
    local startTime = tick()
    
    -- Create and play tween
    local tween = TweenService:Create(
        humanoidRootPart,
        TweenInfo.new(
            TELEPORT_DURATION,
            Enum.EasingStyle.Quad,
            Enum.EasingDirection.Out
        ),
        {CFrame = targetCFrame}
    )
    
    tween:Play()
    
    -- Wait for completion with checks
    while tick() - startTime < TELEPORT_DURATION do
        if not character or not humanoidRootPart then
            tween:Cancel()
            debugPrint("Tween cancelled: Character changed")
            return false
        end
        RunService.Heartbeat:Wait()
    end
    
    -- Final position correction
    if character and humanoidRootPart then
        humanoidRootPart.CFrame = targetCFrame
        debugPrint("Tween completed successfully")
        return true
    end
    
    return false
end

local function pathfindTeleport(targetPosition)
    if not character or not humanoidRootPart then
        debugPrint("Pathfind failed: Missing character components")
        return false
    end

    -- Create path
    local path = PathfindingService:CreatePath({
        AgentRadius = humanoid.HipHeight,
        AgentHeight = 5,
        AgentCanJump = true,
        WaypointSpacing = 3,
    })

    -- Compute path with timeout
    local pathSuccess, pathStatus
    local computeThread = coroutine.create(function()
        path:ComputeAsync(humanoidRootPart.Position, targetPosition)
    end)

    local startComputeTime = tick()
    coroutine.resume(computeThread)

    while coroutine.status(computeThread) ~= "dead" and tick() - startComputeTime < PATHFINDING_TIMEOUT do
        RunService.Heartbeat:Wait()
    end

    if coroutine.status(computeThread) ~= "dead" then
        debugPrint("Pathfinding timed out")
        return false
    end

    pathStatus = path.Status

    if pathStatus ~= Enum.PathStatus.Success then
        debugPrint("Pathfinding failed with status:", tostring(pathStatus))
        return false
    end

    local waypoints = path:GetWaypoints()
    if #waypoints < 2 then
        debugPrint("Not enough waypoints")
        return false
    end

    -- Compute total distance
    local totalDistance = 0
    for i = 2, #waypoints do
        totalDistance += (waypoints[i].Position - waypoints[i - 1].Position).Magnitude
    end

    if totalDistance <= 0 then
        debugPrint("Zero distance path")
        return false
    end

    -- Step teleport along waypoints within TELEPORT_DURATION
    local startTime = tick()

    for i = 2, #waypoints do
        if not character or not humanoidRootPart then
            debugPrint("Path teleport cancelled: Character changed")
            return false
        end

        local prevPos = waypoints[i - 1].Position
        local currPos = waypoints[i].Position
        local segmentDistance = (currPos - prevPos).Magnitude
        local segmentTime = (segmentDistance / totalDistance) * TELEPORT_DURATION

        humanoidRootPart.CFrame = CFrame.new(currPos + Vector3.new(0, HEIGHT_OFFSET, 0))

        local segmentStart = tick()
        while tick() - segmentStart < segmentTime do
            RunService.Heartbeat:Wait()
        end
    end

    -- Final adjustment
    if character and humanoidRootPart then
        humanoidRootPart.CFrame = CFrame.new(targetPosition + Vector3.new(0, HEIGHT_OFFSET, 0))
        debugPrint("Path teleport completed successfully")
        return true
    end

    return false
end


-- Main teleport function with retries
function TeleportSystem.teleport(targetPosition, maxRetries)
    maxRetries = maxRetries or MAX_TELEPORT_RETRIES
    
    if not targetPosition then
        debugPrint("No target position provided")
        return false
    end
    
    -- Wait for character to be ready if needed
    if not character or not humanoidRootPart then
        debugPrint("Waiting for character...")
        initializeCharacter()
    end
    
    -- Adjust target position
    local adjustedPosition = Vector3.new(
        targetPosition.X,
        targetPosition.Y + HEIGHT_OFFSET,
        targetPosition.Z
    )
    
    local targetCFrame = CFrame.new(adjustedPosition)
    
    -- Check position safety
    if not isPositionSafe(targetPosition) then
        debugPrint("Target position is not safe")
        return false
    end
    
    -- Try teleport with retries
    local success = false
    local attempts = 0
    
    while not success and attempts < maxRetries do
        attempts += 1
        debugPrint("Attempt", attempts, "of", maxRetries)
        
        -- First try pathfinding
        success = pathfindTeleport(adjustedPosition)
        
        -- Fall back to tween if pathfinding fails
        if not success then
            debugPrint("Pathfinding failed, trying tween...")
            success = tweenTeleport(targetCFrame)
        end
        
        -- Small delay between attempts
        if not success and attempts < maxRetries then
            task.wait(0.5)
        end
    end
    
    debugPrint(success and "Teleport succeeded" or "Teleport failed after all attempts")
    return success
end

-- Public function to toggle debug mode
function TeleportSystem.setDebugMode(enabled)
    debugMode = enabled
end

return TeleportSystem