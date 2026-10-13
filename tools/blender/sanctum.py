# Casa de feitiçaria do centro do mapa (Sanctum). Roda dentro do Blender: monta as peças por tipo
# ("Stone_sanctum", "Roof_sanctum"...), que o Roblox pinta pelo nome, e exporta o .fbx.
# Medidas em studs; as mesmas estão em Config.Sanctum (colisão feita no Roblox).

import bpy, bmesh, math
from mathutils import Matrix, Vector

# cena limpa
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
for m in list(bpy.data.meshes):
    bpy.data.meshes.remove(m)

K = {}
def bm_of(kind):
    if kind not in K:
        K[kind] = bmesh.new()
    return K[kind]

def box(kind, size, loc, rot=None):
    bm = bm_of(kind)
    m = Matrix.Translation(Vector(loc))
    if rot is not None:
        m = m @ rot
    m = m @ Matrix.Diagonal((size[0], size[1], size[2], 1))
    bmesh.ops.create_cube(bm, size=1, matrix=m)

def loft(kind, rings, segs, phase=0.0, cap_bottom=True, cap_top=True, matrix=None):
    """rings: lista de (cx, cy, z, r). r == 0 vira ponta."""
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
            if len(a) == 1 and len(b) == 1:
                continue
            if len(b) == 1:
                bm.faces.new((a[i], a[j], b[0]))
            elif len(a) == 1:
                bm.faces.new((a[0], b[j], b[i]))
            else:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap_bottom and len(loops[0]) > 1:
        bm.faces.new(list(reversed(loops[0])))
    if cap_top and len(loops[-1]) > 1:
        bm.faces.new(loops[-1])

def cyl(kind, r, z0, z1, x=0, y=0, segs=12, r2=None, phase=0.0):
    loft(kind, [(x, y, z0, r), (x, y, z1, r if r2 is None else r2)], segs, phase)

def prism(kind, pts, depth, matrix):
    """pts 2D (u, v) no plano local XZ; extrusão em +Y local por depth."""
    bm = bm_of(kind)
    front = [bm.verts.new(matrix @ Vector((u, 0, v))) for u, v in pts]
    back = [bm.verts.new(matrix @ Vector((u, depth, v))) for u, v in pts]
    n = len(pts)
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[j], front[i], back[i], back[j]))

def rotz(deg):
    return Matrix.Rotation(math.radians(deg), 4, 'Z')

def gem(kind, x, y, z, r, h, segs=6, matrix=None):
    loft(kind, [(x, y, z - h / 2, 0), (x, y, z - h * 0.12, r), (x, y, z + h * 0.12, r), (x, y, z + h / 2, 0)], segs, matrix=matrix)

# ---------------------------------------------------------------- medidas (studs)
HALF = 30.0      # meia largura do salão (por fora)
THICK = 3.0
FLOOR = 2.0      # topo do embasamento
WALL = 30.0      # altura das paredes
TOP = FLOOR + WALL
DOOR_W, DOOR_H = 14.0, 16.0   # vão: retângulo + meio círculo
PLINTH = 34.0
PORCH = 38.0

# embasamento e degraus
box("Dark", (PLINTH * 2, PLINTH * 2, FLOOR), (0, 0, FLOOR / 2))
box("Gold", (PLINTH * 2 + 0.6, PLINTH * 2 + 0.6, 0.35), (0, 0, FLOOR - 0.35))

