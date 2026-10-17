# EXPERIMENTOS (reversíveis): animações novas de golpes do golem, uma por golpe ("SlamV2",
# "ChargeV2"...). Cada uma é ligada por uma chave em Config.Boss (slamV2, chargeV2) e injetada em
# GolemAnims por src/shared/GolemExperiment.luau. Método: skill roblox-boss-attack-overhaul.
#
# Não mexe em tools/blender/golem.py nem em src/shared/GolemAnims.luau: carrega o esqueleto, as
# poses e o bake de lá (executa o golem.py sem o main()) e grava só os clips daqui em
# src/shared/GolemAnimsV2.luau, a 30 quadros por segundo (o impacto pode cair num quadro ímpar).
#
#   blender -b --factory-startup -P tools/blender/golem_v2.py
#   SNAP=<pasta> grava prévias de cada quadro par (o novo e o original lado a lado no nome)
#   ONLY=ChargeV2 limita as prévias a um clip
#
# A mecânica (dano, raio, alcance) é a do Config; o momento do dano é o evento "impact" do clip.

import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

_src = open(os.path.join(HERE, "golem.py"), encoding="utf-8").read().rstrip()
assert _src.endswith("main()"), "golem.py mudou: o fim não é mais main()"
G = {"__file__": os.path.join(HERE, "golem.py"), "__name__": "golem_lib"}
exec(compile(_src[: -len("main()")], "golem.py", "exec"), G)

pose, legs, BASE = G["pose"], G["legs"], G["BASE"]
ROOT = G["ROOT"]
OUT = os.path.join(ROOT, "src", "shared", "GolemAnimsV2.luau")
SNAP = os.environ.get("SNAP")
ONLY = os.environ.get("ONLY")
FPS = G["FPS"]

# ponta do punho no osso da mão (lado direito; o esquerdo é espelhado)
FIST = {"R": Vector((10.0, 0.8, 1.2)), "L": Vector((-10.0, 0.8, 1.2))}


def fist_z(full, side="R"):
    D = G["fk"](full, G["ground"](full))
    return (D["Hand" + side] @ FIST[side]).z


def plant(full, depth, sides=("R", "L")):
    """Acha o ângulo do ombro que deixa a ponta do(s) punho(s) `depth` studs abaixo do chão: o
    punho fica enterrado de verdade, sem atravessar o piso (busca binária no pitch do ombro)."""
    out = dict(full)
    for side in sides:
        key = "UpperArm" + side
        _, yaw, roll = out[key]
        lo, hi = 60.0, 180.0

        def z(a):
            test = dict(out)
            test[key] = (a, yaw, roll)
            if len(sides) == 2:
                other = "UpperArm" + ("L" if side == "R" else "R")
                test[other] = (a, out[other][1], out[other][2])
            return fist_z(test, side)

        rising = z(hi) > z(lo)
        for _ in range(40):
            mid = (lo + hi) / 2
            if (z(mid) > -depth) == rising:
                hi = mid
            else:
                lo = mid
        a = (lo + hi) / 2
        out[key] = (a, yaw, roll)
        if len(sides) == 2:
            other = "UpperArm" + ("L" if side == "R" else "R")
            out[other] = (a, out[other][1], out[other][2])
            break
    return out


###################################################################################################
# Esmagamento de Punhos (Config.Boss.slamV2)
#   antecipação (0-26): afunda e enrola, depois sobe esticando o corpo inteiro, arqueia para trás
#     com os punhos juntos lá no alto e segura, tremendo;
#   execução (26-33): o quadril desce primeiro, o tronco dobra e os braços chegam por último;
#   impacto (33): punhos enterrados, joelhos dobrados, cabeça erguida olhando o alvo;
#   assentamento (33-38): o peso continua descendo depois do contato e devolve um pouco;
#   erupção (38-50): segura os punhos no chão, empurrando (os espinhos saem nessa hora);
#   recuperação (50-68): arranca os punhos, endireita em dois tempos e volta ao repouso.

