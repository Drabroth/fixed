-- AutoLootBody compatibility build
-- Loot categories:
--   LootBody        = dead monsters
--   LootBodyPart    = monster body parts
--   LootGm82_000_001= dropped items
--   LootGm82_000    = non-drop/world items
--   LootGm82_009    = gather spots
--   LootGm82_036    = Seeker's Tokens
--   LootGm80_001    = chests
-- Includes live range refresh, safe pcall wrappers, and InteractManager-based gimmick processing.

local modname="AutoLootBody"
local configfile=modname..".json"
local myapi = require("_XYZApi/_XYZApi")
local _config={
    {name="Loot Settings",type="mutualbox"},
    {name="range",type="int",default=30,label="Loot Range"},
    {name="lootBody",type="bool",default=true,label="Loot Body"},
    {name="lootBodyPart",type="bool",default=true,label="Loot Body Part"},
    {name="lootDropItem",type="bool",default=true,label="Loot Drop Item"},
    {name="lootDirectItem",type="bool",default=true,label="Loot Non-Drop Item"},
    {name="lootGatherSpot",type="bool",default=true,label="Loot Gather Point"},
    {name="lootSeekerToken",type="bool",default=false,label="Loot Seeker's Token"},
    {name="lootChest",type="bool",default=false,label="Loot Chest"},

    {name="disableOnBattle",type="bool",default=false,label="Disable During Battle"},

    {name="Loot Message Settings",type="mutualbox"},
    {name="showLootMessage",type="bool",default=true},
    {name="messageFontsize",type="fontsize",default=30},
}  
local myapi = require("_XYZApi/_XYZApi")
local config= myapi.InitFromFile(_config,configfile)
local msgTime=120
local posDelta=2/(msgTime)
local colorDelta=math.floor(0xff000000/msgTime)&0xff000000
local rangeSq=config.range*config.range

local mainplayer=nil -- 暂时弃用
local waitingBodyControllerList={}
local lootMessageList={}
local gimmickManager = sdk.get_managed_singleton("app.GimmickManager")
local battleManager = sdk.get_managed_singleton("app.BattleManager")
local playerManager=sdk.get_managed_singleton("app.CharacterManager")

local font = imgui.load_font("times.ttf", config.messageFontsize)

local function Log(...)
    print(...)
    for k,v in ipairs{...} do
        log.info("["..modname.."]"..tostring(v))
    end
end

local function refreshplayer()
    playerManager = sdk.get_managed_singleton("app.CharacterManager")
    gimmickManager = sdk.get_managed_singleton("app.GimmickManager")
    battleManager = sdk.get_managed_singleton("app.BattleManager")

    if playerManager ~= nil then
        mainplayer = playerManager:get_ManualPlayer()
    else
        mainplayer = nil
    end
end
sdk.hook(sdk.find_type_definition("app.GuiManager"):get_method("OnChangeSceneType"),nil,
function ()
    refreshplayer()
    waitingBodyControllerList={}
    lootMessageList={}
end
)
refreshplayer()


-- local function getCharacterPos(char)
--     local joint=char:get_GameObject():get_Transform():getJointByName("Head_0")
--     local ground_joint=char:get_GameObject():get_Transform():getJointByName("root")
--     -- no head enemy
--     if joint == nil then
--         return ground_joint:get_Position()
--     end
--     --if head is too tall from ground, return the ground
--     if joint:get_Position().y - ground_joint:get_Position().y >2 then
--         return ground_joint:get_Position()
--     end
--     return joint:get_Position()
-- end

