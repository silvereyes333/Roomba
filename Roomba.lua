--[[
-- Roomba
- (Thanks to BalkiTheWise for the name)
 ]]

Roomba = {
    name = "Roomba",
    author = "Wobin, CrazyDutchGuy, Ayantir & silvereyes",
    version = "17.0.9",
    website = "http://www.esoui.com/downloads/info402-Roomba.html",
    debugMode = false,
}

local db
local defaults = {
    RoombaAtGBank = true,
    RoombaPosition = KEYBIND_STRIP_ALIGN_LEFT,
}
local addon = Roomba
local DELAY = 100
local currentRun = {}
local currentBank
local checkingBank
local restackInProgress
local duplicates = {}
local descriptorName = addon.name
local UI
local inBagCollection = {}
local cSlot
local cSlotIdx
local cInstanceId
local cItemDuplicateList
local keyBindIndex = 1
local waitingRetries = 1
local keybindCheck
local keybindDescriptor
local currentReturnIndex
local lastRestackResult = {}
local itemIndex
local slotIndex
local qtyToMoveToGuildBank
local Debug

function Debug(message)
    if Roomba.debugMode then
        d("[RB-DEBUG] " .. message)
    end
end

-- Flag for other addons. Returns true while Roomba restacks
function addon.WorkInProgress()
    return restackInProgress
end

-- Scan in a stackable bag
local function ScanInStackableBag(bagToScan)

    local lookUp = {}
    local duplitemp = {}
    duplicates = {}
    
    -- We only need to store slots with items
    for index, slot in pairs(bagToScan) do
        
        -- Stack at max?
        local stack, maxStack = GetSlotStackSize(slot.bagId, slot.slotIndex)
        
        -- Stack is not at max
        if stack ~= maxStack then
            
            -- itemId
            local itemInstanceId = slot.itemInstanceId
            
            -- We already find this item before
            if lookUp[itemInstanceId] then
                -- Already marked as duplicate?
                if not duplitemp[itemInstanceId] then
                    -- Duplicate
                    duplitemp[itemInstanceId] = lookUp[itemInstanceId]
                end
            else
                -- New item found
                lookUp[itemInstanceId] = {}
            end
            
            -- Now group all items by id
            table.insert(lookUp[itemInstanceId], {slotId = slot.slotIndex, stack = stack, texture = slot.iconFile, name = slot.name, itemInstanceId = slot.itemInstanceId})
            
        end
        
    end
    
    for _, data in pairs(duplitemp) do
        table.insert(duplicates, data)
    end

end

-- Bank is ready! Find those duplicates! Runs when EVENT_GUILD_BANK_ITEMS_READY + 1s
local function RoombaReady()
    
    -- Are we in the process of checking the bank? Need to protect due to Keybinding
    if (not checkingBank) then return end
    
    local bagToScan = SHARED_INVENTORY:GenerateFullSlotData(nil, BAG_GUILDBANK)
    
    -- If Guild does not get a bank , should not happend
    if DoesGuildHavePrivilege(currentBank, GUILD_PRIVILEGE_BANK_DEPOSIT) then
        -- If no permission, don't do
        if DoesPlayerHaveGuildPermission(currentBank, GUILD_PERMISSION_BANK_DEPOSIT) and DoesPlayerHaveGuildPermission(currentBank, GUILD_PERMISSION_BANK_WITHDRAW) then
            
            ScanInStackableBag(bagToScan)
            
            -- If they're is no buttons, add them
            if not KEYBIND_STRIP:HasKeybindButtonGroup(keybindDescriptor) then
                if not KEYBIND_STRIP[keybindCheck] then
                    KEYBIND_STRIP:AddKeybindButtonGroup(keybindDescriptor)
                elseif not KEYBIND_STRIP[keybindCheck][2] then
                    keyBindIndex = 2
                    KEYBIND_STRIP:AddKeybindButtonGroup(keybindDescriptor)
                end
            -- Update descriptors. Descriptors update will call Roomba.HaveStuffToStack and show Restack button if needed
            elseif KEYBIND_STRIP:HasKeybindButtonGroup(keybindDescriptor) then
                KEYBIND_STRIP:UpdateKeybindButtonGroup(keybindDescriptor)
            end
            
            currentRun = {}
            
        else
            if KEYBIND_STRIP:HasKeybindButtonGroup(keybindDescriptor) then
                KEYBIND_STRIP:RemoveKeybindButtonGroup(keybindDescriptor)
            end
        end
    end
    
end

local function StopStackingProcess()

    Debug("StopStackingProcess()")
    cInstanceId = nil
    cSlotIdx = nil
    cSlot = nil
    inBagCollection = {}
    currentReturnIndex = nil
    restackInProgress = false
    keyBindIndex = 1
    waitingRetries = 1
    
end

