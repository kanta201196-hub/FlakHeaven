extends Node
## Gameplay event bus (autoload `Events`, ADR-02, CS-03).
## Emitters report what happened and do not know who listens; listeners connect in `_ready` or
## `Main.start_run`. Holds no state. Service calls (sound, projectiles, fx) stay direct — only
## gameplay events go through here. Activity kinds are ids: `&"ground"`, `&"convoy"`,
## `&"dogfight"`, `&"transport"`, `&"rescue"`, `&"class_task"` (see `Rewards.ACTIVITY`).

## An enemy took `dmg` damage (after armor).
@warning_ignore("unused_signal")
signal enemy_hit(enemy: Enemy, dmg: float)
## A player ordnance explosion (rocket, bomb, thermobaric, chain reaction) of radius `r` went off at `pos`
## (logic plane); `r_base` is its radius before the player's radius upgrades. Ground structures that can break
## (the «Укрепрайон» fort, FA-03) listen. Blasts with r_base below FortBalance.BLAST_MIN_R are not sent.
@warning_ignore("unused_signal")
signal player_blast(pos: Vector2, r: float, r_base: float)
## A piece of the fort at `key` (FortView.key_of) changed state; its FortView swaps the meshes.
@warning_ignore("unused_signal")
signal fort_changed(key: Vector2i)
## An enemy or convoy vehicle was destroyed by the player's side.
@warning_ignore("unused_signal")
signal enemy_killed(enemy: Enemy)
## The player's plane lost `amount` hull.
@warning_ignore("unused_signal")
signal player_damaged(amount: float)
## The player's plane was destroyed.
@warning_ignore("unused_signal")
signal player_died()
## A bullet or missile passed close to the player without hitting; `kind` is the projectile type.
@warning_ignore("unused_signal")
signal near_miss(kind: StringName)
## A sortie activity was completed; `RunState` pays the reward, other listeners only react.
@warning_ignore("unused_signal")
signal activity_succeeded(kind: StringName)
## A sortie activity was lost; `who` names the escaped ace, if any.
@warning_ignore("unused_signal")
signal activity_failed(kind: StringName, who: String)
## Boss wave `wave` started with `count` bosses.
@warning_ignore("unused_signal")
signal boss_wave(wave: int, count: int)
## The player flew through the last evacuation gate.
@warning_ignore("unused_signal")
signal evac_reached()
## The evacuation window closed without the player.
@warning_ignore("unused_signal")
signal evac_closed()
## A boss destroyed the evacuation point; `who` is its name for the banner.
@warning_ignore("unused_signal")
signal evac_point_lost(who: String)
## Show a banner at the top of the screen for `duration` real seconds.
@warning_ignore("unused_signal")
signal banner(text: String, duration: float)
## Radio message from `from`; `enemy` marks intercepted enemy chatter (red frame).
@warning_ignore("unused_signal")
signal radio(from: String, text: String, enemy: bool)
