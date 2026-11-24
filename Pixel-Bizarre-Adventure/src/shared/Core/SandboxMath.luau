--!strict

local Combat = require("../Contracts/CombatTypes")

export type DamageInput = {
	raw: number,
	sourceBonus: number?,
	timing: number?,
	onFire: boolean?,
	stageMatch: boolean?,
	critical: boolean?,
	defense: number,
	mitigationPp: number?,
	penetrationPp: number?,
	exposurePp: number?,
	guarding: boolean?,
	shatter: boolean?,
	armor: number,
	act: number,
}

local Math = {}

function Math.playerHp(level: number, health: number): number
	return 42 + 3 * level + health
end

function Math.basicRaw(level: number, stat: number): number
	return 12 + 0.55 * level + 0.34 * stat
end

function Math.scalingStat(tag: Combat.ScalingTag, physical: number, special: number): number
	if tag == "Physical" then return physical end
	if tag == "Special" then return special end
	local higher = math.max(physical, special)
	if tag == "Hybrid" then return 0.75 * higher + 0.25 * math.min(physical, special) end
	return higher
end

function Math.focusPrecision(focus: number): number
	return math.clamp(math.floor(focus / 15), 0, 10)
end

function Math.focusResist(focus: number): number
	return math.clamp(math.floor(focus / 10), 0, 15)
end

function Math.statusChance(basePercent: number, resistPp: number): number
	return math.clamp(basePercent, 0, 100) * (1 - math.clamp(resistPp, 0, 100) / 100)
end

function Math.dodgePercent(dodge: number, precision: number): number
	return math.max(0, math.clamp(dodge, 0, 50) - precision)
end

function Math.hitPercent(dodge: number, precision: number, dodgeOnly: boolean): number
	if dodgeOnly then
		return 100 - Math.dodgePercent(dodge, precision)
	end
	return math.clamp(95 + precision - math.clamp(dodge, 0, 50), 15, 100)
end

function Math.flagFleePercent(speed: number, enemySpeed: number): number
	return math.clamp(75 + speed - enemySpeed, 25, 95)
end

function Math.effectiveSpeed(speed: number, onFire: boolean): number
	return speed * (if onFire then 1.10 else 1)
end

function Math.turnComesFirst(
	a: Combat.TurnOrderEntry, b: Combat.TurnOrderEntry, round: number, rosterOrder: { [string]: number }
): boolean
	if a.speed ~= b.speed then
		return a.speed > b.speed
	end
	if round % 2 == 1 then
		return rosterOrder[a.actorId] < rosterOrder[b.actorId]
	end
	return rosterOrder[b.actorId] < rosterOrder[a.actorId]
end

function Math.damage(hit: DamageInput): number
	local raw = hit.raw * (1 + math.min(0.35, hit.sourceBonus or 0)) * (hit.timing or 1)
	if hit.onFire then raw *= 1.15 end
	if hit.stageMatch then raw *= 1.15 end
	if hit.critical then raw *= 1.50 end

	local defensePp = math.clamp(hit.defense * 0.2, 0, 51)
	local cappedMitigation = math.min(75, defensePp + (hit.mitigationPp or 0))
	local mitigation = math.max(0, cappedMitigation - (hit.penetrationPp or 0) - (hit.exposurePp or 0))
	local afterMitigation = raw * (1 - mitigation / 100)
	local guarding = hit.guarding and not hit.shatter
	local afterGuard = afterMitigation * (if guarding then 0.65 else 1)
	local flat = math.min(0.20 * afterGuard, hit.armor + (if guarding then hit.act else 0))
	return math.floor(math.max(1, afterGuard - flat))
end

return table.freeze(Math)
