# Balcão de poções da casa de feitiçaria: caldeirão fervendo em cima do fogo, estante com
# frascos, bancada com livro e cristais. Roda dentro do Blender e exporta
# assets/models/potion_shop.fbx. As peças são separadas por tipo ("Iron_potion_shop"), que o
# Roblox pinta pelo nome. Os cubinhos "Pivot_*" (centro, no chão) e "Front_*" (lado de onde o
# jogador chega) servem para o jogo posicionar e virar o modelo. Medidas em studs; a frente é -Y.

import bpy, bmesh, math, os
from mathutils import Matrix, Vector

OUT = os.environ.get("SHOP_OUT", r"E:\Projetos roblox\Teste_foda\assets\models\potion_shop.fbx")
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

def ball(kind, x, y, z, r, segs=8):
    loft(kind, [(x, y, z - r, 0), (x, y, z - r * 0.7, r * 0.7), (x, y, z, r), (x, y, z + r * 0.7, r * 0.7), (x, y, z + r, 0)], segs)

def bottle(kind, x, y, z, r, h):
    """Frasco: bojo redondo, gargalo, rolha e o líquido aceso por dentro (o bojo é o líquido)."""
    loft(kind, [(x, y, z, r * 0.55), (x, y, z + h * 0.12, r), (x, y, z + h * 0.45, r), (x, y, z + h * 0.62, r * 0.38)], 8)
    loft("Glass", [(x, y, z + h * 0.62, r * 0.38), (x, y, z + h * 0.86, r * 0.34), (x, y, z + h * 0.9, r * 0.46)], 8)
    loft("Cork", [(x, y, z + h * 0.88, r * 0.32), (x, y, z + h, r * 0.28)], 6)

# ---------------------------------------------------------------- tapete de pedra e fogo
loft("Stone", [(0, 0, 0, 5.6), (0, 0, 0.35, 5.4), (0, 0, 0.5, 5.0)], 12)
for i in range(12):  # pedras em volta da fogueira
    a = 2 * math.pi * i / 12
    box("Stone", (1.0, 0.8, 0.7), (2.3 * math.cos(a), 2.3 * math.sin(a), 0.8), Matrix.Rotation(a + 0.3 * (i % 3), 4, 'Z'))
for i in range(5):  # lenha em estrela
    a = math.pi * i / 5
    box("Wood", (3.4, 0.5, 0.5), (0, 0, 0.85 + 0.1 * (i % 2)), Matrix.Rotation(a, 4, 'Z') @ Matrix.Rotation(0.12, 4, 'Y'))
for (x, y, r, h) in ((0, 0, 0.9, 2.3), (0.8, 0.3, 0.6, 1.7), (-0.7, 0.4, 0.55, 1.5), (0.2, -0.8, 0.6, 1.8), (-0.4, -0.6, 0.45, 1.3)):
    loft("Flame", [(x, y, 0.9, r * 0.5), (x, y, 0.9 + h * 0.3, r), (x + 0.1, y, 0.9 + h * 0.7, r * 0.55), (x + 0.2, y + 0.1, 0.9 + h, 0)], 6)

# ---------------------------------------------------------------- caldeirão
for i in range(3):  # tripé de ferro
    a = 2 * math.pi * i / 3 + 0.5
    p0 = Vector((2.5 * math.cos(a), 2.5 * math.sin(a), 0.5))
    p1 = Vector((1.5 * math.cos(a), 1.5 * math.sin(a), 3.0))
    d = p1 - p0
    box("Iron", (d.length, 0.28, 0.28), (0, 0, 0), Matrix.Translation((p0 + p1) / 2) @ d.to_track_quat('X', 'Z').to_matrix().to_4x4())
loft("Iron", [(0, 0, 2.5, 0.9), (0, 0, 2.7, 1.9), (0, 0, 3.3, 2.5), (0, 0, 4.2, 2.6), (0, 0, 4.8, 2.25), (0, 0, 5.0, 2.45), (0, 0, 5.15, 2.45), (0, 0, 5.15, 2.05), (0, 0, 4.7, 2.0)], 12)
loft("Gold", [(0, 0, 3.55, 2.62), (0, 0, 3.8, 2.68)], 12)
for s in (-1, 1):  # alças
    for k in range(5):
        a = math.pi * k / 4
        box("Iron", (0.22, 0.22, 0.5), (s * (2.55 + 0.45 * math.sin(a)), 0, 4.2 + 0.45 * math.cos(a)), Matrix.Rotation(-s * a, 4, 'Y'))
# líquido aceso, bolhas e a colher
loft("Liquid", [(0, 0, 4.7, 2.0), (0, 0, 4.82, 2.0)], 12)
for (x, y, r, z) in ((0.7, 0.4, 0.42, 4.95), (-0.8, 0.5, 0.3, 4.9), (0.1, -0.9, 0.36, 4.92), (-0.3, -0.1, 0.24, 5.5), (0.9, -0.5, 0.2, 5.9), (-0.9, -0.6, 0.16, 6.4), (0.3, 0.8, 0.14, 6.9)):
    ball("Liquid", x, y, z, r, 6)
