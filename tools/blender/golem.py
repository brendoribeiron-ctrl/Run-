# Golem: o chefe da sala (src/server/Boss.luau). Um colosso de basalto em blocos, com ombreiras e
# manoplas enormes de frisos dourados, chifres e garras de magma e olhos em brasa (referência:
# "Magma Boss" do Sketchfab, estilo Blockbench). Velho e cansado: corcunda, braços pesados quase
# no chão, passos lentos, golpes com antecipação longa e recuperação pesada, como chefe de Sekiro.
#
# Cada peça é rígida e pertence a um osso: o objeto "<Tipo>_<Osso>" (Rock_Chest, Magma_HandR) é
# pintado pelo tipo e movido pelo osso. O jogo não usa animação do Roblox: este script grava a
# rotação de cada osso, quadro a quadro, em src/shared/GolemAnims.luau, e o cliente move as peças
# (src/client/Boss.luau). Assim o servidor sabe exatamente quando cada golpe acerta.
#
# Eixos: X = direita do golem (ossos "R"), Y = frente, Z = cima; pés em Z = 0. Medidas em studs.
#
#   blender -b --factory-startup -P tools/blender/golem.py     (SNAP=<pasta> grava prévias)
#
# Exporta assets/models/golem.fbx (peças em repouso) e src/shared/GolemAnims.luau, e salva
# E:\Projetos roblox\Blender\Golem\golem.blend com o esqueleto e uma ação por animação.

import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODELS = os.path.join(ROOT, "assets", "models")
ANIMS = os.path.join(ROOT, "src", "shared", "GolemAnims.luau")
BLEND = r"E:\Projetos roblox\Blender\Golem\golem.blend"
SNAP = os.environ.get("SNAP")
FPS = 30  # animação
BAKE_STEP = 2  # grava 1 de cada 2 quadros (15 por segundo); o jogo interpola

COLORS = {
    "Rock": (0.09, 0.075, 0.07, 1), "Plate": (0.17, 0.14, 0.13, 1), "Trim": (0.95, 0.6, 0.16, 1),
    "Magma": (0.9, 0.22, 0.08, 1), "Ember": (1.0, 0.85, 0.3, 1),
    "Pivot": (1, 0, 1, 1), "MarkX": (1, 0, 1, 1), "MarkY": (1, 0, 1, 1),
}
GLOW = ("Magma", "Ember")

###################################################################################################
# Esqueleto: (nome, cabeça, ponta, pai). As rotações giram em volta da cabeça do osso.

BONES = [
    ("Pelvis", (0, 0, 11.0), (0, 0, 13.5), None),
    ("Spine", (0, 0, 13.5), (0, 0, 17.5), "Pelvis"),
    ("Chest", (0, 0, 17.5), (0, 0, 23.0), "Spine"),
    ("Head", (0, 1.4, 23.2), (0, 1.4, 28.0), "Chest"),
]
for _s, _n in ((1, "R"), (-1, "L")):
    BONES += [
        ("UpperArm" + _n, (9.8 * _s, 0, 22.6), (10.0 * _s, 0, 15.0), "Chest"),
        ("Forearm" + _n, (10.0 * _s, 0, 15.0), (10.0 * _s, 0.6, 7.0), "UpperArm" + _n),
        ("Hand" + _n, (10.0 * _s, 0.6, 7.0), (10.0 * _s, 0.8, 3.0), "Forearm" + _n),
        ("Thigh" + _n, (3.6 * _s, 0, 11.0), (3.6 * _s, 0, 6.6), "Pelvis"),
        ("Shin" + _n, (3.6 * _s, 0, 6.6), (3.6 * _s, 0.2, 2.0), "Thigh" + _n),
        ("Foot" + _n, (3.6 * _s, 0.2, 2.0), (3.6 * _s, 2.6, 0.6), "Shin" + _n),
    ]
BONE_NAMES = [b[0] for b in BONES]
HEADS = {b[0]: Vector(b[1]) for b in BONES}
PARENT = {b[0]: b[3] for b in BONES}

###################################################################################################
# Modelo: um Kit por osso, peças em blocos.

kits = {name: kit.Kit(name) for name in BONE_NAMES}


def rot(x=0.0, y=0.0, z=0.0):
    return Matrix.Rotation(math.radians(z), 4, "Z") @ Matrix.Rotation(math.radians(y), 4, "Y") @ Matrix.Rotation(math.radians(x), 4, "X")


def B(bone, kind, size, at, r=None):
    kits[bone].box(kind, size, at, r)


def both(fn):
    """Constrói os dois lados: fn(s, n) com s = +1 (direita, "R") ou -1 (esquerda, "L")."""
    for s, n in ((1, "R"), (-1, "L")):
        fn(s, n)


