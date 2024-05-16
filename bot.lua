-- 初始化全局变量来存储最新的游戏状态和游戏主机进程。
LatestGameState = LatestGameState or nil
InAction = InAction or false -- 防止代理同时采取多个操作。

Logs = Logs or {}

colors = {
    red = "\27[31m",
    green = "\27[32m",
    blue = "\27[34m",
    reset = "\27[0m",
    gray = "\27[90m"
}

function addLog(msg, text) -- 函数定义注释用于性能，可用于调试
    Logs[msg] = Logs[msg] or {}
    table.insert(Logs[msg], text)
end

-- 检查两个点是否在给定范围内。
-- @param x1, y1: 第一个点的坐标
-- @param x2, y2: 第二个点的坐标
-- @param range: 点之间允许的最大距离
-- @return: Boolean 指示点是否在指定范围内
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- 往某个玩家移动
function moveToPlayer(player, targer)
    local direction = ""
    if player.y < targer.y then
        direction = "Down"
    elseif player.y > targer.y then
        direction = "Up"
    end
    if player.x < targer.x then
        direction = "Right"
    elseif player.x > targer.x then
        direction = "Left"
    end
    return direction
end

-- 往某个玩家远离
function moveAwayFromPlayer(player, targer)
    if player.y < targer.y then
        return "Up"
    elseif player.y > targer.y then
        return "Down"
    elseif player.x < targer.x then
        return "Left"
    else
        return "Right"
    end
end

-- 根据玩家的距离和能量决定下一步行动。
-- 寻找最低血量的玩家，去进行击杀
-- 如果血量比最低血量玩家还低，判断能量是否能一击必杀，再去寻找
-- 否则先进行躲藏
function decideNextAction()
    local player = LatestGameState.Players[ao.id]
    -- 血量最低的玩家
    local targetMinPlayerId = pairs(LatestGameState.Players)[0]
    local targetMinPlayer = LatestGameState.Players[targetMinPlayerId]
    if targetMinPlayerId == ao.id then
        targetMinPlayerId = pairs(LatestGameState.Players)[1]
        targetMinPlayer = LatestGameState.Players[targetMinPlayerId]
    end

    for target, state in pairs(LatestGameState.Players) do
        -- 寻找血量最低的玩家
        if targetMinPlayer.health > state.health and target ~= ao.id then
            targetMinPlayer = state
            targetMinPlayerId = target
        end
    end

    -- 判断自己的血量是否比最低血量玩家还低
    if player.health <= targetMinPlayer.health then
        -- 判断能量能否一击必杀
        if player.energy >= targetMinPlayer.health then
            print(colors.red .. "追击" .. targetMinPlayerId .. colors.reset)
            -- 往targetMinPlayer附近移动
            direction = moveToPlayer(player, targetMinPlayer)
            if direction then
                ao.send({
                    Target = Game,
                    Action = "PlayerMove",
                    Player = ao.id,
                    Direction = direction
                })
            end
        else
            print(colors.red .. "躲藏." .. colors.reset)
            -- 往最近的玩家远离
            local targetMaxPlayerId = pairs(LatestGameState.Players)[0]
            local targetMaxPlayer = LatestGameState.Players[targetMaxPlayerId]
            if targetMaxPlayerId == ao.id then
                targetMaxPlayerId = pairs(LatestGameState.Players)[1]
                targetMaxPlayer = LatestGameState.Players[targetMaxPlayerId]
            end
            -- 最小距离
            local minDistance = math.abs(player.x - targetMaxPlayer.x) + math.abs(player.y - targetMaxPlayer.y)
            for target, state in pairs(LatestGameState.Players) do
                local distance = math.abs(player.x - state.x) + math.abs(player.y - state.y)
                if distance < minDistance and target ~= ao.id then
                    targetMaxPlayer = state
                    targetMaxPlayerId = target
                    minDistance = distance
                end
            end
            -- 远离
            direction = moveAwayFromPlayer(player, targetMaxPlayer)
            ao.send({
                Target = Game,
                Action = "PlayerMove",
                Player = ao.id,
                Direction = direction
            })
        end
    else
        -- 往targetMinPlayer附近移动
        print(colors.red .. "追击" .. targetMinPlayerId .. colors.reset)
        direction = moveToPlayer(player, targetMinPlayer)
		if direction then
			ao.send({
				Target = Game,
				Action = "PlayerMove",
				Player = ao.id,
				Direction = direction
			})
		end
    end

    InAction = false -- InAction 逻辑添加
