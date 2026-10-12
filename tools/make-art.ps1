# Gera ícone (512x512) e capa (1920x1080) do jogo a partir de capturas do Studio:
# recorta a área do jogo, preenche o quadro e escreve o título com contorno.
#   powershell -File tools\make-art.ps1 -Source shots\x.png -Out art\capa.png -Width 1920 -Height 1080 -Title "WALL BREAKER|TITANS"
param(
	[Parameter(Mandatory = $true)][string]$Source,
	[Parameter(Mandatory = $true)][string]$Out,
	[int]$Width = 1920,
	[int]$Height = 1080,
	[string]$Title = '',
	[string]$Tag = '',
	# área do jogo dentro da captura, em frações (esquerda, topo, direita, base)
	[string]$CropBox = '0.006,0.162,0.744,0.745',
	# ponto de interesse dentro dessa área (0-1), mantido no quadro ao cortar
	[double]$FocusX = 0.5,
	[double]$FocusY = 0.5,
	[double]$Zoom = 1.0,
	[double]$TitleY = 0.04,
	[double]$TitleSize = 0.17
)

Add-Type -AssemblyName System.Drawing
$crop = $CropBox -split ',' | ForEach-Object { [double]::Parse($_, [cultureinfo]::InvariantCulture) }
$image = [System.Drawing.Image]::FromFile((Resolve-Path $Source))
$gx = $image.Width * $crop[0]; $gy = $image.Height * $crop[1]
$gw = $image.Width * ($crop[2] - $crop[0]); $gh = $image.Height * ($crop[3] - $crop[1])

# janela de origem com a proporção do destino, o maior possível dentro da área do jogo
$ratio = $Width / $Height
if ($gw / $gh -gt $ratio) { $sh = $gh / $Zoom; $sw = $sh * $ratio } else { $sw = $gw / $Zoom; $sh = $sw / $ratio }
$sx = $gx + [math]::Min([math]::Max($gw * $FocusX - $sw / 2, 0), $gw - $sw)
$sy = $gy + [math]::Min([math]::Max($gh * $FocusY - $sh / 2, 0), $gh - $sh)

$canvas = New-Object System.Drawing.Bitmap $Width, $Height
$g = [System.Drawing.Graphics]::FromImage($canvas)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
$g.DrawImage($image, (New-Object System.Drawing.RectangleF 0, 0, $Width, $Height), (New-Object System.Drawing.RectangleF $sx, $sy, $sw, $sh), [System.Drawing.GraphicsUnit]::Pixel)
$image.Dispose()

function Draw-Outlined([string]$text, [single]$size, [single]$top, [System.Drawing.Color]$fill, [single]$angle) {
	$family = New-Object System.Drawing.FontFamily 'Arial Black'
	$format = New-Object System.Drawing.StringFormat
	$format.Alignment = [System.Drawing.StringAlignment]::Center
	$path = New-Object System.Drawing.Drawing2D.GraphicsPath
	$path.AddString($text, $family, [int][System.Drawing.FontStyle]::Bold, $size, (New-Object System.Drawing.PointF ($Width / 2), $top), $format)
	# texto mais largo que o quadro: encolhe até caber, mantendo o centro
	$bounds = $path.GetBounds()
	$limit = $Width * 0.9
	if ($bounds.Width -gt $limit) {
		$fit = [single]($limit / $bounds.Width)
		$shrink = New-Object System.Drawing.Drawing2D.Matrix
		$shrink.Translate([single]($Width / 2), $top)
		$shrink.Scale($fit, $fit)
		$shrink.Translate([single](-$Width / 2), (-$top))
		$path.Transform($shrink)
		$size = $size * $fit
	}
	if ($angle -ne 0) {
		$matrix = New-Object System.Drawing.Drawing2D.Matrix
		$matrix.RotateAt($angle, (New-Object System.Drawing.PointF ($Width / 2), ($top + $size / 2)))
		$path.Transform($matrix)
	}
	$pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 16, 18, 34)), ($size * 0.2)
	$pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
	$g.DrawPath($pen, $path)
	$g.FillPath((New-Object System.Drawing.SolidBrush $fill), $path)
}

if ($Title) {
	# sombra escura atrás do título para ele ler em qualquer fundo
	$half = [int]($Height * 0.5)
	$area = New-Object System.Drawing.Rectangle 0, 0, $Width, $half
	# o pincel cobre um pouco mais que a área pintada: sem isso a borda do degradê vira uma linha
	$brushArea = New-Object System.Drawing.Rectangle 0, -2, $Width, ($half + 4)
	$shade = New-Object System.Drawing.Drawing2D.LinearGradientBrush $brushArea, ([System.Drawing.Color]::FromArgb(170, 8, 10, 24)), ([System.Drawing.Color]::FromArgb(0, 8, 10, 24)), ([single]90)
	$g.FillRectangle($shade, $area)
	$lines = $Title -split '\|'
	$size = [single]($Height * $TitleSize)
	$colors = @([System.Drawing.Color]::FromArgb(255, 255, 210, 30), [System.Drawing.Color]::FromArgb(255, 25, 227, 255))
	for ($i = 0; $i -lt $lines.Count; $i++) {
		Draw-Outlined $lines[$i] $size ([single]($Height * $TitleY + $i * $size * 1.02)) $colors[$i % 2] -3
	}
}
if ($Tag) {
	Draw-Outlined $Tag ([single]($Height * 0.075)) ([single]($Height * 0.86)) ([System.Drawing.Color]::White) 0
}

$g.Dispose()
$full = [System.IO.Path]::GetFullPath($Out)
New-Item -ItemType Directory -Force ([System.IO.Path]::GetDirectoryName($full)) | Out-Null
$canvas.Save($full, [System.Drawing.Imaging.ImageFormat]::Png)
$canvas.Dispose()
"$full ($Width x $Height)"
