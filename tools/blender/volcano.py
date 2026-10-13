# Mundo 2, o vulcão (src/server/Volcano.luau). Quatro modelos, todos em studs:
#
#   volcano_base   a ilha de chegada: praça de basalto com o cristal de magma no centro, obeliscos,
#                  o portal de volta, poças de lava, a muralha de colunas e o portão da pista
#   volcano_track  um trecho de 50 studs da pista (o jogo repete): lajes sobre lava, canais de
#                  lava nas bordas, paredões de colunas de basalto com cachoeira de lava e, no
#                  começo do trecho, um par de chifres de obsidiana com braseiros pendurados
#   volcano_mount  o vulcão do fundo: cone com cratera acesa e rios de lava descendo
#   volcano_spire  agulha de rocha para espalhar pelo mar de lava
#
# Eixos: X = direita, Y = para dentro da pista, Z = cima. O chão onde se pisa fica em Z = 0.
#
#   blender -b --factory-startup -P tools/blender/volcano.py
#
# Exporta os .fbx em assets/models/ e salva E:\Projetos roblox\Blender\Mundo 2 Vulcao\volcano.blend.

import math
import os
import random
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODELS = os.path.join(ROOT, "assets", "models")
BLEND = r"E:\Projetos roblox\Blender\Mundo 2 Vulcao\volcano.blend"
SNAP = os.environ.get("SNAP")

COLORS = {
    "Rock": (0.17, 0.13, 0.15, 1), "RockDark": (0.09, 0.07, 0.09, 1), "Basalt": (0.24, 0.2, 0.22, 1), "BasaltDark": (0.15, 0.12, 0.14, 1),
    "Obsidian": (0.05, 0.03, 0.09, 1), "Lava": (1.0, 0.36, 0.04, 1), "Ember": (1.0, 0.62, 0.1, 1), "Flame": (1.0, 0.75, 0.2, 1),
    "Crystal": (1.0, 0.25, 0.08, 1), "Iron": (0.08, 0.08, 0.1, 1), "Gold": (0.95, 0.7, 0.2, 1), "Portal": (0.35, 0.85, 1.0, 1), "Board": (0.07, 0.05, 0.08, 1),
    "Pivot": (1, 0, 1, 1), "MarkX": (1, 0, 1, 1), "MarkY": (1, 0, 1, 1),
}
GLOW = ("Lava", "Ember", "Flame", "Crystal", "Portal")
HEX = math.pi / 6  # coluna de basalto: seis lados, um deles de frente

kit.clean_scene()


def column(k, rnd, x, y, r, z0, z1):
    k.cyl("Rock" if rnd.random() < 0.6 else "RockDark", r, z0, z1, x, y, 6, phase=HEX)


def band(k, kind, a, b, at, r, length=0.9):
    """Anel curto em volta de um tubo, no ponto `at` (0-1) entre a e b."""
    a, b = Vector(a), Vector(b)
    mid = a.lerp(b, at)
    half = (b - a).normalized() * length / 2
    k.tube(kind, [mid - half, mid + half], [r, r], 8)


def brazier(k, x, y, z, size=1.0):
    k.loft("Iron", [(x, y, z, 0.3 * size), (x, y, z + 0.7 * size, 1.5 * size), (x, y, z + 1.4 * size, 1.75 * size), (x, y, z + 1.4 * size, 1.4 * size), (x, y, z + 0.9 * size, 0.6 * size)], 8)
    k.gem("Flame", x, y, z + 2.3 * size, 0.95 * size, 2.6 * size, 5)
    k.gem("Ember", x, y, z + 2.0 * size, 1.25 * size, 1.5 * size, 5)