local function getCharacterPos(char)
    local ok, result = pcall(function()
        if char == nil or not sdk.is_managed_object(char) then
            return nil
        end

        local gameObject = char:get_GameObject()
        if gameObject == nil then
            return nil
        end

        local transform = gameObject:get_Transform()
        if transform == nil then
            return nil
        end

        local ground_joint = nil
        local okRoot, rootResult = pcall(function()
            return transform:getJointByName("root")
        end)

        if okRoot then
            ground_joint = rootResult
        end

        local head_joint = nil
        local okHead, headResult = pcall(function()
            return transform:getJointByName("Head_0")
        end)

        if okHead then
            head_joint = headResult
        end

        if ground_joint == nil then
            local okPos, pos = pcall(function()
                return transform:get_Position()
            end)

            if okPos then
                return pos
            end

            return nil
        end

        if head_joint == nil then
            return ground_joint:get_Position()
        end

        local headPos = head_joint:get_Position()
        local groundPos = ground_joint:get_Position()

        if headPos.y - groundPos.y > 2 then
            return groundPos
        end

        return headPos
    end)

    if ok then
        return result
    end

    Log("getCharacterPos exception:", result)
    return nil
end

local function AddMessage(msg,pos)
    Log("Add Message:",msg)
    if config.showLootMessage then
        local lootMsg={
            msg=msg,
            pos=pos,
            color=0xffeeeeee
        }
        lootMessageList[lootMsg]=msgTime
    end
end

-- local function DistanceSq(r)
--     -- mainplayer会失效?
--     local player = playerManager:get_ManualPlayer()
--     if player == nil or player:get_GameObject() == nil then 
--         return 0
--     end
--     local l = player:get_GameObject():get_Transform():getJointByName("root"):get_Position()
--     return (l.x-r.x)*(l.x-r.x)
--            +(l.y-r.y)*(l.y-r.y)
--            +(l.z-r.z)*(l.z-r.z)
-- end

local function DistanceSq(r)
    if r == nil then
        return 0
    end

    local ok, distance = pcall(function()
        local player = playerManager:get_ManualPlayer()

        if player == nil or not sdk.is_managed_object(player) then
            return 0
        end

        local gameObject = player:get_GameObject()
        if gameObject == nil then
            return 0
        end

        local transform = gameObject:get_Transform()
        if transform == nil then
            return 0
        end

        -- Gebruik de positie van de player transform direct.
        -- Geen root-joint nodig.
        local l = transform:get_Position()

        if l == nil then
            return 0
        end

        return (l.x-r.x)*(l.x-r.x)
             + (l.y-r.y)*(l.y-r.y)
             + (l.z-r.z)*(l.z-r.z)
    end)

    if ok and distance ~= nil then
        return distance
    end

    Log("DistanceSq exception:", distance)
    return 0
end

-- interactiveObject:getDistanceSqFromPlayer calc only x-z distance，same as gimmick:get_DistanceXZSqFromPlayer
local function DistanceSqGimmick(gimmick)
    if gimmick == nil or not sdk.is_managed_object(gimmick) then
        return 0
    end

    local ok, distance = pcall(function()
        local gameObject = gimmick:get_GameObject()
        if gameObject == nil then
            return 0
        end

        local transform = gameObject:get_Transform()
        if transform == nil then
            return 0
        end

        local pos = transform:get_Position()
        if pos == nil then
            return 0
        end

        return DistanceSq(pos)
    end)

    if ok and distance ~= nil then
        return distance
    end

    Log("DistanceSqGimmick ERROR", distance)
    return 0
end

