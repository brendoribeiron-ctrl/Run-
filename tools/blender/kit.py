# Ferramentas comuns dos modelos feitos por código (wizard.py, volcano.py).
#
# Cada modelo é um Kit: as peças são agrupadas por tipo ("Rock", "Lava"...) e cada tipo vira um
# objeto "<Tipo>_<modelo>", que o Roblox pinta pelo nome. Tudo é volume fechado: malha do Roblox
# só tem um lado, então folha solta sumiria vista de trás.
#
# Eixos no Blender: X = direita, Y = frente do modelo, Z = cima. Três cubinhos marcam isso no
# arquivo exportado (Pivot na origem, MarkX em +X, MarkY em +Y, a MARK de distância): o jogo lê
# os três, acerta posição, direção e escala, e apaga.

import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

MARK = 20.0  # distância dos marcadores à origem, em studs


def clean_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)


class Kit:
    def __init__(self, name):
        self.name = name
        self.K = {}
        self.objects = []

    def bm(self, kind):
        if kind not in self.K:
            self.K[kind] = bmesh.new()
        return self.K[kind]

    def box(self, kind, size, loc, rot=None):
        m = Matrix.Translation(Vector(loc))
        if rot is not None:
            m = m @ rot
        m = m @ Matrix.Diagonal((size[0], size[1], size[2], 1))
        bmesh.ops.create_cube(self.bm(kind), size=1, matrix=m)

    def _skin(self, bm, loops, segs, cap_bottom, cap_top):
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

    def loft(self, kind, rings, segs, phase=0.0, matrix=None, wobble=None):
        """rings: (cx, cy, z, r); r == 0 vira ponta. wobble(anel, i) multiplica o raio do vértice."""
        bm = self.bm(kind)
        M = matrix or Matrix.Identity(4)
        loops = []
        for n, (cx, cy, z, r) in enumerate(rings):
            if r <= 1e-6:
                loops.append([bm.verts.new(M @ Vector((cx, cy, z)))])
                continue
            loop = []
            for i in range(segs):
                a = phase + 2 * math.pi * i / segs
                k = r * (wobble(n, i) if wobble else 1)
                loop.append(bm.verts.new(M @ Vector((cx + k * math.cos(a), cy + k * math.sin(a), z))))
            loops.append(loop)
        self._skin(bm, loops, segs, True, True)

    def cyl(self, kind, r, z0, z1, x=0, y=0, segs=12, r2=None, phase=0.0):
        self.loft(kind, [(x, y, z0, r), (x, y, z1, r if r2 is None else r2)], segs, phase)

    def tube(self, kind, pts, radii, segs=8):
        """Tubo que segue uma linha de pontos, com um raio por ponto (0 = ponta)."""
        bm = self.bm(kind)
        pts = [Vector(p) for p in pts]
        loops = []
        side = None
        for i, (p, r) in enumerate(zip(pts, radii)):
            t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            if side is None:
                ref = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
                side = t.cross(ref).normalized()
            else:
                side = (side - t * side.dot(t)).normalized()
            up = t.cross(side)
            if r <= 1e-6:
                loops.append([bm.verts.new(p)])
            else:
                loops.append([bm.verts.new(p + (side * math.cos(2 * math.pi * k / segs) + up * math.sin(2 * math.pi * k / segs)) * r) for k in range(segs)])
        self._skin(bm, loops, segs, True, True)

    def prism(self, kind, pts, depth, matrix):
        """pts 2D (u, v) no plano local XZ; extrusão em +Y local por depth."""
        bm = self.bm(kind)
        front = [bm.verts.new(matrix @ Vector((u, 0, v))) for u, v in pts]
        back = [bm.verts.new(matrix @ Vector((u, depth, v))) for u, v in pts]
        n = len(pts)
        bm.faces.new(front)
        bm.faces.new(list(reversed(back)))
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((front[j], front[i], back[i], back[j]))

    def slab(self, kind, pts, z0, z1):
        """Polígono deitado (pts em X, Y) com espessura de z0 a z1."""
        bm = self.bm(kind)
        low = [bm.verts.new(Vector((x, y, z0))) for x, y in pts]
        high = [bm.verts.new(Vector((x, y, z1))) for x, y in pts]
        n = len(pts)
        bm.faces.new(list(reversed(low)))
        bm.faces.new(high)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((low[i], low[j], high[j], high[i]))

    def gem(self, kind, x, y, z, r, h, segs=6, matrix=None):
        self.loft(kind, [(x, y, z - h / 2, 0), (x, y, z - h * 0.12, r), (x, y, z + h * 0.12, r), (x, y, z + h / 2, 0)], segs, matrix=matrix)

    def ball(self, kind, x, y, z, r, segs=10, squash=1.0):
        rings = []
        steps = 6
        for i in range(steps + 1):
            a = -math.pi / 2 + math.pi * i / steps
            rings.append((x, y, z + math.sin(a) * r * squash, max(math.cos(a) * r, 0) if 0 < i < steps else 0))
        self.loft(kind, rings, segs)

    def markers(self):
        self.box("Pivot", (0.2, 0.2, 0.2), (0, 0, 0))
        self.box("MarkX", (0.2, 0.2, 0.2), (MARK, 0, 0))
        self.box("MarkY", (0.2, 0.2, 0.2), (0, MARK, 0))

    def build(self, colors, glow=()):
        """Fecha as malhas e cria os objetos numa coleção com o nome do modelo."""
        self.markers()
        collection = bpy.data.collections.new(self.name)
        bpy.context.scene.collection.children.link(collection)
        report = []
        for kind, bm in self.K.items():
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            bmesh.ops.triangulate(bm, faces=bm.faces)
            me = bpy.data.meshes.new(kind + "_" + self.name)
            bm.to_mesh(me)
            bm.free()
            ob = bpy.data.objects.new(kind + "_" + self.name, me)
            collection.objects.link(ob)
            color = colors.get(kind, (1, 0, 1, 1))
            mat = bpy.data.materials.get("M_" + kind) or bpy.data.materials.new("M_" + kind)
            mat.diffuse_color = color
            mat.use_nodes = True
            bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
            bsdf.inputs["Base Color"].default_value = color
            if kind in glow:
                bsdf.inputs["Emission Color"].default_value = color
                bsdf.inputs["Emission Strength"].default_value = 3
            me.materials.append(mat)
            self.objects.append(ob)
            report.append((kind, len(me.polygons)))
        print(self.name, "triângulos:", sum(n for _, n in report), report)
        return self.objects

    def export(self, folder):
        path = os.path.join(folder, self.name + ".fbx")
        bpy.ops.object.select_all(action="DESELECT")
        for ob in self.objects:
            ob.select_set(True)
        bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"MESH"}, apply_scale_options="FBX_SCALE_ALL",
            axis_forward="-Z", axis_up="Y", bake_space_transform=True, mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False)
        print("exportado", path, os.path.getsize(path))

    def hide(self, hidden=True):
        for ob in self.objects:
            ob.hide_render = hidden
            ob.hide_viewport = hidden


def snapshot(path, eye, target, lens=35, size=(1100, 800)):
    """Imagem rápida da cena (motor Workbench, cor do material) para conferir o modelo."""
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("Snap")
    cam_data.lens = lens
    cam_data.clip_end = 5000
    cam = bpy.data.objects.new("Snap", cam_data)
    scene.collection.objects.link(cam)
    cam.location = Vector(eye)
    cam.rotation_euler = (Vector(target) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = False
    scene.display.shading.show_cavity = True
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.filepath = path
    scene.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