def build_mesh():
    # quadril: bloco, cinto dourado, placa da frente e das laterais
    B("Pelvis", "Rock", (9.6, 6.4, 3.8), (0, -0.2, 11.8))
    B("Pelvis", "Trim", (10.0, 6.8, 0.9), (0, -0.2, 13.3))
    B("Pelvis", "Plate", (5.0, 1.0, 4.4), (0, 3.2, 10.6), rot(x=8))
    B("Pelvis", "Trim", (5.2, 1.1, 0.5), (0, 3.45, 12.5), rot(x=8))
    for s in (1, -1):
        B("Pelvis", "Plate", (1.0, 4.4, 3.4), (s * 5.1, -0.2, 11.0), rot(y=s * 6))
    # barriga: bloco, placas do abdômen e uma rachadura
    B("Spine", "Rock", (8.6, 6.2, 4.6), (0, 0, 15.4))
    for s in (1, -1):
        for z in (14.4, 16.4):
            B("Spine", "Plate", (3.4, 0.8, 1.6), (s * 2.0, 3.25, z))
    B("Spine", "Magma", (0.4, 0.3, 3.2), (-0.1, 3.2, 15.4), rot(y=24))
    B("Spine", "Rock", (6.0, 5.0, 3.0), (0, -1.0, 13.0))
    # peito: tronco largo, peitorais, núcleo de magma com moldura, corcunda e rachaduras
    B("Chest", "Rock", (13.2, 9.0, 6.8), (0, 0.2, 20.8))
    for s in (1, -1):
        B("Chest", "Plate", (5.6, 1.2, 4.2), (s * 3.1, 4.9, 21.6), rot(x=-6))
        B("Chest", "Trim", (5.8, 1.3, 0.5), (s * 3.1, 5.05, 23.6), rot(x=-6))
    B("Chest", "Trim", (3.2, 0.9, 3.2), (0, 4.85, 18.8))
    B("Chest", "Magma", (2.0, 1.1, 2.0), (0, 5.05, 18.8))
    B("Chest", "Ember", (0.8, 0.5, 0.8), (0, 5.45, 18.8))
    B("Chest", "Rock", (10.0, 4.4, 5.4), (0, -5.4, 22.2))
    for i, z in enumerate((20.4, 22.6, 24.6)):
        B("Chest", "Plate", (2.4 - i * 0.4, 2.0, 1.8), (0, -7.6 + i * 0.4, z), rot(x=20))
    B("Chest", "Magma", (0.4, 0.3, 4.4), (-4.4, 4.75, 19.4), rot(y=30))
    B("Chest", "Magma", (0.4, 0.3, 2.8), (4.6, 4.75, 18.6), rot(y=-38))
    B("Chest", "Magma", (0.4, 0.3, 3.6), (3.0, -7.65, 21.0), rot(y=-20))
    B("Chest", "Magma", (3.0, 0.3, 0.4), (-2.4, -7.65, 19.2), rot(y=12))
    B("Chest", "Trim", (8.0, 1.0, 1.0), (0, 4.4, 24.0))
    # cabeça afundada entre os ombros: testa pesada, olhos em brasa, mandíbula, chifres de magma
    B("Head", "Rock", (5.6, 5.6, 5.0), (0, 2.8, 25.4))
    B("Head", "Rock", (6.4, 1.8, 1.5), (0, 5.8, 26.6), rot(x=-12))
    for s in (1, -1):
        B("Head", "Ember", (1.4, 0.5, 0.6), (s * 1.4, 5.65, 25.5))
        B("Head", "Magma", (0.6, 0.5, 0.7), (s * 1.3, 6.0, 23.9))
        # chifre: sai de lado, sobe, anel dourado e ponta em brasa
        B("Head", "Magma", (3.4, 1.7, 1.7), (s * 4.3, 2.6, 27.2))
        B("Head", "Magma", (1.7, 1.7, 3.4), (s * 5.7, 2.6, 29.3))
        B("Head", "Trim", (2.0, 2.0, 0.5), (s * 5.7, 2.6, 28.3))
        B("Head", "Ember", (1.9, 1.9, 1.3), (s * 5.7, 2.6, 31.5))
        B("Head", "Rock", (1.2, 3.0, 2.2), (s * 3.1, 3.6, 24.6))
    B("Head", "Rock", (4.6, 2.4, 1.9), (0, 4.6, 23.4))
    B("Head", "Plate", (4.0, 3.6, 0.8), (0, 2.2, 28.1))

    def arm(s, n):
        x = 10.1 * s
        # ombreira: bloco escuro entre dois frisos dourados, tampo com quadrado de magma
        B("UpperArm" + n, "Rock", (7.6, 7.8, 5.4), (x, 0, 23.4))
        for z in (25.8, 21.0):
            B("UpperArm" + n, "Trim", (8.0, 8.2, 0.8), (x, 0, z))
        B("UpperArm" + n, "Magma", (4.8, 4.8, 0.3), (x, 0, 26.3))
        B("UpperArm" + n, "Rock", (2.8, 2.8, 0.45), (x, 0, 26.4))
        B("UpperArm" + n, "Ember", (1.0, 1.0, 0.55), (x, 0, 26.5))
        B("UpperArm" + n, "Plate", (1.0, 5.0, 2.4), (x + s * 4.0, 0, 23.4))
        # braço: coluna de magma listrada de pedra
        B("UpperArm" + n, "Magma", (4.0, 4.2, 5.8), (x, 0, 17.8))
        for dx in (-1.25, 0, 1.25):
            B("UpperArm" + n, "Rock", (0.55, 4.5, 5.8), (x + dx, 0, 17.8))
        B("UpperArm" + n, "Trim", (4.6, 4.8, 0.7), (x, 0, 15.2))
        # manopla: bloco enorme com três frisos e placas de fora
        f = "Forearm" + n
        B(f, "Rock", (7.4, 7.6, 8.4), (x, 0.6, 10.6))
        for z in (14.5, 10.8, 6.9):
            B(f, "Trim", (7.8, 8.0, 0.7), (x, 0.6, z))
        for z in (12.6, 8.8):
            B(f, "Plate", (0.8, 5.2, 2.8), (x + s * 3.9, 0.6, z))
        B(f, "Magma", (0.4, 0.3, 3.0), (x - s * 1.2, 4.45, 12.6), rot(y=s * 20))
        B(f, "Magma", (0.4, 0.3, 2.4), (x + s * 1.6, 4.45, 8.9), rot(y=-s * 30))
        # punho com garras de magma
        h = "Hand" + n
        B(h, "Rock", (5.4, 5.6, 4.0), (x - s * 0.1, 1.0, 4.6))
        B(h, "Trim", (5.6, 1.0, 1.0), (x - s * 0.1, 3.9, 5.8))
        for dx in (-1.75, 0, 1.75):
            B(h, "Magma", (1.3, 1.6, 2.3), (x - s * 0.1 + dx, 3.2, 1.7))
            B(h, "Ember", (1.0, 1.1, 0.7), (x - s * 0.1 + dx, 3.4, 0.4))
        B(h, "Magma", (1.3, 1.5, 2.1), (x - s * 3.0, 2.0, 3.4))

    def leg(s, n):
        x = 3.6 * s
        B("Thigh" + n, "Rock", (4.8, 5.2, 4.8), (x, 0, 8.9))
        B("Thigh" + n, "Plate", (3.6, 1.0, 2.4), (x, 2.9, 7.2))
        B("Shin" + n, "Rock", (5.0, 5.4, 4.8), (x, 0.3, 4.3))
        B("Shin" + n, "Trim", (5.4, 5.8, 0.6), (x, 0.3, 2.4))
        B("Shin" + n, "Magma", (0.35, 0.3, 2.4), (x + s * 0.8, 3.05, 4.6), rot(y=s * 18))
        B("Foot" + n, "Rock", (5.6, 6.8, 2.0), (x, 1.0, 1.0))
        for dx in (-1.8, 0, 1.8):
            B("Foot" + n, "Magma", (1.4, 1.8, 1.4), (x + dx, 4.9, 0.7))
            B("Foot" + n, "Ember", (1.1, 0.6, 0.9), (x + dx, 5.95, 0.55))

    both(arm)
    both(leg)