end

-- 打印游戏公告并触发游戏状态更新的handler。
Handlers.add("PrintAnnouncements", Handlers.utils.hasMatchingTag("Action", "Announcement"), function(msg)
    if msg.Event == "Started-Waiting-Period" then
        ao.send({
            Target = ao.id,
            Action = "AutoPay"
        })
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
        InAction = true --  InAction 逻辑添加
        ao.send({
            Target = Game,
            Action = "GetGameState"
        })
    elseif InAction then --  InAction 逻辑添加
        print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
end)

-- 触发游戏状态更新的handler。
Handlers.add("GetGameStateOnTick", Handlers.utils.hasMatchingTag("Action", "Tick"), function()
    if not InAction then -- InAction 逻辑添加
        InAction = true -- InAction 逻辑添加
        print(colors.gray .. "Getting game state..." .. colors.reset)
        ao.send({
            Target = Game,
            Action = "GetGameState"
        })
    else
        print("Previous action still in progress. Skipping.")
    end
end)

-- 等待期开始时自动付款确认的handler。
Handlers.add("AutoPay", Handlers.utils.hasMatchingTag("Action", "AutoPay"), function(msg)
    print("Auto-paying confirmation fees.")
    ao.send({
        Target = Game,
        Action = "Transfer",
        Recipient = Game,
        Quantity = "1000"
    })
end)

-- 接收游戏状态信息后更新游戏状态的handler。
Handlers.add("UpdateGameState", Handlers.utils.hasMatchingTag("Action", "GameState"), function(msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({
        Target = ao.id,
        Action = "UpdatedGameState"
    })
    print("Game state updated. Print \'LatestGameState\' for detailed view.")
end)

-- 决策下一个最佳操作的handler。
Handlers.add("decideNextAction", Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"), function()
    if LatestGameState.GameMode ~= "Playing" then
        InAction = false -- InAction 逻辑添加
        return
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({
        Target = ao.id,
        Action = "Tick"
    })
end)

-- 被其他玩家击中时自动攻击的handler。
-- 判断能否一击必杀对方，否则打一下跑一下
Handlers.add("ReturnAttack", Handlers.utils.hasMatchingTag("Action", "Hit"), function(msg)
    if not InAction then --  InAction 逻辑添加
        InAction = true --  InAction 逻辑添加

        local playerEnergy = LatestGameState.Players[ao.id].energy
        -- 最近的玩家
        local targetNearestPlayerId = pairs(LatestGameState.Players)[0]
        local targetNearestPlayer = LatestGameState.Players[targetNearestPlayerId]
        if targetNearestPlayerId == ao.id then
            targetNearestPlayerId = pairs(LatestGameState.Players)[1]
            targetNearestPlayer = LatestGameState.Players[targetNearestPlayerId]
        end
        -- 最小距离
        local minDistance = math.abs(player.x - targetNearestPlayer.x) + math.abs(player.y - targetNearestPlayer.y)
        for target, state in pairs(LatestGameState.Players) do
            local distance = math.abs(player.x - state.x) + math.abs(player.y - state.y)
            if distance < minDistance and target ~= ao.id then
                targetNearestPlayer = state
                targetNearestPlayerId = target
                minDistance = distance
            end
        end

        if playerEnergy == undefined then
            print(colors.red .. "Unable to read energy." .. colors.reset)
            ao.send({
                Target = Game,
                Action = "Attack-Failed",
                Reason = "Unable to read energy."
            })
        elseif playerEnergy == 0 then
            -- 远离
            direction = moveAwayFromPlayer(player, targetNearestPlayer)
            ao.send({
                Target = Game,
                Action = "PlayerMove",
                Player = ao.id,
                Direction = direction
            })
        else
            print(colors.red .. "Returning attack." .. colors.reset)
            ao.send({
                Target = Game,
                Action = "PlayerAttack",
                Player = ao.id,
                AttackEnergy = tostring(playerEnergy)
            })
            -- 能否一击必杀
            if playerEnergy >= targetNearestPlayer.health then
                -- 远离
                direction = moveAwayFromPlayer(player, targetNearestPlayer)
                ao.send({
                    Target = Game,
                    Action = "PlayerMove",
                    Player = ao.id,
                    Direction = direction
                })
            end
        end
        InAction = false --  InAction 逻辑添加
        ao.send({
            Target = ao.id,
            Action = "Tick"
        })
    else
        print("Previous action still in progress. Skipping.")
    end
end)
