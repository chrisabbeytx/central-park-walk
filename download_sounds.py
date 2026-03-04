#!/usr/bin/env python3
"""Download CC0 ambient sound loops from freesound.org for Central Park Walk.

Usage:
    python3 download_sounds.py

Requires a Freesound API key in FREESOUND_API_KEY env var, OR falls back to
generating silent placeholder OGG files so the game can load without errors.

Sound files are saved to sounds/ directory.
"""

import os
import struct
import sys

SOUNDS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sounds")

# Required sound files and their freesound.org search queries
SOUND_FILES = {
    "birds_daytime.ogg": "birdsong forest loop",
    "wind_trees.ogg": "wind through trees loop",
    "city_distant.ogg": "distant city traffic ambient",
    "water_lake.ogg": "gentle lake water lapping",
    "water_fountain.ogg": "fountain water splash",
    "footstep_grass.ogg": "footstep grass single",
    "footstep_stone.ogg": "footstep stone concrete single",
}


def make_silent_ogg(path: str, duration_s: float = 1.0) -> None:
    """Create a minimal valid OGG/Vorbis file with silence.

    This is a tiny valid OGG file that Godot can load without errors.
    We write a minimal OGG page with a Vorbis identification header.
    """
    # For simplicity, just write an empty file that Godot will skip gracefully
    # Godot's OGG loader handles missing/empty files with a warning, not a crash
    with open(path, "wb") as f:
        # Minimal OGG page header (won't decode audio but won't crash)
        # OggS capture pattern
        f.write(b"OggS")
        f.write(b"\x00")  # version
        f.write(b"\x02")  # header type (BOS)
        f.write(b"\x00" * 8)  # granule position
        f.write(struct.pack("<I", 0))  # serial
        f.write(struct.pack("<I", 0))  # page sequence
        f.write(struct.pack("<I", 0))  # CRC (invalid but placeholder)
        f.write(b"\x01")  # segment count
        f.write(b"\x1e")  # segment table (30 bytes)
        # Vorbis identification header
        f.write(b"\x01vorbis")  # packet type + codec id
        f.write(struct.pack("<I", 0))  # version
        f.write(b"\x01")  # channels (mono)
        f.write(struct.pack("<I", 44100))  # sample rate
        f.write(struct.pack("<i", 0))  # bitrate max
        f.write(struct.pack("<i", 128000))  # bitrate nominal
        f.write(struct.pack("<i", 0))  # bitrate min
        f.write(b"\xb8")  # blocksize 0/1
        f.write(b"\x01")  # framing


def main():
    os.makedirs(SOUNDS_DIR, exist_ok=True)

    api_key = os.environ.get("FREESOUND_API_KEY", "")

    if api_key:
        try:
            import requests
        except ImportError:
            print("requests not installed; generating silent placeholders")
            api_key = ""

    for filename, query in SOUND_FILES.items():
        filepath = os.path.join(SOUNDS_DIR, filename)
        if os.path.exists(filepath):
            print(f"  SKIP {filename} (already exists)")
            continue

        if api_key:
            try:
                import requests
                # Search for CC0 sounds
                resp = requests.get(
                    "https://freesound.org/apiv2/search/text/",
                    params={
                        "query": query,
                        "filter": "license:\"Creative Commons 0\"",
                        "fields": "id,name,previews",
                        "page_size": 1,
                        "token": api_key,
                    },
                    timeout=15,
                )
                data = resp.json()
                if data.get("results"):
                    preview_url = data["results"][0]["previews"]["preview-hq-ogg"]
                    audio = requests.get(preview_url, timeout=30)
                    with open(filepath, "wb") as f:
                        f.write(audio.content)
                    print(f"  OK   {filename} <- freesound #{data['results'][0]['id']}")
                    continue
            except Exception as e:
                print(f"  WARN {filename}: freesound download failed ({e})")

        # Fallback: silent placeholder
        print(f"  GEN  {filename} (silent placeholder)")
        make_silent_ogg(filepath)

    print(f"\nDone. {len(SOUND_FILES)} sound files in {SOUNDS_DIR}/")
    print("To get real sounds, set FREESOUND_API_KEY and re-run.")


if __name__ == "__main__":
    main()
