# building_builder.gd
# Building geometry: extruded footprint polygons, 5 facade styles
# Extracted from park_loader.gd — all shared utilities accessed via _loader reference.

var _loader  # Reference to park_loader for shared utilities
const MAX_BUILDING_DIST := 200.0  # metres — skip buildings farther than this from park boundary

func _init(loader) -> void:
	_loader = loader


var _bnd_aabb_min := Vector2.ZERO
var _bnd_aabb_max := Vector2.ZERO
var _bnd_aabb_valid := false

func _ensure_boundary_aabb() -> void:
	if _bnd_aabb_valid:
		return
	var poly: PackedVector2Array = _loader.boundary_polygon
	if poly.is_empty():
		return
	_bnd_aabb_min = poly[0]
	_bnd_aabb_max = poly[0]
	for i in range(1, poly.size()):
		var p: Vector2 = poly[i]
		_bnd_aabb_min.x = minf(_bnd_aabb_min.x, p.x)
		_bnd_aabb_min.y = minf(_bnd_aabb_min.y, p.y)
		_bnd_aabb_max.x = maxf(_bnd_aabb_max.x, p.x)
		_bnd_aabb_max.y = maxf(_bnd_aabb_max.y, p.y)
	_bnd_aabb_valid = true

func _near_boundary(px: float, pz: float) -> bool:
	## Fast check: is this point within MAX_BUILDING_DIST of the park boundary?
	## Uses AABB pre-check, then polygon segment distance for edge cases.
	_ensure_boundary_aabb()
	# Quick AABB reject: if outside expanded AABB, definitely too far
	if px < _bnd_aabb_min.x - MAX_BUILDING_DIST or px > _bnd_aabb_max.x + MAX_BUILDING_DIST:
		return false
	if pz < _bnd_aabb_min.y - MAX_BUILDING_DIST or pz > _bnd_aabb_max.y + MAX_BUILDING_DIST:
		return false
	# Inside AABB with margin: check actual polygon distance
	var poly: PackedVector2Array = _loader.boundary_polygon
	var n: int = poly.size()
	var pt := Vector2(px, pz)
	var thresh_sq := MAX_BUILDING_DIST * MAX_BUILDING_DIST
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var ab := b - a
		var len_sq := ab.length_squared()
		var dsq: float
		if len_sq < 0.001:
			dsq = (pt - a).length_squared()
		else:
			var t := clampf((pt - a).dot(ab) / len_sq, 0.0, 1.0)
			var closest := a + ab * t
			dsq = (pt - closest).length_squared()
		if dsq < thresh_sq:
			return true
	return false


func _building_style(cx: float, cz: float, h: float, year: int) -> int:
	# 0=LIMESTONE, 1=GLASS, 2=RED_BRICK, 3=BUFF_BRICK, 4=DARK_STONE
	# In-park short buildings → dark stone (schist pavilions, etc.)
	if _loader._in_boundary(cx, cz) and h < 15.0:
		return 4
	# Supertalls and modern glass towers
	if h > 80.0:
		return 1
	if h > 50.0 and cz > 1000.0:
		return 1
	if year > 1990 and h > 40.0:
		return 1  # modern tall → glass curtain wall
	# East side: Fifth Avenue limestone co-ops
	if cx > 420.0:
		if year > 0 and year < 1900:
			return 0  # Gilded Age limestone
		if year >= 1960:
			return 1  # postwar glass
		return 0  # default limestone
	# West side: Central Park West Art Deco + buff brick
	if cx < -420.0:
		if year > 0 and year < 1900:
			return 2  # pre-war red brick tenements
		if year >= 1920 and year <= 1945:
			return 3  # Art Deco buff brick (The Majestic, San Remo, etc.)
		if year > 1960:
			return 1  # postwar glass
		return 3  # default buff brick
	# North (Harlem): red brick
	if cz < -1200.0:
		return 2
	# South (59th St): mixed commercial/hotel
	if cz > 1500.0:
		if year > 1980:
			return 1  # modern glass
		return 3  # Art Deco hotels
	# Mixed zone: deterministic hash
	var hv := fmod(abs(cx * 7.3 + cz * 13.1), 10.0)
	if hv < 3.0: return 0
	if hv < 5.5: return 2
	if hv < 7.5: return 3
	if hv < 8.5: return 1
	return 0


