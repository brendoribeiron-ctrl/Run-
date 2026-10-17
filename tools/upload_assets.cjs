// Envia os .fbx (modelos) e .png (texturas) de uma pasta ao Roblox pelo Open Cloud (Assets API
// v1) e grava os ids num arquivo Luau. Lê ROBLOX_API_KEY, ROBLOX_CREATOR_ID e ROBLOX_CREATOR_TYPE do .env da raiz.
//
//   node tools/upload_assets.cjs --dry          lista o que seria enviado, sem falar com a Roblox
//   node tools/upload_assets.cjs                envia os novos e os alterados
//   node tools/upload_assets.cjs --force        envia todos de novo
//   node tools/upload_assets.cjs <pasta> --out <arquivo.luau>   outra pasta e outro arquivo de ids
//   node tools/upload_assets.cjs assets/textures --out src/shared/Textures.luau   as texturas
//   node tools/upload_assets.cjs assets/animations --out src/shared/Animations.luau   as animações
//
// Os .png sobem como asset do tipo Image: o id serve direto de Texture/Image no jogo. (Com
// --type Decal o id devolvido é o do Decal, que não serve de textura.)
//
// Arquivo já enviado e sem mudança é pulado; arquivo alterado vira versão nova do mesmo asset
// (o id não muda). O controle fica em <pasta>/uploaded.json.

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const API = process.env.ROBLOX_ASSETS_API || "https://apis.roblox.com/assets/v1"; // a variável só serve para testar contra um servidor falso
const POLL_MS = 2000;
const POLL_LIMIT = 60; // 2 minutos por arquivo
const START = "-- <ids>";
const END = "-- </ids>";

