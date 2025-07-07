-- logic.lua
-- Core logic functions for the Tower Defense Resource Game
-- See README.md for documentation and usage.

local M = {}

function M.dist(x1, y1, x2, y2)
    return ((x2-x1)^2 + (y2-y1)^2)^0.5
end

function M.can_collect(player, src, COLLECT_RADIUS)
    return src.active and M.dist(player.x, player.y, src.x, src.y) < COLLECT_RADIUS
end

function M.tower_select_ammo(ammo, RESOURCE_DAMAGE)
    local best_type, best_dmg = nil, 0
    for r,dmg in pairs(RESOURCE_DAMAGE) do
        if (ammo[r] or 0) > 0 and dmg > best_dmg then
            best_type, best_dmg = r, dmg
        end
    end
    return best_type, best_dmg
end

function M.enemy_find_nearest_resource(enemy, resource_sources, RESOURCE_SIZE, ENEMY_SIZE)
    local min_dist, target_src = math.huge, nil
    for _,src in ipairs(resource_sources) do
        if src.active then
            local d = M.dist(enemy.x+ENEMY_SIZE/2, enemy.y+ENEMY_SIZE/2, src.x+RESOURCE_SIZE/2, src.y+RESOURCE_SIZE/2)
            if d < min_dist then min_dist, target_src = d, src end
        end
    end
    return target_src, min_dist
end

return M