-- getDistanceSqFromPlayer for bodies(or maybe for everything) could also be 0.0,meaning invalid.
-- seems it has a cache system.
local function LootBody(deadBodyController)
    if deadBodyController==nil or (not sdk.is_managed_object(deadBodyController)) or deadBodyController:get_IsEnablePickup()==false then
        waitingBodyControllerList[deadBodyController]=nil
        return
    end
    
    local distance=deadBodyController.InteractiveObject:getDistanceSqFromPlayer(0)
    -- havn't found a way to calc x-y-z distance
    -- local p = deadBodyController.InteractiveObject.Works._items[0].ParentJoint:get_Position()
    if distance~=0.0 and distance<rangeSq then
        -- local pos=getCharacterPos(deadBodyController.Chara)
        local pos = getCharacterPos(deadBodyController.Chara)

        if pos == nil then
            waitingBodyControllerList[deadBodyController] = nil
            return
        end

        local ct=0

        --限制最大尝试次数，防止超过堆叠上限时不停冒无法获得道具的提示
        local maxNum = 1

        if deadBodyController.GatherContext ~= nil
            and deadBodyController.GatherContext._Num ~= nil then
            maxNum = deadBodyController.GatherContext._Num
        end
        if deadBodyController.ItemDropInfo ~= nil then
            local lotlist = deadBodyController.ItemDropInfo._LotList

            if lotlist ~= nil then
                local okCount, count = pcall(function()
                    return lotlist:get_Count()
                end)

                if okCount and count ~= nil then
                    for i = 0, count - 1 do
                        local okItem, lotItem = pcall(function()
                            return lotlist[i]
                        end)

                        if okItem and lotItem ~= nil and lotItem._Num ~= nil then
                            if maxNum < lotItem._Num then
                                maxNum = lotItem._Num
                            end
                        end
                    end
                end
            end
        end
        Log("Start Loot",maxNum)
        --Log("--",deadBodyController.GatherContext._Num,distance,deadBodyController:get_IsDropItemPickuped(),deadBodyController:get_IsDisableInteract(),deadBodyController:isDead(),deadBodyController:isInteractEnable(0),deadBodyController.Chara:get_CharaIDString())
        --item over 99 will be gone and consume loot chance sometimes? but not consumeing loot chance sometimes?

	    while deadBodyController:get_IsEnablePickup()==true and deadBodyController:isInteractEnable(0) and ct<50 and ct<maxNum do --prevent infinite loop,shouldn't happen?
    		deadBodyController:executeInteract(0, playerManager:get_ManualPlayer())
		    ct=ct+1
            --break
	    end

        AddMessage("Loot "..ct,pos)
        waitingBodyControllerList[deadBodyController]=nil
    end
end




local function LootBodyPart(dropPartsController)
    --don't use dropPartsController:get_DropWork():get_IsInteractEnable() 
    if dropPartsController==nil 
        or (not sdk.is_managed_object(dropPartsController)) 
        -- interactiveObject could be nil
        or (not dropPartsController:get_DropObject()) 
        or (not dropPartsController:get__DropPartsContext()) then
        waitingBodyControllerList[dropPartsController]=nil
        return
    end
    
    local interObject=dropPartsController:get_DropObject()

    if dropPartsController.PartsRoot==nil then
        waitingBodyControllerList[dropPartsController]=nil
        return
    end

    --getDistanceSqFromPlayer for some tails is 0,why?
    --local context=dropPartsController:get__DropPartsContext()
    -- context:get_Pos() is via.Positon, joint:get_Position() is via.vec3 ,can't minus; context:get_pos returns strange position
    --local disvec=mainplayer:get_GameObject():get_Transform():getJointByName("root"):get_Position() - dropPartsController.PartsRoot:get_Position()
    --local distance=DistanceSq(mainplayer:get_GameObject():get_Transform():getJointByName("root"):get_Position(),context:get_Pos())
    local distance=DistanceSq(dropPartsController.PartsRoot:get_Position())

    --Log("2",distance,dropPartsController:getDropItemData().Item1,dropPartsController:getDropItemData().Item2,interObject:getDistanceSqFromPlayer(0),
    --    dropPartsController["<IsDropSetup>k__BackingField"],
    --    "--",dropPartsController.PartsRoot)

    if  distance~=0.0 and distance<rangeSq then
        --dropPartsController:startInteract(0,mainplayer)
        --Log("3",distance,dropPartsController:getDropItemData().Item1,dropPartsController:getDropItemData().Item2,interObject:getDistanceSqFromPlayer(0),
        --    interObject:getInteractPointPosition(0).x,interObject:getInteractPointPosition(0).y,interObject:getInteractPointPosition(0).z,
        --    interObject:get_NumInteractPoints())
        local pos=interObject:getInteractPointPosition(0)
        local ct=0

        --DropItemData：<id,num>
        local maxNum=dropPartsController:getDropItemData().Item2
        --local dropItems=dropPartsController.DropPartsData:get_DropItems()
        --local maxNum=context:get_ItemNum()

        Log("Start Loot Body Part",maxNum)
        --interObject:isInteractEnable(0) returns false
	    while ct<20 and ct<maxNum do
    		    dropPartsController:executeInteract(0, playerManager:get_ManualPlayer())
		    ct=ct+1
            --break
	    end
        --executeInteract不会让尾巴变为不可loot状态，不管调用多少次，每次都会获得一个物品，最后尾巴还可以正常loot一次才消失
        --需要调用unregisterInteractiveObject才能让尾巴结束可loot状态，但是如果一次都没调用executeInteract，unregisterInteractiveObject不会生效？
        if maxNum>0 then
            dropPartsController:unregisterInteractiveObject()
        end
        AddMessage("Loot "..ct,pos)
        waitingBodyControllerList[dropPartsController]=nil
    end
