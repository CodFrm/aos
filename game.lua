-- 24点游戏
local bint = require('.bint')(256)
local ao = require('ao')

local utils = {
    add = function(a, b)
        return tostring(bint(a) + bint(b))
    end,
    subtract = function(a, b)
        return tostring(bint(a) - bint(b))
    end,
    toBalanceValue = function(a)
        return tostring(bint(a))
    end,
    toNumber = function(a)
        return tonumber(a)
    end
}

-- 余额
Balances = Balances or {
    [ao.id] = utils.toBalanceValue(10000 * 1e12)
}
Name = Name or 'Blackjack'
Ticker = Ticker or 'BJ'
Denomination = Denomination or 12
Logo = Logo or 'SBCCXwwecBlDqRLUjb8dYABExTJXLieawf7m2aBJ-KY'

-- 当前玩家, 只能有2-6个玩家, 第一个玩家为庄
Player = {}

-- 游戏状态，0: 未开始，1: 已开始 2: 已结束
Status = 0

-- 操作用户
ActionIndex = 0
-- 游戏进程 0: 初始化 1: 询问购买保险 2: 正常游戏阶段
Step = 0

-- 牌库
Cards = {}

-- 洗牌
function refreshCard()
    -- 扑克牌
    Cards = {"A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"}
    -- 发四组
    for i = 1, 4 do
        for j = 1, 13 do
            table.insert(Cards, Cards[j])
        end
    end
end

-- 计算分数
function calculateScore(player)
    local total = 0
    local aceCount = 0

    -- 遍历所有牌计算总分，对A先不计分
    for _, card in ipairs(player.Cards.Front) do
        if card == "A" then
            aceCount = aceCount + 1
        elseif isTen(card) then
            total = total + 10
        else
            total = total + tonumber(card)
        end
    end

    -- 对于每个A，判断最优使用方式
    for i = 1, aceCount do
        if total + 11 <= 21 then
            total = total + 11 -- 如果加11后不超过21，A计为11
        else
            total = total + 1 -- 否则A只能计为1
        end
    end

    return total
end

function broadcast(action, tags)
    msg = {
        Target = i,
        Action = action
    }
    for k, v in ipairs(tags) do
        msg[k] = v
    end
    for i, v in ipairs(Player) do
        msg.Target = v.ID
        ao.send(msg)
    end
end

