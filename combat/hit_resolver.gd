class_name HitResolver
## Finds which hitboxes touched which fighters this frame and applies the hits.
##
## Runs once per frame after every fighter has moved. All hits are detected
## before any is applied, so two attacks that connect on the same frame trade.


## Detects and applies this frame's hits between [param fighters].
## [param damage_multiplier] is the match's damage ratio (1.2 in 1-on-1).
static func resolve(fighters: Array[Fighter], damage_multiplier: float) -> void:
	var hits: Array[Dictionary] = []
	for attacker in fighters:
		var attack := attacker.current_attack()
		if not attack:
			continue
		var hitboxes := attacker.get_active_hitboxes()
		if hitboxes.is_empty():
			continue
		for victim in fighters:
			if victim == attacker or attack.has_hit(victim) or not victim.can_be_hit():
				continue
			var hit := _first_contact(hitboxes, victim)
			if not hit.is_empty():
				hit["attacker"] = attacker
				hit["attack"] = attack
				hit["victim"] = victim
				hits.append(hit)

	for hit in hits:
		_apply(hit["attacker"], hit["attack"], hit["victim"], hit["hitbox"], hit["shield"], damage_multiplier)


## The highest-priority hitbox touching [param victim]'s shield or hurtbox.
static func _first_contact(hitboxes: Array[ActiveHitbox], victim: Fighter) -> Dictionary:
	var hurt := victim.get_hurt_segment()
	var hurt_radius := victim.get_hurt_radius()
	var shield := victim.get_shield_circle()
	for hitbox in hitboxes:
		var reach := hitbox.data.radius
		if shield.z > 0.0 and _segment_point_distance(hitbox.from, hitbox.to, Vector2(shield.x, shield.y)) <= reach + shield.z:
			return {"hitbox": hitbox.data, "shield": true}
		if _segment_distance(hitbox.from, hitbox.to, hurt[0], hurt[1]) <= reach + hurt_radius:
			return {"hitbox": hitbox.data, "shield": false}
	return {}


# The attack is captured at detection time: in a trade, the attacker may already
# be in hitstun from the other hit when this one is applied.
static func _apply(attacker: Fighter, attack: AttackState, victim: Fighter, hitbox: HitboxData,
		on_shield: bool, damage_multiplier: float) -> void:
	attack.mark_hit(victim)
	var move_id := attack.slot
	var stale := attacker.stale_queue.multiplier(move_id)
	var base_damage := hitbox.damage * attack.charge_multiplier()

	var info := HitInfo.new()
	info.attacker_name = attacker.data.display_name
	info.move_name = attack.move.display_name
	info.stale_multiplier = stale
	info.damage = base_damage * stale * damage_multiplier

	if on_shield:
		info.shielded = true
		info.hitlag = SmashFormulas.hitlag_frames(base_damage * stale, hitbox.hitlag_multiplier, false, true)
		attacker.stale_queue.push(move_id, true)
		attacker.enter_hitlag(info.hitlag)
		victim.receive_shield_hit(info, hitbox, base_damage * stale, attacker)
		return

	var crouching := victim.is_crouching()
	var knockback_damage := base_damage * (1.0 + (stale - 1.0) * SmashFormulas.STALENESS_KNOCKBACK_SHARE)
	var percent_after := victim.percent + info.damage
	var knockback := SmashFormulas.knockback(percent_after, knockback_damage, victim.stats.weight,
			hitbox.knockback_growth, hitbox.base_knockback, hitbox.set_knockback,
			SmashFormulas.rage(attacker.percent))
	if crouching:
		knockback *= SmashFormulas.CROUCH_CANCEL_KNOCKBACK

	var angle := float(hitbox.angle)
	if hitbox.angle == SmashFormulas.SAKURAI_ANGLE:
		angle = SmashFormulas.sakurai_angle(knockback, victim.grounded)
	var direction := attacker.facing * (-1 if hitbox.reverse else 1)
	if direction < 0:
		angle = 180.0 - angle

	info.knockback = knockback
	info.angle = fposmod(angle, 360.0)
	info.hitstun = SmashFormulas.hitstun_frames(knockback)
	info.tumble = SmashFormulas.is_tumble(knockback)
	info.crouch_cancelled = crouching
	info.hitlag = SmashFormulas.hitlag_frames(base_damage * stale, hitbox.hitlag_multiplier, crouching)

	attacker.stale_queue.push(move_id)
	attacker.enter_hitlag(info.hitlag)
	victim.receive_hit(info, hitbox, attacker)


static func _segment_point_distance(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared == 0.0:
		return a.distance_to(p)
	var t := clampf((p - a).dot(ab) / length_squared, 0.0, 1.0)
	return (a + ab * t).distance_to(p)


static func _segment_distance(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> float:
	if _segments_intersect(a1, a2, b1, b2):
		return 0.0
	return minf(
			minf(_segment_point_distance(a1, a2, b1), _segment_point_distance(a1, a2, b2)),
			minf(_segment_point_distance(b1, b2, a1), _segment_point_distance(b1, b2, a2)))


static func _segments_intersect(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> bool:
	var d1 := (a2 - a1).cross(b1 - a1)
	var d2 := (a2 - a1).cross(b2 - a1)
	var d3 := (b2 - b1).cross(a1 - b1)
	var d4 := (b2 - b1).cross(a2 - b1)
	return d1 * d2 < 0.0 and d3 * d4 < 0.0
