# Montarias (painel MOUNTS): skate flutuante e tapete voador. Roda dentro do Blender e exporta
# um .fbx por montaria em assets/models. As peças são separadas por tipo ("Deck_hoverboard"),
# que o Roblox pinta pelo nome. O tapete sai em gomos numerados ("Cloth_carpet_3") para o jogo
# ondular. Em cada modelo, um cubinho "Pivot_*" marca onde o boneco pisa e, no skate, as peças
# "Jet_*" marcam a traseira. Medidas em studs; o comprimento fica no eixo Y do Blender.

import bpy, bmesh, math, os
from mathutils import Matrix, Vector

OUT = os.environ.get("MOUNTS_OUT", r"E:\Projetos roblox\Teste_foda\assets\models")
K = {}

def bm_of(kind):
    if kind not in K:
        K[kind] = bmesh.new()
    return K[kind]

def box(kind, size, loc, rot=None):
    m = Matrix.Translation(Vector(loc))
    if rot is not None:
        m = m @ rot
    bmesh.ops.create_cube(bm_of(kind), size=1, matrix=m @ Matrix.Diagonal((size[0], size[1], size[2], 1)))

def loft(kind, rings, segs, phase=0.0, matrix=None):
    bm = bm_of(kind)
    M = matrix or Matrix.Identity(4)
    loops = []
    for (cx, cy, z, r) in rings:
        if r <= 1e-6:
            loops.append([bm.verts.new(M @ Vector((cx, cy, z)))])
        else:
            loops.append([bm.verts.new(M @ Vector((cx + r * math.cos(phase + 2 * math.pi * i / segs), cy + r * math.sin(phase + 2 * math.pi * i / segs), z))) for i in range(segs)])
    for a, b in zip(loops, loops[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            if len(b) == 1 and len(a) > 1:
                bm.faces.new((a[i], a[j], b[0]))
            elif len(a) == 1 and len(b) > 1:
                bm.faces.new((a[0], b[j], b[i]))
            elif len(a) > 1:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    if len(loops[0]) > 1:
        bm.faces.new(list(reversed(loops[0])))
    if len(loops[-1]) > 1:
        bm.faces.new(loops[-1])

def prism(kind, pts, depth, matrix):
    bm = bm_of(kind)
    front = [bm.verts.new(matrix @ Vector((u, 0, v))) for u, v in pts]
    back = [bm.verts.new(matrix @ Vector((u, depth, v))) for u, v in pts]
    n = len(pts)
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[j], front[i], back[i], back[j]))

def finish(model):
    """Vira objetos (um por tipo), exporta <model>.fbx e limpa a cena."""
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    report = []
    for kind, bm in K.items():
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bmesh.ops.triangulate(bm, faces=bm.faces)
        base, _, seg = kind.partition("#")
        name = base + "_" + model + ("_" + seg if seg else "")
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(ob)
        report.append((name, len(me.polygons)))
    K.clear()
    bpy.ops.object.select_all(action="DESELECT")
    for ob in bpy.data.objects:
        ob.select_set(True)
    path = os.path.join(OUT, model + ".fbx")
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"MESH"}, apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z", axis_up="Y", bake_space_transform=True, mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False)
    print(model, len(report), "objetos", sum(n for _, n in report), "tris", os.path.getsize(path), "bytes")

# ---------------------------------------------------------------- skate flutuante
# Estilo antigravidade: as rodas ficam deitadas, viradas para o chão, com um disco aceso embaixo.
# O topo do shape fica em z = 0 (onde o boneco pisa); a frente é +Y.
side = Matrix.Rotation(math.radians(90), 4, 'Z')  # perfil desenhado de lado, extrudado na largura
HALF_W = 1.05
profile = [(-3.3, 0.5), (-2.5, -0.3), (2.5, -0.3), (3.4, 0.55), (3.4, 0.85), (2.5, 0.0), (-2.5, 0.0), (-3.3, 0.8)]
prism("Deck", profile, HALF_W * 2, Matrix.Translation((HALF_W, 0, 0)) @ side)
# lixa escura em cima e faixas acesas
box("Grip", (HALF_W * 2 - 0.3, 4.7, 0.04), (0, 0, 0.02))
for x in (-0.55, 0.55):
    box("Glow", (0.12, 4.4, 0.05), (x, 0, 0.045))