Ml = Matrix.Translation((1.2, 0.9, 5.3)) @ Matrix.Rotation(math.radians(24), 4, 'Y') @ Matrix.Rotation(math.radians(-14), 4, 'X')
box("Wood", (0.2, 0.2, 3.6), (0, 0, 1.0), Ml)
loft("Wood", [(0, 0, -1.0, 0.1), (0, 0, -0.85, 0.42), (0, 0, -0.6, 0.42)], 8, matrix=Ml)

# ---------------------------------------------------------------- estante atrás (+Y)
for x in (-3.9, 3.9):
    box("Wood", (0.5, 1.2, 9.2), (x, 4.2, 5.0))
    loft("Gold", [(x, 4.2, 9.6, 0.5), (x, 4.2, 10.0, 0.3), (x, 4.2, 10.5, 0)], 6)
for z in (0.9, 3.6, 6.2, 8.8):
    box("Wood", (8.4, 1.4, 0.3), (0, 4.2, z))
box("Wood", (8.0, 0.2, 9.0), (0, 4.75, 5.0))  # fundo
box("Gold", (8.6, 1.5, 0.18), (0, 4.2, 9.05))
# frascos nas prateleiras: três cores de poção, tamanhos variados
shelf = {3.75: ((-3.0, "PotionA", 0.55, 1.9), (-1.7, "PotionB", 0.45, 1.5), (-0.5, "PotionC", 0.6, 2.0), (0.9, "PotionA", 0.4, 1.3), (2.0, "PotionB", 0.58, 2.1), (3.1, "PotionC", 0.42, 1.5)),
         6.35: ((-2.9, "PotionC", 0.5, 1.7), (-1.5, "PotionA", 0.6, 2.1), (0.0, "PotionB", 0.5, 1.6), (1.5, "PotionC", 0.55, 1.9), (2.9, "PotionA", 0.45, 1.6)),
         1.05: ((-2.6, "PotionB", 0.62, 2.0), (-0.9, "PotionC", 0.5, 1.6), (2.6, "PotionB", 0.5, 1.8))}
for z, row in shelf.items():
    for (x, kind, r, h) in row:
        bottle(kind, x, 4.0, z, r, h)
# livros deitados e em pé na prateleira de baixo
for i, (w, c) in enumerate(((0.5, "BookA"), (0.4, "BookB"), (0.55, "BookA"), (0.45, "BookB"))):
    box(c, (w, 1.0, 1.7), (0.5 + i * 0.56, 4.0, 1.9))
    box("Gold", (w + 0.02, 0.08, 0.2), (0.5 + i * 0.56, 3.5, 2.3))

# ---------------------------------------------------------------- bancada na frente, de lado
box("Wood", (3.4, 2.2, 0.35), (-4.1, -2.4, 2.9))
for (x, y) in ((-5.5, -3.2), (-2.7, -3.2), (-5.5, -1.6), (-2.7, -1.6)):
    box("Wood", (0.35, 0.35, 2.7), (x, y, 1.35))
box("Gold", (3.5, 2.3, 0.1), (-4.1, -2.4, 3.1))
# livro aberto
box("BookA", (1.7, 1.2, 0.14), (-4.3, -2.3, 3.22), Matrix.Rotation(0.3, 4, 'Z'))
for s in (-1, 1):
    box("Page", (0.78, 1.06, 0.1), (0, 0, 0), Matrix.Translation((-4.3, -2.3, 3.32)) @ Matrix.Rotation(0.3, 4, 'Z') @ Matrix.Translation((s * 0.41, 0, 0)) @ Matrix.Rotation(s * 0.14, 4, 'Y'))
bottle("PotionA", -3.1, -2.9, 3.15, 0.45, 1.5)
bottle("PotionC", -5.2, -1.9, 3.15, 0.36, 1.2)
# cristais nascendo do chão, do outro lado
for (x, y, tilt, h, r, a) in ((4.4, -2.6, 8, 3.4, 0.7, 0.4), (5.0, -1.7, 26, 2.3, 0.5, 1.4), (3.7, -3.3, 24, 2.0, 0.45, -1.0), (4.9, -3.3, 38, 1.5, 0.36, 0.2)):
    axis = Vector((-math.sin(a), math.cos(a), 0))
    Mc = Matrix.Translation((x, y, 0.3)) @ Matrix.Rotation(math.radians(tilt), 4, axis)
    loft("Crystal", [(0, 0, 0, r), (0, 0, h * 0.7, r * 0.9), (0, 0, h, 0)], 6, matrix=Mc)

box("Pivot", (0.1, 0.1, 0.1), (0, 0, 0))
box("Front", (0.1, 0.1, 0.1), (0, -4, 0))

# ---------------------------------------------------------------- objetos e exportação
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
report = []
for kind, bm in K.items():
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    me = bpy.data.meshes.new(kind + "_potion_shop")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(kind + "_potion_shop", me)
    bpy.context.collection.objects.link(ob)
    report.append((kind, len(me.polygons)))
K.clear()
bpy.ops.object.select_all(action="DESELECT")
for ob in bpy.data.objects:
    ob.select_set(True)
bpy.ops.export_scene.fbx(filepath=OUT, use_selection=True, object_types={"MESH"}, apply_scale_options="FBX_SCALE_ALL",
    axis_forward="-Z", axis_up="Y", bake_space_transform=True, mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False)
print(report, os.path.getsize(OUT))