func _build_buildings(buildings: Array) -> void:
	if buildings.is_empty():
		return

	# 5 style groups: 0=LIMESTONE, 1=GLASS, 2=RED_BRICK, 3=BUFF_BRICK, 4=DARK_STONE
	var sv: Array = []  # verts per style
	var sn: Array = []  # normals
	var su: Array = []  # uvs
	var sc: Array = []  # vertex colors
	for _i in range(5):
		sv.append(PackedVector3Array())
		sn.append(PackedVector3Array())
		su.append(PackedVector2Array())
		sc.append(PackedColorArray())
	var roof_verts   := PackedVector3Array()
	var roof_normals := PackedVector3Array()
	var roof_colors  := PackedColorArray()

	var rng := RandomNumberGenerator.new()
	var built_count := 0
	var skipped_dist := 0

	for bld in buildings:
		var pts:  Array = bld["points"]
		var h:    float = float(bld["height"])
		var n:    int   = pts.size()
		if n < 3:
			continue

		# Centroid for style assignment + LOD classification
		var cx := 0.0; var cz := 0.0
		for pt in pts:
			cx += float(pt[0]); cz += float(pt[1])
		cx /= float(n); cz /= float(n)

		# LOD: in-park buildings get full detail; outside buildings get simple extrusion
		var in_park: bool = _loader._in_boundary(cx, cz)

		# Skip buildings too far from the park — only render the visible facade ring
		if not in_park and not _near_boundary(cx, cz):
			skipped_dist += 1
			continue
		built_count += 1

		# Base height: full per-vertex sampling for in-park, centroid-only for outside
		var base := INF
		if in_park:
			for pt in pts:
				base = minf(base, _loader._terrain_y(float(pt[0]), float(pt[1])))
		else:
			base = _loader._terrain_y(cx, cz)
		if base == INF:
			base = float(bld.get("base", 0.0))
		var top:  float = base + h

		var bld_name: String = str(bld.get("name", "")).to_lower()
		var year_built: int = int(bld.get("year_built", 0))
		var style := _building_style(cx, cz, h, year_built)
		# Named in-park buildings: override style per Wikimedia research
		if bld_name.contains("boathouse") or bld_name.contains("kerbs"):
			style = 2  # RED_BRICK — Kerbs Boathouse (red brick + copper roof)
		elif bld_name.contains("dairy"):
			style = 4  # DARK_STONE — The Dairy (Victorian stone + gables)
		elif bld_name.contains("belvedere") or bld_name.contains("castle"):
			style = 4  # DARK_STONE — Belvedere Castle (Manhattan schist)
		elif bld_name.contains("bandshell") or bld_name.contains("naumburg"):
			style = 0  # LIMESTONE — Naumburg Bandshell (concrete/limestone)
		elif bld_name.contains("blockhouse"):
			style = 4  # DARK_STONE — Blockhouse No. 1 (1814, Manhattan schist)
		elif bld_name.contains("pavilion") or bld_name.contains("ladies"):
			style = 0  # LIMESTONE — Ladies' Pavilion (ornamental cast iron, light)
		elif bld_name.contains("arsenal"):
			style = 2  # RED_BRICK — The Arsenal (1848, red brick Gothic Revival)
		elif bld_name.contains("chess") or bld_name.contains("checkers"):
			style = 4  # DARK_STONE — Chess & Checkers House (rustic stone)

		# Per-building tint variation via vertex color (±15%)
		rng.seed = int(abs(cx * 73.7 + cz * 131.1)) + 12345
		var rv := rng.randf_range(-0.15, 0.15)
		var gv := rng.randf_range(-0.12, 0.12)
		var bv := rng.randf_range(-0.08, 0.08)
		var bld_tint := Color(1.0 + rv, 1.0 + gv, 1.0 + bv)

		# Mark building footprint cells (only for in-park buildings; outside don't affect vegetation)
		if in_park:
			var grid_cell: float = _loader.BUILDING_GRID_CELL
			for pt in pts:
				var bx := float(pt[0]); var bz := float(pt[1])
				for di in range(-1, 2):
					for dj in range(-1, 2):
						var key := Vector2i(int(floor(bx / grid_cell)) + di,
											int(floor(bz / grid_cell)) + dj)
						_loader._building_grid[key] = true

		# --- Setback for tall towers (>40m): upper 35% recedes 1.5m ---
		var setback_h := 0.0  # height where setback begins (0 = no setback)
		var setback_inset := 1.5
		var has_setback := h > 40.0
		if has_setback:
			setback_h = h * 0.65

		# Walls – UV.x = metres along wall, UV.y = metres above base
		for i in n:
			var p1 := Vector2(float(pts[i][0]),           float(pts[i][1]))
			var p2 := Vector2(float(pts[(i + 1) % n][0]), float(pts[(i + 1) % n][1]))
			var seg := p2 - p1
			if seg.length_squared() < 0.01:
				continue
			var seg_len := seg.length()
			var norm := Vector3(-seg.y, 0.0, seg.x).normalized()

			if not in_park and not has_setback:
				# Outside park, no setback: single wall quad, no ground floor detail
				var a := Vector3(p1.x, base, p1.y)
				var b := Vector3(p2.x, base, p2.y)
				var c := Vector3(p2.x, top, p2.y)
				var d := Vector3(p1.x, top, p1.y)
				sv[style].append_array(PackedVector3Array([a, b, c, a, c, d]))
				for _j in range(6):
					sn[style].append(norm)
					sc[style].append(bld_tint)
				su[style].append_array(PackedVector2Array([
					Vector2(0.0, 0.0), Vector2(seg_len, 0.0),
					Vector2(seg_len, h), Vector2(0.0, 0.0),
					Vector2(seg_len, h), Vector2(0.0, h),
				]))
			elif has_setback:
				# Lower portion: base → setback
				var sb_y := base + setback_h
				var a := Vector3(p1.x, base, p1.y)
				var b := Vector3(p2.x, base, p2.y)
				var c := Vector3(p2.x, sb_y, p2.y)
				var d := Vector3(p1.x, sb_y, p1.y)
				sv[style].append_array(PackedVector3Array([a, b, c, a, c, d]))
				for _j in range(6):
					sn[style].append(norm)
					sc[style].append(bld_tint)
				su[style].append_array(PackedVector2Array([
					Vector2(0.0, 0.0), Vector2(seg_len, 0.0),
					Vector2(seg_len, setback_h), Vector2(0.0, 0.0),
					Vector2(seg_len, setback_h), Vector2(0.0, setback_h),
				]))
				# Upper portion: setback inward along normal
				var inset_off := Vector2(norm.x, norm.z) * setback_inset
				var ip1 := p1 + inset_off
				var ip2 := p2 + inset_off
				var upper_h := h - setback_h
				var ua := Vector3(ip1.x, sb_y, ip1.y)
				var ub := Vector3(ip2.x, sb_y, ip2.y)
				var uc := Vector3(ip2.x, top, ip2.y)
				var ud := Vector3(ip1.x, top, ip1.y)
				sv[style].append_array(PackedVector3Array([ua, ub, uc, ua, uc, ud]))
				for _j in range(6):
					sn[style].append(norm)
					sc[style].append(bld_tint * Color(0.95, 0.95, 0.95))
				su[style].append_array(PackedVector2Array([
					Vector2(0.0, setback_h), Vector2(seg_len, setback_h),
					Vector2(seg_len, h), Vector2(0.0, setback_h),
					Vector2(seg_len, h), Vector2(0.0, h),
				]))
			else:
				# In-park buildings: ground floor setback for buildings >8m
				var gf_h := 4.0  # ground floor height
				var gf_inset := 0.3  # how much the upper wall protrudes past ground floor
				if h > 8.0:
					# Ground floor face (recessed by gf_inset along normal)
					var gf_off := Vector2(norm.x, norm.z) * gf_inset
					var gp1 := p1 + gf_off
					var gp2 := p2 + gf_off
					var gf_top := base + gf_h
					var ga := Vector3(gp1.x, base, gp1.y)
					var gb := Vector3(gp2.x, base, gp2.y)
					var gc := Vector3(gp2.x, gf_top, gp2.y)
					var gd := Vector3(gp1.x, gf_top, gp1.y)
					sv[style].append_array(PackedVector3Array([ga, gb, gc, ga, gc, gd]))
					for _j in range(6):
						sn[style].append(norm)
						sc[style].append(bld_tint * Color(0.92, 0.92, 0.92))
					su[style].append_array(PackedVector2Array([
						Vector2(0.0, 0.0), Vector2(seg_len, 0.0),
						Vector2(seg_len, gf_h), Vector2(0.0, 0.0),
						Vector2(seg_len, gf_h), Vector2(0.0, gf_h),
					]))
					# Ledge top at ground floor line (horizontal face)
					var la := Vector3(gp1.x, gf_top, gp1.y)
					var lb := Vector3(gp2.x, gf_top, gp2.y)
					var lc := Vector3(p2.x, gf_top, p2.y)
					var ld := Vector3(p1.x, gf_top, p1.y)
					sv[style].append_array(PackedVector3Array([la, lb, lc, la, lc, ld]))
					for _j in range(6):
						sn[style].append(Vector3.UP)
						sc[style].append(bld_tint * Color(0.85, 0.85, 0.85))
					su[style].append_array(PackedVector2Array([
						Vector2(0.0, gf_h), Vector2(seg_len, gf_h),
						Vector2(seg_len, gf_h + 0.3), Vector2(0.0, gf_h),
						Vector2(seg_len, gf_h + 0.3), Vector2(0.0, gf_h + 0.3),
					]))
					# Upper wall above ground floor
					var ua := Vector3(p1.x, gf_top, p1.y)
					var ub := Vector3(p2.x, gf_top, p2.y)
					var uc := Vector3(p2.x, top, p2.y)
					var ud := Vector3(p1.x, top, p1.y)
					sv[style].append_array(PackedVector3Array([ua, ub, uc, ua, uc, ud]))
					for _j in range(6):
						sn[style].append(norm)
						sc[style].append(bld_tint)
					su[style].append_array(PackedVector2Array([
						Vector2(0.0, gf_h), Vector2(seg_len, gf_h),
						Vector2(seg_len, h), Vector2(0.0, gf_h),
						Vector2(seg_len, h), Vector2(0.0, h),
					]))
				else:
					# Short buildings — single wall, no setback
					var a := Vector3(p1.x, base, p1.y)
					var b := Vector3(p2.x, base, p2.y)
					var c := Vector3(p2.x, top, p2.y)
					var d := Vector3(p1.x, top, p1.y)
					sv[style].append_array(PackedVector3Array([a, b, c, a, c, d]))
					for _j in range(6):
						sn[style].append(norm)
						sc[style].append(bld_tint)
					su[style].append_array(PackedVector2Array([
						Vector2(0.0, 0.0), Vector2(seg_len, 0.0),
						Vector2(seg_len, h), Vector2(0.0, 0.0),
						Vector2(seg_len, h), Vector2(0.0, h),
					]))

				# Cornice ledge at roofline — 0.15m protruding, 0.2m tall (in-park only)
				if h > 6.0:
					var corn_d := 0.15  # cornice protrusion
					var corn_h := 0.20  # cornice height
					var corn_off := Vector2(-norm.x, -norm.z) * corn_d
					var cp1 := p1 - corn_off  # shifted outward
					var cp2 := p2 - corn_off
					var corn_base := top - corn_h
					# Front face of cornice
					var cfa := Vector3(cp1.x, corn_base, cp1.y)
					var cfb := Vector3(cp2.x, corn_base, cp2.y)
					var cfc := Vector3(cp2.x, top, cp2.y)
					var cfd := Vector3(cp1.x, top, cp1.y)
					sv[style].append_array(PackedVector3Array([cfa, cfb, cfc, cfa, cfc, cfd]))
					for _j in range(6):
						sn[style].append(norm)
						sc[style].append(bld_tint * Color(0.88, 0.88, 0.88))
					su[style].append_array(PackedVector2Array([
						Vector2(0.0, h - corn_h), Vector2(seg_len, h - corn_h),
						Vector2(seg_len, h), Vector2(0.0, h - corn_h),
						Vector2(seg_len, h), Vector2(0.0, h),
					]))
					# Bottom face of cornice (catches SSAO shadow)
					var cba := Vector3(p1.x, corn_base, p1.y)
					var cbb := Vector3(p2.x, corn_base, p2.y)
					sv[style].append_array(PackedVector3Array([cba, cbb, cfb, cba, cfb, cfa]))
					for _j in range(6):
						sn[style].append(Vector3.DOWN)
						sc[style].append(bld_tint * Color(0.80, 0.80, 0.80))
					su[style].append_array(PackedVector2Array([
						Vector2(0.0, 0.0), Vector2(seg_len, 0.0),
						Vector2(seg_len, 0.15), Vector2(0.0, 0.0),
						Vector2(seg_len, 0.15), Vector2(0.0, 0.15),
					]))

		# --- Rooftop parapet for buildings >10m (in-park only; outside skips for perf) ---
		var parapet_h := 0.8
		if h > 10.0 and in_park:
			for i in n:
				var p1 := Vector2(float(pts[i][0]),           float(pts[i][1]))
				var p2 := Vector2(float(pts[(i + 1) % n][0]), float(pts[(i + 1) % n][1]))
				var seg := p2 - p1
				if seg.length_squared() < 0.01:
					continue
				var seg_len := seg.length()
				var norm := Vector3(-seg.y, 0.0, seg.x).normalized()
				# If setback, parapet sits on upper (inset) polygon
				var pp1 := p1; var pp2 := p2
				if has_setback:
					var inset_off := Vector2(norm.x, norm.z) * setback_inset
					pp1 = p1 + inset_off; pp2 = p2 + inset_off
				var pa := Vector3(pp1.x, top, pp1.y)
				var pb := Vector3(pp2.x, top, pp2.y)
				var pc := Vector3(pp2.x, top + parapet_h, pp2.y)
				var pd := Vector3(pp1.x, top + parapet_h, pp1.y)
				sv[style].append_array(PackedVector3Array([pa, pb, pc, pa, pc, pd]))
				for _j in range(6):
					sn[style].append(norm)
					sc[style].append(bld_tint * Color(0.90, 0.90, 0.90))
				su[style].append_array(PackedVector2Array([
					Vector2(0.0, h), Vector2(seg_len, h),
					Vector2(seg_len, h + parapet_h), Vector2(0.0, h),
					Vector2(seg_len, h + parapet_h), Vector2(0.0, h + parapet_h),
				]))

		# Flat roof with randomized color
		var polygon := PackedVector2Array()
		for pt in pts:
			polygon.append(Vector2(float(pt[0]), float(pt[1])))
		var indices := Geometry2D.triangulate_polygon(polygon)
		# Named in-park building roof overrides (Wikimedia reference)
		var roof_col := Color(0.18, 0.17, 0.16)  # dark tar default
		var roof_override := false
		if bld_name.contains("boathouse") or bld_name.contains("kerbs"):
			roof_col = Color(0.29, 0.48, 0.42)    # aged copper verdigris #4A7B6B
			roof_override = true
		elif bld_name.contains("dairy"):
			roof_col = Color(0.35, 0.33, 0.30)    # dark slate
			roof_override = true
		elif bld_name.contains("belvedere") or bld_name.contains("castle"):
			roof_col = Color(0.32, 0.30, 0.28)    # schist gray cap
			roof_override = true
		elif bld_name.contains("blockhouse"):
			roof_col = Color(0.30, 0.28, 0.26)    # weathered stone cap
			roof_override = true
		elif bld_name.contains("arsenal"):
			roof_col = Color(0.22, 0.20, 0.18)    # dark slate
			roof_override = true
		if not roof_override:
			# Random roof: dark tar (30%), light concrete (30%), brown (20%), greenish (20%)
			var roof_rv := fmod(abs(cx * 11.3 + cz * 17.7), 10.0)
			if roof_rv >= 3.0 and roof_rv < 6.0:
				roof_col = Color(0.52, 0.50, 0.48)    # light concrete
			elif roof_rv >= 6.0 and roof_rv < 8.0:
				roof_col = Color(0.34, 0.28, 0.20)    # brown
			elif roof_rv >= 8.0:
				roof_col = Color(0.28, 0.36, 0.26)    # greenish patina
		for i in range(0, indices.size(), 3):
			roof_verts.append(Vector3(polygon[indices[i    ]].x, top, polygon[indices[i    ]].y))
			roof_verts.append(Vector3(polygon[indices[i + 1]].x, top, polygon[indices[i + 1]].y))
			roof_verts.append(Vector3(polygon[indices[i + 2]].x, top, polygon[indices[i + 2]].y))
			for _j in range(3):
				roof_normals.append(Vector3.UP)
				roof_colors.append(roof_col)

	print("Buildings: %d rendered, %d skipped (>%dm from boundary), %d total" % [built_count, skipped_dist, MAX_BUILDING_DIST, buildings.size()])

	# Build wall meshes per style
	var style_names := ["Limestone", "Glass", "RedBrick", "BuffBrick", "DarkStone"]
	var style_mats := [
		_make_facade_limestone(),
		_make_facade_glass(),
		_make_facade_red_brick(),
		_make_facade_buff_brick(),
		_make_facade_dark_stone(),
	]
	_loader.facade_materials = style_mats.duplicate()
	for s in range(5):
		if sv[s].is_empty():
			continue
		var mesh: ArrayMesh = _loader._make_mesh(sv[s], sn[s], su[s], sc[s])
		mesh.surface_set_material(0, style_mats[s])
		var mi := MeshInstance3D.new(); mi.mesh = mesh
		mi.name = "BuildingWalls_" + style_names[s]
		_loader.add_child(mi)

	# Roof mesh with per-building vertex colors
	if not roof_verts.is_empty():
		var r_mesh: ArrayMesh = _loader._make_mesh(roof_verts, roof_normals, null, roof_colors)
		var r_mat := StandardMaterial3D.new()
		r_mat.vertex_color_use_as_albedo = true
		r_mat.roughness = 0.92
		r_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		r_mesh.surface_set_material(0, r_mat)
		var r_mi := MeshInstance3D.new()
		r_mi.mesh = r_mesh
		r_mi.name = "BuildingRoofs"
		_loader.add_child(r_mi)



