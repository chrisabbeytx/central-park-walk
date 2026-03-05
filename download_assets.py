#!/usr/bin/env python3
"""
Download free CC0 textures and sky for Central Park Walk.

  • Grass PBR (albedo / normal / roughness) from ambientCG
  • Sky equirectangular HDR from Poly Haven

Run once; re-running skips already-downloaded files.
"""

import io
import os
import sys
import time
import urllib.request
import zipfile

OUT = "textures"
os.makedirs(OUT, exist_ok=True)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _get(url: str, desc: str, timeout: int = 60) -> bytes:
    print(f"  GET {desc} …", flush=True)
    req = urllib.request.Request(url, headers={"User-Agent": "central-park-walk/1.0"})
    for attempt in range(1, 4):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                data = r.read()
            print(f"      {len(data)//1024} KB")
            return data
        except Exception as exc:
            print(f"      attempt {attempt} failed: {exc}", file=sys.stderr)
            if attempt < 3:
                time.sleep(3 * attempt)
    print(f"  FAILED: {desc}", file=sys.stderr)
    return b""


def _save(path: str, data: bytes) -> None:
    with open(path, "wb") as f:
        f.write(data)


def _exists(*paths) -> bool:
    return all(os.path.exists(p) for p in paths)


# ---------------------------------------------------------------------------
# Grass PBR textures (ambientCG, CC0)
# ---------------------------------------------------------------------------

GRASS_ID   = "Grass004_2K-JPG"
GRASS_URL  = f"https://ambientcg.com/get?file={GRASS_ID}.zip"
GRASS_FILES = {
    f"{GRASS_ID}_Color.jpg":    f"{OUT}/grass_albedo.jpg",
    f"{GRASS_ID}_NormalGL.jpg": f"{OUT}/grass_normal.jpg",
    f"{GRASS_ID}_Roughness.jpg":f"{OUT}/grass_rough.jpg",
}

def download_grass():
    targets = list(GRASS_FILES.values())
    if _exists(*targets):
        print("Grass textures already downloaded, skipping.")
        return
    print("Downloading grass PBR from ambientCG …")
    raw = _get(GRASS_URL, GRASS_ID + ".zip")
    if not raw:
        return
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        for src, dst in GRASS_FILES.items():
            if src in z.namelist():
                with z.open(src) as f:
                    _save(dst, f.read())
                print(f"  → {dst}")
            else:
                print(f"  WARNING: {src} not found in zip", file=sys.stderr)
    print("Grass done.")


# ---------------------------------------------------------------------------
# ambientCG CC0 texture packs (2K upgrades + new sets)
# ---------------------------------------------------------------------------

# Each entry: (texture_id, suffixes_to_extract)
# Files land at textures/{ID}_{suffix}
AMBIENTCG_PACKS = [
    # Meadow grass blend
    ("Ground037_2K-JPG", ["Color.jpg", "NormalGL.jpg", "Roughness.jpg"]),
    # Oak leaves (broader, rounder)
    ("LeafSet003_2K-JPG", ["Color.jpg", "NormalGL.jpg", "Roughness.jpg", "Opacity.jpg"]),
    # Elm leaves (smaller, denser)
    ("LeafSet009_2K-JPG", ["Color.jpg", "NormalGL.jpg", "Roughness.jpg", "Opacity.jpg"]),
    # 2K upgrades for path textures (replace 1K versions)
    ("Asphalt012_2K-JPG", ["Color.jpg", "NormalGL.jpg", "Roughness.jpg"]),
    ("Concrete034_2K-JPG", ["Color.jpg", "NormalGL.jpg", "Roughness.jpg"]),
    ("PavingStones130_2K-JPG", ["Color.jpg", "NormalGL.jpg", "Roughness.jpg"]),
    ("Gravel021_2K-JPG", ["Color.jpg", "NormalGL.jpg", "Roughness.jpg"]),
    ("WoodFloor041_2K-JPG", ["Color.jpg", "NormalGL.jpg", "Roughness.jpg"]),
    # 2K bark upgrade
    ("Bark007_2K-JPG", ["Color.jpg", "NormalGL.jpg", "Roughness.jpg", "AmbientOcclusion.jpg"]),
    # Building facade textures
    ("Facade011_2K-JPG", ["Color.jpg", "NormalGL.jpg", "Roughness.jpg"]),
    ("Bricks059_2K-JPG", ["Color.jpg", "NormalGL.jpg", "Roughness.jpg"]),
    ("Bricks031_2K-JPG", ["Color.jpg", "NormalGL.jpg", "Roughness.jpg"]),
    # Additional leaf sets for vegetation
    ("LeafSet005_2K-JPG", ["Color.jpg", "NormalGL.jpg", "Roughness.jpg", "Opacity.jpg"]),
    ("LeafSet019_2K-JPG", ["Color.jpg", "NormalGL.jpg", "Roughness.jpg", "Opacity.jpg"]),
]

def download_ambientcg_packs():
    for tex_id, suffixes in AMBIENTCG_PACKS:
        targets = [f"{OUT}/{tex_id}_{s}" for s in suffixes]
        if _exists(*targets):
            print(f"{tex_id} already downloaded, skipping.")
            continue
        print(f"Downloading {tex_id} from ambientCG …")
        url = f"https://ambientcg.com/get?file={tex_id}.zip"
        raw = _get(url, tex_id + ".zip", timeout=120)
        if not raw:
            continue
        try:
            with zipfile.ZipFile(io.BytesIO(raw)) as z:
                names = z.namelist()
                for suffix in suffixes:
                    src = f"{tex_id}_{suffix}"
                    dst = f"{OUT}/{src}"
                    if src in names:
                        with z.open(src) as f:
                            _save(dst, f.read())
                        print(f"  → {dst}")
                    else:
                        print(f"  WARNING: {src} not found in zip", file=sys.stderr)
        except zipfile.BadZipFile:
            print(f"  ERROR: bad zip for {tex_id}", file=sys.stderr)
        print(f"{tex_id} done.")


# ---------------------------------------------------------------------------
# Sky HDRI (Poly Haven, CC0)
# ---------------------------------------------------------------------------

SKY_OUT  = f"{OUT}/sky.hdr"
SKY_BASE = "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k"
SKY_CANDIDATES = [
    "kloppenheim_06_puresky_1k.hdr",   # pure sky, no horizon clutter
    "kloppenheim_06_1k.hdr",           # same location, includes horizon
    "autumn_field_puresky_1k.hdr",     # blue sky + light clouds
]

def download_sky():
    if os.path.exists(SKY_OUT):
        print("Sky HDR already downloaded, skipping.")
        return
    print("Downloading sky HDR from Poly Haven …")
    for fname in SKY_CANDIDATES:
        url  = f"{SKY_BASE}/{fname}"
        data = _get(url, fname, timeout=90)
        if data:
            _save(SKY_OUT, data)
            print(f"  → {SKY_OUT}  (source: {fname})")
            return
    print("  WARNING: all sky candidates failed – will use procedural sky", file=sys.stderr)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    download_grass()
    print()
    download_sky()
    print()
    download_ambientcg_packs()
    print("\nDone.")