-- Stop a Guild bank restack and do another scan
local function StopGBRestackAndRestartScan()

    local self = addon
    Debug("StopGBRestackAndRestartScan()")
    
    -- Unregister
    EVENT_MANAGER:UnregisterForEvent(self.name, EVENT_GUILD_BANK_TRANSFER_ERROR)
    EVENT_MANAGER:UnregisterForEvent(self.name, EVENT_GUILD_BANK_ITEM_ADDED)
    EVENT_MANAGER:UnregisterForEvent(self.name, EVENT_INVENTORY_SINGLE_SLOT_UPDATE)
    
    -- Kick off the next transaction
    StopStackingProcess()
        
    -- Now rescan and show/hide roomba button
    UI:GetNamedChild("Description"):SetText("Complete")
    UI:SetHidden(true)
    
    -- Perform another scan if an addon played with GuildBank while we restacking
    RoombaReady()

end

-- Trigger when  :
-- EVENT_GUILD_BANK_TRANSFER_ERROR
-- Called by itself
-- Called by OnGuildBankItemAdded (EVENT_GUILD_BANK_ITEM_ADDED)
local function ReturnItemsToBank(_, errorCode)
    
    local self = addon
    Debug("ReturnItemsToBank(_, " .. tostring(errorCode) .. ")")
    
    -- Protect for fast Escape while we restack
    if (not checkingBank) then
        StopGBRestackAndRestartScan()
        return
    end
    
    if errorCode == GUILD_BANK_NO_SPACE_LEFT then
    
        -- Stop. Guild Bank is full, User need to clean it manually        
        StopGBRestackAndRestartScan()
        return
    
    -- Can occur if an addon has destroyed our item while we were restacking
    elseif errorCode == GUILD_BANK_ITEM_NOT_FOUND then
        
        -- Need to move to next stack
        
        -- Let's try next try of the same item. Is there another stack to move?
        if next(lastRestackResult[itemIndex], slotIndex) then
            
            -- yes, try to move it
            slotIndex = slotIndex + 1
            
            Debug("zo_callLater(ReturnItemsToBank, " .. tostring(DELAY) .. "), slotIndex=" .. tostring(slotIndex) .. ", itemIndex=" .. tostring(itemIndex))
            zo_callLater(ReturnItemsToBank, DELAY)
            
        -- No more stack. Maybe another item?
        elseif next(lastRestackResult, itemIndex) then
            -- Yes, move its first stack
            itemIndex = itemIndex + 1
            slotIndex = 1
            
            Debug("zo_callLater(ReturnItemsToBank, " .. tostring(DELAY) .. "), slotIndex=1, itemIndex=" .. tostring(itemIndex))
            zo_callLater(ReturnItemsToBank, DELAY)
            
        else
            -- Nothing to move
            Debug("Nothing to move. Stop.")
            return
        end
    -- Can occur if an addon has destroyed our item while we were restacking
    elseif errorCode == GUILD_BANK_TRANSFER_PENDING then
        
        -- Retry to move the stack
        
        waitingRetries = waitingRetries + 1
        if waitingRetries < 10 then
            UI:GetNamedChild("Description"):SetText("Guild bank busy, trying to return restacked " .. cSlot.name .. " to the Guild Bank again")
            Debug("zo_callLater(ReturnItemsToBank, " .. tostring(DELAY * 5) .. "), slotIndex=" .. tostring(slotIndex) .. ", itemIndex=" .. tostring(itemIndex) .. ", waitingRetries=" .. tostring(waitingRetries))
            zo_callLater(ReturnItemsToBank, DELAY * 5) -- Should be long, Guild Bank can be busy for 3-5s quite often
        else
            StopGBRestackAndRestartScan()
        end
    elseif SHARED_INVENTORY:GenerateSingleSlotData(lastRestackResult[itemIndex][slotIndex].bagId, lastRestackResult[itemIndex][slotIndex].slotId) then
        UI:GetNamedChild("Description"):SetText("Returning restacked " .. cSlot.name .. " to the Guild Bank")
        TransferToGuildBank(lastRestackResult[itemIndex][slotIndex].bagId, lastRestackResult[itemIndex][slotIndex].slotId)
        Debug("TransferToGuildBank(" .. tostring(lastRestackResult[itemIndex][slotIndex].bagId) .. ", " .. tostring(lastRestackResult[itemIndex][slotIndex].slotId) .. ")")
        -- It will trigger .BankItemsReceived because of EVENT_GUILD_BANK_ITEM_ADDED
        -- It will trigger ReturnItemsToBank if an error has occured
    -- Another error
    elseif errorCode then
        Debug("No error code. Stop.")
        -- Not handled yet, stop
        return
    else
        -- It's a 3rd party addon push while we were restacking, or item has been destroyed
        Debug("Third party addon, or item destroyed. RestackGuildbank().")
        self.RestackGuildbank()
    end
    
end