# ---------------------------------------------------------------------------
# Building facade materials + shaders (5 architectural styles)
# ---------------------------------------------------------------------------

# Facade shader (limestone, glass tower, dark stone)
func _facade_shader(use_brick: bool) -> String:
	# Unified facade shader — use_brick selects between procedural (facade_color/
	# facade_normal/facade_rough) and textured brick (brick_alb/brick_nrm/brick_rgh)
	# wall material. Window grid, night emission, atmospheric haze are shared.
	var wall_uniforms: String
	if use_brick:
		wall_uniforms = """
uniform sampler2D brick_alb;
uniform sampler2D brick_nrm : hint_normal;
uniform sampler2D brick_rgh;
uniform float tex_scale = 0.5;"""
	else:
		wall_uniforms = """
uniform vec3 wall_tint = vec3(0.78, 0.72, 0.62);
uniform float wall_rough = 0.88;
uniform float wall_metal = 0.0;
uniform sampler2D facade_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D facade_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D facade_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float facade_tile = 2.0;"""

	var wall_sampling: String
	if use_brick:
		wall_sampling = """
		vec2 tex_uv = UV * tex_scale;
		vec3 wall_col = texture(brick_alb, tex_uv).rgb * COLOR.rgb;
		if (is_cornice) { wall_col *= 0.78; }
		if (is_ledge)   { wall_col *= 1.12; }
		if (is_awning)  { wall_col *= 0.55; }
		ALBEDO    = clamp(wall_col, 0.0, 1.0);
		ROUGHNESS = texture(brick_rgh, tex_uv).r;
		METALLIC  = 0.0;
		vec3 wall_nrm = texture(brick_nrm, tex_uv).rgb;
		if (is_ledge) { wall_nrm.g = 0.7; }
		NORMAL_MAP = wall_nrm;
		NORMAL_MAP_DEPTH = is_ledge ? 1.2 : 1.0;
		emission += wall_col * 0.45;"""
	else:
		wall_sampling = """
		vec2 fac_uv = UV / facade_tile;
		vec3 fac_col = texture(facade_color, fac_uv).rgb;
		vec3 fac_nrm = texture(facade_normal, fac_uv).rgb;
		float fac_rgh = texture(facade_rough, fac_uv).r;
		float var_ = hash2(world_pos.xz * 0.15) * 0.08;
		vec3 base_wall = wall_tint * COLOR.rgb * (0.92 + var_);
		vec3 wall_col = mix(base_wall, fac_col * base_wall * 2.0, 0.35);
		if (is_cornice) { wall_col *= 0.78; }
		if (is_ledge)   { wall_col *= 1.12; }
		if (is_awning)  { wall_col *= 0.55; }
		ALBEDO    = clamp(wall_col, 0.0, 1.0);
		ROUGHNESS = mix(wall_rough, fac_rgh, 0.4);
		METALLIC  = wall_metal;
		NORMAL_MAP = fac_nrm;
		NORMAL_MAP_DEPTH = 0.8;
		if (is_ledge) {
			NORMAL_MAP = vec3(fac_nrm.r, 0.7, fac_nrm.b);
			NORMAL_MAP_DEPTH = 1.2;
		}
		emission += wall_col * 0.45;"""

	return """shader_type spatial;
render_mode cull_disabled;
""" + wall_uniforms + """
uniform vec3 glass_a = vec3(0.10, 0.13, 0.16);
uniform vec3 glass_b = vec3(0.35, 0.48, 0.58);
uniform float glass_rough = 0.12;
uniform float glass_metal = 0.15;
uniform float win_w = 1.5;
uniform float win_h = 2.0;
uniform float gap_x = 0.6;
uniform float gap_y = 0.8;
uniform float ground_h = 3.5;
uniform float night_factor = 0.0;
uniform sampler2D win_gradient : source_color, filter_linear_mipmap;

varying vec3 world_pos;

float hash2(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 43.21);
	return fract(p.x * p.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Per-building hash for window size jitter + UV offset
	vec2 bld = floor(world_pos.xz * 0.03);
	float bld_hash = hash2(bld * 0.7);
	float actual_win_w = win_w * (0.8 + bld_hash * 0.4);
	float actual_gap_x = gap_x * (0.8 + fract(bld_hash * 7.3) * 0.4);
	float actual_win_h = win_h * (0.85 + fract(bld_hash * 3.1) * 0.3);

	// Per-building UV.x offset so adjacent buildings don't align
	float uv_offset = fract(bld_hash * 5.7) * (actual_win_w + actual_gap_x);

	float cell_w = actual_win_w + actual_gap_x;
	float cell_h = actual_win_h + gap_y;
	float shifted_u = UV.x + uv_offset;
	float lx = fract(shifted_u / cell_w);
	float ly = fract((UV.y - ground_h) / cell_h);

	// Window reveal border (fraction of cell for 0.08m dark inset on each side)
	float reveal_frac = 0.08 / cell_w;
	float reveal_frac_y = 0.08 / cell_h;
	float win_frac_x = actual_win_w / cell_w;
	float win_frac_y = actual_win_h / cell_h;

	// Ground floor: wider, darker storefront openings
	bool is_ground = UV.y < ground_h && UV.y > 0.5;
	float gnd_lx = fract(shifted_u / (cell_w * 1.5));
	bool gnd_win = is_ground && (gnd_lx < 0.65) && (UV.y > 1.2);

	bool in_win = ((lx < win_frac_x) && (ly < win_frac_y) && (UV.y > ground_h)) || gnd_win;

	// Window reveal depth — dark shadow border on window edges
	bool in_reveal = false;
	if (in_win && !gnd_win) {
		bool near_edge_x = (lx < reveal_frac) || (lx > win_frac_x - reveal_frac);
		bool near_edge_y = (ly < reveal_frac_y) || (ly > win_frac_y - reveal_frac_y);
		in_reveal = near_edge_x || near_edge_y;
	}

	// Per-floor ledge lines — thin horizontal band at each floor level
	float floor_pos = (UV.y - ground_h) / cell_h;
	float floor_frac = fract(floor_pos);
	bool is_ledge = (UV.y > ground_h) && (floor_frac < 0.03 || floor_frac > 0.97);

	// Cornice bands every 4 floors
	float floor_num = floor_pos;
	bool is_cornice = (UV.y > ground_h) && (fract(floor_num / 4.0) < 0.08);

	// Ground floor awning shadow — 40% of buildings (hash-based)
	bool has_awning = fract(bld_hash * 3.3) < 0.40;
	bool is_awning = has_awning && UV.y > (ground_h - 0.3) && UV.y < ground_h;

	vec2 cell_idx = vec2(floor(shifted_u / cell_w), floor((UV.y - ground_h) / cell_h));
	float wrand = hash2(bld * 0.5 + cell_idx * 0.13);

	vec3 emission = vec3(0.0);

	if (in_win) {
		vec3 win_col;
		if (gnd_win) {
			win_col = mix(glass_a * 0.7, glass_b * 0.6, wrand * 0.4);
		} else {
			win_col = mix(glass_a, glass_b, wrand * 0.6);
		}
		ROUGHNESS = glass_rough;
		METALLIC  = glass_metal;
		if (in_reveal) {
			win_col *= 0.35;
			ROUGHNESS = 0.6;
			METALLIC = 0.0;
		}
		NORMAL_MAP = vec3(0.5, 0.5, 1.0);
		NORMAL_MAP_DEPTH = 0.0;

		// Night window emission
		if (night_factor > 0.01 && !in_reveal) {
			// ~65% of windows lit, warm interior tones
			bool is_lit = wrand < 0.65;
			if (gnd_win) { is_lit = wrand < 0.80; }
			if (is_lit) {
				float warmth = fract(wrand * 7.3);
				vec3 warm_light = mix(vec3(1.0, 0.68, 0.28), vec3(1.0, 0.76, 0.40), warmth);
				if (fract(wrand * 13.7) < 0.10) {
					warm_light = vec3(0.35, 0.42, 0.58);
				}
				float em_strength = gnd_win ? 0.60 : 0.50;
				em_strength *= (0.6 + wrand * 0.5);
				vec2 win_uv = gnd_win
					? vec2(gnd_lx / 0.65, clamp((UV.y - 1.2) / (ground_h - 1.2), 0.0, 1.0))
					: vec2(lx / win_frac_x, ly / win_frac_y);
				vec3 grad = texture(win_gradient, vec2(win_uv.x, 1.0 - win_uv.y)).rgb;
				emission = warm_light * grad * em_strength * night_factor;
				win_col = warm_light * grad * 0.15;
				ROUGHNESS = 0.9;
				METALLIC = 0.0;
			}
		}
		ALBEDO = win_col;
	} else {
""" + wall_sampling + """
	}

	EMISSION = emission;

	// Atmospheric distance fade — buildings dissolve into haze
	float bldg_dist = length(world_pos.xyz - INV_VIEW_MATRIX[3].xyz);
	float atm_fade = smoothstep(120.0, 400.0, bldg_dist);
	vec3 haze_col = vec3(0.58, 0.56, 0.52);
	ALBEDO = mix(ALBEDO, haze_col, atm_fade * 0.45);
	ROUGHNESS = mix(ROUGHNESS, 0.95, atm_fade * 0.3);
	EMISSION = mix(EMISSION, haze_col * 0.3, atm_fade * 0.5);
}
"""


