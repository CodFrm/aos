Game = "o7pnXXGX1CA9W5Pw0h8pb1WL6FAryliOcYHQmzLAiyY"

GameStatus = {}

function getBalances()
    ao.send({
        Target = Game,
        Action = "Balances"
    })
end

function requestToken()
    ao.send({
        Target = Game,
        Action = "RequestToken"
    })
end

function join()
    ao.send({
        Target = Game,
        Action = "Join"
    })
end

-- 购买保险
function insurance()
    ao.send({
        Target = Game,
        Action = "Insurance",
        Data = "Yes"
    })
end

-- 庄家开始游戏
function bankerStart()
    ao.send({
        Target = Game,
        Action = "BankerStart"
    })
end

-- 庄家继续游戏
function bankerContinue()
    ao.send({
        Target = Game,
        Action = "BankerContinue"
    })
end

-- 获取游戏状态
function getStatus()
    ao.send({
        Target = Game,
        Action = "Status"
    })
end

-- 询问行动
Handlers.add("Action", Handlers.utils.hasMatchingTag("Action", "Action"), function(msg)
    if msg.From ~= ao.id then
        return
    end
    if msg.Reason then
        print(msg.Reason)
        return
    end
    -- 询问是否拿牌、加倍、分牌、投降
    print("请选择操作：1.拿牌 2.加倍 3.分牌 4.投降, 输入action(对应数字)")
    return
end)

function action(actionId)
    ao.send({
        Target = Game,
        Action = "Action",
        ActionID = actionId
    })
end

-- 询问是否购买保险
Handlers.add("Insurance", Handlers.utils.hasMatchingTag("Action", "Insurance"), function(msg)
    if msg.From ~= ao.id then
        return
    end
    -- 询问是否购买保险
    print("是否购买保险？ 输入insurance()购买，玩家完成后请庄家输入bankerContinue()继续游戏")
    return
end)

-- 庄家黑杰克结束
Handlers.add("BankerBlackjack", Handlers.utils.hasMatchingTag("Action", "BankerBlackjack"), function(msg)
    -- 庄家黑杰克结束
    print("庄家黑杰克游戏结束")
    return
end)

-- 处理发牌
Handlers.add("PostCard", Handlers.utils.hasMatchingTag("Action", "PostCard"), function(msg)
    if msg.Back then
        print("暗牌: " .. msg.Card)
    else
        print("发牌: " .. msg.From .. " " .. msg.Card)
    end
end)

-- 处理玩家加入
Handlers.add("Join", Handlers.utils.hasMatchingTag("Action", "Join"), function(msg)
    if msg.Reason then
        print(msg.Reason)
        return
    end
    if msg.From == ao.id then
        print(
            "孤注一掷 21点小游戏加载完成~\n输入: join() 加入游戏\ngetBalances() 查询余额\nrequestToken() 获取一些代币")
    else
        print(msg.From .. " 加入游戏")
    end
    ao.send({
        Target = Game,
        Action = "Status"
    })
end)

-- GameStatus
Handlers.add("GameStatus", Handlers.utils.hasMatchingTag("Action", "Status"), function(msg)
    GameStatus = msg
    if msg.Status == 0 then
        print("未开始")
    elseif msg.Status == 1 then
        print("已开始")
    elseif msg.Status == 2 then
        print("已结束")
    end
    isBanker = false
    for i, v in ipairs(msg.Players) do
        if v.Role == "Banker" then
            print(v.Player .. " 庄家")
            if v.Player == ao.id then
                isBanker = true
            end
        else
            print(v.Player .. " 玩家")
        end
    end
    if isBanker then
        print("庄家操作: bankerStart() 开始游戏")
    end
end)

-- 游戏结束
Handlers.add("GameEnd", Handlers.utils.hasMatchingTag("Action", "GameEnd"), function(msg)
    if msg.From ~= ao.id then
        return
    end
    if msg.Status == "Win" then
        print("恭喜你赢了！")
    elseif msg.Status == "Lose" then
        print("很遗憾，你输了！")
    elseif msg.Status == "Insurance" then
        print("保险赢了！")
    else
        print("平局！")
    end
    if msg.Reason then
        print(msg.Reason)
    end
    -- 游戏结束
    print("游戏结束")
    return
end)

-- 余额查询
Handlers.add("Balances", Handlers.utils.hasMatchingTag("Action", "Balances"), function(msg)
    print("余额: " .. msg.Balance)
end)

print(
    "孤注一掷 21点小游戏加载完成~\n输入: join() 加入游戏\ngetBalances() 查询余额\nrequestToken() 获取一些代币")

