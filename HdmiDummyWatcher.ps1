Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# CHANGE THIS: pick a substring that reliably identifies your dummy adapter's monitor InstanceId
$TargetInstanceIdContains = "DISPLAY\DEFAULT_MONITOR\1&C528B8A&3&UID256"

# Optional: if you have multiple monitors and only want a specific adapter,
# make this more specific once you know the adapter's InstanceId substring.
#$TargetInstanceIdContains = "DISPLAY\GSM"  # example

function Test-DummyPresent {
    try {
        # Prefer Get-PnpDevice when available (newer Windows/PowerShell)
        if (Get-Command -Name Get-PnpDevice -ErrorAction SilentlyContinue) {
            $monitors = Get-PnpDevice -Class Monitor -ErrorAction Stop |
                Where-Object { $_.Status -eq "OK" -and $_.InstanceId -like "*$TargetInstanceIdContains*" }
            return ($monitors.Count -ge 1)
        } else {
            # Fallback: use CIM to query PnP entities and match PNPDeviceID
            # This helps on systems where the PnPDevice cmdlets are not present.
            $devices = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop |
                Where-Object { $_.PNPDeviceID -like "*$TargetInstanceIdContains*" }
            return ($devices.Count -ge 1)
        }
    } catch {
        # If anything goes wrong (cmdlet missing, permission error, etc.), return $false
        return $false
    }
}

function New-Icon([System.Drawing.Color]$color) {
    $bmp = New-Object System.Drawing.Bitmap 16,16
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $brush = New-Object System.Drawing.SolidBrush($color)
    $g.FillEllipse($brush, 1,1,14,14)
    $g.Dispose()
    $hIcon = $bmp.GetHicon()
    return [System.Drawing.Icon]::FromHandle($hIcon)
}

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Visible = $true
$notify.Text = "HDMI Dummy Watcher"

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$exitItem = $menu.Items.Add("Exit")
$exitItem.add_Click({
    $notify.Visible = $false
    $notify.Dispose()
    [System.Windows.Forms.Application]::Exit()
})
$notify.ContextMenuStrip = $menu

$state = $null
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000  # check every 2 seconds
$timer.Add_Tick({
    $present = Test-DummyPresent

    if ($state -ne $present) {
        $state = $present
        if ($present) {
            $notify.Icon = (New-Icon ([System.Drawing.Color]::LimeGreen))
            $notify.BalloonTipTitle = "HDMI Dummy: Present"
            $notify.BalloonTipText  = "Dummy display adapter detected."
            $notify.ShowBalloonTip(2000)
        } else {
            $notify.Icon = (New-Icon ([System.Drawing.Color]::Red))
            $notify.BalloonTipTitle = "WARNING: HDMI Dummy Missing"
            $notify.BalloonTipText  = "Dummy display adapter NOT detected. Local display may be visible."
            $notify.ShowBalloonTip(5000)
        }
    }
})
$timer.Start()

# Start with correct icon immediately
$state = Test-DummyPresent
$notify.Icon = (New-Icon ($(if ($state) {[System.Drawing.Color]::LimeGreen} else {[System.Drawing.Color]::Red})))

[System.Windows.Forms.Application]::Run()