for side in range(4):
    R = rotz(side * 90)
    # parede com o vão em arco (perfil único, extrudado)
    r = DOOR_W / 2
    pts = [(-HALF, FLOOR), (-r, FLOOR), (-r, FLOOR + DOOR_H)]
    for i in range(1, 12):
        a = math.pi - math.pi * i / 12
        pts.append((r * math.cos(a), FLOOR + DOOR_H + r * math.sin(a)))
    pts += [(r, FLOOR + DOOR_H), (r, FLOOR), (HALF, FLOOR), (HALF, TOP), (-HALF, TOP)]
    prism("Stone", pts, THICK, R @ Matrix.Translation((0, HALF - THICK, 0)))
    # moldura dourada do arco, por fora e por dentro
    for depth_y in (HALF - 0.05, HALF - THICK - 0.35):
        ring = []
        for i in range(0, 13):
            a = math.pi - math.pi * i / 12
            ring.append(a)
        outer = [(-(r + 1.1), FLOOR)] + [((r + 1.1) * math.cos(a), FLOOR + DOOR_H + (r + 1.1) * math.sin(a)) for a in ring] + [((r + 1.1), FLOOR)]
        inner = [(r, FLOOR)] + [(r * math.cos(a), FLOOR + DOOR_H + r * math.sin(a)) for a in reversed(ring)] + [(-r, FLOOR)]
        prism("Gold", outer + inner, 0.4, R @ Matrix.Translation((0, depth_y, 0)))
    # faixa escura na base e cornija no topo
    for sx in (-1, 1):
        box("Dark", (HALF - r - 1.1, THICK + 0.8, 3.0), (0, 0, 0), R @ Matrix.Translation((sx * (HALF + r + 1.1) / 2, HALF - THICK / 2, FLOOR + 1.5)))
    box("Dark", (HALF * 2 + 2, THICK + 1.6, 1.6), (0, 0, 0), R @ Matrix.Translation((0, HALF - THICK / 2, TOP - 0.8)))
    box("Gold", (HALF * 2 + 2.4, THICK + 2.0, 0.5), (0, 0, 0), R @ Matrix.Translation((0, HALF - THICK / 2, TOP - 1.9)))
    # janelas ogivais acesas (duas por parede), por fora e por dentro
    for sx in (-1, 1):
        wx = sx * 15.5
        for y, d in ((HALF - 0.02, 0.3), (HALF - THICK - 0.28, 0.3)):
            M = R @ Matrix.Translation((wx, y, 0))
            prism("Glass", [(-2.4, 11), (2.4, 11), (2.4, 21), (0, 25), (-2.4, 21)], d, M)
            prism("Gold", [(-3.0, 10.4), (3.0, 10.4), (3.0, 21.3), (0, 25.9), (-3.0, 21.3), (-2.4, 21), (0, 25), (2.4, 21), (2.4, 11), (-2.4, 11), (-2.4, 21), (-3.0, 21.3)], d + 0.15, M)
            box("Gold", (0.3, d + 0.15, 13.6), (0, 0, 0), R @ Matrix.Translation((wx, y + d / 2, 17.8)))
            box("Gold", (4.8, d + 0.15, 0.3), (0, 0, 0), R @ Matrix.Translation((wx, y + d / 2, 16)))
        box("Dark", (7, 1.6, 0.9), (0, 0, 0), R @ Matrix.Translation((wx, HALF + 0.5, 10.0)))
    # alpendre: plataforma, degraus, colunas, frontão com rosácea
    box("Dark", (26, PORCH - PLINTH, FLOOR), (0, 0, 0), R @ Matrix.Translation((0, (PORCH + PLINTH) / 2, FLOOR / 2)))
    box("Stone", (24, 2, FLOOR * 2 / 3), (0, 0, 0), R @ Matrix.Translation((0, PORCH + 1, FLOOR / 3)))
    box("Stone", (24, 2, FLOOR / 3), (0, 0, 0), R @ Matrix.Translation((0, PORCH + 3, FLOOR / 6)))
    for sx in (-1, 1):
        cx, cy = sx * 10.5, PORCH - 2
        p = R @ Vector((cx, cy, 0))
        cyl("Dark", 2.0, FLOOR, FLOOR + 1.6, p.x, p.y, 8)
        cyl("Stone", 1.3, FLOOR + 1.6, 25.0, p.x, p.y, 8)
        cyl("Gold", 1.6, 12.5, 13.1, p.x, p.y, 8)
        cyl("Gold", 1.9, 25.0, 25.7, p.x, p.y, 8)
        cyl("Dark", 2.2, 25.7, 27.0, p.x, p.y, 8)
        # lanterna pendurada na coluna, virada para fora
        l = R @ Vector((cx, cy + 2.6, 0))
        box("Gold", (0.3, 2.4, 0.3), (0, 0, 0), R @ Matrix.Translation((cx, cy + 1.6, 19.5)))
        box("Gold", (0.2, 0.2, 1.2), (l.x, l.y, 18.8))
        box("Gold", (1.7, 1.7, 0.3), (l.x, l.y, 18.2))
        box("Glow", (1.25, 1.25, 2.0), (l.x, l.y, 17.05))
        box("Gold", (1.7, 1.7, 0.3), (l.x, l.y, 15.9))
    box("Dark", (25, PORCH - HALF + 0.5, 1.4), (0, 0, 0), R @ Matrix.Translation((0, (PORCH + HALF) / 2 + 0.25, 27.7)))
    prism("Roof", [(-14.5, 28.4), (14.5, 28.4), (0, 41.5)], PORCH - HALF + 2.0, R @ Matrix.Translation((0, HALF - 0.5, 0)))
    prism("Stone", [(-11.5, 28.4), (11.5, 28.4), (0, 38.6)], 0.5, R @ Matrix.Translation((0, PORCH + 1.5, 0)))
    for sx in (-1, 1):  # beiral dourado nas duas águas
        ang = math.atan2(13.1, 14.5)
        Mb = R @ Matrix.Translation((sx * 7.25, PORCH + 1.9, 35.2)) @ Matrix.Rotation(sx * ang, 4, 'Y')
        box("Gold", (20.4, 0.9, 0.9), (0, 0, 0), Mb)
    # rosácea
    Mr = R @ Matrix.Translation((0, PORCH + 2.0, 32.2)) @ Matrix.Rotation(math.radians(-90), 4, 'X')
    loft("Glass", [(0, 0, 0, 2.6), (0, 0, 0.35, 2.6)], 12, matrix=Mr)
    loft("Gold", [(0, 0, -0.05, 3.2), (0, 0, 0.2, 3.2)], 12, matrix=Mr)
    for k in range(3):
        box("Gold", (5.2, 0.3, 0.3), (0, 0, 0), R @ Matrix.Translation((0, PORCH + 2.3, 32.2)) @ Matrix.Rotation(math.radians(k * 60), 4, 'Y'))
    p = R @ Vector((0, PORCH + 0.6, 0))
    gem("Glow", p.x, p.y, 44.6, 1.3, 4.2)
    cyl("Gold", 0.7, 41.0, 42.6, p.x, p.y, 6)

