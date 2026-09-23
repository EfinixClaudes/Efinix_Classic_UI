local _, ns = ...

-- Talent window (Blizzard_TalentUI 1.12): a 384x512 panel with the player's
-- portrait, one tab per talent tree, the tree's background painting, a
-- scrolling 4-column grid of 37 px talent buttons with rank badges, branch
-- lines and arrows between prerequisites, "Points spent" and "Talent Points"
-- readouts. Forever keeps its talents in one trait tree with three groups
-- (Camelot ClassTalentsFrame), so the groups become the tabs and the node
-- positions become tiers and columns. A click learns the talent at once, as
-- in 2006: the rank is purchased and the configuration committed in one go;
-- if the game refuses the commit (combat, casting) the point stays staged
-- and an Apply button appears.
--
-- Strategy: replace. Blizzard's PlayerSpellsFrame talent tab is a 1200 px
-- trait tree that cannot be shaped into the Vanilla frame; it is left alone
-- and only our micro button and the talent key binding point here.
local Combat = ns.Combat

local Talents = ns.RegisterModule("Talents", {})
ns.Talents = Talents

local NUM_COLUMNS = 4 -- NUM_TALENT_COLUMNS
local MAX_TIERS = 8 -- MAX_NUM_TALENT_TIERS
local BUTTON_SIZE = 32 -- TALENT_BUTTON_SIZE (branch geometry)
local BUTTON = 37 -- ItemButtonTemplate 1.12
local STRIDE = 63 -- SetTalentButtonLocation
local INITIAL_OFFSET_X = 35 -- INITIAL_TALENT_OFFSET_X
local INITIAL_OFFSET_Y = 20 -- INITIAL_TALENT_OFFSET_Y
local MAX_BRANCHES = 30
local MAX_ARROWS = 30

local B = "Interface\\Buttons\\"
local T = "Interface\\TalentFrame\\"
local P = "Interface\\PaperDollInfoFrame\\"
local FILES = {
    topLeft = P .. "UI-Character-General-TopLeft",
    topRight = P .. "UI-Character-General-TopRight",
    botLeft = T .. "UI-TalentFrame-BotLeft",
    botRight = T .. "UI-TalentFrame-BotRight",
    branches = T .. "UI-TalentBranches",
    arrows = T .. "UI-TalentArrows",
    rankBorder = T .. "TalentFrame-RankBorder",
    slot = B .. "UI-EmptySlot-White",
    normal = B .. "UI-Quickslot2",
    pushed = B .. "UI-Quickslot-Depress",
    highlight = B .. "ButtonHilight-Square",
    closeUp = B .. "UI-Panel-MinimizeButton-Up",
    closeDown = B .. "UI-Panel-MinimizeButton-Down",
    closeHighlight = B .. "UI-Panel-MinimizeButton-Highlight",
    inputBorder = "Interface\\Common\\Common-Input-Border",
    tabActive = P .. "UI-Character-ActiveTab",
    tabInactive = P .. "UI-Character-InActiveTab",
    scrollBar = P .. "UI-Character-ScrollBar",
}

-- 1.12 tree backgrounds (GetTalentTabInfo file names), in Vanilla tree order.
-- The literal names keep tools/import_blizzard_art.py able to find the files.
local BACKGROUNDS = {
    WARRIOR = { T .. "WarriorArms", T .. "WarriorFury", T .. "WarriorProtection" },
    PALADIN = { T .. "PaladinHoly", T .. "PaladinProtection", T .. "PaladinCombat" },
    HUNTER = { T .. "HunterBeastMastery", T .. "HunterMarksmanship", T .. "HunterSurvival" },
    ROGUE = { T .. "RogueAssassination", T .. "RogueCombat", T .. "RogueSubtlety" },
    PRIEST = { T .. "PriestDiscipline", T .. "PriestHoly", T .. "PriestShadow" },
    SHAMAN = { T .. "ShamanElementalCombat", T .. "ShamanEnhancement", T .. "ShamanRestoration" },
    MAGE = { T .. "MageArcane", T .. "MageFire", T .. "MageFrost" },
    WARLOCK = { T .. "WarlockCurses", T .. "WarlockSummoning", T .. "WarlockDestruction" },
    DRUID = { T .. "DruidBalance", T .. "DruidFeralCombat", T .. "DruidRestoration" },
}
local DEFAULT_BACKGROUND = T .. "MageFire" -- Blizzard_TalentUI.lua fallback

-- Blizzard_TalentUI.lua TALENT_BRANCH_TEXTURECOORDS / TALENT_ARROW_TEXTURECOORDS
local BRANCH_COORDS = {
    up = { [1] = { 0.12890625, 0.25390625, 0, 0.484375 }, [-1] = { 0.12890625, 0.25390625, 0.515625, 1.0 } },
    down = { [1] = { 0, 0.125, 0, 0.484375 }, [-1] = { 0, 0.125, 0.515625, 1.0 } },
    left = { [1] = { 0.2578125, 0.3828125, 0, 0.5 }, [-1] = { 0.2578125, 0.3828125, 0.5, 1.0 } },
    right = { [1] = { 0.2578125, 0.3828125, 0, 0.5 }, [-1] = { 0.2578125, 0.3828125, 0.5, 1.0 } },
    topright = { [1] = { 0.515625, 0.640625, 0, 0.5 }, [-1] = { 0.515625, 0.640625, 0.5, 1.0 } },
    topleft = { [1] = { 0.640625, 0.515625, 0, 0.5 }, [-1] = { 0.640625, 0.515625, 0.5, 1.0 } },
    bottomright = { [1] = { 0.38671875, 0.51171875, 0, 0.5 }, [-1] = { 0.38671875, 0.51171875, 0.5, 1.0 } },
    bottomleft = { [1] = { 0.51171875, 0.38671875, 0, 0.5 }, [-1] = { 0.51171875, 0.38671875, 0.5, 1.0 } },
    tdown = { [1] = { 0.64453125, 0.76953125, 0, 0.5 }, [-1] = { 0.64453125, 0.76953125, 0.5, 1.0 } },
    tup = { [1] = { 0.7734375, 0.8984375, 0, 0.5 }, [-1] = { 0.7734375, 0.8984375, 0.5, 1.0 } },
}
local ARROW_COORDS = {
    top = { [1] = { 0, 0.5, 0, 0.5 }, [-1] = { 0, 0.5, 0.5, 1.0 } },
    right = { [1] = { 1.0, 0.5, 0, 0.5 }, [-1] = { 1.0, 0.5, 0.5, 1.0 } },
    left = { [1] = { 0.5, 1.0, 0, 0.5 }, [-1] = { 0.5, 1.0, 0.5, 1.0 } },
}

