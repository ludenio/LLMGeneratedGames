# Custom instructions for Copilot

## Project overview
There is no graphics in the game except colored primitives drawn procedurally and tilemap loaded from map.tmx made with Tiled map editor.

## Core functionalities
The player explores a large map, collects resources, builds towers, and defends against waves of enemies. The game combines elements of action, strategy, and resource management.

## Doc
- `docs/instruction.md` - how to work on the project
- `docs/design.md` - project design
- `docs/todo.md` - list of tasks to implement

## Current file structure
- `*.md` - documentation
- `main.lua`, `logic.lua` - game logic
- `test.lua` - autotests
- (readonly, never change it, it's edidted with Tiled map editor only) `map.tmx` - map made in Tiled editor
- (readonly, never change it, it's edidted with Tiled map editor only) `tiles.png` - tilesheet texture to draw the map

## How to implement tasks
- Read the design.md file and instructions.md
- Find uncheck task in ToDo section of `docs/todo.md` file
- Analyze code and documentation to design structure
- Implement the task
- Run `love .` in command line and check if output doesn't containt errors. Fix if it does.
- Run autotests. Fix if tests are failed.
- If all is good - check the implemented task in ToDo section of `docs/todo.md` as done
