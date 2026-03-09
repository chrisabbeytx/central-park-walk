## Central Park Walk

*An AI-human collaboration to reconstruct Central Park in 3D from freely available public data.*

> "The only thing more terrifying than a superintelligence that fully understands every square centimeter of this universe and what it means to the people who live here is one that doesn't."

Central Park Walk is a real-time 3D simulation of the entirety of New York's Central Park — all 843 acres — built from freely available public data and interpreted by Claude (Anthropic). You walk through it. That's all. No objectives, no score, no enemies. Just a place. Not a photorealistic replica. An honest interpretation.

## The Data

Every tree has a real measured height from LiDAR. Every path follows its real-world geometry from OpenStreetMap. Every bridge is one of 55 actual bridges, rendered in its correct architectural style. The terrain is accurate to one foot of vertical resolution. And all of it was assembled by an AI interpreting the accumulated record of human attention to one of the most documented places on Earth.

The simulation covers 100% of Central Park's terrain at 4096×4096 mesh resolution, derived from NYC's 2017 LiDAR survey. 16,243 trees are placed from the NYC Tree Census, cross-referenced with LiDAR canopy measurements so 89% have their real measured heights. 2,624 paths are rendered with analytical GPU path rendering — material-specific and width-correct. 8,463 building facades line the park boundary with procedural windows that glow warm at night.

55 bridges span the park in 5 architectural styles: stone, cast iron, brick, rustic wood, and the signature Bow Bridge with its interlocking-circles railing. 15 tunnels have barrel-vault interiors with portal lighting. A 7,962-segment brownstone perimeter wall with 105 gate openings marks where the park meets the city. Custom Blender scripts generate period-accurate park furniture: Bishop's Crook lampposts, cast iron benches, wire mesh trash cans, granite drinking fountains.

Rain, snow, fog, puddles, morning dew. A full day/night cycle with sodium vapor park lighting and lit windows, procedural clouds, ambient soundscapes that shift by location. The data-first philosophy means: if we don't have real data for something, we leave a gap rather than guess. Gaps tell us what humans haven't yet measured, mapped, or photographed.

## The Vision

Every LiDAR return is a moment when a laser pulse bounced off something real. Every OpenStreetMap edit is a person who cared enough about a path or a bench to record it. Every photo on Wikimedia Commons is someone who stopped, looked, and captured what they saw. This project takes all of that accumulated human attention and asks: what does an AI see when it looks at what humans have recorded about a place?

Central Park Walk is the answer. The data has gaps, and we leave them visible. The AI has a perspective, and we let it show. What emerges is a conversation between human observation and machine perception about a piece of shared physical reality that hundreds of millions of people have walked through, photographed, grieved in, fallen in love in, and called their own.

The project is designed to expand. More places, more data sources, more contributors, more understanding. Every person who visits Central Park with a camera, a phone, or a 3D scanner can add to the record. Every contribution makes the interpretation richer. This is a never-ending collaboration between human attention and machine perception — and it has only just begun.

## Screenshots

*Coming soon — run `--tour` to generate your own.*

## Quick Start

