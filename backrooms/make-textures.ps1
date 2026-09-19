Add-Type -AssemblyName System.Drawing

$src = Join-Path $PSScriptRoot 'plackkiiiii.jpg'
$img = [System.Drawing.Bitmap]::FromFile($src)

function Get-FlatFielded {
  param(
    [System.Drawing.Bitmap]$Source,
    [int]$SX, [int]$SY, [int]$SW, [int]$SH,
    [double]$Target,
    [double]$StretchX = 1.0
  )
  $OW = [int][math]::Round($SW * $StretchX)
  $crop = New-Object System.Drawing.Bitmap($OW, $SH)
  $g = [System.Drawing.Graphics]::FromImage($crop)
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.DrawImage($Source, (New-Object System.Drawing.Rectangle(0,0,$OW,$SH)),
               (New-Object System.Drawing.Rectangle($SX,$SY,$SW,$SH)), 'Pixel')
  $g.Dispose()
  $SW = $OW

  # rozmycie (niskie częstotliwości = wypalone światło)
  $small = New-Object System.Drawing.Bitmap(8,8)
  $gs = [System.Drawing.Graphics]::FromImage($small)
  $gs.InterpolationMode = 'HighQualityBilinear'
  $gs.DrawImage($crop, (New-Object System.Drawing.Rectangle(0,0,8,8)),
                (New-Object System.Drawing.Rectangle(0,0,$SW,$SH)), 'Pixel')
  $gs.Dispose()

  $blur = New-Object System.Drawing.Bitmap($SW,$SH)
  $gb = [System.Drawing.Graphics]::FromImage($blur)
  $gb.InterpolationMode = 'HighQualityBilinear'
  $gb.DrawImage($small, (New-Object System.Drawing.Rectangle(0,0,$SW,$SH)),
                (New-Object System.Drawing.Rectangle(0,0,8,8)), 'Pixel')
  $gb.Dispose()

  $out = New-Object System.Drawing.Bitmap($SW,$SH)
  for($y=0; $y -lt $SH; $y++){
    for($x=0; $x -lt $SW; $x++){
      $c  = $crop.GetPixel($x,$y)
      $b  = $blur.GetPixel($x,$y)
      $Lb = 0.299*$b.R + 0.587*$b.G + 0.114*$b.B
      if($Lb -lt 10){ $Lb = 10 }
      $k = $Target / $Lb
      $r = [int][math]::Min(255, [math]::Round($c.R * $k))
      $gr= [int][math]::Min(255, [math]::Round($c.G * $k))
      $bl= [int][math]::Min(255, [math]::Round($c.B * $k))
      # miękka kompresja prześwietleń (żeby jasne plamy nie kafelkowały się)
      $L = 0.299*$r + 0.587*$gr + 0.114*$bl
      if($L -gt 185){
        $k2 = (185.0 + ($L-185.0)*0.30) / $L
        $r = [int][math]::Round($r*$k2); $gr = [int][math]::Round($gr*$k2); $bl = [int][math]::Round($bl*$k2)
      }
      $out.SetPixel($x,$y,[System.Drawing.Color]::FromArgb(255,$r,$gr,$bl))
    }
  }
  $crop.Dispose(); $small.Dispose(); $blur.Dispose()
  return $out
}

function To-Base64Png {
  param([System.Drawing.Bitmap]$Bmp)
  $ms = New-Object System.IO.MemoryStream
  $Bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  $b64 = [Convert]::ToBase64String($ms.ToArray())
  $ms.Dispose()
  return $b64
}

