local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local TeleportSystem = {}
local debugMode = false -- Set to true to see console messages

-- Configuration
local TELEPORT_DURATION = 1.5
local PATHFINDING_TIMEOUT = 1
local HEIGHT_OFFSET = 3
local MAX_TELEPORT_RETRIES = 3
local MAX_PATHFIND_DISTANCE = 1024 -- Maximum safe distance for pathfinding

-- Local references
local localPlayer = Players.LocalPlayer
local character
local humanoid
local humanoidRootPart

-- Track current teleport task and cancellation flag
local currentTeleportTask = nil
local cancelCurrentTeleport = false

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
    }

    for _, mat in ipairs(unsafeMaterials) do
        if raycastResult.Material == mat then
            debugPrint("Position unsafe: Bad material ("..tostring(mat)..")")
            return false
        end
    end

    if raycastResult.Normal.Y < 0.7 then
        debugPrint("Position unsafe: Too steep (normal Y:", raycastResult.Normal.Y)
        return false
    end

    return true
end

local function tweenTeleport(targetCFrame, duration)
    duration = duration or TELEPORT_DURATION

    if not character or not humanoidRootPart then
        debugPrint("Tween failed: No character or HRP")
        return false
    end

    local startTime = tick()

    local tween = TweenService:Create(
        humanoidRootPart,
        TweenInfo.new(
            duration,
            Enum.EasingStyle.Quad,
            Enum.EasingDirection.Out
        ),
        {CFrame = targetCFrame}
    )

    tween:Play()

    while tick() - startTime < duration do
        if cancelCurrentTeleport then
            tween:Cancel()
            debugPrint("Tween cancelled due to new teleport request")
            return false
        end
        if not character or not humanoidRootPart then
            tween:Cancel()
            debugPrint("Tween cancelled: Character changed")
            return false
        end
        RunService.Heartbeat:Wait()
    end

    if character and humanoidRootPart then
        humanoidRootPart.CFrame = targetCFrame
        debugPrint("Tween completed successfully")
        return true
    end

    return false
end

local function pathfindTeleport(targetPosition, duration)
    duration = duration or TELEPORT_DURATION

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
    local endTime = startTime + duration
    local currentSegment = segments[1]
    local segmentProgress = 0

    while tick() < endTime do
        if cancelCurrentTeleport then
            debugPrint("Pathfind teleport cancelled due to new teleport request")
            return false
        end

        local now = tick()
        local elapsed = now - startTime
        local t = elapsed / duration

        local targetDist = t * totalDistance
        local traversedDist = 0

        for i, seg in ipairs(segments) do
            if traversedDist + seg.distance >= targetDist then
                currentSegment = seg
                segmentProgress = (targetDist - traversedDist) / seg.distance
                break
            else
                traversedDist += seg.distance
            end
        end

        if currentSegment then
            local pos = currentSegment.from:Lerp(currentSegment.to, segmentProgress)
            humanoidRootPart.CFrame = CFrame.new(pos + Vector3.new(0, HEIGHT_OFFSET, 0))
        end

        RunService.Heartbeat:Wait()
    end

    if character and humanoidRootPart then
        humanoidRootPart.CFrame = CFrame.new(targetPosition + Vector3.new(0, HEIGHT_OFFSET, 0))
        debugPrint("Path teleport completed successfully")
        return true
    end

    return false
end

-- Main teleport function with cancellation, retries, and fallback
function TeleportSystem.teleport(targetPosition, maxRetries, duration)
    maxRetries = maxRetries or MAX_TELEPORT_RETRIES
    duration = duration or TELEPORT_DURATION

    if not targetPosition then
        debugPrint("No target position provided")
        return false
    end

    -- Cancel current teleport if running
    if currentTeleportTask then
        debugPrint("Cancelling previous teleport")
        cancelCurrentTeleport = true
        currentTeleportTask:Cancel() -- In case it's a task object (roblox coroutine-like)
        -- just in case, wait a frame to let it exit cleanly
        task.wait()
    end

    cancelCurrentTeleport = false

    -- Run the new teleport as a task so it can be canceled
    local co = coroutine.create(function()
        if not character or not humanoidRootPart then
            debugPrint("Waiting for character...")
            initializeCharacter()
        end

        local adjustedPosition = Vector3.new(
            targetPosition.X,
            targetPosition.Y + HEIGHT_OFFSET,
            targetPosition.Z
        )

        local targetCFrame = CFrame.new(adjustedPosition)

        if not isPositionSafe(targetPosition) then
            debugPrint("Target position is not safe — falling back to tween")
            return tweenTeleport(targetCFrame, duration)
        end

        local success = false
        local attempts = 0

        while not success and attempts < maxRetries do
            if cancelCurrentTeleport then
                debugPrint("Teleport cancelled before attempt "..attempts+1)
                return false
            end

            attempts += 1
            debugPrint("Attempt", attempts, "of", maxRetries)

            local distance = (humanoidRootPart.Position - targetPosition).Magnitude
            if distance <= MAX_PATHFIND_DISTANCE then
                success = pathfindTeleport(adjustedPosition, duration)
            else
                debugPrint("Target too far for pathfinding, using tween directly")
            end

            if not success then
                debugPrint("Pathfinding failed or skipped, trying tween...")
                success = tweenTeleport(targetCFrame, duration)
            end

            if not success and attempts < maxRetries then
                task.wait(0.5)
            end
        end

        debugPrint(success and "Teleport succeeded" or "Teleport failed after all attempts")
        return success
    end)

    currentTeleportTask = {
        coroutine = co,
        Cancel = function()
            cancelCurrentTeleport = true
        end
    }

    -- Run the coroutine asynchronously
    task.spawn(function()
        local success, result = coroutine.resume(co)
        if not success then
            debugPrint("Teleport coroutine error:", result)
        end
        currentTeleportTask = nil
    end)

    return true -- we started the teleport, result will be async
end

function TeleportSystem.setDebugMode(enabled)
    debugMode = enabled
end

return TeleportSystem