def slam_v2():
    load = pose(BASE, {"loc": (0, -0.5), "Pelvis": (-10, 0, 0), "Spine": (-14, 0, 0), "Chest": (-24, 0, 0), "Head": (40, 0, 0),
                       "UpperArm": (6, 0, -18), "Forearm": (30, 0, 0), "Hand": (-8, 0, 0)}, legs(-10, (40, -64), (40, -64)))
    rise = pose(BASE, {"loc": (0, -0.6), "Pelvis": (-2, 0, 0), "Spine": (4, 0, 0), "Chest": (12, 0, 0), "Head": (16, 0, 0),
                       "UpperArm": (142, 0, 20), "Forearm": (40, 0, 0), "Hand": (8, 0, 0), "lift": 0.5}, legs(-2, (12, -18), (12, -18)))
    top = pose(BASE, {"loc": (0, -0.9), "Pelvis": (0, 0, 0), "Spine": (8, 0, 0), "Chest": (20, 0, 0), "Head": (6, 0, 0),
                      "UpperArm": (172, 0, 6), "Forearm": (26, 0, 0), "Hand": (14, 0, 0), "lift": 0.8}, legs(0, (8, -12), (8, -12)))
    hang = pose(top, {"Spine": (9, 0, 1), "Chest": (23, 0, -1), "Head": (4, 0, 0), "UpperArm": (176, 0, 4), "Forearm": (32, 0, 0), "lift": 0.9})
    swing = pose(BASE, {"loc": (0, 0.2), "Pelvis": (-10, 0, 0), "Spine": (-12, 0, 0), "Chest": (-22, 0, 0), "Head": (36, 0, 0),
                        "UpperArm": (168, 0, 6), "Forearm": (34, 0, 0), "Hand": (6, 0, 0), "lift": 0.4}, legs(-10, (40, -58), (40, -58)))
    impact = plant(pose(BASE, {"loc": (0, 0.9), "Pelvis": (-20, 0, 0), "Spine": (-32, 0, 0), "Chest": (-62, 0, 0), "Head": (66, 0, 0),
                               "UpperArm": (150, 0, 5), "Forearm": (10, 0, 0), "Hand": (-14, 0, 0)}, legs(-20, (72, -96), (72, -96))), 0.6)
    squash = plant(pose(impact, {"Pelvis": (-22, 0, 0), "Spine": (-34, 0, 0), "Chest": (-66, 0, 0), "Head": (70, 0, 0)},
                        legs(-22, (78, -104), (78, -104))), 1.1)
    rebound = plant(pose(impact, {"Chest": (-60, 0, 0), "Head": (62, 0, 0)}), 0.8)
    press_a = plant(pose(impact, {"Chest": (-61, 0, 3), "Spine": (-32, 0, 2), "Head": (58, 0, -3)}), 0.8)
    press_b = plant(pose(impact, {"Chest": (-60, 0, -2), "Spine": (-31, 0, -1), "Head": (56, 0, 2)}), 0.8)
    pull = pose(BASE, {"loc": (0, 0.5), "Pelvis": (-14, 0, 0), "Spine": (-20, 0, 0), "Chest": (-40, 0, 0), "Head": (50, 0, 0),
                       "UpperArm": (98, 0, -4), "Forearm": (26, 0, 0), "Hand": (4, 0, 0)}, legs(-14, (50, -68), (50, -68)))
    settle = pose(BASE, {"loc": (0, 0.2), "Pelvis": (-8, 0, 0), "Spine": (-12, 0, 0), "Chest": (-22, 0, 0), "Head": (34, 0, 0),
                         "UpperArm": (44, 0, -6), "Forearm": (18, 0, 0), "lift": 0.08}, legs(-8, (30, -44), (30, -44)))
    keys = [
        (0, BASE, None),
        (8, load, ("SINE", "EASE_OUT")),
        (16, rise, None),
        (22, top, None),
        (26, hang, ("CUBIC", "EASE_IN")),
        (30, swing, ("QUAD", "EASE_IN")),
        (33, impact, None),
        (35, squash, ("QUAD", "EASE_OUT")),
        (38, rebound, None),
        (43, press_a, None),
        (48, press_b, None),
        (53, pull, ("SINE", "EASE_IN_OUT")),
        (60, settle, None),
        (68, BASE, None),
    ]
    return dict(loop=False, keys=keys, events={"impact": 33, "rise": 16, "hang": 22})


