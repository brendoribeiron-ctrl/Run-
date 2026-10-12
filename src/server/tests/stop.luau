-- Encerra a sessão de Play aberta pela ponte (StudioTestService:ExecutePlayModeAsync no modo de edição).
--   node tools/bridge.cjs run server src/server/tests/stop.luau

task.delay(0.5, function()
	game:GetService("StudioTestService"):EndTest("stop")
end)
return "parando"