-- 发牌 参数一是玩家 参数二表明是暗牌还是明牌
function postCard(player, back)
    -- 从牌库中取出一张牌 删除并加入玩家手牌
    cardIndex = math.random(1, #Cards)
    card = Cards[cardIndex]
    table.remove(Cards, cardIndex)
    if back then
        table.insert(player.Cards.Back, card)
        ao.send({
            Target = player.ID,
            Action = "PostCard",
            From = player.ID,
            Card = card,
            Back = true
        })
    else
        table.insert(player.Cards.Front, card)
        -- 明牌进行广播
        broadcast("PostCard", {
            From = player.ID,
            Card = card,
            Back = false
        })
    end
end

function isTen(card)
    return card == "10" or card == "J" or card == "Q" or card == "K"
end

function startGame()
    refreshCard()
    Step = 0
    broadcast("GameStart", {})
    -- 开始游戏
    -- 给闲家发两张明牌
    for i = 2, #Player do
        postCard(Player[i], false)
        postCard(Player[i], false)
    end
    -- 庄家一张明牌一张暗牌
    postCard(Player[1], false)
    postCard(Player[1], true)
    -- 如果庄家的明牌是T，暗牌是A，直接翻开并拥有黑杰克，进入结算
    if isTen(Player[1].Cards.Front[1]) then
        if Player[1].Cards.Back[1] == "A" then
            broadcast("BankerBlackjack", {})
            -- 结算
            for i, v in ipairs(Player) do
                if isBlackjack(v) then
                    -- 庄闲都是黑杰克，平局
                    broadcast("GameEnd", {
                        From = v.ID,
                        Status = "Push"
                    })
                else
                    -- 庄家是黑杰克，玩家输掉赌注
                    Balances[v.ID] = utils.subtract(Balances[v.ID], v.Score)
                    Balances[Player[1].ID] = utils.add(Balances[Player[1].ID], v.Score)
                    broadcast("GameEnd", {
                        From = v.ID,
                        Status = "Lose"
                    })
                end
            end
            Status = 2
            return
        end
    elseif Player[1].Cards.Front[1] == "A" then
        -- 如果庄家的明牌是A，询问是否买保险
        -- 进入保险阶段
        Step = 1
        broadcast("Insurance", {})
        return
    end
    Step = 2
end

-- 判断是否为黑杰克
function isBlackjack(player)
    if player.Cards.Front == 2 then
        if player.Cards.Front[1] == "A" and isTen(player.Cards.Front[2]) then
            return true
        elseif player.Cards.Front[2] == "A" and isTen(player.Cards.Front[1]) then
            return true
        end
    end
    return false
end

-- 购买保险
Handlers.add("Insurance", Handlers.utils.hasMatchingTag("Action", "Insurance"), function(msg)
    if Step ~= 1 then
        return
    end
    if msg.Data == "Yes" then
        -- 玩家购买保险, 庄家不能购买保险
        for i, v in ipairs(Player) do
            if v.Role == "Banker" then
                return
            elseif v.ID == msg.From then
                Balances[msg.From] = utils.subtract(Balances[msg.From], v.Score * 0.5)
                Balances[Player[1].ID] = utils.add(Balances[Player[1].ID], v.Score * 0.5)
                broadcast("Insurance", {
                    From = msg.From,
                    Status = "Success"
                })
                v.Insurance = true
            end
        end
    end
end)

-- 庄家继续游戏
Handlers.add("BankerContinue", Handlers.utils.hasMatchingTag("Action", "BankerContinue"), function(msg)
    if msg.From ~= Player[1].ID then
        return
    end
    -- 保险结算
    if Step == 2 then
        -- 如果庄家暗牌是10，翻开牌，买了保险的玩家获得1倍
        if isTen(Player[1].Cards.Back[1]) then
            for i, v in ipairs(Player) do
                if v.Insurance then
                    Balances[v.ID] = utils.add(Balances[v.ID], v.Score)
                    Balances[Player[1].ID] = utils.subtract(Balances[Player[1].ID], v.Score)
                    -- 通报保险赔付
                    v.End = true
                    broadcast("GameEnd", {
                        From = v.ID,
                        Status = "Insurance",
                        Reason = "庄家暗牌是10"
                    })
                elseif isBlackjack(v) then
                    -- 如果玩家有blackjack，平局
                    -- Balances[v.ID] = utils.add(Balances[v.ID], 100)
                    v.End = true
                    broadcast("GameEnd", {
                        From = v.ID,
                        Status = "Push",
                        Reason = "双方都是黑杰克"
                    })
                else
                    -- 如果玩家没有blackjack，输掉赌注
                    v.End = true
                    Balances[v.ID] = utils.subtract(Balances[v.ID], v.Score)
                    Balances[Player[1].ID] = utils.add(Balances[Player[1].ID], v.Score)
                    broadcast("GameEnd", {
                        From = v.ID,
                        Status = "Lose",
                        Reason = "庄家暗牌是10"
                    })
                end
            end
            -- 明牌
            table.insert(Player[1].Cards.Front, Player[1].Cards.Back[1])
            table.remove(Player[1].Cards.Back, 1)
            -- 游戏结束
            Status = 2
            return
        else
            -- 如果庄家没有blackjack，但是玩家有，玩家获得1.5倍
            for i, v in ipairs(Player) do
                if v.Role ~= "Banker" then
                    if isBlackjack(v) then
                        v.End = true
                        Balances[v.ID] = utils.add(Balances[v.ID], v.Score * 1.5)
                        Balances[Player[1].ID] = utils.subtract(Balances[Player[1].ID], v.Score * 1.5)
                        broadcast("GameEnd", {
                            From = v.ID,
                            Status = "Win"
                        })
                    end
                end
            end
            -- 与剩下的玩家继续游戏
        end
        Step = 3
        -- 游戏从第一个非黑杰克玩家开始
        index = 0
        for i, v in ipairs(Player) do
            if v.Role ~= "Banker" and not v.End then
                index = i
                break
            end
        end
        if index == 0 then
            index = 2
        end
        -- 询问是否拿牌、加倍、分牌、投降
        ActionIndex = index
        broadcast("Action", {
            From = Player[index].ID
        })
        return
    end
end)

-- 询问行动
Handlers.add("Action", Handlers.utils.hasMatchingTag("Action", "Action"), function(msg)
    if msg.From ~= Player[ActionIndex].ID then
        ao.send({
            Target = msg.From,
            Action = "Action",
            Status = "Fail",
            Reason = "不是你的回合"
        })
        return
    end
    -- 询问是否拿牌、加倍、分牌、投降
    if msg.ActionID == 1 then
        postCard(Player[ActionIndex], false)
        if calculateScore(Player[ActionIndex]) > 21 then
            broadcast("GameEnd", {
                From = Player[ActionIndex].ID,
                Status = "Lose"
            })
            Balances[Player[ActionIndex].ID] = utils.subtract(Balances[Player[ActionIndex].ID],
                Player[ActionIndex].Score)
            Balances[Player[1].ID] = utils.add(Balances[Player[1].ID], Player[ActionIndex].Score)
            Player[ActionIndex].End = true
        end
    end
    -- 进入下一个玩家
    for i = 0, #Player do
        ActionIndex = ActionIndex + 1
        if Player[ActionIndex] == nil then
            ActionIndex = 1
        end
        if Player[ActionIndex].End then
            ActionIndex = ActionIndex + 1
        end
    end
end)

-- 庄家开始游戏
Handlers.add("BankerStart", Handlers.utils.hasMatchingTag("Action", "BankerStart"), function(msg)
    if msg.From ~= Player[1].ID then
        return
    end
    -- 庄家开始游戏, 至少需要2人
    if #Player < 2 then
        broadcast("BankerStart", {
            Status = "Fail",
            Reason = "玩家不足"
        })
        return
    end
    startGame()
end)

-- 加入游戏
Handlers.add("Join", Handlers.utils.hasMatchingTag("Action", "Join"), function(msg)
    -- 判断当前游戏状态
    if Status ~= 1 then
        ao.send({
            Target = msg.From,
            Action = "Join",
            From = ao.id,
            Status = "Fail",
            Reason = "游戏已开始"
        })
        -- 判断当前玩家人数
        return
    elseif #Player >= 6 then
        ao.send({
            Target = msg.From,
            Action = "Join",
            From = ao.id,
            Status = "Fail",
            Reason = "玩家已满"
        })
        return
    end
    -- 过滤已经加入的玩家
    for i, v in ipairs(Player) do
        if v.ID == msg.From then
            ao.send({
                Target = msg.From,
                Action = "Join",
                From = ao.id,
                Status = "Fail",
                Reason = "已加入游戏"
            })
            return
        end
    end
    -- 判断玩家余额
    if not Balances[msg.From] or utils.toNumber(Balances[msg.From]) < 100 then
        ao.send({
            Target = msg.From,
            Action = "Join",
            From = ao.id,
            Status = "Fail",
            Reason = "余额不足"
        })
        return
    end
    if #Player == 0 then
        -- 广播角色为庄家
        broadcast("Join", {
            From = msg.From,
            Role = "Banker"
        })
        Player[1] = {
            ID = msg.From,
            Role = "Banker",
            Score = 0,
            Cards = {
                -- 明牌
                Front = {},
                -- 暗牌
                Back = {}
            }
        }
    else
        -- 成为闲家
        broadcast("Join", {
            From = msg.From,
            Role = "Player"
        })
        table.insert(Player, {
            ID = msg.From,
            Role = "Player",
            Score = 100,
            Cards = {
                -- 明牌
                Front = {},
                -- 暗牌
                Back = {}
            }
        })
        -- 玩家数大于等于6时，开始游戏
        if #Player >= 6 then
            startGame()
        end
    end
end)

-- 获取游戏状态
Handlers.add("GetStatus", Handlers.utils.hasMatchingTag("Action", "Status"), function(msg)
    sendPlayerinfo = {}
    for i, v in ipairs(Player) do
        table.insert(sendPlayerinfo, {
            ID = v.ID,
            Role = v.Role,
            Score = v.Score
        })
    end
    ao.send({
        Target = msg.From,
        Action = "Status",
        From = ao.id,
        Player = sendPlayerinfo,
        Status = Status,
        Step = Step
    })
end)

function sendBalances(msg)
    bal = 0
    if not Balances[msg.From] then
        bal = 0
    else
        bal = Balances[msg.From]
    end
    ao.send({
        Target = msg.From,
        Balance = bal,
        Ticker = Ticker,
        Account = msg.From,
        Data = bal
    })
end

-- 请求获取积分
Handlers.add("RequestToken", Handlers.utils.hasMatchingTag("Action", "RequestToken"), function(msg)
    if not Balances[msg.From] then
        Balances[msg.From] = '0'
    end
    -- 添加1000
    Balances[msg.From] = utils.add(Balances[msg.From], 1000)
    sendBalances(msg)
end)

-- 查询信息
Handlers.add("Info", Handlers.utils.hasMatchingTag("Action", "Info"), function(msg)
    ao.send({
        Target = msg.From,
        Name = Name,
        Ticker = Ticker,
        Logo = Logo,
        Denomination = tostring(Denomination)
    })
end)

-- 查询余额
Handlers.add("Balances", Handlers.utils.hasMatchingTag("Action", "Balances"), function(msg)
    sendBalances(msg)
end)
