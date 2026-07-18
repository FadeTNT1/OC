-- Ender IO Alloy Smelter controller
-- Sends exactly 1 input item to each Alloy Smelter
-- Pulls completed items into a vanilla Minecraft barrel

--------------------------------------------------
-- CONFIGURATION
--------------------------------------------------

-- Input barrel receiving items from AE2
local SOURCE_NAME = "sophisticatedstorage:barrel_0"

-- Normal vanilla Minecraft output barrel
-- Change the number if your modem displays a different name.
local OUTPUT_NAME = "minecraft:barrel_0"

-- Alloy Smelter inventory slots
local INPUT_SLOTS = { 1, 2, 3 }
local OUTPUT_SLOT = 4

-- Delay between complete network scans
local CHECK_INTERVAL = 0.05

--------------------------------------------------
-- PERIPHERAL HELPERS
--------------------------------------------------

local function hasType(name, wantedType)
    local types = { peripheral.getType(name) }

    for _, peripheralType in ipairs(types) do
        if peripheralType == wantedType then
            return true
        end
    end

    return false
end

local function findAlloySmelters()
    local smelters = {}

    for _, name in ipairs(peripheral.getNames()) do
        if name ~= SOURCE_NAME
            and name ~= OUTPUT_NAME
            and string.find(name, "alloy_smelter", 1, true)
            and hasType(name, "inventory") then

            table.insert(smelters, name)
        end
    end

    table.sort(smelters)
    return smelters
end

local function getSortedSlots(inventory)
    local slots = {}

    for slot in pairs(inventory.list()) do
        table.insert(slots, slot)
    end

    table.sort(slots)
    return slots
end

--------------------------------------------------
-- INPUT HANDLING
--------------------------------------------------

local function countInputItems(machine)
    local contents = machine.list()
    local total = 0

    for _, slot in ipairs(INPUT_SLOTS) do
        local item = contents[slot]

        if item then
            total = total + item.count
        end
    end

    return total
end

local function sendOneInput(source, machineName)
    local sourceSlots = getSortedSlots(source)

    for _, sourceSlot in ipairs(sourceSlots) do
        for _, targetSlot in ipairs(INPUT_SLOTS) do
            local success, moved = pcall(function()
                return source.pushItems(
                    machineName,
                    sourceSlot,
                    1,
                    targetSlot
                )
            end)

            if success and moved == 1 then
                return true
            end
        end
    end

    return false
end

--------------------------------------------------
-- OUTPUT HANDLING
--------------------------------------------------

local function collectOutput(outputBarrel, machineName, machine)
    local contents = machine.list()
    local outputItem = contents[OUTPUT_SLOT]

    if not outputItem then
        return 0
    end

    local success, moved = pcall(function()
        return outputBarrel.pullItems(
            machineName,
            OUTPUT_SLOT,
            64
        )
    end)

    if not success then
        print("Could not collect from:")
        print(machineName)
        print(tostring(moved))
        return 0
    end

    return moved
end

--------------------------------------------------
-- STARTUP CHECKS
--------------------------------------------------

term.clear()
term.setCursorPos(1, 1)

if not peripheral.isPresent(SOURCE_NAME) then
    error("Input barrel not found: " .. SOURCE_NAME)
end

if not peripheral.isPresent(OUTPUT_NAME) then
    print("Output barrel not found:")
    print(OUTPUT_NAME)
    print("")
    print("Connected inventories:")

    for _, name in ipairs(peripheral.getNames()) do
        if hasType(name, "inventory") then
            print(name)
        end
    end

    error("Correct OUTPUT_NAME near the top of rc.lua")
end

local source = peripheral.wrap(SOURCE_NAME)
local outputBarrel = peripheral.wrap(OUTPUT_NAME)

if not source or type(source.pushItems) ~= "function" then
    error("Input barrel is not a usable inventory.")
end

if not outputBarrel or type(outputBarrel.pullItems) ~= "function" then
    error("Output barrel is not a usable inventory.")
end

local smelters = findAlloySmelters()

if #smelters == 0 then
    error("No Alloy Smelters were detected.")
end

--------------------------------------------------
-- STATUS DISPLAY
--------------------------------------------------

print("Alloy Smelter Controller")
print("------------------------")
print("Input:  " .. SOURCE_NAME)
print("Output: " .. OUTPUT_NAME)
print("Smelters: " .. #smelters)
print("")
print("Running... Hold Ctrl+T to stop.")

--------------------------------------------------
-- MAIN LOOP
--------------------------------------------------

local startingMachine = 1

while true do
    for offset = 0, #smelters - 1 do
        local index =
            ((startingMachine + offset - 1) % #smelters) + 1

        local machineName = smelters[index]
        local machine = peripheral.wrap(machineName)

        if machine and type(machine.list) == "function" then
            -- First remove completed output.
            collectOutput(outputBarrel, machineName, machine)

            -- Then supply one new item when all input slots are empty.
            if countInputItems(machine) == 0 then
                sendOneInput(source, machineName)
            end
        end
    end

    -- Rotate the first machine so distribution remains fair.
    startingMachine = (startingMachine % #smelters) + 1

    sleep(CHECK_INTERVAL)
end