end

local function LootBodyOrBodyPart(controller)
    if controller:get_type_definition():is_a("app.DropPartsController") then
        LootBodyPart(controller)
    elseif controller:get_type_definition():is_a("app.SearchDeadBodyInteractController") then
        LootBody(controller)
    else
        waitingBodyControllerList[controller]=nil
    end
    --If a controller is not removed after call `loot`,means it's not in loot range.Increase the ct to delete trash datas.
    if waitingBodyControllerList[controller]~=nil then
        waitingBodyControllerList[controller] = waitingBodyControllerList[controller]-1
        if waitingBodyControllerList[controller] < -7200 then
            waitingBodyControllerList[controller]=nil  
        end
    end
end

-- local function LootGm82_009(gimmick)
--     if gimmick:isInteractEnable(0)==true then
--         --gimmick:get_DistanceXZSqFromPlayer and FarDistanceSq/NearDistanceSq for some gimmick are fix value 
--         --GM82_009_10 will trigger repeatly and distance is always 0.0
--         local distance=DistanceSqGimmick(gimmick) -- gimmick.InteractiveObject:getDistanceSqFromPlayer(0)
--         --local distance2=gimmick:get_DistanceXZSqFromPlayer()
--         --treat 0.0 disatance as invalid
--         if distance~=0.0 and distance<rangeSq then
--             --call StartInteract only causes pickup action
--             Log("Loot Gimmick82_009",distance)
--             gimmick:onExecuteInteractBase(0, playerManager:get_ManualPlayer())
--             AddMessage("Loot 1",gimmick:get_GameObject():get_Transform():get_Position())
--         end
--     end
-- end

local function LootGm82_009(gimmick)
    if gimmick == nil or not sdk.is_managed_object(gimmick) then
        return
    end

    local ok, err = pcall(function()
        if gimmick:isInteractEnable(0) ~= true then
            return
        end

        local distance = DistanceSqGimmick(gimmick)

        Log("GATHER",
            "distance", distance,
            "enabled", gimmick:isInteractEnable(0)
        )

        if distance == 0.0 or distance >= rangeSq then
            return
        end

        local player = playerManager:get_ManualPlayer()
        if player == nil then
            return
        end

        local ok1, err1 = pcall(function()
            gimmick:onExecuteInteractBase(0, player)
        end)

        Log("onExecuteInteractBase", ok1, err1)

        if not ok1 then
            local ok2, err2 = pcall(function()
                gimmick:requestForceInteract(0, player)
            end)

            Log("requestForceInteract", ok2, err2)
        end
    end)

    if not ok then
        Log("LootGm82_009 ERROR", err)
    end
end

