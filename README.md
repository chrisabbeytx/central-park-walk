## Central Park Walk

*An AI-human collaboration to reconstruct Central Park in 3D from freely available public data.*

Central Park Walk is a real-time 3D walking simulation of all 843 acres of New York's Central Park, built entirely from freely available public data — LiDAR surveys, OpenStreetMap, the NYC Tree Census, building footprints — and interpreted by Claude (Anthropic). No objectives, no score. Just a place.

Every tree has a real measured height. Every path follows its real-world geometry. Every building has its actual footprint and construction year. The terrain is accurate to one foot. The data has gaps, and we leave them visible — gaps tell us what humans haven't yet measured or mapped.

![Autumn Dusk — Central Park West Skyline](screenshots/cpw_skyline_autumn_dusk.png)
*Autumn dusk on the Literary Walk. Per-species fall colors driven by phenology data. 6,557 buildings from NYC Building Footprints.*

![Summer Golden Hour — Literary Walk](screenshots/literary_walk_summer_golden.png)
*The Literary Walk at golden hour. Every tree placed from NYC Tree Census data, every path from OpenStreetMap.*

![Winter Snow — Sheep Meadow](screenshots/sheep_meadow_winter_noon.png)
*Sheep Meadow under snow. Rain, snow, fog, puddles, frost, and a full day/night cycle with seasonal atmosphere.*

![North Woods Rustic Bridge](screenshots/north_woods_bridge.png)
*A rustic wood bridge in the North Woods — one of 55 bridges rendered in 5 architectural styles.*

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

# 5. Run
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
| N / Shift+N | Cycle season (Spring / Summer / Autumn / Winter) |
| G | Toggle data gap markers |
| H | Toggle HUD |
| F11 | Toggle fullscreen |
| F12 | Screenshot (saves to screenshots/) |

**Xbox/gamepad**: left stick walk, right stick look, right trigger fly mode.

### CLI Options

```bash
-- --tour              # Automated screenshot tour (340 shots → /tmp/tour/)
-- --tour-showcase     # Curated showcase (22 shots — ground + aerial views)
-- --readme-shots      # Regenerate the 4 README screenshots → screenshots/
-- --pos "x,z,yaw"    # Spawn at specific coordinates
-- --time noon         # Set time (dawn/morning/noon/golden_hour/dusk/night)
-- --weather rain      # Set weather (clear/rain/snow/fog)
-- --season autumn     # Set season (spring/summer/autumn/fall/winter)
```

## What's In It

| Feature | Count | Source |
|---------|-------|--------|
| Terrain | 4096×4096 mesh | NYC LiDAR 2017 (1ft resolution) |
| Trees | ~9,300 | NYC Tree Census + OSM + woodland scatter in 12 ecological zones |
| Paths | 2,624 | OpenStreetMap (58K segments, GPU-rendered) |
| Water | 23 bodies + 10 streams | OpenStreetMap polygons |
| Buildings | 6,557 | NYC Building Footprints + LiDAR heights |
| Bridges | 55 | 5 architectural styles from OSM |
| Tunnels | 15 | Barrel vault interiors with portal lighting |
| Furniture | 1,022+ | Lampposts (201), benches (610), trash cans (166), fountains (19), flagpoles (18), water towers (45) |
| Statues | 106 positions | 4 photogrammetry scans + Cleopatra's Needle model, rest labeled |
| Perimeter wall | 7,962 segments | Manhattan schist, 105 gate openings |
| Sports fields | 147 | Tennis, basketball, baseball, soccer, handball |
| Seasons | 4 | Per-species phenology, leaf scatter, water color, atmosphere |
| Weather | 5 modes | Rain, thunderstorm, snow, fog, clear — with surface response |
| Day/night | Full cycle | 48-lamp pool, lit windows, NYC light pollution, moon |

## Data Sources

All data is freely available. No paid APIs. No API keys.

| Source | What It Provides | License |
|--------|-----------------|---------|
| [NYC LiDAR (2017)](https://gis.ny.gov/elevation/lidar-coverage) | 1ft terrain elevation | Public Domain |
| [NYC 6M Trees](https://data.cityofnewyork.us/Environment/2015-Street-Tree-Census-Tree-Data/uvpi-gqnh) | Tree positions, heights, crown areas | Public Domain |
| [OpenStreetMap](https://www.openstreetmap.org/) | Paths, water, buildings, bridges, furniture | ODbL |
| [NYC Tree Census](https://data.cityofnewyork.us/) | Species, diameter for park trees | Public Domain |
| [Sketchfab](https://sketchfab.com/) | Photogrammetry scans (3 statues + Bethesda Fountain) | CC-BY |
| [Quaternius](https://quaternius.com/) | Tree 3D models | CC0 |
| [ambientCG](https://ambientcg.com/) / [Polyhaven](https://polyhaven.com/) | PBR textures, HDRI sky | CC0 |

## How to Contribute

This project grows with human attention.

**No coding required**: Map furniture in OSM (only ~10% of real lampposts/benches are mapped). Take photogrammetry scans of statues (4 of 106 scanned). Record field audio. Photograph landmarks and materials. Map rock outcrops (~170 named, 1 in OSM).

**Technical**: Species-accurate tree models (5 generic for 100+ species). Interior spaces. Ground detail. Performance profiling. Cross-platform support.

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## Philosophy

1. **Data-first**: Don't guess — get better data. Gaps are visible because gaps are real.
2. **Honest interpretation**: Render what data and AI perception together produce.
3. **Community-driven**: Humans contribute data, AI reinterprets it.
4. **Accessibility**: A walking simulator. No competition, no violence.

## Support the Project

Central Park Walk is built by Christopher Abbey and Claude, with no institutional backing.

[![Contribute on Open Collective](https://opencollective.com/central-park-walk/contribute/button)](https://opencollective.com/central-park-walk)

See [FUNDING.md](FUNDING.md) for details on how funds are used.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Engine | Godot 4.6.1 (Forward+, GDScript) |
| Data pipeline | Python (GDAL, numpy/scipy, Pillow) |
| 3D modeling | Blender 3.0.1 (headless scripts) |
| Rendering | 18 custom GLSL shaders, MultiMesh instancing, analytical GPU path rendering |

## License

Code: [MIT License](LICENSE)
Assets and creative content: [CC-BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)

## Credits

- **Christopher Abbey** — Project creator, technical lead
- **Claude (Anthropic)** — Co-creator: data interpretation, code, shaders, artistic decisions

Asset sources: [credits.txt](credits.txt)

Map data © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors. LiDAR data from NYS GIS Clearinghouse. Tree data from NYC OpenData.