###################################################################################################
# Poses. Cada osso recebe (pitch, yaw, roll) em graus, nos eixos do repouso:
#   pitch (X): osso para cima, negativo inclina para a frente; osso para baixo, positivo vai para
#              a frente (joelho dobra com negativo, cotovelo com positivo, pé positivo = ponta para cima)
#   yaw (Z):   positivo vira para a esquerda (-X)
#   roll (Y):  osso para cima, positivo tomba para a direita; braço/perna direito, negativo abre
# A ordem é roll, depois pitch, depois yaw. Valores sem lado ("UpperArm") valem para os dois
# lados espelhados; com lado ("UpperArmR") só para ele, sempre escritos como se fossem o direito
# (o esquerdo é espelhado: yaw e roll trocam de sinal). "loc" desloca o quadril (x, y) e "lift"
# sobe o corpo; a altura sai sozinha, com o pé (ou joelho) mais baixo encostado no chão.

BASE_RAW = {
    "Pelvis": (-6, 0, 0), "Spine": (-10, 0, 0), "Chest": (-16, 0, 0), "Head": (28, 0, 0),
    "UpperArm": (34, 0, -5), "Forearm": (14, 0, 0), "Hand": (6, 0, 0),
    "Thigh": (14, 0, -3), "Shin": (-22, 0, 0), "Foot": (14, 0, 3),
}


def pose(*layers, **extra):
    """Junta poses: a primeira é a base, as outras sobrescrevem."""
    out = {}
    for layer in layers + (extra,):
        for k, v in layer.items():
            if k in ("UpperArm", "Forearm", "Hand", "Thigh", "Shin", "Foot"):
                out[k + "R"] = v
                out[k + "L"] = v
            else:
                out[k] = v
    return out


def legs(pelvis_pitch, r, l, base=None):
    """Pernas por (coxa, canela); o pé fica plano no chão sozinho (pitch total zero)."""
    out = {}
    for n, (t, s) in (("R", r), ("L", l)):
        out["Thigh" + n] = (t, 0, -3)
        out["Shin" + n] = (s, 0, 0)
        out["Foot" + n] = (-(pelvis_pitch + t + s), 0, 3)
    return out


def euler_q(p, y, r):
    return (Quaternion((0, 0, 1), math.radians(y)) @ Quaternion((1, 0, 0), math.radians(p)) @ Quaternion((0, 1, 0), math.radians(r)))


def bone_q(full, name):
    p, y, r = full.get(name, (0, 0, 0))
    if name.endswith("L"):
        y, r = -y, -r
    return euler_q(p, y, r)


def fk(full, loc):
    """Delta (matriz) de cada osso, em relação ao repouso."""
    D = {}
    for name in BONE_NAMES:
        h = HEADS[name]
        local = Matrix.Translation(h) @ bone_q(full, name).to_matrix().to_4x4() @ Matrix.Translation(-h)
        parent = PARENT[name]
        D[name] = (D[parent] if parent else Matrix.Translation(loc)) @ local
    return D


# pontos que podem tocar o chão: sola de cada pé (cantos e garras) e a frente do joelho
GROUND = []
for _s, _n in ((1, "R"), (-1, "L")):
    for dx in (-2.8, 2.8):
        for dy in (-2.4, 4.4):
            GROUND.append(("Foot" + _n, Vector((3.6 * _s + dx, dy, 0.0))))
    GROUND.append(("Foot" + _n, Vector((3.6 * _s, 6.2, 0.1))))
    GROUND.append(("Shin" + _n, Vector((3.6 * _s, 3.0, 6.2))))
    GROUND.append(("Thigh" + _n, Vector((3.6 * _s, 3.4, 6.2))))


def ground(full):
    x, y = full.get("loc", (0, 0))[:2]
    D = fk(full, Vector((x, y, 0)))
    low = min((D[b] @ p).z for b, p in GROUND)
    return Vector((x, y, -low + full.get("lift", 0)))


###################################################################################################
# Animações (quadros a 30 por segundo). Cada uma: lista de (quadro, pose, easing do trecho
# seguinte), loop e eventos (momento do golpe etc., em quadros).

BASE = pose(BASE_RAW)


def lerp_pose(a, b, t):
    out = {}
    for k in set(a) | set(b):
        va, vb = a.get(k), b.get(k)
        if k == "lift":
            out[k] = (va or 0) + ((vb or 0) - (va or 0)) * t
        elif va is None or vb is None:
            out[k] = va if vb is None else vb
        else:
            out[k] = tuple(x + (y - x) * t for x, y in zip(va, vb))
    return out


def cycle(table, phase):
    """Interpola uma tabela [(fase, valor)] de 0 a período, com volta suave."""
    for (f0, v0), (f1, v1) in zip(table, table[1:]):
        if f0 <= phase <= f1:
            t = (phase - f0) / (f1 - f0)
            t = t * t * (3 - 2 * t)
            return tuple(a + (b - a) * t for a, b in zip(v0, v1))
    return table[-1][1]