box("Glow", (1.5, 0.12, 0.05), (0, 1.6, 0.045))
box("Glow", (1.5, 0.12, 0.05), (0, -1.6, 0.045))
# friso de metal nas bordas
for x in (-HALF_W - 0.04, HALF_W + 0.04):
    box("Metal", (0.1, 5.0, 0.2), (x, 0, -0.15))
for y in (-1.9, 1.9):
    # eixo, braços e as quatro rodas deitadas
    box("Metal", (1.5, 0.7, 0.28), (0, y, -0.44))
    box("Metal", (3.3, 0.3, 0.18), (0, y, -0.55))
    for x in (-1.75, 1.75):
        loft("Wheel", [(x, y, -0.78, 0.5), (x, y, -0.86, 0.62), (x, y, -0.48, 0.62), (x, y, -0.4, 0.5)], 12)
        loft("Metal", [(x, y, -0.4, 0.3), (x, y, -0.34, 0.3)], 8)
        loft("Glow", [(x, y, -0.92, 0.46), (x, y, -0.86, 0.46)], 12)
        loft("Glow", [(x, y, -1.02, 0.2), (x, y, -0.92, 0.3)], 8)
# dois propulsores na traseira (-Y)
for x in (-0.5, 0.5):
    Mj = Matrix.Translation((x, -2.2, -0.52)) @ Matrix.Rotation(math.radians(90), 4, 'X')
    loft("Metal", [(0, 0, -0.1, 0.24), (0, 0, 0.7, 0.3), (0, 0, 0.95, 0.36)], 8, matrix=Mj)
    loft("Jet", [(0, 0, 0.95, 0.27), (0, 0, 1.05, 0.2), (0, 0, 1.5, 0)], 8, matrix=Mj)
# bico aceso na frente
box("Glow", (1.1, 0.1, 0.12), (0, 3.38, 0.68))
box("Pivot", (0.1, 0.1, 0.1), (0, 0, 0))
finish("hoverboard")

# ---------------------------------------------------------------- tapete voador
# Sete gomos ao longo do comprimento; o topo fica em z = 0.
SEGS, SEG_LEN, WIDE = 7, 1.0, 4.4
for i in range(SEGS):
    n = str(i + 1)
    y = (i - (SEGS - 1) / 2) * SEG_LEN
    box("Cloth#" + n, (WIDE - 0.5, SEG_LEN + 0.04, 0.14), (0, y, -0.07))
    for x in (-1, 1):
        box("Gold#" + n, (0.3, SEG_LEN + 0.04, 0.17), (x * (WIDE / 2 - 0.15), y, -0.07))
        box("Trim#" + n, (0.14, SEG_LEN + 0.04, 0.03), (x * (WIDE / 2 - 0.62), y, 0.012))
    last = i in (0, SEGS - 1)
    end = -1 if i == 0 else 1
    if last:
        box("Gold#" + n, (WIDE, 0.3, 0.17), (0, y + end * (SEG_LEN / 2 - 0.13), -0.07))
        for k in range(9):  # franja
            x = (k - 4) * (WIDE - 0.5) / 8
            box("Gold#" + n, (0.1, 0.5, 0.06), (x, y + end * (SEG_LEN / 2 + 0.25), -0.1))
        for x in (-1, 1):  # borlas nos cantos
            cx, cy = x * (WIDE / 2 - 0.1), y + end * (SEG_LEN / 2 + 0.1)
            loft("Gold#" + n, [(cx, cy, -0.75, 0.05), (cx, cy, -0.6, 0.2), (cx, cy, -0.32, 0.17), (cx, cy, -0.2, 0.05)], 6)
            loft("Trim#" + n, [(cx, cy, -0.2, 0.09), (cx, cy, -0.05, 0.09)], 6)
    elif i == SEGS // 2:
        # medalhão no meio
        loft("Gold#" + n, [(0, y, 0, 0.62), (0, y, 0.03, 0.62)], 8, phase=math.pi / 8)
        loft("Gem#" + n, [(0, y, 0.03, 0.34), (0, y, 0.06, 0.34)], 8, phase=math.pi / 8)
    else:
        # losangos do desenho, alternando ouro e cor
        kind = "Trim#" if i % 2 == 0 else "Gold#"
        for x in (-1.0, 0.0, 1.0):
            box(kind + n, (0.46, 0.46, 0.03), (x, y, 0.012), Matrix.Rotation(math.radians(45), 4, 'Z'))
box("Pivot", (0.1, 0.1, 0.1), (0, 0, 0))
finish("carpet")
