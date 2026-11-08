extends CharacterBody3D

@export var max_speed := 9.0
@export var accel := 60.0
@export var air_accel := 20.0
@export var friction := 50.0
@export var jump_velocity := 7.5
@export var gravity := 22.0
@export var mouse_sens := 0.003

@onready var head: Node3D = $Head

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sens)          # yaw: whole body
		head.rotate_x(-event.relative.y * mouse_sens)     # pitch: head only
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	# Gravity and jump
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	# Input -> world-space wish direction
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# Accelerate horizontal velocity toward the target, keep vertical separate
	var horizontal := Vector3(velocity.x, 0, velocity.z)
	var a := accel if is_on_floor() else air_accel
	if wish_dir != Vector3.ZERO:
		horizontal = horizontal.move_toward(wish_dir * max_speed, a * delta)
	elif is_on_floor():
		horizontal = horizontal.move_toward(Vector3.ZERO, friction * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()