def gait(length, legs_table, body, step=5):
    """Ciclo de andar/correr: perna direita na fase f, esquerda meio ciclo depois."""
    keys = []
    for f in range(0, length + 1, step):
        r = cycle(legs_table, f % length)
        l = cycle(legs_table, (f + length / 2) % length)
        full = body(f / length)
        pel = full["Pelvis"][0]
        full["ThighR"], full["ShinR"] = (r[0], -full["Pelvis"][1] * 0.6, -3), (r[1], 0, 0)
        full["ThighL"], full["ShinL"] = (l[0], full["Pelvis"][1] * 0.6, -3), (l[1], 0, 0)
        full["FootR"] = (-(pel + r[0] + r[1]) + r[2], 0, 3)
        full["FootL"] = (-(pel + l[0] + l[1]) + l[2], 0, 3)
        keys.append((f, full, None))
    return keys


TAU = 2 * math.pi

# andar cansado: passo pesado, quadril rebola, braços pendurados balançam atrasados
WALK_LEGS = [(0, (30, -12, 0)), (8, (18, -26, 0)), (16, (4, -10, 0)), (27, (-18, -18, 22)), (42, (36, -64, 18)), (60, (30, -12, 0))]


def walk_body(u):
    c = math.cos(TAU * u)
    s = math.sin(TAU * u)
    return pose(BASE, {
        "Pelvis": (-6, 7 * c, 3 * s), "Spine": (-10, -3 * c, -1.5 * s), "Chest": (-17, -6 * c, -2 * s),
        "Head": (29, 8 * c, 0), "loc": (0.5 * s, 0),
        "UpperArmR": (34 - 14 * c, 0, -5), "UpperArmL": (34 + 14 * c, 0, -5),
        "ForearmR": (16 - 6 * math.cos(TAU * u - 0.8), 0, 0), "ForearmL": (16 + 6 * math.cos(TAU * u - 0.8), 0, 0),
    })


# correr: tronco jogado à frente, passadas largas, braços bombeando
RUN_LEGS = [(0, (46, -22, 0)), (4, (30, -40, 0)), (9, (8, -22, 0)), (14, (-30, -12, 30)), (22, (62, -100, 20)), (30, (46, -22, 0))]


def run_body(u):
    c = math.cos(TAU * u)
    s = math.sin(TAU * u)
    return pose(BASE, {
        "Pelvis": (-10, 9 * c, 2 * s), "Spine": (-16, -4 * c, 0), "Chest": (-28, -9 * c, -2 * s), "Head": (44, 10 * c, 0),
        "UpperArmR": (40 - 42 * c, 0, -8), "UpperArmL": (40 + 42 * c, 0, -8),
        "ForearmR": (46 - 10 * c, 0, 0), "ForearmL": (46 + 10 * c, 0, 0),
        "lift": 0.4 * abs(math.sin(TAU * u)),
    })


# ajoelhado, dormindo: joelho direito no chão, pé esquerdo à frente, punhos no chão, cabeça baixa
KNEEL = pose(BASE, {
    "Pelvis": (-20, 0, 0), "Spine": (-22, 0, 0), "Chest": (-30, 0, 0), "Head": (-6, 0, 0),
    "UpperArm": (92, 0, -8), "Forearm": (8, 0, 0), "Hand": (-24, 0, 0),
    "ThighR": (28, 0, -4), "ShinR": (-102, 0, 0), "FootR": (64, 0, 3),
    "ThighL": (102, 0, -6), "ShinL": (-86, 0, 0), "FootL": (4, 0, 3),
})

STAND_LOW = pose(BASE, {"Chest": (-22, 0, 0), "Head": (34, 0, 0)}, legs(-6, (30, -48), (30, -48)))


