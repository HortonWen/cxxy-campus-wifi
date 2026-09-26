param(
    [string]$Out = 'C:\Users\Administrator\Documents\Codex\cxxy-campus-wifi\exe-app\icon.ico',
    [string]$Preview = 'C:\Users\Administrator\Documents\Codex\cxxy-campus-wifi\exe-app\icon-preview.png'
)

Add-Type -AssemblyName System.Drawing

function New-AppBitmap {
    param([int]$Size)
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.Clear([System.Drawing.Color]::Transparent)

    $corner = [single]($Size * 0.20)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $corner, $corner, 180, 90)
    $path.AddArc($Size - $corner, 0, $corner, $corner, 270, 90)
    $path.AddArc($Size - $corner, $Size - $corner, $corner, $corner, 0, 90)
    $path.AddArc(0, $Size - $corner, $corner, $corner, 90, 90)
    $path.CloseFigure()

    $rect = New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)
    $c1 = [System.Drawing.Color]::FromArgb(69, 129, 255)
    $c2 = [System.Drawing.Color]::FromArgb(148, 92, 255)
    $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, 45)
    $g.FillPath($grad, $path)
    $grad.Dispose()
    $path.Dispose()

    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, [single]($Size * 0.075))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $cx = [single]($Size / 2.0)
    $cy = [single]($Size * 0.56)
    foreach ($r in @(0.34, 0.22, 0.10)) {
        $rf = [single]($Size * $r)
        $g.DrawArc($pen, $cx - $rf, $cy - $rf, $rf * 2, $rf * 2, 225, 90)
    }
    $dot = [single]($Size * 0.065)
    $dotBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $g.FillEllipse($dotBrush, $cx - $dot, $cy - $dot, $dot * 2, $dot * 2)
    $dotBrush.Dispose()
    $pen.Dispose()
    $g.Dispose()
    return $bmp
}

function Get-DibBytes {
    param($Bmp)
    $w = $Bmp.Width
    $h = $Bmp.Height
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $data = $Bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([int]40)                 # BITMAPINFOHEADER biSize
    $bw.Write([int]$w)                 # biWidth
    $bw.Write([int]($h * 2))           # biHeight (XOR + AND)
    $bw.Write([int16]1)                # biPlanes
    $bw.Write([int16]32)               # biBitCount
    $bw.Write([int]0)                  # biCompression
    $bw.Write([int]0)                  # biSizeImage
    $bw.Write([int]0)                  # biXPelsPerMeter
    $bw.Write([int]0)                  # biYPelsPerMeter
    $bw.Write([int]0)                  # biClrUsed
    $bw.Write([int]0)                  # biClrImportant
    $pixels = New-Object byte[] ($data.Stride * $h)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $pixels, 0, $pixels.Length)
    $Bmp.UnlockBits($data)
    $bw.Write($pixels)
    $maskRow = [int]((($w + 31) / 32) * 4)
    $mask = New-Object byte[] ($maskRow * $h)
    $bw.Write($mask)
    $bw.Flush()
    $bytes = $ms.ToArray()
    $bw.Dispose()
    $ms.Dispose()
    return $bytes
}

$sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
$images = @()
foreach ($s in $sizes) {
    $bmp = New-AppBitmap -Size $s
    if ($s -eq 256) { $bmp.Save($Preview, [System.Drawing.Imaging.ImageFormat]::Png) }
    $images += , @($s, [byte[]](Get-DibBytes -Bmp $bmp))
    $bmp.Dispose()
}

$outMs = New-Object System.IO.MemoryStream
$ow = New-Object System.IO.BinaryWriter($outMs)
$ow.Write([int16]0)
$ow.Write([int16]1)
$ow.Write([int16]$images.Count)
$offset = 6 + 16 * $images.Count
foreach ($img in $images) {
    $s = $img[0]
    $data = $img[1]
    $wh = $(if ($s -ge 256) { [byte]0 } else { [byte]$s })
    $ow.Write($wh)
    $ow.Write($wh)
    $ow.Write([byte]0)
    $ow.Write([byte]0)
    $ow.Write([int16]1)
    $ow.Write([int16]32)
    $ow.Write([int]$data.Length)
    $ow.Write([int]$offset)
    $offset += $data.Length
}
foreach ($img in $images) { $ow.Write($img[1]) }
$ow.Flush()
[System.IO.File]::WriteAllBytes($Out, $outMs.ToArray())
$ow.Dispose()
$outMs.Dispose()

"ICON=$Out SIZE=$((Get-Item $Out).Length)"
