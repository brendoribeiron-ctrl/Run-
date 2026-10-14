# Sala do chefe: rotunda no fim de cada corredor (src/server/BossRoom.luau), no estilo do salão
# do trono do Igris (Solo Leveling): pedra azul-aço, frisos dourados, detalhes carmesim, pilares
# altos com capitel de coroa dourada, arcos ogivais, janelas altas acesas, piso em painéis com
# moldura dourada, cúpula com nervuras e óculo, trono num estrado. No centro, o círculo mágico
# onde o chefe dorme. O jogo pinta pelo nome: o mesmo modelo serve a todos os mundos.
#
# Eixos: X = direita, Y = para dentro da sala (a porta fica em -Y, o trono em +Y), Z = cima.
# O piso fica em Z = 0 e o centro da sala na origem. Medidas em studs.
#
#   blender -b --factory-startup -P tools/blender/boss_room.py
#
# Exporta assets/models/boss_room.fbx e salva E:\Projetos roblox\Blender\Sala do Chefe\boss_room.blend.

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODELS = os.path.join(ROOT, "assets", "models")
BLEND = r"E:\Projetos roblox\Blender\Sala do Chefe\boss_room.blend"
SNAP = os.environ.get("SNAP")

COLORS = {
    "Stone": (0.2, 0.26, 0.48, 1), "Dark": (0.06, 0.08, 0.2, 1), "Path": (0.5, 0.56, 0.74, 1), "Tile": (0.1, 0.14, 0.34, 1),
    "Dome": (0.13, 0.17, 0.36, 1), "Gold": (0.95, 0.7, 0.25, 1), "Inlay": (0.95, 0.7, 0.25, 1), "Crimson": (0.75, 0.06, 0.12, 1), "Banner": (0.55, 0.05, 0.1, 1),
    "Glass": (0.75, 0.85, 1.0, 1), "Flame": (1.0, 0.6, 0.15, 1), "Rune": (0.45, 0.75, 1.0, 1), "Wax": (0.9, 0.86, 0.78, 1),
    "DoorL": (0.08, 0.1, 0.24, 1), "DoorR": (0.08, 0.1, 0.24, 1), "DoorLGold": (0.95, 0.7, 0.25, 1), "DoorRGold": (0.95, 0.7, 0.25, 1),
    "Pivot": (1, 0, 1, 1), "MarkX": (1, 0, 1, 1), "MarkY": (1, 0, 1, 1),
}
GLOW = ("Glass", "Flame", "Rune", "Crimson")

R_WALL = 64.0  # face de dentro da parede
WALL_T = 4.0
WALL_H = 60.0
R_PILLAR = 52.0
N = 16  # vãos em volta da sala
BAY = 2 * math.pi / N
DOOR_W, DOOR_H = 16.0, 28.0
DOME_H = 42.0  # quanto a cúpula sobe acima do topo da parede
OCULUS = 11.0

kit.clean_scene()
k = kit.Kit("boss_room")


def polar(r, a, z=0.0):
    return Vector((r * math.cos(a), r * math.sin(a), z))


def bay_angle(i):
    """Centro do vão i. O vão 0 é a porta (-Y); o 8 é o trono (+Y)."""
    return -math.pi / 2 + i * BAY


def pillar_angle(i):
    return bay_angle(i) + BAY / 2


def facing(a):
    """Matriz que leva X local para a tangente da sala e Y local para fora, no ângulo a."""
    return Matrix.Rotation(a - math.pi / 2, 4, "Z")


def sector(kind, r1, r2, a1, a2, z0, z1, segs=6):
    pts = [(r2 * math.cos(a1 + (a2 - a1) * t / segs), r2 * math.sin(a1 + (a2 - a1) * t / segs)) for t in range(segs + 1)]
    pts += [(r1 * math.cos(a2 - (a2 - a1) * t / segs), r1 * math.sin(a2 - (a2 - a1) * t / segs)) for t in range(segs + 1)]
    k.slab(kind, pts, z0, z1)


