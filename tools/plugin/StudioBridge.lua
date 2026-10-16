-- StudioBridge: plugin local que executa Luau enviado por tools/bridge.cjs (127.0.0.1:34871).
-- Instalação: copiar este arquivo para %LOCALAPPDATA%\Roblox\Plugins.
-- Só fala com a própria máquina. Apague o arquivo da pasta Plugins para desligar.
--
-- O plugin roda em toda janela do Studio. Um place com ReplicatedStorage.BridgePort (IntValue)
-- fala na porta dele (o laboratório de efeitos usa 34872), e o jogo e o laboratório abertos
-- juntos não pegam os comandos um do outro.

local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local URL = "http://127.0.0.1:34871"
local function refreshUrl()
	local marker = ReplicatedStorage:FindFirstChild("BridgePort")
	local port = if marker and marker:IsA("IntValue") and marker.Value > 0 then marker.Value else 34871
	URL = "http://127.0.0.1:" .. port
end

local context
if not RunService:IsRunning() then
	context = "edit"
elseif RunService:IsServer() then
	context = "server"
else
	context = "client"
end

local function encode(value)
	local kind = typeof(value)
	if kind == "table" then
		local ok, text = pcall(HttpService.JSONEncode, HttpService, value)
		return if ok then text else tostring(value)
	end
	return tostring(value)
end

local function runJob(job)
	local log = {}
	local connection = LogService.MessageOut:Connect(function(message, messageType)
		if #log < 200 then
			table.insert(log, messageType.Name .. ": " .. message)
		end
	end)

	local response = { id = job.id, ok = false, log = log }
	-- No Play o loadstring fica desligado (LoadStringEnabled = false). Arquivos de src/server/tests
	-- chegam também como nome de módulo e rodam por require, sem loadstring.
	local chunk, compileError
	local server = game:GetService("ServerScriptService"):FindFirstChild("Server")
	local tests = server and server:FindFirstChild("tests")
	local module = job.module and tests and tests:FindFirstChild(job.module)
	if module and module:IsA("ModuleScript") then
		-- argumentos da linha de comando: o módulo lê tests:GetAttribute("Args") (JSON)
		tests:SetAttribute("Args", HttpService:JSONEncode(job.args or {}))
		chunk = function()
			local copy = module:Clone() -- clone: require não reaproveita o resultado anterior
			copy.Parent = tests
			local ok, value = pcall(require, copy)
			copy:Destroy()
			if not ok then
				error(value, 0)
			end
			return value
		end
	else
		local available, loaded, loadError = pcall(loadstring, job.code, "=bridge")
		if available then
			chunk, compileError = loaded, loadError
		else
			compileError = "loadstring indisponível neste contexto; use um arquivo de src/server/tests (" .. tostring(loaded) .. ")"
		end
	end
	if not chunk then
		response.error = "compile: " .. tostring(compileError)
	else
		local results = table.pack(xpcall(chunk, debug.traceback))
		if results[1] then
			response.ok = true
			local parts = {}
			for i = 2, results.n do
				table.insert(parts, encode(results[i]))
			end
			response.result = table.concat(parts, ", ")
		else
			response.error = tostring(results[2])
		end
	end

	task.wait(0.1) -- deixa as últimas mensagens do log chegarem
	connection:Disconnect()
	local sent, sendError = pcall(function()
		return HttpService:RequestAsync({
			Url = URL .. "/result",
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode(response),
		})
	end)
	if not sent then
		error("envio do resultado falhou: " .. tostring(sendError))
	end
end

task.spawn(function()
	while true do
		refreshUrl() -- o Rojo pode sincronizar a marca depois que o plugin já começou
		local ok, reply = pcall(function()
			return HttpService:RequestAsync({ Url = URL .. "/poll?ctx=" .. context, Method = "GET" })
		end)
		if ok and reply.Success then
			local decoded, job = pcall(HttpService.JSONDecode, HttpService, reply.Body)
			if decoded and type(job) == "table" and job.id then
				task.spawn(function()
					local ran, failure = pcall(runJob, job)
					if not ran then
						-- falha da própria ponte: devolve o erro em vez de deixar o terminal esperando
						pcall(function()
							HttpService:RequestAsync({
								Url = URL .. "/result",
								Method = "POST",
								Headers = { ["Content-Type"] = "application/json" },
								Body = HttpService:JSONEncode({ id = job.id, ok = false, error = "bridge: " .. tostring(failure), log = {} }),
							})
						end)
					end
				end)
			end
			task.wait(0.3)
		else
			task.wait(2) -- ponte desligada ou sem permissão de HTTP: tenta de novo sem insistir
		end
	end
end)
