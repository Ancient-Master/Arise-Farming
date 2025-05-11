local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Wait until player is loaded
repeat
    task.wait()
until LocalPlayer:GetAttribute("Loaded") == true

-- Get required modules
local SharedModules = ReplicatedStorage.SharedModules
local PetsController = require(SharedModules.Pets.PetsController)
local PetsService = require(SharedModules.PetsService)
local ExtraFunctions = require(SharedModules.ExtraFunctions)

-- Store the current target (so pets don't switch)
local currentTarget = nil

-- Function to find closest enemy
local function findClosestEnemy()
    if not LocalPlayer.Character or not LocalPlayer.Character.PrimaryPart then
        return nil
    end
    
    local playerPos = LocalPlayer.Character.PrimaryPart.Position
    local closestEnemy = nil
    local closestDistance = math.huge
    
    for _, clientEnemy in workspace.__Main.__Enemies.Client:GetChildren() do
        local serverEnemy = workspace.__Main.__Enemies.Server:FindFirstChild(clientEnemy.Name, true)
        if serverEnemy and not serverEnemy:GetAttribute("Dead") and serverEnemy:GetAttribute("HP") > 0 then
            local distance = (clientEnemy.PrimaryPart.Position - playerPos).Magnitude
            if distance < closestDistance then
                closestDistance = distance
                closestEnemy = clientEnemy
            end
        end
    end
    
    return closestEnemy, closestDistance
end

local function hasAvailablePets()
    local petsFolder = workspace.__Main.__Pets:FindFirstChild(LocalPlayer.UserId)
    if not petsFolder then return false end
    
    for _, pet in ipairs(petsFolder:GetChildren()) do
        if not pet:GetAttribute("Attacking") then
            return true
        end
    end
    
    return false
end

-- Attack the nearest enemy once (only if no current target)
local function attackNearestEnemyOnce()

    
    -- Only find a new target if we don't have one
    if not currentTarget then
        local enemy, distance = findClosestEnemy()
        if enemy and PetsService:GetRange(LocalPlayer) > distance and hasAvailablePets() then
            currentTarget = enemy.Name  -- Store the target name so we don't switch
            PetsController.AutoEnemy(enemy)
        end
    end
end




local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
   Name = "Arise Farming",
   Icon = 0, -- Icon in Topbar. Can use Lucide Icons (string) or Roblox Image (number). 0 to use no icon (default).
   LoadingTitle = "Arise Farming",
   LoadingSubtitle = "Loading...",
   Theme = "Amethyst", -- Check https://docs.sirius.menu/rayfield/configuration/themes

   DisableRayfieldPrompts = false,
   DisableBuildWarnings = false, -- Prevents Rayfield from warning when the script has a version mismatch with the interface

   ConfigurationSaving = {
      Enabled = true,
      FolderName = "Arise", -- Create a custom folder for your hub/game
      FileName = "AriseFarming" -- Create a custom file name for your hub/game
   },

   Discord = {
      Enabled = false, -- Prompt the user to join your Discord server if their executor supports it
      Invite = "noinvitelink", -- The Discord invite code, do not include discord.gg/. E.g. discord.gg/ ABCD would be ABCD
      RememberJoins = true -- Set this to false to make them join the discord every time they load it up
   },

   KeySystem = false, -- Set this to true to use our key system
   KeySettings = {
      Title = "Untitled",
      Subtitle = "Key System",
      Note = "No method of obtaining the key is provided", -- Use this to tell the user how to get a key
      FileName = "Key", -- It is recommended to use something unique as other scripts using Rayfield may overwrite your key file
      SaveKey = true, -- The user's key will be saved, but if you change the key, they will be unable to use your script
      GrabKeyFromSite = false, -- If this is true, set Key below to the RAW site you would like Rayfield to get the key from
      Key = {"Hello"} -- List of keys that will be accepted by the system, can be RAW file links (pastebin, github etc) or simple strings ("hello","key22")
   }
})

local Label 


local Tab = Window:CreateTab("Arise", 4483362458) -- Title, Image

local Toggle = Tab:CreateToggle({
   Name = "Auto Punch",
   CurrentValue = false,
   Flag = "ClickToggle",
   Callback = function(Value)
      a = Value
      while a do
         task.wait()
         require(ReplicatedStorage.SharedModules.WeaponsModule).Click({["KeyCode"] = Enum.KeyCode.ButtonX}, false, nil, true)
      end
   end,
})


local Toggle1 = Tab:CreateToggle({
   Name = "Auto Send Shadows",
   CurrentValue = false,
   Flag = "AttackToggle",
   Callback = function(Value)
      b = Value
      while b and task.wait() do
         -- Reset current target if invalid
         if currentTarget then
            local enemy = workspace.__Main.__Enemies.Client:FindFirstChild(currentTarget)
            if not enemy or not enemy:GetAttribute("HP") or enemy:GetAttribute("HP") <= 0 or enemy:GetAttribute("Dead") then
               currentTarget = nil
            else
               -- Re-attack the same enemy if still valid
               PetsController.AutoEnemy(enemy)
            end
         end
         
         -- Find new target if none exists
         if not currentTarget then
            local enemy, distance = findClosestEnemy()
            if enemy then
               local petRange = PetsService:GetRange(LocalPlayer)
               if petRange and petRange > distance and hasAvailablePets() then
                  currentTarget = enemy.Name
                  PetsController.AutoEnemy(enemy)
               end
            end
         end
      end
      
      -- Reset target when toggle is turned off
      if not b then
         currentTarget = nil
      end
   end,
})
local Dropdown = Tab:CreateDropdown({
   Name = "Dropdown Example",
   Options = {"Option 1","Option 2","Option 3","Option 4","Option 5","Option 6","Option 7"},
   CurrentOption = {"Option 1"},
   MultipleOptions = false,
   Flag = "Dropdown1", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
   Callback = function(Options)
   -- The function that takes place when the selected option is changed
   -- The variable (Options) is a table of strings for the current selected options
   end,
})
Rayfield:LoadConfiguration()