def clips():
    C = {}
    C["Sleep"] = dict(loop=True, keys=[
        (0, KNEEL, None),
        (60, pose(KNEEL, {"Chest": (-27, 0, 0), "Spine": (-21, 0, 0), "Head": (-3, 0, 0), "UpperArm": (90, 0, -9), "lift": 0.15}), None),
        (120, KNEEL, None),
    ], events={})

    C["Wake"] = dict(loop=False, keys=[
        (0, KNEEL, None),
        (22, pose(KNEEL, {"Head": (-2, 8, 4)}), None),
        (30, pose(KNEEL, {"Head": (-4, -4, -2)}), None),
        (44, pose(KNEEL, {"Head": (62, 0, 0), "Chest": (-26, 0, 0)}), None),
        (60, pose(KNEEL, {"Head": (58, 0, 0), "Chest": (-24, 0, 0), "UpperArm": (80, 0, -14), "Forearm": (18, 0, 0)}), None),
        (82, pose(KNEEL, {"Head": (50, 0, 0), "Pelvis": (-14, 0, 0), "Spine": (-18, 0, 0), "Chest": (-26, 0, 0), "UpperArm": (70, 0, -12),
                          "ThighR": (46, 0, -4), "ShinR": (-84, 0, 0), "FootR": (52, 0, 3), "ThighL": (70, 0, -6), "ShinL": (-76, 0, 0), "FootL": (20, 0, 3)}), None),
        (100, STAND_LOW, None),
        (112, pose(BASE, {"Pelvis": (-2, 0, 0), "Spine": (2, 0, 0), "Chest": (10, 0, 0), "Head": (34, 0, 0),
                          "UpperArm": (34, 0, -48), "Forearm": (46, 0, 0), "Hand": (20, 0, 0)}, legs(-2, (22, -34), (22, -34))), None),
        (128, pose(BASE, {"Pelvis": (-2, 0, 0), "Spine": (4, 0, 0), "Chest": (12, 0, 0), "Head": (38, 0, 0),
                          "UpperArm": (30, 0, -52), "Forearm": (50, 0, 0), "Hand": (22, 0, 0)}, legs(-2, (20, -30), (20, -30))), None),
        (150, BASE, None),
    ], events={"eyes": 44, "roar": 110})

    C["Idle"] = dict(loop=True, keys=[
        (0, BASE, None),
        (45, pose(BASE, {"Spine": (-9, 2, 0), "Chest": (-12, 1, 1), "Head": (25, -2, 0), "UpperArm": (32, 0, -7), "Forearm": (12, 0, 0), "lift": 0.12}), None),
        (90, BASE, None),
    ], events={})

    C["Walk"] = dict(loop=True, keys=gait(60, WALK_LEGS, walk_body), events={})
    C["Run"] = dict(loop=True, keys=gait(30, RUN_LEGS, run_body, step=3), events={})

    # Pisão Sísmico: arrasta o pé, joga o peso, ergue a perna sem pular e deixa o pé despencar
    prep = pose(BASE, {"loc": (-1.2, 0), "Spine": (-10, 0, -6), "Chest": (-16, 0, -4)},
                {"ThighR": (0, 0, -3), "ShinR": (-30, 0, 0), "FootR": (36, 0, 3), "ThighL": (24, 0, -3), "ShinL": (-36, 0, 0), "FootL": (18, 0, 3)})
    lifted = pose(prep, {"loc": (-1.7, 0), "Spine": (-6, 0, -11), "Chest": (-10, 0, -7), "Head": (24, 0, 6),
                         "UpperArmR": (30, 0, -26), "UpperArmL": (34, 0, -22),
                         "ThighR": (62, 0, -3), "ShinR": (-50, 0, 0), "FootR": (8, 0, 3)})
    C["Stomp"] = dict(loop=False, keys=[
        (0, BASE, None),
        (12, prep, None),
        (18, lifted, None),
        (20, pose(lifted, {"Spine": (-5, 0, -13), "Chest": (-9, 0, -9)}), ("QUAD", "EASE_IN")),
        (22, pose(BASE, {"loc": (-0.4, 0), "Spine": (-14, 0, -2), "Chest": (-28, 0, 0), "Head": (36, 0, 0),
                         "UpperArm": (46, 0, -3), "Forearm": (24, 0, 0)}, legs(-6, (26, -16), (26, -38))), None),
        (26, pose(BASE, {"loc": (-0.2, 0), "Spine": (-13, 0, 0), "Chest": (-30, 0, 0), "Head": (38, 0, 0),
                         "UpperArm": (54, 0, -2), "Forearm": (32, 0, 0)}, legs(-6, (24, -22), (24, -34))), None),
        (32, pose(BASE, {"Chest": (-20, 0, 0), "UpperArm": (32, 0, -6), "Forearm": (12, 0, 0)}, legs(-6, (18, -24), (18, -26))), None),
        (42, BASE, None),
    ], events={"impact": 22})

    # Golpe de Arrasto: vira o corpo para a direita com o braço atrás, quase raspando o chão, e
    # varre da direita para a esquerda; o quadril começa, o tronco segue, a mão chega por último
    wind = pose(BASE, {"loc": (0.6, -0.4), "Pelvis": (-8, -18, 0), "Spine": (-14, -12, 0), "Chest": (-24, -14, 0), "Head": (32, 22, 0),
                       "UpperArmR": (-14, 0, -42), "ForearmR": (6, 0, 0), "UpperArmL": (44, 0, -8)},
                legs(-8, (12, -34), (20, -36)), {"ThighR": (12, 18, -10), "ThighL": (20, 18, -6)})
    C["Sweep"] = dict(loop=False, keys=[
        (0, BASE, None),
        (10, wind, None),
        (12, pose(wind, {"Pelvis": (-8, -8, 0), "ThighR": (12, 8, -10), "ThighL": (20, 8, -6)}), ("QUAD", "EASE_IN")),
        (15, pose(wind, {"Pelvis": (-8, 6, 0), "Spine": (-14, 2, 0), "Chest": (-22, -2, 0), "UpperArmR": (40, -50, -30),
                         "ThighR": (12, -6, -10), "ThighL": (20, -6, -6)}), ("QUAD", "EASE_IN")),
        (18, pose(wind, {"loc": (0, 0.4), "Pelvis": (-8, 20, 0), "Spine": (-14, 14, 0), "Chest": (-20, 22, 0), "Head": (30, 6, 0),
                         "UpperArmR": (80, -10, -6), "ForearmR": (8, 0, 0), "UpperArmL": (24, 0, -40),
                         "ThighR": (12, -20, -10), "ThighL": (20, -20, -6)}), None),
        (20, pose(wind, {"loc": (-0.4, 0.6), "Pelvis": (-8, 26, 0), "Spine": (-14, 18, 0), "Chest": (-20, 28, 0), "Head": (30, -8, 0),
                         "UpperArmR": (80, 34, 0), "ForearmR": (10, 0, 0), "UpperArmL": (20, 0, -46),
                         "ThighR": (12, -26, -10), "ThighL": (20, -26, -6)}), None),
        (23, pose(wind, {"loc": (-0.6, 0.6), "Pelvis": (-8, 32, 0), "Spine": (-14, 20, 0), "Chest": (-22, 34, 0), "Head": (32, -12, 0),
                         "UpperArmR": (70, 48, 0), "ForearmR": (16, 0, 0), "UpperArmL": (22, 0, -40),
                         "ThighR": (12, -32, -10), "ThighL": (20, -32, -6)}), None),
        (30, pose(BASE, {"Pelvis": (-8, 12, 0), "Chest": (-20, 10, 0), "UpperArmR": (52, 16, -4), "ForearmR": (14, 0, 0)},
                  legs(-8, (16, -30), (18, -32)), {"ThighR": (16, -12, -6), "ThighL": (18, -12, -4)}), None),
        (38, BASE, None),
    ], events={"impact": 19})

    # Esmagamento de Punhos: ergue os dois punhos devagar, pausa, e despenca o corpo inteiro
    raised = pose(BASE, {"Spine": (-8, 0, 0), "Chest": (-12, 0, 0), "Head": (12, 0, 0),
                         "UpperArm": (166, 0, 8), "Forearm": (56, 0, 0), "Hand": (10, 0, 0)}, legs(-6, (28, -44), (28, -44)))
    down = pose(BASE, {"Pelvis": (-16, 0, 0), "Spine": (-28, 0, 0), "Chest": (-58, 0, 0), "Head": (60, 0, 0),
                       "UpperArm": (150, 0, 6), "Forearm": (12, 0, 0), "Hand": (-10, 0, 0)}, legs(-16, (66, -88), (66, -88)))
    C["Slam"] = dict(loop=False, keys=[
        (0, BASE, None),
        (10, pose(BASE, {"UpperArm": (70, 0, 10), "Forearm": (70, 0, 0), "Chest": (-20, 0, 0)}, legs(-6, (22, -34), (22, -34))), None),
        (18, raised, None),
        (22, pose(raised, {"Chest": (-10, 0, 2), "UpperArm": (169, 0, 7)}), None),
        (26, pose(raised, {"Chest": (-8, 0, -1), "UpperArm": (172, 0, 8), "lift": 0.3}, legs(-6, (18, -28), (18, -28))), ("CUBIC", "EASE_IN")),
        (31, down, None),
        (34, pose(down, {"Chest": (-61, 0, 0), "Head": (62, 0, 0)}), None),
        (46, pose(down, {"Chest": (-57, 0, 2), "Head": (52, 0, 0)}), None),
        (52, pose(BASE, {"Pelvis": (-12, 0, 0), "Spine": (-20, 0, 0), "Chest": (-40, 0, 0), "Head": (48, 0, 0), "UpperArm": (96, 0, -2), "Forearm": (20, 0, 0)},
                  legs(-12, (46, -62), (46, -62))), None),
        (60, BASE, None),
    ], events={"impact": 31})

    # Pulso Ancestral: concentra, mão direita no peito, esquerda no chão, descarga pela palma e
    # termina exausto, com o braço apoiado no joelho
    crouch = pose(BASE, {"Pelvis": (-12, 0, 0), "Spine": (-18, 0, 0), "Chest": (-32, 0, 0), "Head": (30, 0, 6),
                         "UpperArmR": (62, 42, 0), "ForearmR": (100, 0, 0), "UpperArmL": (92, 0, -10), "ForearmL": (2, 0, 0), "HandL": (-40, 0, 0)},
                  legs(-12, (34, -56), (44, -62)))
    C["Pulse"] = dict(loop=False, keys=[
        (0, BASE, None),
        (12, pose(BASE, {"Head": (18, 0, 14), "UpperArm": (30, 0, -2), "Forearm": (8, 0, 0), "Chest": (-14, 0, 0)}), None),
        (18, pose(BASE, {"Head": (22, 0, 10), "Chest": (-18, 0, 0), "UpperArmR": (62, 42, 0), "ForearmR": (100, 0, 0), "UpperArmL": (34, 0, -6)}), None),
        (27, crouch, ("QUAD", "EASE_IN")),
        (30, pose(crouch, {"Chest": (-36, 0, 0), "UpperArmL": (98, 0, -8), "HandL": (-50, 0, 0)}, legs(-12, (38, -64), (50, -74))), None),
        (33, pose(crouch, {"Chest": (-27, 0, 0), "Head": (38, 0, 0), "UpperArmL": (96, 0, -8)}, legs(-12, (38, -62), (50, -72))), None),
        (42, pose(crouch, {"Chest": (-36, 0, 0), "Head": (4, 0, 0), "UpperArmR": (62, 10, -2), "ForearmR": (40, 0, 0), "UpperArmL": (60, 0, -4), "HandL": (0, 0, 0)},
                  legs(-12, (40, -60), (40, -60))), None),
        (54, pose(crouch, {"Chest": (-34, 0, 0), "Head": (8, 0, 0), "UpperArmR": (62, 10, -2), "ForearmR": (42, 0, 0), "UpperArmL": (56, 0, -4), "HandL": (0, 0, 0), "lift": 0.15},
                  legs(-12, (38, -58), (38, -58))), None),
        (66, BASE, None),
    ], events={"charge": 0, "gather": 19, "pulse": 30})

    # Corrida + ataque: freia plantando o pé, gira armando o braço baixo e solta um gancho de
    # baixo para cima com o corpo inteiro; depois fica ofegante
    run0 = gait(30, RUN_LEGS, run_body, step=3)[0][1]
    cock = pose(BASE, {"loc": (0, 0.6), "Pelvis": (-6, -20, 0), "Spine": (-14, -12, 0), "Chest": (-26, -26, 0), "Head": (40, 30, 0),
                       "UpperArmR": (-46, 0, -24), "ForearmR": (34, 0, 0), "UpperArmL": (58, 0, -10), "ForearmL": (30, 0, 0)},
                legs(-6, (40, -40), (-8, -44)), {"ThighR": (40, 20, -6), "ThighL": (-8, 20, -4)})
    C["Charge"] = dict(loop=False, keys=[
        (0, run0, None),
        (6, cock, None),
        (11, pose(cock, {"Chest": (-30, -32, 0), "UpperArmR": (-52, 0, -26)}, legs(-6, (46, -52), (-6, -50)), {"ThighR": (46, 20, -6), "ThighL": (-6, 20, -4)}), ("CUBIC", "EASE_IN")),
        (17, pose(BASE, {"loc": (0, 1.6), "Pelvis": (-2, 18, 0), "Spine": (-2, 14, 0), "Chest": (8, 24, 0), "Head": (22, -6, 0),
                         "UpperArmR": (150, 10, 18), "ForearmR": (22, 0, 0), "UpperArmL": (20, 0, -36), "ForearmL": (30, 0, 0)},
                  legs(-2, (24, -10), (-20, -12)), {"ThighR": (24, -18, -4), "ThighL": (-20, -18, -4)}), None),
        (21, pose(BASE, {"loc": (0, 1.8), "Pelvis": (-2, 22, 0), "Spine": (0, 16, 0), "Chest": (12, 30, 0), "Head": (20, -8, 0),
                         "UpperArmR": (166, 16, 22), "ForearmR": (26, 0, 0), "UpperArmL": (16, 0, -40)},
                  legs(-2, (24, -10), (-20, -12)), {"ThighR": (24, -22, -4), "ThighL": (-20, -22, -4)}), None),
        (34, pose(BASE, {"loc": (0, 1.2), "Chest": (-24, 8, 0), "Head": (34, 0, 0), "UpperArmR": (56, 0, -4), "ForearmR": (20, 0, 0)},
                  legs(-6, (26, -36), (10, -30))), None),
        (54, BASE, None),
    ], events={"impact": 17})

    # Morte: cambaleia para trás, cai de joelhos, desaba para a frente e se desfaz
    knees = pose(BASE, {"loc": (0, -1.0), "Pelvis": (-4, 0, 0), "Spine": (-6, 0, 0), "Chest": (-4, 0, 0), "Head": (34, 0, 6),
                        "UpperArm": (8, 0, -10), "Forearm": (10, 0, 0),
                        "ThighR": (8, 0, -6), "ShinR": (-96, 0, 0), "FootR": (64, 0, 3), "ThighL": (8, 0, -6), "ShinL": (-96, 0, 0), "FootL": (64, 0, 3)})
    C["Death"] = dict(loop=False, keys=[
        (0, BASE, None),
        (14, pose(BASE, {"loc": (0, -1.6), "Spine": (-2, 0, 0), "Chest": (4, 0, 4), "Head": (48, 0, 8), "UpperArm": (12, 0, -30), "Forearm": (30, 0, 0)},
                  legs(-6, (6, -14), (24, -30))), None),
        (24, pose(BASE, {"loc": (0, -1.4), "Chest": (-6, 0, -3), "Head": (40, 0, -4), "UpperArm": (16, 0, -20)}, legs(-6, (30, -60), (30, -60))), None),
        (40, knees, None),
        (56, pose(knees, {"Head": (20, 0, 0)}), None),
        (72, pose(knees, {"loc": (0, -0.6), "Pelvis": (-22, 0, 0), "Spine": (-28, 0, 0), "Chest": (-56, 0, 0), "Head": (30, 0, 0), "UpperArm": (118, 0, -12), "Forearm": (6, 0, 0),
                          "ThighR": (30, 0, -6), "ShinR": (-102, 0, 0), "FootR": (64, 0, 3), "ThighL": (30, 0, -6), "ShinL": (-102, 0, 0), "FootL": (64, 0, 3)}), None),
        (88, pose(knees, {"loc": (0, -0.6), "Pelvis": (-24, 0, 0), "Spine": (-30, 0, 0), "Chest": (-60, 0, 0), "Head": (-14, 0, 0), "UpperArm": (122, 0, -14), "Forearm": (4, 0, 0),
                          "ThighR": (32, 0, -6), "ShinR": (-102, 0, 0), "FootR": (64, 0, 3), "ThighL": (32, 0, -6), "ShinL": (-102, 0, 0), "FootL": (64, 0, 3)}), None),
        (100, pose(knees, {"loc": (0, -0.6), "Pelvis": (-24, 0, 0), "Spine": (-30, 0, 0), "Chest": (-60, 0, 0), "Head": (-16, 0, 0), "UpperArm": (122, 0, -14), "Forearm": (4, 0, 0),
                           "ThighR": (32, 0, -6), "ShinR": (-102, 0, 0), "FootR": (64, 0, 3), "ThighL": (32, 0, -6), "ShinL": (-102, 0, 0), "FootL": (64, 0, 3)}), None),
    ], events={"crumble": 88})
    return C


