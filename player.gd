extends CharacterBody3D

signal dash_jumped(quality: float)   # 0.0 = mistimed, 1.0 = perfect

enum State { NORMAL, DASHING }
var state := State.NORMAL

@export_group("Movement")
@export var max_speed := 9.0
@export var accel := 60.0
@export var air_accel := 25.0
@export var friction := 50.0
@export var jump_velocity := 7.5
@export var gravity := 22.0
@export var mouse_sens := 0.002

@export_group("Jump forgiveness")
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.12

@export_group("Dash")
@export var dash_speed := 18.0
@export var dash_duration := 0.3
@export var dash_cooldown := 0.4
@export var max_air_dashes := 1

@export_group("Dash jump")
@export var sweet_center := 0.9        # where in the dash (0..1) the perfect moment is
@export var sweet_half_width := 0.5   # how far either side still gives a bonus
@export var dash_jump_min_speed := 13.0  # mistimed dash jump
@export var dash_jump_max_speed := 26.0  # perfectly timed dash jump
@export var dash_jump_height := 0.85     # fraction of normal jump: a lower, longer arc

@onready var head: Node3D = $Head

var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var dash_cooldown_timer := 0.0
var air_dashes_left := 0

var dash_dir := Vector3.ZERO
var dash_elapsed := 0.0
var dash_in_air := false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	dash_jumped.connect(func(q: float): print("dash jump quality: ", snappedf(q, 0.01)))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sens)
		head.rotate_x(-event.relative.y * mouse_sens)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	_update_timers(delta)

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	# An air dash is a hover: no gravity while it lasts
	var air_dashing := state == State.DASHING and dash_in_air
	if not is_on_floor() and not air_dashing:
		velocity.y -= gravity * delta

	match state:
		State.NORMAL:
			_normal_move(delta, wish_dir)
		State.DASHING:
			_dash_move(delta)

	move_and_slide()

func _update_timers(delta: float) -> void:
	coyote_timer = coyote_time if is_on_floor() else maxf(coyote_timer - delta, 0.0)
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time
	else:
		jump_buffer_timer = maxf(jump_buffer_timer - delta, 0.0)
	dash_cooldown_timer = maxf(dash_cooldown_timer - delta, 0.0)
	if is_on_floor():
		air_dashes_left = max_air_dashes

func _try_jump() -> void:
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = jump_velocity
		jump_buffer_timer = 0.0
		coyote_timer = 0.0

# ---------- Normal movement ----------

func _normal_move(delta: float, wish_dir: Vector3) -> void:
	if Input.is_action_just_pressed("dash") and _can_dash():
		_start_dash(wish_dir)
		return

	_try_jump()

	var horizontal := Vector3(velocity.x, 0, velocity.z)

	if is_on_floor() and velocity.y <= 0.0:
		if wish_dir != Vector3.ZERO:
			horizontal = horizontal.move_toward(wish_dir * max_speed, accel * delta)
		else:
			horizontal = horizontal.move_toward(Vector3.ZERO, friction * delta)
	else:
		# Air control that preserves momentum (see Stage 2 notes on dot product)
		var current := horizontal.dot(wish_dir)
		var add := clampf(max_speed - current, 0.0, air_accel * delta)
		horizontal += wish_dir * add

	velocity.x = horizontal.x
	velocity.z = horizontal.z

# ---------- Dash ----------

func _can_dash() -> bool:
	return dash_cooldown_timer <= 0.0 and (is_on_floor() or air_dashes_left > 0)

func _start_dash(wish_dir: Vector3) -> void:
	state = State.DASHING
	dash_elapsed = 0.0
	dash_in_air = not is_on_floor()
	jump_buffer_timer = 0.0   # a jump pressed before the dash shouldn't instantly dash-jump

	if dash_in_air:
		air_dashes_left -= 1
		velocity.y = 0.0

	# Dash where you're steering; with no input, dash where you're facing (-Z is forward)
	dash_dir = wish_dir if wish_dir != Vector3.ZERO else -transform.basis.z
	velocity.x = dash_dir.x * dash_speed
	velocity.z = dash_dir.z * dash_speed

func _dash_move(delta: float) -> void:
	dash_elapsed += delta
	velocity.x = dash_dir.x * dash_speed
	velocity.z = dash_dir.z * dash_speed
	if dash_in_air:
		velocity.y = 0.0

	# Dash jump: only when grounded (coyote time counts)
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		_dash_jump()
		return

	if dash_elapsed >= dash_duration:
		_end_dash()

func _timing_quality() -> float:
	var t := dash_elapsed / dash_duration                  # normalized 0..1
	var distance := absf(t - sweet_center)                 # how far from the perfect moment
	return clampf(1.0 - distance / sweet_half_width, 0.0, 1.0)

func _dash_jump() -> void:
	var quality := _timing_quality()
	var speed := lerpf(dash_jump_min_speed, dash_jump_max_speed, quality)
	velocity.x = dash_dir.x * speed
	velocity.z = dash_dir.z * speed
	velocity.y = jump_velocity * dash_jump_height
	jump_buffer_timer = 0.0
	coyote_timer = 0.0
	_end_dash()
	dash_jumped.emit(quality)

func _end_dash() -> void:
	state = State.NORMAL
	dash_cooldown_timer = dash_cooldown