local function RestackStackableBag(bagId, duplicateList)
    
    local result = {}
    local indexItemsDuplicated, dataItems = next(duplicateList)
    Debug("RestackStackableBag(" .. tostring(bagId) .. ", " .. tostring(duplicateList) .. ")")
    
    if bagId == BAG_BACKPACK then

        local restartAfter = false
        local itemIndex = 0
        
        -- Loop for item X/Y/Z
        while indexItemsDuplicated do
            
            local index = 1
            local itemInfo = dataItems[index]
            local baseSlot = nil
            local lastMoveWasSingleStack = false
            local lastMoveWasMultiStack = false
            result[indexItemsDuplicated] = {}
            
            -- Loop for item X and slots 1/2/3/y
            while itemInfo do
                
                -- 1st loop : we go in
                if not baseSlot then
                    -- Our actual stack / Our max size
                    baseSlot = itemInfo
                    baseSlot.actualStack, baseSlot.maxStack = GetSlotStackSize(bagId, itemInfo.slotId)
                else
                    
                    local qty
                    -- If stacking, will we get 1 or 2 stacks ?
                    itemInfo.maxStack = baseSlot.maxStack
                    
                    if (baseSlot.actualStack + itemInfo.stack) <= baseSlot.maxStack then
                        
                        -- Only 1 stack, we can merge stacks
                        qty = itemInfo.stack
                        
                        -- Merging
                        if IsProtectedFunction("RequestMoveItem") then
                            Debug("CallSecureProtected(\"RequestMoveItem\", " .. tostring(bagId) .. ", " .. tostring(itemInfo.slotId) .. ", " .. tostring(bagId) .. ", " .. tostring(baseSlot.slotId) .. ", " .. tostring(qty) .. ")")
                            CallSecureProtected("RequestMoveItem", bagId, itemInfo.slotId, bagId, baseSlot.slotId, qty)
                        else
                            Debug("RequestMoveItem(" .. tostring(bagId) .. ", " .. tostring(itemInfo.slotId) .. ", " .. tostring(bagId) .. ", " .. tostring(baseSlot.slotId) .. ", " .. tostring(qty) .. ")")
                            RequestMoveItem(bagId, itemInfo.slotId, bagId, baseSlot.slotId, qty)
                        end
                        
                        -- Update values baseSlot can still be used in next loop
                        baseSlot.actualStack = baseSlot.actualStack + itemInfo.stack
                        baseSlot.stack = baseSlot.actualStack
                        
                        if lastMoveWasMultiStack == true then
                            result[indexItemsDuplicated][#result[indexItemsDuplicated]] = baseSlot
                            lastMoveWasSingleStack = true
                            lastMoveWasMultiStack = false
                        elseif lastMoveWasSingleStack == true then
                            result[indexItemsDuplicated][#result[indexItemsDuplicated]] = baseSlot
                            lastMoveWasMultiStack = false
                        else
                            table.insert(result[indexItemsDuplicated], baseSlot)
                            lastMoveWasSingleStack = true
                            lastMoveWasMultiStack = false
                        end
                        
                    else
                        
                        -- It won't fit, just move the qty to match maxStack, no need to rescan because slots don't move, only stacks.
                        qty = baseSlot.maxStack - baseSlot.actualStack
                        
                        -- Merging
                        if IsProtectedFunction("RequestMoveItem") then
                            Debug("CallSecureProtected(\"RequestMoveItem\", " .. tostring(bagId) .. ", " .. tostring(itemInfo.slotId) .. ", " .. tostring(bagId) .. ", " .. tostring(baseSlot.slotId) .. ", " .. tostring(qty) .. ")")
                            CallSecureProtected("RequestMoveItem", bagId, itemInfo.slotId, bagId, baseSlot.slotId, qty)
                        else
                            Debug("RequestMoveItem(" .. tostring(bagId) .. ", " .. tostring(itemInfo.slotId) .. ", " .. tostring(bagId) .. ", " .. tostring(baseSlot.slotId) .. ", " .. tostring(qty) .. ")")
                            RequestMoveItem(bagId, itemInfo.slotId, bagId, baseSlot.slotId, qty)
                        end
                        
                        if lastMoveWasMultiStack == true then
                            result[indexItemsDuplicated][#result[indexItemsDuplicated]].stack = baseSlot.maxStack
                            result[indexItemsDuplicated][#result[indexItemsDuplicated]].actualStack = baseSlot.maxStack
                            table.insert(result[indexItemsDuplicated], itemInfo)
                            result[indexItemsDuplicated][#result[indexItemsDuplicated]].stack = itemInfo.stack - qty
                            result[indexItemsDuplicated][#result[indexItemsDuplicated]].actualStack = itemInfo.stack - qty
                            lastMoveWasSingleStack = false
                        elseif lastMoveWasSingleStack == true then
                            result[indexItemsDuplicated][#result[indexItemsDuplicated]].stack = baseSlot.maxStack
                            result[indexItemsDuplicated][#result[indexItemsDuplicated]].actualStack = baseSlot.maxStack
                            table.insert(result[indexItemsDuplicated], itemInfo)
                            result[indexItemsDuplicated][#result[indexItemsDuplicated]].stack = itemInfo.stack - qty
                            result[indexItemsDuplicated][#result[indexItemsDuplicated]].actualStack = itemInfo.stack - qty
                            lastMoveWasSingleStack = false
                            lastMoveWasMultiStack = true
                        else
                            table.insert(result[indexItemsDuplicated], baseSlot)
                            result[indexItemsDuplicated][#result[indexItemsDuplicated]].stack = baseSlot.maxStack
                            result[indexItemsDuplicated][#result[indexItemsDuplicated]].actualStack = baseSlot.maxStack
                            table.insert(result[indexItemsDuplicated], itemInfo)
                            result[indexItemsDuplicated][#result[indexItemsDuplicated]].stack = itemInfo.stack - qty
                            result[indexItemsDuplicated][#result[indexItemsDuplicated]].actualStack = itemInfo.stack - qty
                            lastMoveWasSingleStack = false
                            lastMoveWasMultiStack = true
                        end
                        
                        -- Baseslot is now at max, we cannot use it anymore
                        baseSlot = itemInfo
                        baseSlot.actualStack = itemInfo.stack - qty
                        
                    end
                    
                end
                
                index = index + 1
                itemInfo = dataItems[index]
            
            end
            
            itemIndex = itemIndex + 1
            indexItemsDuplicated, dataItems = next(duplicateList, itemIndex)
            
        end
    elseif bagId == BAG_VIRTUAL then
        
        result = {
            [1] = {}
        }
        
        local stack, maxStack = GetSlotStackSize(bagId, dataItems[1].slotId)
        local qtyToPush = qtyToMoveToGuildBank
        
        local pushBack = true
        while pushBack do
            
            local qtyToWrite
            if qtyToPush > maxStack then
                qtyToWrite = maxStack
                qtyToPush = qtyToPush - maxStack
            else
                qtyToWrite = qtyToPush
                pushBack = false
            end
            
            table.insert(result[1], {itemInstanceId = dataItems[1].itemInstanceId, slotId = dataItems[1].slotId, bagId = bagId, stack = qtyToWrite, texture = dataItems[1].texture, name = dataItems[1].name})
            
        end
        
    end
    
    return result
    
end

-- Triggers when EVENT_GUILD_BANK_ITEM_ADDED
local function OnGuildBankItemAdded(_, gslot)
    
    local self = addon
    Debug("OnGuildBankItemAdded(_, " .. tostring(gslot) .. ")")
    
    -- Roomba is restacking the guild bank
    -- Is the item added our last move ?
    -- Get its instanceID
    local id = GetItemInstanceId(BAG_GUILDBANK, gslot)
    
    -- Protection
    if id ~= lastRestackResult[itemIndex][slotIndex].itemInstanceId then return end
    
    --If we're here that's because it's our Roomba item which was sent in GuildBank
    -- Let's move the next stack
    -- Let's try next try of the same item. Is there another stack to move?
    
    if next(lastRestackResult[itemIndex], slotIndex) then
        
        -- yes, try to move it
        qtyToMoveToGuildBank = qtyToMoveToGuildBank - lastRestackResult[itemIndex][slotIndex].stack
        slotIndex = slotIndex + 1
        Debug("zo_callLater(ReturnItemsToBank, " .. tostring(DELAY) .. "), slotIndex=1, itemIndex=" .. tostring(itemIndex))
        zo_callLater(ReturnItemsToBank, DELAY)
        
    -- No more stack. Maybe another item? - Should not happen , because there is only 1 item in .lastRestackResult, the others items are in duplicates
    elseif next(lastRestackResult, itemIndex) then
    
        -- Yes, move its first stack
        itemIndex = itemIndex + 1
        slotIndex = 1
        qtyToMoveToGuildBank = 0
        Debug("zo_callLater(ReturnItemsToBank, " .. tostring(DELAY) .. "), slotIndex=1, itemIndex=" .. tostring(itemIndex))
        zo_callLater(ReturnItemsToBank, DELAY)
        
    else
    
        -- Nothing else to move for this item, let's do the rest
        qtyToMoveToGuildBank = 0
        Debug("RestackGuildbank()")
        self.RestackGuildbank()
        
    end
    
end

-- Triggers when EVENT_INVENTORY_SINGLE_SLOT_UPDATE
local function ReceiveItemInBagpack(_, bagId, slotId, _, _, _, stackCountChange)
    
    local self = addon
    Debug("ReceiveItemInBagpack(_, " .. tostring(bagId) .. ", " .. tostring(slotId) .. ", _, _, _, " .. tostring(stackCountChange) .. ")")
    
    -- Protection
    if (bagId == BAG_BACKPACK or bagId == BAG_VIRTUAL) and cItemDuplicateList then
    
        local id = GetItemInstanceId(bagId, slotId)
        
        -- Is slot really used?
        if not id then return end
        
        -- Is slot == our item transferred, avoid manual transfers interfer while we restack
        if id ~= cSlot.itemInstanceId then return end
        
        -- Set in wich bag/slot our stack is
        cSlot.bagId = bagId
        cSlot.slotId = slotId
        qtyToMoveToGuildBank = qtyToMoveToGuildBank + cSlot.stack
        
        -- Build an array for merging in backpack
        table.insert(inBagCollection, cSlot)
        
        -- If we have another slot to move from GuildBank
        if next(cItemDuplicateList, cSlotIdx) then
            
            cSlotIdx, cSlot = next(cItemDuplicateList, cSlotIdx)
            
            local duplicateId = GetItemInstanceId(BAG_GUILDBANK, cSlot.slotId)
            
            -- Is slot really used?
            if not duplicateId then
                StopGBRestackAndRestartScan()
                return
            end
            
            -- Is slot == our item transferred, avoid manual transfers interfer while we restack
            if duplicateId ~= cSlot.itemInstanceId then
                StopGBRestackAndRestartScan()
                return
            end
            
            -- The TransferFromGuildBank will execute ReceiveItemInBagpack because of registration
            Debug("TransferFromGuildBank(" .. tostring(cSlot.slotId) .. ")")
            TransferFromGuildBank(cSlot.slotId)
            
        else
            
            -- No more slots to move, let's stack them
            -- Disable ReceiveItemInBagpack, we've finished to transfer all stacks of same item
            EVENT_MANAGER:UnregisterForEvent(self.name, EVENT_INVENTORY_SINGLE_SLOT_UPDATE)
            
            UI:GetNamedChild("Description"):SetText("Stacking " .. cSlot.name .. " in inventory")
            
            -- restack items Add an array up to our array to cheat
            lastRestackResult = RestackStackableBag(bagId, {inBagCollection})
            
            -- These events will loop the move back to the guild bank
            -- This event is only here to "retry" if a return has fail
            EVENT_MANAGER:RegisterForEvent(self.name, EVENT_GUILD_BANK_TRANSFER_ERROR, ReturnItemsToBank)
            -- This event will triger the next transfer to bagpack?
            EVENT_MANAGER:RegisterForEvent(self.name, EVENT_GUILD_BANK_ITEM_ADDED, OnGuildBankItemAdded)
            
            -- This one is mandatory due to lags of SHARED_INVENTORY:GenerateFullSlotData
            Debug("zo_callLater(function() { ... }, " .. tostring(DELAY) .. ")")
            zo_callLater(function()
            
                --Init
                itemIndex = 1
                slotIndex = 1
                
                -- No errors, is our item here ?
                
                if lastRestackResult[itemIndex][slotIndex] and SHARED_INVENTORY:GenerateSingleSlotData(bagId, lastRestackResult[itemIndex][slotIndex].slotId) and UI and UI:GetNamedChild("Description") and cSlot then
                    UI:GetNamedChild("Description"):SetText("Returning restacked " .. cSlot.name .. " to the Guild Bank")
                    Debug("TransferToGuildBank(" .. tostring(bagId) .. ", " .. tostring(lastRestackResult[itemIndex][slotIndex].slotId) .. ")")
                    TransferToGuildBank(bagId, lastRestackResult[itemIndex][slotIndex].slotId)
                    -- It will trigger OnGuildBankItemAdded because of EVENT_GUILD_BANK_ITEM_ADDED
                    -- It will trigger ReturnItemsToBank if an error has occured
                end
            end, DELAY)
            
        end
    end
    
end

-- Restack the bank. This function is voluntary leaked to global due to an internal loop in the addon code
function addon.RestackGuildbank()
    
    local self = addon
    Debug("RestackGuildbank()")

    -- Protect
    if (not checkingBank) then return end
    
    -- 5 slots Needed to Work
    if not CheckInventorySpaceAndWarn(5) then return end
    
    -- Resetted after each restack / each bank swap
    if not cInstanceId then
        checkingBank = false
        RoombaReady()
        checkingBank = true
    end
    
    -- Pull the next job off the stack
    cInstanceId, cItemDuplicateList = next(duplicates, cInstanceId)
    
    -- Protect against Keybind
    if cInstanceId then currentRun[cInstanceId] = true end
    
    qtyToMoveToGuildBank = 0
    
    -- They are some duplicates .cItemDuplicateList is an array of multiple stacks of same item
    if cItemDuplicateList then
        
        -- Flag for other addons
        restackInProgress = true
        
        -- Show progress Bar, etc.
        UI:SetHidden(false)
        local index = NonContiguousCount(currentRun)
        local total = NonContiguousCount(duplicates)
        ZO_StatusBar_SmoothTransition(UI:GetNamedChild("SpeedRow").bar, index , total, FORCE_VALUE)
        UI:GetNamedChild("SpeedRow").value:SetText(string.format("%3d", (index / total) * 100) .. "%")
        UI:GetNamedChild("SpeedRow").value:SetWidth(90)
        UI:GetNamedChild("SpeedRow").value:SetHidden(false)
        
        -- Init
        cSlotIdx = 1
        
        -- 1st stack
        cSlot = cItemDuplicateList[cSlotIdx]
        
        -- cSlot is the slot to get from GuildBank
        UI:GetNamedChild("Icon"):SetTexture(cSlot.texture)
        
        -- Init what's actually in our bagpack
        inBagCollection = {}
        
        -- If it suddenly doesn't exist, try the next in the list (can be caused by addons which autodestroy or other transfering utilities).
        if not SHARED_INVENTORY:GenerateSingleSlotData(BAG_GUILDBANK, cSlot.slotId) then zo_callLater(self.RestackGuildbank, DELAY) end
        
        -- Will trigger the function when TransferFromGuildBank will be executed
        EVENT_MANAGER:RegisterForEvent(self.name, EVENT_INVENTORY_SINGLE_SLOT_UPDATE, ReceiveItemInBagpack)
        
        UI:GetNamedChild("Description"):SetText("Retrieving " .. cSlot.name .. " from Guild Bank")
        
        -- Take a stack from bank, it will trigger ReceiveItemInBagpack
        Debug("TransferFromGuildBank(" .. tostring(cSlot.slotId) .. ")")
        TransferFromGuildBank(cSlot.slotId)
        
    else
        StopGBRestackAndRestartScan()
    end
    
end

local function BagNeedRestack()

    -- Protect
    if SCENE_MANAGER and SCENE_MANAGER:GetCurrentScene() then
        if (not (SCENE_MANAGER:GetCurrentScene():GetName() == "guildBank" or SCENE_MANAGER:GetCurrentScene():GetName() == "gamepad_guild_bank")) then
            return false
        end
    end
    
    if #duplicates >= 1 then
        return true
    end

end

local function BeginStackingProcess()

    local self = addon
    
    -- What function to use ? depends on the scene
    if (SCENE_MANAGER:GetCurrentScene():GetName() == "guildBank" or SCENE_MANAGER:GetCurrentScene():GetName() == "gamepad_guild_bank") and db.RoombaAtGBank then
        -- Rescan first
        RoombaReady()
        -- Restack GuildBank
        self.RestackGuildbank()
    end

end

-- For Compatibility, can be called by other addons
addon.BeginStackingProcess = BeginStackingProcess

local function BeginScanningProcess()

    if (SCENE_MANAGER:GetCurrentScene():GetName() == "guildBank" or SCENE_MANAGER:GetCurrentScene():GetName() == "gamepad_guild_bank") and db.RoombaAtGBank then
        RoombaReady()
    end
    
end

local function SelectGuildBank(_, guildBankId)
    
    -- Reset flag for bank switch
    checkingBank = false
    currentBank = guildBankId
    StopStackingProcess()
    
end

local function OnGuildBankReallyReady()
    Debug("OnGuildBankReallyReady()")

    -- Limit calls to RoombaReady()
    if not checkingBank then
        
        if IsInGamepadPreferredMode() then
            UI = RoombaWindowGamepad
        else
            UI = RoombaWindow
        end
        
        checkingBank = true
        RoombaReady()
    end
    
end

local function OnGuildBankReady()
    -- Guild bank is evented to be ready, but wait a short while before processing. (multiple readys for big banks ~3/4)
    zo_callLater(function() OnGuildBankReallyReady() end, 1700)
end

local function OnCloseGuildBank()
  
    local self = addon
  
    if db.RoombaAtGBank then
        
        if KEYBIND_STRIP:HasKeybindButtonGroup(keybindDescriptor) then
            KEYBIND_STRIP:RemoveKeybindButtonGroup(keybindDescriptor) 
        end
        
        if UI then
            UI:SetHidden(true)
        end
        
        StopStackingProcess()
        
        EVENT_MANAGER:UnregisterForEvent(self.name, EVENT_GUILD_BANK_ITEMS_READY)
        EVENT_MANAGER:UnregisterForEvent(self.name, EVENT_GUILD_BANK_SELECTED)        
        EVENT_MANAGER:UnregisterForEvent(self.name, EVENT_INVENTORY_SINGLE_SLOT_UPDATE)
        EVENT_MANAGER:UnregisterForEvent(self.name, EVENT_GUILD_BANK_TRANSFER_ERROR)
        EVENT_MANAGER:UnregisterForEvent(self.name, EVENT_GUILD_BANK_ITEM_ADDED)
        checkingBank = false
        
    end
end

local function OnOpenGuildBank()
    local self = addon
    if db.RoombaAtGBank then
        EVENT_MANAGER:RegisterForEvent(self.name, EVENT_GUILD_BANK_ITEMS_READY, OnGuildBankReady)
        -- Clear the flag when swapping banks
        EVENT_MANAGER:RegisterForEvent(self.name, EVENT_GUILD_BANK_SELECTED, SelectGuildBank)
    end
end

local function UpdateAndDisplayKeybind()

    -- We can't "really" update a keybind name dynamically while using "name = function() .. end" so we use the "visible" one.
    
    if BagNeedRestack() then
        descriptorName = GetString(SI_BINDING_NAME_RUN_ROOMBA) 
    else
        
        if SCENE_MANAGER and SCENE_MANAGER:GetCurrentScene() then
            local scene = SCENE_MANAGER:GetCurrentScene():GetName()
            if scene == "guildBank" or "gamepad_guild_bank" then
                descriptorName = GetString(ROOMBA_RESCAN_BANK)
            end
        end
        
    end

    local scene = SCENE_MANAGER:GetCurrentScene():GetName()
    if scene == "guildBank" or scene == "gamepad_guild_bank" then
        return true
    else
        return false
    end

end

local function InitializeKeybind()

    keybindDescriptor = { 
        alignment = db.RoombaPosition,
        [keyBindIndex] = {
            name = function() return descriptorName end,
            keybind = "RUN_ROOMBA",
            control = self,
            callback = Roomba_StartRoomba, 
            visible = UpdateAndDisplayKeybind, 
            icon = [[Roomba\media\RoombaSearch.dds]],
        },
    }
    
end

local function InitializeSpeedRow(control)
    
    control:SetDrawLayer(DL_OVERLAY)
    control:GetNamedChild("SpeedRow").value:SetText(" 0%")
    
    ZO_StatusBar_SetGradientColor(control:GetNamedChild("SpeedRow").bar, ZO_XP_BAR_GRADIENT_COLORS)
    ZO_StatusBar_SmoothTransition(control:GetNamedChild("SpeedRow").bar, 0, 20, FORCE_VALUE)
    
    control:GetNamedChild("SpeedRow"):GetNamedChild("Icon"):SetHidden(true)
    control:GetNamedChild("SpeedRow"):GetNamedChild("BarContainer"):ClearAnchors()
    control:GetNamedChild("SpeedRow"):GetNamedChild("BarContainer"):SetAnchor(BOTTOM, control:GetNamedChild("Icon"), BOTTOM, 30, 70)
    
    control:GetNamedChild("SpeedRow").value:SetFont("ZoFontHeader3")
    
end

local function InitialiseSettings()

    local self = addon

    -- Fetch the saved variables
    db = LibSavedVars:NewAccountWide(self.name .. "_Account", defaults)
                     :AddCharacterSettingsToggle(self.name .. "_Character")
    
    if LSV_Data.EnableDefaultsTrimming then
        db:EnableDefaultsTrimming()
    end
    
    if db.RoombaPosition == KEYBIND_STRIP_ALIGN_LEFT then
        keybindCheck = "leftButtons"
    elseif db.RoombaPosition == KEYBIND_STRIP_ALIGN_RIGHT then
        keybindCheck = "rightButtons"
    elseif db.RoombaPosition == KEYBIND_STRIP_ALIGN_CENTER then
        keybindCheck = "centerButtons"
    end
    
    local panelData = {
        type = "panel",
        name = self.name,
        displayName = self.name,
        author = self.author,
        version = self.version,
        slashCommand = "/roomba",
        registerForRefresh = true,
        registerForDefaults = true,
        website = self.website,
    }
    
    local LAM = LibAddonMenu2 or LibStub("LibAddonMenu-2.0")
    LAM:RegisterAddonPanel("RoombaOptions", panelData)
    
    local optionsTable = {
        
        -- Account-wide settings
        db:GetLibAddonMenuAccountCheckbox(),
        
        {
            type = "checkbox",
            name = GetString(ROOMBA_GBANK),
            tooltip = GetString(ROOMBA_GBANK_TOOLTIP),
            getFunc = function() return db.RoombaAtGBank end,
            setFunc = function(newValue) db.RoombaAtGBank = newValue end,
            default = defaults.RoombaAtGBank,
        },
        {
            type = "dropdown",
            name = GetString(ROOMBA_POSITION),
            tooltip = GetString(ROOMBA_POSITION_TOOLTIP),
            choices = {
                GetString("ROOMBA_POSITION_CHOICE", KEYBIND_STRIP_ALIGN_LEFT),
                GetString("ROOMBA_POSITION_CHOICE", KEYBIND_STRIP_ALIGN_CENTER),
                GetString("ROOMBA_POSITION_CHOICE", KEYBIND_STRIP_ALIGN_RIGHT),
            },
            default = defaults.RoombaPosition,
            warning = GetString(SI_ADDON_MANAGER_RELOAD),
            getFunc = function() return GetString("ROOMBA_POSITION_CHOICE", db.RoombaPosition) end,
            setFunc = function(choice)
                if choice == GetString("ROOMBA_POSITION_CHOICE", KEYBIND_STRIP_ALIGN_LEFT) then
                    db.RoombaPosition = KEYBIND_STRIP_ALIGN_LEFT
                    keybindCheck = "leftButtons"
                elseif choice == GetString("ROOMBA_POSITION_CHOICE", KEYBIND_STRIP_ALIGN_RIGHT) then
                    db.RoombaPosition = KEYBIND_STRIP_ALIGN_RIGHT
                    keybindCheck = "rightButtons"
                elseif choice == GetString("ROOMBA_POSITION_CHOICE", KEYBIND_STRIP_ALIGN_CENTER) then
                    db.RoombaPosition = KEYBIND_STRIP_ALIGN_CENTER
                    keybindCheck = "centerButtons"
                elseif IsInGamepadPreferredMode() then
                    -- When user click on LAM reinit button
                    db.RoombaPosition = defaults.RoombaPosition
                    keybindCheck = "centerButtons"
                else
                -- When user click on LAM reinit button
                    db.RoombaPosition = defaults.RoombaPosition
                    keybindCheck = "leftButtons"
                end
                
                ReloadUI()
                
            end,
        },
    }
    
    LAM:RegisterOptionControls("RoombaOptions", optionsTable)
    
end

-- Called by Bindings
function Roomba_StartRoomba()

    if BagNeedRestack() then
        BeginStackingProcess()
    else
        BeginScanningProcess()
    end

end

-- Don't spam this function, GetNumBagFreeSlots & FindFirstEmptySlotInBag are slow to update (wait for Guild Bank event before using it twice)
-- This function accept qtyToMoveToGuildBank leaked to local or global namespace.
-- It's the qty to move from BAG_VIRTUAL. if not provided, math.min(stackCount, maxStack) is pushed
local function PreHookTransferToGuildBank()

    -- Bug sometimes, so let's use the backpack for every move
    local original_TransferToGuildBank = TransferToGuildBank
    local function TransferToGuildBankByBackpack(sourceBag, slotIndex)
      
        if IsGuildBankOpen() and sourceBag == BAG_VIRTUAL then
            Debug("TransferToGuildBankByBackpack(" .. tostring(sourceBag) .. ", " .. tostring(slotIndex) .. ")")
            if GetNumBagFreeSlots(BAG_BACKPACK) >= 1 and GetNumBagFreeSlots(BAG_GUILDBANK) >= 1 then
                local proxySlot = FindFirstEmptySlotInBag(BAG_BACKPACK)
                local stack, maxStack = GetSlotStackSize(sourceBag, slotIndex)
                local qtyTuPush = qtyToMoveToGuildBank or 0 -- Var can be nil
                qtyTuPush = math.min(stack, maxStack, qtyTuPush) -- qtyToMoveToGuildBank > maxStack too. Avoid this.
                
                if IsProtectedFunction("RequestMoveItem") then
                    Debug("CallSecureProtected(\"RequestMoveItem\", " .. tostring(sourceBag) .. ", " .. tostring(slotIndex) .. ", " .. tostring(BAG_BACKPACK) .. ", " .. tostring(proxySlot) .. ", " .. tostring(qtyTuPush) .. ")")
                    CallSecureProtected("RequestMoveItem", sourceBag, slotIndex, BAG_BACKPACK, proxySlot, qtyTuPush)
                else
                    Debug("RequestMoveItem(" .. tostring(sourceBag) .. ", " .. tostring(slotIndex) .. ", " .. tostring(BAG_BACKPACK) .. ", " .. tostring(proxySlot) .. ", " .. tostring(qtyTuPush) .. ")")
                    RequestMoveItem(sourceBag, slotIndex, BAG_BACKPACK, proxySlot, qtyTuPush)
                end
                
                original_TransferToGuildBank(BAG_BACKPACK, proxySlot)
                
                return true
            
            end
        end
    end

    ZO_PreHook("TransferToGuildBank", TransferToGuildBankByBackpack)

end

local function OnAddonLoaded(_, addOnName)
    
    local self = addon
    
    if addOnName == self.name then
    
        if IsInGamepadPreferredMode() then
            defaults.RoombaPosition = KEYBIND_STRIP_ALIGN_CENTER
        end
        
        ZO_CreateStringId("SI_BINDING_NAME_RUN_ROOMBA", descriptorName)
        
        InitializeSpeedRow(RoombaWindow)
        InitializeSpeedRow(RoombaWindowGamepad)
        
        InitialiseSettings()
        InitializeKeybind()
        
        PreHookTransferToGuildBank()
        
        -- Set the function to run when guild bank is opened (before guild bank is ready)
        EVENT_MANAGER:RegisterForEvent(self.name, EVENT_OPEN_GUILD_BANK, OnOpenGuildBank)
        
        -- Set the function to run when guild bank is closed
        EVENT_MANAGER:RegisterForEvent(self.name, EVENT_CLOSE_GUILD_BANK, OnCloseGuildBank)
    end
    
end

EVENT_MANAGER:RegisterForEvent(addon.name, EVENT_ADD_ON_LOADED, OnAddonLoaded)