# Texturas das auras (src/client/Aura.luau), desenhadas por código com o numpy do Blender.
# Tudo é branco com alfa: a cor entra no jogo (Color do emissor, do Trail, da imagem).
#
#   blender -b --factory-startup -P tools/blender/aura_textures.py
#
# Grava os PNG em assets/textures/ e um .blend com todas as texturas em planos, para olhar,
# em E:\Projetos roblox\Blender\Auras VFX\aura_textures.blend.
#
#   flame   4x4 quadros: labareda toon que nasce, ondula e se desfaz (flipbook de partícula)
#   circle  círculo mágico: anéis, runas, estrela de seis pontas
#   swirl   riscos de vento em espiral saindo do centro
#   ribbon  faixa de luz com as duas bordas acesas (Trail largo)
#   slash   corte: miolo preto, borda branca, cauda em dedos (Trail escuro)
#   shards  2x2 lascas pontudas
#   star    estrela de quatro pontas
#   glow    brilho redondo e macio
#   streak  risco de luz com o miolo quente (pilares e faíscas)
#   spikes  coroa de espinhos toon (estouro das magias do golem)
#   crack   rachaduras no chão (pisão e esmagamento do golem)
#   wave    onda no chão com borda dura (pulso do golem)

import math
import os

import bpy
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "textures")
BLEND = r"E:\Projetos roblox\Blender\Auras VFX\aura_textures.blend"
SS = 3  # cada pixel é a média de SS x SS amostras: borda dura sem serrilhado


def grid(w, h):
    """Centros das amostras: x de 0 a 1 (esquerda para a direita), y de 0 a 1 (baixo para cima)."""
    x = (np.arange(w * SS) + 0.5) / (w * SS)
    y = 1 - (np.arange(h * SS) + 0.5) / (h * SS)
    return np.meshgrid(x, y)


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def vnoise(x, y, seed):
    xi = np.floor(x).astype(np.int64)
    yi = np.floor(y).astype(np.int64)
    xf = x - xi
    yf = y - yi
    u = xf * xf * (3 - 2 * xf)
    v = yf * yf * (3 - 2 * yf)

    def h(i, j):
        n = (i * 374761393 + j * 668265263 + seed * 1442695041) & 0xFFFFFFFF
        n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
        return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0

    a = h(xi, yi) * (1 - u) + h(xi + 1, yi) * u
    b = h(xi, yi + 1) * (1 - u) + h(xi + 1, yi + 1) * u
    return a * (1 - v) + b * v


def fbm(x, y, seed, octaves=4):
    total = np.zeros_like(x)
    amp = 0.5
    for o in range(octaves):
        total += amp * vnoise(x * 2**o, y * 2**o, seed + o * 17)
        amp *= 0.5
    return total / (1 - 0.5**octaves)


