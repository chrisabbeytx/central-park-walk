extends CharacterBody3D

# Comfortable stroll: ~8 km/h ≈ 2.25 m/s — leisurely park pace.
const WALK_SPEED    := 2.25  # m/s
const LOOK_SPEED    := 100.0  # degrees/second at full stick deflection
const DEADZONE      := 0.15   # ignore stick values below this
const STEP_HEIGHT   := 0.25  # max step-up height (> 0.17m stair rise)

var head: Node3D    # pitch pivot at eye height
var _stair_offset: float = 0.0  # camera smoothing for stair steps


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	floor_snap_length = 0.3  # snap down stairs (STEP_RISE = 0.17m)

	# Capsule collider
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	col.shape   = cap
	col.position = Vector3(0.0, 0.85, 0.0)
	add_child(col)

	# Head node – only rotates on X (pitch)
	head = Node3D.new()
	head.name     = "Head"
	head.position = Vector3(0.0, 1.65, 0.0)
	add_child(head)

	# Camera attached to head
	var cam := Camera3D.new()
	cam.name    = "Camera"
	cam.current = true
	cam.fov     = 90.0
	head.add_child(cam)


func _physics_process(delta: float) -> void:
	_handle_look(delta)
	var pre_y := position.y
	_handle_movement(delta)
	# Smooth camera on stair step teleports
	var dy := position.y - pre_y
	if absf(dy) > 0.1:  # sudden jump = stair step, not normal movement
		_stair_offset += dy
	_stair_offset = lerpf(_stair_offset, 0.0, clampf(15.0 * delta, 0.0, 1.0))
	head.position.y = 1.65 - _stair_offset


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotation_degrees.y      -= event.relative.x * 0.15
		head.rotation_degrees.x -= event.relative.y * 0.15
		head.rotation_degrees.x  = clampf(head.rotation_degrees.x, -80.0, 80.0)
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_F:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _handle_look(delta: float) -> void:
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)

	if absf(rx) < DEADZONE: rx = 0.0
	if absf(ry) < DEADZONE: ry = 0.0

	rotation_degrees.y -= rx * LOOK_SPEED * delta
	head.rotation_degrees.x -= ry * LOOK_SPEED * delta
	head.rotation_degrees.x = clampf(head.rotation_degrees.x, -80.0, 80.0)


func _handle_movement(delta: float) -> void:
	var lx := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var ly := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)

	if absf(lx) < DEADZONE: lx = 0.0
	if absf(ly) < DEADZONE: ly = 0.0

	# WASD keyboard fallback
	if Input.is_key_pressed(KEY_A): lx -= 1.0
	if Input.is_key_pressed(KEY_D): lx += 1.0
	if Input.is_key_pressed(KEY_W): ly -= 1.0
	if Input.is_key_pressed(KEY_S): ly += 1.0

	var wish := Vector3(lx, 0.0, ly)
	if wish.length_squared() > 1.0:
		wish = wish.normalized()

	# Right trigger: fly mode (5x–20x), bypasses collision
	var rt := clampf(Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT), 0.0, 1.0)
	if rt > 0.1:
		var speed := WALK_SPEED * lerpf(5.0, 20.0, rt)
		# Move in camera look direction (head pitch + body yaw)
		var cam_basis := head.global_transform.basis
		var fly_dir := cam_basis * wish
		position += fly_dir * speed * delta
		velocity = Vector3.ZERO
	else:
		# Normal walk with gravity and collision
		if not is_on_floor():
			velocity.y -= 9.8 * delta
		wish = transform.basis * wish
		wish.y = 0.0
		velocity.x = wish.x * WALK_SPEED
		velocity.z = wish.z * WALK_SPEED

		# Stair stepping: if blocked horizontally on floor, try stepping up
		if is_on_floor() and wish.length_squared() > 0.001:
			var h_vel := Vector3(velocity.x, 0.0, velocity.z)
			if h_vel.length_squared() > 0.001 and test_move(global_transform, h_vel * delta):
				# Blocked. Check we can move up, then forward from raised position.
				var up_motion := Vector3(0.0, STEP_HEIGHT, 0.0)
				if not test_move(global_transform, up_motion):
					var up_xf := global_transform
					up_xf.origin += up_motion
					if not test_move(up_xf, h_vel * delta):
						position.y += STEP_HEIGHT
						# floor_snap_length pulls us back down after move_and_slide

		move_and_slide()
