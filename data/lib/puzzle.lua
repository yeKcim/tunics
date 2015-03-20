local Tree = require 'lib/tree'
local List = require 'lib/list'

local HideTreasuresVisitor = {}

setmetatable(HideTreasuresVisitor, HideTreasuresVisitor)

function HideTreasuresVisitor:visit_room(room)
    room:each_child(function (key, child)
        if child.class == 'Treasure' and child.open ~= 'bigkey' then
            room:update_child(key, child:with_needs{see='compass'})
        end
        child:accept(self)
    end)
end
function HideTreasuresVisitor:visit_treasure(treasure)
end
function HideTreasuresVisitor:visit_enemy(enemy)
end

local KeyDetectorVisitor = {}

setmetatable(KeyDetectorVisitor, KeyDetectorVisitor)

function KeyDetectorVisitor:visit_room(room)
    local has_keys = false
    room:each_child(function (key, child)
        if not has_keys then
            has_keys = child:accept(self)
        end
    end)
    return has_keys
end

function KeyDetectorVisitor:visit_treasure(treasure)
    if treasure.name == 'smallkey' then
        return true
    else
        return false
    end
end

function KeyDetectorVisitor:visit_enemy(enemy)
    return false
end

local Puzzle = {}

function Puzzle.treasure_step(item_name)
    return function (root)
        root:add_child(Tree.Treasure:new{name=item_name})
    end
end

function Puzzle.boss_step(root)
    root:add_child(Tree.Enemy:new{name='boss'}:with_needs{open='bigkey'})
end

function Puzzle.hide_treasures_step(root)
    root:accept(HideTreasuresVisitor)
end

function Puzzle.obstacle_step(item_name)
    return function (root)
        root:each_child(function (key, head)
            root:update_child(key, head:with_needs{reach=item_name})
        end)
    end
end

function Puzzle.big_chest_step(item_name)
    return function (root)
        root:add_child(Tree.Treasure:new{name=item_name, open='bigkey'})
    end
end

function Puzzle.bomb_doors_step(root)
    root:each_child(function (key, head)
        root:update_child(key, head:with_needs{see='map',open='bomb'})
    end)
end

function Puzzle.locked_door_step(rng, root)
    function lockable_weight(node)
        local has_keys = node:accept(KeyDetectorVisitor)
        if has_keys then
            return 0
        else
            return 1
        end
    end
    local key, child = root:random_child(rng, lockable_weight)
    if key then
        root:update_child(key, child:with_needs{open='smallkey'})
        return true
    else
        return false
    end
end

function Puzzle.max_heads(rng, n)
    return function (root)
        while #root.children > n do
            local fork = Tree.Room:new()
            fork:merge_child(root:remove_child(root:random_child(rng)))
            fork:merge_child(root:remove_child(root:random_child(rng)))
            root:add_child(fork)
        end
    end
end

function Puzzle.compass_puzzle()
    return {
        Puzzle.hide_treasures_step,
        Puzzle.treasure_step('compass'),
    }
end

function Puzzle.map_puzzle(rng)
    local steps = {
        Puzzle.treasure_step('bomb'),
        Puzzle.treasure_step('map'),
    }
    List.shuffle(rng, steps)
    table.insert(steps, 1, Puzzle.bomb_doors_step)
    return steps
end

function Puzzle.items_puzzle(rng, item_names)
    List.shuffle(rng, item_names)
    local steps = {}
    for _, item_name in ipairs(item_names) do
        table.insert(steps, Puzzle.obstacle_step(item_name))
        table.insert(steps, Puzzle.big_chest_step(item_name))
    end
    table.insert(steps, Puzzle.treasure_step('bigkey'))
    return steps
end

function Puzzle.lock_puzzle(rng)
    return {
        function (root)
            if Puzzle.locked_door_step(rng, root) then
                Puzzle.treasure_step('smallkey')(root)
            end
        end,
    }
end

function Puzzle.alpha_dungeon(rng, nkeys, item_names)
    local puzzles = {
        Puzzle.items_puzzle(rng:create(), item_names),
        --Puzzle.map_puzzle(rng:create()),
        --Puzzle.compass_puzzle(),
    }
    for i = 1, nkeys do
        --table.insert(puzzles, Puzzle.lock_puzzle(rng:create()))
    end
    List.shuffle(rng:create(), puzzles)

    local my_rng = rng:create()
    local steps = {}
    for _, puzzle in ipairs(puzzles) do
        local n = my_rng:random(3)
        if n == 1 then
            steps = List.intermingle(rng:create(), steps, puzzle)
        else
            steps = List.concat(steps, puzzle)
        end
    end
    table.insert(steps, 1, Puzzle.boss_step)

    local root = Tree.Room:new()
    for i, step in ipairs(steps) do
        Puzzle.max_heads(rng:create(), 3)(root)
        step(root)
    end
    root:each_child(function (key, child)
        if child.class ~= 'Room' then
            local room = Tree.Room:new()
            room:add_child(child)
            root:update_child(key, room)
        end
    end)
    root.open = 'entrance'
    return root
end

return Puzzle
