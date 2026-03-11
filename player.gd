extends CharacterBody3D

# Comfortable stroll: ~8 km/h ≈ 2.25 m/s — leisurely park pace.
const LOOK_SPEED    := 100.0  # degrees/second at full stick deflection
const DEADZONE      := 0.15   # ignore stick values below this
const STEP_HEIGHT   := 0.25  # max step-up height (> 0.17m stair rise)
const SPEED_STEPS: Array = [0.35, 1.2, 3.0, 10.0, 30.0, 100.0]
const SPEED_NAMES: Array = ["Stroll", "Walk", "Jog", "Bike", "Drive", "Fly"]

var walk_speed: float = 1.2
var _speed_idx: int = 1
var head: Node3D    # pitch pivot at eye height
var _stair_offset: float = 0.0  # camera smoothing for stair steps
var boundary_polygon: PackedVector2Array  # XZ park boundary (set by main.gd)
var tour_freeze := false  # when true, physics runs but player doesn't move/look
var terrain_height_fn: Callable  # set by main.gd → _terrain_height(x, z) -> float


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	floor_snap_length = 0.5  # snap to ground on slopes and stairs
	safe_margin = 0.05       # wider collision margin prevents tunneling on steep terrain

	# Capsule collider
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.25
	cap.height = 1.30
	col.shape   = cap
	col.position = Vector3(0.0, 0.65, 0.0)
	add_child(col)

	# Head node – only rotates on X (pitch)
	head = Node3D.new()
	head.name     = "Head"
	head.position = Vector3(0.0, 1.24, 0.0)
	add_child(head)

	# Camera attached to head
	var cam := Camera3D.new()
	cam.name    = "Camera"
	cam.current = true
	cam.fov     = 82.0
	var cam_attr := CameraAttributesPractical.new()
	cam_attr.dof_blur_far_enabled    = false
	cam_attr.dof_blur_near_enabled   = false
	cam.attributes = cam_attr
	head.add_child(cam)


func _physics_process(delta: float) -> void:
	if tour_freeze:
		velocity = Vector3.ZERO
		move_and_slide()  # keep physics body synced with scene transform
		return
	_handle_look(delta)
	var pre_pos := position
	var pre_y := position.y
	_handle_movement(delta)
	# Smooth camera on stair step teleports
	var dy := position.y - pre_y
	if absf(dy) > 0.08:  # sudden jump = stair step, not normal movement
		_stair_offset += dy
	_stair_offset = lerpf(_stair_offset, 0.0, clampf(10.0 * delta, 0.0, 1.0))
	head.position.y = 1.58 - _stair_offset


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		rotation_degrees.y      -= event.relative.x * 0.15
		head.rotation_degrees.x -= event.relative.y * 0.15
		head.rotation_degrees.x  = clampf(head.rotation_degrees.x, -80.0, 80.0)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_speed(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_speed(-1)
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
			_change_speed(1)
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			_change_speed(-1)


func _change_speed(dir: int) -> void:
	var old_idx := _speed_idx
	_speed_idx = clampi(_speed_idx + dir, 0, SPEED_STEPS.size() - 1)
	walk_speed = SPEED_STEPS[_speed_idx]
	if _speed_idx == old_idx:
		print("Speed: %s (%.1f m/s) [already at %s]" % [SPEED_NAMES[_speed_idx], walk_speed, "min" if dir < 0 else "max"])
	else:
		print("Speed: %s (%.1f m/s)" % [SPEED_NAMES[_speed_idx], walk_speed])


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
		var speed := walk_speed * lerpf(5.0, 20.0, rt)
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
		velocity.x = wish.x * walk_speed
		velocity.z = wish.z * walk_speed

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

	# Safety net: never let the player fall below the terrain surface.
	# Prevents tunneling through HeightMapShape3D on steep slopes at speed.
	if terrain_height_fn.is_valid():
		var floor_y: float = terrain_height_fn.call(position.x, position.z)
		if position.y < floor_y + 0.1:
			position.y = floor_y + 0.1
			velocity.y = maxf(velocity.y, 0.0)


func _point_in_polygon(px: float, pz: float) -> bool:
	## Ray-casting algorithm on the OSM park boundary polygon.
	var inside := false
	var n := boundary_polygon.size()
	var j := n - 1
	for i in range(n):
		var zi := boundary_polygon[i].y
		var zj := boundary_polygon[j].y
		if (zi > pz) != (zj > pz):
			var xi := boundary_polygon[i].x
			var xj := boundary_polygon[j].x
			var x_cross := xi + (pz - zi) / (zj - zi) * (xj - xi)
			if px < x_cross:
				inside = not inside
		j = i
	return inside
