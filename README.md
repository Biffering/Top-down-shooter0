# Squad Surge (Godot 4)

A lane shooter in the "squad runner" style. You move side to side while your squad
auto-fires, enemy waves charge straight at you, you shoot bonus crates to power up,
then you fight a boss. At the end your points are tallied into coins that you spend on
permanent upgrades and skins.

## Running it
1. Install **Godot 4.3 or newer** (the standard build, not .NET): https://godotengine.org/download
2. Open Godot, click **Import**, and select `project.godot` in this folder.
3. Press **F5** (or the ▶ Play button).

You don't need any art assets. Everything is drawn in code.

## Controls
- **Drag** with the mouse or your finger, or use **Left/Right** or **A/D**, to move.
- Your squad shoots on its own.
- **Esc** or **P** pauses the game.

## How a run works
- **Enemies**: grunts (red), runners (orange, fast) and brutes (purple, tanky, kill 3 soldiers).
  Every enemy that reaches your squad kills soldiers. If you run out of soldiers, the run ends.
- **Bonus crates**: the number on a crate is how much damage it needs to break. Break it to
  get the bonus. Crates also block bullets, so choose your targets carefully.
  - RAPID: +25% fire rate
  - +2 SQUAD: two more soldiers (more bullets, and past 10 soldiers each extra one adds damage)
  - POWER: +35% damage
  - SPREAD: two more angled shots
  - PIERCE: bullets pass through one more enemy
  - SHIELD: blocks one hit
- **Super orb**: once in a while a kill drops a glowing rainbow star (brutes drop it more often).
  It wanders around the track as it drifts down. Steer into it to trigger **SUPER SURGE**: everything goes
  into slow motion, the screen flashes white, and shockwaves roll out from your squad and blow up every enemy
  on screen in a chain of explosions. The boss loses 30% of its health. After that you get 4 seconds of rainbow spiral
  bullets that deal triple damage, pierce enemies and explode on every hit. You can tune it in `game.gd`
  with `SUPER_DURATION`, `ORB_DROP_CHANCE` and `ORB_COOLDOWN`.
- **Boss**: shows up after 50 seconds. It sends out minions and slowly moves toward you.
  If it reaches your squad, you lose.
- **Tally**: distance, kills, bonuses, survivors and the boss kill add up to your points.
  Points ÷ 10 = coins. You get coins even if you lose. If you win, you move on to the next level,
  and enemies there are tougher.

## Permanent upgrades (main menu → Upgrades)
Firepower, Trigger Speed, Reinforcements, Shield and Bounty (more coins). Each level costs 1.6× more than the last.
Skins: Classic, Crimson, Toxic, Royal, Gold, Shadow.

Progress is saved to `user://squad_surge_save.json`. You can wipe it with "Reset progress" on the menu.

## Sound effects
There are 20 retro sound effects in `sounds/`: shooting, bullet hits, enemy and brute deaths, crate hits,
power-ups, losing soldiers, shield blocks, the boss alarm/hits/explosion, victory and defeat jingles, the
level start, the points tally (ticks that rise in pitch, a ding per row, a cha-ching for the total), coins,
new best score and button clicks. The main menu has a **SOUND: ON/OFF** toggle, and the setting is saved.

- **To swap a sound**, replace the `.wav` with one of your own that has the same name.
- **To adjust volumes**, edit `VOLUME` at the top of `scripts/sfx.gd`. It's in decibels: -6 is about half as loud.
- **To play a sound from your own code**, call `Sfx.play("powerup")`.

## Music
There are five looping tracks in `music/`, all composed and rendered by code:
- **menu**: chill synthwave, used for the menus and the results screen
- **rock**: retro rock with distorted power chords and a chiptune lead (levels 1, 4, 7...)
- **techno**: four-on-the-floor with acid bass (levels 2, 5, 8...)
- **chiptune**: NES-style action track (levels 3, 6, 9...)
- **boss**: heavy, fast, double-kick metal that plays when the boss shows up

The music crossfades between tracks, gets quieter while the game is paused, and stops for the
victory/defeat jingle. Use **MUSIC: ON/OFF** on the main menu to turn it off. To use your own songs,
drop in `.ogg` files with the same names. To change which track plays on which level, edit
`LEVEL_TRACKS` in `scripts/music.gd`. Volumes are in `VOLUME` in the same file.

## Files
- `scripts/game.gd`: gameplay, spawning, collisions and all drawing. Tuning constants are at the top
  (`LEVEL_TIME`, `ENEMY_TYPES`, `BONUS_INFO`, `BONUS_WEIGHTS`, boss HP in `_spawn_boss`).
- `scripts/main.gd`: menus, HUD, results tally and the shop UI (all built in code).
- `scripts/save.gd`: autoload with save data, upgrade definitions and costs, and skins.
- `scripts/sfx.gd`: autoload that plays the sound effects (volume, pitch variation and spam limiting).
- `scripts/music.gd`: autoload that plays the music (crossfades, looping, pause ducking).
- `sounds/`: the .wav sound effects.
- `music/`: the .ogg music tracks.

## Exporting to a phone
The project is already set to portrait 480×854 with the Compatibility renderer, so it runs on mobile.
Go to Project → Export, add Android or iOS, and install the export templates when Godot asks.