--丢弃的物品和怪物掉落的物品
local function LootGm82_000_001(gimmick)
    if gimmick == nil or not sdk.is_managed_object(gimmick) then
        return false
    end

    local ok, result = pcall(function()
        if gimmick:isInteractEnable(0) ~= true then
            return false
        end

        local distance = DistanceSqGimmick(gimmick)

        local itemId = nil
        local itemNum = nil
        pcall(function() itemId = gimmick:getItemId() end)
        pcall(function() itemNum = gimmick:getItemNum() end)

        Log("DROP ITEM",
            "distance", distance,
            "item", itemId,
            "num", itemNum
        )

        if distance == 0.0 or distance >= rangeSq then
            return false
        end

        local player = playerManager:get_ManualPlayer()
        if player == nil then
            return false
        end

        local methods = {
            {"onStartInteractBase", function()
                gimmick:onStartInteractBase(0, player)
            end},
            {"requestForceInteract", function()
                gimmick:requestForceInteract(0, player)
            end},
            {"onExecuteInteractBase", function()
                gimmick:onExecuteInteractBase(0, player)
            end},
            {"onEndInteractBase", function()
                gimmick:onEndInteractBase(0, player)
            end}
        }

        local workedAny = false

        for i, entry in ipairs(methods) do
            local worked, err = pcall(entry[2])
            Log("DROP METHOD", i, entry[1], worked, err)

            if worked then
                workedAny = true
                break
            end
        end

        if not workedAny then
            return false
        end

        local pos = nil
        pcall(function()
            pos = gimmick:get_GameObject():get_Transform():get_Position()
        end)

        if pos ~= nil then
            AddMessage("Loot "..tostring(itemNum or 1), pos)
        end

        return true
    end)

    if not ok then
        Log("LootGm82_000_001 ERROR", result)
        return false
    end

    return result
end

--本来就在地图上的物品
--not include seeker's token:82_036
-- local function LootGm82_000(gimmick)
--     if gimmick:isInteractEnable(0)==true then
--         local distance = DistanceSqGimmick(gimmick) --gimmick.InteractiveObject:getDistanceSqFromPlayer(0)
--         --treat 0.0 disatance as invalid
--         if distance~=0.0 and distance<rangeSq then
--             Log("Loot Gimmick82_000",distance,gimmick:getItemId(),gimmick:getItemNum())
--             local msg="Loot "..gimmick:getItemNum() -- num became 0 after interact
--             --gimmick:onStartInteractBase(0,mainplayer)
--             --gimmick:onExecuteInteractBase(0,mainplayer)
--             --gimmick:onEndInteractBase(0,mainplayer)
--             --gimmick:endInteract(0)
--             --only this works,but each frame only work for one item?
--             gimmick:requestForceInteract(0, playerManager:get_ManualPlayer())
--             AddMessage(msg,gimmick:get_GameObject():get_Transform():get_Position())
--             return true
--         end
--     end
--     return false
-- end

local function LootGm82_000(gimmick)
    if gimmick == nil or not sdk.is_managed_object(gimmick) then
        return false
    end

    local ok, result = pcall(function()
        if gimmick:isInteractEnable(0) ~= true then
            return false
        end

        local distance = DistanceSqGimmick(gimmick)

        Log("DIRECT ITEM",
            "distance", distance,
            "item", gimmick:getItemId(),
            "num", gimmick:getItemNum()
        )

        if distance == 0.0 or distance >= rangeSq then
            return false
        end

        local player = playerManager:get_ManualPlayer()
        if player == nil then
            return false
        end

        local methods = {
            {"requestForceInteract", function()
                gimmick:requestForceInteract(0, player)
            end},
            {"onStartInteractBase", function()
                gimmick:onStartInteractBase(0, player)
            end},
            {"onExecuteInteractBase", function()
                gimmick:onExecuteInteractBase(0, player)
            end},
            {"onEndInteractBase", function()
                gimmick:onEndInteractBase(0, player)
            end}
        }

        for i, entry in ipairs(methods) do
            local worked, err = pcall(entry[2])
            Log("DIRECT METHOD", i, entry[1], worked, err)

            if worked then
                local pos = nil
                pcall(function()
                    pos = gimmick:get_GameObject():get_Transform():get_Position()
                end)

                if pos ~= nil then
                    AddMessage("Loot "..tostring(gimmick:getItemNum()), pos)
                end

                return true
            end
        end

        return false
    end)

    if not ok then
        Log("LootGm82_000 ERROR", result)
        return false
    end

    return result
