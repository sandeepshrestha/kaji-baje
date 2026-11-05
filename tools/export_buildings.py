"""Export the UI8 building .blend files to .glb for Godot.

Each building is re-centred so its footprint sits on the origin with the
base at y = 0, and lights, cameras and render-only backdrops are dropped.

Usage (Blender runs the script, the paths come after --):
  /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/export_buildings.py -- \
      source_art/ui8/buildings assets/buildings
"""
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SRC = os.path.abspath(argv[0] if argv else "source_art/ui8/buildings")
OUT = os.path.abspath(argv[1] if len(argv) > 1 else "assets/buildings")

BACKDROP_SIZE = 9.0
MAX_POLYS_PER_OBJECT = 1500


def slug(name: str) -> str:
    # "19.house.blend" -> "house_19", so the two houses do not collide.
    num, _, rest = os.path.splitext(name)[0].partition(".")
    words = "_".join(rest.strip().lower().replace(".", " ").split())
    return "%s_%s" % (words, num.strip()) if num.strip().isdigit() else "_".join(name.lower().split())


def world_bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    return lo, hi


def export(path: str) -> None:
    bpy.ops.wm.open_mainfile(filepath=path)
    for o in list(bpy.data.objects):
        if o.type in {"LIGHT", "CAMERA"} or o.hide_render:
            bpy.data.objects.remove(o, do_unlink=True)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        print("skip (no meshes):", path)
        return
    # The buildings are 4-7 units across. A studio backdrop or render floor is
    # far bigger than that.
    for o in meshes:
        if max(o.dimensions) > BACKDROP_SIZE:
            print("  drop backdrop", o.name, tuple(round(d, 1) for d in o.dimensions))
            bpy.data.objects.remove(o, do_unlink=True)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    # Background props do not need render-grade detail. Count after the
    # existing modifiers (subdivision is where most of the weight comes from).
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for o in meshes:
        polys = len(o.evaluated_get(depsgraph).data.polygons)
        if polys > MAX_POLYS_PER_OBJECT:
            mod = o.modifiers.new("decimate", "DECIMATE")
            mod.ratio = MAX_POLYS_PER_OBJECT / polys
    lo, hi = world_bounds(meshes)
    shift = Vector(((lo.x + hi.x) * -0.5, (lo.y + hi.y) * -0.5, -lo.z))
    for o in bpy.data.objects:
        if o.parent is None:
            o.location += shift
    out = os.path.join(OUT, slug(os.path.basename(path)) + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_visible=False, export_apply=True,
                              export_lights=False, export_cameras=False)
    lo, hi = world_bounds(meshes)
    print("exported %s  size %.2f x %.2f x %.2f" % (out, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z))


os.makedirs(OUT, exist_ok=True)
for f in sorted(os.listdir(SRC)):
    if f.endswith(".blend"):
        export(os.path.join(SRC, f))