# ---------------------------------------------------------------- torres de canto
for sx in (-1, 1):
    for sy in (-1, 1):
        x, y = sx * HALF, sy * HALF
        cyl("Dark", 9.4, 0, 4.0, x, y, 12)
        cyl("Gold", 9.0, 4.0, 4.6, x, y, 12)
        cyl("Stone", 8.0, 4.6, 46.0, x, y, 12)
        cyl("Gold", 8.5, 24.0, 24.8, x, y, 12)
        cyl("Dark", 8.9, 32.0, 33.6, x, y, 12)
        loft("Stone", [(x, y, 42.0, 8.0), (x, y, 46.0, 10.2), (x, y, 48.0, 10.2)], 12)
        cyl("Gold", 10.6, 48.0, 48.7, x, y, 12)
        # ameias
        for i in range(12):
            if i % 2 == 0:
                a = 2 * math.pi * (i + 0.5) / 12
                box("Stone", (2.6, 2.2, 2.4), (x + 9.2 * math.cos(a), y + 9.2 * math.sin(a), 49.8), Matrix.Rotation(a + math.pi / 2, 4, 'Z'))
        # chapéu: aba larga e cone alto levemente torto para fora
        lean = Vector((sx, sy, 0)).normalized()
        loft("Roof", [(x, y, 48.7, 12.2), (x, y, 50.2, 11.0), (x + lean.x * 0.6, y + lean.y * 0.6, 60.0, 6.6), (x + lean.x * 1.8, y + lean.y * 1.8, 69.0, 3.0), (x + lean.x * 3.6, y + lean.y * 3.6, 77.0, 0)], 12)
        cyl("Gold", 6.9, 59.6, 60.5, x + lean.x * 0.6, y + lean.y * 0.6, 12)
        gem("Glow", x + lean.x * 4.4, y + lean.y * 4.4, 81.5, 1.5, 5.0)
        # seteiras acesas viradas para fora
        for da in (-50, 0, 50):
            a = math.atan2(sy, sx) + math.radians(da)
            for zc in (16.0, 38.5):
                box("Glass", (1.5, 0.5, 5.2), (x + 7.75 * math.cos(a), y + 7.75 * math.sin(a), zc), Matrix.Rotation(a + math.pi / 2, 4, 'Z'))
                box("Gold", (2.3, 0.4, 0.5), (x + 7.8 * math.cos(a), y + 7.8 * math.sin(a), zc - 3.0), Matrix.Rotation(a + math.pi / 2, 4, 'Z'))
        # cristais na base, por fora
        for k, (da, tilt, h, rr) in enumerate(((0, 14, 12.0, 2.3), (-34, 30, 8.0, 1.7), (36, 26, 9.0, 1.8), (-12, 42, 5.5, 1.2))):
            a = math.atan2(sy, sx) + math.radians(da)
            base = Vector((x + 9.3 * math.cos(a), y + 9.3 * math.sin(a), 0.2))
            axis = Vector((-math.sin(a), math.cos(a), 0))
            Mc = Matrix.Translation(base) @ Matrix.Rotation(-math.radians(tilt), 4, axis)
            loft("Glow", [(0, 0, 0, rr), (0, 0, h * 0.7, rr * 0.9), (0, 0, h, 0)], 6, matrix=Mc)

