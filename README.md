## Central Park Walk

*An AI-human collaboration to reconstruct Central Park in 3D from freely available public data.*

Central Park Walk is a real-time 3D walking simulation of all 843 acres of New York's Central Park, built entirely from freely available public data — LiDAR surveys, OpenStreetMap, the NYC Tree Census, building footprints — and interpreted by Claude (Anthropic). No objectives, no score. Just a place.

Every tree has a real measured height. Every path follows its real-world geometry. Every building has its actual footprint and construction year. The terrain is accurate to one foot. The data has gaps, and we leave them visible — gaps tell us what humans haven't yet measured or mapped.

![Autumn Dusk — Central Park West Skyline](screenshots/cpw_skyline_autumn_dusk.png)
*Autumn dusk. Per-species fall colors driven by phenology data. 6,557 buildings from NYC Building Footprints.*

![Rain — Conservatory Water](screenshots/conservatory_rain_afternoon.png)
*Rain on the Conservatory Water. Real-time weather with surface ripples, fog, and city silhouette.*

![Winter Snow — Sheep Meadow](screenshots/sheep_meadow_winter_noon.png)
*Sheep Meadow under snow. Full day/night cycle with seasonal atmosphere, frost, and puddles.*

![Winter Morning — North Woods](screenshots/north_woods_snow_morning.png)
*The North Woods in snow. 8K LiDAR terrain at 0.61m resolution with ~9,300 trees from census + woodland scatter.*

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
| Terrain | 8192×8192 mesh (14M verts) | NYC LiDAR 2017 (1ft resolution, 0.61m cells) |
| Trees | ~9,300 | NYC Tree Census + OSM + woodland scatter in 12 ecological zones. 17 custom Blender models: 15 species (oak, elm, maple, birch, cherry, ginkgo, honeylocust, linden, london plane, callery pear, pine, willow, magnolia) + generic deciduous + standing dead snag. Per-species summer leaf colors + fall colors + phenology. Cherry blossom + callery pear + magnolia spring bloom. 5 species-specific bark textures (birch lenticels, london plane mottled exfoliation, pine scaled plates). Frost sparkle, morning dew |
| Water | 23 bodies + 10 streams | OpenStreetMap polygons. Dawn/dusk mist (8 localized fog volumes) |
| Buildings | 6,557 | NYC Building Footprints + LiDAR heights. 5 facade material types (limestone, brick, concrete, glass/granite, cream) with per-building hash variation, floor-height-accurate windows, cornice bands, awnings, grime weathering |
| Furniture | 1,022+ | Lampposts (201), benches (610), trash cans (166), fountains (19), flagpoles (18), water towers (45), iron fences (207 segments) |
| Statues | 106 positions | 4 photogrammetry scans + Cleopatra's Needle model + 61 stone pedestals, rest labeled |
| Sports fields | 147 | Tennis, basketball, baseball, soccer, handball |
| Grass | ~762K tiles | 10 CPC-data-driven types with narrow 3D blades (8–15mm), wildflowers, clover. Mowed=1-segment spikes, woodland=2-segment curves, meadow=3-segment arches. Mowing stripes on formal lawns, path-edge wear (shorter/browner near paths), multi-scale color variation (5 scales from field-level drainage to per-clump species mix), dandelion + clover weeds in maintained lawns, winter dormancy. Soft tile-edge fade (dithered alpha), Lambertian shading (no specular), distance darkening |
| Seasons | 4 | Per-species phenology, cherry/callery pear/magnolia spring blossoms, spring cherry blossom petal drift, autumn falling leaf particles, leaf scatter, water color, atmosphere |
| Weather | 5 modes | Rain, thunderstorm, snow, fog, clear — with surface response |
| Day/night | Full cycle | 48-lamp pool (45m range, 110 energy), lit windows, NYC warm ambient light pollution, moon, atmospheric haze, aerial perspective (distance desaturation + blue shift) |
| Color grading | Cinematic | Split-tone (teal shadows/amber highlights), film grain, vignette, seasonal + TOD color shifts, S-curve contrast, distance-based grass darkening |

## Data Sources

All data is freely available. No paid APIs. No API keys.

| Source | What It Provides | License |
|--------|-----------------|---------|
| [NYC LiDAR (2017)](https://gis.ny.gov/elevation/lidar-coverage) | 1ft terrain elevation | Public Domain |
| [NYC 6M Trees](https://data.cityofnewyork.us/Environment/2015-Street-Tree-Census-Tree-Data/uvpi-gqnh) | Tree positions, heights, crown areas | Public Domain |
| [OpenStreetMap](https://www.openstreetmap.org/) | Paths, water, buildings, bridges, furniture | ODbL |
| [NYC Tree Census](https://data.cityofnewyork.us/) | Species, diameter for park trees | Public Domain |
| [Sketchfab](https://sketchfab.com/) | Photogrammetry scans (3 statues + Bethesda Fountain) | CC-BY |
| Custom Blender scripts | All 17 tree models, furniture, Cleopatra's Needle | Original (MIT) |
| [ambientCG](https://ambientcg.com/) / [Polyhaven](https://polyhaven.com/) | PBR textures, HDRI sky | CC0 |

## How to Contribute

This project grows with human attention.

**No coding required**: Map furniture in OSM (only ~10% of real lampposts/benches are mapped). Take photogrammetry scans of statues (4 of 106 scanned). Record field audio. Photograph landmarks and materials. Map rock outcrops (~170 named, 1 in OSM).

**Technical**: 17 custom Blender tree models (all species-specific). Interior spaces. Performance profiling. Cross-platform support.

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
| Rendering | 20 custom GLSL shaders (terrain, water, water mist, stream, facade, stone, tree leaf/bark, grass, hedge, wood, cast iron, roof, sky, weather), MultiMesh instancing, 8K prebaked terrain mesh, world atlas path rendering |

## License

Code: [MIT License](LICENSE)
Assets and creative content: [CC-BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)

## Credits

- **Christopher Abbey** — Project creator, technical lead
- **Claude (Anthropic)** — Co-creator: data interpretation, code, shaders, artistic decisions

Asset sources: [credits.txt](credits.txt)

Map data © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors. LiDAR data from NYS GIS Clearinghouse. Tree data from NYC OpenData.