func _set_facade_textures(mat: ShaderMaterial) -> void:
	var fc: ImageTexture = _loader._load_tex("res://textures/Facade011_2K-JPG_Color.jpg")
	var fn: ImageTexture = _loader._load_tex("res://textures/Facade011_2K-JPG_NormalGL.jpg")
	var fr: ImageTexture = _loader._load_tex("res://textures/Facade011_2K-JPG_Roughness.jpg")
	if fc: mat.set_shader_parameter("facade_color", fc)
	if fn: mat.set_shader_parameter("facade_normal", fn)
	if fr: mat.set_shader_parameter("facade_rough", fr)
	mat.set_shader_parameter("facade_tile", 2.0)
	var wg: ImageTexture = _loader._load_tex("res://textures/window_night_gradient.png")
	if wg: mat.set_shader_parameter("win_gradient", wg)


func _make_facade_limestone() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _loader._get_shader("facade_proc", _facade_shader(false))
	mat.set_shader_parameter("wall_tint", Vector3(0.78, 0.72, 0.62))
	mat.set_shader_parameter("wall_rough", 0.88)
	mat.set_shader_parameter("wall_metal", 0.0)
	mat.set_shader_parameter("glass_a", Vector3(0.10, 0.13, 0.16))
	mat.set_shader_parameter("glass_b", Vector3(0.35, 0.48, 0.58))
	mat.set_shader_parameter("glass_rough", 0.12)
	mat.set_shader_parameter("glass_metal", 0.15)
	mat.set_shader_parameter("win_w", 1.5)
	mat.set_shader_parameter("win_h", 2.0)
	mat.set_shader_parameter("gap_x", 0.6)
	mat.set_shader_parameter("gap_y", 0.8)
	mat.set_shader_parameter("ground_h", 3.5)
	_set_facade_textures(mat)
	return mat