# ---------------------------------------------------------------- telhado, torre central e chapéu
s2 = math.sqrt(2)
box("Dark", (HALF * 2 - 0.5, HALF * 2 - 0.5, 1.0), (0, 0, TOP - 0.5))            # forro
box("Gold", (HALF * 2 + 5.0, HALF * 2 + 5.0, 0.7), (0, 0, TOP + 0.35))            # beiral
loft("Roof", [(0, 0, TOP + 0.7, 34.0 * s2), (0, 0, TOP + 2.2, 32.0 * s2), (0, 0, 52.0, 13.5 * s2)], 4, phase=math.pi / 4)
for k in range(4):  # cumeeiras douradas
    a = math.pi / 4 + k * math.pi / 2
    p0 = Vector((32.0 * s2 * math.cos(a), 32.0 * s2 * math.sin(a), TOP + 2.2))
    p1 = Vector((13.5 * s2 * math.cos(a), 13.5 * s2 * math.sin(a), 52.0))
    d = p1 - p0
    Mq = Matrix.Translation((p0 + p1) / 2) @ d.to_track_quat('X', 'Z').to_matrix().to_4x4()
    box("Gold", (d.length, 0.9, 0.9), (0, 0, 0), Mq)
# lucarnas acesas nas quatro águas
for side in range(4):
    R = rotz(side * 90)
    prism("Stone", [(-3.6, 38.0), (3.6, 38.0), (3.6, 44.0), (0, 47.2), (-3.6, 44.0)], 7.0, R @ Matrix.Translation((0, 20.0, 0)))
    prism("Roof", [(-4.6, 43.4), (0, 48.4), (4.6, 43.4), (4.6, 44.4), (0, 49.4), (-4.6, 44.4)], 8.0, R @ Matrix.Translation((0, 19.6, 0)))
    prism("Glass", [(-2.2, 39.2), (2.2, 39.2), (2.2, 43.4), (0, 45.6), (-2.2, 43.4)], 0.3, R @ Matrix.Translation((0, 27.0, 0)))

cyl("Dark", 14.4, 50.5, 53.5, segs=8, phase=math.pi / 8)
cyl("Gold", 14.0, 53.5, 54.2, segs=8, phase=math.pi / 8)
cyl("Stone", 12.5, 54.2, 78.0, segs=8, phase=math.pi / 8)
cyl("Gold", 13.0, 66.0, 66.8, segs=8, phase=math.pi / 8)
loft("Stone", [(0, 0, 74.0, 12.5), (0, 0, 78.0, 15.2), (0, 0, 80.0, 15.2)], 8, phase=math.pi / 8)
cyl("Gold", 15.7, 80.0, 80.8, segs=8, phase=math.pi / 8)
for i in range(8):  # janelas altas nas oito faces
    a = 2 * math.pi * i / 8
    rr = 12.5 * math.cos(math.pi / 8)
    M = Matrix.Rotation(a - math.pi / 2, 4, 'Z') @ Matrix.Translation((0, rr - 0.05, 0))
    prism("Glass", [(-1.9, 57.0), (1.9, 57.0), (1.9, 61.5), (0, 64.2), (-1.9, 61.5)], 0.3, M)
    prism("Glass", [(-1.9, 68.5), (1.9, 68.5), (1.9, 72.0), (0, 74.6), (-1.9, 72.0)], 0.3, M)
    box("Gold", (5.0, 0.6, 0.5), (0, 0, 0), M @ Matrix.Translation((0, 0.2, 56.5)))
    box("Gold", (5.0, 0.6, 0.5), (0, 0, 0), M @ Matrix.Translation((0, 0.2, 68.0)))
