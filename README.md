# Wall Breaker Titans (Teste_foda)

Simulador de Roblox: carregar força, ser lançado por um corredor, quebrar paredes, rolar um personagem e colocá-lo no terreno para render dinheiro. Tudo em código, sincronizado com o Studio pelo Rojo 7.7.1.

## Estrutura

| Pasta | Vai para | Conteúdo |
|---|---|---|
| `src/shared` | `ReplicatedStorage.Shared` | `Config` (todos os números) e `Format` |
| `src/server` | `ServerScriptService.Server` | regras do jogo, mundo gerado por código, dados |
| `src/server/tests` | `ServerScriptService.Server.tests` | testes que rodam no servidor do Play |
| `src/client` | `StarterPlayerScripts.Client` | HUD, entrada e efeitos |
| `tools` | fora do jogo | ponte com o Studio, captura de tela, envio de teclas |

## Rodar

```bash
rojo serve                      # depois Connect no plugin Rojo do Studio
rojo build -o Teste_foda.rbxlx  # gera o place do zero
```

## Testar pelo terminal

O plugin `tools/plugin/StudioBridge.lua` fica em `%LOCALAPPDATA%\Roblox\Plugins` e só conversa com `127.0.0.1:34871`.

```bash
node tools/bridge.cjs serve                                        # deixar rodando
node tools/bridge.cjs run server src/server/tests/slice1.luau 30000  # com o Play ligado
node tools/bridge.cjs run server src/server/tests/slice2.luau 60000  # corrida, sorteio, pedestais
node tools/bridge.cjs run server src/server/tests/goto_zone.luau     # leva o jogador à zona de carga
node tools/bridge.cjs run server src/server/tests/setup_plot.luau    # enche pedestais e hotbar
powershell -File tools\screenshot.ps1 -Out shots\tela.png            # -Count 30 -IntervalMs 330 = rajada
powershell -File tools\montage.ps1 -Pattern shots\run\r_*.png -Out shots\run\sheet.png
powershell -File tools\studio-input.ps1 -Steps "key:F5;wait:12000"   # F5 = Play, SHIFT+F5 = parar
```

No Play o `loadstring` fica desligado, por isso o contexto `server` só roda arquivos de `src/server/tests` (chegam como módulos). Código solto funciona no contexto `edit`, depois de reiniciar o Studio com o plugin instalado.

## Fatias

1. Terreno, saco de pancada, Poder e HUD: **feito**
2. Plataforma de carga, lançamento e barra de distância: **feito**
3. Paredes com Poder mínimo e quebra em blocos: **feito**
4. Roleta de cartas, card do resultado e inventário (hotbar): **feito**
5. Pedestais e dinheiro por segundo: **feito** (falta o pad de upgrade por personagem)
6. Upgrade do saco: **feito**; skills, rebirth e índice: botões no HUD, sem janela ainda
7. Recompensas por tempo, diário, VIP e boosts
8. Polimento
