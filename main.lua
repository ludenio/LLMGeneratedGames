-- main.lua
-- Love2D Tower Defense Resource Game
-- See README.md for up-to-date documentation and instructions.

require('tiledmap')

local C = require('constants')

local function add_log(msg)
    print(os.date('%H:%M:%S') .. ' ' .. msg)
end

-- Game settings
local TILE_SIZE = 16
local WIDTH, HEIGHT = 800, 600
local PLAYER_SIZE = 8
local PLAYER_COLOR = { 0.2, 0.8, 0.2 }
local BG_COLOR = { 0.12, 0.12, 0.12 }
local PLAYER_SPEED = 200
local ENEMY_SIZE = PLAYER_SIZE
local ENEMY_COLOR = { 0.78, 0.2, 0.2 }
local ENEMY_SPEED = C.ENEMY_SPEED
local ENEMY_HEALTH = C.ENEMY_HEALTH
local ENEMY_CHOP_TIME = 1.2 -- seconds to steal resource
local RESOURCE_TYPES = C.RESOURCE_TYPES
local RESOURCE_SIZE = TILE_SIZE
local RESOURCE_MAX_HP = C.RESOURCE_MAX_HP
local RESOURCE_RESPAWN_TIME = 5   -- seconds
local COLLECT_RADIUS = 24         -- smaller for 16x16 scale
local COLLECT_HIT_INTERVAL = 0.17 -- faster: 3 chops for default
local TOWER_COST = C.TOWER_COST
local TOWER_COIN_COST = C.TOWER_COST
local RESOURCE_DAMAGE = C.TOWER_DAMAGE
local TOWER_RANGE = C.TOWER_RANGE
local TOWER_FIRE_RATE = C.TOWER_FIRE_RATE
local BULLET_SPEED = 160 -- slower for scale
local CHECKOUT_ZONES = {}
local CUSTOMER_SIZE = PLAYER_SIZE
local CUSTOMER_COLOR = { 1, 0.9, 0.3 }
local CUSTOMER_SPEED = C.CUSTOMER_SPEED
local CUSTOMER_WAIT_TIME = 4 -- seconds
local CUSTOMER_SPAWN_INTERVAL = C.CUSTOMER_SPAWN_INTERVAL
local SELL_REWARD = 3        -- coins per resource
local UPGRADE_SHOPS = {}
local UPGRADE_COST = 20
local UPGRADE_COLOR = { 0.3, 0.7, 1 }
local has_upgrade = false
local ENEMY_ZONES = {}
local enemy_zone_triggered = false
local ENEMY_LINE_COUNT = C.ENEMY_WAVE_SIZE
local wave_number = 0
local wave_total = 0
local wave_alive = 0
local log_messages = {}
local LOG_MAX = 8
local debug_timer = 0
local next_raid_time = 0
local raid_countdown = 0
local raid_pending = false
local raid_message = nil
local RESOURCE_TO_CHECKOUT_TILE = {}

local logic = require('logic')

local camera = { x = 0, y = 0, scale = 2 } -- 2x zoom

local function dist(x1, y1, x2, y2)
    return logic.dist(x1, y1, x2, y2)
end

function remove_nearest_flag_or_barack()
    local px = player.x + player.size / 2
    local py = player.y + player.size / 2
    local best_dist, best_index, best_type = math.huge, nil, nil

    for i, flag in ipairs(flags) do
        local d = dist(px, py, flag.x, flag.y)
        if d <= C.FLAG_COMMAND_RADIUS and d < best_dist then
            best_dist, best_index, best_type = d, i, "flag"
        end
    end
    for i, barack in ipairs(baracks) do
        local d = dist(px, py, barack.x, barack.y)
        if d <= C.FLAG_COMMAND_RADIUS and d < best_dist then
            best_dist, best_index, best_type = d, i, "barack"
        end
    end
    if best_index and best_type == "flag" then
        table.remove(flags, best_index)
        add_log("Flag removed!")
    elseif best_index and best_type == "barack" then
        table.remove(baracks, best_index)
        add_log("Barack removed!")
    else
        add_log("No flag or barack in range to remove.")
    end
end

function assign_resource_checkout_tiles()
    -- Assign each resource type to a checkout tile (by order)
    for i, rtype in ipairs(RESOURCE_TYPES) do
        if CHECKOUT_ZONES[i] then
            RESOURCE_TO_CHECKOUT_TILE[rtype.name] = CHECKOUT_ZONES[i]
        end
    end
end

function love.load()
    love.window.setMode(WIDTH, HEIGHT)
    TiledMap_Load('map.tmx', TILE_SIZE)
    -- Set world size to map size
    WORLD_WIDTH = TiledMap_GetMapW() * TILE_SIZE
    WORLD_HEIGHT = TiledMap_GetMapH() * TILE_SIZE

    -- Find all special tiles on the first layer
    local layer_z = 1
    -- Resource sources (cleaned up, data-driven)
    resource_sources = {}
    local resource_tile_ids = {
        wood = 51,
        stone = 104,
        grass = 311,
        metal = 69
    }
    for i, rtype in ipairs(RESOURCE_TYPES) do
        local tile_id = resource_tile_ids[rtype.name]
        if tile_id then
            for _, pos in ipairs(TiledMap_ListAllOfTypeOnLayer(layer_z, tile_id)) do
                table.insert(resource_sources, {
                    x = pos.x * TILE_SIZE,
                    y = pos.y * TILE_SIZE,
                    type = rtype,
                    max_hp = RESOURCE_MAX_HP[rtype.name],
                    hp = RESOURCE_MAX_HP[rtype.name],
                    respawn_timer = 0,
                    active = true
                })
                print("Resource created:", rtype.name, "hp:", RESOURCE_MAX_HP[rtype.name], "max_hp:",
                    RESOURCE_MAX_HP[rtype.name])
            end
        end
    end
    -- Enemy spawn zones (support multiple tiles)
    ENEMY_ZONES = {}
    local enemy_spawns = TiledMap_ListAllOfTypeOnLayer(layer_z, 981)
    for _, s in ipairs(enemy_spawns) do
        table.insert(ENEMY_ZONES, { x = s.x * TILE_SIZE, y = s.y * TILE_SIZE, w = TILE_SIZE, h = TILE_SIZE })
    end
    -- Customer shop zones (support multiple tiles)
    CHECKOUT_ZONES = {}
    local shop_tiles = TiledMap_ListAllOfTypeOnLayer(layer_z, 747)
    for _, s in ipairs(shop_tiles) do
        table.insert(CHECKOUT_ZONES, { x = s.x * TILE_SIZE, y = s.y * TILE_SIZE, w = TILE_SIZE, h = TILE_SIZE })
    end
    -- Upgrades zones (support multiple tiles)
    UPGRADE_SHOPS = {}
    local upgrade_tiles = TiledMap_ListAllOfTypeOnLayer(layer_z, 998)
    for _, s in ipairs(upgrade_tiles) do
        table.insert(UPGRADE_SHOPS, { x = s.x * TILE_SIZE, y = s.y * TILE_SIZE, w = TILE_SIZE, h = TILE_SIZE })
    end
    -- Place player at first empty tile (not a special tile)
    local placed = false
    for y = 0, TiledMap_GetMapH() - 1 do
        for x = 0, TiledMap_GetMapW() - 1 do
            local tid = TiledMap_GetMapTile(x, y, layer_z)
            if tid ~= 51 and tid ~= 104 and tid ~= 311 and tid ~= 981 and tid ~= 747 and tid ~= 998 and tid ~= 0 and tid ~= 69 then
                player = { x = x * TILE_SIZE, y = y * TILE_SIZE, size = PLAYER_SIZE, speed = PLAYER_SPEED }
                placed = true
                break
            end
        end
        if placed then break end
    end

    -- For backward compatibility, set ENEMY_ZONE, CHECKOUT_ZONE, UPGRADE_SHOP to the first tile if any exist
    ENEMY_ZONE = ENEMY_ZONES[1]
    CHECKOUT_ZONE = CHECKOUT_ZONES[1]
    UPGRADE_SHOP = UPGRADE_SHOPS[1]

    enemies = {}
    towers = {}
    bullets = {}
    blueprints = {}
    -- New mechanics:
    baracks = {}           -- Completed Barack buildings
    robots = {}            -- Active robots
    flags = {}             -- Directional flags
    barack_blueprints = {} -- Similar to blueprints, but for baracks
    flag_blueprints = {}   -- Optional: to support build-in-progress for flags
    resource_items = {}
    player_carry = {}
    spawn_timer = 0
    collect_timer = 0
    collecting = nil
    path = { { 0, HEIGHT / 2 }, { WIDTH, HEIGHT / 2 } }
    customers = {}
    customer_timer = 0
    for _, t in ipairs(towers or {}) do t.ammo = {} end
    -- Initialize raid timer
    next_raid_time = love.timer.getTime() + math.random(30, 60) -- first raid in 30-60 seconds
    raid_countdown = 0
    raid_pending = false
    raid_message = nil

    assign_resource_checkout_tiles()
end