end

--seekers token
local function LootGm82_036(gimmick)
    if gimmick == nil or not sdk.is_managed_object(gimmick) then
        return false
    end

    local ok, result = pcall(function()
        if gimmick:isInteractEnable(0) ~= true then
            return false
        end

        local distance = DistanceSqGimmick(gimmick)

        Log("SEEKER TOKEN",
            "distance", distance
        )

        if distance == 0.0 or distance >= rangeSq then
            return false
        end

        local player = playerManager:get_ManualPlayer()
        if player == nil then
            return false
        end

        local methods = {
            function()
                gimmick:requestForceInteract(0, player)
            end,
            function()
                gimmick:onEndInteractBase(0, player)
            end,
            function()
                gimmick:onExecuteInteractBase(0, player)
            end,
            function()
                gimmick:onStartInteractBase(0, player)
            end
        }

        for i, fn in ipairs(methods) do
            local worked, err = pcall(fn)
            Log("SEEKER METHOD", i, worked, err)

            if worked then
                local pos = nil
                pcall(function()
                    pos = gimmick:get_GameObject():get_Transform():get_Position()
                end)

                if pos ~= nil then
                    AddMessage("Loot Seeker's Token", pos)
                end

                return true
            end
        end

        return false
    end)

    if not ok then
        Log("LootGm82_036 ERROR", result)
        return false
    end

    return result
end

--chest
local function LootGm80_001(gimmick)
    if gimmick == nil or not sdk.is_managed_object(gimmick) then
        return false
    end

    local ok, result = pcall(function()
        if gimmick:isInteractEnable(0) ~= true then
            return false
        end

        local distance = DistanceSqGimmick(gimmick)

        Log("CHEST",
            "distance", distance
        )

        if distance == 0.0 or distance >= rangeSq then
            return false
        end

        local player = playerManager:get_ManualPlayer()
        if player == nil then
            return false
        end

        -- Try the interaction methods that existed across older DD2 versions.
        local executeWorked, executeErr = pcall(function()
            gimmick:onExecuteInteractBase(0, player)
        end)
        Log("CHEST EXECUTE", executeWorked, executeErr)

        local openWorked, openErr = pcall(function()
            gimmick:open(true, player)
        end)
        Log("CHEST OPEN", openWorked, openErr)

        if not executeWorked and not openWorked then
            local forceWorked, forceErr = pcall(function()
                gimmick:requestForceInteract(0, player)
            end)
            Log("CHEST FORCE", forceWorked, forceErr)

            if not forceWorked then
                local startWorked, startErr = pcall(function()
                    gimmick:onStartInteractBase(0, player)
                end)
                Log("CHEST START", startWorked, startErr)

                if not startWorked then
                    return false
                end
            end
        end

        local pos = nil
        pcall(function()
            pos = gimmick:get_GameObject():get_Transform():get_Position()
        end)

        if pos ~= nil then
            AddMessage("Loot Chest", pos)
        end

        return true
    end)

    if not ok then
        Log("LootGm80_001 ERROR", result)
        return false
    end

    return result
end


--executeInteract throw exception in re.on_frame,why?
-- Updated compatibility path:
-- GimmickManager:lateUpdate() is no longer used here.
-- Gimmicks are processed from the still-working InteractManager:onUpdate() hook.

local getGimmickListMethod=sdk.find_type_definition("app.GimmickManager"):get_method("getGimmickList(app.GimmickID)")
local gimmick82_036=sdk.find_type_definition("app.GimmickID"):get_field("Gm82_036"):get_data(nil)
local gimmick82_000=sdk.find_type_definition("app.GimmickID"):get_field("Gm82_000"):get_data(nil)

local interval=0
local interval2=0

