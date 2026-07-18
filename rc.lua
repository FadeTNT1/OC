-- Ender IO Alloy Smelter one-item distributor
-- CC:Tweaked 1.120.0 / Minecraft 1.21.1

--------------------------------------------------
-- CONFIGURATION
--------------------------------------------------

-- Change this to the name displayed when you right-click
-- the modem attached to your AE2 input barrel or chest.
local SOURCE_NAME = "minecraft:barrel_0"

-- Total number of items allowed across all three
-- input slots of each Alloy Smelter.
local MAX_INPUT_ITEMS = 1

-- How frequently the network is checked.
local CHECK_INTERVAL = 0.25

--------------------------------------------------
-- ALLOY SMELTER SLOT LAYOUT
--------------------------------------------------

local INPUT_SLOTS = { 1, 2, 3 }

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function hasPeripheralType(name, wantedType)
    local types = { peripheral.getType(name) }

    for _, peripheralType in ipairs(types) do
        if peripheralType == wantedType then
            return true
        end
    end

    return false
end

local function listInventories()
    print("Inventories visible on the wired network:")

    for _, name in ipairs(peripheral.getNames()) do
        if hasPeripheralType(name, "inventory") then
            print("  " .. name)
        end
    end
end

local function findAlloySmelters()
    local found = {}

    for _, name in ipairs(peripheral.getNames()) do
        if name ~= SOURCE_NAME
            and string.find(name, "alloy_smelter", 1, true)
            and hasPeripheralType(name, "inventory") then

            table.insert(found, name)
        end
    end

    table.sort(found)
    return found
end

local function sortedInventorySlots(inventory)
    local slots = {}

    for slot in pairs(inventory.list()) do
        table.insert(slots, slot)
    end

    table.sort(slots)
    return slots
end

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

local function sendOneItem(source, targetName)
    local sourceSlots = sortedInventorySlots(source)

    for _, sourceSlot in ipairs(sourceSlots) do
        -- Try each of the Alloy Smelter's three input slots.
        -- Ender IO will reject items which are not valid inputs.
        for _, targetSlot in ipairs(INPUT_SLOTS) do
            local success, transferred = pcall(
                source.pushItems,
                targetName,
                sourceSlot,
                1,
                targetSlot
            )

            if success and transferred == 1 then
                return true
            end
        end
    end

    return false
end

local function serviceMachine(source, targetName)
    if not peripheral.isPresent(targetName) then
        return false
    end

    local machine = peripheral.wrap(targetName)

    if not machine or type(machine.list) ~= "function" then
        return false
    end

    local currentInputCount = countInputItems(machine)

    if currentInputCount >= MAX_INPUT_ITEMS then
        return false
    end

    return sendOneItem(source, targetName)
end

--------------------------------------------------
-- STARTUP CHECKS
--------------------------------------------------

term.clear()
term.setCursorPos(1, 1)

if not peripheral.isPresent(SOURCE_NAME) then
    print("ERROR: Source inventory not found:")
    print(SOURCE_NAME)
    print("")
    listInventories()
    error("Correct SOURCE_NAME at the top of startup.")
end

local source = peripheral.wrap(SOURCE_NAME)

if not source
    or type(source.list) ~= "function"
    or type(source.pushItems) ~= "function" then

    error(SOURCE_NAME .. " is not a usable inventory.")
end

local targets = findAlloySmelters()

if #targets == 0 then
    print("No Alloy Smelters were detected.")
    print("")
    listInventories()
    error("Check the Wired Modems and machine side settings.")
end

print("Alloy Smelter Distributor")
print("-------------------------")
print("Source: " .. SOURCE_NAME)
print("Smelters: " .. #targets)
print("Maximum input items: " .. MAX_INPUT_ITEMS)
print("")
print("Running... Hold Ctrl+T to stop.")

--------------------------------------------------
-- MAIN LOOP
--------------------------------------------------

local startingMachine = 1

while true do
    -- Start at a different machine each cycle so the first
    -- machine does not always receive scarce items first.
    for offset = 0, #targets - 1 do
        local index = ((startingMachine + offset - 1) % #targets) + 1
        local targetName = targets[index]

        local success, problem = pcall(
            serviceMachine,
            source,
            targetName
        )

        if not success then
            print("Error with " .. targetName .. ":")
            print(tostring(problem))
        end
    end

    startingMachine = (startingMachine % #targets) + 1
    sleep(CHECK_INTERVAL)
end