###################################################################################################
# Gancho da corrida (Config.Boss.chargeV2). Chega correndo; o impacto continua perto do original
# (0,60 s contra 0,57 s) porque o servidor solta o golpe já em cima do jogador.
#   freada (0-5): finca o pé da frente, joga o tronco para trás, braços abrem para equilibrar;
#   armação (5-13): gira o quadril e o tronco para a direita, agacha, o braço direito vai baixo e
#     para trás, a cabeça fica no alvo; segura tremendo;
#   execução (13-18): o quadril gira primeiro, o ombro depois, o punho por último;
#   impacto (18): o punho crava no chão à frente, o corpo todo atrás dele;
#   arrancada (18-28): o punho rasga o chão e sobe num gancho, o corpo inteiro estica e sai do chão;
#   recuperação (28-56): desce pesado, ofegante, e volta ao repouso.

def charge_v2():
    run0 = G["gait"](30, G["RUN_LEGS"], G["run_body"], step=3)[0][1]
    brake = pose(BASE, {"loc": (0, 0.8), "Pelvis": (-2, -8, 0), "Spine": (-4, -6, 0), "Chest": (-8, -10, 0), "Head": (26, 10, 0),
                        "UpperArmR": (20, 0, -34), "ForearmR": (50, 0, 0), "UpperArmL": (46, 0, -26), "ForearmL": (40, 0, 0)},
                 legs(-2, (52, -28), (-18, -40)), {"ThighR": (52, 8, -6), "ThighL": (-18, 8, -4)})
    coil = pose(BASE, {"loc": (0, 1.0), "Pelvis": (-12, -26, 0), "Spine": (-18, -16, 0), "Chest": (-34, -30, 0), "Head": (52, 34, 0),
                       "UpperArmR": (-24, 0, -8), "ForearmR": (62, 0, 0), "HandR": (-10, 0, 0), "UpperArmL": (60, 0, -14), "ForearmL": (54, 0, 0)},
                legs(-12, (64, -72), (2, -58)), {"ThighR": (64, 24, -6), "ThighL": (2, 24, -4)})
    hang = pose(coil, {"Chest": (-38, -34, 0), "Head": (54, 36, 0), "UpperArmR": (-30, 0, -8), "ForearmR": (66, 0, 0), "Spine": (-19, -18, 0)})
    smash = plant(pose(BASE, {"loc": (0, 1.6), "Pelvis": (-18, 4, 0), "Spine": (-24, 8, 0), "Chest": (-48, 16, 0), "Head": (58, -6, 0),
                              "UpperArmR": (120, 8, 4), "ForearmR": (8, 0, 0), "HandR": (-18, 0, 0), "UpperArmL": (24, 0, -44), "ForearmL": (30, 0, 0)},
                       legs(-18, (72, -86), (8, -62)), {"ThighR": (72, -6, -6), "ThighL": (8, -6, -4)}), 0.5, ("R",))
    grind = plant(pose(smash, {"Chest": (-45, 19, 0), "Spine": (-22, 10, 0), "Head": (56, -8, 0)}), 0.4, ("R",))
    rip = pose(BASE, {"loc": (0, 2.0), "Pelvis": (-2, 18, 0), "Spine": (0, 14, 0), "Chest": (12, 26, 0), "Head": (22, -8, 0),
                      "UpperArmR": (164, 14, 20), "ForearmR": (22, 0, 0), "HandR": (10, 0, 0), "UpperArmL": (16, 0, -42), "ForearmL": (30, 0, 0), "lift": 0.5},
               legs(-2, (22, -8), (-20, -12)), {"ThighR": (22, -20, -4), "ThighL": (-20, -20, -4)})
    follow = pose(rip, {"Chest": (16, 30, 0), "UpperArmR": (172, 16, 22), "Head": (18, -10, 0), "lift": 0.7})
    land = pose(BASE, {"loc": (0, 1.4), "Pelvis": (-8, 6, 0), "Chest": (-28, 8, 0), "Head": (38, 0, 0), "UpperArmR": (60, 0, -4), "ForearmR": (22, 0, 0)},
                legs(-8, (34, -48), (12, -36)))
    breathe = pose(BASE, {"loc": (0, 1.2), "Chest": (-22, 4, 0), "Head": (34, 0, 0), "UpperArmR": (48, 0, -5), "lift": 0.06},
                   legs(-6, (22, -32), (18, -30)))
    keys = [
        (0, run0, None),
        (5, brake, ("SINE", "EASE_OUT")),
        (10, coil, None),
        (13, hang, ("CUBIC", "EASE_IN")),
        (18, smash, None),
        (20, grind, ("QUAD", "EASE_OUT")),
        (24, rip, None),
        (28, follow, ("SINE", "EASE_IN_OUT")),
        (38, land, None),
        (46, breathe, None),
        (56, BASE, None),
    ]
    return dict(loop=False, keys=keys, events={"impact": 18, "brake": 5, "coil": 10, "rip": 22})