local function ProcessGimmicks()
    -- Always refresh the squared loot range from the live config.
    -- This avoids using an old rangeSq value after changing Loot Range in-game.
    local liveRange = tonumber(config.range) or 30
    rangeSq = liveRange * liveRange

    interval2 = interval2 + 1
    if interval2 <= 15 then return end
    interval2 = 0

    Log("AUTOLOOT TICK")
    Log("LIVE LOOT RANGE", liveRange, "rangeSq", rangeSq)
    Log("lootBody =", tostring(config.lootBody))
    Log("lootBodyPart =", tostring(config.lootBodyPart))
    Log("lootDropItem =", tostring(config.lootDropItem))
    Log("lootDirectItem =", tostring(config.lootDirectItem))
    Log("lootGatherSpot =", tostring(config.lootGatherSpot))
    Log("lootSeekerToken =", tostring(config.lootSeekerToken))
    Log("lootChest =", tostring(config.lootChest))

    if config.lootGatherSpot then
        Log("ENTER GATHER")
        local okList, gimmicks = pcall(function()
            return gimmickManager:get_CollectionGimmicks()
        end)
        Log("COLLECTION LIST RESULT", okList, gimmicks)

        if okList and gimmicks ~= nil then
            local okCount, count = pcall(function()
                return gimmicks:get_Count()
            end)
            Log("COLLECTION COUNT", okCount, count)

            if okCount and count ~= nil then
                for i = 0, count - 1 do
                    local okItem, gimmick = pcall(function()
                        return gimmicks[i]
                    end)
                    if okItem and gimmick ~= nil then
                        LootGm82_009(gimmick)
                    end
                end
            end
        end
    end

    if config.lootDropItem then
        local okList, gimmicks = pcall(function()
            return gimmickManager:get_DropItemGimmicks()
        end)

        if okList and gimmicks ~= nil then
            local okCount, count = pcall(function()
                return gimmicks:get_Count()
            end)
            if okCount and count ~= nil then
                for i = 0, count - 1 do
                    local okItem, gimmick = pcall(function()
                        return gimmicks[i]
                    end)
                    if okItem and gimmick ~= nil then
                        local okLoot, err = pcall(function()
                            LootGm82_000_001(gimmick)
                        end)
                        if not okLoot then
                            Log("DROP ITEM ERROR", err)
                        end
                    end
                end
            end
        end
    end

    if config.lootDirectItem then
        Log("ENTER DIRECT ITEM")
        local okList, gimmicks = pcall(function()
            return getGimmickListMethod(gimmickManager, gimmick82_000)
        end)
        Log("DIRECT LIST RESULT", okList, gimmicks)

        if okList and gimmicks ~= nil then
            local okCount, count = pcall(function()
                return gimmicks:get_Count()
            end)
            Log("DIRECT COUNT", okCount, count)

            if okCount and count ~= nil then
                for i = 0, count - 1 do
                    local okItem, gimmick = pcall(function()
                        return gimmicks[i]
                    end)
                    if okItem and gimmick ~= nil and LootGm82_000(gimmick) then
                        break
                    end
                end
            end
        end
    end

    if config.lootSeekerToken then
        Log("ENTER SEEKER TOKEN")

        local okList, gimmicks = pcall(function()
            return getGimmickListMethod(gimmickManager, gimmick82_036)
        end)

        Log("SEEKER LIST RESULT", okList, gimmicks)

        if okList and gimmicks ~= nil then
            local okCount, count = pcall(function()
                return gimmicks:get_Count()
            end)

            Log("SEEKER COUNT", okCount, count)

            if okCount and count ~= nil then
                for i = 0, count - 1 do
                    local okItem, gimmick = pcall(function()
                        return gimmicks[i]
                    end)
                    if okItem and gimmick ~= nil and LootGm82_036(gimmick) then
                        break
                    end
                end
            end
        end
    end

    if config.lootChest then
        Log("ENTER CHEST")

        local okList, gimmicks = pcall(function()
            return gimmickManager:get_TreasureBoxGimmicks()
        end)

        Log("CHEST LIST RESULT", okList, gimmicks)

        if okList and gimmicks ~= nil then
            local okCount, count = pcall(function()
                return gimmicks:get_Count()
            end)

            Log("CHEST COUNT", okCount, count)

            if okCount and count ~= nil then
                for i = 0, count - 1 do
                    local okItem, gimmick = pcall(function()
                        return gimmicks[i]
                    end)
                    if okItem and gimmick ~= nil and LootGm80_001(gimmick) then
                        break
                    end
                end
            end
        end
    end
