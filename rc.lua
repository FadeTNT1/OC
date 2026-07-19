-- Fast Alloy Smelter controller for CC:Tweaked + Ender IO
--
-- Network layout:
--   * One gold Sophisticated Storage barrel containing ores (source)
--   * One basic oak Sophisticated Storage barrel receiving products (output)
--   * Any number of Ender IO Alloy Smelters
--   * Every block connected to the same CC:Tweaked wired-modem network
--
-- The larger Sophisticated Storage barrel is selected as the source.
-- The smaller Sophisticated Storage barrel is selected as the output.

local Controller = {}

local INPUT_SLOT_1 = 1
local INPUT_SLOT_2 = 2
local INPUT_SLOT_3 = 3
local OUTPUT_SLOT = 4
local OUTPUT_LIMIT = 64

local function hasPeripheralType(api, name, wanted)
    local types = { api.getType(name) }

    for index = 1, #types do
        if types[index] == wanted then
            return true
        end
    end

    return false
end

function Controller.detectBarrels(api)
    local barrels = {}

    for _, name in ipairs(api.getNames()) do
        if string.find(name, "sophisticatedstorage:barrel", 1, true)
            and hasPeripheralType(api, name, "inventory") then

            local inventory = api.wrap(name)

            if inventory and type(inventory.size) == "function" then
                barrels[#barrels + 1] = {
                    name = name,
                    size = inventory.size(),
                }
            end
        end
    end

    if #barrels < 2 then
        error("Connect both Sophisticated Storage barrels to the wired network.")
    end

    table.sort(barrels, function(left, right)
        if left.size == right.size then
            return left.name < right.name
        end

        return left.size < right.size
    end)

    local output = barrels[1]
    local source = barrels[#barrels]

    if source.size == output.size then
        error("Could not distinguish the gold source barrel from the oak output barrel.")
    end

    return source.name, output.name
end

function Controller.findSmelters(api, sourceName, outputName)
    local smelters = {}

    for _, name in ipairs(api.getNames()) do
        if name ~= sourceName
            and name ~= outputName
            and string.find(name, "alloy_smelter", 1, true)
            and hasPeripheralType(api, name, "inventory") then

            local inventory = api.wrap(name)

            if inventory
                and type(inventory.list) == "function"
                and type(inventory.pushItems) == "function" then

                smelters[#smelters + 1] = {
                    name = name,
                    inventory = inventory,
                }
            end
        end
    end

    table.sort(smelters, function(left, right)
        return left.name < right.name
    end)

    return smelters
end

function Controller.newSourceState(source)
    local slots = {}

    for slot, item in pairs(source.list()) do
        if item.count and item.count > 0 then
            slots[#slots + 1] = {
                slot = slot,
                count = item.count,
            }
        end
    end

    return {
        slots = slots,
        index = 1,
    }
end

function Controller.pushOneInput(source, machineName, sourceState)
    local slots = sourceState.slots
    local slotCount = #slots

    if slotCount == 0 then
        return 0
    end

    local checked = 0

    while checked < slotCount do
        local entry = slots[sourceState.index]

        if entry and entry.count > 0 then
            local moved = source.pushItems(
                machineName,
                entry.slot,
                1,
                INPUT_SLOT_1
            )

            if moved > 0 then
                entry.count = entry.count - moved

                if entry.count <= 0 then
                    sourceState.index = (sourceState.index % slotCount) + 1
                end

                return moved
            end
        end

        sourceState.index = (sourceState.index % slotCount) + 1
        checked = checked + 1
    end

    return 0
end

function Controller.serviceMachine(
    source,
    outputName,
    machineName,
    machine,
    sourceState
)
    local items = machine.list()
    local movedOut = 0

    -- Empty the finished-product slot first.
    local outputItem = items[OUTPUT_SLOT]

    if outputItem then
        movedOut = machine.pushItems(
            outputName,
            OUTPUT_SLOT,
            OUTPUT_LIMIT
        )

        -- The output barrel is full or otherwise blocked. Do not add more work.
        if movedOut < outputItem.count then
            return movedOut, 0
        end
    end

    -- Keep exactly one total input item in the smelter.
    if items[INPUT_SLOT_1]
        or items[INPUT_SLOT_2]
        or items[INPUT_SLOT_3] then

        return movedOut, 0
    end

    local movedIn = Controller.pushOneInput(
        source,
        machineName,
        sourceState
    )

    return movedOut, movedIn
end

function Controller.runPass(source, outputName, smelters, startingIndex)
    local sourceState = Controller.newSourceState(source)
    local machineCount = #smelters

    if machineCount == 0 then
        return 1
    end

    for offset = 0, machineCount - 1 do
        local index = ((startingIndex + offset - 1) % machineCount) + 1
        local entry = smelters[index]

        Controller.serviceMachine(
            source,
            outputName,
            entry.name,
            entry.inventory,
            sourceState
        )
    end

    return (startingIndex % machineCount) + 1
end

local args = { ... }

if args[1] == "__test__" then
    return Controller
end

local sourceName, outputName = Controller.detectBarrels(peripheral)
local source = peripheral.wrap(sourceName)
local smelters = Controller.findSmelters(
    peripheral,
    sourceName,
    outputName
)

if not source or type(source.list) ~= "function"
    or type(source.pushItems) ~= "function" then

    error("The detected gold source barrel is not a usable inventory.")
end

if #smelters == 0 then
    error("No Ender IO Alloy Smelters were detected on the wired network.")
end

term.clear()
term.setCursorPos(1, 1)
print("Fast Alloy Smelter Controller")
print("-----------------------------")
print("Source: " .. sourceName)
print("Output: " .. outputName)
print("Smelters: " .. #smelters)
print("")
print("Running at maximum polling speed.")
print("Hold Ctrl+T to stop.")

local startingIndex = 1

while true do
    startingIndex = Controller.runPass(
        source,
        outputName,
        smelters,
        startingIndex
    )

    -- Yield exactly once after the complete machine array is serviced.
    -- In CC:Tweaked this resumes on the next Minecraft tick.
    sleep(0)
end
