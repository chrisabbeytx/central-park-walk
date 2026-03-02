extends CharacterBody3D

# Comfortable stroll: ~5 km/h ≈ 1.4 m/s feels slow in 3D, so 4.5 m/s is a brisk-but-pleasant walk.
const WALK_SPEED    := 4.5   # m/s
const LOOK_SPEED    := 100.0  # degrees/second at full stick deflection
const DEADZONE      := 0.15   # ignore stick values below this

var head: Node3D    # pitch pivot at eye height


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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
	_handle_movement(delta)


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
		move_and_slide()
