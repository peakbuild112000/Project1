extends Area3D
class_name ClimbItemPickup

## Consumable pickup. Jetpacks refill the single equipment slot; bandages are
## counted in the climber's inventory. Touch asks the host to reserve the item;
## the host confirms with rpc_item_taken on every peer.

signal touched(item_id: String, body: Node)

enum Kind { JETPACK, BANDAGE }

@export var item_id: String = ""
@export var item_kind: int = Kind.JETPACK
@export var fuel_amount: float = 65.0
@export var spin_speed: float = 1.2

var taken: bool = false
var _model: Node3D = null


func _ready() -> void:
	add_to_group("climb_items")
	monitoring = true
	monitorable = true
	collision_layer = 4
	collision_mask = 2
	_model = get_node_or_null("Model") as Node3D
	body_entered.connect(_on_body_entered)


func setup(id: String, fuel: float, kind: int = Kind.JETPACK) -> void:
	item_id = id
	item_kind = kind
	fuel_amount = float(fuel)


func _on_body_entered(body: Node) -> void:
	if taken or not is_instance_valid(body):
		return
	if not bool(body.get("is_local")):
		return
	if item_kind == Kind.BANDAGE:
		if not body.has_method("add_bandage"):
			return
	else:
		if not body.has_method("equip_jetpack"):
			return
	touched.emit(item_id, body)


func set_taken(value: bool) -> void:
	taken = value
	monitoring = not value
	visible = not value


func _process(delta: float) -> void:
	if taken or _model == null:
		return
	_model.rotation.y += delta * spin_speed
	_model.position.y = 0.16 + sin(float(Time.get_ticks_msec()) * 0.002) * 0.07
