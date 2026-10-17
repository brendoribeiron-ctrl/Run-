# Personagens de anime (mundo 1: Black Clover) no estilo dos jogos de "anime farm": corpo de
# bloco do Roblox com cantos arredondados, cabeça um pouco maior, rosto de anime em relevo
# (olhos em camadas, cílios, sobrancelhas, boca) e cabelo de mechas achatadas.
#
#   blender -b --factory-startup -P tools/blender/anime.py -- [asta noelle] [--preview arquivo.png]
#
# Fica fora do jogo: o elenco em uso é o de avatares do catálogo (src/shared/AnimeCast.luau).
# Exporta assets/anime_blender/bc_<nome>.fbx (envio: node tools/upload_assets.cjs
# assets/anime_blender --out <arquivo>). Cada tipo de peça vira "<Tipo>_bc_<nome>", pintado pelo
# nome com a tabela gravada em assets/anime_blender/AnimePalettes.luau. Pés na origem, frente +Y.

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODELS = os.path.join(ROOT, "assets", "anime_blender")  # fora do jogo: o elenco usa o catálogo (Shared.AnimeCast)


def rgb(r, g, b):
    return (r / 255, g / 255, b / 255, 1)


# cores de cada tipo de peça, por personagem (o jogo usa a mesma tabela)
PALETTE = {
    "asta": {
        "Skin": rgb(245, 200, 160), "Hair": rgb(214, 212, 200), "HairDark": rgb(168, 166, 156),
        "Eye": rgb(255, 255, 255), "Iris": rgb(46, 160, 70), "Pupil": rgb(12, 40, 18), "Shine": rgb(255, 255, 255),
        "Lash": rgb(28, 22, 22), "Brow": rgb(120, 116, 106), "Mouth": rgb(110, 28, 34), "Teeth": rgb(255, 255, 255),
        "Band": rgb(24, 22, 26), "Gold": rgb(232, 182, 60), "Robe": rgb(20, 20, 24),
        "Tunic": rgb(236, 234, 228), "Jacket": rgb(36, 46, 82), "Pants": rgb(36, 46, 82),
        "Belt": rgb(110, 70, 40), "Boot": rgb(26, 24, 26), "Toe": rgb(236, 234, 228),
        "Blade": rgb(44, 44, 50), "Edge": rgb(90, 90, 98), "Grip": rgb(70, 46, 30),
    },
    "noelle": {
        "Skin": rgb(250, 218, 196), "Hair": rgb(228, 228, 240), "HairDark": rgb(190, 190, 210),
        "Eye": rgb(255, 255, 255), "Iris": rgb(150, 70, 200), "Pupil": rgb(50, 16, 74), "Shine": rgb(255, 255, 255),
        "Lash": rgb(40, 28, 44), "Brow": rgb(180, 178, 196), "Mouth": rgb(150, 50, 70), "Blush": rgb(255, 150, 170),
        "Gold": rgb(232, 182, 60), "Robe": rgb(20, 20, 24), "Dress": rgb(120, 60, 170), "Blazer": rgb(200, 202, 214),
        "Tie": rgb(120, 60, 170), "Boot": rgb(232, 232, 240), "Water": rgb(80, 180, 255),
    },
}
GLOW = {"Water", "Vein"}
SMOOTH = {"Skin", "Robe", "Water", "Hair", "HairMid", "HairDark", "Dress", "Blazer", "Tunic", "Jacket", "Pants"}


# ---------------------------------------------------------------- formas
def merge(dst, src, matrix):
    src.verts.index_update()
    vs = [dst.verts.new(matrix @ v.co) for v in src.verts]
    for f in src.faces:
        dst.faces.new([vs[v.index] for v in f.verts])
    src.free()