# chapéu de feiticeiro: aba, faixa e ponta dobrada
loft("Roof", [(0, 0, 80.8, 19.5), (0, 0, 82.4, 18.0), (0.3, 0, 96.0, 11.0), (1.4, 0, 108.0, 6.4), (3.8, 0, 118.0, 3.2), (7.4, 0, 125.0, 1.3), (11.0, 0, 128.0, 0)], 12)
cyl("Gold", 11.6, 94.6, 96.6, 0.3, 0, 12)
gem("Glow", 0.3 + 11.4, 0, 95.6, 1.5, 3.2)
gem("Glow", 0.3 - 11.4, 0, 95.6, 1.5, 3.2)
gem("Glow", 0.3, 11.4, 95.6, 1.5, 3.2)
gem("Glow", 0.3, -11.4, 95.6, 1.5, 3.2)
# cristal flutuando acima da ponta, com um anel inclinado
gem("Glow", 0, 0, 139.0, 3.6, 13.0, 6)
Mring = Matrix.Translation((0, 0, 139.0)) @ Matrix.Rotation(math.radians(24), 4, 'X')
for i in range(20):
    a = 2 * math.pi * i / 20
    box("Gold", (2.5, 0.7, 0.7), (0, 0, 0), Mring @ Matrix.Rotation(a, 4, 'Z') @ Matrix.Translation((0, 7.6, 0)))
Mring2 = Matrix.Translation((0, 0, 139.0)) @ Matrix.Rotation(math.radians(-58), 4, 'Y')
for i in range(16):
    a = 2 * math.pi * i / 16
    box("Gold", (2.1, 0.5, 0.5), (0, 0, 0), Mring2 @ Matrix.Rotation(a, 4, 'Z') @ Matrix.Translation((0, 5.2, 0)))

# ---------------------------------------------------------------- interior
loft("Floor", [(0, 0, FLOOR, 22.0), (0, 0, FLOOR + 0.12, 22.0)], 24)
for (rad, kind, n, w) in ((22.0, "Gold", 32, 0.7), (15.0, "Glow", 28, 0.45), (9.5, "Gold", 20, 0.5)):
    for i in range(n):
        a = 2 * math.pi * i / n
        L = 2 * rad * math.sin(math.pi / n) + 0.1
        box(kind, (L, w, 0.16), (rad * math.cos(a), rad * math.sin(a), FLOOR + 0.16), Matrix.Rotation(a + math.pi / 2, 4, 'Z'))
for i in range(8):  # estrela de oito pontas entre os anéis
    a = 2 * math.pi * i / 8
    b = a + 2 * math.pi * 3 / 8
    p0 = Vector((15.0 * math.cos(a), 15.0 * math.sin(a), FLOOR + 0.16))
    p1 = Vector((15.0 * math.cos(b), 15.0 * math.sin(b), FLOOR + 0.16))
    d = p1 - p0
    box("Glow", (d.length, 0.35, 0.14), (0, 0, 0), Matrix.Translation((p0 + p1) / 2) @ Matrix.Rotation(math.atan2(d.y, d.x), 4, 'Z'))
cyl("Dark", 7.0, FLOOR, FLOOR + 1.0, segs=8, phase=math.pi / 8)
cyl("Gold", 6.2, FLOOR + 1.0, FLOOR + 1.4, segs=8, phase=math.pi / 8)
cyl("Stone", 5.4, FLOOR + 1.4, FLOOR + 2.2, segs=8, phase=math.pi / 8)
gem("Glow", 0, 0, FLOOR + 10.5, 3.0, 11.0, 6)
for i in range(4):
    a = math.pi / 4 + i * math.pi / 2
    gem("Glow", 5.6 * math.cos(a), 5.6 * math.sin(a), FLOOR + 6.0, 0.9, 3.0, 6)