function readEnv() {
	const file = path.join(ROOT, ".env");
	const env = {};
	if (!fs.existsSync(file)) return env;
	for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
		const match = line.match(/^\s*([A-Z_]+)\s*=\s*(.*?)\s*$/);
		if (match) env[match[1]] = match[2].replace(/^["']|["']$/g, "");
	}
	// variável de ambiente já definida no terminal vale mais que o .env
	for (const name of ["ROBLOX_API_KEY", "ROBLOX_CREATOR_ID", "ROBLOX_CREATOR_TYPE"]) {
		if (process.env[name]) env[name] = process.env[name];
	}
	return env;
}

function parseArgs(argv) {
	const args = { folder: path.join(ROOT, "assets", "models"), out: path.join(ROOT, "src", "shared", "Assets.luau"), dry: false, force: false, type: "Image" };
	for (let i = 0; i < argv.length; i++) {
		if (argv[i] === "--dry") args.dry = true;
		else if (argv[i] === "--force") args.force = true;
		else if (argv[i] === "--out") args.out = path.resolve(argv[++i]);
		else if (argv[i] === "--type") args.type = argv[++i];
		else args.folder = path.resolve(argv[i]);
	}
	return args;
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function call(method, url, key, body) {
	const response = await fetch(url, { method, headers: { "x-api-key": key }, body });
	const text = await response.text();
	let json;
	try {
		json = JSON.parse(text);
	} catch {
		json = undefined;
	}
	if (!response.ok) {
		throw new Error(`${method} ${url} -> ${response.status}: ${json?.message || text.slice(0, 300)}`);
	}
	return json;
}

// O envio é assíncrono: a resposta é uma operação ("operations/<id>") que precisa ser
// consultada até done = true; só então response.assetId existe.
async function waitOperation(operation, key) {
	for (let attempt = 0; attempt < POLL_LIMIT; attempt++) {
		if (operation.done) {
			if (operation.error) throw new Error(`a Roblox recusou o arquivo: ${operation.error.message || JSON.stringify(operation.error)}`);
			const assetId = operation.response?.assetId;
			if (!assetId) throw new Error("operação terminou sem assetId: " + JSON.stringify(operation));
			return String(assetId);
		}
		const operationId = operation.operationId || String(operation.path || "").split("/").pop();
		if (!operationId) throw new Error("resposta sem operationId: " + JSON.stringify(operation));
		await sleep(POLL_MS);
		operation = await call("GET", `${API}/operations/${operationId}`, key);
	}
	throw new Error("a operação não terminou em 2 minutos; rode de novo mais tarde");
}

const isImage = (file) => file.toLowerCase().endsWith(".png");
// .rbxm/.rbxmx com um KeyframeSequence (tools/anim/export.cjs) sobem como asset do tipo Animation
const isAnimation = (file) => /.rbxmx?$/i.test(file);
const contentType = (file) => (isImage(file) ? "image/png" : isAnimation(file) ? "model/x-" + path.extname(file).slice(1).toLowerCase() : "model/fbx");

function form(request, file) {
	const body = new FormData();
	body.append("request", JSON.stringify(request));
	body.append("fileContent", new Blob([fs.readFileSync(file)], { type: contentType(file) }), path.basename(file));
	return body;
}

async function upload(file, name, previousId, env, imageType) {
	if (previousId) {
		// asset que já existe: versão nova, mesmo id
		const operation = await call("PATCH", `${API}/assets/${previousId}`, env.ROBLOX_API_KEY, form({ assetId: previousId }, file));
		return waitOperation(operation, env.ROBLOX_API_KEY);
	}
	const creator = env.ROBLOX_CREATOR_TYPE === "group" ? { groupId: env.ROBLOX_CREATOR_ID } : { userId: env.ROBLOX_CREATOR_ID };
	const request = { assetType: isImage(file) ? imageType : isAnimation(file) ? "Animation" : "Model", displayName: name, description: "Enviado por tools/upload_assets.cjs", creationContext: { creator } };
	const operation = await call("POST", `${API}/assets`, env.ROBLOX_API_KEY, form(request, file));
	return waitOperation(operation, env.ROBLOX_API_KEY);
}

// Reescreve só o trecho entre as marcas do arquivo Luau.
function writeLuau(out, ids) {
	const source = fs.readFileSync(out, "utf8");
	const start = source.indexOf(START);
	const end = source.indexOf(END);
	if (start < 0 || end < start) throw new Error(`${out} precisa ter as marcas "${START}" e "${END}"`);
	const indent = source.slice(source.lastIndexOf("\n", start) + 1, start);
	const lines = Object.keys(ids)
		.sort()
		.map((name) => `${indent}["${name}"] = "rbxassetid://${ids[name]}",\n`);
	fs.writeFileSync(out, source.slice(0, start) + START + "\n" + lines.join("") + indent + source.slice(end));
}

async function main() {
	const args = parseArgs(process.argv.slice(2));
	const env = readEnv();
	if (!fs.existsSync(args.folder)) throw new Error("pasta não existe: " + args.folder);

	const manifestFile = path.join(args.folder, "uploaded.json");
	const manifest = fs.existsSync(manifestFile) ? JSON.parse(fs.readFileSync(manifestFile, "utf8")) : {};
	const files = fs.readdirSync(args.folder).filter((file) => /.(fbx|png|rbxmx?)$/i.test(file)).sort();
	if (files.length === 0) return console.log("nenhum .fbx, .png ou .rbxm(x) em " + args.folder);

	const jobs = files.map((file) => {
		const name = path.basename(file, path.extname(file)).replace(/[^A-Za-z0-9_]/g, "_");
		const hash = crypto.createHash("sha1").update(fs.readFileSync(path.join(args.folder, file))).digest("hex");
		const known = manifest[name];
		const action = !known ? "novo" : args.force || known.hash !== hash ? "atualizar" : "pular";
		return { file: path.join(args.folder, file), name, hash, known, action };
	});

	if (args.dry) {
		for (const job of jobs) console.log(`${job.action.padEnd(10)} ${job.name}${job.known ? "  (id " + job.known.assetId + ")" : ""}`);
		return console.log(`\nsimulação: nada foi enviado. Ids iriam para ${args.out}`);
	}
	if (!env.ROBLOX_API_KEY || !env.ROBLOX_CREATOR_ID) throw new Error("preencha ROBLOX_API_KEY e ROBLOX_CREATOR_ID no .env da raiz do projeto");

	let failed = 0;
	for (const job of jobs) {
		if (job.action === "pular") {
			console.log(`pulado     ${job.name}  (id ${job.known.assetId}, sem mudança)`);
			continue;
		}
		try {
			const assetId = await upload(job.file, job.name, job.known?.assetId, env, args.type);
			manifest[job.name] = { assetId, hash: job.hash };
			// grava a cada arquivo: se o próximo falhar, o que já subiu não é enviado de novo
			fs.writeFileSync(manifestFile, JSON.stringify(manifest, null, "\t") + "\n");
			console.log(`enviado    ${job.name}  -> rbxassetid://${assetId}`);
		} catch (error) {
			failed++;
			console.error(`FALHOU     ${job.name}: ${error.message}`);
		}
	}

	const ids = {};
	for (const name of Object.keys(manifest)) ids[name] = manifest[name].assetId;
	writeLuau(args.out, ids);
	console.log(`\n${Object.keys(ids).length} ids gravados em ${args.out}`);
	if (failed > 0) process.exitCode = 1;
}

main().catch((error) => {
	console.error("ERRO: " + error.message);
	process.exitCode = 1;
});
