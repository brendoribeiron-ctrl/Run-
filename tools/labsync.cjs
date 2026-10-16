// Envia os scripts do laboratório de efeitos (lab.project.json) para o place VfxLab aberto no
// Studio, pela ponte do laboratório (porta 34875), sem depender do plugin do Rojo. Grava o código
// de cada script, cria o que falta e apaga o que não é do laboratório (sobras de uma sincronização
// errada com o projeto do jogo). ReplicatedStorage.Shared vai inteiro (src/shared), só o que mudou.
//
//   node tools/labsync.cjs
//
// Rode com o laboratório em modo de edição (sem Play): o Play copia o place na hora de começar.

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const ROOT = path.resolve(__dirname, "..");
const read = (file) => fs.readFileSync(path.join(ROOT, file), "utf8");

// [caminho no place, classe, arquivo]
const ITEMS = [
	["ServerScriptService.Server", "Script", "lab/server/init.server.luau"],
	["ServerScriptService.Server.Admin", "ModuleScript", "src/server/Admin.luau"],
	["ServerScriptService.Server.DevArea", "ModuleScript", "src/server/DevArea.luau"],
	["ServerScriptService.Server.Models", "ModuleScript", "src/server/Models.luau"],
	["ServerScriptService.Server.GolemModels", "ModuleScript", "src/server/GolemModels.luau"],
	["ServerScriptService.Server.tests", "Folder", null],
	["StarterPlayer.StarterPlayerScripts.Client", "LocalScript", "lab/client/init.client.luau"],
	["StarterPlayer.StarterPlayerScripts.Client.BossFx", "ModuleScript", "src/client/BossFx.luau"],
	["StarterPlayer.StarterPlayerScripts.Client.Fx", "ModuleScript", "src/client/Fx.luau"],
	["StarterPlayer.StarterPlayerScripts.Client.GolemPose", "ModuleScript", "src/client/GolemPose.luau"],
	["StarterPlayer.StarterPlayerScripts.Client.Ui", "ModuleScript", "src/client/Ui.luau"],
];
for (const file of fs.readdirSync(path.join(ROOT, "src/shared"))) {
	if (file.endsWith(".luau")) {
		ITEMS.push([`ReplicatedStorage.Shared.${file.replace(/.luau$/, "")}`, "ModuleScript", `src/shared/${file}`]);
	}
}
for (const file of fs.readdirSync(path.join(ROOT, "lab/server/tests"))) {
	if (file.endsWith(".luau")) {
		ITEMS.push([`ServerScriptService.Server.tests.${file.replace(/\.luau$/, "")}`, "ModuleScript", `lab/server/tests/${file}`]);
	}
}

const items = ITEMS.map(([where, className, file]) => ({ where, className, source: file ? read(file) : null }));
const payload = JSON.stringify(items);
if (payload.includes("]=====]")) throw new Error("um script contém ]=====]");

// O Luau que roda no Studio (modo de edição): decodifica a lista e aplica.
const luau = `
local HttpService = game:GetService("HttpService")
local items = HttpService:JSONDecode([=====[${payload}]=====])
local wanted = {}
local changed = 0
for _, item in items do
	local names = string.split(item.where, ".")
	local parent: Instance = game:GetService(names[1])
	for i = 2, #names - 1 do
		parent = parent:FindFirstChild(names[i]) :: Instance
	end
	local name = names[#names]
	local current = parent:FindFirstChild(name)
	if current and current.ClassName ~= item.className then
		-- troca de classe: os filhos passam para a nova
		local fresh = Instance.new(item.className)
		fresh.Name = name
		for _, child in current:GetChildren() do
			child.Parent = fresh
		end
		current:Destroy()
		fresh.Parent = parent
		current = fresh
	elseif not current then
		current = Instance.new(item.className)
		current.Name = name
		current.Parent = parent
	end
	if item.source and (current :: any).Source ~= item.source then
		(current :: any).Source = item.source
		changed += 1
	end
	wanted[current] = true
end
-- apaga o que não é do laboratório dentro das pastas gerenciadas
local removed = 0
for _, root in { game.ServerScriptService.Server, game.StarterPlayer.StarterPlayerScripts.Client } do
	for _, child in root:GetDescendants() do
		if child.Parent and not wanted[child] then
			child:Destroy()
			removed += 1
		end
	end
end
return string.format("%d scripts, %d atualizados, %d sobras apagadas", #items, changed, removed)
`;

const bridge = path.join(ROOT, "tools", "bridge.cjs");
// vai por arquivo: o código passa do limite da linha de comando do Windows
const temp = path.join(require("os").tmpdir(), "labsync_payload.lua");
fs.writeFileSync(temp, luau);
const out = execFileSync("node", [bridge, "run", "edit", temp, "20000"], { encoding: "utf8", env: { ...process.env, BRIDGE_PORT: "34875" } });
process.stdout.write(out);