func _make_facade_glass() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _loader._get_shader("facade_proc", _facade_shader(false))
	mat.set_shader_parameter("wall_tint", Vector3(0.50, 0.54, 0.58))
	mat.set_shader_parameter("wall_rough", 0.40)
	mat.set_shader_parameter("wall_metal", 0.35)
	mat.set_shader_parameter("glass_a", Vector3(0.22, 0.32, 0.48))
	mat.set_shader_parameter("glass_b", Vector3(0.42, 0.55, 0.68))
	mat.set_shader_parameter("glass_rough", 0.08)
	mat.set_shader_parameter("glass_metal", 0.40)
	mat.set_shader_parameter("win_w", 2.0)
	mat.set_shader_parameter("win_h", 2.5)
	mat.set_shader_parameter("gap_x", 0.3)
	mat.set_shader_parameter("gap_y", 0.5)
	mat.set_shader_parameter("ground_h", 4.5)
	_set_facade_textures(mat)
	return mat


func _make_facade_red_brick() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _loader._get_shader("facade_brick", _facade_shader(true))
	mat.set_shader_parameter("brick_alb", _loader._load_tex("res://textures/Bricks059_2K-JPG_Color.jpg"))
	mat.set_shader_parameter("brick_nrm", _loader._load_tex("res://textures/Bricks059_2K-JPG_NormalGL.jpg"))
	mat.set_shader_parameter("brick_rgh", _loader._load_tex("res://textures/Bricks059_2K-JPG_Roughness.jpg"))
	mat.set_shader_parameter("tex_scale", 0.5)
	mat.set_shader_parameter("glass_a", Vector3(0.08, 0.10, 0.14))
	mat.set_shader_parameter("glass_b", Vector3(0.22, 0.30, 0.40))
	mat.set_shader_parameter("glass_rough", 0.14)
	mat.set_shader_parameter("glass_metal", 0.12)
	mat.set_shader_parameter("win_w", 1.3)
	mat.set_shader_parameter("win_h", 1.7)
	mat.set_shader_parameter("gap_x", 0.8)
	mat.set_shader_parameter("gap_y", 1.0)
	mat.set_shader_parameter("ground_h", 3.0)
	var wg: ImageTexture = _loader._load_tex("res://textures/window_night_gradient.png")
	if wg: mat.set_shader_parameter("win_gradient", wg)
	return mat


