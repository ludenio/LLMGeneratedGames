# Tower Defense Resource Game – Design Document

## Game Overview

This is a top-down tower defense/resource management game built with Love2D. The player explores a large map, collects resources, builds towers, and defends against waves of enemies. The game combines elements of action, strategy, and resource management.

## Core Gameplay Loop

1. **Explore the Map:**  
   The player moves around a large tiled map, searching for resource nodes (wood, grass, stone, metal).

2. **Collect Resources:**  
   The player collects resources from nodes, which respawn after a cooldown. Carrying capacity is limited.

3. **Build Towers:**  
   The player places blueprints for towers, then invests resources and coins to complete construction. Towers require ammo (resources) to fire.

4. **Defend Against Enemies:**  
   Entering the enemy zone triggers a wave of enemies. Enemies seek out and deplete resource nodes, then attempt to escape. Towers automatically attack enemies within range.

5. **Serve Customers:**  
   Customers periodically arrive at the checkout zone, requesting specific resources. Serving them rewards coins.

6. **Upgrade:**  
   The player can purchase upgrades (e.g., faster chopping) to improve efficiency.

## Key Features

### Implemented Mechanics

- **Player Movement:**  
  WASD/arrow keys to move. Camera follows the player.

- **Resource Nodes:**  
  Placed via Tiled map. Each node has HP and respawns after depletion. Resource types are loaded, and node placement is dynamic based on Tiled map.

- **Barack & Robots (Implemented):**
  - Players can build Barack blueprints and complete construction with resources.
  - Baracks spawn robots; currently, robots spawn on a timer for testing—future work will use a proper resource threshold.
  - Robots follow these core mechanics:
    1. On spawn, move straight up from Barack by `DIR_FLAG_DEFAULT_DISTANCE`, unless a flag is found first.
    2. During all states (moving or executing a command), the robot checks for flags within `FLAG_COMMAND_RADIUS`.
    3. **Command interrupt system is implemented:** If a flag in range has higher priority than the current task, the robot immediately switches; otherwise, it completes its current action.
    4. After completing a command/movement, if another flag is in range, it continues to the highest-priority flag, else self-destructs.
    5. Each robot may carry only one resource.
    6. Robots standard size now matches player and enemy for unified visuals.

- **Flag (Robot Command/Pathing) (Implemented):**
  - Player can place:
    - **Directional Flags** (arrow keys): direction + distance; default if omitted. Priority is determined in `constants.lua`.
    - **Command Flags**:
      - "Collect Wood" (key "2"): robot finds and picks up a free wood item from the ground, delivers it to the shop, then self-destructs.
      - "Chop Wood" (key "1"): robot seeks out the nearest wood node, performs a single chop (reducing its HP by 1), and then self-destructs.
      - "Splitter" (key "3"): first robot that reaches this flag moves left, the next moves right, alternating for each.
      - "Build Something" (key "4"): if robot carries a resource, seeks an unfinished tower blueprint that still needs that resource, delivers it, and self-destructs.
  - Flags have HP (see below), can be destroyed by enemy destroyers, and respect priority/interruption as per `constants.lua`.

- **Inventory:**  
  Limited carrying capacity for resources.

### Planned & Expandable Features

- **Planned/Upgradable Flag Types:**  
  (See section below: "Planned Robot Flag Types")

- **Blueprints & Towers:**  
  Place blueprints, invest resources/coins, and build towers. Towers require ammo to function.

- **Enemies:**  
  Spawn in waves and choose one of two roles:
    - **Destroyer:** Targets a random player flag on the map, attacks it once (reducing its HP by 1), and then self-destructs. If the flag's HP drops to 0, it is destroyed and removed.
    - **Resource Stealer:** Finds the nearest free resource item on the ground (not carried by player/robot), picks it up, and then self-destructs (removing the resource item).
  Enemies do not prioritize attacking towers or resource nodes anymore.

- **Customers:**  
  Request resources at the checkout zone, serve them for coins.

- **Upgrade Shop:**  
  Spend coins for permanent upgrades.

- **UI:**  
  Displays carried resources, coins, blueprints, tower ammo, wave info, and logs.

- **Blueprints & Towers:**  
  Place blueprints, invest resources/coins, and build towers. Towers require ammo to function.

- **Enemies:**  
  Spawn in waves, seek resources, and escape after depleting nodes. Drop resources on death.

- **Customers:**  
  Request resources at the checkout zone. Serve them for coins.

- **Upgrade Shop:**  
  Spend coins for permanent upgrades.

- **UI:**  
  Displays carried resources, coins, blueprints, tower ammo, wave info, and logs.

## Visuals

- **Tile-based Map:**  
  Rendered from a Tiled map file and tileset.
- **Sprites:**  
  Simple colored rectangles for player, enemies, resources, towers, and customers.
- **UI Elements:**  
  Resource bars, progress bars, and log messages.

## Technical Notes

