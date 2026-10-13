# O feiticeiro da casa de feitiçaria: guardião dos próximos mundos (src/server/Wizard.luau).
# Flutua: manto de barra rasgada, capa, barba comprida, chapéu de ponta dobrada, cajado com
# cristal na mão direita e um orbe sobre a esquerda. A frente do modelo é +Y.
#
#   blender -b --factory-startup -P tools/blender/wizard.py
#
# Exporta assets/models/wizard.fbx e salva E:\Projetos roblox\Blender\Feiticeiro\wizard.blend.

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODELS = os.path.join(ROOT, "assets", "models")
BLEND = r"E:\Projetos roblox\Blender\Feiticeiro\wizard.blend"

kit.clean_scene()
w = kit.Kit("wizard")

# ---------------------------------------------------------------- manto
# barra rasgada: o raio alterna entre pontas compridas e reentrâncias
def tatter(ring, i):
    return (1.12 if i % 2 == 0 else 0.86) if ring == 0 else 1.0

w.loft("Robe", [(0, 0, 0.0, 1.55), (0, 0.05, 0.9, 1.75), (0, 0.05, 2.2, 1.5), (0, 0, 3.3, 1.12), (0, 0, 4.3, 1.28), (0, 0, 5.0, 1.02), (0, 0, 5.35, 0.5)], 14, wobble=tatter)
# forro escuro por dentro da barra (aparece por baixo, já que ele flutua)
w.loft("Cloak", [(0, 0, 0.25, 0), (0, 0, 0.45, 1.5), (0, 0, 0.9, 1.6)], 14)
# barrado e cinto dourados, faixa da frente com três pedras
w.loft("Gold", [(0, 0.05, 0.95, 1.79), (0, 0.05, 1.25, 1.74)], 14)
w.loft("Gold", [(0, 0, 3.15, 1.2), (0, 0, 3.5, 1.17)], 14)
w.box("Gold", (0.7, 0.12, 2.3), (0, 1.52, 2.1), Matrix.Rotation(math.radians(-9), 4, "X"))
for z, y in ((1.5, 1.67), (2.1, 1.6), (2.7, 1.48)):
    w.gem("Glow", 0, y, z, 0.2, 0.42, 4, Matrix.Translation((0, y, z)) @ Matrix.Rotation(math.radians(90), 4, "X") @ Matrix.Translation((0, -y, -z)))
w.box("Gold", (0.62, 0.3, 0.62), (0, 1.2, 3.32))  # fivela
w.gem("Glow", 0, 1.38, 3.32, 0.2, 0.2, 4)
# livro de feitiços e saquinho pendurados no cinto
w.box("Book", (0.2, 0.75, 0.95), (-1.22, 0.35, 2.75), Matrix.Rotation(math.radians(12), 4, "Y"))
w.box("Page", (0.14, 0.66, 0.84), (-1.25, 0.4, 2.75), Matrix.Rotation(math.radians(12), 4, "Y"))
w.box("Gold", (0.24, 0.2, 0.2), (-1.24, 0.72, 2.75), Matrix.Rotation(math.radians(12), 4, "Y"))
w.ball("Cloak", 1.05, 0.7, 2.75, 0.34, 8, 1.2)

# ---------------------------------------------------------------- capa e gola
w.loft("Cloak", [(0, -0.2, 1.2, 1.9), (0, -0.25, 3.0, 1.55), (0, -0.15, 4.5, 1.6), (0, 0, 5.05, 1.25), (0, 0, 5.4, 0.62)], 14, phase=math.pi / 14,
    wobble=lambda ring, i: (0.25 if 2 <= i <= 4 else 1.0) if ring < 3 else 1.0)  # aberta na frente
w.loft("Gold", [(0, 0, 5.0, 1.3), (0, 0, 5.25, 1.0), (0, 0, 5.75, 1.25), (0, 0, 5.8, 1.2), (0, 0, 5.35, 0.9)], 14,
    wobble=lambda ring, i: 0.55 if 2 <= i <= 4 and ring >= 2 else 1.0)  # gola alta, aberta na frente
