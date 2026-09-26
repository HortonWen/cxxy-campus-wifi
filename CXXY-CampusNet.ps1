#Requires -Version 5.1
<#
    东南大学成贤学院 Student_CX 校园网 Windows 一键连接 / 自动登录工具

    图形界面用法：
        双击「启动-成贤校园网登录.bat」

    命令行用法（便于开机自启等场景）：
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File CXXY-CampusNet.ps1 -Mode Auto
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File CXXY-CampusNet.ps1 -Mode Check
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File CXXY-CampusNet.ps1 -Mode Login -User 卡号 -Pass 密码

    密码安全：
        默认不保存密码；只有勾选「本机加密保存」后，才会用 Windows DPAPI
        （当前登录用户账户级加密）存到 %APPDATA%\CXXY-CampusNet\cred.bin，
        不会以明文写入任何脚本、配置或日志。
#>
[CmdletBinding()]
param(
    [ValidateSet('Gui','Connect','Check','OpenPortal','Login','Auto')]
    [string]$Mode = 'Gui',
    [string]$Ssid = 'Student_CX',
    [string]$User = '',
    [string]$Pass = '',
    [string]$Isp = '校园内网',
    [switch]$SaveCred
)

$ErrorActionPreference = 'Continue'
$script:GuiMode = $false
$script:LogSink = $null
$script:UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
$script:ConfigDir = Join-Path $env:APPDATA 'CXXY-CampusNet'
$script:CredFile = Join-Path $script:ConfigDir 'cred.bin'

try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