func _make_facade_buff_brick() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _loader._get_shader("facade_brick", _facade_shader(true))
	mat.set_shader_parameter("brick_alb", _loader._load_tex("res://textures/Bricks031_2K-JPG_Color.jpg"))
	mat.set_shader_parameter("brick_nrm", _loader._load_tex("res://textures/Bricks031_2K-JPG_NormalGL.jpg"))
	mat.set_shader_parameter("brick_rgh", _loader._load_tex("res://textures/Bricks031_2K-JPG_Roughness.jpg"))
	mat.set_shader_parameter("tex_scale", 0.5)
	mat.set_shader_parameter("glass_a", Vector3(0.10, 0.12, 0.16))
	mat.set_shader_parameter("glass_b", Vector3(0.30, 0.40, 0.50))
	mat.set_shader_parameter("glass_rough", 0.12)
	mat.set_shader_parameter("glass_metal", 0.15)
	mat.set_shader_parameter("win_w", 1.5)
	mat.set_shader_parameter("win_h", 2.0)
	mat.set_shader_parameter("gap_x", 0.6)
	mat.set_shader_parameter("gap_y", 0.8)
	mat.set_shader_parameter("ground_h", 3.5)
	var wg: ImageTexture = _loader._load_tex("res://textures/window_night_gradient.png")
	if wg: mat.set_shader_parameter("win_gradient", wg)
	return mat


func _make_facade_dark_stone() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _loader._get_shader("facade_proc", _facade_shader(false))
	mat.set_shader_parameter("wall_tint", Vector3(0.58, 0.54, 0.48))
	mat.set_shader_parameter("wall_rough", 0.92)
	mat.set_shader_parameter("wall_metal", 0.0)
	mat.set_shader_parameter("glass_a", Vector3(0.06, 0.08, 0.10))
	mat.set_shader_parameter("glass_b", Vector3(0.18, 0.22, 0.28))
	mat.set_shader_parameter("glass_rough", 0.20)
	mat.set_shader_parameter("glass_metal", 0.05)
	mat.set_shader_parameter("win_w", 1.2)
	mat.set_shader_parameter("win_h", 1.5)
	mat.set_shader_parameter("gap_x", 1.0)
	mat.set_shader_parameter("gap_y", 1.2)
	mat.set_shader_parameter("ground_h", 2.5)
	_set_facade_textures(mat)
	return mat