# ============================================================================== pista (um trecho)
def build_track():
    t = kit.Kit("volcano_track")
    rnd = random.Random(3)
    LENGTH = 50.0

    # lava por baixo de tudo: aparece nas frestas das lajes e nos dois canais
    t.box("Lava", (50, LENGTH, 0.4), (0, LENGTH / 2, -0.75))

    # lajes: grade torta, com fresta entre elas
    xs = [-20.0, -10.0 + rnd.uniform(-1.5, 1.5), rnd.uniform(-1.5, 1.5), 10.0 + rnd.uniform(-1.5, 1.5), 20.0]
    ys = [0.0] + [LENGTH * i / 5 + rnd.uniform(-1.8, 1.8) for i in range(1, 5)] + [LENGTH]
    gap = 0.2
    for i in range(4):
        for j in range(5):
            x0, x1, y0, y1 = xs[i] + gap, xs[i + 1] - gap, ys[j] + gap, ys[j + 1] - gap
            top = -rnd.uniform(0.0, 0.07)
            t.box("Basalt" if (i + j) % 2 == 0 else "BasaltDark", (x1 - x0, y1 - y0, 1.3), ((x0 + x1) / 2, (y0 + y1) / 2, top - 0.65))

    for side in (-1, 1):
        # meio-fio de obsidiana, em pedras de tamanhos diferentes
        y = 0.0
        while y < LENGTH - 0.01:
            step = min(rnd.uniform(5, 9), LENGTH - y)
            t.box("Obsidian", (rnd.uniform(1.3, 1.7), step - 0.25, rnd.uniform(1.7, 2.3)), (side * 20.9, y + step / 2, 0.0))
            y += step

        # paredão: quatro fileiras de colunas, mais altas quanto mais longe da pista
        fall_y = 37.5
        pitch = LENGTH / 14
        radius = pitch / math.sqrt(3)
        for row in range(4):
            for n in range(14):
                cy = (n + 0.5 + 0.5 * (row % 2)) * pitch
                height = (9, 17, 25, 33)[row] + rnd.uniform(-3, 8)
                if abs(cy - fall_y) < 3.4 and row < 3:
                    height = (5, 15, 24)[row] + rnd.uniform(0, 1.5)  # rebaixo por onde a lava desce
                column(t, rnd, side * (26.3 + row * pitch * 0.9), cy, radius, -3, height)
        # cachoeira de lava: nasce no alto do paredão e cai no canal
        t.tube("Lava", [(side * 36, fall_y, 31), (side * 32, fall_y, 26.5), (side * 29, fall_y, 17.5), (side * 26.3, fall_y, 7.5), (side * 23.6, fall_y, -0.5)], [1.9, 1.8, 1.7, 1.7, 2.3], 6)
        t.cyl("Lava", 3.0, -0.6, -0.42, side * 23.0, fall_y, 8)  # espirro onde ela bate

        # cristais de magma no pé do paredão
        for cy in (7.5, 21.0, 46.0):
            for _ in range(3):
                lean = Matrix.Translation((side * (23.4 + rnd.uniform(-0.5, 0.6)), cy + rnd.uniform(-1.4, 1.4), -0.4)) @ Matrix.Rotation(rnd.uniform(-0.45, 0.45), 4, "Y") @ Matrix.Rotation(rnd.uniform(-0.45, 0.45), 4, "X")
                h = rnd.uniform(2.2, 4.6)
                t.loft("Crystal", [(0, 0, 0, h * 0.2), (0, 0, h * 0.7, h * 0.16), (0, 0, h, 0)], 5, matrix=lean)

        # chifre de obsidiana no começo do trecho, curvando para cima da pista
        pts = [(side * 24.6, 0, -1.5), (side * 26.0, 0, 9), (side * 24.5, 0, 20), (side * 19.5, 0, 29.5), (side * 12.5, 0, 35.5), (side * 6.0, 0, 37.5)]
        t.tube("Obsidian", pts, [2.7, 2.4, 2.0, 1.5, 0.9, 0], 7)
        band(t, "Ember", pts[1], pts[2], 0.3, 2.55)
        band(t, "Ember", pts[2], pts[3], 0.55, 1.95)
        t.tube("Obsidian", [(side * 27.5, 2.2, -1), (side * 29.5, 2.6, 7), (side * 29.0, 2.4, 13)], [1.5, 1.0, 0], 6)  # espinho menor ao lado
        # braseiro pendurado
        bx = side * 14.0
        t.box("Iron", (0.22, 0.22, 10.5), (bx, 0, 29.2))
        brazier(t, bx, 0, 22.4)

    t.build(COLORS, GLOW)
    t.export(MODELS)
    if SNAP:
        kit.snapshot(os.path.join(SNAP, "track_a.png"), (0, -42, 16), (0, 25, 8), 28)
        kit.snapshot(os.path.join(SNAP, "track_b.png"), (55, -30, 60), (0, 25, 4), 35)
    return t


