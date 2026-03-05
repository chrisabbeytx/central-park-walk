#!/usr/bin/env python3
"""
Download 3D models and upgraded terrain textures for Central Park Walk.

Assets:
  • Quaternius tree models (CC0) via Poly.pizza — maple, birch, pine, generic deciduous
  • Polyhaven shrub models (CC0) — shrub_02
  • OpenGameArt park furniture (CC0) — bench, lamppost, trash can
  • Polyhaven terrain textures (CC0) — grass, forest floor, dirt

All downloads are direct HTTP — no authentication required.
Re-running skips already-downloaded files.
"""

import io
import os
import sys
import time
import urllib.request
import zipfile

MODELS_DIR = "models"
TEXTURES_DIR = "textures"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _get(url: str, desc: str, timeout: int = 120) -> bytes:
    print(f"  GET {desc} …", flush=True)
    req = urllib.request.Request(url, headers={"User-Agent": "central-park-walk/1.0"})
    for attempt in range(1, 4):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                data = r.read()
            print(f"      {len(data) // 1024} KB")
            return data
        except Exception as exc:
            print(f"      attempt {attempt} failed: {exc}", file=sys.stderr)
            if attempt < 3:
                time.sleep(3 * attempt)
    print(f"  FAILED: {desc}", file=sys.stderr)
    return b""


def _save(path: str, data: bytes) -> None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


def _exists(*paths) -> bool:
    return all(os.path.exists(p) for p in paths)


# ---------------------------------------------------------------------------
# Quaternius tree models (CC0) — via Poly.pizza CDN
# All from "Ultimate Stylized Nature" pack by Quaternius
# Same author = cohesive art style across all trees
# ---------------------------------------------------------------------------

# (output_path, url, description)
TREE_MODELS = [
    # Deciduous — maple variants (multiple trees in one GLB)
    ("models/trees/maple.glb",
     "https://static.poly.pizza/cdfcf39f-f8c7-44a6-bb3f-82afe42fc141.glb",
     "Quaternius Maple Trees"),
    # Deciduous — birch variants
    ("models/trees/birch.glb",
     "https://static.poly.pizza/457b2397-4bfb-41c4-862d-82d1592b2a5f.glb",
     "Quaternius Birch Trees"),
    # Deciduous — generic (for oak/elm stand-ins with color variation)
    ("models/trees/deciduous.glb",
     "https://static.poly.pizza/53a83125-e16a-4024-b8f6-1e72679c7ddf.glb",
     "Quaternius Generic Deciduous Trees"),
    # Conifer — pine
    ("models/trees/pine.glb",
     "https://static.poly.pizza/42a2a958-040d-4ce3-bae5-2332c1282cb5.glb",
     "Quaternius Pine Trees"),
    # Dead trees — for variety
    ("models/trees/dead.glb",
     "https://static.poly.pizza/65539ff7-ff6b-4036-ad02-8233b6ce748f.glb",
     "Quaternius Dead Trees"),
]


def download_tree_models():
    print("\nDownloading Quaternius tree models (CC0) …")
    for out_path, url, desc in TREE_MODELS:
        if os.path.exists(out_path):
            print(f"  {desc} already downloaded, skipping.")
            continue
        data = _get(url, desc)
        if data:
            _save(out_path, data)
            print(f"    → {out_path}")
    print("Tree models done.")


# ---------------------------------------------------------------------------
# Quaternius Stylized Nature MegaKit (CC0) — vegetation models
# ---------------------------------------------------------------------------

NATURE_MEGAKIT_URL = "https://opengameart.org/sites/default/files/stylized_nature_megakitstandard.zip"
NATURE_MEGAKIT_MODELS = [
    "Bush_Common", "Bush_Common_Flowers",
    "Fern_1",
    "Flower_3_Group", "Flower_3_Single", "Flower_4_Group", "Flower_4_Single",
    "Grass_Common_Short", "Grass_Common_Tall", "Grass_Wispy_Short", "Grass_Wispy_Tall",
    "Clover_1", "Clover_2",
    "Plant_1", "Plant_1_Big", "Plant_7", "Plant_7_Big",
    "Mushroom_Common", "Mushroom_Laetiporus",
    "Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3",
]
NATURE_MEGAKIT_TEXTURES = [
    "Flowers.png", "Grass.png", "Leaves.png", "Leaves_NormalTree_C.png",
    "Leaves_TwistedTree_C.png", "Mushrooms.png", "Rocks_Diffuse.png",
]