CLIPS = {"SlamV2": (slam_v2, "Slam"), "ChargeV2": (charge_v2, "Charge")}


def fist_heights(clip, side="R"):
    """Altura (Z) da ponta do punho em cada chave: no contato com o chão tem que dar perto de 0."""
    return [(frame, round(fist_z(full, side), 2)) for frame, full, _ in clip["keys"]]


def main():
    G["kit"].clean_scene()
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    for a in list(bpy.data.armatures):
        bpy.data.armatures.remove(a)
    scene = bpy.context.scene
    scene.render.fps = FPS

    built = {name: make() for name, (make, _) in CLIPS.items()}
    originals = G["clips"]()
    for name, clip in built.items():
        print(name, "punho (quadro, z):", fist_heights(clip))
        print(name, "original:", fist_heights(originals[CLIPS[name][1]]))

    objects = []
    if SNAP:
        # modelo só para as prévias (o jogo usa o modelo que já foi enviado)
        G["build_mesh"]()
        for bone, k in G["kits"].items():
            k.name = bone
            k.markers = lambda: None
            for ob in k.build(G["COLORS"], G["GLOW"]):
                objects.append(ob)

    arm = G["make_armature"]()
    for ob in objects:
        bone = ob.name.split("_", 1)[1]
        if bone in G["BONE_NAMES"]:
            world = ob.matrix_world.copy()
            ob.parent = arm
            ob.parent_type = "BONE"
            ob.parent_bone = bone
            bpy.context.view_layer.update()
            ob.matrix_world = world

    actions = {name: G["key_clip"](arm, name, clip) for name, clip in built.items()}
    G["BAKE_STEP"] = 1
    baked = {name: G["bake_clip"](arm, actions[name], clip) for name, clip in built.items()}

    G["ANIMS"] = OUT
    G["write_anims"](baked, built)
    with open(OUT, encoding="utf-8") as f:
        text = f.read()
    text = text.replace("-- Gerado por tools/blender/golem.py: não edite à mão.", "-- EXPERIMENTOS. Gerado por tools/blender/golem_v2.py: não edite à mão.")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)

    if SNAP:
        os.makedirs(SNAP, exist_ok=True)
        for name, clip in built.items():
            if ONLY and name != ONLY:
                continue
            original = CLIPS[name][1]
            extra = G["key_clip"](arm, original, originals[original])
            for label, act, c in ((name, actions[name], clip), (original, extra, originals[original])):
                arm.animation_data.action = act
                if len(act.slots) > 0:
                    arm.animation_data.action_slot = act.slots[0]
                for f in range(0, c["keys"][-1][0] + 1, 2):
                    scene.frame_set(f)
                    G["kit"].snapshot(os.path.join(SNAP, f"{label}_{f:03d}.png"), (78, 24, 22), (0, 2, 16), 35, (240, 300))


main()