# ============================================================================== ilha de chegada
def build_base():
    b = kit.Kit("volcano_base")
    rnd = random.Random(11)
    R = 85.0

    # a ilha: tronco de rocha que afunda na lava; o topo fica um fio abaixo de onde se pisa
    b.loft("Rock", [(0, 0, -18, 99), (0, 0, -6, 92), (0, 0, -0.12, R)], 30, wobble=lambda ring, i: 1 + 0.045 * math.sin(i * 2.3 + ring))

    # praça: três discos e o anel de runas de lava
    b.cyl("Basalt", 31, -0.5, -0.03, segs=36)
    b.cyl("BasaltDark", 21, -0.5, -0.015, segs=30)
    b.cyl("Obsidian", 10, -0.5, 0.0, segs=24)
    for n in range(24):
        a = n * 2 * math.pi / 24
        b.box("Lava", (3.2, 0.9, 0.4), (0, 0, 0), Matrix.Rotation(a, 4, "Z") @ Matrix.Translation((0, 26, -0.19)))
        if n % 2 == 0:
            b.box("Lava", (0.7, 3.0, 0.4), (0, 0, 0), Matrix.Rotation(a, 4, "Z") @ Matrix.Translation((0, 15.5, -0.185)))
    # veios de lava da praça até a borda (menos na direção do portão, onde passa o caminho)
    for n in range(8):
        if n == 2:
            continue
        a = n * math.pi / 4
        b.box("Lava", (1.1, 46, 0.4), (0, 0, 0), Matrix.Rotation(a - math.pi / 2, 4, "Z") @ Matrix.Translation((0, 55, -0.26)))
        b.cyl("Lava", 2.4, -0.4, -0.06, math.cos(a) * 55, math.sin(a) * 55, 6, phase=a)

    # caminho de lajes até o portão
    y = 31.0
    while y < 86:
        step = rnd.uniform(6.5, 9.5)
        cut = rnd.uniform(-3, 3)
        for x0, x1 in ((-12, cut - 0.2), (cut + 0.2, 12)):
            b.box("Basalt" if rnd.random() < 0.5 else "BasaltDark", (x1 - x0, step - 0.4, 0.5), ((x0 + x1) / 2, y + step / 2, -0.25 - rnd.uniform(0, 0.03)))
        y += step

    # cristal de magma flutuando no centro, sobre um pedestal
    b.loft("Obsidian", [(0, 0, 0, 5.2), (0, 0, 1.6, 4.4), (0, 0, 2.4, 2.6), (0, 0, 4.2, 2.0), (0, 0, 4.9, 2.8)], 8)
    b.loft("Ember", [(0, 0, 1.6, 4.5), (0, 0, 1.95, 4.2)], 8)
    b.gem("Crystal", 0, 0, 15.5, 3.3, 12.0, 6)
    for n in range(6):
        a = n * math.pi / 3
        b.gem("Crystal", math.cos(a) * 6.2, math.sin(a) * 6.2, 14 + 2.2 * math.sin(n * 2.1), 0.75, 2.6, 5)
    b.gem("Ember", 0, 0, 6.6, 1.1, 1.8, 6)

    # seis obeliscos em volta da praça
    for n in range(6):
        a = n * math.pi / 3 + math.pi / 6
        x, yy = math.cos(a) * 24.5, math.sin(a) * 24.5
        b.loft("Obsidian", [(x, yy, 0, 2.5), (x, yy, 1.2, 2.5), (x, yy, 1.5, 2.0), (x, yy, 15, 1.35), (x, yy, 18.6, 0)], 4, phase=a + math.pi / 4)
        b.loft("Ember", [(x, yy, 6.0, 1.86), (x, yy, 6.5, 1.82)], 4, phase=a + math.pi / 4)
        b.loft("Ember", [(x, yy, 11.0, 1.62), (x, yy, 11.4, 1.59)], 4, phase=a + math.pi / 4)
        b.gem("Ember", x, yy, 20.6, 0.6, 1.7, 4)

    # muralha: duas voltas de colunas, abertas só no portão
    for row, (radius, low, high) in enumerate(((82.0, 5, 13), (86.2, 10, 25))):
        count = int(2 * math.pi * radius / 3.55)
        for n in range(count):
            a = (n + 0.5 * row) * 2 * math.pi / count
            x, yy = math.cos(a) * radius, math.sin(a) * radius
            if yy > 0 and abs(x) < 23:
                continue
            column(b, rnd, x, yy, 2.05, -4, rnd.uniform(low, high))

    # portão: duas torres de colunas, cada uma com lava escorrendo, e dois chifres cruzados em cima
    GATE = 90.0
    for side in (-1, 1):
        cx = side * 31.0
        column(b, rnd, cx, GATE, 4.6, -4, 56)
        for n in range(6):
            a = n * math.pi / 3
            column(b, rnd, cx + math.cos(a) * 7.9, GATE + math.sin(a) * 7.9, 4.6, -4, rnd.uniform(34, 49))
        b.cyl("Lava", 3.6, 55.6, 56.3, cx, GATE, 6, phase=HEX)
        b.tube("Lava", [(cx, GATE - 2, 56.2), (cx, GATE - 5.2, 54), (cx, GATE - 6.4, 44), (cx - side * 1.5, GATE - 9.0, 30), (cx, GATE - 12.2, 12), (cx, GATE - 13.5, -0.3)], [1.2, 1.3, 1.2, 1.1, 1.3, 2.0], 6)
        b.cyl("Lava", 3.4, -0.3, -0.05, cx, GATE - 14.2, 8)
        b.tube("Obsidian", [(side * 25, GATE, 30), (side * 23, GATE, 47), (side * 13, GATE, 59), (-side * 1, GATE, 64), (-side * 9, GATE, 63)], [3.2, 2.9, 2.2, 1.1, 0], 7)
        band(b, "Ember", (side * 23, GATE, 47), (side * 13, GATE, 59), 0.5, 2.75, 1.4)
        b.box("Iron", (0.4, 0.4, 13), (side * 14.5, GATE - 1.5, 51))  # corrente da placa
        brazier(b, side * 19.5, GATE - 12.5, 0.2, 1.3)
        b.cyl("Rock", 2.2, -1, 0.3, side * 19.5, GATE - 12.5, 6)
    b.box("Board", (36, 1.4, 11), (0, GATE - 1.5, 39.5))  # placa: o jogo escreve por cima
    b.box("Gold", (37.2, 1.0, 0.7), (0, GATE - 1.5, 45.3))
    b.box("Gold", (37.2, 1.0, 0.7), (0, GATE - 1.5, 33.7))

    # portal de volta: anel de obsidiana em pé, do lado oposto ao portão
    PY, PZ, PR = -62.0, 9.6, 8.2
    ring = [(math.cos(k * 2 * math.pi / 20) * PR, PY, PZ + math.sin(k * 2 * math.pi / 20) * PR) for k in range(21)]
    b.tube("Obsidian", ring, [1.35] * 21, 7)
    disc = [(math.cos(k * 2 * math.pi / 24) * (PR - 0.7), math.sin(k * 2 * math.pi / 24) * (PR - 0.7)) for k in range(24)]
    b.prism("Portal", disc, 0.5, Matrix.Translation((0, PY - 0.25, PZ)))
    b.box("Obsidian", (24, 7, 2.6), (0, PY, 0.9))
    b.box("Gold", (24.6, 7.6, 0.4), (0, PY, 1.9))
    for k in range(10):
        a = k * 2 * math.pi / 10 + 0.3
        b.gem("Gold", math.cos(a) * PR, PY + 1.4, PZ + math.sin(a) * PR, 0.5, 1.2, 4)
    for side in (-1, 1):
        b.cyl("Rock", 1.5, -1, 5.0, side * 14.5, PY + 2, 6, phase=HEX)
        brazier(b, side * 14.5, PY + 2, 5.0)

    # poças de lava com beirada de pedras
    for cx, cy, size in ((-54, 20, 9.5), (56, -12, 8.5), (-40, -46, 7.5), (48, 44, 7.0)):
        pts = []
        for k in range(9):
            a = k * 2 * math.pi / 9
            rr = size * rnd.uniform(0.75, 1.1)
            pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
        b.slab("Lava", pts, -0.4, -0.04)
        for (px, py), (qx, qy) in zip(pts, pts[1:] + pts[:1]):
            for at in (0.0, 0.5):
                b.cyl("Obsidian", rnd.uniform(1.0, 1.7), -0.6, rnd.uniform(0.5, 2.0), px + (qx - px) * at, py + (qy - py) * at, 6, phase=rnd.uniform(0, 1))

    # espinhos de obsidiana perto da muralha
    for n in range(16):
        a = n * 2 * math.pi / 16 + 0.2
        if abs(math.cos(a) * 74) < 26 and math.sin(a) > 0:
            continue
        for _ in range(3):
            rr = 74 + rnd.uniform(-3, 3)
            lean = Matrix.Translation((math.cos(a) * rr + rnd.uniform(-2, 2), math.sin(a) * rr + rnd.uniform(-2, 2), -0.5)) @ Matrix.Rotation(rnd.uniform(-0.35, 0.35), 4, "Y") @ Matrix.Rotation(rnd.uniform(-0.35, 0.35), 4, "X")
            h = rnd.uniform(5, 12)
            b.loft("Obsidian", [(0, 0, 0, h * 0.17), (0, 0, h * 0.5, h * 0.11), (0, 0, h, 0)], 5, matrix=lean)

    b.build(COLORS, GLOW)
    b.export(MODELS)
    if SNAP:
        kit.snapshot(os.path.join(SNAP, "base_a.png"), (-70, -150, 120), (0, 10, 10), 30)
        kit.snapshot(os.path.join(SNAP, "base_b.png"), (10, 20, 9), (0, 90, 30), 22)
        kit.snapshot(os.path.join(SNAP, "base_c.png"), (18, -20, 8), (0, -62, 9), 30)
    return b