def download_vegetation():
    out_dir = os.path.join(MODELS_DIR, "vegetation")
    # Check if already extracted
    marker = os.path.join(out_dir, "Bush_Common.gltf")
    if os.path.exists(marker):
        print("Vegetation models already downloaded, skipping.")
        return

    print("\nDownloading Quaternius Stylized Nature MegaKit (CC0) …")
    data = _get(NATURE_MEGAKIT_URL, "Stylized Nature MegaKit (104 MB)", timeout=300)
    if not data:
        return

    os.makedirs(out_dir, exist_ok=True)
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            names = z.namelist()
            extracted = 0
            for name in names:
                if not name.startswith("glTF/"):
                    continue
                basename = name[5:]
                if not basename:
                    continue
                stem = basename.rsplit(".", 1)[0]
                is_model = any(basename.startswith(m + ".") for m in NATURE_MEGAKIT_MODELS)
                is_texture = basename in NATURE_MEGAKIT_TEXTURES
                if is_model or is_texture:
                    dest = os.path.join(out_dir, basename)
                    with z.open(name) as src:
                        _save(dest, src.read())
                    extracted += 1
            print(f"  Extracted {extracted} files → {out_dir}/")
    except zipfile.BadZipFile:
        print("  ERROR: bad zip", file=sys.stderr)
    print("Vegetation models done.")


# ---------------------------------------------------------------------------
# Polyhaven shrub models (CC0) — multi-file glTF download
# ---------------------------------------------------------------------------

POLYHAVEN_MODELS = [
    # shrub_02: small flowering shrub, ~741KB geometry, reasonable for instancing
    ("models/shrubs/shrub_02", "shrub_02", "Polyhaven shrub_02"),
    ("models/shrubs/shrub_03", "shrub_03", "Polyhaven shrub_03"),
]

# Polyhaven glTF = .gltf + .bin + texture JPGs (NOT a single GLB)
PH_MODEL_BASE = "https://dl.polyhaven.org/file/ph-assets/Models"


def download_polyhaven_models():
    print("\nDownloading Polyhaven shrub models (CC0) …")
    for out_dir, asset, desc in POLYHAVEN_MODELS:
        gltf_path = os.path.join(out_dir, f"{asset}_1k.gltf")
        if os.path.exists(gltf_path):
            print(f"  {desc} already downloaded, skipping.")
            continue

        os.makedirs(out_dir, exist_ok=True)

        # Download .gltf descriptor
        url = f"{PH_MODEL_BASE}/gltf/1k/{asset}/{asset}_1k.gltf"
        data = _get(url, f"{desc} gltf")
        if data:
            _save(gltf_path, data)

        # Download .bin geometry (shared across resolutions, hosted under highest res)
        for res in ["4k", "8k"]:
            url = f"{PH_MODEL_BASE}/gltf/{res}/{asset}/{asset}.bin"
            data = _get(url, f"{desc} bin")
            if data:
                _save(os.path.join(out_dir, f"{asset}.bin"), data)
                break

        # Download 1K textures
        for suffix in ["diff", "nor_gl", "arm"]:
            url = f"{PH_MODEL_BASE}/jpg/1k/{asset}/{asset}_{suffix}_1k.jpg"
            data = _get(url, f"{desc} {suffix}")
            if data:
                _save(os.path.join(out_dir, f"{asset}_{suffix}_1k.jpg"), data)

        print(f"    → {out_dir}/")

    print("Polyhaven shrub models done.")


# ---------------------------------------------------------------------------
# OpenGameArt park furniture (CC0)
# ---------------------------------------------------------------------------

FURNITURE_PACKS = [
    # Park Furniture by loafbrr_1 — bench, lamp posts, tables, umbrellas (GLB)
    ("models/furniture/park_furniture.zip",
     "https://opengameart.org/sites/default/files/parkfurnitures.zip",
     "OpenGameArt Park Furniture (CC0)"),
    # Park Props Lowpoly — garbage can, bench, gazebo, bridge, fountain (FBX)
    ("models/furniture/park_props_lowpoly.zip",
     "https://opengameart.org/sites/default/files/Park_Lowpoly_FBX.zip",
     "OpenGameArt Park Props Lowpoly (CC0)"),
]


def download_furniture():
    print("\nDownloading park furniture models (CC0) …")
    for zip_path, url, desc in FURNITURE_PACKS:
        extract_dir = zip_path.replace(".zip", "")
        if os.path.isdir(extract_dir):
            print(f"  {desc} already downloaded, skipping.")
            continue

        data = _get(url, desc, timeout=300)
        if not data:
            continue

        os.makedirs(os.path.dirname(zip_path) or ".", exist_ok=True)
        _save(zip_path, data)

        # Extract
        try:
            with zipfile.ZipFile(io.BytesIO(data)) as z:
                os.makedirs(extract_dir, exist_ok=True)
                z.extractall(extract_dir)
                print(f"    Extracted {len(z.namelist())} files")
        except zipfile.BadZipFile:
            print(f"  ERROR: bad zip for {desc}", file=sys.stderr)
            continue

        # Clean up zip
        os.remove(zip_path)
        print(f"    → {extract_dir}/")

    print("Furniture models done.")


# ---------------------------------------------------------------------------
# Polyhaven terrain textures (CC0)
# ---------------------------------------------------------------------------

POLYHAVEN_TEXTURES = [
    # Forest floor for woodland areas (Ramble, North Woods)
    ("forrest_ground_01", [
        ("diff", "forrest_ground_01_Color.jpg"),
        ("nor_gl", "forrest_ground_01_NormalGL.jpg"),
        ("rough", "forrest_ground_01_Roughness.jpg"),
    ]),
    # Park dirt for worn areas and tree bases
    ("park_dirt", [
        ("diff", "park_dirt_Color.jpg"),
        ("nor_gl", "park_dirt_NormalGL.jpg"),
        ("rough", "park_dirt_Roughness.jpg"),
    ]),
]