end

sdk.hook(
    sdk.find_type_definition("app.InteractManager"):get_method("onUpdate()"),
    function()
        if config.disableOnBattle and battleManager:get_IsBattleMode() then
            return
        end

        -- Keep mob/body loot on the same live range value too.
        local liveRange = tonumber(config.range) or 30
        rangeSq = liveRange * liveRange

        interval = interval + 1

        if interval > 15 then
            for k,v in pairs(waitingBodyControllerList) do
                if waitingBodyControllerList[k] <= 0 then
                    local okLoot, err = pcall(function()
                        LootBodyOrBodyPart(k)
                    end)

                    if not okLoot then
                        Log("BODY/BODYPART ERROR", err)
                        waitingBodyControllerList[k] = nil
                    end
                else
                    waitingBodyControllerList[k] = waitingBodyControllerList[k] - 1
                end
            end
            interval = 0
        end

        local okGimmicks, gimmickErr = pcall(ProcessGimmicks)
        if not okGimmicks then
            Log("PROCESS GIMMICKS ERROR", gimmickErr)
        end
    end,
    nil
)

--record body when setup interactive object(when monster die)
sdk.hook(
--if do executeInteract in post hook of setupInteractiveObject,the body will be forced to be intractable for once. even if set this&that to disable or destroy the controller,still interactable
--  sdk.find_type_definition("app.SearchDeadBodyInteractController"):get_method("setupInteractiveObject"),
    sdk.find_type_definition("app.SearchDeadBodyInteractController"):get_method("setupInteractiveObject()"),
    function(args)
        local this=sdk.to_managed_object(args[2])
        if this:get_IsEnablePickup() and config.lootBody then
            Log("Setup Body")
            waitingBodyControllerList[this] = 1 -- wait 1*30 frame
        end
    end,
    nil
)

--Record drop body parts
--新掉落的尾巴有时只会触发OnPartsBroken而不触发setupInteractiveObject？
sdk.hook(
    sdk.find_type_definition("app.DropPartsController"):get_method("onPartsBroken(via.GameObject, System.Boolean)"),
    function(args)
        local this=sdk.to_managed_object(args[2])
        --get_Gimmick returns nil for tail
        --DropItemData: <id,num>
        if config.lootBodyPart and this:getDropItemData().Item2>=0 then
            Log("Setup BodyPart")
            waitingBodyControllerList[this] = 1 -- wait 1*30 frame
        end
    end,
    nil
)
sdk.hook(
    sdk.find_type_definition("app.DropPartsController"):get_method("setupInteractiveObject"),
    function(args)
        local this=sdk.to_managed_object(args[2])
        --get_Gimmick returns nil for tail
        --DropItemData: <id,num>
        if config.lootBodyPart and this:getDropItemData().Item2>=0 then
            Log("Setup BodyPart2")
            waitingBodyControllerList[this] = 1 -- wait 1*30 frame
        end
    end,
    nil
)

--draw loot message
re.on_frame(function()
    --draw loot message
    if config.showLootMessage==true then
        imgui.push_font(font)
        for lootMessage,v in pairs(lootMessageList) do
		    if lootMessage.msg~=nil then
                draw.world_text(lootMessage.msg,lootMessage.pos,lootMessage.color)
            end

            lootMessageList[lootMessage]=lootMessageList[lootMessage]-1
            lootMessage.pos.y=lootMessage.pos.y+posDelta

            lootMessage.color=lootMessage.color-colorDelta
            if lootMessageList[lootMessage] < 0 then
                lootMessageList[lootMessage]=nil
            end    
        end
        imgui.pop_font()
    end
end)

myapi.DrawIt(modname,configfile,_config,config,function () 
    rangeSq=config.range*config.range
end)