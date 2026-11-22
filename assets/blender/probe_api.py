import bpy
import sys

print("BFORARTISTS_VERSION:", bpy.app.version_string)
print("BLENDER_VERSION:", bpy.app.version)
try:
    op = bpy.ops.export_scene.gltf
    print("GLTF_OP_AVAILABLE: True")
    rna = op.get_rna_type()
    names = sorted(p.identifier for p in rna.properties)
    for key in ["filepath", "export_format", "use_selection", "export_apply",
                "export_materials", "export_yup", "export_cameras", "export_lights"]:
        print("GLTF_ARG", key, key in names)
except Exception as exc:  # noqa: BLE001
    print("GLTF_OP_AVAILABLE: False", repr(exc))

print("PROBE_DONE")
