# Contributing to Central Park Walk

Thank you for your interest. This project grows with human attention — every photo, scan, recording, measurement, or line of code makes the AI's interpretation of Central Park richer.

You don't need to be a developer to contribute. Some of the most valuable contributions are data: a photo of a lamppost, a recording of birdsong at the Ramble, a measurement of a bench. If you've been to Central Park, you have something to offer.

## Find What's Missing

**In the game:** Press **G** to toggle data gap markers. Orange markers show statues/fountains needing scans, green markers show areas needing tree surveys. Each marker displays the real-world GPS coordinates so you can navigate there with your phone.

**On the map:** Open [`data_gaps.geojson`](data_gaps.geojson) on GitHub — it renders as a clickable interactive map. Each pin shows what's needed and how to contribute. Load it on your phone to navigate to the exact spot.

**Machine-readable:** `data_gaps.json` has full details for every gap with IDs, coordinates, and format specs.

The gap list regenerates automatically — when you fill a gap, it disappears from the map.

## Data Contributions (No coding required)

### 3D Scans (65 statues + 3 fountains needed)

We have scans of 4 out of 69 scannable objects (3 statues + Bethesda Fountain). The rest show only floating labels in the simulation.

**What you need:** iPhone 12 Pro+ or iPad Pro (has LiDAR), or DSLR with 50+ photos

**Free apps:** Polycam, Scaniverse, 3d Scanner App

**Steps:**
1. Open `data_gaps.geojson` on your phone to find the statue
2. Scan from all angles — walk slowly around the entire object, include the base
3. Export as GLB in real-world scale (metres), decimated to <100K triangles
4. Submit a PR adding your scan to `models/contributions/statue_name.glb`

**License:** CC-BY 4.0 or CC-BY-SA 4.0 (state in your PR description)

**High priority scans:** Balto, Cleopatra's Needle, Shakespeare, Burnett Memorial Fountain, Cherry Hill Fountain, Sophie Loeb Fountain

### Tree Surveys

Some areas have fewer trees in our census data than exist in reality. The Mall / Literary Walk has 44 trees in our data but ~150 American Elms in reality.

**What you need:** Phone with GPS + tape measure

**Steps:**
1. Open `data_gaps.geojson` to find the flagged area
2. For each tree, record: GPS location, species (common name), trunk diameter at chest height in cm, estimated height in metres
3. Submit as CSV:

```csv
lat,lon,species,dbh_cm,height_m,notes
40.7724,-73.9713,American Elm,65,22,Mall east row
40.7725,-73.9713,American Elm,58,20,Mall east row
```

**Submit:** GitHub issue with CSV data, or PR adding to `data/tree_surveys/area_name.csv`

### Photography
Reference photos help verify contributed data and guide texture work. Useful subjects:
- Close-ups of stone textures (schist outcrops, granite curbs, sandstone walls)
- Architectural details on bridges, arches, and tunnels
- Seasonal changes at specific locations
- Ground surfaces: paths, plazas, lawns

Upload to Wikimedia Commons with location metadata. Then open an issue linking your uploads.

### OpenStreetMap Editing
Only 7–11% of Central Park's furniture is mapped in OSM. If you visit the park, you can map what you see:

1. Create an account at [openstreetmap.org](https://www.openstreetmap.org/)
2. Use [StreetComplete](https://streetcomplete.app/) (Android) or [Every Door](https://every-door.app/) for easy mobile mapping
3. Add benches, lampposts, trash cans, drinking fountains with their exact positions
4. Tag with standard OSM tags: `amenity=bench`, `highway=street_lamp`, etc.

We re-download OSM data periodically, so your edits will appear in the simulation.

## Validation

All contributions are reviewed before merge:
- **Coordinates** must fall within Central Park boundary
- **Species names** must match NYC Parks approved species list
- **Trunk diameters** must be 5–300 cm, heights 2–50 m
- **Tree positions** must be >1m apart (no duplicates)
- **Scans** must be recognizable as the named object at correct scale
- **License** must be CC-BY 4.0, CC-BY-SA 4.0, or public domain

## Technical Contributions

### Getting Started

```bash
git clone https://github.com/central-park-walk/central-park-walk.git
cd central-park-walk
# Follow setup in README.md
```

### Code Style

**GDScript** (modular architecture):
- `main.gd` — scene root: terrain, sky, player, HUD, day/night cycle
- `park_loader.gd` — orchestrator + shared utilities (paths, heightmap, mesh helpers)
- `*_builder.gd` — 8 focused modules: bridge, water, tunnel, building, tree, boundary, furniture, infrastructure
- `player.gd` — first-person CharacterBody3D controller
- Follow Godot's [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)
- Use `snake_case` for variables and functions, `PascalCase` for classes
- Private members prefixed with `_`

**Python** (data pipeline, Blender scripts):
- Standard PEP 8
- Blender scripts follow the `make_*.py` pattern: build geometry, apply materials, export GLB
- Data pipeline scripts are idempotent: safe to re-run
- `convert_to_godot.py` pre-bakes: park_data.json/bin, heightmap.bin, terrain_mesh.bin, world_atlas.bin, landuse_map.png, boundary_mask.png — all spatial grids at 8192×8192 (0.61m/cell) matching LiDAR resolution

### Priority Areas

1. **Additional tree species models**: We now have 15 custom Blender tree models (oak, elm, maple, birch, cherry, ginkgo, honeylocust, linden, london plane, callery pear, pine, + generic deciduous/conifer). More species detail welcome — subspecies variants, size classes, seasonal accuracy. Blender scripts follow the `scripts/make_*.py` pattern.
2. **Interior spaces**: Bethesda Arcade (Minton tile ceiling), bridge underpasses, tunnel interiors. The LiDAR terrain creates terrain caves where architectural spaces should be.
3. **Ground detail**: Terrain tile models for wildflowers, grass, undergrowth, ferns.
4. **Cross-platform**: Currently Linux-only with Forward+ renderer. Testing and fixes for Windows/macOS welcome.
5. **Performance**: No GPU profiling has been done. Help identify bottlenecks.

### Pull Request Process

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/description`)
3. Make your changes
4. Test by running Godot and walking through relevant areas
5. Submit a PR with a clear description of what changed and why

### Data-First Philosophy

Everything in this project comes from real data. Nothing is procedurally generated except what must be (weather, lighting, time). If data is missing, we leave a gap — gaps signal what the real world hasn't been measured yet.

- If furniture positions are wrong, find the real positions (OSM, photos) rather than randomizing
- If a material color looks off, research the real material (Wikimedia Commons) rather than guessing
- If a tree species is wrong, check the NYC Tree Census rather than picking aesthetically

## Creative Contributions

### Historical Layers
Central Park has 170 years of history. Help us map:
- What specific locations looked like at different points in time
- Historical events tied to specific places
- Olmsted and Vaux's original design intentions vs. current state

### Literary Connections
Central Park appears in thousands of novels, films, songs, and poems. Help map creative works to the specific places they reference.

## Questions?

Open an issue or start a discussion. We're a small team and we're glad you're here.