w.gem("Glow", 0, 1.02, 5.05, 0.26, 0.36, 6)  # broche

# ---------------------------------------------------------------- cabeça
w.ball("Skin", 0, 0.1, 6.1, 0.78, 12, 1.05)
w.loft("Skin", [(0, 0.82, 6.0, 0.16), (0, 1.12, 5.9, 0.12), (0, 1.18, 5.86, 0)], 6)  # nariz
for sx in (-1, 1):
    w.ball("Glow", sx * 0.3, 0.76, 6.2, 0.15, 8)  # olhos acesos
    w.tube("Beard", [(sx * 0.12, 0.76, 6.42), (sx * 0.4, 0.82, 6.5), (sx * 0.78, 0.7, 6.4)], [0.07, 0.13, 0], 6)  # sobrancelha
    w.tube("Beard", [(sx * 0.05, 0.95, 5.8), (sx * 0.5, 1.0, 5.66), (sx * 1.0, 0.95, 5.86)], [0.1, 0.14, 0], 6)  # bigode
    w.ball("Skin", sx * 0.8, 0.1, 6.05, 0.2, 6)  # orelhas
# barba: desce em três mechas até a cintura
w.tube("Beard", [(0, 0.6, 5.62), (0, 1.05, 5.2), (0, 1.3, 4.4), (0, 1.38, 3.6), (0.1, 1.42, 2.9)], [0.5, 0.6, 0.48, 0.3, 0], 8)
w.tube("Beard", [(-0.42, 0.5, 5.8), (-0.55, 1.0, 5.1), (-0.5, 1.22, 4.3), (-0.42, 1.3, 3.7)], [0.42, 0.42, 0.28, 0], 7)
w.tube("Beard", [(0.42, 0.5, 5.8), (0.55, 1.0, 5.1), (0.5, 1.22, 4.3), (0.4, 1.3, 3.8)], [0.42, 0.42, 0.28, 0], 7)
# cabelo atrás
w.tube("Beard", [(0, -0.4, 6.4), (0, -0.85, 5.8), (0, -0.9, 5.0), (0, -0.75, 4.4)], [0.7, 0.72, 0.5, 0], 8)

# ---------------------------------------------------------------- chapéu
tilt = Matrix.Translation((0, 0.05, 6.78)) @ Matrix.Rotation(math.radians(-8), 4, "X") @ Matrix.Rotation(math.radians(5), 4, "Y")
w.loft("Hat", [(0, 0, -0.05, 2.0), (0, 0, 0.1, 2.05), (0, 0, 0.2, 1.0)], 16, matrix=tilt, wobble=lambda ring, i: 1 + 0.06 * math.sin(i * 1.7))
# a copa sobe e dobra para trás e para o lado
crown = [(0, 0, 0.15, 0.98), (0, -0.05, 1.0, 0.8), (0.08, -0.2, 1.9, 0.6), (0.25, -0.55, 2.7, 0.42), (0.5, -1.05, 3.25, 0.27), (0.85, -1.6, 3.45, 0.15), (1.2, -2.0, 3.3, 0)]
w.loft("Hat", crown, 12, matrix=tilt)
w.loft("Gold", [(0, 0, 0.2, 1.02), (0, 0, 0.62, 0.92)], 12, matrix=tilt)
w.box("Gold", (0.5, 0.16, 0.55), (0, 0.97, 0.4), tilt @ Matrix.Translation((0, 0.97, 0.4)) @ Matrix.Translation((0, -0.97, -0.4)))
tip = tilt @ Vector((1.25, -2.05, 3.05))
w.gem("Glow", tip.x, tip.y, tip.z - 0.25, 0.2, 0.5, 4)  # estrela pendurada na ponta
# estrelas bordadas na copa
for a, z, r in ((0.5, 0.95, 0.83), (2.2, 1.4, 0.72), (4.0, 0.9, 0.84), (5.2, 1.7, 0.64)):
    p = tilt @ Vector((math.cos(a) * r, math.sin(a) * r - 0.1, z))
    w.gem("Gold", p.x, p.y, p.z, 0.13, 0.3, 4)

