"""Generate Descent greybox assets as .glb via Blender.

Run:  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" --background --python tools/gen_assets.py

Greybox primitives, flat solid colors only. No textures, no rigging.
Outputs res://assets/{player,enemy,arena}.glb (Blender is Z-up; glTF export
converts to Godot's Y-up, so capsules built along +Z stand along +Y in Godot).
"""
import bpy
import os

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets")
os.makedirs(OUT, exist_ok=True)


def clear():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)


def flat_mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Metallic"].default_value = 0.0
    m.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    return m


def set_origin_world(obj):
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    obj.location = (0, 0, 0)


def make_capsule(name, radius, cyl_h, mat):
    # cylinder body + two spherical caps, joined; geometry spans z = 0 .. 2*radius+cyl_h
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=cyl_h, location=(0, 0, radius + cyl_h / 2))
    cyl = bpy.context.active_object
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=(0, 0, radius + cyl_h))
    top = bpy.context.active_object
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=(0, 0, radius))
    bot = bpy.context.active_object
    bpy.ops.object.select_all(action='DESELECT')
    for o in (cyl, top, bot):
        o.select_set(True)
    bpy.context.view_layer.objects.active = cyl
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    set_origin_world(obj)
    return obj


def select_only(objs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def export(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True)


# player (blue capsule)
clear()
p = make_capsule("Player", 0.4, 1.2, flat_mat("blue", (0.15, 0.35, 0.85)))
select_only([p])
export(os.path.join(OUT, "player.glb"))

# enemy (red capsule)
clear()
e = make_capsule("Enemy", 0.4, 1.2, flat_mat("red", (0.80, 0.15, 0.12)))
select_only([e])
export(os.path.join(OUT, "enemy.glb"))

# arena: dark-grey ground plane + 4 mid-grey walls (open top box)
clear()
gmat = flat_mat("ground", (0.12, 0.12, 0.13))
wmat = flat_mat("wall", (0.40, 0.40, 0.42))
bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0, 0))
ground = bpy.context.active_object
ground.name = "Ground"
ground.data.materials.append(gmat)
objs = [ground]
half, h, t = 5.0, 2.5, 0.3
specs = [
    ((0, -half, h / 2), (12, t, h)),
    ((0, half, h / 2), (12, t, h)),
    ((-half, 0, h / 2), (t, 12, h)),
    ((half, 0, h / 2), (t, 12, h)),
]
for i, (loc, scale) in enumerate(specs):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    w = bpy.context.active_object
    w.name = "Wall%d" % i
    w.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    w.data.materials.append(wmat)
    objs.append(w)
select_only(objs)
export(os.path.join(OUT, "arena.glb"))

print("DONE assets ->", OUT)