PH_TEX_BASE = "https://dl.polyhaven.org/file/ph-assets/Textures/jpg/2k"


def download_polyhaven_textures():
    print("\nDownloading Polyhaven terrain textures (CC0) …")
    for asset_name, maps in POLYHAVEN_TEXTURES:
        targets = [os.path.join(TEXTURES_DIR, local) for _, local in maps]
        if _exists(*targets):
            print(f"  {asset_name} already downloaded, skipping.")
            continue

        print(f"  Downloading {asset_name} …")
        for suffix, local_name in maps:
            url = f"{PH_TEX_BASE}/{asset_name}/{asset_name}_{suffix}_2k.jpg"
            data = _get(url, f"{asset_name} {suffix}")
            if data:
                out_path = os.path.join(TEXTURES_DIR, local_name)
                _save(out_path, data)
                print(f"    → {out_path}")

    print("Polyhaven textures done.")


# ---------------------------------------------------------------------------
# Credits file
# ---------------------------------------------------------------------------

def write_credits():
    credits_path = "credits.txt"
    print(f"\nWriting {credits_path} …")
    content = """\
=============================================================================
Central Park Walk — Asset Credits & Licenses
=============================================================================

All third-party assets used in this project are free and openly licensed.

-----------------------------------------------------------------------------
3D Tree Models — Quaternius (CC0 1.0)
-----------------------------------------------------------------------------

"Ultimate Stylized Nature" pack
  Author: Quaternius (https://quaternius.com)
  Source: https://quaternius.com/packs/ultimatestylizednature.html
  License: CC0 1.0 (Public Domain)
  Models used: Maple Trees, Birch Trees, Generic Deciduous, Pine Trees,
               Dead Trees

-----------------------------------------------------------------------------
3D Vegetation — Quaternius Stylized Nature MegaKit (CC0 1.0)
-----------------------------------------------------------------------------

"Stylized Nature MegaKit" — bushes, ferns, flowers, grass, clover, mushrooms, rocks
  Author: Quaternius (https://quaternius.com)
  Source: https://quaternius.com/packs/stylizednaturemegakit.html
  Also: https://opengameart.org/content/stylized-nature-megakit
  License: CC0 1.0 (Public Domain)

-----------------------------------------------------------------------------
3D Shrub Models — Polyhaven (CC0 1.0)
-----------------------------------------------------------------------------

"shrub_02" — https://polyhaven.com/a/shrub_02
"shrub_03" — https://polyhaven.com/a/shrub_03
License: CC0 1.0 (Public Domain)

-----------------------------------------------------------------------------
3D Park Furniture — OpenGameArt (CC0 1.0)
-----------------------------------------------------------------------------

"Park Furniture" by loafbrr_1
  URL: https://opengameart.org/content/park-furniture
  License: CC0 1.0 (Public Domain)

"Park Props Lowpoly"
  URL: https://opengameart.org/content/park-props-lowpoly
  License: CC0 1.0 (Public Domain)

-----------------------------------------------------------------------------
Terrain Textures — Polyhaven (CC0 1.0)
-----------------------------------------------------------------------------

"forrest_ground_01" — https://polyhaven.com/a/forrest_ground_01
"park_dirt" — https://polyhaven.com/a/park_dirt
License: CC0 1.0 (Public Domain)

-----------------------------------------------------------------------------
Existing Textures — ambientCG (CC0 1.0)
-----------------------------------------------------------------------------

Grass004, Ground037, Asphalt012, Concrete034, PavingStones130, Gravel021,
WoodFloor041, Bark007, LeafSet003, LeafSet009, Facade011, Bricks031,
Bricks059 — all from https://ambientcg.com/

-----------------------------------------------------------------------------
Sky HDRI — Polyhaven (CC0 1.0)
-----------------------------------------------------------------------------

"kloppenheim_06_puresky" — https://polyhaven.com/a/kloppenheim_06_puresky

-----------------------------------------------------------------------------
Terrain Elevation — Terrarium (Public Domain)
-----------------------------------------------------------------------------

GEBCO elevation data via Terrarium tiles.

-----------------------------------------------------------------------------
Map Data — OpenStreetMap (ODbL)
-----------------------------------------------------------------------------

OpenStreetMap contributors — https://www.openstreetmap.org/copyright
License: Open Data Commons Open Database License (ODbL)

=============================================================================
"""
    with open(credits_path, "w") as f:
        f.write(content)
    print(f"  → {credits_path}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    os.chdir(os.path.dirname(os.path.abspath(__file__)))

    # Create directory structure
    for d in ["models/trees", "models/shrubs", "models/furniture", "models/vegetation"]:
        os.makedirs(d, exist_ok=True)

    write_credits()
    download_polyhaven_textures()
    download_tree_models()
    download_vegetation()
    download_polyhaven_models()
    download_furniture()
    print("\nAll done.")