###################################################################################################
# Blender: armadura, peças presas aos ossos, uma ação por animação

def make_armature():
    data = bpy.data.armatures.new("Golem")
    arm = bpy.data.objects.new("Golem", data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name, head, tail, parent in BONES:
        eb = data.edit_bones.new(name)
        eb.head = Vector(head)
        eb.tail = Vector(tail)
        eb.roll = 0
        if parent:
            eb.parent = data.edit_bones[parent]
            eb.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return arm


def channelbag_fcurves(act):
    try:
        return list(act.fcurves)
    except AttributeError:
        pass
    out = []
    for layer in act.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                out.extend(bag.fcurves)
    return out


def key_clip(arm, name, clip):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = act
    rest = {b.name: b.matrix_local.to_quaternion() for b in arm.data.bones}
    last = {}
    ease_frames = {}
    for frame, full, ease in clip["keys"]:
        loc = ground(full)
        for pb in arm.pose.bones:
            R = rest[pb.name]
            q = R.inverted() @ bone_q(full, pb.name) @ R
            if pb.name in last and last[pb.name].dot(q) < 0:
                q = -q
            last[pb.name] = q
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            if pb.name == "Pelvis":
                pb.location = R.inverted() @ loc
                pb.keyframe_insert("location", frame=frame)
        if ease:
            ease_frames[frame] = ease
    if ease_frames:
        for fc in channelbag_fcurves(act):
            for kp in fc.keyframe_points:
                e = ease_frames.get(int(round(kp.co.x)))
                if e:
                    kp.interpolation = e[0]
                    kp.easing = e[1]
    return act


def bake_clip(arm, act, clip):
    """Rotação de cada osso (no pai, nos eixos do repouso) e posição do quadril, quadro a quadro."""
    arm.animation_data.action = act
    if arm.animation_data.action_slot is None and len(act.slots) > 0:
        arm.animation_data.action_slot = act.slots[0]
    length = clip["keys"][-1][0]
    frames = list(range(0, length + 1, BAKE_STEP))
    if frames[-1] != length:
        frames.append(length)
    scene = bpy.context.scene
    rest = {b.name: b.matrix_local for b in arm.data.bones}
    rows = []
    for f in frames:
        scene.frame_set(f)
        D = {pb.name: pb.matrix @ rest[pb.name].inverted() for pb in arm.pose.bones}
        row = []
        for name in BONE_NAMES:
            parent = PARENT[name]
            rel = (D[parent].inverted() @ D[name]) if parent else D[name]
            q = rel.to_quaternion().normalized()
            if q.w < 0:
                q = -q
            if name == "Pelvis":
                h = HEADS[name]
                loc = D[name].translation - h + q @ h
                row += [loc.x, loc.z, -loc.y]  # Blender (x, y, z) -> Roblox (x, z, -y)
            row += [q.x, q.z, -q.y]
        rows.append(row)
    return frames, rows


def fmt(v):
    s = f"{v:.3f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def write_anims(baked, C):
    lines = [
        "--!strict",
        "-- Gerado por tools/blender/golem.py: não edite à mão. Rotação de cada osso do golem, quadro a",
        "-- quadro, para src/client/Boss.luau mover as peças e src/server/Boss.luau saber quando cada",
        "-- golpe acerta. Eixos do Roblox, em studs, com o modelo na escala 1.",
        "-- frames[i] = { quadril x, y, z, depois x, y, z do quaternion de cada osso (w >= 0) }",
        "",
        "return {",
        f"\tfps = {FPS // BAKE_STEP},",
        "\tbones = { " + ", ".join(f'"{n}"' for n in BONE_NAMES) + " },",
        "\tparents = { " + ", ".join(str(BONE_NAMES.index(PARENT[n]) + 1 if PARENT[n] else 0) for n in BONE_NAMES) + " },",
        "\theads = { " + ", ".join(f"{fmt(HEADS[n].x)}, {fmt(HEADS[n].z)}, {fmt(-HEADS[n].y)}" for n in BONE_NAMES) + " },",
        "\tclips = {",
    ]
    for name, (frames, rows) in baked.items():
        clip = C[name]
        length = clip["keys"][-1][0] / FPS
        events = ", ".join(f"{k} = {fmt(v / FPS)}" for k, v in sorted(clip["events"].items()))
        lines.append(f"\t\t{name} = {{")
        lines.append(f"\t\t\tloop = {'true' if clip['loop'] else 'false'},")
        lines.append(f"\t\t\tlength = {fmt(length)},")
        lines.append(f"\t\t\tevents = {{ {events} }},")
        lines.append("\t\t\ttimes = { " + ", ".join(fmt(f / FPS) for f in frames) + " },")
        lines.append("\t\t\tframes = {")
        for row in rows:
            lines.append("\t\t\t\t{ " + ", ".join(fmt(v) for v in row) + " },")
        lines.append("\t\t\t},")
        lines.append("\t\t},")
    lines += ["\t},", "}", ""]
    with open(ANIMS, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print("animações:", ANIMS, os.path.getsize(ANIMS))


def main():
    kit.clean_scene()
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    for a in list(bpy.data.armatures):
        bpy.data.armatures.remove(a)
    scene = bpy.context.scene
    scene.render.fps = FPS

    build_mesh()
    # um objeto por (tipo, osso); os marcadores do kit ficam soltos, só para o jogo achar a escala
    collection = bpy.data.collections.new("golem")
    scene.collection.children.link(collection)
    objects = []
    tris = 0
    for bone, k in kits.items():
        k.name = bone  # objetos "<Tipo>_<Osso>"
        k.markers = lambda: None
        bpy.context.scene.collection.children.link(bpy.data.collections.new("tmp_" + bone))
        for ob in k.build(COLORS, GLOW):
            tris += len(ob.data.polygons)
            for c in list(ob.users_collection):
                c.objects.unlink(ob)
            collection.objects.link(ob)
            objects.append(ob)
    for c in list(bpy.data.collections):
        if c.name.startswith("tmp_") or (c.name in BONE_NAMES and len(c.objects) == 0):
            bpy.data.collections.remove(c)
    marks = kit.Kit("golem")
    marks.markers()
    for ob in marks.build(COLORS):
        objects.append(ob)
    print("golem: triângulos", tris, "objetos", len(objects))

    # exporta em repouso, antes de prender as peças aos ossos
    exporter = kit.Kit("golem")
    exporter.objects = objects
    exporter.export(MODELS)

    arm = make_armature()
    for ob in objects:
        bone = ob.name.split("_", 1)[1]
        if bone in BONE_NAMES:
            world = ob.matrix_world.copy()
            ob.parent = arm
            ob.parent_type = "BONE"
            ob.parent_bone = bone
            bpy.context.view_layer.update()
            ob.matrix_world = world
        else:
            ob.hide_render = True
            ob.hide_viewport = True

    C = clips()
    baked = {}
    actions = {}
    for name, clip in C.items():
        actions[name] = key_clip(arm, name, clip)
    for name, clip in C.items():
        baked[name] = bake_clip(arm, actions[name], clip)
    write_anims(baked, C)

    if SNAP:
        os.makedirs(SNAP, exist_ok=True)
        for name, clip in C.items():
            arm.animation_data.action = actions[name]
            length = clip["keys"][-1][0]
            picks = sorted(set([0] + [f for f, _, _ in clip["keys"]] + list(clip["events"].values())))
            for f in picks:
                scene.frame_set(f)
                kit.snapshot(os.path.join(SNAP, f"{name}_{f:03d}_a.png"), (30, 38, 22), (0, 2, 13), 35, (300, 300))
                kit.snapshot(os.path.join(SNAP, f"{name}_{f:03d}_b.png"), (50, 2, 14), (0, 2, 13), 35, (300, 300))
            if name == "Idle":
                scene.frame_set(0)
                kit.snapshot(os.path.join(SNAP, "front.png"), (0, 60, 16), (0, 0, 15), 35, (700, 700))
                kit.snapshot(os.path.join(SNAP, "side.png"), (60, 4, 16), (0, 0, 15), 35, (700, 700))
                kit.snapshot(os.path.join(SNAP, "back.png"), (-30, -50, 30), (0, 0, 15), 35, (700, 700))
        arm.animation_data.action = actions["Idle"]

    os.makedirs(os.path.dirname(BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)


main()
