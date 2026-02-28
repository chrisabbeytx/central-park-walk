#!/usr/bin/env python3
"""
Convert central_park_osm.json → park_data.json

Projects OSM lat/lon into local metres relative to the centre of Central Park,
using the same coordinate convention as the Godot scene:

    origin  = (REF_LAT, REF_LON)  ≈ centre of Central Park
    +X axis = East
    −Z axis = North   (Godot's default forward is −Z)

Output park_data.json contains:
    ref_lat / ref_lon        – projection origin
    metres_per_deg_lat/lon   – scale factors (for inverse projection in Godot)
    paths[]                  – list of {highway, points[[x,z], …]}
    boundary[]               – [[x,z], …] ordered outer ring of the park
"""

import json
import math
import os
import sys
from collections import defaultdict

# ---------------------------------------------------------------------------
# Projection constants  (tuned for ~40.78 ° N)
# ---------------------------------------------------------------------------
REF_LAT            = 40.7829
REF_LON            = -73.9654
METRES_PER_DEG_LAT = 110_540.0
METRES_PER_DEG_LON = 111_320.0 * math.cos(math.radians(REF_LAT))   # ≈ 84 264 m/°

# ---------------------------------------------------------------------------
# Visual widths per highway tag (metres) – used by park_loader.gd
# ---------------------------------------------------------------------------
HIGHWAY_WIDTH = {
    "pedestrian": 6.0,
    "footway":    3.0,
    "cycleway":   3.5,
    "path":       2.5,
    "steps":      2.5,
    "track":      3.0,
}


def project(lat: float, lon: float) -> tuple[float, float]:
    """Return (x, z) in metres, origin = REF_LAT / REF_LON."""
    x =  (lon - REF_LON) * METRES_PER_DEG_LON
    z = -(lat - REF_LAT) * METRES_PER_DEG_LAT
    return (round(x, 2), round(z, 2))


# ---------------------------------------------------------------------------
# Boundary ring assembly
# ---------------------------------------------------------------------------
def assemble_ring(outer_way_ids: list, ways_nodes: dict) -> list:
    """
    Join a set of outer-boundary way IDs end-to-end into a single ordered
    list of node IDs.  Uses a greedy walk: at each step find a way whose
    start-node matches the current tail of the ring.
    """
    # endpoint → [(way_id, nodes_in_forward_order), …]
    endpoint_map: dict = defaultdict(list)
    for wid in outer_way_ids:
        nodes = ways_nodes.get(wid)
        if not nodes:
            continue
        endpoint_map[nodes[0]].append((wid, nodes))
        endpoint_map[nodes[-1]].append((wid, nodes[::-1]))  # reversed start

    first_id = next((w for w in outer_way_ids if w in ways_nodes), None)
    if first_id is None:
        return []

    ring = list(ways_nodes[first_id])
    used = {first_id}

    for _ in range(len(outer_way_ids) + 2):
        tail     = ring[-1]
        advanced = False
        for wid, nodes in endpoint_map.get(tail, []):
            if wid not in used:
                ring.extend(nodes[1:])   # nodes[0] == tail, already appended
                used.add(wid)
                advanced = True
                break
        if not advanced:
            break

    return ring


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> None:
    src = "central_park_osm.json"
    if not os.path.exists(src):
        print(f"ERROR: {src} not found – run download_osm.py first.", file=sys.stderr)
        sys.exit(1)

    with open(src) as fh:
        raw = json.load(fh)

    elements = raw.get("elements", [])

    # Index raw data
    nodes_ll:   dict[int, tuple]  = {}   # id → (lat, lon)
    ways_tags:  dict[int, dict]   = {}   # id → tag dict
    ways_nodes: dict[int, list]   = {}   # id → [node_id, …]
    relations:  list              = []

    for e in elements:
        t = e["type"]
        if t == "node" and "lat" in e:
            nodes_ll[e["id"]] = (e["lat"], e["lon"])
        elif t == "way":
            ways_tags[e["id"]]  = e.get("tags", {})
            ways_nodes[e["id"]] = e.get("nodes", [])
        elif t == "relation":
            relations.append(e)

    # -------------------------------------------------------------------
    # Paths
    # -------------------------------------------------------------------
    paths_out   = []
    skipped_hw  = 0
    skipped_pts = 0

    for wid, tags in ways_tags.items():
        hw = tags.get("highway")
        if hw not in HIGHWAY_WIDTH:
            skipped_hw += 1
            continue

        pts = []
        for nid in ways_nodes.get(wid, []):
            if nid in nodes_ll:
                pts.append(list(project(*nodes_ll[nid])))

        if len(pts) < 2:
            skipped_pts += 1
            continue

        paths_out.append({"highway": hw, "points": pts})

    # -------------------------------------------------------------------
    # Boundary
    # -------------------------------------------------------------------
    boundary_pts: list = []
    cp_rel = None

    for rel in relations:
        if rel.get("tags", {}).get("name") == "Central Park":
            cp_rel = rel
            break

    if cp_rel is None and relations:
        cp_rel = relations[0]
        name = cp_rel.get("tags", {}).get("name", "unnamed")
        print(f"  No 'Central Park' relation found; using '{name}' as boundary.")

    if cp_rel:
        members = cp_rel.get("members", [])

        # Prefer explicit "outer" role; fall back to any way member
        outer_ids = [m["ref"] for m in members
                     if m["type"] == "way" and m.get("role") == "outer"]
        if not outer_ids:
            outer_ids = [m["ref"] for m in members if m["type"] == "way"]

        ring_node_ids = assemble_ring(outer_ids, ways_nodes)
        for nid in ring_node_ids:
            if nid in nodes_ll:
                boundary_pts.append(list(project(*nodes_ll[nid])))

        # Remove duplicate close-ring point (first == last)
        if boundary_pts and boundary_pts[0] == boundary_pts[-1]:
            boundary_pts.pop()
    else:
        print("  WARNING: No boundary relation found – park walls will be skipped.")

    # -------------------------------------------------------------------
    # Write output
    # -------------------------------------------------------------------
    out = {
        "ref_lat":            REF_LAT,
        "ref_lon":            REF_LON,
        "metres_per_deg_lat": METRES_PER_DEG_LAT,
        "metres_per_deg_lon": round(METRES_PER_DEG_LON, 2),
        "paths":              paths_out,
        "boundary":           boundary_pts,
    }

    with open("park_data.json", "w") as fh:
        json.dump(out, fh, separators=(",", ":"))

    size_kb = os.path.getsize("park_data.json") / 1024

    print(f"\nPaths written:    {len(paths_out)}"
          f"  (skipped {skipped_pts} with missing nodes)")
    print(f"Boundary points:  {len(boundary_pts)}")
    print(f"\nSaved → park_data.json  ({size_kb:.1f} KB)")
    print("\nNext steps:")
    print("  1. Copy park_data.json into your Godot project root (it's already there).")
    print("  2. Open Godot and press F5 to run.")


if __name__ == "__main__":
    main()
