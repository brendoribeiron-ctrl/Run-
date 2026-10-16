# Peças 3D dos efeitos do golem (src/client/BossFx.luau). Cada tipo é uma peça sozinha, em
# volta da origem, com tamanho de referência 10 studs; o jogo copia, escala e anima.
#
#   Dome    cúpula de choque (casca fechada, raio 10, altura 10)
#   Swirl   três faixas em espiral sobre a cúpula (vento girando), raio 10,5
#   Ring    anel de choque deitado: borda de fora grossa, de dentro fina, raio 10
#   Band    parede baixa de onda (aro alto, raio 10, altura 3), com lábio para dentro
#   Slash   lua crescente deitada, de 200 graus, raio 10, abrindo para a frente (+Y)
#   SpikeA  espinho de rocha facetado (altura 10), base enterrada
#   SpikeB  espinho de rocha mais fino e torto
#   Shard   cristal de magia, seis faces, altura 10
#   Pillar  coluna de luz (raio 1, altura 10, ponta afinando)
#
# Malha do Roblox só tem um lado: tudo é volume fechado (a cúpula vista de dentro precisa da
# casca de dentro).
#
#   blender -b --factory-startup -P tools/blender/boss_fx.py
#
# Exporta assets/models/boss_fx.fbx e salva E:\Projetos roblox\Blender\Golem\boss_fx.blend.

import math
import os
import random
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODELS = os.path.join(ROOT, "assets", "models")
BLEND = r"E:\Projetos roblox\Blender\Golem\boss_fx.blend"

kit.clean_scene()
k = kit.Kit("boss_fx")
rng = random.Random(7)


def lathe(kind, profile, segs):
    """Gira um perfil 2D fechado (r, z), todo com r > 0, em volta do eixo Z: sólido fechado."""
    bm = k.bm(kind)
    rings = []
    for r, z in profile:
        rings.append([bm.verts.new((r * math.cos(2 * math.pi * i / segs), r * math.sin(2 * math.pi * i / segs), z)) for i in range(segs)])
    n = len(rings)
    for a in range(n):
        b = (a + 1) % n
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((rings[a][i], rings[a][j], rings[b][j], rings[b][i]))


def strip(kind, sections):
    """Sólido que segue uma lista de seções de 4 pontos; seção com 1 ponto vira ponta."""
    bm = k.bm(kind)
    loops = [[bm.verts.new(p) for p in s] for s in sections]
    k._skin(bm, loops, 4, True, True)


# ---------------------------------------------------------------- cúpula
R = 10.0
steps = 10
outer = [(R * math.cos(math.radians(85 * i / steps)), R * math.sin(math.radians(85 * i / steps))) for i in range(steps + 1)]
inner = [(r * 0.94, z * 0.94) for r, z in reversed(outer)]
lathe("Dome", outer + inner, 32)

# ---------------------------------------------------------------- espiral
for band in range(3):
    pts, radii = [], []
    n = 22
    for i in range(n + 1):
        t = i / n
        polar = math.radians(4 + 78 * t)  # do chão até perto do topo
        azim = band * 2 * math.pi / 3 + t * 2 * math.pi * 0.85
        r = 10.5 * math.cos(polar)
        pts.append((r * math.cos(azim), r * math.sin(azim), 10.5 * math.sin(polar)))
        radii.append(0.55 * math.sin(math.pi * min(t * 1.15, 1)) + 0.05 if i < n else 0)
    k.tube("Swirl", pts, radii, 6)

# ---------------------------------------------------------------- anel deitado
lathe("Ring", [(6.5, 0.0), (10.0, 0.0), (10.0, 0.7), (9.3, 0.55), (6.5, 0.04)], 40)

# ---------------------------------------------------------------- parede da onda
lathe("Band", [(9.7, 0.0), (10.0, 0.0), (10.15, 1.6), (10.0, 3.0), (9.55, 2.4), (9.6, 1.0)], 48)

# ---------------------------------------------------------------- lua crescente
sections = []
n = 30
span = math.radians(200)
for i in range(n + 1):
    t = i / n
    a = math.pi / 2 - span / 2 + span * t  # +Y no meio
    # mais larga perto da ponta que vai na frente (t alto), ponta fina atrás
    w = 4.5 * math.sin(math.pi * t) ** 0.7 * (0.55 + 0.45 * t)
    h = 0.5 * math.sin(math.pi * t) ** 0.5
    if i in (0, n):
        sections.append([(R * math.cos(a), R * math.sin(a), 0)])
        continue
    ro, ri = R, R - w
    ca, sa = math.cos(a), math.sin(a)
    sections.append([(ro * ca, ro * sa, -h * 0.3), (ro * ca, ro * sa, h * 0.3), (ri * ca, ri * sa, h), (ri * ca, ri * sa, -h)])
strip("Slash", sections)

# ---------------------------------------------------------------- espinhos de rocha
def spike(kind, base, height, lean, segs, seed):
    r = random.Random(seed)
    rings = []
    levels = [(-1.5, 1.05), (0.0, 1.0), (height * 0.3, 0.72), (height * 0.62, 0.42), (height * 0.86, 0.16), (height, 0.0)]
    for z, f in levels:
        s = max(z, 0) / height
        rings.append((lean[0] * s, lean[1] * s, z, base * f))
    k.loft(kind, rings, segs, phase=r.uniform(0, 1), wobble=lambda ring, i: r.uniform(0.75, 1.2))


spike("SpikeA", 2.3, 10.0, (0.6, 0.3), 5, 3)
spike("SpikeB", 1.6, 10.0, (1.6, -0.4), 4, 11)

# ---------------------------------------------------------------- cristal
k.loft("Shard", [(0, 0, -1.5, 1.3), (0, 0, 6.5, 1.5), (0.15, 0.1, 8.0, 1.05), (0.3, 0.2, 10.0, 0.0)], 6, phase=0.3)

# ---------------------------------------------------------------- coluna de luz
k.loft("Pillar", [(0, 0, 0, 1.0), (0, 0, 7.5, 1.0), (0, 0, 9.3, 0.55), (0, 0, 10.0, 0.0)], 14)

COLORS = {
    "Dome": (1, 0.6, 0.2, 1), "Swirl": (1, 1, 1, 1), "Ring": (1, 0.8, 0.4, 1), "Band": (0.4, 0.7, 1, 1),
    "Slash": (1, 0.5, 0.1, 1), "SpikeA": (0.3, 0.27, 0.26, 1), "SpikeB": (0.3, 0.27, 0.26, 1),
    "Shard": (0.4, 0.8, 1, 1), "Pillar": (1, 1, 0.8, 1),
    "Pivot": (1, 0, 1, 1), "MarkX": (1, 0, 1, 1), "MarkY": (1, 0, 1, 1),
}
k.build(COLORS)
k.export(MODELS)

shots = os.environ.get("SNAP")
if shots:
    # espalha as peças numa fileira só para a foto
    for i, ob in enumerate(o for o in k.objects if o.name.split("_")[0] not in ("Pivot", "MarkX", "MarkY")):
        ob.location.x += (i - 4) * 24
    kit.snapshot(os.path.join(shots, "boss_fx.png"), (0, -200, 90), (0, 0, 3), 30, (1800, 700))
os.makedirs(os.path.dirname(BLEND), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=BLEND)
print("projeto salvo em", BLEND)
