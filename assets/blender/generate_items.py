"""Generate four low-poly item models for the Godot project and export them as GLB.

Run with:
    bforartists.exe -b --python "C:\\Users\\PC\\Documents\\project-1\\assets\\blender\\generate_items.py"

All geometry uses built-in Blender/bforartists primitives. Coordinates are authored
Z-up (Blender) and exported Y-up (glTF/Godot), so "height" below is Blender Z.
"""

import math
import os

import bpy
from mathutils import Vector

OUT_DIR = r"C:\Users\PC\Documents\project-1\assets\models"

# --------------------------------------------------------------------------- #
# Materials
# --------------------------------------------------------------------------- #

MATS = {}


def make_material(name, rgba, metallic=0.0, roughness=0.5,
                  emission=None, emission_strength=0.0):
    """Create (or refresh) a node-based material with a visible base color."""
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = tuple(rgba)

    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    if bsdf is None:
        for node in nodes:
            if node.type == "BSDF_PRINCIPLED":
                bsdf = node
                break
    if bsdf is None:
        return mat

    def set_input(keys, value):
        for key in keys:
            if key in bsdf.inputs:
                bsdf.inputs[key].default_value = value
                return True
        return False

    set_input(("Base Color",), tuple(rgba))
    set_input(("Metallic",), float(metallic))
    set_input(("Roughness",), float(roughness))
    if emission is not None:
        set_input(("Emission Color", "Emission"), (tuple(emission) + (1.0,))[:4])
        set_input(("Emission Strength",), float(emission_strength))
    return mat


def init_materials():
    MATS["dark"] = make_material(
        "MAT_DarkSlateMetal", (0.105, 0.130, 0.165, 1.0), 0.75, 0.42)
    MATS["edge"] = make_material(
        "MAT_MetalEdge", (0.205, 0.245, 0.290, 1.0), 0.65, 0.48)
    MATS["cyan"] = make_material(
        "MAT_CyanGlow", (0.020, 0.720, 0.930, 1.0), 0.15, 0.30,
        emission=(0.02, 0.75, 0.95), emission_strength=1.6)
    MATS["cyan_bright"] = make_material(
        "MAT_CyanHot", (0.350, 0.950, 1.000, 1.0), 0.0, 0.25,
        emission=(0.35, 0.95, 1.0), emission_strength=3.0)
    MATS["orange"] = make_material(
        "MAT_OrangeWarning", (0.950, 0.360, 0.070, 1.0), 0.25, 0.45,
        emission=(0.9, 0.3, 0.04), emission_strength=0.25)
    MATS["wood"] = make_material(
        "MAT_WarmWood", (0.400, 0.255, 0.135, 1.0), 0.0, 0.85)
    MATS["rubber"] = make_material(
        "MAT_DarkRubber", (0.045, 0.055, 0.070, 1.0), 0.0, 0.90)
    MATS["elastic"] = make_material(
        "MAT_Elastic", (0.055, 0.360, 0.450, 1.0), 0.0, 0.70)


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #

def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.object.select_all(action="DESELECT")


def finish(obj, name, material):
    obj.name = name
    obj.data.name = name + "Mesh"
    if material is not None:
        obj.data.materials.clear()
        obj.data.materials.append(material)
    return obj


def cube(name, location, scale, material, bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=2.0, location=location)
    obj = bpy.context.object
    obj.scale = scale
    if bevel:
        apply_bevel(obj, bevel)
    return finish(obj, name, material)


def cylinder(name, location, radius, depth, material, vertices=12,
             radius2=None, rotation=None):
    if radius2 is None:
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=vertices, radius=radius, depth=depth, location=location)
    else:
        bpy.ops.mesh.primitive_cone_add(
            vertices=vertices, radius1=radius, radius2=radius2,
            depth=depth, location=location)
    obj = bpy.context.object
    if rotation is not None:
        obj.rotation_mode = "QUATERNION"
        obj.rotation_quaternion = rotation
    return finish(obj, name, material)


def torus(name, location, major_radius, minor_radius, material,
          major_segments=24, minor_segments=6):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius, minor_radius=minor_radius,
        major_segments=major_segments, minor_segments=minor_segments,
        location=location)
    return finish(bpy.context.object, name, material)