def segment(px, py, ax, ay, bx, by):
    """Distância de cada ponto ao segmento a-b."""
    dx, dy = bx - ax, by - ay
    t = np.clip(((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy), 0, 1)
    return np.hypot(px - (ax + t * dx), py - (ay + t * dy))


def down(a, w, h):
    return a.reshape(h, SS, w, SS).mean(axis=(1, 3))


def save(name, tone, alpha):
    """tone e alpha no tamanho das amostras; reduz e grava assets/textures/<name>.png."""
    hs, ws = alpha.shape
    w, h = ws // SS, hs // SS
    a = down(alpha, w, h)
    # tom médio só de onde há tinta: a borda suavizada não escurece nem clareia
    t = np.where(a > 1e-4, down(tone * alpha, w, h) / np.maximum(a, 1e-4), 1.0)
    rgba = np.empty((h, w, 4), dtype=np.float32)
    rgba[..., 0] = rgba[..., 1] = rgba[..., 2] = np.clip(t, 0, 1)
    rgba[..., 3] = np.clip(a, 0, 1)
    image = bpy.data.images.get(name) or bpy.data.images.new(name, w, h, alpha=True)
    image.pixels.foreach_set(rgba[::-1].ravel())  # o Blender guarda as linhas de baixo para cima
    image.filepath_raw = os.path.join(OUT, name + ".png")
    image.file_format = "PNG"
    image.save()
    print("gravado", name, w, "x", h)
    return image


# ---------------------------------------------------------------------------------------------


def flame_frame(t, size):
    X, Y = grid(size, size)
    x = (X - 0.5) * 2
    y = Y
    grow = smooth(0.0, 0.3, t)
    erode = smooth(0.4, 1.0, t)
    n = fbm(x * 2.2, y * 3.4 - t * 3.2, 11)
    v = np.full_like(x, -1.0)
    # três línguas de alturas diferentes, fundidas: a labareda fica gorda embaixo e recortada em cima
    for offset, tall, fat, phase in ((0.0, 1.0, 0.4, 0.0), (-0.2, 0.8, 0.34, 2.1), (0.22, 0.66, 0.32, 4.0)):
        height = (0.3 + 0.56 * grow) * tall
        yy = (y - 0.08) / height
        lick = np.clip(yy, 0, 1.4)
        # as línguas de lado nascem juntas e abrem para fora na ponta
        sway = offset * (0.5 + 1.3 * lick) + 0.16 * np.sin(lick * 3.4 + t * 7.0 + phase) * lick
        sway = sway + (fbm(x * 1.2 + phase, y * 2.4 - t * 2.6, 5) - 0.5) * 0.5 * lick
        width = fat * np.power(np.clip(yy, 0, None), 0.45) * np.power(np.clip(1.08 - yy, 0, None), 0.8) * 1.5
        d = np.abs(x - sway) / np.maximum(width, 1e-4)
        one = 1 - d - (n - 0.4) * 1.4 * (0.15 + lick) - erode * (0.45 + 1.5 * n)
        v = np.maximum(v, np.where(width > 0, one, -1))
    # margem: nada encosta na borda do quadro, senão vaza para o quadro vizinho
    edge = np.minimum(np.minimum(X, 1 - X), np.minimum(Y, 1 - Y))
    v = np.where(edge > 0.035, v, -1)
    alpha = (v > 0).astype(np.float64)
    tone = np.where(v > 0.42, 1.0, 0.74)
    return tone, alpha


def flame():
    cell, n = 256, 4
    tone = np.ones((cell * n * SS, cell * n * SS))
    alpha = np.zeros_like(tone)
    for f in range(n * n):
        t, a = flame_frame(f / (n * n - 1) * 0.94, cell)
        r, c = divmod(f, n)
        s = cell * SS
        tone[r * s : (r + 1) * s, c * s : (c + 1) * s] = t
        alpha[r * s : (r + 1) * s, c * s : (c + 1) * s] = a
    return save("flame", tone, alpha)


def circle():
    size = 1024
    X, Y = grid(size, size)
    x = (X - 0.5) * 2
    y = (Y - 0.5) * 2
    r = np.hypot(x, y)
    th = np.arctan2(y, x)
    ink = np.zeros_like(r, dtype=bool)

    def ring(r0, w):
        return np.abs(r - r0) < w / 2

    for r0, w in ((0.94, 0.022), (0.895, 0.008), (0.725, 0.014), (0.37, 0.01), (0.17, 0.012), (0.125, 0.006)):
        ink |= ring(r0, w)

    # faixa de runas: cada casa sorteia traços entre os nós de uma grade 3x3
    cells = 18
    rng = np.random.default_rng(7)
    a = (th / (2 * math.pi) % 1) * cells
    ci = np.floor(a).astype(int)
    ga = (a - ci - 0.5) * 2.1  # -1..1 dentro da casa, com folga entre vizinhas
    gb = (r - 0.81) / 0.052  # -1..1 na faixa
    nodes = [(i, j) for i in (-0.7, 0, 0.7) for j in (-0.8, 0, 0.8)]
    for c in range(cells):
        inside = ci == c
        order = rng.permutation(len(nodes))
        for k in range(rng.integers(3, 5)):
            p, q = nodes[order[k]], nodes[order[k + 1]]
            ink |= inside & (segment(ga, gb, p[0], p[1], q[0], q[1]) < 0.13)
        if rng.random() < 0.5:
            ink |= inside & (np.abs(np.hypot(ga, gb) - 0.5) < 0.1)

    # marcas de régua por dentro do anel do meio
    ticks = 72
    ta = (th / (2 * math.pi) % 1) * ticks
    near = np.abs(ta - np.round(ta)) / ticks * 2 * math.pi * r
    long = (np.round(ta).astype(int) % 6) == 0
    ink |= (near < 0.004) & (r < 0.718) & (r > np.where(long, 0.65, 0.685))

    # estrela de seis pontas, com um círculo em cada ponta
    R = 0.64
    for turn in (0, math.pi / 3):
        pts = [(R * math.cos(turn + k * 2 * math.pi / 3 + math.pi / 2), R * math.sin(turn + k * 2 * math.pi / 3 + math.pi / 2)) for k in range(3)]
        for k in range(3):
            p, q = pts[k], pts[(k + 1) % 3]
            ink |= segment(x, y, p[0], p[1], q[0], q[1]) < 0.007
    for k in range(6):
        cx, cy = R * math.cos(k * math.pi / 3 + math.pi / 2), R * math.sin(k * math.pi / 3 + math.pi / 2)
        d = np.hypot(x - cx, y - cy)
        ink |= (np.abs(d - 0.062) < 0.006) | (d < 0.022)
    # estrelinha de oito raios no centro
    for k in range(8):
        ang = k * math.pi / 4
        ink |= segment(x, y, 0.03 * math.cos(ang), 0.03 * math.sin(ang), 0.115 * math.cos(ang), 0.115 * math.sin(ang)) < 0.004

    # véu fraco por dentro: o chão fica tingido mesmo entre os traços
    veil = 0.13 * smooth(0.95, 0.2, r) * (r < 0.94)
    alpha = np.maximum(ink.astype(np.float64), veil)
    return save("circle", np.ones_like(alpha), alpha)


def swirl():
    size = 1024
    X, Y = grid(size, size)
    x = (X - 0.5) * 2
    y = (Y - 0.5) * 2
    r = np.hypot(x, y)
    th = np.arctan2(y, x) - 1.5 * r  # a espiral: o ângulo atrasa conforme o raio cresce
    fill = np.zeros_like(r)
    line = np.zeros_like(r, dtype=bool)
    rng = np.random.default_rng(21)
    count = 30
    for i in range(count):
        t0 = (i + rng.uniform(-0.3, 0.3)) / count * 2 * math.pi
        r0 = rng.uniform(0.1, 0.5)
        length = min(rng.uniform(0.28, 0.55), 0.95 - r0)
        thin = i % 3 == 2
        wmax = rng.uniform(0.006, 0.01) if thin else rng.uniform(0.022, 0.05)
        q = (r - r0) / length
        qq = np.clip(q, 0, 1)
        half = wmax * np.power(qq, 0.6) * np.power(1 - qq, 0.3) * 1.6  # cometa: cabeça gorda para fora
        da = (th - t0 + math.pi) % (2 * math.pi) - math.pi
        s = np.abs(da * r)
        inside = (q > 0) & (q < 1) & (s < half)
        if thin:
            line |= inside
        else:
            border = 0.007
            line |= inside & ((s > half - border) | (q > 1 - border / length * 1.2))
            fill = np.maximum(fill, inside * 0.3)
    alpha = np.maximum(fill, line * 0.95) * smooth(0.97, 0.86, r)
    return save("swirl", np.ones_like(alpha), alpha)


def ribbon():
    w, h = 512, 128
    X, Y = grid(w, h)
    edges = (np.abs(Y - 0.1) < 0.032) | (np.abs(Y - 0.9) < 0.032)
    inner = (Y > 0.1) & (Y < 0.9)
    silk = fbm(X * 2.5, Y * 13, 3)
    body = 0.2 + 0.45 * smooth(0.5, 0.72, silk)
    thread = (np.abs(Y - 0.5 - 0.1 * np.sin(X * 9)) < 0.012) * 0.8
    alpha = np.maximum(edges * 0.96, inner * np.maximum(body, thread))
    return save("ribbon", np.ones_like(alpha), alpha)


def slash():
    w, h = 512, 128
    X, Y = grid(w, h)
    v = np.abs(Y - 0.5)
    half = 0.44 * np.power(np.clip(1 - X, 0, 1), 0.25)
    mask = v < half
    # a cauda se abre em dedos: quanto mais para trás, mais o ruído come
    fingers = fbm(X * 1.6, Y * 7, 9)
    mask &= fingers > (X - 0.35) * 1.15
    mask &= (X > 0.01) & (X < 0.985)
    # borda: o que some quando a máscara encolhe
    reach = int(0.13 * h * SS)
    core = mask.copy()
    for dy in range(-reach, reach + 1, 2):
        span = int(math.sqrt(reach * reach - dy * dy))
        for dx in (-span, 0, span):
            core &= np.roll(np.roll(mask, dy, axis=0), dx, axis=1)
    tone = np.where(core, 0.0, 1.0)
    return save("slash", tone, mask.astype(np.float64))


def shards():
    cell = 256
    shapes = [
        [(0.5, 0.95), (0.62, 0.5), (0.5, 0.05), (0.38, 0.5)],  # losango comprido
        [(0.42, 0.93), (0.7, 0.3), (0.5, 0.07), (0.3, 0.38)],  # pipa torta
        [(0.55, 0.94), (0.66, 0.12), (0.34, 0.2)],  # lasca triangular
        [(0.3, 0.8), (0.6, 0.92), (0.72, 0.42), (0.52, 0.08), (0.36, 0.3)],  # caco
    ]
    tone = np.ones((cell * 2 * SS, cell * 2 * SS))
    alpha = np.zeros_like(tone)
    X, Y = grid(cell, cell)
    for index, pts in enumerate(shapes):
        inside = np.ones_like(X, dtype=bool)
        cx = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        for k in range(len(pts)):
            ax, ay = pts[k]
            bx, by = pts[(k + 1) % len(pts)]
            side = (bx - ax) * (Y - ay) - (by - ay) * (X - ax)
            centre = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
            inside &= (side * centre) >= 0
        facet = np.where(X + (Y - 0.5) * 0.25 > cx, 0.7, 1.0)  # duas faces: uma na luz, outra na sombra
        r, c = divmod(index, 2)
        s = cell * SS
        tone[r * s : (r + 1) * s, c * s : (c + 1) * s] = facet
        alpha[r * s : (r + 1) * s, c * s : (c + 1) * s] = inside
    return save("shards", tone, alpha)


def star():
    size = 256
    X, Y = grid(size, size)
    x = np.abs(X - 0.5) * 2
    y = np.abs(Y - 0.5) * 2
    p = 0.5
    d = np.power(np.power(x, p) + np.power(y, p), 1 / p)
    hard = d < 0.92
    halo = 0.35 * np.power(np.clip(1 - np.hypot(x, y) / 0.6, 0, 1), 2)
    alpha = np.maximum(hard.astype(np.float64), halo)
    return save("star", np.ones_like(alpha), alpha)


def glow():
    size = 256
    X, Y = grid(size, size)
    r = np.hypot(X - 0.5, Y - 0.5) * 2
    alpha = np.power(np.clip(1 - r, 0, 1), 2.2)
    return save("glow", np.ones_like(alpha), alpha)


def streak():
    w, h = 256, 64
    X, Y = grid(w, h)
    v = np.abs(Y - 0.5) * 2
    alpha = np.maximum(np.power(np.clip(1 - v, 0, 1), 3) * 0.55, (v < 0.16) * 1.0)
    alpha *= smooth(0, 0.06, X) * smooth(1, 0.94, X)
    return save("streak", np.ones_like(alpha), alpha)


def comet():
    """Faixa de fogo para o rastro do voo: corre ao longo de X e emenda nas pontas (a textura
    desliza pelo Beam). Corpo cheio no meio, borda em línguas deitadas, fios soltos por fora."""
    w, h = 512, 256
    X, Y = grid(w, h)

    def tile(sx, sy, seed):
        # ruído que emenda em X: mistura a amostra com a mesma amostra uma volta atrás
        return fbm(X * sx, Y * sy, seed) * (1 - X) + fbm((X - 1) * sx, Y * sy, seed) * X

    v = np.abs(Y - 0.5) * 2
    tongues = tile(3.0, 5.0, 31)
    # línguas: dente de serra que sobe devagar e cai de uma vez, deitado para trás; cada lado
    # da faixa tem o seu passo, para não ficar espelhado
    side = np.where(Y > 0.5, 0.0, 0.43)
    saw = np.mod(X * 4 + side + v * 0.9 + 0.35 * (tongues - 0.5), 1.0)
    saw2 = np.mod(X * 7 + side * 2 + v * 0.6, 1.0)
    edge = 0.36 + 0.34 * np.power(saw, 1.6) + 0.14 * np.power(saw2, 2.0) + 0.3 * (tongues - 0.5)
    body = v < edge
    wisps = (tile(2.0, 16.0, 47) > 0.66) & (v < 0.94) & (v > 0.3)
    alpha = np.maximum(body * 1.0, wisps * 0.8)
    # por dentro, veios mais escuros correndo no sentido do voo: dois tons com a mesma cor
    veins = tile(2.5, 22.0, 59)
    tone = np.where(body & (veins > 0.6) & (v > 0.1), 0.7, 1.0)
    return save("comet", tone, alpha)


def spikes():
    """Coroa de espinhos toon: anel com pontas duras de tamanhos diferentes saindo para fora
    (o estouro branco das magias de referência). Fica numa peça achatada que cresce e some."""
    size = 512
    X, Y = grid(size, size)
    dx, dy = X - 0.5, Y - 0.5
    r = np.hypot(dx, dy) * 2
    a = (np.arctan2(dy, dx) / (2 * np.pi)) % 1.0
    teeth = 40
    cell = np.floor(a * teeth)
    f = a * teeth - cell
    rng = np.random.default_rng(7)
    lengths = rng.uniform(0.08, 0.34, teeth + 1)
    lengths[::5] += 0.12
    tooth = lengths[cell.astype(np.int64)] * (1 - np.abs(f - 0.5) * 2)
    band = (r > 0.52) & (r < 0.62 + tooth)
    inner = (r > 0.47) & (r < 0.5)
    alpha = np.maximum(band * 1.0, inner * 0.8)
    tone = np.where(r < 0.66, 1.0, 0.9)
    return save("spikes", tone, alpha)


def crack():
    """Rachaduras no chão saindo do centro, com galhos, grossas perto do impacto."""
    size = 512
    X, Y = grid(size, size)
    rng = np.random.default_rng(13)
    width = np.full(X.shape, 9.0)
    for i in range(9):
        angle = i * 2 * np.pi / 9 + rng.uniform(-0.25, 0.25)
        x, y = 0.5, 0.5
        reach = rng.uniform(0.36, 0.48)
        steps = 6
        for s in range(steps):
            angle += rng.uniform(-0.45, 0.45)
            step = reach / steps
            nx, ny = x + np.cos(angle) * step, y + np.sin(angle) * step
            thick = 0.016 * (1 - s / steps) + 0.004
            d = segment(X, Y, x, y, nx, ny) / thick
            width = np.minimum(width, d)
            if s in (1, 3) and rng.random() < 0.8:
                b = angle + rng.choice([-1, 1]) * rng.uniform(0.5, 0.9)
                bx, by = nx + np.cos(b) * step * 1.3, ny + np.sin(b) * step * 1.3
                width = np.minimum(width, segment(X, Y, nx, ny, bx, by) / (thick * 0.6))
            x, y = nx, ny
    r = np.hypot(X - 0.5, Y - 0.5) * 2
    core = r < 0.09
    alpha = np.maximum((width < 1.0) * 1.0, core * 1.0)
    alpha = np.maximum(alpha, np.clip(1.6 - width, 0, 1) * 0.35)
    return save("crack", np.ones_like(alpha), alpha)


def wave():
    """Onda no chão: borda clara e dura na frente, rastro que apaga para dentro."""
    size = 512
    X, Y = grid(size, size)
    r = np.hypot(X - 0.5, Y - 0.5) * 2
    edge = (r > 0.9) & (r < 0.97)
    trail = smooth(0.55, 0.9, r) * (r < 0.9) * 0.55
    alpha = np.maximum(edge * 1.0, trail)
    return save("wave", np.ones_like(alpha), alpha)


def preview(images):
    """Um plano por textura, lado a lado, com a imagem como luz própria sobre fundo escuro."""
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    world = bpy.context.scene.world or bpy.data.worlds.new("World")
    bpy.context.scene.world = world
    world.use_nodes = True
    background = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    background.inputs[0].default_value = (0.02, 0.02, 0.03, 1)
    at = 0.0
    for image in images:
        image.pack()
        w, h = image.size
        sx, sy = (2.0, 2.0 * h / w) if w >= h else (2.0 * w / h, 2.0)
        bpy.ops.mesh.primitive_plane_add(size=1, location=(at + sx / 2, 0, 0))
        plane = bpy.context.active_object
        plane.name = "Tex_" + image.name
        plane.scale = (sx, sy, 1)
        material = bpy.data.materials.new("Mat_" + image.name)
        material.use_nodes = True
        tree = material.node_tree
        tree.nodes.clear()
        tex = tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        emission = tree.nodes.new("ShaderNodeEmission")
        clear = tree.nodes.new("ShaderNodeBsdfTransparent")
        mix = tree.nodes.new("ShaderNodeMixShader")
        out = tree.nodes.new("ShaderNodeOutputMaterial")
        tree.links.new(tex.outputs["Color"], emission.inputs["Color"])
        tree.links.new(tex.outputs["Alpha"], mix.inputs[0])
        tree.links.new(clear.outputs[0], mix.inputs[1])
        tree.links.new(emission.outputs[0], mix.inputs[2])
        tree.links.new(mix.outputs[0], out.inputs["Surface"])
        plane.data.materials.append(material)
        at += sx + 0.3
    os.makedirs(os.path.dirname(BLEND), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    print("projeto salvo em", BLEND)


def main():
    os.makedirs(OUT, exist_ok=True)
    only = os.environ.get("ONLY")  # ONLY=spikes,crack grava só essas, sem o .blend de prévia
    if only:
        for name in only.split(","):
            globals()[name]()
        return
    images = [flame(), circle(), swirl(), ribbon(), slash(), shards(), star(), glow(), streak(), comet(), spikes(), crack(), wave()]
    preview(images)


main()