for sx in (-1, 1):
    for sy in (-1, 1):
        x, y = sx * 17.5, sy * 17.5
        cyl("Dark", 2.6, FLOOR, FLOOR + 1.8, x, y, 8)
        cyl("Stone", 1.7, FLOOR + 1.8, TOP - 2.4, x, y, 8)
        cyl("Gold", 2.0, 14.0, 14.7, x, y, 8)
        loft("Dark", [(x, y, TOP - 3.4, 1.7), (x, y, TOP - 1.0, 3.2)], 8)
        box("Gold", (0.3, 0.3, 2.2), (x - sx * 2.6, y - sy * 2.6, 20.0))
        box("Glow", (1.2, 1.2, 1.8), (x - sx * 2.6, y - sy * 2.6, 18.2))
for off in (-17.5, 17.5):  # vigas do forro
    box("Wood", (HALF * 2 - 6, 1.6, 1.8), (0, off, TOP - 1.9))
    box("Wood", (1.6, HALF * 2 - 6, 1.8), (off, 0, TOP - 1.9))
# lustre
cyl("Gold", 0.25, 25.0, TOP - 1.0, segs=6)
for i in range(16):
    a = 2 * math.pi * i / 16
    box("Gold", (2.45, 0.5, 0.5), (6.0 * math.cos(a), 6.0 * math.sin(a), 25.0), Matrix.Rotation(a + math.pi / 2, 4, 'Z'))
for i in range(4):
    a = i * math.pi / 2
    box("Gold", (12.0, 0.3, 0.3), (0, 0, 25.0), Matrix.Rotation(a, 4, 'Z')) if i < 2 else None
    box("Glow", (1.0, 1.0, 1.6), (6.0 * math.cos(a), 6.0 * math.sin(a), 26.2))
    box("Glow", (1.0, 1.0, 1.6), (6.0 * math.cos(a + math.pi / 4), 6.0 * math.sin(a + math.pi / 4), 26.2))

# ---------------------------------------------------------------- objetos
COL = {"Stone": (0.62, 0.6, 0.85, 1), "Dark": (0.12, 0.13, 0.35, 1), "Roof": (0.42, 0.18, 0.72, 1), "Gold": (0.95, 0.7, 0.2, 1), "Glass": (0.4, 0.75, 1, 1), "Glow": (0.5, 1, 0.95, 1), "Wood": (0.35, 0.22, 0.12, 1), "Floor": (0.2, 0.2, 0.5, 1)}
report = []
for kind, bm in K.items():
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.triangulate(bm, faces=bm.faces)
    me = bpy.data.meshes.new(kind + "_sanctum")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(kind + "_sanctum", me)
    bpy.context.collection.objects.link(ob)
    mat = bpy.data.materials.get("M_" + kind) or bpy.data.materials.new("M_" + kind)
    mat.diffuse_color = COL[kind]
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = COL[kind]
    if kind in ("Glass", "Glow"):
        bsdf.inputs["Emission Color"].default_value = COL[kind]
        bsdf.inputs["Emission Strength"].default_value = 3
    me.materials.append(mat)
    report.append((kind, len(me.polygons)))
print(report)
allv = [ob.matrix_world @ v.co for ob in bpy.data.objects for v in ob.data.vertices]
print("bbox", [round(min(v[i] for v in allv), 1) for i in range(3)], [round(max(v[i] for v in allv), 1) for i in range(3)])

# ---------------------------------------------------------------- exporta
import os
OUT = os.environ.get("SANCTUM_OUT", r"E:\Projetos roblox\Teste_foda\assets\models\sanctum.fbx")
bpy.ops.object.select_all(action="DESELECT")
for ob in bpy.data.objects:
    ob.select_set(True)
bpy.ops.export_scene.fbx(filepath=OUT, use_selection=True, object_types={"MESH"}, apply_scale_options="FBX_SCALE_ALL",
    axis_forward="-Z", axis_up="Y", bake_space_transform=True, mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False)
print("exportado", OUT, os.path.getsize(OUT))