- **Engine:** Love2D (Lua)
- **Map:** Loaded from Tiled `.tmx` and `.lua` files using `tiledmap.lua`.
- **Testing:** Busted unit tests for core logic.

## Win/Lose Conditions

- **Win:** No explicit win condition; the game is score/challenge-based.
- **Lose:** Not defined; the player is challenged to survive and optimize resource management.
---

## Example Robot and Flag Scenarios (Current Implementation)

A. **Default Move and Self-Destruct:**  
   - Robot spawns from Barack, moves straight up by `DIR_FLAG_DEFAULT_DISTANCE`, never encounters any flag, and self-destructs.

B. **Directional Flag Use:**  
   - Robot spawns, moves up, encounters a "Right" directional flag within `FLAG_COMMAND_RADIUS`, moves right by the specified (or default) distance, finds no further flags, and self-destructs.

C. **Collect and Chop Wood (Command):**  
   - "Collect Wood" flag: Robot finds a ground wood item, picks it up, delivers to shop, then self-destructs.
   - "Chop Wood" flag: Robot seeks out the nearest wood node, hits it once, then self-destructs.

D. **Splitter & Building:**  
   - "Splitter" flag: First robot arriving goes left, second right, alternately, before resuming normal flag logic.
   - "Build Something" flag: Robot with a resource finds a matching, unbuilt tower blueprint, invests resource, then self-destructs.

E. **Enemy Behaviors:**  
   - *Destroyer*: Picks a random flag, attacks it once, then self-destructs (flag can be destroyed if HP is 0).
   - *Resource Stealer*: Seeks out a ground resource item, destroys it (removes from world), then self-destructs.

F. **Priority/Interruption System:**  
   - Robot always switches to higher-priority commands if a suitable flag is in range. Otherwise, finishes current action before considering lower or equal priorities.


---

## Planned Robot Flag Types

This section documents new types of flag commands for robots that are not yet implemented, but are planned for the next development phase. Each new flag type will have a key binding, a user-facing description, a flag type string, and a defined priority in `constants.lua`.

**Examples of future/planned flags:**
- **Collect Stone** (`key "3"`): Robot seeks and mines the nearest stone node.
- **Deliver to Barack** (`key "4"`): Robot brings a carried resource to the nearest Barack.
- **Wait/Idle** (`key "5"`): Robot pauses in place for a set duration or until a higher-priority command arrives.
- **Defend Location**: Park the robot at the flag for some time, or act as a static defender (future purpose).
- **Custom/Scripted Sequence**: More advanced programmable behaviors (long-term goal).

For each planned flag type, specify:
- Flag display/visual
- Key binding
- Command logic/robot behavior
- Priority (in `constants.lua`)
- Any required resources for the action (if applicable)

---

## Example Session

1. Player collects wood and stone from resource nodes.
2. Places a tower blueprint, invests resources and coins to build it.
3. Constructs a Barack and delivers enough resources to spawn robots.
4. Barack spawns a robot (gray square).
5. Player places a "Collect Wood" flag (key "1") in the robot's path. The robot seeks out a wood node, mines/waits until wood is obtained, and then checks for a follow-up flag.
6. If a "Deliver to Shop" flag (key "2") is nearby, the robot delivers the wood to the shop; if not, the robot self-destructs.
7. If the robot encounters a directional flag (arrow keys), it moves in the specified direction for the set distance, then repeats its flag search/destruct logic.
8. Triggers an enemy wave; towers fire at enemies using loaded ammo.
9. Collects dropped resources, serves a customer, and upgrades chop speed.

---

This document provides a high-level understanding of the game's mechanics, flow, and technical structure.

---

# Map Tile Code

- Tile ID 50 = wood
- Tile ID 103 = stone
- Tile ID 310 = grass
- Tile ID 980 = enemy spawn zone
- Tile ID 746 = customer checkout shop zone
- Tile ID 997 = upgrades zone
- Tile ID 68 = metal

# Flag HP and Map Building

- All flags are destructible, with HP per type defined in `constants.lua`. Enemies with the destroyer role will target and damage these flags.
- The map is built by reading the Tiled `.tmx` file (`map.tmx`).
- Resource nodes (wood, stone, grass, metal) are placed at tiles with the corresponding Tile IDs as listed above.
- Enemy spawn zone, customer shop zone, and upgrade shop are placed at their respective Tile IDs.
- Metal resource is now mapped from the Tiled map using Tile ID 68.
- All other tiles are considered walkable/empty for player placement.



---

## Notes for Future Iterations

- To add a new resource type (e.g., metal) as a map-placed node:
  1. Assign a unique tile ID for the resource in Tiled and update the tileset.
  2. Add the tile ID to the Map Tile Code section above.
  3. Update the resource placement code in `main.lua` to include the new tile ID.
  4. Update this document to reflect the change.
- Keep this document in sync with the code and Tiled map for clarity and maintainability.


