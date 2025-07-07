-- tests.lua
-- Busted tests for logic.lua (Tower Defense Resource Game)
-- See README.md for documentation and usage.

local logic = require 'logic'

describe('logic.dist', function()
  it('returns correct Euclidean distance', function()
    assert.is_true(math.abs(logic.dist(0,0,3,4) - 5) < 1e-6)
    assert.is_true(math.abs(logic.dist(1,2,1,2) - 0) < 1e-6)
  end)
end)

describe('logic.can_collect', function()
  it('returns true if player is within radius and resource is active', function()
    local player = {x=0, y=0}
    local src = {x=0, y=10, active=true}
    assert.is_true(logic.can_collect(player, src, 15))
  end)
  it('returns false if resource is inactive', function()
    local player = {x=0, y=0}
    local src = {x=0, y=10, active=false}
    assert.is_false(logic.can_collect(player, src, 15))
  end)
  it('returns false if player is out of radius', function()
    local player = {x=0, y=0}
    local src = {x=0, y=20, active=true}
    assert.is_false(logic.can_collect(player, src, 15))
  end)
end)

describe('logic.tower_select_ammo', function()
  it('selects highest damage ammo available', function()
    local ammo = {wood=1, stone=2}
    local RESOURCE_DAMAGE = {wood=1, grass=2, stone=3, metal=4}
    local t, dmg = logic.tower_select_ammo(ammo, RESOURCE_DAMAGE)
    assert.are.equal('stone', t)
    assert.are.equal(3, dmg)
  end)
  it('returns nil if no ammo', function()
    local ammo = {}
    local RESOURCE_DAMAGE = {wood=1, grass=2, stone=3, metal=4}
    local t, dmg = logic.tower_select_ammo(ammo, RESOURCE_DAMAGE)
    assert.is_nil(t)
    assert.are.equal(0, dmg)
  end)
end)

describe('logic.enemy_find_nearest_resource', function()
  it('finds the closest active resource', function()
    local enemy = {x=0, y=0}
    local resource_sources = {
      {x=10, y=0, active=true},
      {x=100, y=0, active=true},
      {x=5, y=0, active=false}
    }
    local RESOURCE_SIZE, ENEMY_SIZE = 0, 0
    local src, dist = logic.enemy_find_nearest_resource(enemy, resource_sources, RESOURCE_SIZE, ENEMY_SIZE)
    assert.are.equal(resource_sources[1], src)
  end)
  it('returns nil if no active resources', function()
    local enemy = {x=0, y=0}
    local resource_sources = {
      {x=10, y=0, active=false},
      {x=100, y=0, active=false}
    }
    local RESOURCE_SIZE, ENEMY_SIZE = 0, 0
    local src, dist = logic.enemy_find_nearest_resource(enemy, resource_sources, RESOURCE_SIZE, ENEMY_SIZE)
    assert.is_nil(src)
  end)
end)