def apply_bevel(obj, width, segments=2):
    """Apply a bevel modifier immediately (keeps geometry low-poly)."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new(name="BevelEdges", type="BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.select_set(False)


def radial_cylinder(name, angle, radius_from_center, z, length,
                    thickness, material, vertices=6):
    """A short cylinder lying horizontally along a radial direction."""
    direction = Vector((math.cos(angle), math.sin(angle), 0.0))
    quat = Vector((0.0, 0.0, 1.0)).rotation_difference(direction)
    loc = (radius_from_center * direction.x,
           radius_from_center * direction.y, z)
    return cylinder(name, loc, thickness, length, material,
                    vertices=vertices, rotation=quat)


def apply_all_transforms():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.select_all(action="DESELECT")


def export_glb(filename):
    """Select every mesh, print names, bake transforms, and export one GLB."""
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs:
        obj.select_set(True)
    if objs:
        bpy.context.view_layer.objects.active = objs[0]

    print("OBJECTS_IN_%s: %s" % (
        filename.upper().replace(".", "_"),
        ", ".join(sorted(o.name for o in objs))))

    path = os.path.join(OUT_DIR, filename)
    props = {p.identifier for p in bpy.ops.export_scene.gltf.get_rna_type().properties}
    kwargs = {
        "filepath": path,
        "export_format": "GLB",
        "use_selection": True,
        "export_apply": True,
        "export_yup": True,
        "export_cameras": False,
        "export_lights": False,
    }
    if "export_materials" in props:
        kwargs["export_materials"] = "EXPORT"
    kwargs = {key: value for key, value in kwargs.items() if key in props}
    bpy.ops.export_scene.gltf(**kwargs)
    size = os.path.getsize(path) if os.path.exists(path) else -1
    print("EXPORTED: %s (%d bytes)" % (path, size))


def build_and_export(filename, builder):
    clear_scene()
    builder()
    apply_all_transforms()
    export_glb(filename)


# --------------------------------------------------------------------------- #
# 1. Jetpack  (Blender Z = GLB Y; bottom ~ -0.42 after export)
# --------------------------------------------------------------------------- #

def build_jetpack():
    # Main capsule-like tank (cylinder + beveled edges).
    tank = cylinder("JetpackBody", (0, 0, 0), 0.150, 0.62,
                    MATS["dark"], vertices=12)
    apply_bevel(tank, 0.045, segments=2)

    cylinder("JetpackTopCap", (0, 0, 0.34), 0.090, 0.060,
             MATS["edge"], vertices=12)
    cylinder("JetpackWarningBand", (0, 0, 0.22), 0.155, 0.050,
             MATS["orange"], vertices=12)

    # Two side thrusters with glowing nozzles.
    for side, sx in (("L", -0.175), ("R", 0.175)):
        cylinder("JetpackThruster" + side, (sx, 0.020, -0.020),
                 0.075, 0.50, MATS["dark"], vertices=12)
        torus("JetpackThrusterRing" + side, (sx, 0.020, 0.205),
              0.075, 0.011, MATS["edge"], 12, 5)
        cylinder("JetpackNozzle" + side, (sx, 0.020, -0.350),
                 0.082, 0.140, MATS["cyan"], vertices=12, radius2=0.050)
        cylinder("JetpackNozzleCore" + side, (sx, 0.020, -0.428),
                 0.048, 0.016, MATS["cyan_bright"], vertices=12)

    # Harness straps and buckle on the front face (-Y in Blender).
    cube("JetpackStrapL", (-0.105, -0.160, 0.015),
         (0.022, 0.014, 0.275), MATS["rubber"])
    cube("JetpackStrapR", (0.105, -0.160, 0.015),
         (0.022, 0.014, 0.275), MATS["rubber"])
    cube("JetpackBelt", (0, -0.172, -0.120),
         (0.170, 0.016, 0.030), MATS["edge"])
    cube("JetpackBuckle", (0, -0.192, -0.120),
         (0.045, 0.014, 0.035), MATS["orange"])
    cube("JetpackBackPlate", (0, 0.158, 0.0),
         (0.130, 0.014, 0.250), MATS["edge"])


# --------------------------------------------------------------------------- #
# 2. Trampoline  (Blender Z = GLB Y; bottom at 0 after export)
# --------------------------------------------------------------------------- #

def build_trampoline():
    # Lower ring, legs and feet: everything starts at Z = 0.
    torus("TrampolineBaseRing", (0, 0, 0.060),
          0.820, 0.050, MATS["dark"], 24, 6)
    for idx in range(8):
        angle = 2.0 * math.pi * idx / 8.0
        cx, cy = 0.82 * math.cos(angle), 0.82 * math.sin(angle)
        cylinder("TrampolineLeg_%02d" % (idx + 1), (cx, cy, 0.410),
                 0.048, 0.820, MATS["dark"], vertices=8)
        cylinder("TrampolineFoot_%02d" % (idx + 1), (cx, cy, 0.015),
                 0.085, 0.030, MATS["rubber"], vertices=8)

    # Radial support arms leading out to the large top frame.
    for idx in range(8):
        angle = 2.0 * math.pi * idx / 8.0
        radial_cylinder("TrampolineSupport_%02d" % (idx + 1),
                        angle, 0.970, 0.820, 0.340, 0.038, MATS["edge"])

    torus("TrampolineFrame", (0, 0, 0.820),
          1.120, 0.055, MATS["dark"], 32, 6)

    # Taut elastic mat and its cyan stitching ring.
    cylinder("TrampolineMat", (0, 0, 0.760),
             0.940, 0.022, MATS["elastic"], vertices=32)
    torus("TrampolineMatRing", (0, 0, 0.777),
          0.870, 0.012, MATS["cyan"], 32, 5)

    # Alternating cyan/orange springs around the mat.
    for idx in range(16):
        angle = 2.0 * math.pi * idx / 16.0
        material = MATS["cyan"] if idx % 2 == 0 else MATS["orange"]
        radial_cylinder("TrampolineSpring_%02d" % (idx + 1),
                        angle, 1.000, 0.780, 0.145, 0.017, material)

    # Four orange safety pads on the top frame.
    for idx in range(4):
        angle = math.radians(45.0 + 90.0 * idx)
        px, py = 1.120 * math.cos(angle), 1.120 * math.sin(angle)
        pad = cube("TrampolineWarningPad_%02d" % (idx + 1),
                   (px, py, 0.878), (0.085, 0.050, 0.012), MATS["orange"])
        pad.rotation_euler.z = angle


# --------------------------------------------------------------------------- #
# 3. Plank  (3.0 long X, 0.7 wide Y -> 0.7 Z in GLB, 0.18 thick Z -> Y in GLB)
# --------------------------------------------------------------------------- #

def build_plank():
    board = cube("PlankBoard", (0, 0, 0), (1.5, 0.35, 0.09),
                 MATS["wood"], bevel=0.018)

    cube("PlankEdgeL", (0, -0.340, 0), (1.5, 0.022, 0.096), MATS["edge"])
    cube("PlankEdgeR", (0, 0.340, 0), (1.5, 0.022, 0.096), MATS["edge"])
    cube("PlankEndCapL", (-1.480, 0, 0), (0.025, 0.360, 0.100), MATS["edge"])
    cube("PlankEndCapR", (1.480, 0, 0), (0.025, 0.360, 0.100), MATS["edge"])

    # Grip stripes across the top face; orange at the two ends.
    for idx in range(11):
        x = -1.25 + 0.25 * idx
        material = MATS["orange"] if idx in (0, 10) else MATS["cyan"]
        cube("PlankGripStripe_%02d" % (idx + 1), (x, 0, 0.096),
             (0.023, 0.300, 0.007), material)

    # Underneath mounting brackets.
    cube("PlankBracketL", (-1.000, 0, -0.115),
         (0.090, 0.250, 0.030), MATS["dark"])
    cube("PlankBracketR", (1.000, 0, -0.115),
         (0.090, 0.250, 0.030), MATS["dark"])


# --------------------------------------------------------------------------- #
# 4. Crate  (1.1 m cube, origin at center)
# --------------------------------------------------------------------------- #

def build_crate():
    body = cube("CrateBody", (0, 0, 0), (0.530, 0.530, 0.530),
                MATS["dark"], bevel=0.020)

    # Twelve reinforced edge beams.
    for iz, z in enumerate((-0.515, 0.515)):
        for iy, y in enumerate((-0.515, 0.515)):
            cube("CrateFrameX_%d%d" % (iz, iy), (0, y, z),
                 (0.550, 0.036, 0.036), MATS["edge"])
    for ix, x in enumerate((-0.515, 0.515)):
        for iz, z in enumerate((-0.515, 0.515)):
            cube("CrateFrameY_%d%d" % (ix, iz), (x, 0, z),
                 (0.036, 0.550, 0.036), MATS["edge"])
    for ix, x in enumerate((-0.515, 0.515)):
        for iy, y in enumerate((-0.515, 0.515)):
            cube("CrateFrameZ_%d%d" % (ix, iy), (x, y, 0),
                 (0.036, 0.036, 0.550), MATS["edge"])

    # Cyan identification panel on the front (-Y in Blender).
    cube("CratePanelCyan", (0, -0.537, 0),
         (0.310, 0.008, 0.230), MATS["cyan"])
    cube("CratePanelFrame", (0, -0.534, 0),
         (0.350, 0.006, 0.270), MATS["edge"])

    # Orange warning stripes on the lid.
    cube("CrateLidStripeL", (-0.270, 0, 0.537),
         (0.040, 0.460, 0.008), MATS["orange"])
    cube("CrateLidStripeR", (0.270, 0, 0.537),
         (0.040, 0.460, 0.008), MATS["orange"])


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    init_materials()
    build_and_export("jetpack.glb", build_jetpack)
    build_and_export("trampoline.glb", build_trampoline)
    build_and_export("plank.glb", build_plank)
    build_and_export("crate.glb", build_crate)
    print("ALL_MODELS_DONE")


if __name__ == "__main__":
    main()
