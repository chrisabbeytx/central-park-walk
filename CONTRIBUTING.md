# Contributing to Central Park Walk

Thank you for your interest. This project grows with human attention — every photo, scan, recording, measurement, or line of code makes the AI's interpretation of Central Park richer.

You don't need to be a developer to contribute. Some of the most valuable contributions are data: a photo of a lamppost, a recording of birdsong at the Ramble, a measurement of a bench. If you've been to Central Park, you have something to offer.

## Data Contributions (No coding required)

### Photography
Take photos of specific landmarks, materials, and details. We use Wikimedia Commons as our visual reference library. Useful subjects:
- Close-ups of stone textures (schist outcrops, granite curbs, sandstone walls)
- Architectural details on bridges, arches, and tunnels
- Furniture: lampposts, benches, trash cans, drinking fountains, signs
- Seasonal changes: spring blossoms, summer canopy, autumn foliage, winter bare branches
- Ground surfaces: paths, plazas, lawns at different times of year

Upload to Wikimedia Commons with location metadata if possible. Then open an issue with the "Data Contribution" template.

### 3D Scans
Photogrammetry scans of statues, architectural details, and rock outcrops are extremely valuable. We currently have 3 of 106 known statues scanned.

**Tools**: Meshroom (free), RealityCapture, Polycam (phone), Luma AI (phone)
**Tips**: Capture 40-60 overlapping photos in diffuse light. Avoid harsh shadows. Include a scale reference if possible.
**Upload**: Sketchfab (CC-BY license) or open an issue with a download link.

### Field Recordings
We need real Central Park audio to replace our procedural sounds. Useful recordings:
- Bird calls at specific locations and times of day/year
- Water sounds (lake lapping, fountain splash, stream flow)
- Ambient atmosphere at different park zones
- Seasonal sounds (cicadas, wind through leaves, ice)

Upload to Freesound.org (CC0 preferred) or open an issue.

### OpenStreetMap Editing
Only 7–11% of Central Park's furniture is mapped in OSM. If you visit the park, you can map what you see:

1. Create an account at [openstreetmap.org](https://www.openstreetmap.org/)
2. Use [StreetComplete](https://streetcomplete.app/) (Android) or [Every Door](https://every-door.app/) for easy mobile mapping
3. Add benches, lampposts, trash cans, drinking fountains with their exact positions
4. Tag with standard OSM tags: `amenity=bench`, `highway=street_lamp`, etc.

We re-download OSM data periodically, so your edits will appear in the simulation.

### Local Knowledge
If you know Central Park well, open an "Area Detail" issue. Tell us what's wrong or missing in a specific area. Reference photos are extremely helpful.

## Technical Contributions

### Getting Started

```bash
git clone https://github.com/central-park-walk/central-park-walk.git
cd central-park-walk
# Follow setup in README.md
```

### Code Style

**GDScript** (main.gd, park_loader.gd, player.gd):
- Follow Godot's [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)
- Use `snake_case` for variables and functions, `PascalCase` for classes
- Private members prefixed with `_`
- Keep shader code as inline strings in GDScript (the project has no separate .gdshader files)

**Python** (data pipeline, Blender scripts):
- Standard PEP 8
- Blender scripts follow the `make_*.py` pattern: build geometry, apply materials, export GLB
- Data pipeline scripts are idempotent: safe to re-run

### Priority Areas

1. **Species-accurate tree models**: We need American Elm, Red Oak, Sugar Maple, Pin Oak models. The park's 4 generic Quaternius models don't capture species character. Blender scripts preferred (following the `scripts/make_*.py` pattern).
2. **Interior spaces**: Bethesda Arcade (Minton tile ceiling), bridge underpasses, tunnel interiors. The LiDAR terrain creates terrain caves where architectural spaces should be.
3. **Ground detail**: Terrain tile models for wildflowers, grass, undergrowth, ferns. The systems exist in code but need proper 3D models.
4. **Cross-platform**: Currently Linux-only with Forward+ renderer. Testing and fixes for Windows/macOS welcome.
5. **Performance**: No GPU profiling has been done. Help identify bottlenecks.

### Pull Request Process

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/description`)
3. Make your changes
4. Test by running Godot and walking through relevant areas
5. Submit a PR with a clear description of what changed and why

### Data-First Philosophy

When contributing, prefer real data over procedural generation:
- If furniture positions are wrong, find the real positions (OSM, photos) rather than randomizing
- If a material color looks off, research the real material (Wikimedia Commons) rather than guessing
- If a tree species is wrong, check the NYC Tree Census rather than picking aesthetically

Gaps are okay. A gap in the simulation is a signal that we need more data from the real world. That's valuable information.

## Creative Contributions

### Guided Meditations
Chrissie is developing contemplative experiences within the park. If you're interested in contributing meditation scripts, ambient narratives, or mindfulness exercises tied to specific park locations, open an issue to discuss.

### Historical Layers
Central Park has 170 years of history. Help us map:
- What specific locations looked like at different points in time
- Historical events tied to specific places
- Olmsted and Vaux's original design intentions vs. current state

### Literary Connections
Central Park appears in thousands of novels, films, songs, and poems. Help map creative works to the specific places they reference.

## Questions?

Open an issue or start a discussion. We're a small team and we're glad you're here.