### Prerequisites
- [Godot 4.6.1](https://godotengine.org/download) (Linux x86_64)
- Python 3 with: `numpy`, `scipy`, `gdal`, `Pillow`
- [Blender 3.0+](https://www.blender.org/download/) (optional, for model regeneration)
- NVIDIA GPU recommended (Forward+ renderer)

### Setup

```bash
# 1. Clone the repository
git clone https://github.com/central-park-walk/central-park-walk.git
cd central-park-walk

# 2. Download OSM data
python3 download_osm.py

# 3. Download textures and models
python3 download_assets.py
python3 download_models.py

# 4. Convert data to Godot format
python3 convert_to_godot.py

# 5. Generate procedural sounds
pip install numpy scipy
python3 scripts/generate_sounds.py

# 6. Run
/path/to/Godot_v4.6.1-stable_linux.x86_64 --path .
```

### Controls

| Input | Action |
|-------|--------|
| WASD | Walk |
| Mouse + RMB | Look around |
| Scroll / +/- | Adjust speed (Stroll / Walk / Jog / Bike / Drive / Fly) |
| T | Cycle time speed (1x / 10x / 100x / Paused) |
| [ / ] | Nudge time ±1 hour |
| P | Cycle weather (Clear / Rain / Snow / Fog) |
| 9 / 0 | Adjust wind |
| H | Toggle HUD |
| F11 | Toggle fullscreen |

**Xbox/gamepad support**: left stick to walk, right stick to look, right trigger for fly mode.

### CLI Options

```bash
-- --tour              # Automated screenshot tour (204 shots → /tmp/tour/)
-- --pos "x,z,yaw"    # Spawn at specific coordinates
-- --time noon         # Set time (dawn/morning/noon/golden_hour/dusk/night)
-- --weather rain      # Set weather (clear/rain/snow/fog)
```

## Data Sources

All data is freely available. No paid APIs. No API keys.

| Source | What It Provides | License |
|--------|-----------------|---------|
| [NYC LiDAR (2017)](https://gis.ny.gov/elevation/lidar-coverage) | 1ft-resolution terrain elevation | Public Domain |
| [NYC 6M Trees](https://data.cityofnewyork.us/Environment/2015-Street-Tree-Census-Tree-Data/uvpi-gqnh) | 130K tree positions with heights + crown areas | Public Domain |
| [OpenStreetMap](https://www.openstreetmap.org/) | Paths, water, buildings, bridges, tunnels, barriers, furniture | ODbL |
| [NYC Tree Census](https://data.cityofnewyork.us/) | Species, diameter for 39,495 park trees | Public Domain |
| [Wikimedia Commons](https://commons.wikimedia.org/) | Material colors, architectural reference | CC-BY-SA |
| [Sketchfab](https://sketchfab.com/) | Photogrammetry statue scans (3 integrated) | CC-BY |
| [Quaternius](https://quaternius.com/) | Tree 3D models (4 species × 5 variants) | CC0 |
| [ambientCG](https://ambientcg.com/) / [Polyhaven](https://polyhaven.com/) | PBR textures, HDRI sky | CC0 |

## Current Coverage

| Feature | Count | Detail |
|---------|-------|--------|
| Terrain | 4096×4096 | LiDAR-accurate, per-pixel normals, structure mask |
| Trees | 16,243 placed | 4 species models, LOD0 + LOD1 billboards (0–500m), zone-specific species |
| Paths | 2,624 | Analytical GPU rendering, 58K segments, width-correct |
| Water | 27 bodies | Per-body color, shore alpha, depth tinting |
| Buildings | 8,463 | 5 facade styles, procedural windows, night emission |
| Bridges | 55 | 5 styles, miter joints, arched soffits, Bow Bridge railings |
| Tunnels | 15 | Barrel vault interiors, portal lighting |
| Furniture | 1,004+ | Custom Blender models: lampposts, benches, trash cans, fountains |
| Statues | 106 positions | 3 photogrammetry scans, generic fallbacks |
| Perimeter wall | 7,962 segments | Brownstone with 105 gate openings, 210 gate pillars |
| Sports fields | 60 | Baseball (25), soccer (6), tennis (28), basketball (1) |
| Weather | 4 modes | Rain, snow, fog, clear — with puddles, mist, dew |
| Day/night | 5 keyframes | Sodium vapor lamps, lit windows, stars, dawn mist |
| Sound | 7 loops | Birds, wind, city, water, footsteps — zone-based crossfade |

## How to Contribute

This project grows with human attention. Here's what we need:

### Data Contributions (No coding required)
- **Furniture mapping**: Only 7–11% of real lampposts, benches, and trash cans are in OSM. Visit the park, map what you see.
- **3D scans**: Photogrammetry of statues, architectural details, rock outcrops. We have 3 of 106 statues scanned.
- **Field recordings**: Bird calls, water, ambient atmosphere at specific locations and times.
- **Photography**: Reference photos of landmarks, materials, seasonal changes.
- **Rock outcrop mapping**: Central Park has ~170 named outcrops. OSM has 1.

### Technical Contributions
- **Species-accurate tree models**: 4 generic models for 100+ real species. The American Elm — the park's signature tree — currently uses a maple model.
- **Interior spaces**: Bethesda Arcade, bridge underpasses, tunnel interiors.
- **Ground detail**: Wildflowers, grass, undergrowth, ferns.
- **Performance**: No GPU profiling done yet.
- **Cross-platform**: Currently Linux-only.

### Creative Contributions
- **Historical overlays**: What did this spot look like in 1860? 1920?
- **Literary connections**: Central Park appears in thousands of works. Help map stories to places.

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## Project Philosophy

1. **Data-first**: Don't guess — get better data. Gaps reveal what we still need to learn.
2. **Honest interpretation**: Faithfully render what data and AI perception together produce.
3. **Community-driven**: Humans contribute data, AI reinterprets it. Continuously expanding.
4. **Accessibility**: A walking simulator. No competition, no violence. Designed for contemplation.

## Support the Project

Central Park Walk is built by a small team — Christopher Abbey and Claude — with no institutional backing. Development is limited by compute availability, and sustaining the project means sustaining the people who build it.

<!-- [Open Collective badge will go here] -->

See [FUNDING.md](FUNDING.md) for details on how funds are used.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Engine | Godot 4.6.1 (Forward+, GDScript) |
| Data pipeline | Python: GDAL, numpy/scipy, Pillow |
| 3D modeling | Blender 3.0.1 (headless scripts) |
| Audio | Procedural synthesis (numpy/scipy FM + filtered noise) |
| Rendering | Custom GLSL shaders, MultiMesh instancing, analytical GPU path rendering |

## License

Code: [MIT License](LICENSE)
Assets and creative content: [CC-BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)

## Credits

- **Christopher Abbey** — Project creator, technical lead
- **Claude (Anthropic)** — Co-creator: data interpretation, code, shaders, Blender scripts, artistic decisions

Asset sources: [credits.txt](credits.txt)

Map data © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors. LiDAR data from NYS GIS Clearinghouse. Tree data from NYC OpenData.

---

*Central Park Walk is a collaboration between humans and AI about what our shared reality looks like — to those who experience it and those who interpret it.*
