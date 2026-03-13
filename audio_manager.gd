## Ambient audio manager — wind, city hum, water proximity, footsteps, rain.
## All sounds are looping WAV files positioned/mixed dynamically based on
## player position, weather, time of day, wind strength, and atlas surface type.

var _loader  # park_loader reference for atlas, terrain, water data

# Audio players — global ambient layers
var _wind_player: AudioStreamPlayer
var _city_player: AudioStreamPlayer
var _rain_player: AudioStreamPlayer

# Positional water sound — moves to nearest water body
var _water_player: AudioStreamPlayer3D

# Footstep system
var _step_grass: AudioStreamWAV
var _step_stone: AudioStreamWAV
var _step_player: AudioStreamPlayer
var _step_timer: float = 0.0
var _step_interval: float = 0.5  # seconds between footsteps at walk speed
var _last_surface: int = 0

# State
var _player_node: CharacterBody3D
var _water_centroids: Array = []  # [Vector3] — precomputed water body centers
var _boundary_polygon: PackedVector2Array  # park boundary for edge distance


func _init(loader) -> void:
	_loader = loader


func setup(player: CharacterBody3D, water_bodies: Array, boundary: PackedVector2Array) -> void:
	_player_node = player
	_boundary_polygon = boundary

	# Precompute water body centroids for proximity checks
	for body in water_bodies:
		var pts: Array = body.get("points", [])
		if pts.size() < 3:
			continue
		var cx := 0.0
		var cz := 0.0
		for p in pts:
			cx += float(p[0])
			cz += float(p[1])
		cx /= float(pts.size())
		cz /= float(pts.size())
		var ty: float = _loader._terrain_y(cx, cz)
		_water_centroids.append(Vector3(cx, ty, cz))

	# --- Wind ---
	_wind_player = AudioStreamPlayer.new()
	_wind_player.bus = "Master"
	_wind_player.volume_db = -20.0
	var wind_stream := _load_wav("res://sounds/wind_trees.wav")
	if wind_stream:
		wind_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wind_stream.loop_end = wind_stream.data.size() / (wind_stream.format + 1) / (1 if not wind_stream.stereo else 2)
		_wind_player.stream = wind_stream
	_loader.add_child(_wind_player)
	if _wind_player.stream:
		_wind_player.play()

	# --- City ambient ---
	_city_player = AudioStreamPlayer.new()
	_city_player.bus = "Master"
	_city_player.volume_db = -24.0
	var city_stream := _load_wav("res://sounds/city_distant.wav")
	if city_stream:
		city_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		city_stream.loop_end = city_stream.data.size() / (city_stream.format + 1) / (1 if not city_stream.stereo else 2)
		_city_player.stream = city_stream
	_loader.add_child(_city_player)
	if _city_player.stream:
		_city_player.play()

	# --- Rain (reuses water_fountain.wav — splashing water ≈ rain hitting surfaces) ---
	_rain_player = AudioStreamPlayer.new()
	_rain_player.bus = "Master"
	_rain_player.volume_db = -40.0  # starts silent, ramps with wetness
	var rain_stream := _load_wav("res://sounds/water_fountain.wav")
	if rain_stream:
		rain_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		rain_stream.loop_end = rain_stream.data.size() / (rain_stream.format + 1) / (1 if not rain_stream.stereo else 2)
		_rain_player.stream = rain_stream
	_loader.add_child(_rain_player)

	# --- Water proximity (3D positional) ---
	_water_player = AudioStreamPlayer3D.new()
	_water_player.bus = "Master"
	_water_player.volume_db = -12.0
	_water_player.max_distance = 80.0
	_water_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	var water_stream := _load_wav("res://sounds/water_lake.wav")
	if water_stream:
		water_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		water_stream.loop_end = water_stream.data.size() / (water_stream.format + 1) / (1 if not water_stream.stereo else 2)
		_water_player.stream = water_stream
	_loader.add_child(_water_player)
	if _water_player.stream:
		_water_player.play()

	# --- Footsteps ---
	_step_grass = _load_wav("res://sounds/footstep_grass.wav")
	_step_stone = _load_wav("res://sounds/footstep_stone.wav")
	_step_player = AudioStreamPlayer.new()
	_step_player.bus = "Master"
	_step_player.volume_db = -8.0
	_loader.add_child(_step_player)