local function tex(key)
    return ns.Assets.Resolve(FILES[key])
end

local function artAvailable()
    return ns.Assets.HasMedia(FILES.botLeft) or ns.Compat.TextureExists(FILES.botLeft)
end

local function plain(value)
    if ns.Compat.IsSecret(value) then
        return nil
    end
    return value
end

local function sound(id)
    if id then
        PlaySound(id)
    end
end

local frame
local toggleButton
local selectedTab = 1
local trees = {} -- index -> { groupID, name, icon, spent, nodes = { {nodeID, tier, column, ...} } }
local pointsLeft = 0
local configID
local treeID
local branchArray = {} -- [tier][column] = { id, up, down, left, right, leftArrow, rightArrow, topArrow }

---------------------------------------------------------------------------
-- Data (C_Traits / C_ClassTalents)
---------------------------------------------------------------------------
-- Camelot resolves the talent configuration through the active spec group
-- (ClassTalentsFrameMixin:SetTab -> GetCombatConfigIDForSpecGroup); the
-- Retail GetActiveConfigID and the combat config list are the fallbacks.
Talents.configSource = "none"
local function activeConfig()
    local candidates = {}
    if C_SpecializationInfo and C_SpecializationInfo.GetCombatConfigIDForSpecGroup then
        local group = C_SpecializationInfo.GetActiveSpecGroup and C_SpecializationInfo.GetActiveSpecGroup() or 1
        local ok, id = pcall(C_SpecializationInfo.GetCombatConfigIDForSpecGroup, group)
        if ok and id then
            candidates[#candidates + 1] = { id = id, source = "specgroup" }
        end
    end
    if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
        local id = C_ClassTalents.GetActiveConfigID()
        if id then
            candidates[#candidates + 1] = { id = id, source = "active" }
        end
    end
    if C_Traits.GetConfigsByType and Enum.TraitConfigType and Enum.TraitConfigType.Combat then
        local ok, ids = pcall(C_Traits.GetConfigsByType, Enum.TraitConfigType.Combat)
        if ok and type(ids) == "table" then
            for _, id in ipairs(ids) do
                candidates[#candidates + 1] = { id = id, source = "combatlist" }
            end
        end
    end
    for _, candidate in ipairs(candidates) do
        local info = C_Traits.GetConfigInfo(candidate.id)
        if info and info.treeIDs and info.treeIDs[1] then
            Talents.configSource = candidate.source
            return candidate.id, info.treeIDs[1]
        end
    end
    Talents.configSource = "none (" .. #candidates .. " candidates)"
    return nil
end

local function nodeDefinition(nodeInfo)
    local entryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID or nodeInfo.entryIDs[1]
    if not entryID then
        return nil
    end
    local entry = C_Traits.GetEntryInfo(configID, entryID)
    local definition = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
    return entryID, entry, definition
end

local function talentName(definition)
    if not definition then
        return nil
    end
    if definition.overrideName and definition.overrideName ~= "" then
        return definition.overrideName
    end
    if definition.spellID and C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(definition.spellID)
    end
    return nil
end

local function talentIcon(definition)
    if not definition then
        return nil
    end
    if definition.overrideIcon then
        return definition.overrideIcon
    end
    if definition.spellID and C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(definition.spellID)
    end
    return nil
end

-- Node positions are tree coordinates (units of 1/10 px in Blizzard's own
-- layout); within one group the distinct X and Y values are the columns and
-- tiers. Rounded against the smallest step so uneven spacing still lands.
local function gridIndex(value, sorted)
    if #sorted <= 1 then
        return 1
    end
    local step = math.huge
    for i = 2, #sorted do
        step = math.min(step, sorted[i] - sorted[i - 1])
    end
    if step <= 0 then
        return 1
    end
    return math.floor((value - sorted[1]) / step + 0.5) + 1
end

local function sortedUnique(values)
    local seen, list = {}, {}
    for _, value in ipairs(values) do
        if not seen[value] then
            seen[value] = true
            list[#list + 1] = value
        end
    end
    table.sort(list)
    return list
end

function Talents.Rebuild()
    trees = {}
    pointsLeft = 0
    configID, treeID = activeConfig()
    if not configID then
        return
    end

    local displayInfos = C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}
    table.sort(displayInfos, function(a, b)
        return (a.orderIndex or 0) < (b.orderIndex or 0)
    end)
    local groupIDs, byGroup = {}, {}
    for index, info in ipairs(displayInfos) do
        groupIDs[#groupIDs + 1] = info.groupID
        local tree = { groupID = info.groupID, name = info.displayName, icon = info.icon, spent = 0, nodes = {} }
        trees[index] = tree
        byGroup[info.groupID] = tree
    end
    local currency = C_Traits.GetGroupCurrencyInfo(configID, groupIDs) or {}
    for _, groupInfo in ipairs(currency) do
        local tree = byGroup[groupInfo.traitNodeGroupID]
        local first = groupInfo.currencyInfos and groupInfo.currencyInfos[1]
        if tree and first then
            tree.spent = tonumber(plain(first.spent)) or 0
        end
    end
    local treeCurrency = C_Traits.GetTreeCurrencyInfo(configID, treeID, false)
    if treeCurrency and treeCurrency[1] then
        pointsLeft = tonumber(plain(treeCurrency[1].quantity)) or 0
    end

    -- nodes, grouped
    local byNode = {}
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
        local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
        if nodeInfo and nodeInfo.isVisible and not nodeInfo.subTreeID then
            local tree = byGroup[nodeInfo.groupIDs and nodeInfo.groupIDs[1]]
            if tree then
                local entryID, entry, definition = nodeDefinition(nodeInfo)
                local node = {
                    nodeID = nodeID,
                    info = nodeInfo,
                    entryID = entryID,
                    entry = entry,
                    definition = definition,
                    name = talentName(definition),
                    icon = talentIcon(definition),
                    rank = tonumber(plain(nodeInfo.ranksPurchased)) or 0,
                    maxRank = tonumber(plain(nodeInfo.maxRanks)) or 1,
                    prereqs = {},
                }
                tree.nodes[#tree.nodes + 1] = node
                byNode[nodeID] = node
            end
        end
    end
    -- prerequisites: an edge runs from the required talent to the one that needs it
    for _, node in pairs(byNode) do
        for _, edge in ipairs(node.info.visibleEdges or {}) do
            local target = byNode[edge.targetNode]
            if target then
                target.prereqs[#target.prereqs + 1] = { node = node, active = edge.isActive == true }
            end
        end
    end
    -- tiers and columns
    for _, tree in ipairs(trees) do
        local xs, ys = {}, {}
        for _, node in ipairs(tree.nodes) do
            xs[#xs + 1] = node.info.posX
            ys[#ys + 1] = node.info.posY
        end
        xs, ys = sortedUnique(xs), sortedUnique(ys)
        for _, node in ipairs(tree.nodes) do
            node.column = math.max(1, math.min(NUM_COLUMNS, gridIndex(node.info.posX, xs)))
            node.tier = math.max(1, math.min(MAX_TIERS, gridIndex(node.info.posY, ys)))
        end
        table.sort(tree.nodes, function(a, b)
            if a.tier ~= b.tier then
                return a.tier < b.tier
            end
            return a.column < b.column
        end)
    end
    if selectedTab > #trees then
        selectedTab = 1
    end
end

---------------------------------------------------------------------------
-- Branches (Blizzard_TalentUI.lua TalentFrame_DrawLines, verbatim logic)
---------------------------------------------------------------------------
local function resetBranches()
    for i = 1, MAX_TIERS do
        branchArray[i] = branchArray[i] or {}
        for j = 1, NUM_COLUMNS do
            branchArray[i][j] =
                { id = nil, up = 0, left = 0, right = 0, down = 0, leftArrow = 0, rightArrow = 0, topArrow = 0 }
        end
    end
end

local function drawLines(buttonTier, buttonColumn, tier, column, requirementsMet)
    requirementsMet = requirementsMet and 1 or -1
    if buttonColumn == column then
        if buttonTier - tier > 1 then
            for i = tier + 1, buttonTier - 1 do
                if branchArray[i][buttonColumn].id then
                    return -- blocked vertically
                end
            end
        end
        for i = tier, buttonTier - 1 do
            branchArray[i][buttonColumn].down = requirementsMet
            if i + 1 <= buttonTier - 1 then
                branchArray[i + 1][buttonColumn].up = requirementsMet
            end
        end
        branchArray[buttonTier][buttonColumn].topArrow = requirementsMet
        return
    end
    if buttonTier == tier then
        local left, right = math.min(buttonColumn, column), math.max(buttonColumn, column)
        if right - left > 1 then
            for i = left + 1, right - 1 do
                if branchArray[tier][i].id then
                    return -- blocked
                end
            end
        end
        for i = left, right - 1 do
            branchArray[tier][i].right = requirementsMet
            branchArray[tier][i + 1].left = requirementsMet
        end
        if buttonColumn < column then
            branchArray[buttonTier][buttonColumn].rightArrow = requirementsMet
        else
            branchArray[buttonTier][buttonColumn].leftArrow = requirementsMet
        end
        return
    end
    -- diagonal
    local left, right = math.min(buttonColumn, column), math.max(buttonColumn, column)
    if left == column then
        left = left + 1
    else
        right = right - 1
    end
    local blocked = false
    for i = left, right do
        if branchArray[tier][i].id then
            blocked = true
        end
    end
    left, right = math.min(buttonColumn, column), math.max(buttonColumn, column)
    if not blocked then
        branchArray[tier][buttonColumn].down = requirementsMet
        branchArray[buttonTier][buttonColumn].up = requirementsMet
        for i = tier, buttonTier - 1 do
            branchArray[i][buttonColumn].down = requirementsMet
            branchArray[i + 1][buttonColumn].up = requirementsMet
        end
        for i = left, right - 1 do
            branchArray[tier][i].right = requirementsMet
            branchArray[tier][i + 1].left = requirementsMet
        end
        branchArray[buttonTier][buttonColumn].topArrow = requirementsMet
        return
    end
    if left == buttonColumn then
        left = left + 1
    else
        right = right - 1
    end
    for i = left, right do
        if branchArray[buttonTier][i].id then
            return -- undrawable
        end
    end
    for i = tier, buttonTier - 1 do
        branchArray[i][column].up = requirementsMet
        branchArray[i + 1][column].down = requirementsMet
    end
    if buttonColumn < column then
        branchArray[buttonTier][buttonColumn].rightArrow = requirementsMet
    else
        branchArray[buttonTier][buttonColumn].leftArrow = requirementsMet
    end
end

local branchIndex, arrowIndex

local function setBranch(coords, x, y)
    local texture = frame.branches[branchIndex]
    branchIndex = branchIndex + 1
    if not texture then
        return
    end
    texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", frame.ScrollChild, "TOPLEFT", x, y)
    texture:Show()
end

local function setArrow(coords, x, y)
    local texture = frame.arrows[arrowIndex]
    arrowIndex = arrowIndex + 1
    if not texture then
        return
    end
    texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", frame.ArrowFrame, "TOPLEFT", x, y)
    texture:Show()
end

local function drawBranches()
    branchIndex, arrowIndex = 1, 1
    local ignoreUp = false
    for i = 1, MAX_TIERS do
        for j = 1, NUM_COLUMNS do
            local node = branchArray[i][j]
            local xOffset = (j - 1) * STRIDE + INITIAL_OFFSET_X + 2
            local yOffset = -((i - 1) * STRIDE) - INITIAL_OFFSET_Y - 2
            if node.id then
                if node.up ~= 0 then
                    if not ignoreUp then
                        setBranch(BRANCH_COORDS.up[node.up], xOffset, yOffset + BUTTON_SIZE)
                    else
                        ignoreUp = false
                    end
                end
                if node.down ~= 0 then
                    setBranch(BRANCH_COORDS.down[node.down], xOffset, yOffset - BUTTON_SIZE + 1)
                end
                if node.left ~= 0 then
                    setBranch(BRANCH_COORDS.left[node.left], xOffset - BUTTON_SIZE, yOffset)
                end
                if node.right ~= 0 then
                    local tempNode = branchArray[i][j + 1]
                    if tempNode and tempNode.left ~= 0 and tempNode.down < 0 then
                        setBranch(BRANCH_COORDS.right[tempNode.down], xOffset + BUTTON_SIZE, yOffset)
                    else
                        setBranch(BRANCH_COORDS.right[node.right], xOffset + BUTTON_SIZE + 1, yOffset)
                    end
                end
                if node.rightArrow ~= 0 then
                    setArrow(ARROW_COORDS.right[node.rightArrow], xOffset + BUTTON_SIZE / 2 + 5, yOffset)
                end
                if node.leftArrow ~= 0 then
                    setArrow(ARROW_COORDS.left[node.leftArrow], xOffset - BUTTON_SIZE / 2 - 5, yOffset)
                end
                if node.topArrow ~= 0 then
                    setArrow(ARROW_COORDS.top[node.topArrow], xOffset, yOffset + BUTTON_SIZE / 2 + 5)
                end
            else
                if node.up ~= 0 and node.left ~= 0 and node.right ~= 0 then
                    setBranch(BRANCH_COORDS.tup[node.up], xOffset, yOffset)
                elseif node.down ~= 0 and node.left ~= 0 and node.right ~= 0 then
                    setBranch(BRANCH_COORDS.tdown[node.down], xOffset, yOffset)
                elseif node.left ~= 0 and node.down ~= 0 then
                    setBranch(BRANCH_COORDS.topright[node.left], xOffset, yOffset)
                    setBranch(BRANCH_COORDS.down[node.down], xOffset, yOffset - 32)
                elseif node.left ~= 0 and node.up ~= 0 then
                    setBranch(BRANCH_COORDS.bottomright[node.left], xOffset, yOffset)
                elseif node.left ~= 0 and node.right ~= 0 then
                    setBranch(BRANCH_COORDS.right[node.right], xOffset + BUTTON_SIZE, yOffset)
                    setBranch(BRANCH_COORDS.left[node.left], xOffset + 1, yOffset)
                elseif node.right ~= 0 and node.down ~= 0 then
                    setBranch(BRANCH_COORDS.topleft[node.right], xOffset, yOffset)
                    setBranch(BRANCH_COORDS.down[node.down], xOffset, yOffset - 32)
                elseif node.right ~= 0 and node.up ~= 0 then
                    setBranch(BRANCH_COORDS.bottomleft[node.right], xOffset, yOffset)
                elseif node.up ~= 0 and node.down ~= 0 then
                    setBranch(BRANCH_COORDS.up[node.up], xOffset, yOffset)
                    setBranch(BRANCH_COORDS.down[node.down], xOffset, yOffset - 32)
                    ignoreUp = true
                end
            end
        end
    end
    for i = branchIndex, MAX_BRANCHES do
        frame.branches[i]:Hide()
    end
    for i = arrowIndex, MAX_ARROWS do
        frame.arrows[i]:Hide()
    end
end

---------------------------------------------------------------------------
-- Learning
---------------------------------------------------------------------------
local function reportError(text)
    if UIErrorsFrame and text then
        UIErrorsFrame:AddMessage(text, 1, 0.1, 0.1, 1)
    end
end

local function canEdit()
    if C_ClassTalents and C_ClassTalents.CanEditTalents then
        local ok, why = C_ClassTalents.CanEditTalents()
        if not ok then
            return false, why
        end
    end
    return true
end

-- Commit what is staged: the 2006 talent was learned the moment it was
-- clicked, so every purchase is followed by a commit.
local function commit()
    if C_Traits.IsReadyForCommit and not C_Traits.IsReadyForCommit() then
        return false
    end
    if C_ClassTalents and C_ClassTalents.CommitConfig then
        return C_ClassTalents.CommitConfig() == true
    end
    return C_Traits.CommitConfig(configID) == true
end

local function learn(node)
    if not configID or not node then
        return
    end
    if InCombatLockdown() then
        reportError(ERR_NOT_IN_COMBAT or "You can't do that while in combat")
        return
    end
    local ok, why = canEdit()
    if not ok then
        reportError(why)
        return
    end
    local nodeInfo = C_Traits.GetNodeInfo(configID, node.nodeID)
    if not nodeInfo or not nodeInfo.canPurchaseRank then
        return
    end
    if not C_Traits.PurchaseRank(configID, node.nodeID) then
        return
    end
    sound(SOUNDKIT and SOUNDKIT.UI_CLASS_TALENT_NODE_SPEND)
    if not commit() then
        ns.Print("the talent point is placed but not learned yet; click Apply when the game allows it")
    end
    Talents.Update()
end

-- A staged (not yet applied) point can be taken back with a right click.
local function unlearnStaged(node)
    if not configID or not node or InCombatLockdown() then
        return
    end
    local nodeInfo = C_Traits.GetNodeInfo(configID, node.nodeID)
    if nodeInfo and nodeInfo.canRefundRank and C_Traits.RefundRank(configID, node.nodeID) then
        Talents.Update()
    end
end

local function hasStagedChanges()
    return configID ~= nil
        and C_Traits.ConfigHasStagedChanges ~= nil
        and C_Traits.ConfigHasStagedChanges(configID) == true
end

---------------------------------------------------------------------------
-- Tooltip (GameTooltip:SetTalent 1.12: name, rank, description, next rank)
---------------------------------------------------------------------------
local function description(entryID, rank)
    if not entryID or rank < 1 or not C_Traits.GetTraitDescription then
        return nil
    end
    local ok, text = pcall(C_Traits.GetTraitDescription, entryID, rank)
    if ok and type(text) == "string" and text ~= "" then
        return text
    end
    return nil
end

local function conditionLines(node, tree)
    local lines = {}
    local seen = {}
    local ids = {}
    for _, id in ipairs(node.info.conditionIDs or {}) do
        ids[#ids + 1] = id
    end
    for _, id in ipairs(node.entry and node.entry.conditionIDs or {}) do
        ids[#ids + 1] = id
    end
    for _, condID in ipairs(ids) do
        if not seen[condID] then
            seen[condID] = true
            local ok, cond = pcall(C_Traits.GetConditionInfo, configID, condID)
            if ok and cond and not cond.isMet and not cond.isAlwaysMet and cond.tooltipFormat then
                local text = cond.tooltipFormat
                if cond.spentAmountRequired then
                    text = text:format(cond.spentAmountRequired, tree.name or "")
                elseif cond.playerLevel then
                    text = text:format(cond.playerLevel)
                end
                lines[#lines + 1] = text
            end
        end
    end
    return lines
end

local function showTooltip(button)
    local node, tree = button.node, trees[selectedTab]
    if not node then
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(node.name or UNKNOWN or "Unknown", 1, 1, 1)
    GameTooltip:AddLine(("Rank %d/%d"):format(node.rank, node.maxRank), 1, 1, 1)
    local current = description(node.entryID, math.max(node.rank, 1))
    if current then
        GameTooltip:AddLine(current, 1, 0.82, 0, true)
    end
    if node.rank > 0 and node.rank < node.maxRank then
        local nextText = description(node.entryID, node.rank + 1)
        if nextText then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Next rank:", 1, 1, 1)
            GameTooltip:AddLine(nextText, 1, 0.82, 0, true)
        end
    end
    for _, prereq in ipairs(node.prereqs) do
        if not prereq.active then
            GameTooltip:AddLine(
                ("Requires %d point%s in %s"):format(
                    prereq.node.maxRank,
                    prereq.node.maxRank == 1 and "" or "s",
                    prereq.node.name or "?"
                ),
                1,
                0.1,
                0.1
            )
        end
    end
    if tree then
        for _, line in ipairs(conditionLines(node, tree)) do
            GameTooltip:AddLine(line, 1, 0.1, 0.1, true)
        end
    end
    if node.info.canPurchaseRank and pointsLeft > 0 then
        GameTooltip:AddLine("Click to learn", 0.1, 1, 0.1)
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
local function createTalentButton(parent, index)
    local button = CreateFrame("Button", "FCUI_TalentFrameTalent" .. index, parent)
    button:SetSize(BUTTON, BUTTON)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- ItemButtonTemplate 1.12: icon fills the button, UI-Quickslot2 64x64 CENTER 0,-1
    button.Icon = button:CreateTexture(nil, "BORDER")
    button.Icon:SetAllPoints()
    button:SetNormalTexture(tex("normal"))
    local normal = button:GetNormalTexture()
    normal:ClearAllPoints()
    normal:SetSize(64, 64)
    normal:SetPoint("CENTER", button, "CENTER", 0, -1)
    button:SetPushedTexture(tex("pushed"))
    button:SetHighlightTexture(tex("highlight"), "ADD")
    -- TalentButtonTemplate: Slot (UI-EmptySlot-White 64x64 CENTER), RankBorder 32x32 at the
    -- bottom right corner, Rank text centred on it
    button.Slot = button:CreateTexture(nil, "BACKGROUND")
    button.Slot:SetTexture(tex("slot"))
    button.Slot:SetSize(64, 64)
    button.Slot:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.RankBorder = button:CreateTexture(nil, "OVERLAY")
    button.RankBorder:SetTexture(tex("rankBorder"))
    button.RankBorder:SetSize(32, 32)
    button.RankBorder:SetPoint("CENTER", button, "BOTTOMRIGHT", 0, 0)
    button.Rank = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.Rank:SetPoint("CENTER", button.RankBorder, "CENTER", 0, 0)
    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            unlearnStaged(self.node)
        else
            learn(self.node)
        end
    end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return button
end

-- CharacterFrameTabButtonTemplate 1.12: 20/88/20 px slices of UI-Character-InActiveTab,
-- the selected tab shows UI-Character-ActiveTab and sits 5 px lower
local function createTab(parent, id)
    local tab = CreateFrame("Button", "FCUI_TalentFrameTab" .. id, parent)
    tab:SetID(id)
    tab:SetSize(115, 32)
    tab.pieces = {}
    local coords = { { 0, 0.15625 }, { 0.15625, 0.84375 }, { 0.84375, 1.0 } }
    for state, file in pairs({ inactive = "tabInactive", active = "tabActive" }) do
        local pieces = {}
        for i = 1, 3 do
            local piece = tab:CreateTexture(nil, "BACKGROUND")
            piece:SetTexture(tex(file))
            piece:SetTexCoord(coords[i][1], coords[i][2], 0, 1)
            piece:SetHeight(32)
            pieces[i] = piece
        end
        pieces[1]:SetWidth(20)
        pieces[3]:SetWidth(20)
        pieces[1]:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, state == "active" and 5 or 0)
        pieces[2]:SetPoint("LEFT", pieces[1], "RIGHT")
        pieces[3]:SetPoint("LEFT", pieces[2], "RIGHT")
        tab.pieces[state] = pieces
    end
    tab.Text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tab.Text:SetPoint("CENTER", tab, "CENTER", 0, 2)
    tab:SetHighlightTexture(tex("highlight"), "ADD")
    tab:GetHighlightTexture():SetPoint("TOPLEFT", tab, "TOPLEFT", 8, -4)
    tab:GetHighlightTexture():SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -8, 4)
    tab:SetScript("OnClick", function(self)
        selectedTab = self:GetID()
        sound(SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB)
        Talents.Update()
    end)
    return tab
end

local function layoutTab(tab, name, selected)
    tab.Text:SetText(name)
    -- PanelTemplates_TabResize(10, tab): text width plus padding, 20 px end pieces
    local width = math.max(60, math.floor(tab.Text:GetStringWidth() + 10 + 40))
    tab:SetWidth(width)
    tab.pieces.inactive[2]:SetWidth(width - 40)
    tab.pieces.active[2]:SetWidth(width - 40)
    for _, piece in ipairs(tab.pieces.inactive) do
        piece:SetShown(not selected)
    end
    for _, piece in ipairs(tab.pieces.active) do
        piece:SetShown(selected)
    end
    tab.Text:SetPoint("CENTER", tab, "CENTER", 0, selected and -2 or 2)
    if selected then
        tab.Text:SetFontObject(GameFontHighlightSmall)
    else
        tab.Text:SetFontObject(GameFontNormalSmall)
    end
end

local function createPanelButton(parent, text, width)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, 22)
    button:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    button:GetNormalTexture():SetTexCoord(0, 0.625, 0, 0.6875)
    button:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
    button:GetPushedTexture():SetTexCoord(0, 0.625, 0, 0.6875)
    button:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight", "ADD")
    button:GetHighlightTexture():SetTexCoord(0, 0.625, 0, 0.6875)
    button:SetNormalFontObject(GameFontNormalSmall)
    button:SetHighlightFontObject(GameFontHighlightSmall)
    button:SetDisabledFontObject(GameFontDisableSmall)
    button:SetText(text)
    return button
end

local function createFrame()
    frame = CreateFrame("Frame", "FCUI_TalentFrame", UIParent)
    frame:SetSize(384, 512)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -104)
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:Hide()

    toggleButton = CreateFrame("Button", "FCUI_TalentFrameToggle", UIParent)
    toggleButton:Hide()
    toggleButton:SetScript("OnClick", function()
        Talents.Toggle()
    end)

    -- Blizzard_TalentUI.xml chrome
    local function chrome(key, width, height, point, x, y)
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetTexture(tex(key))
        t:SetSize(width, height)
        t:SetPoint(point, frame, point, x, y)
        ns.Dark.Tint(t)
        return t
    end
    chrome("topLeft", 256, 256, "TOPLEFT", 2, -1)
    chrome("topRight", 128, 256, "TOPRIGHT", 2, -1)
    chrome("botLeft", 256, 256, "BOTTOMLEFT", 2, -1)
    chrome("botRight", 128, 256, "BOTTOMRIGHT", 2, -1)

    frame.Portrait = frame:CreateTexture(nil, "BACKGROUND")
    frame.Portrait:SetSize(60, 60)
    frame.Portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -6)

    -- tree painting: 256x256 at 23,-77, 64 wide strip right of it, 128 tall strip below
    frame.Background = {}
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(256, 256)
    bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 23, -77)
    frame.Background.topLeft = bg
    bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(64, 256)
    bg:SetPoint("TOPLEFT", frame.Background.topLeft, "TOPRIGHT", 0, 0)
    frame.Background.topRight = bg
    bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(256, 128)
    bg:SetPoint("TOPLEFT", frame.Background.topLeft, "BOTTOMLEFT", 0, 0)
    frame.Background.bottomLeft = bg
    bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(64, 128)
    bg:SetPoint("TOPLEFT", frame.Background.topLeft, "BOTTOMRIGHT", 0, 0)
    frame.Background.bottomRight = bg
    for _, texture in pairs(frame.Background) do
        ns.Dark.Tint(texture)
    end

    frame.Title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.Title:SetPoint("TOP", frame, "TOP", 0, -18)
    frame.Title:SetText(TALENTS or "Talents")

    -- points spent box: Common-Input-Border 8 + 248 + 8 x 20 at 75,-48
    local left = frame:CreateTexture(nil, "ARTWORK")
    left:SetTexture(tex("inputBorder"))
    left:SetSize(8, 20)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 75, -48)
    left:SetTexCoord(0, 0.0625, 0, 0.625)
    local middle = frame:CreateTexture(nil, "ARTWORK")
    middle:SetTexture(tex("inputBorder"))
    middle:SetSize(248, 20)
    middle:SetPoint("LEFT", left, "RIGHT")
    middle:SetTexCoord(0.0625, 0.9375, 0, 0.625)
    local right = frame:CreateTexture(nil, "ARTWORK")
    right:SetTexture(tex("inputBorder"))
    right:SetSize(8, 20)
    right:SetPoint("LEFT", middle, "RIGHT")
    right:SetTexCoord(0.9375, 1, 0, 0.625)
    frame.SpentPoints = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.SpentPoints:SetPoint("TOP", middle, "TOP", 0, -5)

    frame.PointsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.PointsText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 252, 87)
    frame.PointsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.PointsLabel:SetPoint("RIGHT", frame.PointsText, "LEFT", -3, 0)
    frame.PointsLabel:SetText(CHARACTER_POINTS1_COLON or "Talent Points:")

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(32, 32)
    close:SetPoint("CENTER", frame, "TOPRIGHT", -44, -25)
    close:SetNormalTexture(tex("closeUp"))
    close:SetPushedTexture(tex("closeDown"))
    close:SetHighlightTexture(tex("closeHighlight"), "ADD")
    close:SetScript("OnClick", function()
        Talents.Toggle()
    end)

    frame.Cancel = createPanelButton(frame, CLOSE or "Close", 80)
    frame.Cancel:SetPoint("CENTER", frame, "TOPLEFT", 305, -420)
    frame.Cancel:SetScript("OnClick", function()
        Talents.Toggle()
    end)
    -- not 1.12: only shown while a point is placed but the game has not applied it yet
    frame.Apply = createPanelButton(frame, "Apply", 80)
    frame.Apply:SetPoint("RIGHT", frame.Cancel, "LEFT", -4, 0)
    frame.Apply:SetScript("OnClick", function()
        if InCombatLockdown() then
            reportError(ERR_NOT_IN_COMBAT or "You can't do that while in combat")
            return
        end
        if not commit() then
            reportError("The game did not accept the talents yet, try again in a moment")
        end
        Talents.Update()
    end)
    frame.Apply:Hide()

    -- scroll frame 296x332 at TOPRIGHT -65,-77; the classic bar art behind Blizzard's scroll bar
    local scroll = CreateFrame("ScrollFrame", "FCUI_TalentFrameScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scroll:SetSize(296, 332)
    scroll:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -65, -77)
    frame.Scroll = scroll
    local barTop = frame:CreateTexture(nil, "ARTWORK")
    barTop:SetTexture(tex("scrollBar"))
    barTop:SetSize(31, 256)
    barTop:SetPoint("TOPLEFT", scroll, "TOPRIGHT", -2, 5)
    barTop:SetTexCoord(0, 0.484375, 0, 1)
    local barBottom = frame:CreateTexture(nil, "ARTWORK")
    barBottom:SetTexture(tex("scrollBar"))
    barBottom:SetSize(31, 106)
    barBottom:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", -2, -2)
    barBottom:SetTexCoord(0.515625, 1, 0, 0.4140625)
    ns.Dark.Tint(barTop)
    ns.Dark.Tint(barBottom)

    local child = CreateFrame("Frame", "FCUI_TalentFrameScrollChild", scroll)
    child:SetSize(320, 50)
    scroll:SetScrollChild(child)
    frame.ScrollChild = child

    frame.branches = {}
    for i = 1, MAX_BRANCHES do
        local branch = child:CreateTexture(nil, "BORDER")
        branch:SetTexture(tex("branches"))
        branch:SetSize(32, 32)
        branch:Hide()
        frame.branches[i] = branch
    end
    frame.buttons = {}
    for i = 1, NUM_COLUMNS * MAX_TIERS do
        local button = createTalentButton(child, i)
        button:Hide()
        frame.buttons[i] = button
    end
    frame.ArrowFrame = CreateFrame("Frame", nil, child)
    frame.ArrowFrame:SetAllPoints(child)
    frame.ArrowFrame:SetFrameLevel(child:GetFrameLevel() + 5)
    frame.arrows = {}
    for i = 1, MAX_ARROWS do
        local arrow = frame.ArrowFrame:CreateTexture(nil, "OVERLAY")
        arrow:SetTexture(tex("arrows"))
        arrow:SetSize(32, 32)
        arrow:Hide()
        frame.arrows[i] = arrow
    end

    frame.tabs = {}
    for id = 1, 3 do
        local tab = createTab(frame, id)
        if id == 1 then
            tab:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 46)
        else
            tab:SetPoint("LEFT", frame.tabs[id - 1], "RIGHT", -15, 0)
        end
        frame.tabs[id] = tab
    end

    frame:SetScript("OnShow", function()
        sound(SOUNDKIT and (SOUNDKIT.TALENT_SCREEN_OPEN or SOUNDKIT.IG_CHARACTER_INFO_OPEN))
        Talents.Rebuild()
        Talents.Update()
        if ns.ActionBars and ns.ActionBars.MicroMenu and ns.ActionBars.MicroMenu.UpdateOwnStates then
            ns.ActionBars.MicroMenu.UpdateOwnStates()
        end
    end)
    frame:SetScript("OnHide", function()
        sound(SOUNDKIT and (SOUNDKIT.TALENT_SCREEN_CLOSE or SOUNDKIT.IG_CHARACTER_INFO_CLOSE))
        if ns.ActionBars and ns.ActionBars.MicroMenu and ns.ActionBars.MicroMenu.UpdateOwnStates then
            ns.ActionBars.MicroMenu.UpdateOwnStates()
        end
    end)
    table.insert(UISpecialFrames, "FCUI_TalentFrame")
end

---------------------------------------------------------------------------
-- Update (TalentFrame_Update 1.12)
---------------------------------------------------------------------------
local function backgroundBase()
    local _, classFile = UnitClass("player")
    local list = BACKGROUNDS[classFile or ""]
    return list and list[selectedTab] or DEFAULT_BACKGROUND
end

function Talents.Update()
    if not frame or not frame:IsShown() then
        return
    end
    SetPortraitTexture(frame.Portrait, "player")

    for id, tab in ipairs(frame.tabs) do
        local tree = trees[id]
        if tree then
            layoutTab(tab, tree.name or ("Tree " .. id), id == selectedTab)
            tab:Show()
        else
            tab:Hide()
        end
    end

    local tree = trees[selectedTab]
    local raw = backgroundBase()
    -- the import manifest lists the base name; the client is asked for the first piece
    if ns.Assets.HasMedia(raw) or ns.Compat.TextureExists(raw .. "-TopLeft") then
        local base = ns.Assets.Resolve(raw)
        frame.Background.topLeft:SetTexture(base .. "-TopLeft")
        frame.Background.topRight:SetTexture(base .. "-TopRight")
        frame.Background.bottomLeft:SetTexture(base .. "-BottomLeft")
        frame.Background.bottomRight:SetTexture(base .. "-BottomRight")
    else
        -- painting not on this machine yet (see tools/import_blizzard_art.py): plain dark board
        for _, texture in pairs(frame.Background) do
            texture:SetColorTexture(0.05, 0.05, 0.05, 0.8)
        end
    end

    frame.PointsText:SetText(pointsLeft)
    if tree then
        local spentFormat = MASTERY_POINTS_SPENT or "Points spent in %s Talents:"
        frame.SpentPoints:SetText(spentFormat:format(tree.name or "") .. " |cffffffff" .. tree.spent .. "|r")
    else
        frame.SpentPoints:SetText("")
    end
    frame.Apply:SetShown(hasStagedChanges())

    resetBranches()
    local used = 0
    local maxTier = 1
    if tree then
        for _, node in ipairs(tree.nodes) do
            used = used + 1
            local button = frame.buttons[used]
            if not button then
                break
            end
            button.node = node
            button:ClearAllPoints()
            button:SetPoint(
                "TOPLEFT",
                frame.ScrollChild,
                "TOPLEFT",
                (node.column - 1) * STRIDE + INITIAL_OFFSET_X,
                -((node.tier - 1) * STRIDE) - INITIAL_OFFSET_Y
            )
            maxTier = math.max(maxTier, node.tier)
            branchArray[node.tier][node.column].id = node.nodeID
            button.Icon:SetTexture(node.icon)
            button.Rank:SetText(node.rank)

            -- TalentFrame_Update: green while learnable and not maxed, gold when maxed,
            -- grey when the tier, points or prerequisites are missing
            local info = node.info
            local learnable = info.canPurchaseRank == true
            local available = learnable or node.rank > 0
            if available then
                button.Icon:SetDesaturated(false)
                button.Icon:SetVertexColor(1, 1, 1)
                if node.rank < node.maxRank then
                    button.Slot:SetVertexColor(0.1, 1.0, 0.1)
                    button.Rank:SetTextColor(0.1, 1.0, 0.1)
                else
                    button.Slot:SetVertexColor(1.0, 0.82, 0)
                    button.Rank:SetTextColor(1.0, 0.82, 0)
                end
                button.RankBorder:SetVertexColor(1, 1, 1)
                button.RankBorder:Show()
                button.Rank:Show()
            else
                button.Icon:SetDesaturated(true)
                button.Icon:SetVertexColor(0.65, 0.65, 0.65)
                button.Slot:SetVertexColor(0.5, 0.5, 0.5)
                if node.rank == 0 then
                    button.RankBorder:Hide()
                    button.Rank:Hide()
                else
                    button.RankBorder:SetVertexColor(0.5, 0.5, 0.5)
                    button.Rank:SetTextColor(0.5, 0.5, 0.5)
                    button.RankBorder:Show()
                    button.Rank:Show()
                end
            end
            button:Show()
        end
        -- prerequisite lines, drawn after every id is placed
        for _, node in ipairs(tree.nodes) do
            for _, prereq in ipairs(node.prereqs) do
                local met = prereq.active and (node.info.canPurchaseRank == true or node.rank > 0)
                drawLines(node.tier, node.column, prereq.node.tier, prereq.node.column, met)
            end
        end
    end
    for i = used + 1, #frame.buttons do
        frame.buttons[i]:Hide()
        frame.buttons[i].node = nil
    end
    frame.ScrollChild:SetHeight(math.max(50, maxTier * STRIDE + INITIAL_OFFSET_Y))
    drawBranches()

    for _, button in ipairs(frame.buttons) do
        if button:IsShown() and GameTooltip:IsOwned(button) then
            showTooltip(button)
        end
    end
end

---------------------------------------------------------------------------
-- Bindings, micro button, lifecycle
---------------------------------------------------------------------------
local function updateBindings()
    if not toggleButton then
        return
    end
    Combat.Run("talents:bindings", function()
        ClearOverrideBindings(toggleButton)
        local key1, key2 = GetBindingKey("TOGGLETALENTS")
        for _, key in ipairs({ key1, key2 }) do
            if key then
                SetOverrideBindingClick(toggleButton, true, key, toggleButton:GetName())
            end
        end
    end)
end

function Talents:Init()
    if not artAvailable() then
        error("Interface\\TalentFrame\\UI-TalentFrame-BotLeft is not available; run tools/import_blizzard_art.py")
    end
    if not C_Traits or not C_Traits.GetNodeInfo or not C_ClassTalents then
        error("C_Traits / C_ClassTalents API missing")
    end
    createFrame()
end

function Talents:Enable()
    updateBindings()
    ns.RegisterEvent("UPDATE_BINDINGS", self, updateBindings)
    local function refresh()
        if frame and frame:IsShown() then
            Talents.Rebuild()
            Talents.Update()
        end
    end
    for _, event in ipairs({
        "TRAIT_CONFIG_UPDATED",
        "TRAIT_NODE_CHANGED",
        "TRAIT_NODE_CHANGED_PARTIAL",
        "TRAIT_NODE_ENTRY_UPDATED",
        "TRAIT_TREE_CURRENCY_INFO_UPDATED",
        "TRAIT_TREE_CHANGED",
        "ACTIVE_COMBAT_CONFIG_CHANGED",
        "PLAYER_TALENT_UPDATE",
        "PLAYER_LEVEL_UP",
        "PLAYER_ENTERING_WORLD",
    }) do
        ns.RegisterEvent(event, self, refresh)
    end
    ns.RegisterEvent("CONFIG_COMMIT_FAILED", self, function()
        ns.Print("the game could not apply the talents; the point stays placed, click Apply to try again")
        refresh()
    end)
    ns.RegisterEvent("UNIT_PORTRAIT_UPDATE", self, function(_, _, unit)
        if unit == "player" and frame and frame:IsShown() then
            SetPortraitTexture(frame.Portrait, "player")
        end
    end)
end

function Talents:Disable()
    ns.UnregisterAllEvents(self)
    if frame then
        frame:Hide()
    end
    if toggleButton then
        Combat.Run("talents:bindings", function()
            ClearOverrideBindings(toggleButton)
        end)
    end
    ns.Print("Talents disabled, /reload to restore the Blizzard talent window")
end

-- module lifecycle (the data loader is Talents.Rebuild)
function Talents:Refresh()
    if frame and frame:IsShown() then
        Talents.Rebuild()
        Talents.Update()
    end
end

function Talents.Toggle()
    if not frame then
        return
    end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

function Talents.IsShown()
    return frame ~= nil and frame:IsShown()
end

function Talents:Diag()
    Talents.Rebuild()
    ns.Print(
        "  window=%s shown=%s config=%s (%s) tree=%s trees=%d points=%d tab=%d staged=%s",
        tostring(frame ~= nil),
        tostring(frame and frame:IsShown()),
        tostring(configID),
        Talents.configSource,
        tostring(treeID),
        #trees,
        pointsLeft,
        selectedTab,
        tostring(hasStagedChanges())
    )
    if treeID then
        local nodes = C_Traits.GetTreeNodes(treeID) or {}
        local groups = C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}
        ns.Print("  tree nodes=%d groups=%d", #nodes, #groups)
    end
    for index, tree in ipairs(trees) do
        local columns, tiers = 0, 0
        for _, node in ipairs(tree.nodes) do
            columns = math.max(columns, node.column)
            tiers = math.max(tiers, node.tier)
        end
        ns.Print(
            "  tree %d %s: %d talents, %d spent, grid %dx%d",
            index,
            tostring(tree.name),
            #tree.nodes,
            tree.spent,
            columns,
            tiers
        )
    end
end