def rbox(K, kind, size, center, r, segs=2, rot=None):
    """Caixa de cantos arredondados."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    bmesh.ops.bevel(bm, geom=bm.verts[:] + bm.edges[:], offset=r, segments=segs, profile=0.5, affect="EDGES", clamp_overlap=True)
    m = Matrix.Translation(Vector(center))
    if rot is not None:
        m = m @ rot
    merge(K.bm(kind), bm, m)


def ellipsoid(K, kind, center, radii, from_deg=-90, to_deg=90, steps=8, segs=20):
    cx, cy, cz = center
    rx, ry, rz = radii
    loops = []
    bm = K.bm(kind)
    for i in range(steps + 1):
        a = math.radians(from_deg + (to_deg - from_deg) * i / steps)
        c, s = math.cos(a), math.sin(a)
        if c < 1e-4:
            loops.append([bm.verts.new((cx, cy, cz + rz * s))])
            continue
        loops.append([bm.verts.new((cx + rx * c * math.sin(2 * math.pi * k / segs), cy + ry * c * math.cos(2 * math.pi * k / segs), cz + rz * s)) for k in range(segs)])
    K._skin(bm, loops, segs, True, True)


def sring(cx, cy, z, a, b, n=6, segs=36, front=None):
    """Anel superelíptico (retângulo arredondado) na altura z."""
    pts = []
    for k in range(segs):
        t = 2 * math.pi * k / segs
        c, s = math.cos(t), math.sin(t)
        x = a * math.copysign(abs(c) ** (2 / n), c)
        y = b * math.copysign(abs(s) ** (2 / n), s)
        pts.append(Vector((cx + x, cy + y, z)))
    return pts


def ring_loft(K, kind, rings):
    bm = K.bm(kind)
    loops = [[bm.verts.new(p) for p in ring] for ring in rings]
    K._skin(bm, loops, len(rings[0]), True, True)


def lock(K, kind, pts, widths, thick=0.5, flat=None, segs=6):
    """Mecha achatada: segue pts, largura por ponto (0 = ponta); a espessura fica na direção flat."""
    bm = K.bm(kind)
    pts = [Vector(p) for p in pts]
    loops = []
    for i, (p, w) in enumerate(zip(pts, widths)):
        t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        n = Vector(flat(i, p) if callable(flat) else (flat or (0, 0, 1)))
        n = (n - t * n.dot(t))
        if n.length < 1e-4:
            n = t.orthogonal()
        n.normalize()
        side = t.cross(n)
        if w <= 1e-6:
            loops.append([bm.verts.new(p)])
            continue
        loops.append([bm.verts.new(p + side * math.cos(2 * math.pi * k / segs) * w + n * math.sin(2 * math.pi * k / segs) * w * thick) for k in range(segs)])
    K._skin(bm, loops, segs, True, True)


def spike(K, kind, base, direction, length, width, bend=(0, 0, 0), center=None, thick=0.5, steps=4, power=0.85):
    base, d, bend = Vector(base), Vector(direction).normalized(), Vector(bend)
    pts, ws = [], []
    for i in range(steps + 1):
        s = i / steps
        pts.append(base + d * length * s + bend * length * s * s)
        ws.append(width * (1 - s) ** power if i < steps else 0)
    flat = None
    if center is not None:
        c = Vector(center)
        flat = lambda i, p: (p - c)  # noqa: E731
    lock(K, kind, pts, ws, thick, flat)


def clump(K, kind, base, d, length, w, bend=(0, 0, 0), center=None, thick=0.55):
    """Mecha grossa de anime: larga até perto da ponta, curvada, achatada contra a cabeça."""
    base, d, bend = Vector(base), Vector(d).normalized(), Vector(bend)
    pts = [base + d * length * t + bend * length * t * t for t in (0, 0.25, 0.5, 0.75, 1)]
    c = Vector(center) if center is not None else None
    lock(K, kind, pts, [w * 0.85, w, w * 0.8, w * 0.42, 0], thick, (lambda i, p: p - c) if c is not None else None, segs=8)


def ellipse(cx, cz, rx, rz, n=18, a0=0.0):
    return [(cx + rx * math.cos(a0 + 2 * math.pi * k / n), cz + rz * math.sin(a0 + 2 * math.pi * k / n)) for k in range(n)]


def stroke(pts, w, taper=True):
    """Traço 2D: contorno de uma linha de pontos com largura w (afinando nas pontas)."""
    left, right = [], []
    n = len(pts)
    for i, (x, z) in enumerate(pts):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, n - 1)]
        dx, dz = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dz) or 1
        nx, nz = -dz / L, dx / L
        k = w * (math.sin(math.pi * i / (n - 1)) * 0.75 + 0.25 if taper else 1)
        left.append((x + nx * k / 2, z + nz * k / 2))
        right.append((x - nx * k / 2, z - nz * k / 2))
    return left + right[::-1]


class Face:
    """Desenho em relevo no plano da frente da cabeça (y = face). u = direita, v = cima."""

    def __init__(self, K, face_y, cz):
        self.K, self.y, self.cz = K, face_y, cz

    def shape(self, kind, pts, layer, cx=0.0, cz=0.0, s=1, tilt=0.0):
        c, sn = math.cos(tilt * s), math.sin(tilt * s)
        out = []
        for u, v in pts:
            u, v = u * c - v * sn, u * sn + v * c
            out.append((cx + s * u, self.cz + cz + v))
        if s < 0:
            out.reverse()
        base = self.y - 0.03
        self.K.prism(kind, out, 0.032 + 0.007 * layer, Matrix.Translation((0, base, 0)))

    def eye(self, cx, cz, s, rx, rz, tilt=0.0, iris=(0.72, 0.84), lash=0.045, wing=0.06, lower=True):
        """s = +1 olho da direita do personagem (lado +X), -1 da esquerda; o lado de fora é +u."""
        f = lambda kind, pts, layer: self.shape(kind, pts, layer, cx, cz, s, tilt)  # noqa: E731
        f("Eye", ellipse(0, 0, rx, rz, 20), 0)
        ix, iz = rx * iris[0], rz * iris[1]
        f("Iris", ellipse(-0.01, -0.015, ix, iz, 18), 1)
        f("Pupil", ellipse(-0.01, -0.03, ix * 0.48, iz * 0.55, 14), 2)
        f("Shine", ellipse(ix * 0.35, iz * 0.38, ix * 0.32, ix * 0.32, 10), 3)
        f("Shine", ellipse(-ix * 0.4, -iz * 0.5, ix * 0.16, ix * 0.16, 8), 3)
        # cílio de cima: faixa sobre o arco de cima, mais grossa do lado de fora, com a "asa"
        outer, inner = [], []
        for k in range(15):
            a = math.radians(175 - 165 * k / 14)
            th = lash * (0.6 + 0.8 * (1 - (a / math.pi)))
            inner.append((rx * 0.98 * math.cos(a), rz * 0.92 * math.sin(a)))
            outer.append(((rx + th) * math.cos(a), (rz + th) * math.sin(a)))
        outer.append((rx + wing, rz * 0.05 - wing * 0.2))
        f("Lash", outer + list(reversed(inner)), 3)
        if lower:
            lo = [(rx * math.cos(a), rz * math.sin(a)) for a in (math.radians(-15), math.radians(-40), math.radians(-60))]
            f("Lash", lo + [(x * 0.92 + 0.012, y * 0.92 + 0.012) for x, y in reversed(lo)], 1)

    def brow(self, cx, cz, s, pts, tilt=0.0):
        self.shape("Brow", pts, 1, cx, cz, s, tilt)


def bull(scale):
    """Emblema do touro dos Touros Negros: cara com chifres para cima."""
    p = [(-0.5, 0.55), (-0.42, 0.2), (-0.25, 0.12), (-0.22, -0.2), (-0.1, -0.5), (0.1, -0.5), (0.22, -0.2), (0.25, 0.12), (0.42, 0.2), (0.5, 0.55),
         (0.3, 0.3), (0.2, 0.32), (0, 0.22), (-0.2, 0.32), (-0.3, 0.3)]
    return [(x * scale, z * scale) for x, z in p]


def emblem(K, kind, pts, cx, cz, y, depth=0.05):
    K.prism(kind, [(cx + u, cz + v) for u, v in pts], depth, Matrix.Translation((0, y, 0)))


# ---------------------------------------------------------------- corpo comum
HEAD_Z = 4.9  # centro da cabeça
HEAD = (1.5, 1.32, 1.42)
FACE_Y = HEAD[1] / 2


def robe(K, a, b, top=4.2, bottom=3.0):
    """Manto curto dos Touros Negros: cai dos ombros até o meio do peito, gola e barra douradas,
    capuz caído nas costas, botão dourado do lado direito e o touro do lado esquerdo."""
    rings = [sring(0, 0, top + 0.08, 0.6, 0.53), sring(0, 0, top, a * 0.55, b * 0.94), sring(0, 0, top - 0.1, a * 0.93, b * 0.98),
             sring(0, 0, top - 0.25, a, b), sring(0, 0, bottom, a * 1.04, b * 1.06)]
    ring_loft(K, "Robe", rings)
    ring_loft(K, "Gold", [sring(0, 0, bottom - 0.03, a * 1.05, b * 1.07), sring(0, 0, bottom + 0.1, a * 1.045, b * 1.065)])
    ring_loft(K, "Gold", [sring(0, 0, top + 0.04, 0.64, 0.57), sring(0, 0, top + 0.16, 0.62, 0.55)])
    ellipsoid(K, "Robe", (0, -b * 0.88, top + 0.02), (0.72, 0.34, 0.3), steps=6, segs=16)
    front = b * 1.03
    rot = Matrix.Translation((a * 0.42, front, top - 0.42)) @ Matrix.Rotation(math.radians(-90), 4, "X")
    K.loft("Gold", [(0, 0, -0.02, 0.09), (0, 0, 0.07, 0.09), (0, 0, 0.1, 0.05)], 10, matrix=rot)
    emblem(K, "Gold", bull(0.32), -a * 0.45, top - 0.5, front - 0.02, 0.07)


# ---------------------------------------------------------------- Asta
def asta():
    K = kit.Kit("bc_asta")
    random.seed(7)
    rbox(K, "Skin", HEAD, (0, 0, HEAD_Z), 0.2, 3)
    K.cyl("Skin", 0.3, 3.9, 4.3, segs=12)

    # pernas: calça azul-escura, botas pretas de bico branco
    for x in (-0.5, 0.5):
        rbox(K, "Pants", (0.98, 0.98, 1.4), (x, 0, 1.3), 0.1)
        rbox(K, "Boot", (1.04, 1.06, 0.72), (x, 0, 0.36), 0.12)
        rbox(K, "Toe", (0.9, 0.3, 0.32), (x, 0.42, 0.16), 0.1)
        rbox(K, "Boot", (1.08, 1.1, 0.14), (x, 0, 0.7), 0.05)
    # tronco: túnica branca comprida por baixo da jaqueta aberta
    rbox(K, "Tunic", (2.0, 1.0, 2.2), (0, 0, 2.95), 0.12)
    for x in (-1, 1):
        rbox(K, "Jacket", (0.72, 1.06, 1.9), (x * 0.66, 0, 3.08), 0.1)
    rbox(K, "Jacket", (2.0, 0.3, 1.9), (0, -0.4, 3.08), 0.1)
    # cinto de couro com bolsinha
    ring_loft(K, "Belt", [sring(0, 0, 2.1, 1.06, 0.54, 8), sring(0, 0, 2.32, 1.06, 0.54, 8)])
    rbox(K, "Belt", (0.36, 0.26, 0.4), (0.75, 0.6, 2.12), 0.06)
    rbox(K, "Gold", (0.22, 0.1, 0.18), (0, 0.55, 2.21), 0.03)
    # braços: manga até o cotovelo, rasgada, antebraço de fora
    for s in (-1, 1):
        x = s * 1.5
        rbox(K, "Jacket", (1.02, 1.02, 1.05), (x, 0, 3.5), 0.12)
        for k in range(3):
            K.prism("Jacket", [(-0.15, 0), (0.15, 0), (0, -0.22 - 0.06 * (k % 2))], 0.04,
                    Matrix.Translation((x - 0.3 + k * 0.3, 0.5, 2.99)))
        rbox(K, "Skin", (0.94, 0.94, 1.15), (x, 0, 2.5), 0.14)
    robe(K, 1.26, 0.68)

    # rosto: olhos verdes determinados, sobrancelhas grossas, sorrisão
    F = Face(K, FACE_Y, HEAD_Z)
    for s in (-1, 1):
        F.eye(s * 0.32, -0.06, s, 0.17, 0.19, tilt=math.radians(-8), lash=0.05, wing=0.07)
        F.brow(s * 0.3, 0.2, s, [(-0.2, -0.02), (0.18, 0.06), (0.2, 0.11), (-0.2, 0.05)], tilt=math.radians(-12))
    grin = [(-0.24, 0.05), (-0.16, 0.02), (0, 0.01), (0.16, 0.02), (0.24, 0.05), (0.18, -0.06), (0.08, -0.12), (-0.08, -0.12), (-0.18, -0.06)]
    F.shape("Mouth", grin, 0, 0, -0.42)
    F.shape("Teeth", [(-0.2, 0.035), (0, 0.022), (0.2, 0.035), (0.17, -0.015), (-0.17, -0.015)], 1, 0, -0.42)

    # bandana preta com o touro dourado e as pontas do nó atrás
    ring_loft(K, "Band", [sring(0, 0, HEAD_Z + 0.32, 0.79, 0.7, 8), sring(0, 0, HEAD_Z + 0.53, 0.79, 0.7, 8)])
    emblem(K, "Gold", bull(0.2), 0, HEAD_Z + 0.425, 0.68, 0.06)
    for s in (-1, 1):
        lock(K, "Band", [(s * 0.1, -0.7, HEAD_Z + 0.42), (s * 0.35, -0.95, HEAD_Z + 0.3), (s * 0.55, -1.1, HEAD_Z + 0.05)], [0.1, 0.09, 0.0], 0.35, (0, -1, 0))

    # cabelo: calota + mechas espetadas para cima e para trás, franja por cima da bandana
    C = Vector((0, -0.04, HEAD_Z + 0.42))
    R = (0.82, 0.78, 0.46)
    ellipsoid(K, "Hair", C, R, 0, 90, 6, 20)
    rbox(K, "Hair", (1.56, 0.5, 1.0), (0, -0.5, HEAD_Z + 0.05), 0.2)

    def on_dome(theta, phi, push=0.0):
        t, p = math.radians(theta), math.radians(phi)
        pos = C + Vector((R[0] * math.cos(p) * math.sin(t), R[1] * math.cos(p) * math.cos(t), R[2] * math.sin(p)))
        n = Vector((math.cos(p) * math.sin(t) / R[0], math.cos(p) * math.cos(t) / R[1], math.sin(p) / R[2])).normalized()
        return pos - n * push, n

    def j(a=0.25):
        return Vector((random.uniform(-a, a), random.uniform(-a, a), random.uniform(-a, a)))

    # coroa de mechas laterais saindo para fora
    for theta in range(45, 330, 38):
        pos, n = on_dome(theta, 10, 0.15)
        d = n * 1.4 + Vector((0, -0.2, 0.45)) + j(0.15)
        spike(K, "HairDark" if 120 < theta < 240 else "Hair", pos, d, random.uniform(0.7, 0.9), 0.42, bend=(0, -0.1, 0.3), center=C, thick=0.55)
    # mechas do meio, mais compridas, para cima e para fora
    for theta in range(0, 360, 45):
        pos, n = on_dome(theta + 22, 45, 0.15)
        d = n * 1.2 + Vector((0, -0.2, 0.55)) + j(0.15)
        spike(K, "Hair", pos, d, random.uniform(0.8, 1.05), 0.45, bend=(0, -0.15, 0.15), center=C, thick=0.55)
    for theta in (30, 150, 270):
        pos, n = on_dome(theta, 72, 0.12)
        d = n + Vector((0, -0.3, 0.8)) + j(0.15)
        spike(K, "Hair", pos, d, random.uniform(0.75, 0.9), 0.42, bend=(0, -0.2, 0), center=C, thick=0.55)
    # a mecha alta do topo, curvada
    lock(K, "Hair", [(0.05, 0.1, HEAD_Z + 0.75), (0.1, 0.15, HEAD_Z + 1.35), (0.05, -0.05, HEAD_Z + 1.8), (-0.12, -0.35, HEAD_Z + 1.95)],
         [0.24, 0.17, 0.09, 0], 0.45, (0, -1, 0.2))
    # nuca: mechas para baixo
    for x in (-0.55, -0.2, 0.2, 0.55):
        spike(K, "Hair", (x, -0.66, HEAD_Z + 0.25), (x * 0.5, -0.35, -1), 0.6, 0.3, bend=(0, -0.15, 0), center=C, thick=0.45)
    # franja: mechas que caem por cima da bandana até a testa
    for x, ln, tilt in ((-0.4, 0.5, -0.3), (0.0, 0.6, 0.15), (0.4, 0.48, 0.35)):
        spike(K, "Hair", (x, 0.52, HEAD_Z + 0.66), (tilt, 0.6, -1), ln, 0.3, bend=(0, 0.15, 0), center=C, thick=0.45)
    # costeletas
    for s in (-1, 1):
        spike(K, "Hair", (s * 0.72, 0.25, HEAD_Z + 0.35), (s * 0.15, 0.1, -1), 0.5, 0.18, center=C, thick=0.4)

    # Espada Mata-Demônios nas costas: lâmina larga negra de ponta reta lascada, cabo enrolado
    blade = [(-0.42, 0), (0.42, 0), (0.46, -3.6), (0.3, -4.0), (0.1, -3.9), (-0.08, -4.15), (-0.46, -4.0)]
    rot = Matrix.Translation((0.95, -0.85, 5.0)) @ Matrix.Rotation(math.radians(-38), 4, "Y") @ Matrix.Rotation(math.radians(180), 4, "Z")
    K.prism("Blade", blade, 0.16, rot @ Matrix.Translation((0, -0.08, 0)))
    edge = [(0.36, -0.1), (0.46, -0.1), (0.5, -3.6), (0.4, -3.75)]
    K.prism("Edge", edge, 0.2, rot @ Matrix.Translation((0, -0.1, 0)))
    K.prism("Edge", [(-0.36, -0.1), (-0.46, -0.1), (-0.5, -3.95), (-0.4, -3.8)], 0.2, rot @ Matrix.Translation((0, -0.1, 0)))
    for k in range(5):
        K.prism("Grip", [(-0.17, 0.05 + k * 0.24), (0.17, 0.02 + k * 0.24), (0.15, 0.24 + k * 0.24), (-0.15, 0.27 + k * 0.24)], 0.2,
                rot @ Matrix.Translation((0, -0.1, 0)))
    K.prism("Blade", [(-0.2, 1.2), (0.2, 1.2), (0.2, 1.36), (-0.2, 1.36)], 0.24, rot @ Matrix.Translation((0, -0.12, 0)))
    return K


# ---------------------------------------------------------------- Noelle
def noelle():
    K = kit.Kit("bc_noelle")
    random.seed(11)
    rbox(K, "Skin", HEAD, (0, 0, HEAD_Z), 0.2, 3)
    K.cyl("Skin", 0.28, 3.9, 4.3, segs=12)

    # pernas: botas altas brancas
    for x in (-0.46, 0.46):
        rbox(K, "Skin", (0.86, 0.86, 1.2), (x, 0, 1.45), 0.12)
        rbox(K, "Boot", (0.92, 0.94, 1.35), (x, 0, 0.67), 0.14)
        rbox(K, "Dress", (0.96, 0.98, 0.12), (x, 0, 1.33), 0.04)
    # vestido roxo curto: corpo + saia rodada
    rbox(K, "Dress", (1.8, 0.92, 2.0), (0, 0, 3.0), 0.14)
    ring_loft(K, "Dress", [sring(0, 0, 2.3, 0.95, 0.5, 6), sring(0, 0, 1.95, 1.1, 0.62, 4), sring(0, 0, 1.6, 1.22, 0.72, 4)])
    # blazer prateado: lapelas abertas na frente e mangas compridas
    for s in (-1, 1):
        K.prism("Blazer", [(s * 0.9, 4.0), (s * 0.3, 4.0), (s * 0.55, 3.0), (s * 0.9, 2.75)], 0.08, Matrix.Translation((0, 0.43, 0)))
        rbox(K, "Blazer", (0.4, 0.96, 1.4), (s * 0.72, 0, 3.3), 0.1)
        x = s * 1.33
        rbox(K, "Blazer", (0.86, 0.86, 1.65), (x, 0, 3.15), 0.14)
        rbox(K, "Dress", (0.9, 0.9, 0.16), (x, 0, 2.38), 0.05)
        rbox(K, "Skin", (0.8, 0.8, 0.42), (x, 0, 2.1), 0.14)
    robe(K, 1.14, 0.62, bottom=3.1)

    # rosto: olhos grandes roxos, cílios longos, boquinha emburrada e bochecha corada
    F = Face(K, FACE_Y, HEAD_Z)
    for s in (-1, 1):
        F.eye(s * 0.3, -0.08, s, 0.17, 0.22, tilt=math.radians(4), lash=0.055, wing=0.09)
        F.brow(s * 0.3, 0.24, s, [(-0.15, 0.0), (0.16, 0.03), (0.16, 0.06), (-0.15, 0.035)], tilt=math.radians(6))
        F.shape("Blush", ellipse(0, 0, 0.1, 0.035, 12), 0, s * 0.42, -0.36)
    F.shape("Mouth", [(-0.07, 0.0), (0.07, 0.0), (0.04, -0.035), (-0.04, -0.035)], 0, 0, -0.45)

    # cabelo prateado: calota lisa, franja reta, mechas do rosto e duas maria-chiquinhas longas
    C = Vector((0, -0.04, HEAD_Z + 0.36))
    R = (0.82, 0.79, 0.5)
    ellipsoid(K, "Hair", C, R, 0, 90, 6, 20)
    rbox(K, "Hair", (1.6, 0.6, 1.25), (0, -0.45, HEAD_Z - 0.05), 0.25)
    for k in range(5):
        x = -0.56 + k * 0.28
        ln = 0.5 + 0.08 * math.cos(k * 2.1)
        spike(K, "Hair", (x, 0.5, HEAD_Z + 0.74 - abs(x) * 0.2), (x * 0.35, 0.35, -1), ln, 0.22, bend=(0, 0.14, 0), center=C, thick=0.4, power=0.9)
    for s in (-1, 1):
        lock(K, "Hair", [(s * 0.7, 0.3, HEAD_Z + 0.45), (s * 0.8, 0.32, HEAD_Z), (s * 0.78, 0.3, HEAD_Z - 0.45), (s * 0.7, 0.25, HEAD_Z - 0.75)],
             [0.17, 0.15, 0.1, 0], 0.4, (s, 0, 0))
        # prendedor e a maria-chiquinha: três mechas grossas em S até as costas
        tie = Vector((s * 0.66, -0.5, HEAD_Z + 0.42))
        K.loft("Tie", [(0, 0, -0.12, 0.17), (0, 0, 0.12, 0.17)], 12, matrix=Matrix.Translation(tie) @ Matrix.Rotation(math.radians(90), 4, "Y"))
        for k, (dx, dy) in enumerate(((0, 0), (0.1, -0.12), (-0.08, -0.1))):
            pts = [tie + Vector((s * 0.1, -0.1, 0)), tie + Vector((s * (0.28 + dx), -0.42 + dy, -0.4)), tie + Vector((s * (0.32 + dx), -0.58 + dy, -1.1)),
                   tie + Vector((s * (0.24 + dx), -0.58 + dy, -1.8)), tie + Vector((s * (0.32 + dx), -0.52 + dy, -2.5 + 0.2 * k))]
            lock(K, "Hair" if k < 2 else "HairDark", pts, [0.12, 0.24, 0.28, 0.2, 0], 0.55, (0, -1, 0))
    # fio d'água girando na mão direita: bolha de magia
    ellipsoid(K, "Water", (1.35, 0.55, 1.45), (0.42, 0.42, 0.42), steps=8, segs=18)
    return K


# ---------------------------------------------------------------- peças do elenco
# Corpo, rosto, cabelos e acessórios reaproveitados pelo resto do elenco de Black Clover.

def sun(scale):
    """Emblema da Aurora Dourada: estrela de oito pontas."""
    return [((scale * (0.5 if k % 2 == 0 else 0.22)) * math.cos(math.pi / 2 + k * math.pi / 8),
             (scale * (0.5 if k % 2 == 0 else 0.22)) * math.sin(math.pi / 2 + k * math.pi / 8)) for k in range(16)]


def lion(scale):
    """Emblema do Leão Carmesim: juba em pontas."""
    return [((scale * (0.5 if k % 2 == 0 else 0.34)) * math.cos(math.pi / 2 + k * math.pi / 10),
             (scale * (0.5 if k % 2 == 0 else 0.34)) * math.sin(math.pi / 2 + k * math.pi / 10)) for k in range(20)]


def squad_robe(K, fem, mark="bull", bottom=None):
    """Manto do esquadrão (cor do tipo Robe): Touros Negros, Aurora Dourada ou Leão Carmesim."""
    a, b = (1.14, 0.62) if fem else (1.26, 0.68)
    bottom = bottom or (3.1 if fem else 3.0)
    top = 4.2
    rings = [sring(0, 0, top + 0.08, 0.6, 0.53), sring(0, 0, top, a * 0.55, b * 0.94), sring(0, 0, top - 0.1, a * 0.93, b * 0.98),
             sring(0, 0, top - 0.25, a, b), sring(0, 0, bottom, a * 1.04 + (3.0 - bottom) * 0.08, b * 1.06 + (3.0 - bottom) * 0.06)]
    ring_loft(K, "Robe", rings)
    a2, b2 = a * 1.05 + (3.0 - bottom) * 0.08, b * 1.07 + (3.0 - bottom) * 0.06
    ring_loft(K, "Gold", [sring(0, 0, bottom - 0.03, a2, b2), sring(0, 0, bottom + 0.1, a2 * 0.995, b2 * 0.995)])
    ring_loft(K, "Gold", [sring(0, 0, top + 0.04, 0.64, 0.57), sring(0, 0, top + 0.16, 0.62, 0.55)])
    ellipsoid(K, "Robe", (0, -b * 0.88, top + 0.02), (0.72, 0.34, 0.3), steps=6, segs=16)
    front = b * 1.03
    K.loft("Gold", [(0, 0, -0.02, 0.09), (0, 0, 0.07, 0.09), (0, 0, 0.1, 0.05)], 10,
           matrix=Matrix.Translation((a * 0.42, front, top - 0.42)) @ Matrix.Rotation(math.radians(-90), 4, "X"))
    emblem(K, "Gold", {"bull": bull, "sun": sun, "lion": lion}[mark](0.32), -a * 0.45, top - 0.5, front - 0.02, 0.07)


def long_coat(K, a=1.08, b=0.6, bottom=0.55):
    """Sobretudo comprido até perto do chão (tipo Coat), com barra, gola e faixa da frente douradas."""
    rings = [sring(0, 0, 4.28, 0.6, 0.53), sring(0, 0, 4.15, a * 0.9, b), sring(0, 0, 3.4, a, b * 1.02),
             sring(0, 0, 2.0, a * 1.1, b * 1.12), sring(0, 0, bottom, a * 1.28, b * 1.32)]
    ring_loft(K, "Coat", rings)
    ring_loft(K, "Gold", [sring(0, 0, bottom - 0.03, a * 1.29, b * 1.33), sring(0, 0, bottom + 0.14, a * 1.27, b * 1.31)])
    ring_loft(K, "Gold", [sring(0, 0, 4.22, 0.66, 0.58), sring(0, 0, 4.4, 0.63, 0.56)])
    for z0, z1, y0, y1 in ((4.1, 2.0, b + 0.01, b * 1.12 + 0.01), (2.0, bottom + 0.1, b * 1.12 + 0.01, b * 1.32 + 0.01)):
        K.prism("Gold", [(-0.08, z0), (0.08, z0), (0.08, z1), (-0.08, z1)], 0.05, Matrix.Translation((0, (y0 + y1) / 2 - 0.02, 0)))


def body(K, fem=False, top="Top", sleeves="short", jacket=None, skirt=None, legs="Pants", boots=0.72, belt=True, cuffs=None):
    """Corpo de bloco: cabeça, tronco, braços, pernas, botas. Devolve o x dos braços."""
    tw, td = (1.8, 0.92) if fem else (2.0, 1.0)
    aw = 0.86 if fem else 0.98
    ax = tw / 2 + aw / 2 + 0.02
    lw, lx = (0.86, 0.46) if fem else (0.98, 0.5)
    rbox(K, "Skin", HEAD, (0, 0, HEAD_Z), 0.2, 3)
    K.cyl("Skin", 0.28, 3.9, 4.3, segs=12)
    rbox(K, top, (tw, td, 2.0), (0, 0, 3.0), 0.12)
    if jacket:
        for s in (-1, 1):
            rbox(K, jacket, (tw * 0.36, td + 0.06, 1.9), (s * tw * 0.33, 0, 3.08), 0.1)
        rbox(K, jacket, (tw, 0.3, 1.9), (0, -td / 2 + 0.1, 3.08), 0.1)
    for s in (-1, 1):
        x = s * lx
        if skirt:
            rbox(K, legs, (lw, lw, 1.6), (x, 0, 1.2), 0.12)
        else:
            rbox(K, legs, (lw, lw, 1.4), (x, 0, 1.3), 0.1)
        rbox(K, "Boot", (lw + 0.06, lw + 0.08, boots), (x, 0, boots / 2), 0.12)
        rbox(K, "Boot", (lw + 0.1, lw + 0.12, 0.12), (x, 0, boots - 0.04), 0.04)
    if skirt:
        kind, length = skirt
        ring_loft(K, kind, [sring(0, 0, 2.3, tw / 2 + 0.05, td / 2 + 0.04, 6), sring(0, 0, 2.3 - length * 0.5, tw / 2 + 0.2, td / 2 + 0.14, 4),
                            sring(0, 0, 2.3 - length, tw / 2 + 0.32, td / 2 + 0.24, 4)])
    if belt:
        ring_loft(K, "Belt", [sring(0, 0, 2.02, tw / 2 + 0.05, td / 2 + 0.04, 8), sring(0, 0, 2.22, tw / 2 + 0.05, td / 2 + 0.04, 8)])
        rbox(K, "Gold", (0.22, 0.1, 0.18), (0, td / 2 + 0.05, 2.12), 0.03)
    sleeve = jacket or top
    for s in (-1, 1):
        x = s * ax
        if sleeves == "long":
            rbox(K, sleeve, (aw, aw, 1.72), (x, 0, 3.14), 0.12)
            rbox(K, "Skin", (aw - 0.06, aw - 0.06, 0.4), (x, 0, 2.16), 0.12)
            if cuffs:
                rbox(K, cuffs, (aw + 0.04, aw + 0.04, 0.16), (x, 0, 2.34), 0.05)
        elif sleeves == "short":
            rbox(K, sleeve, (aw + 0.04, aw + 0.04, 0.9), (x, 0, 3.55), 0.12)
            rbox(K, "Skin", (aw - 0.04, aw - 0.04, 1.2), (x, 0, 2.5), 0.14)
        else:
            rbox(K, "Skin", (aw, aw, 2.0), (x, 0, 3.0), 0.12)
    return ax


EYES = {  # rx, rz, inclinação, cílio, asa
    "normal": (0.17, 0.19, -4, 0.05, 0.07), "fierce": (0.17, 0.15, -12, 0.055, 0.08), "cute": (0.17, 0.22, 4, 0.055, 0.09),
    "calm": (0.17, 0.14, -2, 0.05, 0.06), "cool": (0.16, 0.11, -8, 0.05, 0.08),
}
BROWS = {
    "normal": ([(-0.18, 0.0), (0.18, 0.03), (0.18, 0.08), (-0.18, 0.05)], -4),
    "angry": ([(-0.2, -0.02), (0.18, 0.06), (0.2, 0.11), (-0.2, 0.05)], -14),
    "thin": ([(-0.15, 0.0), (0.16, 0.03), (0.16, 0.06), (-0.15, 0.035)], 4),
    "worried": ([(-0.17, 0.03), (0.17, -0.01), (0.17, 0.03), (-0.17, 0.08)], 8),
}


def face(K, eye="normal", brows="normal", mouth="smile", blush=False):
    F = Face(K, FACE_Y, HEAD_Z)
    for s in (-1, 1):
        if eye == "closed":
            F.shape("Lash", stroke([(-0.16, -0.05), (-0.08, 0.02), (0.0, 0.05), (0.08, 0.02), (0.16, -0.05)], 0.05), 2, s * 0.32, -0.06, s)
        else:
            rx, rz, tilt, lash, wing = EYES[eye]
            F.eye(s * 0.32, -0.06, s, rx, rz, tilt=math.radians(tilt), lash=lash, wing=wing)
        pts, tilt = BROWS[brows]
        top = -0.06 + (EYES.get(eye, EYES["calm"])[1]) + 0.07
        F.brow(s * 0.3, top, s, pts, tilt=math.radians(tilt))
        if blush:
            F.shape("Blush", ellipse(0, 0, 0.1, 0.035, 12), 0, s * 0.42, -0.36)
    m = -0.42
    if mouth == "grin":
        F.shape("Mouth", [(-0.24, 0.05), (-0.16, 0.02), (0, 0.01), (0.16, 0.02), (0.24, 0.05), (0.18, -0.06), (0.08, -0.12), (-0.08, -0.12), (-0.18, -0.06)], 0, 0, m)
        F.shape("Teeth", [(-0.2, 0.035), (0, 0.022), (0.2, 0.035), (0.17, -0.015), (-0.17, -0.015)], 1, 0, m)
    elif mouth == "big":
        F.shape("Mouth", [(-0.15, 0.03), (0.15, 0.03), (0.11, -0.07), (0, -0.11), (-0.11, -0.07)], 0, 0, m)
        F.shape("Tongue", ellipse(0, -0.065, 0.07, 0.03, 10), 1, 0, m)
    elif mouth == "smile":
        F.shape("Mouth", stroke([(-0.13, 0.03), (-0.06, -0.02), (0.06, -0.02), (0.13, 0.03)], 0.04), 0, 0, m)
    elif mouth == "smirk":
        F.shape("Mouth", stroke([(-0.11, -0.01), (0.03, -0.015), (0.13, 0.04)], 0.035), 0, 0, m)
    elif mouth == "frown":
        F.shape("Mouth", stroke([(-0.12, -0.03), (0, 0.015), (0.12, -0.03)], 0.035), 0, 0, m)
    elif mouth == "pout":
        F.shape("Mouth", [(-0.07, 0.0), (0.07, 0.0), (0.04, -0.035), (-0.04, -0.035)], 0, 0, m)
    else:
        F.shape("Mouth", stroke([(-0.09, 0.0), (0.09, 0.0)], 0.032, False), 0, 0, m)
    return F


# cabelo: calota sobre a cabeça; HC/HR são o centro e os raios dela
HC = Vector((0, -0.04, HEAD_Z + 0.32))
HR = (0.82, 0.78, 0.54)


def on(theta, phi, push=0.0, C=HC, R=HR):
    t, p = math.radians(theta), math.radians(phi)
    pos = C + Vector((R[0] * math.cos(p) * math.sin(t), R[1] * math.cos(p) * math.cos(t), R[2] * math.sin(p)))
    n = Vector((math.cos(p) * math.sin(t) / R[0], math.cos(p) * math.cos(t) / R[1], math.sin(p) / R[2])).normalized()
    return pos - n * push, n


def jitter(a):
    return Vector((random.uniform(-a, a), random.uniform(-a, a), random.uniform(-a, a)))


def hair_base(K, kind="Hair", back=1.2):
    ellipsoid(K, kind, HC, HR, 0, 90, 6, 20)
    rbox(K, kind, (1.62, 1.44, 0.45), (0, -0.02, HEAD_Z + 0.58), 0.2)
    rbox(K, kind, (1.6, 0.6, back), (0, -0.45, HEAD_Z + 0.55 - back / 2), 0.25)


def bangs(K, kind, style="straight", n=5, length=0.5, width=0.22):
    if style == "straight":
        for k in range(n):
            x = -0.56 + k * 1.12 / (n - 1)
            spike(K, kind, (x, 0.5, HEAD_Z + 0.74 - abs(x) * 0.2), (x * 0.35, 0.35, -1), length + 0.06 * math.cos(k * 2.1), width,
                  bend=(0, 0.14, 0), center=HC, thick=0.4, power=0.9)
    elif style == "parted":
        for s in (-1, 1):
            for k in range(3):
                spike(K, kind, (s * (0.1 + k * 0.22), 0.5, HEAD_Z + 0.76 - k * 0.04), (s * 0.55, 0.35, -1), length - 0.06 * k, width,
                      bend=(0, 0.14, 0), center=HC, thick=0.4, power=0.9)
    elif style == "swept":
        for k in range(n):
            x = -0.5 + k * 1.0 / (n - 1)
            spike(K, kind, (x, 0.5, HEAD_Z + 0.76), (0.75, 0.35, -1), length, width, bend=(0.1, 0.14, 0), center=HC, thick=0.4, power=0.9)
    elif style == "messy":
        for x, tilt, ln in ((-0.46, -0.4, 0.5), (-0.22, 0.2, 0.58), (0.02, -0.15, 0.62), (0.25, 0.3, 0.55), (0.48, 0.45, 0.48)):
            spike(K, kind, (x, 0.5, HEAD_Z + 0.72), (tilt, 0.5, -1), ln * length / 0.55, width, bend=(0, 0.15, 0), center=HC, thick=0.45)


def spiky(K, kind="Hair", dark="HairDark", length=1.0, up=0.45, side=0.42, bang="messy"):
    """Espetado tipo shonen (Asta, Leopold): coroa para fora, meio e topo para cima."""
    hair_base(K, kind)
    for theta in range(45, 330, 38):
        pos, n = on(theta, 10, 0.15)
        spike(K, dark if 120 < theta < 240 else kind, pos, n * 1.4 + Vector((0, -0.2, up)) + jitter(0.15),
              random.uniform(0.7, 0.9) * length, side, bend=(0, -0.1, 0.3), center=HC, thick=0.55)
    for theta in range(0, 360, 45):
        pos, n = on(theta + 22, 45, 0.15)
        spike(K, kind, pos, n * 1.2 + Vector((0, -0.2, up + 0.1)) + jitter(0.15), random.uniform(0.8, 1.05) * length, 0.45,
              bend=(0, -0.15, 0.15), center=HC, thick=0.55)
    for theta in (30, 150, 270):
        pos, n = on(theta, 72, 0.12)
        spike(K, kind, pos, n + Vector((0, -0.3, 0.8)) + jitter(0.15), random.uniform(0.75, 0.9) * length, 0.42, bend=(0, -0.2, 0), center=HC, thick=0.55)
    for x in (-0.55, -0.2, 0.2, 0.55):
        spike(K, kind, (x, -0.66, HEAD_Z + 0.25), (x * 0.5, -0.35, -1), 0.6, 0.3, bend=(0, -0.15, 0), center=HC, thick=0.45)
    bangs(K, kind, bang, length=0.55, width=0.26)
    for s in (-1, 1):
        spike(K, kind, (s * 0.74, 0.25, HEAD_Z + 0.4), (s * 0.15, 0.1, -1), 0.5, 0.18, center=HC, thick=0.4)


def messy(K, kind="Hair", dark="HairDark", length=0.55, bang="messy", side=0.55, bang_len=0.55):
    """Curto e bagunçado, caindo para baixo (Yuno, Luck, Zora, Gauche)."""
    hair_base(K, kind)
    for theta in range(40, 330, 28):
        pos, n = on(theta, 14, 0.12)
        spike(K, dark if 130 < theta < 230 else kind, pos, n + Vector((0, -0.1, -0.3)) + jitter(0.2), random.uniform(0.85, 1.1) * length, 0.32,
              bend=(0, -0.05, -0.2), center=HC, thick=0.5)
    for theta in range(0, 360, 45):
        pos, n = on(theta + 20, 50, 0.12)
        spike(K, kind, pos, n + Vector((0, -0.3, 0.15)) + jitter(0.2), random.uniform(0.8, 1.0) * length, 0.36, bend=(0, -0.1, -0.1), center=HC, thick=0.5)
    for theta in (0, 120, 240):
        pos, n = on(theta, 80, 0.1)
        spike(K, kind, pos, Vector((0, -0.5, 0.6)) + jitter(0.2), 0.7 * length, 0.32, bend=(0, -0.2, -0.1), center=HC, thick=0.5)
    bangs(K, kind, bang, length=bang_len, width=0.24)
    for s in (-1, 1):
        for y in (0.22, -0.15):
            spike(K, kind, (s * 0.76, y, HEAD_Z + 0.45), (s * 0.2, 0.05, -1), side, 0.2, center=HC, thick=0.45)
    for x in (-0.5, -0.17, 0.17, 0.5):
        spike(K, dark, (x, -0.66, HEAD_Z + 0.3), (x * 0.4, -0.3, -1), 0.55, 0.28, center=HC, thick=0.45)


def long_hair(K, kind="Hair", dark="HairDark", end=2.6, bang="straight", wave=0.0, volume=1.0, bang_len=0.5):
    """Liso ou ondulado, cortina nas costas até a altura end (Vanessa, Mimosa, Licht, Lucius)."""
    hair_base(K, kind, back=1.4)
    for i, theta in enumerate(range(92, 270, 16)):
        pos, n = on(theta, 12, 0.1)
        n = Vector((n.x, n.y, 0)).normalized()
        pts, ws = [pos], [0.26]
        steps = 4
        for k in range(1, steps + 1):
            t = k / steps
            z = pos.z + (end - pos.z) * t + (0.1 * (i % 3) if k == steps else 0)
            off = n * (0.22 + 0.12 * t) * volume
            sway = Vector((math.sin(t * 6 + i) * wave, 0, 0))
            pts.append(Vector((pos.x, pos.y, 0)) + off + sway + Vector((0, 0, z)))
            ws.append(0.3 * (1 - t * 0.35) if k < steps else 0)
        lock(K, dark if i % 3 == 1 else kind, pts, ws, 0.45, (lambda j, p, n=n: n), segs=6)
    for s in (-1, 1):
        low = max(end + 0.3, 3.4)
        lock(K, kind, [(s * 0.74, 0.32, HEAD_Z + 0.5), (s * 0.86, 0.32, HEAD_Z), (s * (0.86 + wave), 0.28, (HEAD_Z + low) / 2), (s * 0.82, 0.24, low)],
             [0.2, 0.2, 0.17, 0], 0.4, (s, 0, 0))
    bangs(K, kind, bang, length=bang_len)


def pompadour(K, kind="Hair", dark="HairDark"):
    """Topete enorme para a frente, laterais lisas (Magna)."""
    hair_base(K, kind)
    for x, sc in ((0, 1.0), (-0.32, 0.75), (0.32, 0.75)):
        lock(K, kind, [(x, 0.25, HEAD_Z + 0.75), (x, 0.7 * sc + 0.1, HEAD_Z + 0.75 + 0.35 * sc), (x, 1.1 * sc, HEAD_Z + 0.68 + 0.3 * sc),
                       (x, 1.2 * sc, HEAD_Z + 0.45)], [0.32 * sc + 0.08, 0.36 * sc + 0.06, 0.28 * sc + 0.04, 0], 0.7, (0, 0, 1), segs=8)
    for x in (-0.5, 0, 0.5):
        spike(K, dark, (x, -0.66, HEAD_Z + 0.3), (x * 0.4, -0.5, -0.6), 0.5, 0.3, center=HC, thick=0.5)
    for s in (-1, 1):
        spike(K, kind, (s * 0.78, 0.0, HEAD_Z + 0.5), (s * 0.2, -0.6, -0.4), 0.55, 0.26, center=HC, thick=0.4)


def slick(K, kind="Hair", dark="HairDark", n=7, stray=True, rise=1.0):
    """Penteado para trás, pontas espetadas na nuca (Yami, Fuegoleon)."""
    hair_base(K, kind)
    for i in range(n):
        x = -0.62 + 1.24 * i / (n - 1)
        lock(K, kind if i % 2 == 0 else dark, [(x, 0.5, HEAD_Z + 0.66), (x * 1.05, 0.15, HEAD_Z + 0.98), (x * 1.15, -0.45, HEAD_Z + 0.95 + 0.1 * rise),
                                               (x * 1.35, -1.0, HEAD_Z + 0.6 + 0.35 * rise)], [0.2, 0.25, 0.2, 0], 0.5, (0, 0.3, 1))
    for x in (-0.5, -0.17, 0.17, 0.5):
        spike(K, dark, (x, -0.66, HEAD_Z + 0.3), (x * 0.6, -0.7, -0.5), 0.6, 0.28, center=HC, thick=0.5)
    if stray:
        spike(K, kind, (0.18, 0.55, HEAD_Z + 0.68), (0.25, 0.45, -1), 0.6, 0.12, bend=(0, 0.1, 0), center=HC, thick=0.5)


def mane(K, kind="Hair", dark="HairDark"):
    """Juba selvagem e comprida (Mereoleona)."""
    hair_base(K, kind, back=1.4)
    for theta in range(50, 320, 22):
        pos, n = on(theta, 12, 0.12)
        spike(K, dark if 130 < theta < 230 else kind, pos, n * 1.2 + Vector((0, -0.3, -0.4)) + jitter(0.15), random.uniform(1.0, 1.3), 0.4,
              bend=(0, -0.1, -0.3), center=HC, thick=0.5)
    for theta in range(110, 260, 25):
        pos, n = on(theta, 0, 0.1)
        spike(K, kind, pos, n * 0.5 + Vector((0, -0.3, -1)), random.uniform(1.5, 1.9), 0.42, bend=(0, -0.1, 0), center=HC, thick=0.5)
    for theta in range(0, 360, 50):
        pos, n = on(theta, 50, 0.12)
        spike(K, kind, pos, n + Vector((0, -0.3, 0.4)) + jitter(0.2), random.uniform(0.7, 0.9), 0.4, bend=(0, -0.2, 0), center=HC, thick=0.55)
    bangs(K, kind, "messy", length=0.6, width=0.26)


def fluffy(K, kind="Hair", dark="HairDark"):
    """Nuvem de cabelo fofo (Charmy)."""
    hair_base(K, kind)
    for theta in range(0, 360, 36):
        for phi, r in ((10, 0.36), (45, 0.38)):
            if phi == 10 and (theta < 40 or theta > 320):
                continue
            pos, n = on(theta + phi, phi, -0.05)
            ellipsoid(K, dark if phi == 10 and 120 < theta < 240 else kind, pos, (r, r, r * 0.9), steps=5, segs=10)
    ellipsoid(K, kind, HC + Vector((0, 0, 0.42)), (0.45, 0.45, 0.35), steps=5, segs=12)
    for x in (-0.4, 0, 0.4):
        ellipsoid(K, kind, (x, 0.5, HEAD_Z + 0.68), (0.25, 0.2, 0.18), steps=4, segs=10)


def ring(K, kind, center, radius, tube, matrix=None, n=20):
    M = matrix or Matrix.Identity(4)
    pts = [Vector(center) + (M @ Vector((radius * math.cos(2 * math.pi * k / n), 0, radius * math.sin(2 * math.pi * k / n)))) for k in range(n + 1)]
    lock(K, kind, pts, [tube] * len(pts), 1.0, (0, 1, 0), segs=6)


def flame(K, kind, base, size=1.0):
    """Chama: três línguas de fogo subindo."""
    base = Vector(base)
    for k, (dx, h) in enumerate(((0, 1.0), (-0.18, 0.7), (0.18, 0.75))):
        spike(K, kind, base + Vector((dx * size, 0, 0)), (dx * 0.6, 0, 1), h * size, 0.22 * size, bend=(-dx * 0.5, 0, 0), thick=0.8, steps=4, power=0.7)


def weapon_blade(K, kind, start, direction, length, width, thick=0.18, flat=(0, 1, 0)):
    d = Vector(direction).normalized()
    s = Vector(start)
    lock(K, kind, [s, s + d * length * 0.5, s + d * length * 0.92, s + d * length], [width, width, width * 0.9, 0], thick, flat)


CAST = {}  # nome -> (montagem, paleta, escala)

BASE_COLORS = {"Skin": (245, 200, 160), "Eye": (255, 255, 255), "Shine": (255, 255, 255), "Lash": (28, 22, 22), "Mouth": (110, 28, 34),
               "Teeth": (255, 255, 255), "Tongue": (220, 90, 100), "Gold": (232, 182, 60), "Belt": (110, 70, 40), "Boot": (40, 34, 34),
               "Blush": (255, 150, 170), "Robe": (20, 20, 24)}


def character(name, scale=1.0, **colors):
    def wrap(fn):
        c = dict(BASE_COLORS)
        c.update(colors)
        CAST[name] = (fn, {k: rgb(*v) for k, v in c.items()}, scale)
        return fn
    return wrap


GLOW.update({"Fire", "Bolt", "Portal", "Wind", "Halo", "Ember", "Glow"})
TRANSPARENT = {"Water": 0.45, "Portal": 0.25, "Wind": 0.35, "Fire": 0.1}


# ---------------------------------------------------------------- comuns
@character("magna", Hair=(240, 212, 110), HairDark=(200, 166, 70), Iris=(150, 60, 40), Pupil=(40, 10, 10), Brow=(200, 166, 70),
           Top=(235, 235, 238), Pants=(40, 40, 52), Shades=(18, 18, 22), Fire=(255, 120, 30))
def magna():
    K = kit.Kit("bc_magna")
    random.seed(21)
    ax = body(K, top="Top", sleeves="short")
    squad_robe(K, False, "bull")
    F = face(K, "fierce", "angry", "grin")
    for s in (-1, 1):  # óculos escuros
        F.shape("Shades", [(-0.22, 0.12), (0.22, 0.12), (0.24, -0.06), (0.12, -0.15), (-0.18, -0.13)], 5, s * 0.32, -0.04, s)
    F.shape("Shades", [(-0.12, 0.08), (0.12, 0.08), (0.12, 0.03), (-0.12, 0.03)], 5, 0, -0.02)
    pompadour(K)
    for s in (-1, 1):
        ellipsoid(K, "Gold", (s * 0.77, 0.05, HEAD_Z - 0.2), (0.06, 0.06, 0.06), steps=4, segs=8)
    ellipsoid(K, "Fire", (ax, 0.45, 2.0), (0.32, 0.32, 0.32), steps=6, segs=12)
    flame(K, "Fire", (ax, 0.45, 2.15), 0.8)
    return K


@character("luck", Hair=(244, 236, 200), HairDark=(210, 196, 150), Brow=(210, 196, 150), Top=(44, 66, 120), Pants=(36, 36, 46),
           Bolt=(255, 236, 80))
def luck():
    K = kit.Kit("bc_luck")
    random.seed(22)
    ax = body(K, top="Top", sleeves="none")
    squad_robe(K, False, "bull")
    face(K, "closed", "normal", "big")
    messy(K, length=0.55, bang="messy")
    for s in (-1, 1):  # raios nos punhos e nas botas
        for k in range(3):
            a = k * 2.1
            K.prism("Bolt", stroke([(0, 0), (0.12, 0.18), (-0.05, 0.3), (0.1, 0.5)], 0.08), 0.06,
                    Matrix.Translation((s * ax + 0.4 * math.cos(a), 0.4 * math.sin(a), 2.0)) @ Matrix.Rotation(a, 4, "Z"))
        K.prism("Bolt", stroke([(0, 0), (0.12, 0.15), (-0.04, 0.3), (0.1, 0.45)], 0.08), 0.06, Matrix.Translation((s * 0.5, 0.5, 0.15)))
    return K


@character("finral", Hair=(110, 72, 46), HairDark=(80, 50, 32), Iris=(80, 110, 60), Pupil=(20, 30, 14), Brow=(80, 50, 32),
           Top=(232, 230, 222), Jacket=(54, 108, 100), Pants=(50, 44, 40), Portal=(90, 255, 160))
def finral():
    K = kit.Kit("bc_finral")
    random.seed(23)
    ax = body(K, top="Top", jacket="Jacket", sleeves="long")
    squad_robe(K, False, "bull")
    face(K, "calm", "worried", "smile")
    long_hair(K, end=4.0, bang="parted", bang_len=0.45)
    ring(K, "Portal", (ax + 0.9, 0.2, 3.0), 0.75, 0.08, Matrix.Rotation(math.radians(70), 4, "Z"))
    return K


# ---------------------------------------------------------------- incomuns
@character("gauche", Hair=(30, 30, 38), HairDark=(18, 18, 24), Iris=(110, 120, 140), Pupil=(20, 20, 30), Brow=(30, 30, 38),
           Top=(30, 30, 36), Pants=(28, 28, 34), Patch=(20, 20, 24), Mirror=(200, 220, 240), Blood=(200, 20, 30))
def gauche():
    K = kit.Kit("bc_gauche")
    random.seed(24)
    ax = body(K, top="Top", sleeves="long", cuffs="Mirror")
    squad_robe(K, False, "bull")
    F = face(K, "cool", "angry", "frown")
    F.shape("Patch", ellipse(0, 0, 0.21, 0.19, 16), 5, 0.32, -0.04)
    F.shape("Patch", stroke([(0.15, 0.12), (0.5, 0.4)], 0.05, False), 5, 0.32, -0.04)
    F.shape("Patch", stroke([(-0.15, 0.12), (-0.75, 0.28)], 0.05, False), 5, 0.32, -0.04)
    F.shape("Blood", stroke([(0.03, -0.18), (0.04, -0.3)], 0.04), 1, 0, 0)
    messy(K, length=0.6, bang="swept", bang_len=0.6)
    K.loft("Mirror", [(0, 0, 0, 0.32), (0, 0, 0.05, 0.32)], 16, matrix=Matrix.Translation((-ax, 0.55, 2.2)) @ Matrix.Rotation(math.radians(-70), 4, "X"))
    return K


@character("vanessa", Hair=(236, 120, 168), HairDark=(196, 80, 128), Iris=(120, 60, 160), Pupil=(40, 16, 60), Brow=(196, 80, 128),
           Dress=(190, 30, 64), Boot=(30, 26, 30), Bottle=(40, 90, 50), Wine=(140, 20, 40), Thread=(255, 60, 90))
def vanessa():
    K = kit.Kit("bc_vanessa")
    random.seed(25)
    ax = body(K, fem=True, top="Dress", sleeves="none", skirt=("Dress", 0.75), legs="Skin", boots=0.95, belt=False)
    squad_robe(K, True, "bull")
    face(K, "cute", "thin", "smile", blush=True)
    long_hair(K, end=2.4, bang="swept", wave=0.12, volume=1.25, bang_len=0.55)
    K.cyl("Bottle", 0.17, 1.65, 2.15, x=-ax, y=0.5, segs=10)
    K.cyl("Bottle", 0.07, 2.15, 2.45, x=-ax, y=0.5, segs=8)
    K.cyl("Wine", 0.175, 1.75, 1.95, x=-ax, y=0.5, segs=10)
    return K


@character("charmy", 0.78, Hair=(252, 244, 210), HairDark=(226, 210, 160), Iris=(200, 120, 60), Pupil=(60, 30, 10), Brow=(226, 210, 160),
           Dress=(150, 100, 190), Apron=(250, 250, 245), Boot=(120, 80, 50), Wood=(190, 130, 70))
def charmy():
    K = kit.Kit("bc_charmy")
    random.seed(26)
    ax = body(K, fem=True, top="Dress", sleeves="short", skirt=("Dress", 0.6), legs="Skin", belt=False)
    K.prism("Apron", [(-0.55, 3.4), (0.55, 3.4), (0.65, 1.8), (-0.65, 1.8)], 0.06, Matrix.Translation((0, 0.46, 0)))
    squad_robe(K, True, "bull")
    face(K, "cute", "thin", "big", blush=True)
    fluffy(K)
    lock(K, "Wood", [(ax, 0.4, 1.3), (ax, 0.45, 3.6)], [0.08, 0.08], 1.0, (1, 0, 0))
    ellipsoid(K, "Wood", (ax, 0.48, 4.0), (0.32, 0.12, 0.42), steps=6, segs=12)
    return K


# ---------------------------------------------------------------- raros
@character("zora", Hair=(196, 196, 202), HairDark=(120, 120, 130), Iris=(170, 120, 40), Pupil=(40, 24, 8), Brow=(120, 120, 130),
           Top=(36, 36, 44), Pants=(30, 30, 36), Cloak=(64, 58, 66), Paint=(200, 30, 44))
def zora():
    K = kit.Kit("bc_zora")
    random.seed(27)
    body(K, top="Top", sleeves="long")
    rings = [sring(0, 0, 4.3, 0.62, 0.55), sring(0, 0, 4.15, 1.2, 0.66), sring(0, 0, 3.6, 1.3, 0.7), sring(0, 0, 2.7, 1.38, 0.76)]
    ring_loft(K, "Cloak", rings)
    ellipsoid(K, "Cloak", (0, -0.62, 4.45), (0.8, 0.38, 0.5), steps=6, segs=16)
    F = face(K, "cool", "angry", "smirk")
    for s in (-1, 1):
        F.shape("Paint", stroke([(-0.08, -0.16), (0.0, -0.3), (0.06, -0.42)], 0.05), 1, s * 0.32, -0.06, s)
    messy(K, length=0.65, bang="messy")
    return K


@character("mimosa", Hair=(240, 124, 70), HairDark=(206, 90, 46), Iris=(70, 150, 90), Pupil=(16, 40, 22), Brow=(206, 90, 46),
           Robe=(244, 242, 236), Dress=(250, 236, 240), Boot=(244, 242, 236), Flower=(255, 140, 190), Leaf=(90, 190, 90))
def mimosa():
    K = kit.Kit("bc_mimosa")
    random.seed(28)
    ax = body(K, fem=True, top="Dress", sleeves="long", skirt=("Dress", 0.9), legs="Skin", boots=1.0, belt=False)
    squad_robe(K, True, "sun")
    face(K, "cute", "thin", "smile", blush=True)
    long_hair(K, end=2.9, bang="straight", wave=0.05)
    for k in range(5):  # flor no cabelo
        a = k * 2 * math.pi / 5
        ellipsoid(K, "Flower", (-0.78, 0.25 + 0.14 * math.cos(a), HEAD_Z + 0.5 + 0.14 * math.sin(a)), (0.06, 0.12, 0.12), steps=4, segs=8)
    ellipsoid(K, "Gold", (-0.82, 0.25, HEAD_Z + 0.5), (0.07, 0.07, 0.07), steps=4, segs=8)
    for k in range(3):
        spike(K, "Leaf", (ax, 0.45, 2.0), (0.5 * (k - 1), 0.5, 1), 0.5, 0.15, thick=0.3)
    return K


# ---------------------------------------------------------------- épicos
@character("yuno", Hair=(28, 28, 36), HairDark=(16, 16, 22), Iris=(232, 182, 50), Pupil=(80, 50, 10), Brow=(28, 28, 36),
           Robe=(244, 242, 236), Top=(236, 236, 242), Pants=(36, 40, 56), Boot=(90, 60, 40), Wind=(110, 255, 170))
def yuno():
    K = kit.Kit("bc_yuno")
    random.seed(29)
    ax = body(K, top="Top", sleeves="long")
    squad_robe(K, False, "sun")
    face(K, "calm", "normal", "neutral")
    messy(K, length=0.6, bang="messy", bang_len=0.6)
    pts = [Vector((-ax - 0.6 + 0.5 * math.cos(t), 0.3 * math.sin(t), 2.4 + t * 0.22)) for t in [k * 0.5 for k in range(12)]]
    lock(K, "Wind", pts, [0.04 + 0.01 * k for k in range(11)] + [0], 1.0, (0, 0, 1))
    return K


@character("leopold", Hair=(222, 52, 40), HairDark=(130, 24, 22), Iris=(220, 80, 40), Pupil=(60, 10, 10), Brow=(130, 24, 22),
           Robe=(168, 28, 36), Top=(40, 36, 40), Pants=(36, 32, 36), Fire=(255, 120, 30))
def leopold():
    K = kit.Kit("bc_leopold")
    random.seed(30)
    ax = body(K, top="Top", sleeves="short")
    squad_robe(K, False, "lion")
    face(K, "fierce", "angry", "grin")
    spiky(K, length=0.95)
    for s in (-1, 1):
        flame(K, "Fire", (s * ax, 0.1, 1.9), 0.7)
    return K


# ---------------------------------------------------------------- lendários
@character("yami", 1.08, Hair=(26, 26, 30), HairDark=(14, 14, 18), Iris=(90, 90, 96), Pupil=(20, 20, 24), Brow=(26, 26, 30),
           Top=(236, 236, 230), Pants=(42, 42, 48), Stubble=(196, 160, 130), Cig=(240, 240, 240), Ember=(255, 110, 30),
           Sheath=(20, 20, 24), Grip=(60, 40, 90))
def yami():
    K = kit.Kit("bc_yami")
    random.seed(31)
    body(K, top="Top", sleeves="none")
    squad_robe(K, False, "bull", bottom=2.6)
    F = face(K, "cool", "angry", "neutral")
    F.shape("Stubble", [(-0.48, -0.18), (-0.3, -0.3), (-0.18, -0.48), (0.18, -0.48), (0.3, -0.3), (0.48, -0.18), (0.4, -0.55), (0, -0.62), (-0.4, -0.55)], -2, 0, 0)
    slick(K, n=7, stray=True)
    lock(K, "Cig", [(0.12, FACE_Y, HEAD_Z - 0.44), (0.2, FACE_Y + 0.3, HEAD_Z - 0.48)], [0.035, 0.035], 1.0, (0, 0, 1))
    ellipsoid(K, "Ember", (0.2, FACE_Y + 0.32, HEAD_Z - 0.48), (0.04, 0.04, 0.04), steps=4, segs=8)
    # katana na cintura, lado esquerdo
    lock(K, "Sheath", [(-0.95, 0.65, 2.45), (-1.25, 0.2, 1.75), (-1.6, -0.5, 0.8)], [0.07, 0.07, 0.06], 0.5, (1, 0, 0))
    lock(K, "Grip", [(-0.95, 0.65, 2.45), (-0.75, 0.95, 2.9)], [0.06, 0.06], 1.0, (1, 0, 0))
    K.loft("Gold", [(0, 0, 0, 0.13), (0, 0, 0.05, 0.13)], 10, matrix=Matrix.Translation((-0.95, 0.65, 2.45)) @ Matrix.Rotation(math.radians(40), 4, "X"))
    return K


@character("mereoleona", 1.04, Hair=(244, 112, 52), HairDark=(196, 70, 30), Iris=(240, 150, 40), Pupil=(70, 30, 6), Brow=(196, 70, 30),
           Robe=(168, 28, 36), Top=(44, 34, 34), Pants=(64, 44, 40), Fire=(255, 120, 30))
def mereoleona():
    K = kit.Kit("bc_mereoleona")
    random.seed(32)
    ax = body(K, fem=True, top="Top", sleeves="none")
    squad_robe(K, True, "lion", bottom=2.8)
    face(K, "fierce", "angry", "grin")
    mane(K)
    for s in (-1, 1):
        flame(K, "Fire", (s * ax, 0.1, 1.9), 0.9)
    return K


@character("fuegoleon", 1.06, Hair=(214, 56, 42), HairDark=(140, 30, 26), Iris=(220, 90, 40), Pupil=(60, 14, 8), Brow=(140, 30, 26),
           Robe=(168, 28, 36), Top=(240, 238, 232), Pants=(226, 224, 218), Boot=(110, 72, 44), Fire=(255, 120, 30))
def fuegoleon():
    K = kit.Kit("bc_fuegoleon")
    random.seed(33)
    ax = body(K, top="Top", sleeves="long", cuffs="Gold")
    squad_robe(K, False, "lion", bottom=2.4)
    face(K, "fierce", "angry", "neutral")
    slick(K, n=9, stray=False, rise=1.4)
    for k in range(4):  # braço direito de fogo (Salamandra)
        flame(K, "Fire", (ax, 0.0, 2.0 + k * 0.5), 0.55)
    return K


# ---------------------------------------------------------------- míticos
@character("julius", Hair=(226, 214, 176), HairDark=(186, 172, 130), Iris=(110, 130, 170), Pupil=(20, 30, 50), Brow=(186, 172, 130),
           Coat=(246, 242, 230), Top=(70, 56, 100), Pants=(60, 50, 86), Boot=(70, 50, 40), Halo=(255, 214, 90))
def julius():
    K = kit.Kit("bc_julius")
    random.seed(34)
    body(K, top="Top", jacket="Coat", sleeves="long", cuffs="Gold")
    long_coat(K)
    face(K, "calm", "normal", "smile")
    long_hair(K, end=4.0, bang="messy", wave=0.08, bang_len=0.5)
    # relógio da magia do tempo atrás das costas
    ring(K, "Halo", (0, -0.95, 4.6), 1.25, 0.07)
    for k in range(12):
        a = k * math.pi / 6
        K.box("Halo", (0.08, 0.06, 0.22 if k % 3 == 0 else 0.12), (1.1 * math.cos(a), -0.95, 4.6 + 1.1 * math.sin(a)), Matrix.Rotation(-a + math.pi / 2, 4, "Y"))
    lock(K, "Halo", [(0, -0.95, 4.6), (0.55, -0.95, 5.1)], [0.05, 0], 1.0, (0, 1, 0))
    lock(K, "Halo", [(0, -0.95, 4.6), (0, -0.95, 5.4)], [0.04, 0], 1.0, (0, 1, 0))
    return K


@character("licht", Hair=(22, 22, 28), HairDark=(12, 12, 16), Iris=(190, 40, 70), Pupil=(50, 6, 16), Brow=(22, 22, 28),
           Coat=(26, 26, 32), Top=(40, 40, 48), Pants=(30, 30, 36), Blade=(60, 64, 74), Glow=(120, 255, 170), Grip=(40, 30, 50))
def licht():
    K = kit.Kit("bc_licht")
    random.seed(35)
    body(K, top="Top", jacket="Coat", sleeves="long", cuffs="Gold")
    long_coat(K)
    face(K, "cool", "angry", "neutral")
    long_hair(K, end=2.5, bang="parted", bang_len=0.55)
    for s in (-1, 1):  # orelhas de elfo
        spike(K, "Skin", (s * 0.72, 0.05, HEAD_Z + 0.05), (s * 1, -0.2, 0.45), 0.5, 0.14, thick=0.4)
    # espada nas costas com lâmina brilhando
    rot = Matrix.Translation((0.9, -0.85, 5.1)) @ Matrix.Rotation(math.radians(-35), 4, "Y")
    K.prism("Blade", [(-0.18, 0), (0.18, 0), (0.12, -3.8), (0, -4.1), (-0.12, -3.8)], 0.12, rot @ Matrix.Translation((0, -0.06, 0)))
    K.prism("Glow", [(-0.05, -0.3), (0.05, -0.3), (0.03, -3.6), (-0.03, -3.6)], 0.16, rot @ Matrix.Translation((0, -0.08, 0)))
    K.prism("Gold", [(-0.45, 0.0), (0.45, 0.0), (0.45, 0.14), (-0.45, 0.14)], 0.2, rot @ Matrix.Translation((0, -0.1, 0)))
    K.prism("Grip", [(-0.1, 0.14), (0.1, 0.14), (0.1, 0.9), (-0.1, 0.9)], 0.18, rot @ Matrix.Translation((0, -0.09, 0)))
    return K


@character("lucius", Hair=(248, 238, 206), HairDark=(214, 200, 160), Iris=(200, 110, 220), Pupil=(60, 20, 70), Brow=(214, 200, 160),
           Coat=(250, 250, 248), Top=(120, 70, 160), Pants=(240, 240, 236), Boot=(240, 240, 236), Halo=(255, 226, 120))
def lucius():
    K = kit.Kit("bc_lucius")
    random.seed(36)
    body(K, top="Top", jacket="Coat", sleeves="long", cuffs="Gold")
    long_coat(K)
    face(K, "calm", "thin", "smile")
    long_hair(K, end=2.2, bang="parted", wave=0.06, bang_len=0.6)
    ring(K, "Halo", (0, -0.1, HEAD_Z + 1.25), 0.6, 0.07, Matrix.Rotation(math.radians(90), 4, "X"))
    return K


# ---------------------------------------------------------------- montar, exportar, prévia
BUILDERS = {"asta": asta, "noelle": noelle}
SCALE = {}
for _name, (_fn, _pal, _scale) in CAST.items():
    BUILDERS[_name] = _fn
    PALETTE[_name] = _pal
    SCALE[_name] = _scale
PALETTES_LUAU = os.path.join(MODELS, "AnimePalettes.luau")


def write_palettes(path):
    """Tabela de cores e materiais de cada peça, no formato de Models.Style, para o jogo."""
    lines = ["--!strict", "-- Gerado por tools/blender/anime.py (não editar à mão): cor, material e transparência de cada",
             "-- peça dos personagens de anime, pelo tipo no nome (\"Hair_bc_asta\" -> Hair).", "", "return {"]
    for name in BUILDERS:
        lines.append(f"\tbc_{name} = {{")
        for kind, c in sorted(PALETTE[name].items()):
            r, g, b = (round(v * 255) for v in c[:3])
            mat = "Neon" if kind in GLOW else ("Metal" if kind == "Gold" else "SmoothPlastic")
            tr = TRANSPARENT.get(kind, 0)
            extra = f", transparency = {tr}" if tr else ""
            lines.append(f"\t\t{kind} = {{ color = Color3.fromRGB({r}, {g}, {b}), material = Enum.Material.{mat}{extra} }},")
        lines.append("\t},")
    lines.append("}")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("paletas ->", path)


def linear(c):
    return tuple((v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4) if i < 3 else v for i, v in enumerate(c))


def finish(K, name):
    K.build(PALETTE[name], glow=GLOW)
    for ob in K.objects:
        kind = ob.name.split("_")[0]
        # material próprio de cada peça (o kit divide pelo tipo entre modelos) e cor em linear
        color = linear(PALETTE[name].get(kind, (1, 0, 1, 1)))
        mat = bpy.data.materials.new("M_" + ob.name)
        mat.use_nodes = True
        bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = 0.7
        if kind in GLOW:
            bsdf.inputs["Emission Color"].default_value = color
            bsdf.inputs["Emission Strength"].default_value = 1.5
            if kind in TRANSPARENT:
                bsdf.inputs["Alpha"].default_value = 1 - TRANSPARENT[kind]
        ob.data.materials.clear()
        ob.data.materials.append(mat)
        if kind in SMOOTH:
            for p in ob.data.polygons:
                p.use_smooth = True
        if SCALE.get(name, 1) != 1 and kind not in ("Pivot", "MarkX", "MarkY"):
            ob.data.transform(Matrix.Scale(SCALE[name], 4))
    return K


def preview(path, kits):
    scene = bpy.context.scene
    for i, K in enumerate(kits):
        for ob in K.objects:
            ob.location.x += (i - (len(kits) - 1) / 2) * 4.2
            if ob.name.split("_")[0] in ("Pivot", "MarkX", "MarkY"):
                ob.hide_render = True
    try:
        scene.render.engine = "BLENDER_EEVEE"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.55, 0.62, 0.72, 1)
    bg.inputs[1].default_value = 0.9
    scene.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.2
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    scene.collection.objects.link(sun)
    me = bpy.data.meshes.new("Floor")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=40)
    bm.to_mesh(me)
    floor = bpy.data.objects.new("Floor", me)
    mat = bpy.data.materials.new("F")
    mat.use_nodes = True
    next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = (0.25, 0.45, 0.2, 1)
    me.materials.append(mat)
    scene.collection.objects.link(floor)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 50
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = 1400, 900
    try:
        scene.view_settings.view_transform = "Standard"
    except TypeError:
        pass
    scene.render.image_settings.file_format = "PNG"
    views = [("front", (0, 15, 3.6)), ("three", (8, 12, 4.4)), ("back", (-6, -13, 4.2))]
    for tag, eye in views:
        cam.location = Vector(eye)
        cam.rotation_euler = (Vector((0, 0, 3.0)) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = path.replace(".png", f"_{tag}.png")
        bpy.ops.render.render(write_still=True)
    # rosto de perto
    cam.data.lens = 85
    for i, K in enumerate(kits):
        x = (i - (len(kits) - 1) / 2) * 4.2
        eye = Vector((x + 2.2, 7, HEAD_Z + 0.9))
        cam.location = eye
        cam.rotation_euler = (Vector((x, 0, HEAD_Z + 0.2)) - eye).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = path.replace(".png", f"_face{i}.png")
        bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = None
    if "--preview" in argv:
        out = argv[argv.index("--preview") + 1]
        argv = argv[: argv.index("--preview")]
    names = argv or list(BUILDERS)
    kit.clean_scene()
    kits = []
    for name in names:
        K = finish(BUILDERS[name](), name)
        K.export(MODELS)
        kits.append(K)
    write_palettes(PALETTES_LUAU)
    if out:
        preview(out, kits)


main()