function Make-Seamless {
  param([System.Drawing.Bitmap]$Bmp, [double]$Feather = 0.30)
  $W = $Bmp.Width; $H = $Bmp.Height
  $FX = [int][math]::Max(2, [math]::Round($W*$Feather))
  $FY = [int][math]::Max(2, [math]::Round($H*$Feather))
  $src = New-Object System.Drawing.Bitmap($W,$H)
  $g = [System.Drawing.Graphics]::FromImage($src)
  $g.DrawImage($Bmp, 0, 0, $W, $H)
  $g.Dispose()
  $out = New-Object System.Drawing.Bitmap($W,$H)
  for($y=0; $y -lt $H; $y++){
    for($x=0; $x -lt $W; $x++){
      # lustrzane sklejenie w poziomie
      $mx = $W-1-$x
      $tx = 0.0
      if($x -lt $FX){ $tx = 0.5*(1.0 - $x/$FX) }
      elseif($x -gt ($W-1-$FX)){ $tx = 0.5*(1.0 - ($W-1-$x)/$FX) }
      $my = $H-1-$y
      $ty = 0.0
      if($y -lt $FY){ $ty = 0.5*(1.0 - $y/$FY) }
      elseif($y -gt ($H-1-$FY)){ $ty = 0.5*(1.0 - ($H-1-$y)/$FY) }
      $c00 = $src.GetPixel($x,$y); $c10 = $src.GetPixel($mx,$y)
      $c01 = $src.GetPixel($x,$my); $c11 = $src.GetPixel($mx,$my)
      $r = (1-$tx)*(1-$ty)*$c00.R + $tx*(1-$ty)*$c10.R + (1-$tx)*$ty*$c01.R + $tx*$ty*$c11.R
      $gr= (1-$tx)*(1-$ty)*$c00.G + $tx*(1-$ty)*$c10.G + (1-$tx)*$ty*$c01.G + $tx*$ty*$c11.G
      $bl= (1-$tx)*(1-$ty)*$c00.B + $tx*(1-$ty)*$c10.B + (1-$tx)*$ty*$c01.B + $tx*$ty*$c11.B
      $out.SetPixel($x,$y,[System.Drawing.Color]::FromArgb(255,[int][math]::Round($r),[int][math]::Round($gr),[int][math]::Round($bl)))
    }
  }
  $src.Dispose()
  return $out
}

# WALL: lewa ściana (pas o stałej głębokości), rozciągnięty poziomo do prostokąta
$wall = Get-FlatFielded -Source $img -SX 20 -SY 320 -SW 160 -SH 360 -Target 175 -StretchX 3.0
# FLOOR: fragment dywanu, bezszwowy
$floor = Get-FlatFielded -Source $img -SX 640 -SY 600 -SW 420 -SH 320 -Target 135 -StretchX 1.0
$floor = Make-Seamless -Bmp $floor -Feather 0.30
# CEILING: pas płyt sufitowych bez lamp, bezszwowy w poziomie
$ceil = Get-FlatFielded -Source $img -SX 900 -SY 8 -SW 600 -SH 90 -Target 150 -StretchX 1.0
$ceil = Make-Seamless -Bmp $ceil -Feather 0.30

function Get-Stats {
  param([System.Drawing.Bitmap]$Bmp)
  $mn = 999.0; $mx = 0.0
  for($y=0;$y -lt $Bmp.Height;$y+=2){
    for($x=0;$x -lt $Bmp.Width;$x+=2){
      $c=$Bmp.GetPixel($x,$y)
      $l = 0.299*$c.R + 0.587*$c.G + 0.114*$c.B
      if($l -lt $mn){$mn=$l}; if($l -gt $mx){$mx=$l}
    }
  }
  return "$([math]::Round($mn))..$([math]::Round($mx))"
}
"stats wall  (min..max lum): $(Get-Stats $wall)"
"stats floor (min..max lum): $(Get-Stats $floor)"
"stats ceil  (min..max lum): $(Get-Stats $ceil)"

$bWall  = To-Base64Png $wall
$bFloor = To-Base64Png $floor
$bCeil  = To-Base64Png $ceil

$js = "// tekstury wyciete z plackkiiiii.jpg (wyrownane swiatlo)`r`n" +
      "const TEX = {`r`n" +
      " wall: 'data:image/png;base64,$bWall',`r`n" +
      " floor: 'data:image/png;base64,$bFloor',`r`n" +
      " ceil: 'data:image/png;base64,$bCeil'`r`n" +
      "};`r`n"

[System.IO.File]::WriteAllText((Join-Path $PSScriptRoot 'textures.js'), $js, (New-Object System.Text.UTF8Encoding($false)))

"wall  : $($wall.Width)x$($wall.Height)  b64=$([math]::Round($bWall.Length/1024)) KB"
"floor : $($floor.Width)x$($floor.Height)  b64=$([math]::Round($bFloor.Length/1024)) KB"
"ceil  : $($ceil.Width)x$($ceil.Height)  b64=$([math]::Round($bCeil.Length/1024)) KB"
$wall.Dispose(); $floor.Dispose(); $ceil.Dispose(); $img.Dispose()
"OK -> textures.js"