def strip(kind, a, b, width, z0, z1):
    """Faixa reta deitada de a até b (pontos 2D)."""
    a, b = Vector((a[0], a[1], 0)), Vector((b[0], b[1], 0))
    d = b - a
    ang = math.atan2(d.y, d.x)
    mid = (a + b) / 2
    k.box(kind, (d.length, width, z1 - z0), (mid.x, mid.y, (z0 + z1) / 2), Matrix.Rotation(ang, 4, "Z"))


def ogee(half, spring, rise, steps=8):
    """Contorno de um arco ogival (pontos u, v) de -half a +half, nascendo em v = spring."""
    pts = []
    # cada metade é um arco de círculo com centro do lado oposto: ponta no meio
    radius = (half * half + rise * rise) / (2 * half)
    for side in (-1, 1):
        cx = -side * (radius - half)
        seq = range(steps + 1) if side == -1 else range(steps, -1, -1)
        for s in seq:
            # de baixo (u = side*half) até a ponta (u = 0, v = spring + rise)
            t = s / steps
            u_end, v_end = 0.0, rise
            a0 = math.atan2(0, side * half - cx)
            a1 = math.atan2(v_end, u_end - cx)
            a = a0 + (a1 - a0) * t
            pts.append((cx + radius * math.cos(a), spring + radius * math.sin(a)))
    return pts


# ================================================================================ piso
def floor():
    k.cyl("Path", R_WALL + WALL_T, -2.0, 0.0, segs=48)
    # painéis escuros com moldura dourada em dois anéis, cortados pelos caminhos radiais
    for r1, r2 in ((17.0, 31.0), (34.0, 48.0)):
        for i in range(N):
            a1 = bay_angle(i) - BAY / 2 + 0.05 * 22 / r2
            a2 = bay_angle(i) + BAY / 2 - 0.05 * 22 / r2
            gap = 1.3 / r1
            sector("Inlay", r1, r2, a1 + gap, a2 - gap, 0.0, 0.1)
            inner_gap = gap + 0.5 / r1
            sector("Tile", r1 + 0.5, r2 - 0.5, a1 + inner_gap, a2 - inner_gap, 0.0, 0.14)
            # losango dourado no meio de cada painel
            c = polar((r1 + r2) / 2, bay_angle(i))
            s = (r2 - r1) * 0.22
            k.slab("Inlay", [(c.x + s, c.y), (c.x, c.y + s), (c.x - s, c.y), (c.x, c.y - s)], 0.0, 0.2)
    # anéis dourados que separam os anéis de painéis
    for r in (15.5, 32.5, 49.5):
        sector("Inlay", r - 0.35, r + 0.35, 0, 2 * math.pi, 0.0, 0.12, 64)
    # caminho da porta ao centro: duas linhas douradas
    for side in (-1, 1):
        strip("Inlay", (side * 4.2, -R_WALL), (side * 4.2, -15.5), 0.4, 0.0, 0.12)


def magic_circle():
    """Estrado redondo no centro: o chefe dorme aqui. Runas acesas em cima."""
    k.cyl("Stone", 15.0, 0.0, 0.5, segs=40)
    k.cyl("Stone", 13.5, 0.5, 1.1, segs=40)
    k.cyl("Inlay", 13.6, 1.0, 1.15, segs=40)
    top = 1.1
    for r, w in ((12.4, 0.45), (10.6, 0.25), (6.2, 0.3), (2.2, 0.3)):
        sector("Rune", r - w, r + w, 0, 2 * math.pi, top, top + 0.08, 48)
    # hexagrama: dois triângulos de linhas
    for rot in (0.0, math.pi):
        pts = [(10.6 * math.cos(rot + math.pi / 2 + j * 2 * math.pi / 3), 10.6 * math.sin(rot + math.pi / 2 + j * 2 * math.pi / 3)) for j in range(3)]
        for j in range(3):
            strip("Rune", pts[j], pts[(j + 1) % 3], 0.3, top, top + 0.08)
    # marcas entre os dois anéis de fora
    for j in range(24):
        a = j * 2 * math.pi / 24
        strip("Rune", (11.0 * math.cos(a), 11.0 * math.sin(a)), (12.0 * math.cos(a), 12.0 * math.sin(a)), 0.22, top, top + 0.08)
    # quatro pedras de runa em volta do estrado
    for j in range(4):
        a = math.pi / 4 + j * math.pi / 2
        p = polar(17.5, a)
        k.box("Dark", (1.6, 1.6, 3.0), (p.x, p.y, 1.5), Matrix.Rotation(a, 4, "Z"))
        k.gem("Rune", p.x, p.y, 3.9, 0.7, 1.8, 4)


