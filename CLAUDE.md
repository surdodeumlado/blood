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

**BLOOD SPLATTER SIGNATURE PASS — PHASE 2: MASS, MATERIALITY, VISUAL PROOF.**

Prove **movement feel + combat feel** in one sandbox arena. Nothing else is in
scope: no roguelike, no procedural generation, no content.

> **Bunnyhop, air-strafe and slide passed playtest and are FROZEN.** They are
> now the project's reference game feel. Do not refactor the bhop logic, the
> W / A / D relationship, the air-strafe model or slide momentum conservation,
> and do not chase Counter-Strike or Quake any harder. `docs/MOVEMENT.md` has
> the detail; the smoke test pins the numbers so drift fails a check.

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
not change who takes damage or how much, and presentation may lag the gameplay
clock but may never extend it.

Blood rules: combat describes WHAT happened (a `BloodContext`); the victim's
`BloodReservoir` decides HOW MUCH material left the body (a `BloodRelease`);
blood presentation decides HOW it looks. Weapon code never spawns a particle,
never picks a count, and there is never an `if weapon == ...` in the blood
system. A new weapon is a damage type plus an energy number, not code.

Blood is a CORE TECHNOLOGICAL AND VISUAL PILLAR. THE ARENA SHOULD REMEMBER THE
FIGHT. Each impact family has its own pattern strategy generating structurally
different geometry (track / fan / shell / multi-origin), never one shared
emitter with different numbers. Quality tiers scale REPRESENTATION only and may
never change released mass or reservoir state.

Impact rules: **no hit stop, and nothing may touch `Engine.time_scale`.** In a
movement game, impact must never take control away from the player. Hit feel is
local only — hitmarker, sound, FOV pulse, weapon shove, enemy reaction.

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
  `gameplay/combat/combat_config.gd`). Blood numbers live in `data/blood/`
  (schemas: `presentation/gore/blood_profile.gd` and `blood_settings.gd`). No
  magic numbers anywhere else.
- Anything temporary must clean itself up: tracers, impacts, audio players and
  death fragments are pooled or self-freeing, and `tests/movement_smoke_test.gd`
  asserts it.

## Layout

```
core/autoload/ the Sfx pool (the only autoload)
data/          tunable resources (.tres)
gameplay/      player, movement, weapons, enemies, combat config
presentation/  camera, ui, fx, gore (blood system + pattern strategies)
world/         scenes / chambers (the_box, blood_lab)
tests/         headless smoke test, blood suite, blood stress test
docs/          design docs
```

## Validating

```
godot --headless --path . --editor --quit-after 400          # import
godot --headless --path . --quit-after 300                   # THE BOX loads
godot --headless --path . res://tests/movement_smoke_test.tscn
godot --headless --path . res://tests/blood_phase2_test.tscn   # blood system
godot --headless --path . res://tests/blood_phase21_test.tscn  # surface payoff
godot --headless --path . res://tests/blood_stress_test.tscn   # blood budget
godot --headless --path . res://world/chambers/blood_lab/blood_lab.tscn
```

## Docs

- `docs/GAME_VISION.md`
- `docs/MOVEMENT.md`
- `docs/COMBAT.md`
- `docs/BLOOD.md`
- `docs/GORE.md`
