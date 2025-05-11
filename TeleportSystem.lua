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
    local endTime = startTime + TELEPORT_DURATION

    while tick() < endTime do
        if not character or not humanoidRootPart then
            debugPrint("Tween interrupted: Character lost")
            return false
        end

        local now = tick()
        local alpha = math.clamp((now - startTime) / TELEPORT_DURATION, 0, 1)

        local interpolated = startCFrame:Lerp(targetCFrame, alpha)
        humanoidRootPart.CFrame = interpolated

        RunService.Heartbeat:Wait()
    end

    -- Final snap to ensure precision
    if character and humanoidRootPart then
        humanoidRootPart.CFrame = targetCFrame
        debugPrint("Manual tween teleport completed successfully")
        return true
    end

    return false
end


local function pathfindTeleport(targetPosition)
    if not character or not humanoidRootPart then
        debugPrint("Pathfind failed: Missing character components")
        return false
    end

    local path = PathfindingService:CreatePath({
        AgentRadius = humanoid.HipHeight,
        AgentHeight = 5,
        AgentCanJump = true,
        WaypointSpacing = 3,
    })

    path:ComputeAsync(humanoidRootPart.Position, targetPosition)

    if path.Status ~= Enum.PathStatus.Success then
        debugPrint("Pathfinding failed with status:", tostring(path.Status))
        return false
    end

    local waypoints = path:GetWaypoints()
    if #waypoints < 2 then
        debugPrint("Not enough waypoints")
        return false
    end

    -- Precompute timing
    local totalDistance = 0
    local segments = {}
    for i = 2, #waypoints do
        local dist = (waypoints[i].Position - waypoints[i - 1].Position).Magnitude
        table.insert(segments, {
            from = waypoints[i - 1].Position,
            to = waypoints[i].Position,
            distance = dist
        })
        totalDistance += dist
    end

    if totalDistance == 0 then
        debugPrint("Zero distance path")
        return false
    end

    local startTime = tick()
    local endTime = startTime + TELEPORT_DURATION
    local currentSegmentIndex = 1
    local currentSegment = segments[1]
    local segmentProgress = 0

    while tick() < endTime do
        local now = tick()
        local elapsed = now - startTime
        local t = elapsed / TELEPORT_DURATION

        -- Compute how far along total distance we should be
        local targetDist = t * totalDistance
        local traversedDist = 0

        -- Find correct segment
        for i, seg in ipairs(segments) do
            if traversedDist + seg.distance >= targetDist then
                currentSegmentIndex = i
                currentSegment = seg
                segmentProgress = (targetDist - traversedDist) / seg.distance
                break
            else
                traversedDist += seg.distance
            end
        end

        -- Lerp position
        if currentSegment then
            local pos = currentSegment.from:Lerp(currentSegment.to, segmentProgress)
            humanoidRootPart.CFrame = CFrame.new(pos + Vector3.new(0, HEIGHT_OFFSET, 0))
        end

        RunService.Heartbeat:Wait()
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