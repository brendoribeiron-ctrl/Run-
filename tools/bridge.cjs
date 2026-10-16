// Ponte entre o terminal e o Roblox Studio. O plugin tools/plugin/StudioBridge.lua
// consulta este servidor e executa o Luau enfileirado no contexto pedido.
//
//   node tools/bridge.cjs serve
//   node tools/bridge.cjs run <edit|server|client> "<luau ou caminho de arquivo>" [timeoutMs] [args...]
//   (os args chegam ao módulo de teste como JSON no atributo Args da pasta tests)
//   node tools/bridge.cjs status
//
// Outro place (o laboratório de efeitos, lab.project.json) usa outra porta: BRIDGE_PORT=34872.
// O plugin lê a porta de ReplicatedStorage.BridgePort; sem ela, 34871.

const http = require("http");
const fs = require("fs");
const path = require("path");

const PORT = Number(process.env.BRIDGE_PORT) || 34871;
const HOST = "127.0.0.1";

function readBody(req) {
	return new Promise((resolve) => {
		let data = "";
		req.on("data", (chunk) => (data += chunk));
		req.on("end", () => resolve(data));
	});
}

function serve() {
	let nextId = 1;
	const queues = { edit: [], server: [], client: [] };
	const waiting = new Map(); // id -> { res, timer }
	const lastSeen = {};

	const server = http.createServer(async (req, res) => {
		const url = new URL(req.url, `http://${HOST}:${PORT}`);
		const json = (code, body) => {
			res.writeHead(code, { "Content-Type": "application/json" });
			res.end(JSON.stringify(body));
		};

		if (req.method === "GET" && url.pathname === "/poll") {
			const ctx = url.searchParams.get("ctx");
			if (!queues[ctx]) return json(400, { error: "ctx" });
			lastSeen[ctx] = Date.now();
			const job = queues[ctx].shift();
			if (job) console.log(`job ${job.id} entregue a ${ctx}`);
			return json(200, job ? { id: job.id, code: job.code, module: job.module, args: job.args } : {});
		}

		if (req.method === "POST" && url.pathname === "/result") {
			const body = JSON.parse((await readBody(req)) || "{}");
			console.log(`job ${body.id} respondeu ok=${body.ok}`);
			const entry = waiting.get(body.id);
			if (entry) {
				clearTimeout(entry.timer);
				waiting.delete(body.id);
				entry.json(200, body);
			}
			return json(200, { ok: true });
		}

		if (req.method === "POST" && url.pathname === "/run") {
			const body = JSON.parse((await readBody(req)) || "{}");
			if (!queues[body.ctx]) return json(400, { error: "ctx" });
			const id = nextId++;
			const timer = setTimeout(() => {
				waiting.delete(id);
				const index = queues[body.ctx].findIndex((job) => job.id === id);
				if (index >= 0) queues[body.ctx].splice(index, 1);
				json(200, { id, ok: false, error: "timeout: nenhum plugin respondeu neste contexto", log: [] });
			}, body.timeout || 20000);
			waiting.set(id, { json, timer });
			queues[body.ctx].push({ id, code: body.code, module: body.module, args: body.args });
			return;
		}

		if (req.method === "GET" && url.pathname === "/status") {
			const now = Date.now();
			const seen = {};
			for (const ctx of Object.keys(queues)) {
				seen[ctx] = lastSeen[ctx] ? Math.round((now - lastSeen[ctx]) / 100) / 10 : null;
			}
			return json(200, { secondsSinceLastPoll: seen });
		}

		json(404, { error: "not found" });
	});

	server.listen(PORT, HOST, () => console.log(`bridge em http://${HOST}:${PORT}`));
}

function request(method, path, body) {
	return new Promise((resolve, reject) => {
		const payload = body ? JSON.stringify(body) : undefined;
		const req = http.request(
			{ host: HOST, port: PORT, path, method, headers: payload ? { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(payload) } : {} },
			(res) => {
				let data = "";
				res.on("data", (chunk) => (data += chunk));
				res.on("end", () => resolve(JSON.parse(data)));
			}
		);
		req.on("error", reject);
		if (payload) req.write(payload);
		req.end();
	});
}

async function main() {
	const [command, ctx, source, timeout, ...args] = process.argv.slice(2);
	if (command === "serve") return serve();
	if (command === "status") return console.log(JSON.stringify(await request("GET", "/status"), null, 2));
	if (command === "run") {
		const isFile = fs.existsSync(source);
		const code = isFile ? fs.readFileSync(source, "utf8") : source;
		// arquivos de src/server/tests/ também vão como nome de módulo (ServerScriptService.Server.tests, sincronizado pelo Rojo)
		const module = isFile ? path.basename(source).replace(/\.luau?$/, "") : undefined;
		const result = await request("POST", "/run", { ctx, code, module, args, timeout: Number(timeout) || 20000 });
		for (const line of result.log || []) console.log("  | " + line);
		if (result.ok) {
			console.log("=> " + result.result);
		} else {
			console.log("ERRO: " + result.error);
			process.exitCode = 1;
		}
		return;
	}
	console.log("uso: node tools/bridge.cjs serve | status | run <edit|server|client> <luau|arquivo> [timeoutMs]");
}

main().catch((err) => {
	console.error(String(err));
	process.exitCode = 1;
});