# ============================================================================== vulcão do fundo
def build_mount():
    m = kit.Kit("volcano_mount")
    rnd = random.Random(5)
    SEGS = 22
    profile = [(0, 285), (55, 222), (125, 156), (195, 110), (255, 80), (300, 66)]
    bumps = [[rnd.uniform(0.9, 1.12) for _ in range(SEGS)] for _ in profile]

    def wob(offset):
        return lambda ring, i: bumps[min(ring + offset, len(bumps) - 1)][i]

    m.loft("Rock", [(0, 0, z, r) for z, r in profile[:3]], SEGS, wobble=wob(0))
    m.loft("RockDark", [(0, 0, z, r) for z, r in profile[2:]], SEGS, wobble=wob(2))
    m.loft("Ember", [(0, 0, 296, 62), (0, 0, 303, 58), (0, 0, 290, 50)], SEGS, wobble=wob(4))  # boca acesa
    m.cyl("Lava", 55, 280, 291, segs=SEGS)

    def radius_at(z):
        for (z0, r0), (z1, r1) in zip(profile, profile[1:]):
            if z0 <= z <= z1:
                return r0 + (r1 - r0) * (z - z0) / (z1 - z0)
        return profile[-1][1]

    # rios de lava: descem pela encosta serpenteando e engordam embaixo
    for n in range(6):
        a0 = n * math.pi / 3 + rnd.uniform(-0.25, 0.25)
        swing = rnd.uniform(0.08, 0.2)
        pts, radii = [], []
        for step in range(13):
            z = 300 - step * 25
            a = a0 + swing * math.sin(step * 0.8 + n)
            r = radius_at(max(z, 0)) * 1.03 + 2
            pts.append((math.cos(a) * r, math.sin(a) * r, z))
            radii.append(5 + step * 0.9)
        m.tube("Lava", pts, radii, 6)

    # degraus de rocha saindo da encosta
    for n in range(18):
        a = rnd.uniform(0, 2 * math.pi)
        z = rnd.uniform(15, 200)
        r = radius_at(z) * 0.97
        m.cyl("RockDark" if z > 120 else "Rock", rnd.uniform(9, 20), z - 30, z + rnd.uniform(12, 40), math.cos(a) * r, math.sin(a) * r, 6, phase=rnd.uniform(0, 1))

    m.build(COLORS, GLOW)
    m.export(MODELS)
    if SNAP:
        kit.snapshot(os.path.join(SNAP, "mount.png"), (-520, -620, 260), (0, 0, 130), 35)
    return m


