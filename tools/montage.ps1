# Junta uma rajada de capturas numa folha de contato (recorta só a área do jogo).
#   powershell -File tools\montage.ps1 -Pattern shots\run\r_*.png -Out shots\run\sheet.png -From 1 -To 16
param(
	[Parameter(Mandatory = $true)][string]$Pattern,
	[Parameter(Mandatory = $true)][string]$Out,
	[int]$From = 1,
	[int]$To = 999,
	[int]$Columns = 4,
	[int]$CellWidth = 480,
	# área do jogo dentro da janela do Studio, em frações (esquerda, topo, direita, base)
	[string]$CropBox = '0.005,0.16,0.747,0.747'
)
$Crop = $CropBox -split ',' | ForEach-Object { [double]::Parse($_, [cultureinfo]::InvariantCulture) }

Add-Type -AssemblyName System.Drawing
$files = Get-ChildItem $Pattern | Sort-Object Name | Select-Object -Skip ($From - 1) -First ($To - $From + 1)
if (-not $files) { Write-Error 'nenhuma captura encontrada'; exit 1 }

$first = [System.Drawing.Image]::FromFile($files[0].FullName)
$sx = [int]($first.Width * $Crop[0]); $sy = [int]($first.Height * $Crop[1])
$sw = [int]($first.Width * ($Crop[2] - $Crop[0])); $sh = [int]($first.Height * ($Crop[3] - $Crop[1]))
$first.Dispose()
$cellHeight = [int]($CellWidth * $sh / $sw)
$rows = [math]::Ceiling($files.Count / $Columns)

$sheet = New-Object System.Drawing.Bitmap ($Columns * $CellWidth), ($rows * $cellHeight)
$g = [System.Drawing.Graphics]::FromImage($sheet)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$font = New-Object System.Drawing.Font 'Arial', 14, ([System.Drawing.FontStyle]::Bold)
for ($i = 0; $i -lt $files.Count; $i++) {
	$image = [System.Drawing.Image]::FromFile($files[$i].FullName)
	$x = ($i % $Columns) * $CellWidth
	$y = [math]::Floor($i / $Columns) * $cellHeight
	$g.DrawImage($image, (New-Object System.Drawing.Rectangle $x, $y, $CellWidth, $cellHeight), (New-Object System.Drawing.Rectangle $sx, $sy, $sw, $sh), [System.Drawing.GraphicsUnit]::Pixel)
	$g.DrawString(($From + $i).ToString(), $font, [System.Drawing.Brushes]::Yellow, ($x + 4), ($y + 2))
	$image.Dispose()
}
$g.Dispose()
$full = [System.IO.Path]::GetFullPath($Out)
$sheet.Save($full, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()
"$full ($($files.Count) quadros)"