# ---------------------------------------------------------------- braços
# direito: erguido para o lado, segurando o cajado
w.tube("Robe", [(0.85, 0.05, 4.85), (1.5, 0.35, 4.55), (2.05, 0.75, 4.75), (2.2, 0.9, 5.0)], [0.5, 0.5, 0.5, 0.54], 9)
w.tube("Gold", [(2.17, 0.87, 4.95), (2.23, 0.93, 5.08)], [0.57, 0.57], 9)
w.ball("Skin", 2.3, 0.98, 5.2, 0.3, 8)
# esquerdo: à frente, palma para cima, com o orbe flutuando
w.tube("Robe", [(-0.85, 0.05, 4.85), (-1.35, 0.6, 4.35), (-1.6, 1.35, 4.2), (-1.65, 1.7, 4.3)], [0.5, 0.5, 0.5, 0.54], 9)
w.tube("Gold", [(-1.64, 1.66, 4.28), (-1.66, 1.78, 4.33)], [0.57, 0.57], 9)
w.ball("Skin", -1.68, 1.95, 4.42, 0.3, 8, 0.7)
w.ball("Orb", -1.68, 2.0, 5.35, 0.5, 12)
for k in range(5):
    a = k * 2 * math.pi / 5
    w.gem("Glow", -1.68 + math.cos(a) * 0.85, 2.0 + math.sin(a) * 0.85, 5.35 + math.sin(a * 2) * 0.2, 0.09, 0.3, 4)

# ---------------------------------------------------------------- cajado
sx, sy = 2.42, 1.1
w.tube("Wood", [(sx + 0.1, sy, 0.3), (sx, sy, 2.5), (sx - 0.05, sy, 5.2), (sx, sy, 7.6), (sx + 0.05, sy, 8.3)], [0.1, 0.15, 0.14, 0.15, 0.2], 7)
for z in (1.2, 4.6, 5.8, 8.2):
    w.cyl("Gold", 0.2, z, z + 0.16, sx, sy, 8)
# garra de três dedos segurando o cristal
for k in range(3):
    a = k * 2 * math.pi / 3 + 0.5
    cx, cy = math.cos(a), math.sin(a)
    w.tube("Gold", [(sx, sy, 8.25), (sx + cx * 0.55, sy + cy * 0.55, 8.7), (sx + cx * 0.62, sy + cy * 0.62, 9.3), (sx + cx * 0.3, sy + cy * 0.3, 9.85)], [0.13, 0.12, 0.09, 0], 6)
w.gem("Crystal", sx, sy, 9.25, 0.42, 1.25, 6)
w.gem("Glow", sx, sy, 10.35, 0.1, 0.3, 4)

COLORS = {
    "Robe": (0.3, 0.14, 0.62, 1), "Cloak": (0.11, 0.07, 0.3, 1), "Gold": (0.95, 0.7, 0.2, 1), "Glow": (0.5, 1, 0.95, 1),
    "Skin": (0.92, 0.72, 0.58, 1), "Beard": (0.93, 0.93, 0.97, 1), "Hat": (0.24, 0.1, 0.52, 1), "Wood": (0.35, 0.22, 0.12, 1),
    "Crystal": (0.4, 0.9, 1, 1), "Orb": (1, 0.45, 0.1, 1), "Book": (0.55, 0.1, 0.16, 1), "Page": (0.95, 0.92, 0.8, 1),
    "Pivot": (1, 0, 1, 1), "MarkX": (1, 0, 1, 1), "MarkY": (1, 0, 1, 1),
}
w.build(COLORS, glow=("Glow", "Crystal", "Orb"))
w.export(MODELS)

shots = os.environ.get("SNAP")
if shots:
    kit.snapshot(os.path.join(shots, "wizard_front.png"), (4.5, 15, 7.5), (0.3, 0, 5.2), 50, (800, 1000))
    kit.snapshot(os.path.join(shots, "wizard_side.png"), (-13, 7, 8), (0.3, 0, 5.2), 50, (800, 1000))
os.makedirs(os.path.dirname(BLEND), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=BLEND)
print("projeto salvo em", BLEND)
