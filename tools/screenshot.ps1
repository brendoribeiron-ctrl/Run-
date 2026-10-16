# Captura a janela do Roblox Studio em PNG, mesmo sem ela estar em primeiro plano.
#   powershell -File tools\screenshot.ps1 -Out shots\nome.png
#   -Window VfxLab   escolhe a janela pelo título (jogo e laboratório de efeitos abertos juntos);
#                    sem -Window, pega uma janela que não seja a do laboratório
param(
	[Parameter(Mandatory = $true)][string]$Out,
	[int]$Count = 1,
	[int]$IntervalMs = 400,
	[int]$DelayMs = 0,
	[string]$Window = ''
)

Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class StudioShot {
	[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
	[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
	[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
	[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
	[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@

[StudioShot]::SetProcessDPIAware() | Out-Null
$windows = Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }
if ($Window) {
	$studio = $windows | Where-Object { $_.MainWindowTitle -like "*$Window*" } | Select-Object -First 1
} else {
	$studio = $windows | Where-Object { $_.MainWindowTitle -notlike '*VfxLab*' } | Select-Object -First 1
}
if (-not $studio) { Write-Error 'Roblox Studio não está aberto.'; exit 1 }
$handle = $studio.MainWindowHandle
if ([StudioShot]::IsIconic($handle)) { Write-Error 'A janela do Studio está minimizada.'; exit 1 }

$rect = New-Object StudioShot+RECT
[StudioShot]::GetWindowRect($handle, [ref]$rect) | Out-Null
$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top

$full = [System.IO.Path]::GetFullPath($Out)
New-Item -ItemType Directory -Force ([System.IO.Path]::GetDirectoryName($full)) | Out-Null
if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }

# -Count > 1: rajada, uma captura a cada -IntervalMs, salva como nome_01.png, nome_02.png...
for ($i = 1; $i -le $Count; $i++) {
	$bitmap = New-Object System.Drawing.Bitmap $width, $height
	$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
	$hdc = $graphics.GetHdc()
	[StudioShot]::PrintWindow($handle, $hdc, 2) | Out-Null  # 2 = PW_RENDERFULLCONTENT
	$graphics.ReleaseHdc($hdc)
	$graphics.Dispose()
	$target = $full
	if ($Count -gt 1) { $target = $full -replace '\.png$', ('_{0:d2}.png' -f $i) }
	$bitmap.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
	$bitmap.Dispose()
	if ($i -lt $Count) { Start-Sleep -Milliseconds $IntervalMs }
}
"$full ($width x $height) x$Count"
