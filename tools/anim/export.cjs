// Exporta um KeyframeSequence do Studio (modo de edição, pela ponte) para .rbxm, para enviar
// como asset do tipo Animation:
//
//   node tools/anim/export.cjs <caminho no place> <saida.rbxm>
//   node tools/anim/export.cjs Workspace.AnimRigs.RestRig.AnimSaves.RestIdle assets/animations/rest_idle.rbxm
//   ROBLOX_CREATOR_ID=<id> node tools/upload_assets.cjs assets/animations --out src/shared/Animations.luau
//
// O Open Cloud só aceita animação em .rbxm binário: o XML (.rbxmx) montado aqui passa pelo
// rojo build, que converte.
//
// O Eclipse Animator (ou qualquer animador) salva no AnimSaves do boneco; este script lê de lá.

const fs = require("fs");
const path = require("path");
const os = require("os");
const { execFileSync } = require("child_process");

const [where, output] = process.argv.slice(2);
if (!where || !output) {
	console.log("uso: node tools/anim/export.cjs <caminho no place> <saida.rbxm>");
	process.exit(1);
}
const ROOT = path.resolve(__dirname, "..", "..");

// Luau: percorre o KeyframeSequence e devolve JSON (CFrame em 12 números)
const luau = `
local HttpService = game:GetService("HttpService")
local node: Instance = game
for _, name in string.split(${JSON.stringify(where)}, ".") do
	node = assert(node:FindFirstChild(name) or (node == game and game:GetService(name)), "não achei " .. name)
end
assert(node:IsA("KeyframeSequence"), "não é KeyframeSequence")
local function pose(p: Pose)
	local children = {}
	for _, c in p:GetChildren() do
		if c:IsA("Pose") then
			table.insert(children, pose(c))
		end
	end
	return { name = p.Name, cf = { p.CFrame:GetComponents() }, weight = p.Weight, style = p.EasingStyle.Value, direction = p.EasingDirection.Value, children = children }
end
local keyframes = {}
for _, k in node:GetKeyframes() do
	local poses = {}
	for _, c in k:GetChildren() do
		if c:IsA("Pose") then
			table.insert(poses, pose(c))
		end
	end
	table.insert(keyframes, { name = k.Name, time = k.Time, poses = poses })
end
return HttpService:JSONEncode({ name = node.Name, loop = node.Loop, priority = node.Priority.Value, keyframes = keyframes })
`;
const temp = path.join(os.tmpdir(), "anim_export.lua");
fs.writeFileSync(temp, luau);
const out = execFileSync("node", [path.join(ROOT, "tools", "bridge.cjs"), "run", "edit", temp, "30000"], { encoding: "utf8" });
const line = out.split(/\r?\n/).find((l) => l.startsWith("=> "));
if (!line) throw new Error("o Studio não respondeu: " + out);
const data = JSON.parse(line.slice(3));

let ref = 0;
const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const cframe = (c) => {
	const n = ["X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"];
	return `<CoordinateFrame name="CFrame">${n.map((k, i) => `<${k}>${c[i]}</${k}>`).join("")}</CoordinateFrame>`;
};
const poseXml = (p) =>
	`<Item class="Pose" referent="RBX${ref++}"><Properties><string name="Name">${esc(p.name)}</string>${cframe(p.cf)}` +
	`<float name="Weight">${p.weight}</float><token name="EasingStyle">${p.style}</token><token name="EasingDirection">${p.direction}</token></Properties>` +
	p.children.map(poseXml).join("") +
	`</Item>`;
const keyframeXml = (k) =>
	`<Item class="Keyframe" referent="RBX${ref++}"><Properties><string name="Name">${esc(k.name)}</string><float name="Time">${k.time}</float></Properties>` +
	k.poses.map(poseXml).join("") +
	`</Item>`;
const xml =
	`<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" version="4">` +
	`<Item class="KeyframeSequence" referent="RBX${ref++}"><Properties><string name="Name">${esc(data.name)}</string>` +
	`<bool name="Loop">${data.loop}</bool><token name="Priority">${data.priority}</token></Properties>` +
	data.keyframes.map(keyframeXml).join("") +
	`</Item></roblox>`;
fs.mkdirSync(path.dirname(path.resolve(output)), { recursive: true });
const work = fs.mkdtempSync(path.join(os.tmpdir(), "anim-"));
fs.writeFileSync(path.join(work, "anim.rbxmx"), xml);
fs.writeFileSync(path.join(work, "default.project.json"), JSON.stringify({ name: data.name, tree: { $path: "anim.rbxmx" } }));
const rojo = path.join(os.homedir(), ".aftman", "bin", "rojo.exe");
execFileSync(rojo, ["build", path.join(work, "default.project.json"), "-o", path.resolve(output)], { encoding: "utf8" });
fs.rmSync(work, { recursive: true, force: true });
console.log(`${data.name}: ${data.keyframes.length} keyframes -> ${output} (${fs.statSync(output).size} bytes)`);
