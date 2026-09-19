# BLOOD SPLATTER: NINE CIRCLES

## Identity

First-person action roguelike. Fast, aggressive, movement-first.
Mechanical touchstones: ULTRAKILL, Hades, The Binding of Isaac, classic Doom, hack'n'slash.

This project is **not** related to any previous project. Do not import concepts,
architecture or naming from elsewhere.

## Stack

- Godot **4.7.2**
- Renderer: **Compatibility** (GL)
- Gameplay: **GDScript**
- Physics: Jolt
- Target: PC / Steam

## Current priority

**PROTOTYPE 0.2 — THE BOX: KINETIC FEEL.**

Prove **movement feel + combat feel** in one sandbox arena. Nothing else is in
scope: no roguelike, no procedural generation, no content.

Implemented: first person camera, WASD, mouse look, jump, dash, crouch, slide,
skill-based bunnyhop / air-strafe with a soft ceiling, momentum, dynamic FOV,
debug HUD, a placeholder **hand cannon** (semi-auto hitscan, ~0.6 s between
shots, 3 body shots or 1 headshot on the dummy, generous head hitbox, spin
animation as the cooldown tell), tracer / muzzle flash / recoil / hitmarker, a
dummy target with hit, headshot and death feedback, synthesised placeholder
audio, and one placeholder arena.

Weapon rules: **no automatic fire, no burst, no reload, infinite ammo.** The
fire cooldown belongs to the weapon, never to the movement controller — the
player can jump, dash, slide, bunnyhop and air-strafe freely through all of it.
Hit detection and presentation are separate: deleting every visual effect must
not change who takes damage or how much.

Not implemented and not to be added unsolicited: roguelike systems, procedural
generation, circles, bosses, save, progression, items, lore, final menus, final
art, the real gore system, production models or sprites, complex enemy AI, Steam
integration, heavy shaders.

## Performance philosophy

The game must run well on modest hardware. No expensive graphics feature gets
added without a reason. Prefer cheap, explicit solutions.

## No premature systems

Do not build:

- a large GameManager
- an EventBus with no consumers
- service architecture
- a custom ECS
- a generic state machine framework
- a dependency injection framework
- a combat framework for 100 weapons that do not exist
- autoloads that nothing needs

The future will need combat, weapons, enemies, 2.5D sprites (then low-poly
models), procedural chambers and roguelike items. Do **not** build speculative
abstractions for any of it now. Simple, explicit, easy to iterate on wins.

There is exactly **one autoload**, `Sfx` (`core/autoload/sfx.gd`): a fixed pool
of audio players plus synthesised placeholder sounds. It exists because the
player, the weapon and every enemy need to make noise from unrelated parts of
the tree. Adding a second autoload needs a reason that good.

## Working agreement

- Claude is the primary implementer.
- The **Godot runtime is the source of truth**. A script that parses is not a
  feature that works. Nothing is "validated" until the game has actually been
  run and played.
- Never commit or change git config without being asked.
- Movement numbers live in `data/movement/default_movement.tres` (schema:
  `gameplay/movement/movement_config.gd`). Combat and feedback numbers live in
  `data/combat/default_combat.tres` (schema:
  `gameplay/combat/combat_config.gd`). No magic numbers anywhere else.
- Anything temporary must clean itself up: tracers, impacts, audio players and
  death fragments are pooled or self-freeing, and `tests/movement_smoke_test.gd`
  asserts it.

## Layout

```
core/autoload/ the Sfx pool (the only autoload)
data/          tunable resources (.tres)
gameplay/      player, movement, weapons, enemies, combat config
presentation/  camera, ui, fx
world/         scenes / chambers
tests/         headless smoke test
docs/          design docs
```

## Validating

```
godot --headless --path . --editor --quit-after 400          # import
godot --headless --path . --quit-after 300                   # THE BOX loads
godot --headless --path . res://tests/movement_smoke_test.tscn
```

## Docs

- `docs/GAME_VISION.md`
- `docs/MOVEMENT.md`
