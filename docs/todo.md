# Development TODOs

This TODO list consolidates all development tasks for the project, including both high-level features and detailed mechanics for Barack, robots, and flags.

---

## General Tasks

- [x] Player movement and controls
- [x] Camera follows player
- [ ] Tiled map loading and rendering (`map.tmx`)
- [ ] Implement map building from the tiled map using Map Tile Code from `design.md`
- [ ] Resource nodes (wood, grass, stone, metal) placed from map
- [ ] Resource collection with progress/progress bar
- [ ] Resource respawn after timer
- [ ] Player inventory with carry limit
- [ ] Dropped resource items and pickup system
- [ ] Blueprint placement for towers
- [ ] Resource/coin investment to complete blueprints
- [ ] Tower construction and ammo management
- [ ] Towers fire at enemies within range
- [ ] Bullets with damage and enemy hit detection
- [ ] Enemy spawn zone and wave system
- [ ] Enemy AI: seek, move to resource, chop, escape, idle
- [ ] Enemies deplete resources and drop items on death
- [ ] Customer system: spawn, walk to checkout, request resource, reward coins
- [ ] Upgrade shop for faster chopping
- [ ] UI: carried resources, blueprints, coins, upgrade shop, enemy zone, wave indicator, towers' ammo
- [ ] Logging system for game events

---

## Barack & Robot Mechanics

- [x] Implement "Barack" building:
    - [x] Allow player to build/construct the Barack.
    - [x] Define Barack visuals and map placement logic. (Basic visuals present)
    - [ ] Enable Barack to accept resources for spawning robots. **(Partial, currently robots spawn on timer for testing)**
    - [ ] Reference robot price from `constants.lua`. **(Partial, TODO: make spawning require payment)**
- [x] Robot spawning from Barack:
    - [x] When resources reach threshold, spawn a robot (gray square) from Barack. **(Partial, see above)**
    - [x] Each robot starts by moving straight **up** from the Barack for the distance defined in `constants.lua` (`DIR_FLAG_DEFAULT_DISTANCE`), unless it finds a flag within range.

---

## Flag (Robot Command & Pathing) Mechanics

- [x] Implement "Flag" building:
    - [x] Allow player to place directional flag at cursor using arrow keys.
        - [x] Each directional flag has an associated *priority* (see `constants.lua`) which determines if it can interrupt other commands.
    - [x] Each directional flag sets a direction and distance for robots (distance from player input or defaults to `DIR_FLAG_DEFAULT_DISTANCE`).
    - [x] Each arrow key (up, down, left, right) places a flag with corresponding direction.
    - [ ] Define flag visual representation and orientation (arrows with optional distance indicator).
    - [x] Allow player to place command flags (flags which instruct robots to perform actions):
        - [ ] Key "1": Place "Chop Wood" flag (robot seeks out nearest wood node, makes **one chop** (hit), then self-destructs).
        - [ ] Key "2": Place "Collect Wood" flag (robot finds a *free wood item* dropped on the ground, picks it up, visibly carries it, delivers it to the shop, then self-destructs).
    - [ ] Define command flag visual representation (distinct from direction flags and with text for command).
    - [ ] Add/Document priorities for all flag types in `constants.lua`.

- [x] Robot logic and lifecycle (FINALIZED):
    - [x] Each robot, after spawning, moves **up** by `DIR_FLAG_DEFAULT_DISTANCE` unless it finds a flag first.
    - [x] If a flag (of any type) is within `FLAG_COMMAND_RADIUS` during movement, the robot compares the *priority* of its current command to the encountered flag:
        - [x] If the new flag's priority is higher, the robot interrupts its current command to execute the higher-priority flag.
        - [x] If the new flag's priority is equal or lower, the robot finishes its original command before responding to new flags.
    - [x] Directional flag: Move in specified direction for the (flag-specified or default) distance.
    - [x] Command flag (collect/deliver): Execute command, waiting until successful if needed.
    - [x] On completing **any instruction** (direction or command), the robot scans for another flag within `DIR_FLAG_DEFAULT_DISTANCE`, again using the same priority-based logic:
        - [x] If one is found, it executes the highest-priority flag in range.
        - [x] If **no flag** is found within this distance, it self-destructs and disappears.
    - [x] Robots carry at most one resource. They only respond to flags within the defined radii and will always switch to higher-priority flags immediately when found.
    - [x] Implement, test, and tweak interruption/priority logic for all robot actions.

---

## Planned/New Robot Flag Types (Future Implementation)

- [ ] Key "3": Collect Stone flag
    - Flag type: collect_stone
    - Command: Robot finds a free stone item dropped on the ground, picks it up, visibly carries it, delivers it to the shop, then self-destructs.
    - Priority: (to define in constants.lua, > directional, < deliver)
    - Visual: (distinct from collect wood)

- [ ] Key "4": Chop Stone flag
    - Flag type: chop_stone
    - Command: Robot seeks out nearest stone node, makes one chop (hit), then self-destructs.
    - Priority: (to define, > directional)
    - Visual: (distinct from chop wood)

- [ ] Key "5": Wait/Idle flag
    - Flag type: wait
    - Command: Robot remains idle at flag for set duration (or until interrupted).
    - Priority: (adjustable)
    - Visual: clock/halt symbol

- [ ] [Extend this section with additional command flags as designed, e.g., defend, patrol, etc.]

For each new flag, specify:
    - Key binding, flag_type string, command behavior, visual style, and priority value.

---

## Map, Rendering, and UI

- [ ] Add Barack and Flag entities to map and rendering systems.
- [ ] Display robots as gray squares.
- [ ] Display flags with arrows pointing in corresponding direction.
- [ ] Provide player feedback on flag/barack placement and robot movement.

---

## Config & Balancing

- [ ] Add robot spawn price to `constants.lua`.
- [ ] Make robot/flag relevant parameters easily configurable.

---

## Integration

- [ ] Integrate robot and flag mechanics with existing game update loop.
- [ ] Ensure new mechanics work with save/load systems (if present).

---

## Testing & Debugging

- [ ] Add or update tests for Barack, robots, and flags.
- [ ] Playtest new mechanics for balance and bugs.