# ================================================================================ pilares e arcos
def pillar(a):
    c = polar(R_PILLAR, a)
    rot = facing(a)
    k.box("Stone", (5.4, 5.4, 2.2), (c.x, c.y, 1.1), rot)
    k.box("Gold", (5.0, 5.0, 0.5), (c.x, c.y, 2.45), rot)
    k.box("Stone", (4.4, 4.4, 1.0), (c.x, c.y, 3.2), rot)
    top = 40.0
    k.cyl("Stone", 1.55, 3.7, top, c.x, c.y, 10)
    for j in range(4):
        off = polar(1.45, a + math.pi / 4 + j * math.pi / 2)
        k.cyl("Stone", 0.75, 3.7, top, c.x + off.x, c.y + off.y, 8)
    for z in (14.0, 27.0):
        k.cyl("Gold", 2.35, z, z + 0.6, c.x, c.y, 12)
    # fenda carmesim emoldurada de ouro na face de dentro
    inward = polar(-2.1, a)
    for lo, hi in ((16.0, 25.0), (29.0, 37.0)):
        k.box("Gold", (1.3, 0.3, hi - lo + 1.0), (c.x + inward.x, c.y + inward.y, (lo + hi) / 2), rot)
        k.box("Crimson", (0.7, 0.4, hi - lo), (c.x + inward.x * 1.04, c.y + inward.y * 1.04, (lo + hi) / 2), rot)
    # capitel em coroa
    k.loft("Gold", [(c.x, c.y, top, 1.9), (c.x, c.y, top + 1.4, 3.2), (c.x, c.y, top + 2.0, 3.2), (c.x, c.y, top + 2.4, 2.4),
                    (c.x, c.y, top + 3.6, 3.7), (c.x, c.y, top + 4.2, 3.7), (c.x, c.y, top + 4.6, 2.6)], 12)
    k.cyl("Dark", 2.7, top + 2.0, top + 3.4, c.x, c.y, 12)
    for j in range(8):
        p = polar(3.1, a + j * math.pi / 4)
        k.gem("Gold", c.x + p.x, c.y + p.y, top + 5.4, 0.45, 2.2, 4)
    k.box("Stone", (4.0, 4.0, 1.4), (c.x, c.y, top + 5.2), rot)
    # viga que liga o capitel à parede, por onde a nervura da cúpula começa
    w = polar(R_WALL + 0.5, a, top + 6.5)
    k.tube("Stone", [(c.x, c.y, top + 5.5), (w.x, w.y, w.z)], [1.0, 1.0], 8)
    # lanterna dourada pendurada do lado de dentro
    lp = polar(R_PILLAR - 3.2, a)
    k.tube("Gold", [(c.x + inward.x, c.y + inward.y, 33.5), (lp.x, lp.y, 33.5), (lp.x, lp.y, 32.0)], [0.15, 0.15, 0.15], 6)
    z = 29.0
    k.loft("Gold", [(lp.x, lp.y, z - 0.8, 0), (lp.x, lp.y, z - 0.2, 0.9), (lp.x, lp.y, z + 0.1, 0.9), (lp.x, lp.y, z + 0.3, 0.6)], 8)
    k.loft("Gold", [(lp.x, lp.y, z + 2.4, 0.6), (lp.x, lp.y, z + 2.7, 1.0), (lp.x, lp.y, z + 3.0, 0.4), (lp.x, lp.y, z + 3.6, 0)], 8)
    for j in range(4):
        q = polar(0.8, a + j * math.pi / 2)
        k.cyl("Gold", 0.1, z + 0.2, z + 2.5, lp.x + q.x, lp.y + q.y, 4)
    k.gem("Flame", lp.x, lp.y, z + 1.3, 0.55, 2.0, 6)