func update(delta: float, wind_strength: float, weather: String,
		rain_wetness: float, time_of_day: float) -> void:
	if not _player_node:
		return
	var pos := _player_node.global_position
	var speed := _player_node.velocity.length()

	# --- Wind volume: base + wind strength + altitude boost ---
	if _wind_player and _wind_player.stream:
		var alt_factor := clampf((pos.y - 30.0) / 100.0, 0.0, 0.5)  # louder at height
		var wind_vol := clampf(wind_strength * 1.5 + 0.15 + alt_factor, 0.0, 1.0)
		_wind_player.volume_db = lerpf(-40.0, -6.0, wind_vol)
		# Pitch shifts slightly with wind strength for variety
		_wind_player.pitch_scale = lerpf(0.9, 1.15, clampf(wind_strength, 0.0, 1.0))

	# --- City hum: louder near edges, at height, and at night ---
	if _city_player and _city_player.stream:
		var edge_dist := _distance_to_boundary(pos.x, pos.z)
		var edge_factor := clampf(1.0 - edge_dist / 400.0, 0.0, 1.0)  # max at edge
		var alt_city := clampf((pos.y - 20.0) / 80.0, 0.0, 0.6)
		# Night: city is louder (less park noise, more traffic)
		var night_boost := 0.0
		if time_of_day < 5.0 or time_of_day > 22.0:
			night_boost = 0.15
		elif time_of_day > 20.0:
			night_boost = lerpf(0.0, 0.15, (time_of_day - 20.0) / 2.0)
		elif time_of_day < 7.0:
			night_boost = lerpf(0.15, 0.0, (time_of_day - 5.0) / 2.0)
		var city_vol := clampf(edge_factor * 0.6 + alt_city + night_boost + 0.08, 0.0, 1.0)
		_city_player.volume_db = lerpf(-40.0, -10.0, city_vol)

	# --- Rain sound ---
	if _rain_player:
		if weather == "rain" or weather == "thunderstorm":
			if not _rain_player.playing and _rain_player.stream:
				_rain_player.play()
			var rain_vol := clampf(rain_wetness, 0.0, 1.0)
			_rain_player.volume_db = lerpf(-40.0, -8.0, rain_vol)
		else:
			if _rain_player.playing and rain_wetness < 0.01:
				_rain_player.stop()
			elif _rain_player.playing:
				_rain_player.volume_db = lerpf(-40.0, -8.0, rain_wetness)

	# --- Water proximity: snap to nearest water body ---
	if _water_player and _water_player.stream and not _water_centroids.is_empty():
		var best_dist := 999999.0
		var best_pos := Vector3.ZERO
		for wc: Vector3 in _water_centroids:
			var d := pos.distance_squared_to(wc)
			if d < best_dist:
				best_dist = d
				best_pos = wc
		_water_player.global_position = best_pos
		# Fountain sound boost when very close
		var dist := sqrtf(best_dist)
		if dist < 15.0:
			_water_player.volume_db = -6.0
		elif dist < 40.0:
			_water_player.volume_db = -12.0
		else:
			_water_player.volume_db = -18.0

	# --- Footsteps ---
	_update_footsteps(delta, pos, speed)


func _update_footsteps(delta: float, pos: Vector3, speed: float) -> void:
	if not _step_player or speed < 0.3:
		_step_timer = 0.0
		return

	# Interval scales with speed: walk=0.5s, jog=0.35s, run=0.25s
	_step_interval = clampf(0.7 / maxf(speed, 0.5), 0.2, 0.6)
	_step_timer += delta
	if _step_timer < _step_interval:
		return
	_step_timer = 0.0

	# Choose sound based on surface type
	var surface := _loader._atlas_surface(pos.x, pos.z)
	var stream: AudioStreamWAV = null
	match surface:
		1:  # grass
			stream = _step_grass
		2, 6:  # paved, bridge
			stream = _step_stone
		3:  # unpaved (gravel)
			stream = _step_grass  # gravel ≈ grass crunch
		_:
			stream = _step_stone  # default to stone

	if stream:
		_step_player.stream = stream
		# Slight pitch randomization for natural feel
		_step_player.pitch_scale = randf_range(0.85, 1.15)
		# Volume scales with speed — slower = quieter steps
		var vol_factor := clampf(speed / 3.0, 0.3, 1.0)
		_step_player.volume_db = lerpf(-18.0, -6.0, vol_factor)
		_step_player.play()


func _distance_to_boundary(px: float, pz: float) -> float:
	## Returns approximate distance from (px, pz) to the nearest park boundary edge.
	if _boundary_polygon.is_empty():
		return 200.0
	var min_d := 999999.0
	var p := Vector2(px, pz)
	var n := _boundary_polygon.size()
	# Sample every 4th segment for performance (boundary has ~215 points)
	for i in range(0, n, 4):
		var a := _boundary_polygon[i]
		var b := _boundary_polygon[(i + 1) % n]
		var ab := b - a
		var len_sq := ab.length_squared()
		if len_sq < 0.01:
			continue
		var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
		var closest := a + ab * t
		var d := p.distance_to(closest)
		if d < min_d:
			min_d = d
	return min_d


func _load_wav(path: String) -> AudioStreamWAV:
	## Load a WAV file as AudioStreamWAV. Returns null on failure.
	var fh := FileAccess.open(path, FileAccess.READ)
	if not fh:
		push_warning("AudioManager: WAV not found: %s" % path)
		return null
	var file_data := fh.get_buffer(fh.get_length())
	fh.close()

	# Parse WAV header
	if file_data.size() < 44:
		return null
	# "RIFF" check
	if file_data[0] != 0x52 or file_data[1] != 0x49 or file_data[2] != 0x46 or file_data[3] != 0x46:
		return null

	var channels: int = file_data[22] | (file_data[23] << 8)
	var sample_rate: int = file_data[24] | (file_data[25] << 8) | (file_data[26] << 16) | (file_data[27] << 24)
	var bits_per_sample: int = file_data[34] | (file_data[35] << 8)

	# Find "data" chunk
	var data_offset := 12
	var data_size := 0
	while data_offset < file_data.size() - 8:
		var chunk_id := ""
		for ci in 4:
			chunk_id += char(file_data[data_offset + ci])
		var chunk_size: int = file_data[data_offset + 4] | (file_data[data_offset + 5] << 8) | (file_data[data_offset + 6] << 16) | (file_data[data_offset + 7] << 24)
		if chunk_id == "data":
			data_offset += 8
			data_size = chunk_size
			break
		data_offset += 8 + chunk_size
		if chunk_size % 2 == 1:
			data_offset += 1  # WAV chunks are word-aligned

	if data_size == 0:
		return null

	var stream := AudioStreamWAV.new()
	stream.mix_rate = sample_rate
	stream.stereo = (channels == 2)
	if bits_per_sample == 16:
		stream.format = AudioStreamWAV.FORMAT_16_BITS
	else:
		stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.data = file_data.slice(data_offset, data_offset + data_size)

	return stream