# ============================================================================== agulha de rocha
def build_spire():
    s = kit.Kit("volcano_spire")
    rnd = random.Random(9)
    column(s, rnd, 0, 0, 4.4, -6, 46)
    s.cyl("Lava", 3.4, 45.8, 46.4, 0, 0, 6, phase=HEX)
    for n in range(6):
        a = n * math.pi / 3
        column(s, rnd, math.cos(a) * 7.6, math.sin(a) * 7.6, 4.4, -6, rnd.uniform(12, 36))
    for n in range(9):
        a = n * 2 * math.pi / 9 + 0.3
        column(s, rnd, math.cos(a) * 14.6, math.sin(a) * 14.6, 4.2, -6, rnd.uniform(2, 14))
    s.tube("Lava", [(0, -3.4, 46), (0, -5.2, 40), (1, -9.5, 24), (0, -13.5, 8), (0, -17, -1)], [1.2, 1.3, 1.3, 1.5, 2.4], 6)
    for n in range(3):
        lean = Matrix.Translation((rnd.uniform(-10, 10), rnd.uniform(4, 12), 0)) @ Matrix.Rotation(rnd.uniform(-0.4, 0.4), 4, "Y") @ Matrix.Rotation(rnd.uniform(-0.4, 0.4), 4, "X")
        h = rnd.uniform(18, 30)
        s.loft("Obsidian", [(0, 0, 0, h * 0.13), (0, 0, h * 0.5, h * 0.08), (0, 0, h, 0)], 5, matrix=lean)
    s.build(COLORS, GLOW)
    s.export(MODELS)
    if SNAP:
        kit.snapshot(os.path.join(SNAP, "spire.png"), (60, -80, 40), (0, 0, 20), 35, (700, 700))
    return s


kits = []
for build in (build_track, build_base, build_mount, build_spire):
    for done in kits:
        done.hide(True)
    kits.append(build())
for done in kits:
    done.hide(False)
os.makedirs(os.path.dirname(BLEND), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=BLEND)
print("projeto salvo em", BLEND)