def arcade():
    """Arcos ogivais entre um pilar e o próximo, com friso dourado por baixo."""
    for i in range(N):
        a1, a2 = pillar_angle(i - 1), pillar_angle(i)
        p1, p2 = polar(R_PILLAR, a1), polar(R_PILLAR, a2)
        mid = (p1 + p2) / 2
        half = (p2 - p1).length / 2 - 2.0
        along = (p2 - p1).normalized()
        pts = ogee(half, 45.0, 9.5, 8)
        line = [mid + along * u + Vector((0, 0, v)) for u, v in pts]
        k.tube("Stone", line, [1.15] * len(line), 8)
        k.tube("Gold", [p - mid.normalized() * 0.9 + Vector((0, 0, -0.9)) for p in line], [0.32] * len(line), 6)
        # pingente carmesim na ponta do arco
        tip = line[len(line) // 2]
        k.gem("Crimson", tip.x, tip.y, tip.z - 2.2, 0.5, 2.6, 4)


def banner(a):
    c = polar(R_PILLAR - 2.6, a)
    rot = facing(a)
    k.box("Gold", (4.2, 0.4, 0.4), (c.x, c.y, 39.6), rot)
    k.box("Banner", (3.4, 0.25, 9.0), (c.x, c.y, 34.8), rot)
    m = Matrix.Translation(Vector((c.x, c.y, 30.3))) @ rot @ Matrix.Translation(Vector((0, -0.125, 0)))
    k.prism("Banner", [(-1.7, 0), (1.7, 0), (0, -2.2)], 0.25, m)
    k.gem("Gold", c.x, c.y, 35.6, 0.85, 2.4, 4, matrix=None)


# ================================================================================ parede
def window(a):
    rot = facing(a)
    base = polar(R_WALL - 0.1, a)
    m = Matrix.Translation(base) @ rot
    w, lo, spring, rise = 7.0, 10.0, 38.0, 7.0
    outline = [(-w / 2, lo)] + ogee(w / 2, spring, rise, 6) + [(w / 2, lo)]
    k.prism("Glass", outline, 0.8, m @ Matrix.Translation(Vector((0, -0.4, 0))))
    # moldura dourada e grade escura
    frame = [Vector((u, -0.7, v)) for u, v in outline] + [Vector((-w / 2, -0.7, lo))]
    k.tube("Gold", [m @ p for p in frame], [0.35] * len(frame), 6)
    k.box("Dark", (0.35, 0.5, spring + rise - lo - 1.0), (m @ Vector((0, -0.6, (lo + spring + rise) / 2 - 0.5))).to_tuple(), rot)
    for v in (16.0, 22.0, 28.0, 34.0):
        k.box("Dark", (w, 0.5, 0.3), (m @ Vector((0, -0.6, v))).to_tuple(), rot)
    # peitoril
    k.box("Stone", (w + 2.0, 1.6, 1.0), (m @ Vector((0, -1.6, lo - 0.5))).to_tuple(), rot)


def bay_wall(i):
    a = bay_angle(i)
    rot = facing(a)
    chord = 2 * (R_WALL + WALL_T) * math.tan(BAY / 2) + 0.6
    center = polar(R_WALL + WALL_T / 2, a)
    m = Matrix.Translation(center) @ rot
    if i == 0:
        # vão da porta: parede em volta da abertura ogival
        outline_hole = ogee(DOOR_W / 2, DOOR_H - 10.0, 10.0, 8)
        left = [(-chord / 2, 0), (-DOOR_W / 2, 0)] + outline_hole[: len(outline_hole) // 2] + [(0, WALL_H), (-chord / 2, WALL_H)]
        right = [(DOOR_W / 2, 0), (chord / 2, 0), (chord / 2, WALL_H), (0, WALL_H)] + outline_hole[len(outline_hole) // 2:]
        for poly in (left, right):
            k.prism("Stone", poly, WALL_T, m @ Matrix.Translation(Vector((0, -WALL_T / 2, 0))))
        doorway(m, rot, outline_hole)
        return
    k.box("Stone", (chord, WALL_T, WALL_H), (center.x, center.y, WALL_H / 2), rot)
    # rodapé e cornija
    inner = polar(R_WALL - 0.4, a)
    k.box("Dark", (chord, 1.0, 2.0), (inner.x, inner.y, 1.0), rot)
    k.box("Gold", (chord, 0.6, 0.5), (inner.x, inner.y, 2.2), rot)
    k.box("Gold", (chord, 1.2, 0.8), (inner.x, inner.y, WALL_H - 0.4), rot)
    if i == N // 2:
        throne_panel(a)
    else:
        window(a)
        # placa de pedra escura com losango carmesim embaixo da janela
        low = polar(R_WALL - 0.3, a)
        k.box("Dark", (9.0, 0.6, 6.0), (low.x, low.y, 5.5), rot)
        k.gem("Crimson", low.x, low.y, 5.5, 1.2, 3.6, 4)


def doorway(m, rot, hole):
    # moldura dourada da porta e emblema em cima
    frame = [Vector((u, -WALL_T / 2 - 0.4, v)) for u, v in [(-DOOR_W / 2, 0)] + hole + [(DOOR_W / 2, 0)]]
    k.tube("Gold", [m @ p for p in frame], [0.5] * len(frame), 6)
    k.gem("Crimson", *(m @ Vector((0, -WALL_T / 2 - 0.6, DOOR_H + 3.0))).to_tuple(), 1.5, 4.0, 4)
    # duas folhas da porta, cada uma num objeto (o jogo gira cada uma pela dobradiça)
    for name, side in (("DoorL", -1), ("DoorR", 1)):
        leaf = [(0, 0), (side * DOOR_W / 2, 0)]
        tip = [p for p in hole if (p[0] * side) >= -1e-6]
        tip = sorted(tip, key=lambda p: -p[0] * side)
        leaf += [(p[0], p[1]) for p in tip]
        leaf = [(u, v) for u, v in leaf]
        if side == -1:
            leaf = list(reversed(leaf))
        k.prism(name, leaf, 1.2, m @ Matrix.Translation(Vector((0, -0.6, 0))))
        gold = name + "Gold"
        hinge = side * DOOR_W / 2
        for v in (5.0, 13.0, 21.0):
            k.box(gold, (DOOR_W / 2 - 1.0, 0.3, 0.6), (m @ Vector((hinge / 2, -1.3, v))).to_tuple(), rot)
        k.box(gold, (0.6, 0.3, DOOR_H - 4.0), (m @ Vector((side * 0.6, -1.3, (DOOR_H - 4.0) / 2))).to_tuple(), rot)
        k.gem(gold, *(m @ Vector((side * 3.5, -1.5, 11.0))).to_tuple(), 0.9, 2.6, 4)


def throne_panel(a):
    """Painel atrás do trono: arco escuro com filigrana dourada e fendas carmesim."""
    rot = facing(a)
    base = polar(R_WALL - 0.8, a)
    m = Matrix.Translation(base) @ rot
    outline = [(-11.0, 0.0)] + ogee(11.0, 34.0, 14.0, 8) + [(11.0, 0.0)]
    k.prism("Dark", outline, 1.0, m @ Matrix.Translation(Vector((0, -0.5, 0))))
    edge = [Vector((u, -0.6, v)) for u, v in outline] + [Vector((-11.0, -0.6, 0.0))]
    k.tube("Gold", [m @ p for p in edge], [0.45] * len(edge), 6)
    for u, lo, hi in ((-6.5, 12.0, 30.0), (6.5, 12.0, 30.0), (0.0, 30.0, 42.0)):
        k.box("Gold", (1.6, 0.4, hi - lo + 1.2), (m @ Vector((u, -0.8, (lo + hi) / 2))).to_tuple(), rot)
        k.box("Crimson", (0.9, 0.5, hi - lo), (m @ Vector((u, -1.0, (lo + hi) / 2))).to_tuple(), rot)
    # filigrana: dois S espelhados subindo do trono
    for side in (-1, 1):
        pts = []
        for s in range(13):
            t = s / 12
            u = side * (2.5 + 3.5 * math.sin(t * math.pi * 1.5))
            pts.append(m @ Vector((u, -0.9, 14.0 + 26.0 * t)))
        k.tube("Gold", pts, [0.3] * len(pts), 6)
    k.gem("Crimson", *(m @ Vector((0, -1.1, 22.0))).to_tuple(), 2.0, 5.5, 4)


# ================================================================================ trono
def throne():
    y0 = 36.0
    steps = ((34.0, 20.0, 1.0), (28.0, 15.0, 2.0), (22.0, 11.0, 3.0))
    for width, depth, z in steps:
        k.box("Stone", (width, depth, z), (0, y0 + depth / 2, z / 2))
        k.box("Gold", (width, 0.4, 0.2), (0, y0 + 0.2, z - 0.05))
    # velas na frente de cada degrau
    for width, depth, z in steps:
        for s in range(-3, 4):
            if s == 0:
                continue
            x = s * width / 8
            k.cyl("Wax", 0.25, z, z + 1.2 + 0.3 * abs(s % 2), x, y0 + 1.0, 6)
            k.gem("Flame", x, y0 + 1.0, z + 1.75 + 0.3 * abs(s % 2), 0.22, 0.8, 4)
    # o trono
    ty = y0 + 8.0
    k.box("Dark", (6.0, 4.6, 2.0), (0, ty, 4.0))
    k.box("Gold", (6.4, 5.0, 0.4), (0, ty, 5.1))
    k.box("Banner", (5.2, 4.0, 0.5), (0, ty, 5.5))
    for side in (-1, 1):
        k.box("Dark", (1.0, 4.6, 3.4), (side * 3.4, ty, 5.6))
        k.gem("Gold", side * 3.4, ty - 2.0, 7.6, 0.6, 1.6, 4)
    back = Matrix.Translation(Vector((0, ty + 2.0, 3.0)))
    k.prism("Dark", [(-3.2, 0), (3.2, 0), (3.2, 10.0), (0, 14.5), (-3.2, 10.0)], 1.0, back)
    k.prism("Gold", [(-3.6, 0), (3.6, 0), (3.6, 10.3), (0, 15.2), (-3.6, 10.3)], 0.4, back @ Matrix.Translation(Vector((0, 1.0, 0))))
    k.gem("Crimson", 0, ty + 1.8, 12.0, 1.1, 3.2, 4)
    for side in (-1, 1):
        k.gem("Gold", side * 3.2, ty + 2.4, 13.6, 0.5, 2.0, 4)
    # dois braseiros altos nas pontas do estrado
    for side in (-1, 1):
        x = side * 15.0
        k.cyl("Stone", 1.0, 1.0, 7.0, x, y0 + 4.0, 8)
        k.loft("Gold", [(x, y0 + 4.0, 7.0, 1.0), (x, y0 + 4.0, 7.8, 2.0), (x, y0 + 4.0, 8.6, 2.2), (x, y0 + 4.0, 8.6, 1.6)], 10)
        k.gem("Flame", x, y0 + 4.0, 9.8, 1.4, 3.4, 6)


# ================================================================================ cúpula
def dome_point(r_frac, a, inset=0.0):
    """Ponto da cúpula: r_frac 1 = beira (topo da parede), 0 = eixo. inset puxa para dentro."""
    phi = math.acos(max(min(r_frac, 1.0), 0.0))
    r = (R_WALL + 2.0) * math.cos(phi) - inset
    z = WALL_H + DOME_H * math.sin(phi) - inset * math.sin(phi)
    return Vector((r * math.cos(a), r * math.sin(a), z))


def dome():
    segs = 48
    rings = 12
    stop = OCULUS / (R_WALL + 2.0)
    fracs = [1.0 - (1.0 - stop) * j / rings for j in range(rings + 1)]
    inner = [[dome_point(f, 2 * math.pi * i / segs) for i in range(segs)] for f in fracs]
    outer = [[p * 1.0 + Vector((p.x, p.y, 0)).normalized() * 3.0 + Vector((0, 0, 3.0)) for p in ring] for ring in inner]
    bm = k.bm("Dome")
    vi = [[bm.verts.new(p) for p in ring] for ring in inner]
    vo = [[bm.verts.new(p) for p in ring] for ring in outer]
    for j in range(rings):
        for i in range(segs):
            n = (i + 1) % segs
            bm.faces.new((vi[j][i], vi[j][n], vi[j + 1][n], vi[j + 1][i]))
            bm.faces.new((vo[j][n], vo[j][i], vo[j + 1][i], vo[j + 1][n]))
    for j in (0, rings):
        for i in range(segs):
            n = (i + 1) % segs
            bm.faces.new((vi[j][i], vo[j][i], vo[j][n], vi[j][n]))
    # nervuras: uma por pilar, da viga até o óculo, com friso dourado
    for i in range(N):
        a = pillar_angle(i)
        line = [dome_point(1.0 - (1.0 - stop) * t / 14, a, 1.2) for t in range(15)]
        k.tube("Stone", line, [1.3] * len(line), 8)
        k.tube("Inlay", [dome_point(1.0 - (1.0 - stop) * t / 14, a, 2.5) for t in range(15)], [0.35] * 15, 6)
        # losangos carmesim entre as nervuras
        b = bay_angle(i)
        for f in (0.75, 0.45):
            p = dome_point(f, b, 0.9)
            k.gem("Crimson", p.x, p.y, p.z, 1.1, 3.4, 4)
    # óculo: anel dourado e vidro aceso em cima
    top = dome_point(stop, 0)
    k.loft("Inlay", [(0, 0, top.z - 1.0, OCULUS + 1.5), (0, 0, top.z + 1.0, OCULUS + 1.5), (0, 0, top.z + 1.0, OCULUS - 0.5), (0, 0, top.z - 1.0, OCULUS - 0.5)], 32)
    k.cyl("Glass", OCULUS, top.z + 2.5, top.z + 3.2, segs=32)
    for j in range(8):
        a = j * math.pi / 4
        strip("Inlay", (0, 0), ((OCULUS - 0.3) * math.cos(a), (OCULUS - 0.3) * math.sin(a)), 0.4, top.z + 2.2, top.z + 2.5)


# ================================================================================ monta
floor()
magic_circle()
for i in range(N):
    pillar(pillar_angle(i))
    bay_wall(i)
    if i % 2 == 0:
        banner(pillar_angle(i))
arcade()
throne()
dome()
k.build(COLORS, GLOW)
k.export(MODELS)

if SNAP:
    os.makedirs(SNAP, exist_ok=True)
    for ob in k.objects:
        if ob.name.startswith("Dome_"):
            ob.hide_render = True
    kit.snapshot(os.path.join(SNAP, "room_top.png"), (0, -40, 200), (0, 5, 0), 28)
    for ob in k.objects:
        ob.hide_render = False
    kit.snapshot(os.path.join(SNAP, "room_door.png"), (0, -58, 8), (0, 30, 20), 20)
    kit.snapshot(os.path.join(SNAP, "room_throne.png"), (-8, -10, 10), (0, 50, 16), 26)
    kit.snapshot(os.path.join(SNAP, "room_up.png"), (10, -20, 4), (0, 10, 70), 18)
    kit.snapshot(os.path.join(SNAP, "room_out.png"), (0, -160, 70), (0, 0, 40), 35)

os.makedirs(os.path.dirname(BLEND), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=BLEND)
print("projeto salvo em", BLEND)
