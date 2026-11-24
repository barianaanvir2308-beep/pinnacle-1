# resource_manager.gd — Energy economy manager
# Autoloaded as "ResourceManager"
extends Node

var current_energy: int = 0
var max_energy: int = 0
var lost_to_cap: int = 0               # income thrown away because the Energy Capacity was full
var passive_enabled: bool = false      # main.gd turns this on only during waves and the countdowns before them
var _fraction: float = 0.0             # leftover part of an Energy (passive income and Decoders pay in fractions)

func _ready() -> void:
	current_energy = Globals.STARTING_ENERGY
	max_energy = Globals.MAX_ENERGY
	
	# Emit initial energy state
	Events.energy_changed.emit(current_energy)

# Passive generation. This node pauses with the game, so nothing is earned while paused.
func _process(delta: float) -> void:
	if passive_enabled:
		add_energy_float(Globals.PASSIVE_ENERGY_RATE * delta)

# =============================================================================
# ENERGY OPERATIONS
# =============================================================================

func can_afford(cost: int) -> bool:
	return current_energy >= cost

func spend_energy(cost: int) -> bool:
	if can_afford(cost):
		current_energy -= cost
		Events.energy_changed.emit(current_energy)
		return true
	else:
		Events.energy_insufficient.emit(cost, current_energy)
		return false

# Income is capped at the Energy Capacity; whatever doesn't fit is lost (and counted)
func add_energy(amount: int) -> void:
	var wanted := current_energy + amount
	if wanted > max_energy:
		lost_to_cap += wanted - max_energy
	current_energy = mini(wanted, max_energy)
	Events.energy_changed.emit(current_energy)

# Income that arrives in fractions: only whole Energy is added, the rest is carried over
func add_energy_float(amount: float) -> void:
	_fraction += amount
	var whole := int(_fraction)
	if whole > 0:
		_fraction -= whole
		add_energy(whole)

func get_sell_refund(original_cost: int) -> int:
	return int(original_cost * Globals.SELL_REFUND_PERCENTAGE)

# =============================================================================
# RESET
# =============================================================================

func reset() -> void:
	current_energy = Globals.STARTING_ENERGY
	lost_to_cap = 0
	_fraction = 0.0
	passive_enabled = false
	Events.energy_changed.emit(current_energy)