function Write-Log {
    param([string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message
    if ($script:LogSink -and $script:GuiMode) {
        $script:LogSink.AppendText($line + [Environment]::NewLine)
        $script:LogSink.SelectionStart = $script:LogSink.TextLength
        $script:LogSink.ScrollToCaret()
    } elseif (-not $script:GuiMode) {
        Write-Host $line
    }
}

function Get-Regex1 {
    param([string]$InputString, [string]$Pattern)
    $m = [regex]::Match([string]$InputString, $Pattern)
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

function Get-WlanInfo {
    $out = (& netsh wlan show interfaces 2>$null | Out-String)
    return [pscustomobject]@{
        Ssid  = (Get-Regex1 -InputString $out -Pattern '(?im)^\s*SSID\s*:\s*(.+?)\s*$')
        State = (Get-Regex1 -InputString $out -Pattern '(?im)^\s*State\s*:\s*(.+?)\s*$')
    }
}

function Add-WlanOpenProfile {
    param([string]$Ssid)
    $esc = $Ssid.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;').Replace("'",'&apos;')
    $xml = "<?xml version=`"1.0`"?>`n<WLANProfile xmlns=`"http://www.microsoft.com/networking/WLAN/profile/v1`">`n  <name>$esc</name>`n  <SSIDConfig><SSID><name>$esc</name></SSID></SSIDConfig>`n  <connectionType>ESS</connectionType>`n  <connectionMode>auto</connectionMode>`n  <MSM><security><authEncryption><authentication>open</authentication><encryption>none</encryption></authEncryption></security></MSM>`n</WLANProfile>"
    $tmp = Join-Path $env:TEMP ('cxxy-wlan-' + [guid]::NewGuid().ToString('N') + '.xml')
    [IO.File]::WriteAllText($tmp, $xml, [Text.Encoding]::UTF8)
    try {
        & netsh wlan add profile filename="$tmp" user=all 2>$null | Out-Null
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Connect-CxxyWifi {
    param([string]$Ssid, [int]$TimeoutSec = 25)
    $info = Get-WlanInfo
    if ($info.Ssid -eq $Ssid -and $info.State -match 'connected') {
        Write-Log "已连接 $($info.Ssid)"
        return $true
    }
    $profiles = (& netsh wlan show profiles 2>$null | Out-String)
    if ($profiles -notmatch [regex]::Escape($Ssid)) {
        Write-Log "未找到 $Ssid 的无线配置，正在创建 ..."
        Add-WlanOpenProfile -Ssid $Ssid
    }
    Write-Log "正在连接无线 $Ssid ..."
    & netsh wlan connect name="$Ssid" ssid="$Ssid" 2>$null | Out-Null
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 800
        $info = Get-WlanInfo
        if ($info.Ssid -eq $Ssid -and $info.State -match 'connected') {
            Write-Log "已连上 $Ssid"
            return $true
        }
    }
    Write-Log "连接 $Ssid 失败，请确认能搜到该信号"
    return $false
}

function Test-Tcp {
    param([string]$HostName, [int]$Port, [int]$TimeoutMs = 2500)
    $client = New-Object Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($HostName, $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne($TimeoutMs)) {
            $client.EndConnect($iar)
            return $true
        }
        return $false
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Test-Online {
    $checks = @(
        @{ Url = 'http://captive.apple.com/hotspot-detect.html'; Needle = 'Success' },
        @{ Url = 'http://www.msftconnecttest.com/connecttest.txt'; Needle = 'Microsoft Connect Test' },
        @{ Url = 'https://www.baidu.com/'; Needle = '' }
    )
    foreach ($ch in $checks) {
        try {
            $r = Invoke-WebRequest -Uri $ch.Url -UseBasicParsing -TimeoutSec 6 -MaximumRedirection 5 -ErrorAction Stop -Headers @{ 'User-Agent' = $script:UA }
            if ($r.StatusCode -eq 200) {
                if ($ch.Needle -eq '' -or [string]$r.Content -match [regex]::Escape($ch.Needle)) {
                    return $true
                }
            }
        } catch { }
    }
    return $false
}

function Get-PortalPage {
    $urls = @('http://6.6.6.6/', 'http://cxxy.seu.edu.cn/')
    foreach ($u in $urls) {
        try {
            $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 10 -MaximumRedirection 5 -ErrorAction Stop -Headers @{ 'User-Agent' = $script:UA }
            $final = $u
            if ($r.BaseResponse -and $r.BaseResponse.ResponseUri) { $final = $r.BaseResponse.ResponseUri.AbsoluteUri }
            return [pscustomobject]@{ Uri = $final; Content = [string]$r.Content; Status = [int]$r.StatusCode }
        } catch {
            if ($_.Exception.Response -and $_.Exception.Response.ResponseUri) {
                return [pscustomobject]@{ Uri = $_.Exception.Response.ResponseUri.AbsoluteUri; Content = ''; Status = [int]$_.Exception.Response.StatusCode }
            }
        }
    }
    return $null
}

function Get-AttrValue {
    param([string]$Tag, [string]$Name)
    return (Get-Regex1 -InputString $Tag -Pattern ('(?is)\b' + [regex]::Escape($Name) + '\s*=\s*["'']([^"'']*)["'']'))
}

function Resolve-Url {
    param([string]$Base, [string]$Relative)
    if ([string]::IsNullOrWhiteSpace($Relative)) { return $Base }
    if ($Relative -match '^https?://') { return $Relative }
    $b = [uri]$Base
    if ($Relative.StartsWith('/')) {
        return ($b.Scheme + '://' + $b.Authority + $Relative)
    }
    $path = $b.AbsolutePath
    $idx = $path.LastIndexOf('/')
    if ($idx -lt 0) { $path = '/' } else { $path = $path.Substring(0, $idx + 1) }
    return ($b.Scheme + '://' + $b.Authority + $path + $Relative)
}

function Submit-PortalForm {
    param([object]$Portal, [string]$User, [string]$Pass, [string]$Isp)
    $html = [string]$Portal.Content
    if (-not $html) { return $null }
    $base = [string]$Portal.Uri
    $forms = [regex]::Matches($html, '(?is)<form\b[^>]*>.*?</form\s*>')
    foreach ($fm in $forms) {
        $open = [regex]::Match($fm.Value, '(?is)<form\b[^>]*>').Value
        $action = Get-AttrValue -Tag $open -Name 'action'
        $inner = [regex]::Replace($fm.Value, '(?is)^.*?<form\b[^>]*>', '')
        $inner = [regex]::Replace($inner, '(?is)</form\s*>.*$', '')

        $fields = @{}
        $passwordName = ''
        $textNames = @()
        $selectInfo = $null
        $controls = [regex]::Matches($inner, '(?is)<(input|select|textarea)\b[^>]*>')
        foreach ($ctrl in $controls) {
            $tag = $ctrl.Value
            $type = Get-AttrValue -Tag $tag -Name 'type'
            $name = Get-AttrValue -Tag $tag -Name 'name'
            $value = Get-AttrValue -Tag $tag -Name 'value'
            if ($type -match '(?i)hidden') {
                if ($name) { $fields[$name] = $value }
                continue
            }
            if ($type -match '(?i)password') {
                if ($name) { $passwordName = $name; $fields[$name] = $Pass }
                continue
            }
            if ($type -match '(?i)submit|button|image|reset') { continue }
            if ($tag -match '(?i)^<select') {
                if ($name) {
                    $sels = [regex]::Matches($inner, '(?is)<select\b[^>]*name\s*=\s*["'']' + [regex]::Escape($name) + '["''][^>]*>(.*?)</select\s*>')
                    if ($sels.Count -gt 0) {
                        $optInner = $sels[0].Groups[1].Value
                        $opts = [regex]::Matches($optInner, '(?is)<option\b[^>]*value\s*=\s*["'']([^"'']*)["''][^>]*>(.*?)</option\s*>')
                        $options = @()
                        foreach ($o in $opts) {
                            $options += [pscustomobject]@{
                                Value = $o.Groups[1].Value
                                Text  = ([regex]::Replace($o.Groups[2].Value, '(?s)<.*?>', '')).Trim()
                            }
                        }
                        $selectInfo = [pscustomobject]@{ Name = $name; Options = $options }
                    }
                }
                continue
            }
            if ($name) { $textNames += $name; $fields[$name] = $value }
        }

        if (-not $passwordName) { continue }

        $userField = ''
        foreach ($cand in $textNames) {
            if ($cand -match '(?i)(user|name|account|login|id|mobile|phone|uname|ddd)') { $userField = $cand; break }
        }
        if (-not $userField -and $textNames.Count -ge 1) { $userField = $textNames[0] }
        if ($userField) { $fields[$userField] = $User }

        if ($selectInfo -and $Isp) {
            $pick = $selectInfo.Options | Where-Object { $_.Text -match [regex]::Escape($Isp) } | Select-Object -First 1
            if (-not $pick) { $pick = $selectInfo.Options | Select-Object -First 1 }
            if ($pick) { $fields[$selectInfo.Name] = $pick.Value }
        }

        $postUri = Resolve-Url -Base $base -Relative $action
        try {
            $r = Invoke-WebRequest -Uri $postUri -Method POST -Body $fields `
                -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing `
                -TimeoutSec 12 -MaximumRedirection 5 -ErrorAction Stop `
                -Headers @{ 'User-Agent' = $script:UA; 'Referer' = $base }
            $final = $postUri
            if ($r.BaseResponse -and $r.BaseResponse.ResponseUri) { $final = $r.BaseResponse.ResponseUri.AbsoluteUri }
            return [pscustomobject]@{ Ok = $true; Content = [string]$r.Content; Uri = $final; Detail = '已按认证页表单提交' }
        } catch {
            return [pscustomobject]@{ Ok = $false; Content = ''; Uri = $postUri; Detail = ('表单提交失败: ' + $_.Exception.Message) }
        }
    }
    return $null
}

function Get-LocalNetwork {
    $ip = ''; $mac = ''
    try {
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric | Select-Object -First 1
        if ($route) {
            $ipAddr = Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
            if ($ipAddr) { $ip = $ipAddr.IPAddress }
            $adapter = Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue
            if ($adapter) { $mac = ($adapter.MacAddress -replace '-', '') }
        }
    } catch { }
    return [pscustomobject]@{ Ip = [string]$ip; Mac = [string]$mac }
}

function Get-QueryValue {
    param([string]$Uri, [string]$Key)
    return (Get-Regex1 -InputString $Uri -Pattern ('(?i)[?&]' + [regex]::Escape($Key) + '=([^&]*)'))
}

function Invoke-DrcomEportal {
    param([object]$Portal, [string]$User, [string]$Pass)
    $b = [uri]$Portal.Uri
    $net = Get-LocalNetwork
    $ip = Get-QueryValue -Uri $Portal.Uri -Key 'wlan_user_ip'
    if (-not $ip) { $ip = $net.Ip }
    $mac = Get-QueryValue -Uri $Portal.Uri -Key 'wlan_user_mac'
    if (-not $mac) { $mac = $net.Mac }
    $ac = Get-QueryValue -Uri $Portal.Uri -Key 'wlan_ac_ip'
    $q = 'c=Portal&a=login&callback=dr1003&login_method=1&user_account={0}&user_password={1}&wlan_user_ip={2}&wlan_user_ipv6=&wlan_user_mac={3}&wlan_ac_ip={4}&wlan_ac_name=&jsVersion=3.3.3&v=10000' -f `
        [uri]::EscapeDataString($User), [uri]::EscapeDataString($Pass), $ip, $mac, $ac
    foreach ($port in @(801, 80, 8080)) {
        $url = 'http://{0}:{1}/eportal/?{2}' -f $b.Host, $port, $q
        try {
            $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10 -MaximumRedirection 0 -ErrorAction Stop `
                -Headers @{ 'User-Agent' = $script:UA; 'Referer' = $Portal.Uri }
            $txt = [string]$r.Content
            if ($txt -match 'result["'']?\s*[:=]\s*["'']?1') {
                return [pscustomobject]@{ Ok = $true; Detail = "Dr.COM ePortal 登录成功 (端口 $port)"; Content = $txt }
            }
        } catch { }
    }
    return [pscustomobject]@{ Ok = $false; Detail = 'Dr.COM ePortal 接口尝试未成功'; Content = '' }
}

function Open-PortalBrowser {
    Write-Log '正在打开校园网认证页 ...'
    Start-Process 'http://cxxy.seu.edu.cn/'
}

function Invoke-AutoLogin {
    param([string]$Ssid, [string]$User, [string]$Pass, [string]$Isp)
    if ([string]::IsNullOrWhiteSpace($User) -or [string]::IsNullOrWhiteSpace($Pass)) {
        Write-Log '缺少账号或密码，无法自动登录'
        return $false
    }
    if (-not (Connect-CxxyWifi -Ssid $Ssid)) {
        Open-PortalBrowser
        return $false
    }

    Write-Log '等待认证网关可达 ...'
    $deadline = (Get-Date).AddSeconds(30)
    $gwOk = $false
    while ((Get-Date) -lt $deadline) {
        if ((Test-Tcp -HostName '211.65.40.6' -Port 8080 -TimeoutMs 1500) -or
            (Test-Tcp -HostName '6.6.6.6' -Port 80 -TimeoutMs 1500)) {
            $gwOk = $true
            break
        }
        Start-Sleep -Seconds 1
    }

    if (Test-Online) {
        Write-Log '当前已通过认证，可直接上网'
        return $true
    }
    if (-not $gwOk) {
        Write-Log '网关暂不可达，稍后再试；先为你打开认证页'
        Open-PortalBrowser
        return $false
    }

    Write-Log '获取认证页面 ...'
    $portal = Get-PortalPage
    if (-not $portal) {
        Write-Log '无法读取认证页，改为手动登录'
        Open-PortalBrowser
        return $false
    }
    Write-Log ('认证页地址: ' + $portal.Uri)

    $res = Submit-PortalForm -Portal $portal -User $User -Pass $Pass -Isp $Isp
    if ($res -and $res.Ok) {
        Write-Log $res.Detail
        Start-Sleep -Seconds 2
        if (Test-Online) { Write-Log '自动登录成功，网络已通'; return $true }
    }

    $res2 = Invoke-DrcomEportal -Portal $portal -User $User -Pass $Pass
    if ($res2.Ok) {
        Write-Log $res2.Detail
        Start-Sleep -Seconds 2
        if (Test-Online) { Write-Log '自动登录成功，网络已通'; return $true }
    }

    Write-Log '自动登录未成功，已打开认证页，请手动输入并登录'
    Open-PortalBrowser
    return $false
}

function Test-Dpapi {
    try {
        Add-Type -AssemblyName System.Security -ErrorAction Stop
        $t = [System.Security.Cryptography.ProtectedData] -as [type]
        return ($null -ne $t)
    } catch {
        return $false
    }
}

function Save-Credential {
    param([string]$User, [string]$Pass, [string]$Isp)
    if (-not (Test-Dpapi)) {
        Write-Log '当前环境不支持本机加密保存，密码不会被保存'
        return $false
    }
    try {
        $plain = [Text.Encoding]::UTF8.GetBytes("$User`n$Pass`n$Isp")
        $enc = [System.Security.Cryptography.ProtectedData]::Protect($plain, $null, 'CurrentUser')
        New-Item -ItemType Directory -Path $script:ConfigDir -Force | Out-Null
        [IO.File]::WriteAllBytes($script:CredFile, $enc)
        Write-Log '密码已在本机加密保存（仅当前 Windows 账户可解密）'
        return $true
    } catch {
        Write-Log ('保存失败: ' + $_.Exception.Message)
        return $false
    }
}

function Read-Credential {
    if (-not (Test-Path $script:CredFile)) { return $null }
    if (-not (Test-Dpapi)) { return $null }
    try {
        $enc = [IO.File]::ReadAllBytes($script:CredFile)
        $plain = [System.Security.Cryptography.ProtectedData]::Unprotect($enc, $null, 'CurrentUser')
        $parts = [Text.Encoding]::UTF8.GetString($plain) -split "`n", 3
        if ($parts.Count -ge 2) {
            return [pscustomobject]@{
                User = $parts[0]
                Pass = $parts[1]
                Isp  = $(if ($parts.Count -ge 3) { $parts[2] } else { '校园内网' })
            }
        }
    } catch { }
    return $null
}

function Clear-Credential {
    if (Test-Path $script:CredFile) {
        Remove-Item -LiteralPath $script:CredFile -Force -ErrorAction SilentlyContinue
        Write-Log '已删除本机保存的登录信息'
    } else {
        Write-Log '没有保存过登录信息'
    }
}

function Show-Gui {
    $script:GuiMode = $true
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $accent    = [System.Drawing.Color]::FromArgb(47, 107, 255)
    $accentDk  = [System.Drawing.Color]::FromArgb(30, 86, 214)
    $accentDk2 = [System.Drawing.Color]::FromArgb(24, 70, 180)
    $body      = [System.Drawing.Color]::FromArgb(244, 246, 251)
    $ink       = [System.Drawing.Color]::FromArgb(31, 41, 55)
    $muted     = [System.Drawing.Color]::FromArgb(107, 114, 128)
    $soft      = [System.Drawing.Color]::FromArgb(232, 240, 254)
    $softDk    = [System.Drawing.Color]::FromArgb(214, 228, 250)
    $green     = [System.Drawing.Color]::FromArgb(22, 163, 74)
    $red       = [System.Drawing.Color]::FromArgb(220, 38, 38)
    $border    = [System.Drawing.Color]::FromArgb(216, 222, 234)
    $white     = [System.Drawing.Color]::White

    $titleFont = New-Object System.Drawing.Font('Microsoft YaHei UI', 15, [System.Drawing.FontStyle]::Bold)
    $boldFont  = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
    $baseFont  = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = '成贤校园网助手'
    $form.ClientSize = New-Object System.Drawing.Size(460, 588)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedSingle'
    $form.MaximizeBox = $false
    $form.BackColor = $body
    $form.Font = $baseFont

    # 顶部标题栏
    $header = New-Object System.Windows.Forms.Panel
    $header.Location = New-Object System.Drawing.Point(0, 0)
    $header.Size = New-Object System.Drawing.Size(460, 76)
    $header.BackColor = $accent
    $form.Controls.Add($header)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Location = New-Object System.Drawing.Point(20, 14)
    $lblTitle.AutoSize = $true
    $lblTitle.Text = '成贤校园网助手'
    $lblTitle.Font = $titleFont
    $lblTitle.ForeColor = $white
    $header.Controls.Add($lblTitle)

    $lblSub = New-Object System.Windows.Forms.Label
    $lblSub.Location = New-Object System.Drawing.Point(22, 49)
    $lblSub.AutoSize = $true
    $lblSub.Text = '东南大学成贤学院 · Student_CX 一键连接与自动认证'
    $lblSub.Font = $baseFont
    $lblSub.ForeColor = [System.Drawing.Color]::FromArgb(224, 234, 255)
    $header.Controls.Add($lblSub)

    # 设置卡片
    $card = New-Object System.Windows.Forms.Panel
    $card.Location = New-Object System.Drawing.Point(16, 92)
    $card.Size = New-Object System.Drawing.Size(428, 208)
    $card.BackColor = $white
    $card.BorderStyle = 'FixedSingle'
    $form.Controls.Add($card)

    $lblSsid = New-Object System.Windows.Forms.Label
    $lblSsid.Location = New-Object System.Drawing.Point(16, 18)
    $lblSsid.Size = New-Object System.Drawing.Size(80, 22)
    $lblSsid.Text = '无线信号名'
    $lblSsid.ForeColor = $ink
    $lblSsid.Font = $baseFont
    $card.Controls.Add($lblSsid)

    $txtSsid = New-Object System.Windows.Forms.TextBox
    $txtSsid.Location = New-Object System.Drawing.Point(100, 15)
    $txtSsid.Size = New-Object System.Drawing.Size(306, 24)
    $txtSsid.BorderStyle = 'FixedSingle'
    $txtSsid.Font = $baseFont
    $txtSsid.Text = $Ssid
    $card.Controls.Add($txtSsid)

    $lblUser = New-Object System.Windows.Forms.Label
    $lblUser.Location = New-Object System.Drawing.Point(16, 58)
    $lblUser.Size = New-Object System.Drawing.Size(80, 22)
    $lblUser.Text = '门户账号'
    $lblUser.ForeColor = $ink
    $lblUser.Font = $baseFont
    $card.Controls.Add($lblUser)

    $txtUser = New-Object System.Windows.Forms.TextBox
    $txtUser.Location = New-Object System.Drawing.Point(100, 55)
    $txtUser.Size = New-Object System.Drawing.Size(306, 24)
    $txtUser.BorderStyle = 'FixedSingle'
    $txtUser.Font = $baseFont
    $card.Controls.Add($txtUser)

    $lblPass = New-Object System.Windows.Forms.Label
    $lblPass.Location = New-Object System.Drawing.Point(16, 98)
    $lblPass.Size = New-Object System.Drawing.Size(80, 22)
    $lblPass.Text = '门户密码'
    $lblPass.ForeColor = $ink
    $lblPass.Font = $baseFont
    $card.Controls.Add($lblPass)

    $txtPass = New-Object System.Windows.Forms.TextBox
    $txtPass.Location = New-Object System.Drawing.Point(100, 95)
    $txtPass.Size = New-Object System.Drawing.Size(306, 24)
    $txtPass.BorderStyle = 'FixedSingle'
    $txtPass.UseSystemPasswordChar = $true
    $txtPass.Font = $baseFont
    $card.Controls.Add($txtPass)

    $lblIsp = New-Object System.Windows.Forms.Label
    $lblIsp.Location = New-Object System.Drawing.Point(16, 138)
    $lblIsp.Size = New-Object System.Drawing.Size(80, 22)
    $lblIsp.Text = '出口线路'
    $lblIsp.ForeColor = $ink
    $lblIsp.Font = $baseFont
    $card.Controls.Add($lblIsp)

    $cmbIsp = New-Object System.Windows.Forms.ComboBox
    $cmbIsp.Location = New-Object System.Drawing.Point(100, 135)
    $cmbIsp.Size = New-Object System.Drawing.Size(150, 24)
    $cmbIsp.DropDownStyle = 'DropDownList'
    $cmbIsp.FlatStyle = 'Flat'
    $cmbIsp.Font = $baseFont
    @('校园内网','中国电信','中国移动') | ForEach-Object { [void]$cmbIsp.Items.Add($_) }
    $cmbIsp.SelectedIndex = 0
    $card.Controls.Add($cmbIsp)

    $chkSave = New-Object System.Windows.Forms.CheckBox
    $chkSave.Location = New-Object System.Drawing.Point(16, 172)
    $chkSave.Size = New-Object System.Drawing.Size(396, 22)
    $chkSave.Text = '本机加密保存密码（仅本人账户可解密）'
    $chkSave.ForeColor = $muted
    $chkSave.Font = $baseFont
    $chkSave.BackColor = $white
    $card.Controls.Add($chkSave)

    # 主按钮
    $btnAuto = New-Object System.Windows.Forms.Button
    $btnAuto.Location = New-Object System.Drawing.Point(16, 314)
    $btnAuto.Size = New-Object System.Drawing.Size(208, 46)
    $btnAuto.Text = '连接并自动登录'
    $btnAuto.Font = $boldFont
    $btnAuto.FlatStyle = 'Flat'
    $btnAuto.FlatAppearance.BorderSize = 0
    $btnAuto.FlatAppearance.MouseOverBackColor = $accentDk
    $btnAuto.FlatAppearance.MouseDownBackColor = $accentDk2
    $btnAuto.BackColor = $accent
    $btnAuto.ForeColor = $white
    $form.Controls.Add($btnAuto)

    $btnOpen = New-Object System.Windows.Forms.Button
    $btnOpen.Location = New-Object System.Drawing.Point(240, 314)
    $btnOpen.Size = New-Object System.Drawing.Size(204, 46)
    $btnOpen.Text = '只打开认证页面'
    $btnOpen.Font = $boldFont
    $btnOpen.FlatStyle = 'Flat'
    $btnOpen.FlatAppearance.BorderSize = 0
    $btnOpen.FlatAppearance.MouseOverBackColor = $softDk
    $btnOpen.FlatAppearance.MouseDownBackColor = $softDk
    $btnOpen.BackColor = $soft
    $btnOpen.ForeColor = $accent
    $form.Controls.Add($btnOpen)

    # 次按钮
    function Set-SecondaryButton {
        param($b, $x, $w, $text)
        $b.Location = New-Object System.Drawing.Point($x, 372)
        $b.Size = New-Object System.Drawing.Size($w, 36)
        $b.Text = $text
        $b.Font = $baseFont
        $b.FlatStyle = 'Flat'
        $b.FlatAppearance.BorderSize = 1
        $b.FlatAppearance.BorderColor = $border
        $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(238, 242, 248)
        $b.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
        $b.BackColor = $white
        $b.ForeColor = $ink
        $form.Controls.Add($b)
    }

    $btnCheck = New-Object System.Windows.Forms.Button
    Set-SecondaryButton -b $btnCheck -x 16 -w 132 -text '检查网络状态'

    $btnSelf = New-Object System.Windows.Forms.Button
    Set-SecondaryButton -b $btnSelf -x 158 -w 132 -text '自助服务'

    $btnClear = New-Object System.Windows.Forms.Button
    Set-SecondaryButton -b $btnClear -x 300 -w 144 -text '清除保存'

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Location = New-Object System.Drawing.Point(18, 418)
    $lblStatus.Size = New-Object System.Drawing.Size(424, 22)
    $lblStatus.Text = '● 状态：尚未检测'
    $lblStatus.Font = $boldFont
    $lblStatus.ForeColor = $muted
    $form.Controls.Add($lblStatus)

    $txtLog = New-Object System.Windows.Forms.TextBox
    $txtLog.Location = New-Object System.Drawing.Point(16, 448)
    $txtLog.Size = New-Object System.Drawing.Size(428, 124)
    $txtLog.Multiline = $true
    $txtLog.ReadOnly = $true
    $txtLog.ScrollBars = 'Vertical'
    $txtLog.BorderStyle = 'FixedSingle'
    $txtLog.BackColor = $white
    $txtLog.ForeColor = $ink
    $txtLog.Font = $baseFont
    $form.Controls.Add($txtLog)
    $script:LogSink = $txtLog

    $btnAuto.Add_Click({
        $u = $txtUser.Text.Trim()
        $p = $txtPass.Text
        $i = $cmbIsp.SelectedItem.ToString()
        if (-not $u -or -not $p) {
            Write-Log '请先填写门户账号和密码'
            $lblStatus.Text = '● 请先填写账号密码'
            $lblStatus.ForeColor = $red
            return
        }
        if ($chkSave.Checked) { [void](Save-Credential -User $u -Pass $p -Isp $i) }
        $lblStatus.Text = '● 正在连接并自动登录…'
        $lblStatus.ForeColor = $accent
        $ok = Invoke-AutoLogin -Ssid $txtSsid.Text.Trim() -User $u -Pass $p -Isp $i
        if ($ok) {
            $lblStatus.Text = '● 已认证，可正常上网'
            $lblStatus.ForeColor = $green
        } else {
            $lblStatus.Text = '● 未完成登录，请查看下方日志'
            $lblStatus.ForeColor = $red
        }
    })

    $btnOpen.Add_Click({
        Open-PortalBrowser
        $lblStatus.Text = '● 已打开认证页，请在浏览器中登录'
        $lblStatus.ForeColor = $accent
    })

    $btnCheck.Add_Click({
        $info = Get-WlanInfo
        Write-Log ('当前无线: ' + $(if ($info.Ssid) { $info.Ssid } else { '未连接' }) + ' / ' + $(if ($info.State) { $info.State } else { '未知' }))
        if (Test-Online) {
            Write-Log '网络状态: 已通过认证，可以上网'
            $lblStatus.Text = '● 已通过认证，可正常上网'
            $lblStatus.ForeColor = $green
        } else {
            Write-Log '网络状态: 未认证或无法访问外网'
            $lblStatus.Text = '● 未认证，需要登录'
            $lblStatus.ForeColor = $red
        }
    })

    $btnSelf.Add_Click({
        Start-Process 'http://211.65.40.6:8080/Self'
        $lblStatus.Text = '● 已打开自助服务'
        $lblStatus.ForeColor = $accent
    })

    $btnClear.Add_Click({
        Clear-Credential
        $lblStatus.Text = '● 已清除本机保存的登录信息'
        $lblStatus.ForeColor = $muted
    })

    $saved = Read-Credential
    if ($saved) {
        $txtUser.Text = $saved.User
        $txtPass.Text = $saved.Pass
        $idx = $cmbIsp.Items.IndexOf($saved.Isp)
        if ($idx -ge 0) { $cmbIsp.SelectedIndex = $idx }
        $chkSave.Checked = $true
        Write-Log '已载入本机加密保存的登录信息'
        $lblStatus.Text = '● 已载入本机保存的登录信息'
        $lblStatus.ForeColor = $muted
    } else {
        Write-Log '填写账号密码后点「连接并自动登录」；密码默认不保存'
    }

    [void]$form.ShowDialog()
}

switch ($Mode) {
    'Gui' {
        Show-Gui
    }
    'Connect' {
        [void](Connect-CxxyWifi -Ssid $Ssid)
    }
    'Check' {
        $info = Get-WlanInfo
        Write-Log ('当前无线: ' + $(if ($info.Ssid) { $info.Ssid } else { '未连接' }))
        if (Test-Online) { Write-Log '网络状态: 已通过认证，可以上网' } else { Write-Log '网络状态: 未认证或无法访问外网' }
    }
    'OpenPortal' {
        Open-PortalBrowser
    }
    'Login' {
        if (-not $User) { $User = Read-Host '请输入门户账号(校园卡号)' }
        if (-not $Pass) {
            $sec = Read-Host '请输入门户密码' -AsSecureString
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
            $Pass = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
        if ($SaveCred) { [void](Save-Credential -User $User -Pass $Pass -Isp $Isp) }
        [void](Invoke-AutoLogin -Ssid $Ssid -User $User -Pass $Pass -Isp $Isp)
    }
    'Auto' {
        $saved = Read-Credential
        if ($saved) {
            [void](Invoke-AutoLogin -Ssid $Ssid -User $saved.User -Pass $saved.Pass -Isp $saved.Isp)
        } else {
            if (Connect-CxxyWifi -Ssid $Ssid) { Open-PortalBrowser }
        }
    }
}