function love.update(dt)
    -- Player movement (robust: always update player.x/y)
    local dx, dy = 0, 0
    if love.keyboard.isDown('w') or love.keyboard.isDown('up') then dy = dy - 1 end
    if love.keyboard.isDown('s') or love.keyboard.isDown('down') then dy = dy + 1 end
    if love.keyboard.isDown('a') or love.keyboard.isDown('left') then dx = dx - 1 end
    if love.keyboard.isDown('d') or love.keyboard.isDown('right') then dx = dx + 1 end
    if dx ~= 0 or dy ~= 0 then
        local len = math.sqrt(dx * dx + dy * dy)
        player.x = player.x + player.speed * dt * dx / (len > 0 and len or 1)
        player.y = player.y + player.speed * dt * dy / (len > 0 and len or 1)
    end
    player.x = math.max(0, math.min(WORLD_WIDTH - player.size, player.x))
    player.y = math.max(0, math.min(WORLD_HEIGHT - player.size, player.y))

    -- Camera follows player, keep player centered in the world, account for zoom
    camera.x = math.floor(player.x + player.size / 2 - WIDTH / (2 * camera.scale))
    camera.y = math.floor(player.y + player.size / 2 - HEIGHT / (2 * camera.scale))
    -- Clamp camera to map bounds
    camera.x = math.max(0, math.min(camera.x, WORLD_WIDTH - WIDTH / camera.scale))
    camera.y = math.max(0, math.min(camera.y, WORLD_HEIGHT - HEIGHT / camera.scale))

    -- Resource collection
    if collecting and (not collecting.active or dist(player.x, player.y, collecting.x, collecting.y) > COLLECT_RADIUS) then
        collecting = nil
        collect_timer = 0
    end
    if not collecting then
        -- Only collect a resource if not near a blueprint
        local near_blueprint = false
        for _, bp in ipairs(blueprints) do
            if not bp.complete and not bp.coin_paid and dist(player.x + player.size / 2, player.y + player.size / 2, bp.x, bp.y) < 40 then
                near_blueprint = true
                break
            end
        end
        if not near_blueprint then
            for _, src in ipairs(resource_sources) do
                if src.active and dist(player.x, player.y, src.x, src.y) < COLLECT_RADIUS then
                    collecting = src
                    collect_timer = 0
                    break
                end
            end
        end
    end
    -- Upgrade shop interaction
    local near_upgrade = false
    for _, shop in ipairs(UPGRADE_SHOPS) do
        if dist(player.x + player.size / 2, player.y + player.size / 2, shop.x + shop.w / 2, shop.y + shop.h / 2) < 50 then
            near_upgrade = true
            break
        end
    end
    if not has_upgrade and near_upgrade then
        if love.keyboard.isDown('e') and #player_carry < C.MAX_CARRY then
            has_upgrade = true
        end
    end
    -- Faster chopping if upgraded
    if collecting and collecting.active then
        if has_upgrade then
            collect_timer = collect_timer + dt * 1.5 -- 2 chops when upgraded
        else
            collect_timer = collect_timer + dt
        end
        if collect_timer >= COLLECT_HIT_INTERVAL then
            for k, v in pairs(collecting) do print("collecting[" .. tostring(k) .. "] = " .. tostring(v)) end
            print("type(collecting.hp):", type(collecting.hp))
            collecting.hp = collecting.hp - 1
            collect_timer = 0
            if type(collecting.hp) ~= "number" then
                error("Resource hp is not a number! It is: " .. tostring(collecting.hp))
            end
            if collecting.hp <= 0 then
                -- Unified resource drop code for player and robots: always drop wood if depleted!
                if collecting.type and collecting.type.name == "wood" then
                    table.insert(resource_items, {
                        x = collecting.x + 10, y = collecting.y + 10, type = collecting.type, picked = false
                    })
                end
                add_log('Resource node depleted: ' .. collecting.type.name)
                collecting.active = false
                collecting.respawn_timer = 0
                collecting = nil
            end
        end
    end
    -- Pick up resource items
    for _, item in ipairs(resource_items) do
        if not item.picked and #player_carry < C.MAX_CARRY then
            if dist(player.x + player.size / 2, player.y + player.size / 2, item.x + 2, item.y + 2) < 30 then
                table.insert(player_carry, item.type.name)
                item.picked = true
                add_log('Picked up: ' .. item.type.name)
            end
        end
    end
    -- Remove picked items
    for i = #resource_items, 1, -1 do
        if resource_items[i].picked then table.remove(resource_items, i) end
    end
    -- Invest carried resources into blueprints (resource vector)
    for _, bp in ipairs(blueprints) do
        if not bp.complete then
            if dist(player.x + player.size / 2, player.y + player.size / 2, bp.x, bp.y) < 40 then
                for i = #player_carry, 1, -1 do
                    local r = player_carry[i]
                    if bp.required[r] and (bp.progress[r] or 0) < bp.required[r] then
                        bp.progress[r] = (bp.progress[r] or 0) + 1
                        table.remove(player_carry, i)
                    end
                end
                -- Check if all requirements are fulfilled
                local all_done = true
                for k, v in pairs(bp.required) do
                    if (bp.progress[k] or 0) < v then
                        all_done = false
                        break
                    end
                end
                if all_done then
                    bp.complete = true
                end
            end
        end
    end

    -- Invest carried resources into barack blueprints
    for i = #barack_blueprints, 1, -1 do
        local bp = barack_blueprints[i]
        if not bp.complete then
            if dist(player.x + player.size / 2, player.y + player.size / 2, bp.x, bp.y) < 40 then
                for j = #player_carry, 1, -1 do
                    local r = player_carry[j]
                    if bp.required[r] and (bp.progress[r] or 0) < bp.required[r] then
                        bp.progress[r] = (bp.progress[r] or 0) + 1
                        table.remove(player_carry, j)
                    end
                end
                -- Check if all requirements are fulfilled
                local all_done = true
                for k, v in pairs(bp.required) do
                    if (bp.progress[k] or 0) < v then
                        all_done = false
                        break
                    end
                end
                if all_done then
                    bp.complete = true
                    -- Move to main baracks list (completed building)
                    table.insert(baracks, {
                        x = bp.x,
                        y = bp.y,
                        ready = true,
                        pending_spawn = false,
                        resources = {},
                        robot_timer = 0
                    })
                    add_log("Barack built!")
                    table.remove(barack_blueprints, i)
                end
            end
        end
    end

    -- Baracks spawn robots for free every 2 seconds
    for _, barack in ipairs(baracks) do
        barack.robot_timer = barack.robot_timer or 0
        barack.robot_timer = barack.robot_timer + dt
        if barack.robot_timer >= 2.0 then
            barack.robot_timer = barack.robot_timer - 2.0
            table.insert(robots, {
                x = barack.x,
                y = barack.y,
                dir = "up",
                state = "forward"
            })
            add_log("Robot spawned from Barack (autospawn every 2s)!")
        end
    end

    -- Robot order/flag logic and movement
    for i = #robots, 1, -1 do
        local robot = robots[i]
        local rx_center = math.floor(robot.x + 0.5)
        local ry_center = math.floor(robot.y + 0.5)
        local did_flag = false

        -- Helper: gets priority for a flag object
        local function flag_priority(flag)
            if flag.flag_type == "dir" and flag.dir then
                return (C.FLAG_PRIORITIES and C.FLAG_PRIORITIES["dir_" .. flag.dir]) or 1
            end
            return (C.FLAG_PRIORITIES and C.FLAG_PRIORITIES[flag.flag_type]) or 0
        end

        -- === FLAG LOGIC (PHYSICAL FLAG APPROACH & PRIORITY) ===
        -- 1. On spawn, check for available flag and set as approach target if eligible, otherwise start with default up movement
        if not robot.init_move then
            local best_flag, best_priority = nil, -math.huge
            for _, flag in ipairs(flags) do
                local fx, fy = math.floor(flag.x + 0.5), math.floor(flag.y + 0.5)
                local dist_flag = ((rx_center - fx) ^ 2 + (ry_center - fy) ^ 2) ^ 0.5
                local pri = flag_priority(flag)
                -- Prevent robot from revisiting last_flag unless they've truly left its radius
                if dist_flag <= C.FLAG_COMMAND_RADIUS
                    and pri > best_priority
                    and (not robot.last_flag or flag ~= robot.last_flag)
                then
                    best_flag, best_priority = flag, pri
                end
            end
            if best_flag then
                robot.state = "approaching_flag"
                robot.target_flag = best_flag
                robot.target_flag_pos = { x = best_flag.x, y = best_flag.y }
                robot.target_flag_priority = best_priority
                robot.init_move = true
            else
                robot.state = "moving_distance"
                robot.dir = "up"
                robot.distance_left = C.DIR_FLAG_DEFAULT_DISTANCE
                robot.current_flag_priority = 0
                robot.init_move = true
            end
        end

        -- 2. Scan for (equal or higher) priority flag in range and, if not currently approaching one of equal/greater priority, set to approach
        local best_flag, best_priority = robot.target_flag,
            robot.target_flag_priority or (robot.current_flag_priority or 0)
        for _, flag in ipairs(flags) do
            local fx = math.floor(flag.x + 0.5)
            local fy = math.floor(flag.y + 0.5)
            local dist_flag = ((rx_center - fx) ^ 2 + (ry_center - fy) ^ 2) ^ 0.5
            local pri = flag_priority(flag)
            -- Prevent robot from picking its last_flag again, unless it has moved away
            if dist_flag <= C.FLAG_COMMAND_RADIUS
                and pri >= best_priority
                and (not robot.last_flag or flag ~= robot.last_flag)
            then
                best_flag, best_priority = flag, pri
            end
        end
        if best_flag and (not robot.target_flag or best_priority > (robot.target_flag_priority or -math.huge)) and (robot.state ~= "approaching_flag" or best_priority > (robot.target_flag_priority or -math.huge)) then
            robot.state = "approaching_flag"
            robot.target_flag = best_flag
            robot.target_flag_pos = { x = best_flag.x, y = best_flag.y }
            robot.target_flag_priority = best_priority
        end

        -- 3. If robot is in "approaching_flag" state, move toward flag (no command exec until arrival)
        if robot.state == "approaching_flag" and robot.target_flag and robot.target_flag_pos then
            local tx, ty = robot.target_flag_pos.x, robot.target_flag_pos.y
            local dx, dy = tx - robot.x, ty - robot.y
            local arrive_dist = 4
            local d = (dx * dx + dy * dy) ^ 0.5
            if d < arrive_dist then
                -- Upload finished! Read and execute the flag
                robot.current_flag_priority = robot.target_flag_priority
                local flag = robot.target_flag
                robot.last_flag = flag    -- Prevent re-targeting this flag until moved away
                robot.current_flag = flag -- Track currently executing flag for debug viz
                robot.target_flag = nil
                robot.target_flag_pos = nil
                robot.target_flag_priority = nil

                if flag.flag_type == "dir" then
                    robot.dir = flag.dir
                    robot.state = "moving_distance"
                    robot.distance_left = flag.distance or C.DIR_FLAG_DEFAULT_DISTANCE
                    robot._move_axis_hold = nil
                elseif flag.flag_type == "splitter" then
                    -- Splitter logic: track how many robots have entered this flag; send left/right alternately
                    flag._splitter_count = (flag._splitter_count or 0) + 1
                    if flag._splitter_count % 2 == 1 then
                        robot.dir = "left"
                    else
                        robot.dir = "right"
                    end
                    robot.state = "moving_distance"
                    robot.distance_left = C.DIR_FLAG_DEFAULT_DISTANCE
                    robot._move_axis_hold = nil
                elseif flag.flag_type == "chop_wood" then
                    robot.state = "chop_wood_seek"
                    robot.target_resource = nil
                elseif flag.flag_type == "collect_wood" then
                    robot.state = "collect_wood"
                    robot.target_item = nil
                    robot.resource = nil
                    robot.target_shop = nil
                elseif flag.flag_type == "build_something" then
                    if robot.resource ~= nil then
                        robot.state = "build_something"
                        robot.target_blueprint = nil
                    else
                        add_log("[Robot] Build flag: no resource, self-destruct.")
                        -- Drop resource if any
                        if robot.resource then
                            local rtype = nil
                            for _, t in ipairs(RESOURCE_TYPES) do
                                if t.name == robot.resource then rtype = t end
                            end
                            if rtype then
                                table.insert(resource_items, {
                                    x = robot.x + 8,
                                    y = robot.y + 8,
                                    type = rtype,
                                    picked = false
                                })
                            end
                        end
                        -- Drop ROBOT_DEATH_DROPS from constants.lua
                        if C.ROBOT_DEATH_DROPS then
                            for _, drop in ipairs(C.ROBOT_DEATH_DROPS) do
                                local drop_type = drop.type
                                local amount = drop.amount or 1
                                local rtype = nil
                                for _, t in ipairs(RESOURCE_TYPES) do
                                    if t.name == drop_type then rtype = t end
                                end
                                if rtype then
                                    for count = 1, amount do
                                        table.insert(resource_items, {
                                            x = robot.x + 8 + math.random(-4, 4),
                                            y = robot.y + 8 + math.random(-4, 4),
                                            type = rtype,
                                            picked = false
                                        })
                                    end
                                end
                            end
                        end
                        table.remove(robots, i)
                        goto continue_robot_loop
                    end
                end
            else
                robot.x = robot.x + dx / (d > 0 and d or 1) * (C.ROBOT_SPEED or 60) * dt
                robot.y = robot.y + dy / (d > 0 and d or 1) * (C.ROBOT_SPEED or 60) * dt
                -- DO NOT run any more logic or states if approaching a flag
                goto continue_robot_loop
            end
        end
        -- Only one robot action per frame: if just finished approaching_flag and switched state, skip remaining logic this frame to prevent double-execute:
        if robot.state == "approaching_flag" or (robot.target_flag == nil and robot.target_flag_pos == nil and robot.target_flag_priority == nil and (rx_center ~= math.floor(robot.x + 0.5) or ry_center ~= math.floor(robot.y + 0.5))) then
            goto continue_robot_loop
        end

        -- If robot moved away from the last_flag, clear last_flag to allow reactions again
        if robot.last_flag then
            local fx, fy = math.floor(robot.last_flag.x + 0.5), math.floor(robot.last_flag.y + 0.5)
            local far_enough = ((robot.x - fx) ^ 2 + (robot.y - fy) ^ 2) ^ 0.5 > C.FLAG_COMMAND_RADIUS
            if far_enough then
                robot.last_flag = nil
            end
        end

        -- 3. Movement and distance-based logic (move in direction for set distance)
        if robot.state == "moving_distance" then
            if not robot._move_axis_hold then
                if robot.dir == "left" or robot.dir == "right" then
                    robot._move_axis_hold = { y = robot.y }
                elseif robot.dir == "up" or robot.dir == "down" then
                    robot._move_axis_hold = { x = robot.x }
                else
                    robot._move_axis_hold = {}
                end
            end
            local d_step = (C.ROBOT_SPEED or 60) * dt
            if robot.distance_left ~= nil and robot.distance_left > 0 then
                local actual_step = math.min(robot.distance_left, d_step)
                if robot.dir == "up" then
                    robot.y = robot.y - actual_step
                    if robot._move_axis_hold and robot._move_axis_hold.x then
                        robot.x = robot._move_axis_hold.x
                    end
                elseif robot.dir == "down" then
                    robot.y = robot.y + actual_step
                    if robot._move_axis_hold and robot._move_axis_hold.x then
                        robot.x = robot._move_axis_hold.x
                    end
                elseif robot.dir == "left" then
                    robot.x = robot.x - actual_step
                    if robot._move_axis_hold and robot._move_axis_hold.y then
                        robot.y = robot._move_axis_hold.y
                    end
                elseif robot.dir == "right" then
                    robot.x = robot.x + actual_step
                    if robot._move_axis_hold and robot._move_axis_hold.y then
                        robot.y = robot._move_axis_hold.y
                    end
                end
                robot.distance_left = robot.distance_left - actual_step
                if robot.distance_left <= 0 then
                    -- Snap exactly to axis (avoid overshoot)
                    if robot.dir == "up" then
                        robot.y = math.floor(robot.y + 0.5)
                        if robot._move_axis_hold and robot._move_axis_hold.x then
                            robot.x = robot._move_axis_hold.x
                        end
                    elseif robot.dir == "down" then
                        robot.y = math.floor(robot.y + 0.5)
                        if robot._move_axis_hold and robot._move_axis_hold.x then
                            robot.x = robot._move_axis_hold.x
                        end
                    elseif robot.dir == "left" then
                        robot.x = math.floor(robot.x + 0.5)
                        if robot._move_axis_hold and robot._move_axis_hold.y then
                            robot.y = robot._move_axis_hold.y
                        end
                    elseif robot.dir == "right" then
                        robot.x = math.floor(robot.x + 0.5)
                        if robot._move_axis_hold and robot._move_axis_hold.y then
                            robot.y = robot._move_axis_hold.y
                        end
                    end
                    robot._move_axis_hold = nil
                    -- After finishing movement, look for highest-priority flag PHYSICALLY within FLAG_COMMAND_RADIUS of CURRENT POSITION
                    local best_flag, best_priority = nil, -math.huge
                    for _, flag in ipairs(flags) do
                        local fx = math.floor(flag.x + 0.5)
                        local fy = math.floor(flag.y + 0.5)
                        local dist_flag = ((robot.x - fx) ^ 2 + (robot.y - fy) ^ 2) ^ 0.5
                        local pri = flag_priority(flag)
                        if dist_flag <= C.FLAG_COMMAND_RADIUS and pri >= best_priority then
                            best_flag = flag
                            best_priority = pri
                        end
                    end
                    if not best_flag then
                        add_log("[Robot] Self-destruct after moving distance (no next flag found)")
                        -- Drop resource if any
                        if robot.resource then
                            local rtype = nil
                            for _, t in ipairs(RESOURCE_TYPES) do
                                if t.name == robot.resource then rtype = t end
                            end
                            if rtype then
                                table.insert(resource_items, {
                                    x = robot.x + 8,
                                    y = robot.y + 8,
                                    type = rtype,
                                    picked = false
                                })
                            end
                        end
                        -- Drop ROBOT_DEATH_DROPS from constants.lua
                        if C.ROBOT_DEATH_DROPS then
                            for _, drop in ipairs(C.ROBOT_DEATH_DROPS) do
                                local drop_type = drop.type
                                local amount = drop.amount or 1
                                local rtype = nil
                                for _, t in ipairs(RESOURCE_TYPES) do
                                    if t.name == drop_type then rtype = t end
                                end
                                if rtype then
                                    for count = 1, amount do
                                        table.insert(resource_items, {
                                            x = robot.x + 8 + math.random(-4, 4),
                                            y = robot.y + 8 + math.random(-4, 4),
                                            type = rtype,
                                            picked = false
                                        })
                                    end
                                end
                            end
                        end
                        table.remove(robots, i)
                        goto continue_robot_loop
                    else
                        -- BEGIN: approach new flag physically
                        robot.state = "approaching_flag"
                        robot.target_flag = best_flag
                        robot.target_flag_pos = { x = best_flag.x, y = best_flag.y }
                        robot.target_flag_priority = best_priority
                        robot.current_flag = nil -- Clear debug line until next approach/execute
                        goto continue_robot_loop
                        -- END approach
                    end
                end
            end
        elseif robot.state == "chop_wood_seek" then
            -- After visiting the flag: seek nearest wood node and go there
            local function pick_free_wood_node()
                local best_dist, best_src = math.huge, nil
                for _, src in ipairs(resource_sources) do
                    if src.type and src.type.name == "wood" and src.active and src.hp and src.hp > 0 then
                        local is_claimed = false
                        for _, rbot in ipairs(robots) do
                            if rbot ~= robot and rbot.target_resource == src and (rbot.state == "chop_wood_seek" or rbot.state == "chop_wood_chop") then
                                is_claimed = true
                                break
                            end
                        end
                        if not is_claimed then
                            local d = dist(robot.x, robot.y, src.x, src.y)
                            if d < best_dist then
                                best_dist = d
                                best_src = src
                            end
                        end
                    end
                end
                return best_src
            end

            if not robot.target_resource or not robot.target_resource.active or not robot.target_resource.hp or robot.target_resource.hp <= 0 then
                robot.target_resource = pick_free_wood_node()
                if not robot.target_resource then
                    add_log("[Robot] No wood node available! Self-destruct.")
                    if robot.resource then
                        local rtype = nil
                        for _, t in ipairs(RESOURCE_TYPES) do
                            if t.name == robot.resource then rtype = t end
                        end
                        if rtype then
                            table.insert(resource_items, {
                                x = robot.x + 8,
                                y = robot.y + 8,
                                type = rtype,
                                picked = false
                            })
                        end
                    end
                    if C.ROBOT_DEATH_DROPS then
                        for _, drop in ipairs(C.ROBOT_DEATH_DROPS) do
                            local drop_type = drop.type
                            local amount = drop.amount or 1
                            local rtype = nil
                            for _, t in ipairs(RESOURCE_TYPES) do
                                if t.name == drop_type then rtype = t end
                            end
                            if rtype then
                                for count = 1, amount do
                                    table.insert(resource_items, {
                                        x = robot.x + 8 + math.random(-4, 4),
                                        y = robot.y + 8 + math.random(-4, 4),
                                        type = rtype,
                                        picked = false
                                    })
                                end
                            end
                        end
                    end
                    table.remove(robots, i)
                    goto continue_robot_loop
                end
            end

            if robot.target_resource then
                local tx = robot.target_resource.x + TILE_SIZE / 2
                local ty = robot.target_resource.y + TILE_SIZE / 2
                local dx, dy = tx - robot.x, ty - robot.y
                local d = (dx * dx + dy * dy) ^ 0.5
                if d < (C.ROBOT_SPEED or 60) * dt then
                    robot.x, robot.y = tx, ty
                    -- Arrived: switch to chop state
                    robot.state = "chop_wood_chop"
                else
                    robot.x = robot.x + dx / (d > 0 and d or 1) * (C.ROBOT_SPEED or 60) * dt
                    robot.y = robot.y + dy / (d > 0 and d or 1) * (C.ROBOT_SPEED or 60) * dt
                end
            end
        elseif robot.state == "chop_wood_chop" then
            -- Chop the node once, then self-destruct
            if robot.target_resource and robot.target_resource.active and robot.target_resource.hp and robot.target_resource.hp > 0 then
                robot.target_resource.hp = robot.target_resource.hp - 1
                -- Drop resource item if depleted now (unified logic)
                if robot.target_resource.hp <= 0 and robot.target_resource.type and robot.target_resource.type.name == "wood" then
                    table.insert(resource_items, {
                        x = robot.target_resource.x + 10,
                        y = robot.target_resource.y + 10,
                        type = robot.target_resource
                            .type,
                        picked = false
                    })
                end
                if robot.target_resource.hp <= 0 then
                    robot.target_resource.active = false
                    robot.target_resource.respawn_timer = 0
                end
                add_log("[Robot] Chop Wood: hit wood node once.")
                if robot.resource then
                    local rtype = nil
                    for _, t in ipairs(RESOURCE_TYPES) do
                        if t.name == robot.resource then rtype = t end
                    end
                    if rtype then
                        table.insert(resource_items, {
                            x = robot.x + 8,
                            y = robot.y + 8,
                            type = rtype,
                            picked = false
                        })
                    end
                end
                if C.ROBOT_DEATH_DROPS then
                    for _, drop in ipairs(C.ROBOT_DEATH_DROPS) do
                        local drop_type = drop.type
                        local amount = drop.amount or 1
                        local rtype = nil
                        for _, t in ipairs(RESOURCE_TYPES) do
                            if t.name == drop_type then rtype = t end
                        end
                        if rtype then
                            for count = 1, amount do
                                table.insert(resource_items, {
                                    x = robot.x + 8 + math.random(-4, 4),
                                    y = robot.y + 8 + math.random(-4, 4),
                                    type = rtype,
                                    picked = false
                                })
                            end
                        end
                    end
                end
                table.remove(robots, i)
                goto continue_robot_loop
            else
                -- If for any reason node is invalid now, self-destruct
                add_log("[Robot] Chop Wood: node was missing, abort.")
                if robot.resource then
                    local rtype = nil
                    for _, t in ipairs(RESOURCE_TYPES) do
                        if t.name == robot.resource then rtype = t end
                    end
                    if rtype then
                        table.insert(resource_items, {
                            x = robot.x + 8,
                            y = robot.y + 8,
                            type = rtype,
                            picked = false
                        })
                    end
                end
                if C.ROBOT_DEATH_DROPS then
                    for _, drop in ipairs(C.ROBOT_DEATH_DROPS) do
                        local drop_type = drop.type
                        local amount = drop.amount or 1
                        local rtype = nil
                        for _, t in ipairs(RESOURCE_TYPES) do
                            if t.name == drop_type then rtype = t end
                        end
                        if rtype then
                            for count = 1, amount do
                                table.insert(resource_items, {
                                    x = robot.x + 8 + math.random(-4, 4),
                                    y = robot.y + 8 + math.random(-4, 4),
                                    type = rtype,
                                    picked = false
                                })
                            end
                        end
                    end
                end
                table.remove(robots, i)
                goto continue_robot_loop
            end
        elseif robot.state == "collect_wood" then
            -- Find nearest free wood item, pick up, visibly carry, deliver to shop, self-destruct after
            -- Step 1: Find and move to nearest ground wood (not picked)
            if not robot.resource then
                -- Seek a free wood item on the ground
                if not robot.target_item or robot.target_item.picked or robot.target_item.type.name ~= "wood" then
                    local best_dist, best_item = math.huge, nil
                    local found_any = false
                    for _, item in ipairs(resource_items) do
                        if item.type and item.type.name == "wood" and not item.picked then
                            found_any = true
                            local d = dist(robot.x, robot.y, item.x + 2, item.y + 2)
                            if d < best_dist then
                                best_dist = d
                                best_item = item
                            end
                        end
                    end
                    robot.target_item = best_item
                    if not found_any then
                        add_log("[Robot] No ground wood to collect! Self-destruct.")
                        if robot.resource then
                            local rtype = nil
                            for _, t in ipairs(RESOURCE_TYPES) do
                                if t.name == robot.resource then rtype = t end
                            end
                            if rtype then
                                table.insert(resource_items, {
                                    x = robot.x + 8,
                                    y = robot.y + 8,
                                    type = rtype,
                                    picked = false
                                })
                            end
                        end
                        if C.ROBOT_DEATH_DROPS then
                            for _, drop in ipairs(C.ROBOT_DEATH_DROPS) do
                                local drop_type = drop.type
                                local amount = drop.amount or 1
                                local rtype = nil
                                for _, t in ipairs(RESOURCE_TYPES) do
                                    if t.name == drop_type then rtype = t end
                                end
                                if rtype then
                                    for count = 1, amount do
                                        table.insert(resource_items, {
                                            x = robot.x + 8 + math.random(-4, 4),
                                            y = robot.y + 8 + math.random(-4, 4),
                                            type = rtype,
                                            picked = false
                                        })
                                    end
                                end
                            end
                        end
                        table.remove(robots, i)
                        goto continue_robot_loop
                    end
                end
                if robot.target_item then
                    local tx = robot.target_item.x + 2
                    local ty = robot.target_item.y + 2
                    local dx = tx - robot.x
                    local dy = ty - robot.y
                    local d = (dx * dx + dy * dy) ^ 0.5
                    if d < (C.ROBOT_SPEED or 60) * dt then
                        robot.x = tx
                        robot.y = ty
                        -- Pick it up
                        if not robot.target_item.picked then
                            robot.target_item.picked = true
                            robot.resource = "wood"
                            add_log("[Robot] Picked up ground wood!")
                        end
                        robot.target_item = nil
                    else
                        robot.x = robot.x + dx / (d > 0 and d or 1) * (C.ROBOT_SPEED or 60) * dt
                        robot.y = robot.y + dy / (d > 0 and d or 1) * (C.ROBOT_SPEED or 60) * dt
                    end
                end
            else
                -- Step 2: Carry it (show visually) to the nearest shop
                if not robot.target_shop then
                    local best_dist, shop = math.huge, nil
                    for _, zone in ipairs(CHECKOUT_ZONES) do
                        local zx = zone.x + zone.w / 2
                        local zy = zone.y + zone.h / 2
                        local d = dist(robot.x, robot.y, zx, zy)
                        if d < best_dist then
                            best_dist = d
                            shop = zone
                        end
                    end
                    if shop then
                        robot.target_shop = { x = shop.x + shop.w / 2, y = shop.y + shop.h / 2 }
                    end
                end

                if robot.target_shop then
                    local tx = robot.target_shop.x
                    local ty = robot.target_shop.y
                    local dx, dy = tx - robot.x, ty - robot.y
                    local d = (dx * dx + dy * dy) ^ 0.5
                    if d < (C.ROBOT_SPEED or 60) * dt then
                        robot.x = tx
                        robot.y = ty
                        -- Deliver and self-destruct
                        add_log("[Robot] Delivered carried wood to shop.")
                        -- Drop carried resource if any
                        if robot.resource then
                            local rtype = nil
                            for _, t in ipairs(RESOURCE_TYPES) do
                                if t.name == robot.resource then rtype = t end
                            end
                            if rtype then
                                table.insert(resource_items, {
                                    x = robot.x + 8,
                                    y = robot.y + 8,
                                    type = rtype,
                                    picked = false
                                })
                            end
                        end
                        -- Drop ROBOT_DEATH_DROPS from constants.lua
                        if C.ROBOT_DEATH_DROPS then
                            for _, drop in ipairs(C.ROBOT_DEATH_DROPS) do
                                local drop_type = drop.type
                                local amount = drop.amount or 1
                                local rtype = nil
                                for _, t in ipairs(RESOURCE_TYPES) do
                                    if t.name == drop_type then rtype = t end
                                end
                                if rtype then
                                    for count = 1, amount do
                                        table.insert(resource_items, {
                                            x = robot.x + 8 + math.random(-4, 4),
                                            y = robot.y + 8 + math.random(-4, 4),
                                            type = rtype,
                                            picked = false
                                        })
                                    end
                                end
                            end
                        end
                        robot.resource = nil
                        table.remove(robots, i)
                        goto continue_robot_loop
                    else
                        robot.x = robot.x + dx / (d > 0 and d or 1) * (C.ROBOT_SPEED or 60) * dt
                        robot.y = robot.y + dy / (d > 0 and d or 1) * (C.ROBOT_SPEED or 60) * dt
                    end
                end
            end
        elseif robot.state == "build_something" then
            -- Robot has a resource: bring it to nearest unfinished tower blueprint
            if not robot.target_blueprint or robot.target_blueprint.complete then
                local best_dist, best_bp = math.huge, nil
                for _, bp in ipairs(blueprints) do
                    -- Only consider incomplete AND still requiring the resource the robot carries
                    if not bp.complete and bp.required[robot.resource] and (bp.progress[robot.resource] or 0) < bp.required[robot.resource] then
                        local d = dist(robot.x, robot.y, bp.x, bp.y)
                        if d < best_dist then
                            best_dist = d
                            best_bp = bp
                        end
                    end
                end
                robot.target_blueprint = best_bp
                if not robot.target_blueprint then
                    add_log("[Robot] No matching blueprint in need of this resource! Self-destruct.")
                    if robot.resource then
                        local rtype = nil
                        for _, t in ipairs(RESOURCE_TYPES) do
                            if t.name == robot.resource then rtype = t end
                        end
                        if rtype then
                            table.insert(resource_items, {
                                x = robot.x + 8,
                                y = robot.y + 8,
                                type = rtype,
                                picked = false
                            })
                        end
                    end
                    if C.ROBOT_DEATH_DROPS then
                        for _, drop in ipairs(C.ROBOT_DEATH_DROPS) do
                            local drop_type = drop.type
                            local amount = drop.amount or 1
                            local rtype = nil
                            for _, t in ipairs(RESOURCE_TYPES) do
                                if t.name == drop_type then rtype = t end
                            end
                            if rtype then
                                for count = 1, amount do
                                    table.insert(resource_items, {
                                        x = robot.x + 8 + math.random(-4, 4),
                                        y = robot.y + 8 + math.random(-4, 4),
                                        type = rtype,
                                        picked = false
                                    })
                                end
                            end
                        end
                    end
                    table.remove(robots, i)
                    goto continue_robot_loop
                end
            end

            local tx = robot.target_blueprint.x
            local ty = robot.target_blueprint.y
            local dx, dy = tx - robot.x, ty - robot.y
            local d = (dx * dx + dy * dy) ^ 0.5
            if d < (C.ROBOT_SPEED or 60) * dt then
                robot.x = tx
                robot.y = ty
                -- Try to invest resource into the blueprint
                for rtype, req in pairs(robot.target_blueprint.required) do
                    if robot.resource == rtype
                        and (robot.target_blueprint.progress[rtype] or 0) < req then
                        robot.target_blueprint.progress[rtype] = (robot.target_blueprint.progress[rtype] or 0) + 1
                        robot.resource = nil
                        add_log("[Robot] Invested resource into blueprint!")
                    end
                end
                -- Always self-destruct after building attempt
                if robot.resource then
                    local rtype = nil
                    for _, t in ipairs(RESOURCE_TYPES) do
                        if t.name == robot.resource then rtype = t end
                    end
                    if rtype then
                        table.insert(resource_items, {
                            x = robot.x + 8,
                            y = robot.y + 8,
                            type = rtype,
                            picked = false
                        })
                    end
                end
                if C.ROBOT_DEATH_DROPS then
                    for _, drop in ipairs(C.ROBOT_DEATH_DROPS) do
                        local drop_type = drop.type
                        local amount = drop.amount or 1
                        local rtype = nil
                        for _, t in ipairs(RESOURCE_TYPES) do
                            if t.name == drop_type then rtype = t end
                        end
                        if rtype then
                            for count = 1, amount do
                                table.insert(resource_items, {
                                    x = robot.x + 8 + math.random(-4, 4),
                                    y = robot.y + 8 + math.random(-4, 4),
                                    type = rtype,
                                    picked = false
                                })
                            end
                        end
                    end
                end
                table.remove(robots, i)
                goto continue_robot_loop
            else
                robot.x = robot.x + dx / (d > 0 and d or 1) * (C.ROBOT_SPEED or 60) * dt
                robot.y = robot.y + dy / (d > 0 and d or 1) * (C.ROBOT_SPEED or 60) * dt
            end
        elseif robot.state == "deliver" then
            -- Find nearest shop if not set
            if not robot.target_shop then
                local best_dist, shop = math.huge, nil
                for _, zone in ipairs(CHECKOUT_ZONES) do
                    local zx = zone.x + zone.w / 2
                    local zy = zone.y + zone.h / 2
                    local d = dist(robot.x, robot.y, zx, zy)
                    if d < best_dist then
                        best_dist = d
                        shop = zone
                    end
                end
                if shop then
                    robot.target_shop = { x = shop.x + shop.w / 2, y = shop.y + shop.h / 2 }
                end
            end
            if robot.target_shop then
                local tx = robot.target_shop.x
                local ty = robot.target_shop.y
                local dx, dy = tx - robot.x, ty - robot.y
                local d = (dx * dx + dy * dy) ^ 0.5
                if d < (C.ROBOT_SPEED or 60) * dt then
                    robot.x = tx
                    robot.y = ty
                    -- Instantly deliver and remove resource, add log
                    add_log("[Robot] Delivered " .. tostring(robot.resource or "item") .. " to shop!")
                    robot._delivered = true
                    -- After delivering, check for next flag or self-destruct
                    local found_next = false
                    for _, flag in ipairs(flags) do
                        local fx = math.floor(flag.x + 0.5)
                        local fy = math.floor(flag.y + 0.5)
                        local dist_flag = ((robot.x - fx) ^ 2 + (robot.y - fy) ^ 2) ^ 0.5
                        if dist_flag <= C.FLAG_COMMAND_RADIUS and flag_priority(flag) > 0 and (not robot.last_flag or flag ~= robot.last_flag) then
                            found_next = true
                            break
                        end
                    end
                    if not found_next then
                        add_log("[Robot] Self-destruct after delivery (no next flag found)")
                        table.remove(robots, i)
                        goto continue_robot_loop
                    else
                        -- BEGIN: approach new flag physically, but ONLY if such a flag exists within FLAG_COMMAND_RADIUS of current robot position
                        local best_flag, best_priority = nil, -math.huge
                        for _, candidate in ipairs(flags) do
                            local fx = math.floor(candidate.x + 0.5)
                            local fy = math.floor(candidate.y + 0.5)
                            local dist_flag = ((robot.x - fx) ^ 2 + (robot.y - fy) ^ 2) ^ 0.5
                            local pri = flag_priority(candidate)
                            if dist_flag <= C.FLAG_COMMAND_RADIUS and pri > best_priority and (not robot.last_flag or candidate ~= robot.last_flag) then
                                best_flag = candidate
                                best_priority = pri
                            end
                        end
                        if best_flag then
                            robot.resource = nil
                            robot.state = "approaching_flag"
                            robot.target_flag = best_flag
                            robot.target_flag_pos = { x = best_flag.x, y = best_flag.y }
                            robot.target_flag_priority = best_priority
                            robot.target_shop = nil
                            robot.current_flag = nil -- Clear debug line until next approach/execute
                            goto continue_robot_loop
                        end
                        -- END approach
                    end
                else
                    robot.x = robot.x + dx / d * (C.ROBOT_SPEED or 60) * dt
                    robot.y = robot.y + dy / d * (C.ROBOT_SPEED or 60) * dt
                end
            end
        end
        ::continue_robot_loop::
        -- End of per-robot update loop (close conditional/loop blocks properly)
    end
    -- Build completed towers from blueprints
    for _, bp in ipairs(blueprints) do
        if bp.complete and not bp.tower_built then
            table.insert(towers,
                {
                    x = bp.x,
                    y = bp.y,
                    range = TOWER_RANGE,
                    cooldown = 0,
                    ammo = {},
                    towerType = bp.towerType or 'charged',
                    built = true,
                    hp =
                        C.TOWER_HP
                })
            add_log('Tower built: ' .. (bp.towerType or 'charged'))
            bp.tower_built = true
        end
    end
    -- Charge towers with resources (player gives resource to tower if close and tower is built)
    for _, tower in ipairs(towers) do
        if tower.towerType == 'charged' and tower.built and dist(player.x + player.size / 2, player.y + player.size / 2, tower.x, tower.y) < 40 then
            for i = #player_carry, 1, -1 do
                local r = player_carry[i]
                tower.ammo[r] = (tower.ammo[r] or 0) + 1
                table.remove(player_carry, i)
                break -- only transfer one resource per frame
            end
        end
    end
    -- After charging towers with resources, restore the firing logic for both tower types
    for _, tower in ipairs(towers) do
        tower.cooldown = math.max(0, tower.cooldown - dt)
        if tower.built then
            if tower.towerType == 'charged' then
                if tower.cooldown == 0 then
                    -- Find ammo type to use (prefer highest damage)
                    local best_type, best_dmg = nil, 0
                    for r, dmg in pairs(RESOURCE_DAMAGE) do
                        if (tower.ammo[r] or 0) > 0 and dmg > best_dmg then
                            best_type, best_dmg = r, dmg
                        end
                    end
                    if best_type then
                        for _, enemy in ipairs(enemies) do
                            if dist(enemy.x, enemy.y, tower.x, tower.y) < tower.range then
                                table.insert(bullets,
                                    {
                                        x = tower.x,
                                        y = tower.y,
                                        target = enemy,
                                        alive = true,
                                        dmg = RESOURCE_DAMAGE
                                            [best_type],
                                        resource_type = best_type
                                    })
                                tower.ammo[best_type] = tower.ammo[best_type] - 1
                                tower.cooldown = TOWER_FIRE_RATE
                                break
                            end
                        end
                    end
                end
            elseif tower.towerType == 'auto' then
                if tower.cooldown == 0 then
                    for _, enemy in ipairs(enemies) do
                        if dist(enemy.x, enemy.y, tower.x, tower.y) < tower.range then
                            table.insert(bullets, { x = tower.x, y = tower.y, target = enemy, alive = true, dmg = 1 })
                            tower.cooldown = TOWER_FIRE_RATE
                            break
                        end
                    end
                end
            end
        end
    end
    -- Update bullets (deal variable damage)
    for _, b in ipairs(bullets) do
        if b.target.alive then
            local dx, dy = b.target.x - b.x, b.target.y - b.y
            local d = (dx ^ 2 + dy ^ 2) ^ 0.5
            if d < BULLET_SPEED * dt then
                b.x, b.y = b.target.x, b.target.y
                b.target.health = b.target.health - (b.dmg or 1)
                if b.target.health <= 0 then b.target.alive = false end
                b.alive = false
            else
                b.x = b.x + BULLET_SPEED * dt * dx / d
                b.y = b.y + BULLET_SPEED * dt * dy / d
            end
        else
            b.alive = false
        end
    end
    for i = #bullets, 1, -1 do
        if not bullets[i].alive then
            add_log('Bullet removed')
            table.remove(bullets, i)
        end
    end
    -- Update resource sources (respawn)
    for _, src in ipairs(resource_sources) do
        if not src.active then
            src.respawn_timer = src.respawn_timer + dt
            local respawn_time = C.RESOURCE_RESPAWN_TIME[src.type.name] or 5
            if src.respawn_timer >= respawn_time then
                src.hp = src.max_hp
                src.active = true
                src.respawn_timer = 0
            end
        end
    end
    -- Customer spawn: use C.CUSTOMER_EXCHANGES
    customer_timer = customer_timer + dt
    if customer_timer > CUSTOMER_SPAWN_INTERVAL then
        local exch = C.CUSTOMER_EXCHANGES[math.random(#C.CUSTOMER_EXCHANGES)]
        local want_type, want_amount = exch.want, exch.want_amount or 1
        local offer_type, offer_amount = exch.offer, exch.offer_amount or 1
        local target_zone = RESOURCE_TO_CHECKOUT_TILE[want_type] or CHECKOUT_ZONES[1]
        -- Customer carries what they offer
        local carry = {}
        for i = 1, offer_amount do table.insert(carry, offer_type) end
        table.insert(customers, {
            x = math.random(40, WIDTH - 40),
            y = HEIGHT + 40, -- spawn below screen
            state = 'walking',
            want = want_type,
            want_amount = want_amount,
            offer = offer_type,
            offer_amount = offer_amount,
            carry = carry,
            wait = 0,
            served = false,
            target_x = target_zone.x + target_zone.w / 2,
            target_y = target_zone.y + target_zone.h / 2,
            checkout_zone = target_zone
        })
        customer_timer = 0
    end
    -- Update customers
    for _, cust in ipairs(customers) do
        if cust.state == 'walking' then
            local dx = cust.target_x - cust.x
            local dy = cust.target_y - cust.y
            local d = (dx ^ 2 + dy ^ 2) ^ 0.5
            if d < CUSTOMER_SPEED * dt then
                -- Count how many customers are already waiting at this checkout tile
                local line_index = 0
                for _, other in ipairs(customers) do
                    if other ~= cust and other.state == 'waiting' and other.target_x == cust.target_x and other.target_y == cust.target_y then
                        line_index = line_index + 1
                    end
                end
                cust.x = cust.target_x
                cust.y = cust.target_y + line_index * (CUSTOMER_SIZE + 6)
                cust.line_index = line_index
                cust.state = 'waiting'
                cust.wait = 0
            else
                cust.x = cust.x + CUSTOMER_SPEED * dt * dx / d
                cust.y = cust.y + CUSTOMER_SPEED * dt * dy / d
            end
        elseif cust.state == 'waiting' then
            local zone = cust.checkout_zone or CHECKOUT_ZONES[1]
            if player.x + player.size > zone.x and player.x < zone.x + zone.w and player.y + player.size > zone.y and player.y < zone.y + zone.h then
                -- Check if player has enough of the wanted resource
                local found = 0
                for i = #player_carry, 1, -1 do
                    if player_carry[i] == cust.want then found = found + 1 end
                end
                local cust_has = #cust.carry
                if found >= (cust.want_amount or 1) and cust_has >= (cust.offer_amount or 1) then
                    -- Remove want_amount from player
                    local removed = 0
                    for i = #player_carry, 1, -1 do
                        if player_carry[i] == cust.want and removed < cust.want_amount then
                            table.remove(player_carry, i)
                            removed = removed + 1
                        end
                    end
                    -- Drop offer_amount items farther away from customer
                    for n = 1, (cust.offer_amount or 1) do
                        local angle = math.random() * 2 * math.pi
                        local dist_away = 20 + math.random(0, 5) -- reduced drop distance
                        local drop_x = cust.x + math.cos(angle) * dist_away
                        local drop_y = cust.y + math.sin(angle) * dist_away
                        for _, t in ipairs(RESOURCE_TYPES) do
                            if t.name == cust.offer then
                                table.insert(resource_items, {
                                    x = drop_x,
                                    y = drop_y,
                                    type = t,
                                    picked = false
                                })
                                add_log(string.format('Customer dropped %s at (%.1f, %.1f)', t.name, drop_x, drop_y))
                            end
                        end
                    end
                    -- Remove all offered items from customer carry
                    cust.carry = {}
                    cust.state = 'leaving'
                    cust.served = true
                end
            end
        elseif cust.state == 'leaving' then
            cust.y = cust.y + CUSTOMER_SPEED * dt
        end
    end
    -- When a customer leaves, update the line_index and y position of those behind them
    for i = #customers, 1, -1 do
        local cust = customers[i]
        if cust.state == 'leaving' and cust.y > HEIGHT + 50 then
            -- Find all customers at the same checkout tile with a higher line_index
            for _, other in ipairs(customers) do
                if other ~= cust and other.state == 'waiting' and other.target_x == cust.target_x and other.target_y == cust.target_y and other.line_index and cust.line_index and other.line_index > cust.line_index then
                    other.line_index = other.line_index - 1
                    other.y = other.target_y + other.line_index * (CUSTOMER_SIZE + 6)
                end
            end
            table.remove(customers, i)
        end
    end
    -- Enemy AI: choose strategy: destroyer or resource stealer
    for _, enemy in ipairs(enemies) do
        if not enemy.role then
            -- Randomly choose role on spawn: 50% destroyer, 50% resource stealer
            if math.random() < 0.5 then
                enemy.role = "destroyer"
                enemy.state = "seek_flag"
            else
                enemy.role = "resource_stealer"
                enemy.state = "seek_item"
            end
        end

        -- DESTROYER: attacks a flag, hits once, then self-destructs
        if enemy.role == "destroyer" then
            if enemy.state == "seek_flag" then
                if #flags == 0 then
                    enemy.state = 'escape'
                else
                    local target_index = math.random(1, #flags)
                    enemy.target_flag = flags[target_index]
                    enemy.state = 'move_to_flag'
                end
            elseif enemy.state == "move_to_flag" then
                if not enemy.target_flag or not enemy.target_flag.hp or enemy.target_flag.hp <= 0 then
                    enemy.target_flag = nil
                    enemy.state = 'seek_flag'
                else
                    local tx = enemy.target_flag.x
                    local ty = enemy.target_flag.y
                    local dx = tx - (enemy.x + ENEMY_SIZE / 2)
                    local dy = ty - (enemy.y + ENEMY_SIZE / 2)
                    local d = (dx ^ 2 + dy ^ 2) ^ 0.5
                    if d < enemy.speed * dt then
                        enemy.x = tx - ENEMY_SIZE / 2
                        enemy.y = ty - ENEMY_SIZE / 2
                        -- Hit once and self-destruct
                        enemy.target_flag.hp = enemy.target_flag.hp - (C.ENEMY_TOWER_DAMAGE or 1)
                        if enemy.target_flag.hp <= 0 then
                            for j = #flags, 1, -1 do
                                if flags[j] == enemy.target_flag then
                                    table.remove(flags, j)
                                    break
                                end
                            end
                        end
                        enemy.alive = false
                    else
                        enemy.x = enemy.x + enemy.speed * dt * (dx / (d > 0 and d or 1))
                        enemy.y = enemy.y + enemy.speed * dt * (dy / (d > 0 and d or 1))
                    end
                end
            end

            -- RESOURCE STEALER: seeks and destroys one ground item
        elseif enemy.role == "resource_stealer" then
            if enemy.state == "seek_item" then
                -- Find nearest free resource item (not picked)
                local best_dist, best_item = math.huge, nil
                for _, item in ipairs(resource_items) do
                    if not item.picked and item.type then
                        local d = dist(enemy.x + ENEMY_SIZE / 2, enemy.y + ENEMY_SIZE / 2, item.x + 2, item.y + 2)
                        if d < best_dist then
                            best_dist = d
                            best_item = item
                        end
                    end
                end
                if not best_item then
                    enemy.state = "escape"
                else
                    enemy.target_item = best_item
                    enemy.state = "move_to_item"
                end
            elseif enemy.state == "move_to_item" then
                if not enemy.target_item or enemy.target_item.picked then
                    enemy.state = "seek_item"
                else
                    local tx = enemy.target_item.x + 2
                    local ty = enemy.target_item.y + 2
                    local dx = tx - (enemy.x + ENEMY_SIZE / 2)
                    local dy = ty - (enemy.y + ENEMY_SIZE / 2)
                    local d = (dx ^ 2 + dy ^ 2) ^ 0.5
                    if d < enemy.speed * dt then
                        enemy.x = tx - ENEMY_SIZE / 2
                        enemy.y = ty - ENEMY_SIZE / 2
                        -- Pick up and destroy the item, then self-destruct
                        if not enemy.target_item.picked then
                            enemy.target_item.picked = true
                        end
                        enemy.alive = false
                    else
                        enemy.x = enemy.x + enemy.speed * dt * (dx / (d > 0 and d or 1))
                        enemy.y = enemy.y + enemy.speed * dt * (dy / (d > 0 and d or 1))
                    end
                end
            end
        end
        -- Common escape logic
        if enemy.state == 'escape' then
            local dx, dy = 0, 1
            enemy.x = enemy.x + enemy.speed * dt * dx
            enemy.y = enemy.y + enemy.speed * dt * dy
            if enemy.y > HEIGHT + 50 then enemy.alive = false end
        end
    end
    -- Remove dead enemies and drop resources
    for i = #enemies, 1, -1 do
        if not enemies[i].alive then
            -- Drop resources from C.ENEMY_DEATH_DROPS
            if C.ENEMY_DEATH_DROPS then
                for _, drop in ipairs(C.ENEMY_DEATH_DROPS) do
                    local drop_type = drop.type
                    local amount = drop.amount or 1
                    -- Find resource definition
                    local rtype = nil
                    for _, t in ipairs(RESOURCE_TYPES) do
                        if t.name == drop_type then rtype = t end
                    end
                    if rtype then
                        for count = 1, amount do
                            table.insert(resource_items, {
                                x = enemies[i].x + ENEMY_SIZE / 2 + math.random(-8, 8),
                                y = enemies[i].y + ENEMY_SIZE / 2 + math.random(-8, 8),
                                type = rtype,
                                picked = false
                            })
                        end
                    end
                end
            end
            add_log('Enemy killed!')
            wave_alive = math.max(0, wave_alive - 1)
            table.remove(enemies, i)
        end
    end

    -- Enemy spawn zone trigger (allow retriggering for new waves)
    local in_enemy_zone = false
    for _, zone in ipairs(ENEMY_ZONES) do
        if player.x + player.size / 2 > zone.x and player.x + player.size / 2 < zone.x + zone.w and player.y + player.size / 2 > zone.y and player.y + player.size / 2 < zone.y + zone.h then
            in_enemy_zone = true
            break
        end
    end
    if #ENEMY_ZONES > 0 and in_enemy_zone then
        if not enemy_zone_triggered then
            wave_number = wave_number + 1
            wave_total = ENEMY_LINE_COUNT
            wave_alive = ENEMY_LINE_COUNT
            for i = 1, ENEMY_LINE_COUNT do
                local zone = ENEMY_ZONES[math.random(#ENEMY_ZONES)]
                table.insert(enemies, {
                    x = zone.x + 10 + (i - 1) * (ENEMY_SIZE + 10),
                    y = zone.y + zone.h + 10,
                    health = ENEMY_HEALTH,
                    speed = ENEMY_SPEED,
                    alive = true,
                    state = 'seek_flag',
                    mine_goal = math.random(1, 3), -- how many resources to mine before escaping
                    carry = {},                    -- list of gathered resource names
                })
            end
            add_log('Wave ' .. wave_number .. ' spawned!')
            enemy_zone_triggered = true
        end
    else
        enemy_zone_triggered = false
    end

    -- Debug: log camera and first resource bar position every 0.5s
    debug_timer = 0 -- keep the variable if needed elsewhere, or remove if unused

    -- In love.update, drop all carried resources when player presses E
    if love.keyboard.isDown('e') and #player_carry > 0 then
        for _, r in ipairs(player_carry) do
            for _, t in ipairs(RESOURCE_TYPES) do
                if t.name == r then
                    -- Drop resource 32 pixels away in a random direction
                    local angle = math.random() * 2 * math.pi
                    local drop_dist = 32
                    local drop_x = player.x + player.size / 2 + math.cos(angle) * drop_dist
                    local drop_y = player.y + player.size / 2 + math.sin(angle) * drop_dist
                    table.insert(resource_items, {
                        x = drop_x,
                        y = drop_y,
                        type = t,
                        picked = false
                    })
                end
            end
        end
        player_carry = {}
    end

    -- Remove destroyed towers
    for i = #towers, 1, -1 do
        if towers[i].hp and towers[i].hp <= 0 then
            table.remove(towers, i)
        end
    end

    -- Automatic enemy raid logic
    local now = love.timer.getTime()
    if not raid_pending and now > next_raid_time - 10 then
        raid_pending = true
        raid_countdown = math.ceil(next_raid_time - now)
    end
    if raid_pending then
        local new_countdown = math.ceil(next_raid_time - now)
        if new_countdown ~= raid_countdown then
            raid_countdown = new_countdown
        end
        if raid_countdown > 0 then
            raid_message = string.format('Raid in %d', raid_countdown)
        else
            raid_message = nil
        end
        if now >= next_raid_time then
            -- Spawn a raid (enemy wave)
            wave_number = wave_number + 1
            wave_total = ENEMY_LINE_COUNT
            wave_alive = ENEMY_LINE_COUNT
            for i = 1, ENEMY_LINE_COUNT do
                local zone = ENEMY_ZONES[math.random(#ENEMY_ZONES)]
                table.insert(enemies, {
                    x = zone.x + 10 + (i - 1) * (ENEMY_SIZE + 10),
                    y = zone.y + zone.h + 10,
                    health = ENEMY_HEALTH,
                    speed = ENEMY_SPEED,
                    alive = true,
                    state = 'seek_flag',
                    mine_goal = math.random(1, 3),
                    carry = {},
                })
            end
            add_log('Raid wave ' .. wave_number .. ' spawned!')
            -- Schedule next raid
            next_raid_time = now + math.random(30, 60)
            raid_pending = false
            raid_countdown = 0
            raid_message = nil
        end
    end

    -- Customer-to-customer exchange logic
    -- After player-customer exchange, before customers move/leave
    local to_leave = {}
    for i = 1, #customers do
        local a = customers[i]
        if a.state == 'waiting' and not a.served then
            for j = i + 1, #customers do
                local b = customers[j]
                if b.state == 'waiting' and not b.served then
                    -- Check if a's want matches b's offer and b's want matches a's offer
                    if a.want == b.offer and b.want == a.offer then
                        local a_want_amt = a.want_amount or 1
                        local a_offer_amt = a.offer_amount or 1
                        local b_want_amt = b.want_amount or 1
                        local b_offer_amt = b.offer_amount or 1
                        -- Check if both have enough to trade
                        if #a.carry >= a_offer_amt and #b.carry >= b_offer_amt then
                            -- Remove offers from both
                            for k = 1, a_offer_amt do table.remove(a.carry) end
                            for k = 1, b_offer_amt do table.remove(b.carry) end
                            -- Mark both as leaving and served
                            a.state = 'leaving'; a.served = true
                            b.state = 'leaving'; b.served = true
                            table.insert(to_leave, a)
                            table.insert(to_leave, b)
                            add_log(string.format('Customers exchanged: %s<->%s', a.want, b.want))
                        end
                    end
                end
            end
        end
    end
end

function love.mousepressed(x, y, button)
    -- Convert screen coordinates to world coordinates
    local wx = x / camera.scale + camera.x
    local wy = y / camera.scale + camera.y
    if button == 1 then
        -- Place charged tower blueprint
        local req = {}
        for k, v in pairs(C.TOWER_COST.charged) do req[k] = v end
        table.insert(blueprints, {
            x = wx, y = wy, required = req, progress = {}, complete = false, towerType = 'charged'
        })
        add_log('Blueprint placed: charged tower')
    elseif button == 2 then
        -- Place auto tower blueprint
        local req = {}
        for k, v in pairs(C.TOWER_COST.auto) do req[k] = v end
        table.insert(blueprints, {
            x = wx, y = wy, required = req, progress = {}, complete = false, towerType = 'auto'
        })
        add_log('Blueprint placed: auto tower')
    end
end

-- Variable for distance input for direction flags
flag_direction_distance_input = nil

function love.textinput(text)
    -- Only accept digits for distance specification, buffer them
    if tonumber(text) then
        flag_direction_distance_input = (flag_direction_distance_input or "") .. text
    end
end

function love.keypressed(key)
    if key == "return" and flag_direction_distance_input then
        -- Reset buffer on Enter/Return
        flag_direction_distance_input = tonumber(flag_direction_distance_input)
        add_log("Set arrow flag distance to: " .. tostring(flag_direction_distance_input))
        return
    end
    if key == "b" then
        -- Place Barack blueprint at player position
        local px = player.x + player.size / 2
        local py = player.y + player.size / 2
        local req = {}
        for resource, amount in pairs(C.BARACK_COST) do req[resource] = amount end
        table.insert(barack_blueprints, {
            x = px, y = py, required = req, progress = {}, complete = false
        })
        add_log('Blueprint placed: barack')
    end
    -- Remove nearest flag or barack
    if key == "r" then
        remove_nearest_flag_or_barack()
    end
    -- Place directional flag with arrow keys
    local dir = nil
    if key == "up" then
        dir = "up"
    elseif key == "down" then
        dir = "down"
    elseif key == "left" then
        dir = "left"
    elseif key == "right" then
        dir = "right"
    end
    if dir then
        local px = player.x + player.size / 2
        local py = player.y + player.size / 2
        -- Use distance from input or the default from constants
        local distance = tonumber(flag_direction_distance_input) or C.DIR_FLAG_DEFAULT_DISTANCE
        local hp = C.FLAG_HP and (C.FLAG_HP["dir"] or 3) or 3
        table.insert(flags, {
            x = px,
            y = py,
            flag_type = "dir",
            dir = dir,
            distance = distance,
            remaining = distance, -- refreshed for each robot reading flag
            hp = hp,
        })
        add_log("Flag placed: " .. dir .. " with distance " .. tostring(distance))
        flag_direction_distance_input = nil -- clear for next use
    end
    -- Command flags
    if key == "1" then
        -- Chop Wood flag
        local px = player.x + player.size / 2
        local py = player.y + player.size / 2
        local hp = C.FLAG_HP and (C.FLAG_HP["chop_wood"] or 3) or 3
        table.insert(flags, {
            x = px,
            y = py,
            flag_type = "chop_wood",
            hp = hp,
        })
        add_log("Flag placed: chop wood")
    elseif key == "2" then
        -- Collect Wood flag
        local px = player.x + player.size / 2
        local py = player.y + player.size / 2
        local hp = C.FLAG_HP and (C.FLAG_HP["collect_wood"] or 3) or 3
        table.insert(flags, {
            x = px,
            y = py,
            flag_type = "collect_wood",
            hp = hp,
        })
        add_log("Flag placed: collect wood")
    elseif key == "3" then
        -- Splitter flag
        local px = player.x + player.size / 2
        local py = player.y + player.size / 2
        local hp = C.FLAG_HP and (C.FLAG_HP["splitter"] or 3) or 3
        table.insert(flags, {
            x = px,
            y = py,
            flag_type = "splitter",
            hp = hp,
        })
        add_log("Flag placed: splitter")
    elseif key == "4" then
        -- Build Something flag
        local px = player.x + player.size / 2
        local py = player.y + player.size / 2
        local hp = C.FLAG_HP and (C.FLAG_HP["build_something"] or 3) or 3
        table.insert(flags, {
            x = px,
            y = py,
            flag_type = "build_something",
            hp = hp,
        })
        add_log("Flag placed: build something")
    end
end

function love.draw()
    love.graphics.push()
    love.graphics.scale(camera.scale, camera.scale)
    love.graphics.translate(-camera.x, -camera.y)
    TiledMap_DrawNearCam(WIDTH / 2, HEIGHT / 2)
    -- Draw resource sources (only progress bars, no overlay)
    for _, src in ipairs(resource_sources) do
        if src.active then
            local bar_w, bar_h = TILE_SIZE * 0.6, 3
            local bar_x = src.x + (TILE_SIZE - bar_w) / 2
            local bar_y = src.y - 6
            love.graphics.setColor(0, 0, 0)
            love.graphics.rectangle('fill', bar_x, bar_y, bar_w, bar_h)
            love.graphics.setColor(0, 1, 0)
            love.graphics.rectangle('fill', bar_x, bar_y, bar_w * src.hp / src.max_hp, bar_h)
            love.graphics.setColor(1, 1, 1, 1)
        end
    end

    -- Draw flag HP bars (green, like resources/towers)
    for _, flag in ipairs(flags) do
        if flag.hp and flag.hp > 0 and C.FLAG_HP and C.FLAG_HP[flag.flag_type or "dir"] then
            local bar_w, bar_h = TILE_SIZE * 0.6, 3
            local bar_x = flag.x - bar_w / 2
            local bar_y = flag.y - TILE_SIZE / 2 - 10
            love.graphics.setColor(0, 0, 0)
            love.graphics.rectangle('fill', bar_x, bar_y, bar_w, bar_h)
            love.graphics.setColor(0, 1, 0)
            love.graphics.rectangle('fill', bar_x, bar_y,
                bar_w * math.max(0, flag.hp) / C.FLAG_HP[flag.flag_type or "dir"], bar_h)
            love.graphics.setColor(1, 1, 1, 1)
        end
    end
    -- Draw towers
    for _, tower in ipairs(towers) do
        local alpha = 1
        if not tower.built then alpha = 0.3 end
        if tower.towerType == 'charged' then
            love.graphics.setColor(0.39, 0.39, 1, alpha)
            love.graphics.circle('fill', tower.x, tower.y, 8)
            love.graphics.setColor(0, 0, 0, alpha)
            love.graphics.circle('fill', tower.x, tower.y, 2)
        else
            love.graphics.setColor(0.39, 0.39, 1, alpha)
            love.graphics.rectangle('fill', tower.x - 8, tower.y - 8, 16, 16)
            love.graphics.setColor(0, 0, 0, alpha)
            love.graphics.circle('fill', tower.x, tower.y, 2)
        end
        love.graphics.setColor(0.39, 0.39, 1, 0.2 * alpha)
        love.graphics.circle('line', tower.x, tower.y, tower.range)
        -- Draw ammo for charged towers as 4x4 colored squares above the tower
        if tower.towerType == 'charged' then
            local i = 0
            for _, rtype in ipairs(RESOURCE_TYPES) do
                local n = tower.ammo[rtype.name] or 0
                for j = 1, n do
                    local x = tower.x - 2
                    local y = tower.y - 12 - i * 6
                    love.graphics.setColor(rtype.color)
                    if rtype.shape == 'circle' then
                        love.graphics.circle('fill', x + 2, y + 2, 2)
                        love.graphics.setColor(0.7, 0.6, 0.1)
                        love.graphics.circle('line', x + 2, y + 2, 2)
                    else
                        love.graphics.rectangle('fill', x, y, 4, 4)
                        love.graphics.setColor(0, 0, 0)
                        love.graphics.rectangle('line', x, y, 4, 4)
                    end
                    love.graphics.setColor(1, 1, 1, 1)
                    i = i + 1
                end
            end
        end
        -- Draw HP bar above tower
        local max_hp = C.TOWER_HP
        if tower.hp then
            local bar_w, bar_h = 16, 3
            local bar_x = tower.x - bar_w / 2
            local bar_y = tower.y - 14
            love.graphics.setColor(0, 0, 0)
            love.graphics.rectangle('fill', bar_x, bar_y, bar_w, bar_h)
            love.graphics.setColor(1, 0, 0)
            love.graphics.rectangle('fill', bar_x, bar_y, bar_w * math.max(0, tower.hp) / max_hp, bar_h)
            love.graphics.setColor(1, 1, 1, 1)
        end
        love.graphics.setColor(1, 1, 1, 1)
    end
    -- Draw enemies (show if carrying resource)
    for _, enemy in ipairs(enemies) do
        love.graphics.setColor(ENEMY_COLOR)
        love.graphics.rectangle('fill', enemy.x, enemy.y, ENEMY_SIZE, ENEMY_SIZE)
        love.graphics.setColor(1, 1, 1, 1)
        -- Draw HP bar above enemy
        if enemy.health then
            local bar_w, bar_h = ENEMY_SIZE, 3
            local bar_x = enemy.x
            local bar_y = enemy.y - 6
            love.graphics.setColor(0, 0, 0)
            love.graphics.rectangle('fill', bar_x, bar_y, bar_w, bar_h)
            love.graphics.setColor(1, 0, 0)
            love.graphics.rectangle('fill', bar_x, bar_y, bar_w * math.max(0, enemy.health) / ENEMY_HEALTH, bar_h)
            love.graphics.setColor(1, 1, 1, 1)
        end
        -- Draw carried resources as colored squares above the enemy (like player)
        if enemy.carry then
            for i, r in ipairs(enemy.carry) do
                local color, shape
                for _, t in ipairs(RESOURCE_TYPES) do if t.name == r then color, shape = t.color, t.shape end end
                local x = enemy.x + ENEMY_SIZE / 2 - 2
                local y = enemy.y - 12 - (i - 1) * 8
                love.graphics.setColor(color)
                if shape == 'circle' then
                    love.graphics.circle('fill', x + 2, y + 2, 2)
                    love.graphics.setColor(0.7, 0.6, 0.1)
                    love.graphics.circle('line', x + 2, y + 2, 2)
                else
                    love.graphics.rectangle('fill', x, y, 4, 4)
                    love.graphics.setColor(0, 0, 0)
                    love.graphics.rectangle('line', x, y, 4, 4)
                end
                love.graphics.setColor(1, 1, 1, 1)
            end
        end
        if enemy.carrying_resource then -- legacy, for drop logic
            for _, t in ipairs(RESOURCE_TYPES) do
                if t.name == enemy.carrying_resource then
                    local x = enemy.x + ENEMY_SIZE / 2 - 2
                    local y = enemy.y - 8
                    love.graphics.setColor(t.color)
                    love.graphics.rectangle('fill', x, y, 4, 4)
                    love.graphics.setColor(0, 0, 0)
                    love.graphics.rectangle('line', x, y, 4, 4)
                    love.graphics.setColor(1, 1, 1, 1)
                end
            end
        end
    end
    -- Draw bullets
    for _, b in ipairs(bullets) do
        local color = { 1, 1, 0 } -- default yellow
        if b.resource_type then
            for _, t in ipairs(RESOURCE_TYPES) do
                if t.name == b.resource_type then
                    color = t.color
                    break
                end
            end
        end
        love.graphics.setColor(color)
        love.graphics.circle('fill', b.x, b.y, 5)
        love.graphics.setColor(1, 1, 1, 1)
    end
    -- Draw player
    love.graphics.setColor(PLAYER_COLOR)
    love.graphics.rectangle('fill', player.x, player.y, PLAYER_SIZE, PLAYER_SIZE)
    love.graphics.setColor(1, 1, 1, 1)
    -- Draw resource items (fixed at world position, 4x4 pixels)
    for _, item in ipairs(resource_items) do
        if not item.picked and item.type then
            love.graphics.setColor(item.type.color)
            if item.type.shape == 'circle' then
                love.graphics.circle('fill', item.x + 2, item.y + 2, 2)
                love.graphics.setColor(0.7, 0.6, 0.1)
                love.graphics.circle('line', item.x + 2, item.y + 2, 2)
            else
                love.graphics.rectangle('fill', item.x, item.y, 4, 4)
                love.graphics.setColor(0, 0, 0)
                love.graphics.rectangle('line', item.x, item.y, 4, 4)
            end
            love.graphics.setColor(1, 1, 1, 1)
        end
    end
    -- Draw blueprints (show required resources above, 30% transparent if not fulfilled, opaque if fulfilled)
    for _, bp in ipairs(blueprints) do
        if not bp.complete then
            local alpha = 0.5
            if bp.towerType == 'charged' then
                love.graphics.setColor(0.39, 0.39, 1, alpha)
                love.graphics.circle('fill', bp.x, bp.y, 8)
                love.graphics.setColor(0, 0, 0, alpha)
                love.graphics.circle('fill', bp.x, bp.y, 2)
            else
                love.graphics.setColor(0.39, 0.39, 1, alpha)
                love.graphics.rectangle('fill', bp.x - 8, bp.y - 8, 16, 16)
                love.graphics.setColor(0, 0, 0, alpha)
                love.graphics.circle('fill', bp.x, bp.y, 2)
            end
            love.graphics.setColor(0.39, 0.39, 1, 0.1)
            love.graphics.circle('line', bp.x, bp.y, TOWER_RANGE)
            -- Draw required resources above blueprint
            local i = 0
            for _, rtype in ipairs(RESOURCE_TYPES) do
                local req = bp.required[rtype.name]
                if req then
                    local done = (bp.progress and (bp.progress[rtype.name] or 0) or 0)
                    for j = 1, req do
                        local x = bp.x - 10 + i * 8
                        local y = bp.y - 24
                        if done >= j then
                            love.graphics.setColor(rtype.color)
                            if rtype.shape == 'circle' then
                                love.graphics.circle('fill', x + 2, y + 2, 2)
                                love.graphics.setColor(0.7, 0.6, 0.1)
                                love.graphics.circle('line', x + 2, y + 2, 2)
                            else
                                love.graphics.rectangle('fill', x, y, 4, 4)
                                love.graphics.setColor(0, 0, 0)
                                love.graphics.rectangle('line', x, y, 4, 4)
                            end
                        else
                            love.graphics.setColor(rtype.color[1], rtype.color[2], rtype.color[3], 0.3)
                            if rtype.shape == 'circle' then
                                love.graphics.circle('fill', x + 2, y + 2, 2)
                                love.graphics.setColor(0.7, 0.6, 0.1, 0.3)
                                love.graphics.circle('line', x + 2, y + 2, 2)
                            else
                                love.graphics.rectangle('fill', x, y, 4, 4)
                                love.graphics.setColor(0, 0, 0, 0.3)
                                love.graphics.rectangle('line', x, y, 4, 4)
                            end
                        end
                        love.graphics.setColor(1, 1, 1, 1)
                        i = i + 1
                    end
                end
            end
        end
    end

    -- Draw barack blueprints (purple, translucent if incomplete)
    for _, bp in ipairs(barack_blueprints) do
        love.graphics.setColor(0.6, 0.3, 1.0, 0.4)
        love.graphics.rectangle('fill', bp.x - 12, bp.y - 12, 24, 24)
        -- Draw required resources above blueprint
        local i = 0
        for _, rtype in ipairs(RESOURCE_TYPES) do
            local req = bp.required[rtype.name]
            if req then
                local done = (bp.progress and (bp.progress[rtype.name] or 0) or 0)
                for j = 1, req do
                    local x = bp.x - 10 + i * 8
                    local y = bp.y - 24
                    if done >= j then
                        love.graphics.setColor(rtype.color)
                        love.graphics.rectangle('fill', x, y, 4, 4)
                        love.graphics.setColor(0, 0, 0)
                        love.graphics.rectangle('line', x, y, 4, 4)
                    else
                        love.graphics.setColor(rtype.color[1], rtype.color[2], rtype.color[3], 0.3)
                        love.graphics.rectangle('fill', x, y, 4, 4)
                        love.graphics.setColor(0, 0, 0, 0.3)
                        love.graphics.rectangle('line', x, y, 4, 4)
                    end
                    love.graphics.setColor(1, 1, 1, 1)
                    i = i + 1
                end
            end
        end
    end

    -- Draw completed Baracks (solid purple squares)
    for _, barack in ipairs(baracks) do
        love.graphics.setColor(0.6, 0.3, 1.0, 1.0)
        love.graphics.rectangle('fill', barack.x - 12, barack.y - 12, 24, 24)

        -- No resource delivery UI needed for free spawning, just display Barack
    end

    -- Draw robots (size matches player/enemy)
    for _, robot in ipairs(robots) do
        love.graphics.setColor(0.55, 0.55, 0.55, 1)
        love.graphics.rectangle('fill', robot.x - PLAYER_SIZE / 2, robot.y - PLAYER_SIZE / 2, PLAYER_SIZE, PLAYER_SIZE)
        love.graphics.setColor(0.22, 0.22, 0.22, 1)
        love.graphics.rectangle('line', robot.x - PLAYER_SIZE / 2, robot.y - PLAYER_SIZE / 2, PLAYER_SIZE, PLAYER_SIZE)
        -- Draw carried wood (or other resource) above their head, like the player
        if robot.resource == "wood" then
            love.graphics.setColor(0.545, 0.27, 0.074, 1) -- wood color
            love.graphics.rectangle('fill', robot.x - 4, robot.y - PLAYER_SIZE / 2 - 10, 8, 8)
            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.rectangle('line', robot.x - 4, robot.y - PLAYER_SIZE / 2 - 10, 8, 8)
            love.graphics.setColor(1, 1, 1, 1)
        end
        -- Draw chop wood flag visual (axe icon) if at a chop_wood flag
        if robot.current_flag and robot.current_flag.flag_type == "chop_wood" then
            love.graphics.setColor(0.4, 0.22, 0.11, 1)
            love.graphics.rectangle('fill', robot.current_flag.x - 5, robot.current_flag.y - 18, 10, 10)
            love.graphics.setColor(0.7, 0.7, 0.7, 1)
            love.graphics.rectangle('fill', robot.current_flag.x - 2, robot.current_flag.y - 18, 4, 5)
            love.graphics.setColor(1, 1, 1, 1)
        end
    end

    -- Draw debug: line from each robot to the flag it is currently executing or approaching
    for _, robot in ipairs(robots) do
        --[[
        if robot.current_flag then
            love.graphics.setColor(1, 0.1, 0.1, 0.7)
            love.graphics.setLineWidth(2)
            love.graphics.line(robot.x, robot.y, robot.current_flag.x, robot.current_flag.y)
        elseif robot.target_flag then
            -- While approaching a flag, line still shows the target
            love.graphics.setColor(1, 0.3, 0.3, 0.5)
            love.graphics.setLineWidth(1)
            love.graphics.line(robot.x, robot.y, robot.target_flag.x, robot.target_flag.y)
        end
        --]]
    end

    -- Draw flags (directional and command)
    for _, flag in ipairs(flags) do
        local size = 16
        local x = flag.x
        local y = flag.y
        -- Draw flag command radius visualization (for all flag types)
        love.graphics.setColor(0, 0.4, 1, 0.15)
        love.graphics.circle("fill", x, y, C.FLAG_COMMAND_RADIUS)
        love.graphics.setColor(0, 0.2, 0.5, 0.3)
        love.graphics.circle("line", x, y, C.FLAG_COMMAND_RADIUS)
        -- Draw the flag itself as before
        if flag.flag_type == "dir" and flag.dir then
            local arrow_col = { up = { 0, 0.7, 1 }, down = { 1, 0.7, 0 }, left = { 1, 0.2, 0.2 }, right = { 0.2, 1, 0.2 } }
            love.graphics.setColor(arrow_col[flag.dir][1], arrow_col[flag.dir][2], arrow_col[flag.dir][3], 1)
            love.graphics.push()
            love.graphics.translate(x, y)
            if flag.dir == "up" then
                love.graphics.polygon("fill", 0, -size / 2, -size / 3, size / 3, size / 3, size / 3)
            elseif flag.dir == "down" then
                love.graphics.polygon("fill", 0, size / 2, -size / 3, -size / 3, size / 3, -size / 3)
            elseif flag.dir == "left" then
                love.graphics.polygon("fill", -size / 2, 0, size / 3, -size / 3, size / 3, size / 3)
            elseif flag.dir == "right" then
                love.graphics.polygon("fill", size / 2, 0, -size / 3, -size / 3, -size / 3, size / 3)
            end
            love.graphics.setColor(0, 0, 0, 1)
            -- Draw an outline
            if flag.dir == "up" then
                love.graphics.polygon("line", 0, -size / 2, -size / 3, size / 3, size / 3, size / 3)
            elseif flag.dir == "down" then
                love.graphics.polygon("line", 0, size / 2, -size / 3, -size / 3, size / 3, -size / 3)
            elseif flag.dir == "left" then
                love.graphics.polygon("line", -size / 2, 0, size / 3, -size / 3, size / 3, size / 3)
            elseif flag.dir == "right" then
                love.graphics.polygon("line", size / 2, 0, -size / 3, -size / 3, -size / 3, size / 3)
            end
            -- Draw distance text for direction flags
            if flag.distance then
                love.graphics.setColor(0.1, 0.1, 0.1, 0.7)
                love.graphics.setColor(1, 1, 1, 1)
            end
            love.graphics.pop()
        elseif flag.flag_type == "collect_wood" then
            -- Draw a simple brown square with a "W" for wood (collect ground item)
            love.graphics.setColor(0.5, 0.3, 0.1, 0.85)
            love.graphics.rectangle("fill", x - size / 2, y - size / 2, size, size)
            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.rectangle("line", x - size / 2, y - size / 2, size, size)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.printf("W", x - size / 2, y - 8, size, "center")
        elseif flag.flag_type == "chop_wood" then
            -- Draw a simple brown square with "CW" for chop wood
            love.graphics.setColor(0.5, 0.3, 0.1, 0.85)
            love.graphics.rectangle("fill", x - size / 2, y - size / 2, size, size)
            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.rectangle("line", x - size / 2, y - size / 2, size, size)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.printf("CW", x - size / 2, y - 10, size, "center")
        elseif flag.flag_type == "splitter" then
            -- Draw a blue square with "< >" for splitter
            love.graphics.setColor(0.2, 0.45, 1, 0.85)
            love.graphics.rectangle("fill", x - size / 2, y - size / 2, size, size)
            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.rectangle("line", x - size / 2, y - size / 2, size, size)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.printf("< >", x - size / 2, y - 10, size, "center")
        end
    end
    -- Draw carried resources above player (small 4x4 squares/circles)
    for i, r in ipairs(player_carry) do
        local color, shape
        for _, t in ipairs(RESOURCE_TYPES) do if t.name == r then color, shape = t.color, t.shape end end
        local x = player.x + player.size / 2 - 2
        local y = player.y - 8 - (i - 1) * 8
        love.graphics.setColor(color)
        if shape == 'circle' then
            love.graphics.circle('fill', x + 2, y + 2, 2)
            love.graphics.setColor(0.7, 0.6, 0.1)
            love.graphics.circle('line', x + 2, y + 2, 2)
        else
            love.graphics.rectangle('fill', x, y, 4, 4)
            love.graphics.setColor(0, 0, 0)
            love.graphics.rectangle('line', x, y, 4, 4)
        end
        love.graphics.setColor(1, 1, 1, 1)
    end

    -- Draw build_something flag visuals
    for _, flag in ipairs(flags) do
        if flag.flag_type == "build_something" then
            local size = 16
            local x = flag.x
            local y = flag.y
            love.graphics.setColor(1, 0.65, 0, 0.9)
            love.graphics.rectangle("fill", x - size / 2, y - size / 2, size, size)
            love.graphics.setColor(0, 0, 0, 1)
            love.graphics.rectangle("line", x - size / 2, y - size / 2, size, size)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.printf("B", x - size / 2, y - 8, size, "center")
        end
    end
    -- Draw customers
    for _, cust in ipairs(customers) do
        love.graphics.setColor(CUSTOMER_COLOR)
        love.graphics.rectangle('fill', cust.x - CUSTOMER_SIZE / 2, cust.y - CUSTOMER_SIZE / 2, CUSTOMER_SIZE,
            CUSTOMER_SIZE)
        love.graphics.setColor(0, 0, 0)
        love.graphics.rectangle('line', cust.x - CUSTOMER_SIZE / 2, cust.y - CUSTOMER_SIZE / 2, CUSTOMER_SIZE,
            CUSTOMER_SIZE)
        love.graphics.setColor(1, 1, 1, 1)
        -- Draw what customer offers (carried resource, opaque) ONLY if waiting
        if cust.state == 'waiting' then
            for i = 1, (cust.offer_amount or 1) do
                local color, shape
                for _, t in ipairs(RESOURCE_TYPES) do if t.name == cust.offer then color, shape = t.color, t.shape end end
                local x = cust.x - 2 + (i - 1) * 6 - ((cust.offer_amount or 1) - 1) * 3
                local y = cust.y - CUSTOMER_SIZE / 2 - 16
                love.graphics.setColor(color)
                if shape == 'circle' then
                    love.graphics.circle('fill', x + 2, y + 2, 2)
                    love.graphics.setColor(0.7, 0.6, 0.1)
                    love.graphics.circle('line', x + 2, y + 2, 2)
                else
                    love.graphics.rectangle('fill', x, y, 4, 4)
                    love.graphics.setColor(0, 0, 0)
                    love.graphics.rectangle('line', x, y, 4, 4)
                end
                love.graphics.setColor(1, 1, 1, 1)
            end
        end
        -- Draw what customer wants (30% alpha, possibly multiple) ONLY if waiting
        if cust.state == 'waiting' then
            for i = 1, (cust.want_amount or 1) do
                for _, t in ipairs(RESOURCE_TYPES) do
                    if t.name == cust.want then
                        local x = cust.x - 2 + (i - 1) * 6 - ((cust.want_amount or 1) - 1) * 3
                        local y = cust.y - CUSTOMER_SIZE / 2 - 8
                        love.graphics.setColor(t.color[1], t.color[2], t.color[3], 0.3)
                        if t.shape == 'circle' then
                            love.graphics.circle('fill', x + 2, y + 2, 2)
                            love.graphics.setColor(0.7, 0.6, 0.1, 0.3)
                            love.graphics.circle('line', x + 2, y + 2, 2)
                        else
                            love.graphics.rectangle('fill', x, y, 4, 4)
                            love.graphics.setColor(0, 0, 0, 0.3)
                            love.graphics.rectangle('line', x, y, 4, 4)
                        end
                        love.graphics.setColor(1, 1, 1, 1)
                    end
                end
            end
        end
        -- After purchase, show what they received (the want resource) above their head as they leave
        if cust.state == 'leaving' and cust.served then
            for i = 1, (cust.want_amount or 1) do
                for _, t in ipairs(RESOURCE_TYPES) do
                    if t.name == cust.want then
                        local x = cust.x - 2 + (i - 1) * 6 - ((cust.want_amount or 1) - 1) * 3
                        local y = cust.y - CUSTOMER_SIZE / 2 - 12
                        love.graphics.setColor(t.color)
                        if t.shape == 'circle' then
                            love.graphics.circle('fill', x + 2, y + 2, 2)
                            love.graphics.setColor(0.7, 0.6, 0.1)
                            love.graphics.circle('line', x + 2, y + 2, 2)
                        else
                            love.graphics.rectangle('fill', x, y, 4, 4)
                            love.graphics.setColor(0, 0, 0)
                            love.graphics.rectangle('line', x, y, 4, 4)
                        end
                        love.graphics.setColor(1, 1, 1, 1)
                    end
                end
            end
        end
    end
    love.graphics.pop()
    -- Draw raid countdown message in screen space (UI)
    if raid_message then
        love.graphics.setColor(1, 0.2, 0.2, 1)
        love.graphics.setFont(love.graphics.newFont(32))
        local text = raid_message
        local tw = love.graphics.getFont():getWidth(text)
        love.graphics.print(text, WIDTH / 2 - tw / 2, 40)
        love.graphics.setColor(1, 1, 1, 1)
    end
end
