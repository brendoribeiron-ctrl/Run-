# Envia teclas e cliques para a janela do Roblox Studio (traz a janela para frente antes).
#   powershell -File tools\studio-input.ps1 -Steps 'key:F5;wait:8000;click:0.4,0.4;hold:0.4,0.4,3000;key:SHIFT+F5'
# click/hold usam frações da janela do Studio (0-1).
param(
	[Parameter(Mandatory = $true)][string]$Steps  # passos separados por ';'
)
$stepList = $Steps -split ';'

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class StudioInput {
	[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
	[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
	[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
	[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
	[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
	[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
	[DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint mapType);
	[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
	[DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
	[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@

[StudioInput]::SetProcessDPIAware() | Out-Null
$studio = Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $studio) { Write-Error 'Roblox Studio não está aberto.'; exit 1 }
$handle = $studio.MainWindowHandle

$keys = @{ F5 = 0x74; F8 = 0x77; SHIFT = 0x10; CTRL = 0x11; ALT = 0x12; W = 0x57; A = 0x41; S = 0x53; D = 0x44; E = 0x45; Q = 0x51; K = 0x4B; P = 0x50; V = 0x56; ENTER = 0x0D; TAB = 0x09; SPACE = 0x20; ESC = 0x1B }

function Send-Key([int]$vk, [bool]$up) {
	$scan = [byte][StudioInput]::MapVirtualKey([uint32]$vk, 0)
	$flags = 0
	if ($up) { $flags = 2 }
	[StudioInput]::keybd_event([byte]$vk, $scan, [uint32]$flags, [UIntPtr]::Zero)
}

function Focus-Studio {
	if ([StudioInput]::IsIconic($handle)) { [StudioInput]::ShowWindow($handle, 9) | Out-Null }
	# um toque em ALT libera o SetForegroundWindow para processos em segundo plano
	Send-Key 0x12 $false; Send-Key 0x12 $true
	[StudioInput]::SetForegroundWindow($handle) | Out-Null
	Start-Sleep -Milliseconds 300
}

function Move-To([double]$fx, [double]$fy) {
	$rect = New-Object StudioInput+RECT
	[StudioInput]::GetWindowRect($handle, [ref]$rect) | Out-Null
	$x = [int]($rect.Left + ($rect.Right - $rect.Left) * $fx)
	$y = [int]($rect.Top + ($rect.Bottom - $rect.Top) * $fy)
	[StudioInput]::SetCursorPos($x, $y) | Out-Null
	Start-Sleep -Milliseconds 80
}

Focus-Studio
foreach ($step in $stepList) {
	$kind, $arg = $step -split ':', 2
	switch ($kind) {
		'wait' { Start-Sleep -Milliseconds ([int]$arg) }
		'key' {
			$parts = $arg -split '\+'
			foreach ($p in $parts) { Send-Key $keys[$p] $false }
			Start-Sleep -Milliseconds 60
			[array]::Reverse($parts)
			foreach ($p in $parts) { Send-Key $keys[$p] $true }
		}
		'keyhold' {
			$name, $ms = $arg -split ','
			Send-Key $keys[$name] $false
			Start-Sleep -Milliseconds ([int]$ms)
			Send-Key $keys[$name] $true
		}
		'click' {
			$fx, $fy = $arg -split ','
			Move-To ([double]$fx) ([double]$fy)
			[StudioInput]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
			Start-Sleep -Milliseconds 60
			[StudioInput]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
		}
		'hold' {
			$fx, $fy, $ms = $arg -split ','
			Move-To ([double]$fx) ([double]$fy)
			[StudioInput]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
			Start-Sleep -Milliseconds ([int]$ms)
			[StudioInput]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
		}
		'drag' {
			# aperta em (x1,y1), arrasta até (x2,y2) e segura: direcional de toque no emulador
			$x1, $y1, $x2, $y2, $ms = $arg -split ','
			Move-To ([double]$x1) ([double]$y1)
			[StudioInput]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
			for ($i = 1; $i -le 6; $i++) {
				Move-To ([double]$x1 + ([double]$x2 - [double]$x1) * $i / 6) ([double]$y1 + ([double]$y2 - [double]$y1) * $i / 6)
				[StudioInput]::mouse_event(1, 0, 0, 0, [UIntPtr]::Zero)
			}
			Start-Sleep -Milliseconds ([int]$ms)
			[StudioInput]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
		}
		default { Write-Error "passo desconhecido: $step" }
	}
	Start-Sleep -Milliseconds 120
}
'ok'
