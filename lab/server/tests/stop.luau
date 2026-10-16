-- Encerra a sessão de Play do laboratório.
--   BRIDGE_PORT=34875 node tools/bridge.cjs run server lab/server/tests/stop.luau

task.delay(0.5, function()
	game:GetService("StudioTestService"):EndTest("stop")
end)
return "parando"
