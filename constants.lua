-- constants.lua
-- Centralized gameplay constants for easy tuning

local C = {}

-- Customer
C.CUSTOMER_SPEED = 60
C.CUSTOMER_MONEY = 3
C.CUSTOMER_SPAWN_INTERVAL = 6

-- Barack & Robot (new mechanics)
C.BARACK_COST = {
    wood = 0,
    stone = 0,
    metal = 0
}
C.ROBOT_SPAWN_COST = {
    wood = 1,
    stone = 1,
    metal = 1
}
C.ROBOT_SPEED = 60
C.ROBOT_SIZE = 16

-- Flag System (robot pathing/command)
C.FLAG_COMMAND_RADIUS = 25        -- How close a robot must be to a command flag to recognize and execute it
C.DIR_FLAG_DEFAULT_DISTANCE = 200 -- Default distance (in pixels) for direction flags ("arrow" flags)

-- Flag HP per type (flags are now destructible by enemies)
C.FLAG_HP = {
    dir = 10,
    chop_wood = 10,
    collect_wood = 10,
    splitter = 10,
    build_something = 10,
    -- Add more flag types and their HP values as needed.
}

-- Flag priorities: higher means higher precedence when multiple flags are within range.
C.FLAG_PRIORITIES = {
    -- Directional flags (can further customize each if needed)
    dir_up = 1,
    dir_down = 1,
    dir_left = 1,
    dir_right = 1,
    -- Command flags
    chop_wood = 2,
    collect_wood = 2,
    build_something = 2,
    splitter = 1
}

-- Enemy
C.ENEMY_SPEED = 80
C.ENEMY_HEALTH = 3
C.ENEMY_WAVE_SIZE = 5

-- Controls resources dropped when an enemy dies
-- Example: { {type = "coin", amount = 1}, {type = "wood", amount = 2} }
C.ENEMY_DEATH_DROPS = {}

-- Controls resources dropped when a robot self-destructs
-- Example: { {type = "coin", amount = 1}, {type = "wood", amount = 2} }
C.ROBOT_DEATH_DROPS = {}

C.ENEMY_RESOURCE_DROP = 0 -- deprecated; use ENEMY_DEATH_DROPS
C.ENEMY_MONEY_DROP = 1    -- deprecated; use ENEMY_DEATH_DROPS
C.ENEMY_TOWER_DAMAGE = 1
C.ENEMY_RESOURCE_DAMAGE = 1

-- Resources
C.RESOURCE_MAX_HP = {
    wood = 5,
    grass = 5,
    stone = 5,
    metal = 5
}

C.RESOURCE_RESPAWN_TIME = {
    wood = 5,
    grass = 7,
    stone = 10,
    metal = 15
}

-- Towers
C.TOWER_COST = {
    charged = { coin = 1, wood = 2 },
    auto = { wood = 1, grass = 2 }
}
C.TOWER_HP = 30
C.TOWER_RANGE = 64
C.TOWER_FIRE_RATE = 0.5
C.TOWER_RADIUS = 64
C.TOWER_DAMAGE = { wood = 1, grass = 2, stone = 3, metal = 4, coin = 10 }

C.MAX_CARRY = 10

C.CUSTOMER_EXCHANGES = {
    { want = 'wood',  want_amount = 1, offer = 'coin',  offer_amount = 2 },
    { want = 'coin',  want_amount = 1, offer = 'wood',  offer_amount = 1 },
    { want = 'stone', want_amount = 2, offer = 'coin',  offer_amount = 1 },
    { want = 'coin',  want_amount = 1, offer = 'stone', offer_amount = 2 },
    { want = 'metal', want_amount = 1, offer = 'coin',  offer_amount = 3 },
    { want = 'coin',  want_amount = 3, offer = 'metal', offer_amount = 1 },
    { want = 'grass', want_amount = 1, offer = 'coin',  offer_amount = 1 },
    { want = 'coin',  want_amount = 2, offer = 'wood',  offer_amount = 1 },
    { want = 'coin',  want_amount = 1, offer = 'stone', offer_amount = 1 },
    { want = 'coin',  want_amount = 1, offer = 'metal', offer_amount = 1 },
    { want = 'coin',  want_amount = 1, offer = 'grass', offer_amount = 1 },
    { want = 'wood',  want_amount = 1, offer = 'stone', offer_amount = 2 },
    { want = 'stone', want_amount = 1, offer = 'wood',  offer_amount = 1 },
    { want = 'wood',  want_amount = 1, offer = 'stone', offer_amount = 1 },
    { want = 'metal', want_amount = 2, offer = 'grass', offer_amount = 2 },
    { want = 'grass', want_amount = 1, offer = 'metal', offer_amount = 1 },
}

-- Unified list of all resources (including coin as a true resource)
C.RESOURCE_TYPES = {
    { name = 'wood',  color = { 0.545, 0.27, 0.074 },  shape = 'square' },
    { name = 'grass', color = { 0.133, 0.545, 0.133 }, shape = 'square' },
    { name = 'stone', color = { 0.47, 0.47, 0.47 },    shape = 'square' },
    { name = 'metal', color = { 0.75, 0.75, 0.75 },    shape = 'square' },
    { name = 'coin',  color = { 1, 0.85, 0.2 },        shape = 'circle' },
}

return C
