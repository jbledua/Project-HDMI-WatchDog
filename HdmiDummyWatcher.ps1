Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# CSV file containing monitor configurations
# Columns: FriendlyName, InstanceId, Status (Required, Optional, Blocked)
$script:CsvPath = Join-Path $PSScriptRoot "monitors.csv"

# Load monitor configurations from CSV
function Get-MonitorConfig {
    if (Test-Path $script:CsvPath) {
        return @(Import-Csv $script:CsvPath)
    } else {
        Write-Warning "Monitor config file not found: $script:CsvPath"
        return @()
    }
}

# Get currently connected monitors with Status "OK"
function Get-ConnectedMonitors {
    try {
        if (Get-Command -Name Get-PnpDevice -ErrorAction SilentlyContinue) {
            return @(Get-PnpDevice -Class Monitor -ErrorAction Stop |
                Where-Object { $_.Status -eq "OK" })
        } else {
            return @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop |
                Where-Object { $_.PNPClass -eq "Monitor" -and $_.Status -eq "OK" })
        }
    } catch {
        return @()
    }
}

# Check if a monitor matching the InstanceId pattern is connected
function Test-MonitorPresent {
    param([string]$InstanceIdPattern)
    
    $connected = Get-ConnectedMonitors
    foreach ($monitor in $connected) {
        $id = if ($monitor.InstanceId) { $monitor.InstanceId } else { $monitor.PNPDeviceID }
        if ($id -like "*$InstanceIdPattern*") {
            return $true
        }
    }
    return $false
}

# Evaluate all monitor statuses and return overall status
# Priority order: Blocked (Black) -> Missing Required or Unlisted (Red) -> Optional connected (Yellow) -> All good (Green)
function Get-OverallStatus {
    $config = Get-MonitorConfig
    $connectedMonitors = Get-ConnectedMonitors
    $issues = @()
    
    # Track which connected monitors are accounted for in config
    $accountedMonitorIds = @()
    
    # First pass: Check for Blocked monitors (highest priority - Black)
    foreach ($entry in $config) {
        if ($entry.Status -eq "Blocked") {
            $present = Test-MonitorPresent -InstanceIdPattern $entry.InstanceId
            if ($present) {
                $issues += "BLOCKED: $($entry.FriendlyName)"
                return @{
                    Color = "Black"
                    Issues = $issues
                    Message = "Blocked monitor detected!"
                }
            }
        }
    }
    
    # Build list of all configured InstanceId patterns
    $configuredPatterns = @($config | ForEach-Object { $_.InstanceId })
    
    # Check for unlisted monitors (Red)
    foreach ($monitor in $connectedMonitors) {
        $id = if ($monitor.InstanceId) { $monitor.InstanceId } else { $monitor.PNPDeviceID }
        $isListed = $false
        
        foreach ($pattern in $configuredPatterns) {
            if ($id -like "*$pattern*") {
                $isListed = $true
                break
            }
        }
        
        if (-not $isListed) {
            $issues += "UNLISTED: $id"
        }
    }
    
    if ($issues.Count -gt 0) {
        return @{
            Color = "Red"
            Issues = $issues
            Message = "Unlisted monitor(s) connected!"
        }
    }
    
    # Check for missing Required monitors (Red)
    foreach ($entry in $config) {
        if ($entry.Status -eq "Required") {
            $present = Test-MonitorPresent -InstanceIdPattern $entry.InstanceId
            if (-not $present) {
                $issues += "MISSING: $($entry.FriendlyName)"
            }
        }
    }
    
    if ($issues.Count -gt 0) {
        return @{
            Color = "Red"
            Issues = $issues
            Message = "Required monitor(s) missing!"
        }
    }
    
    # Check for Optional monitors connected (Yellow)
    $optionalConnected = @()
    foreach ($entry in $config) {
        if ($entry.Status -eq "Optional") {
            $present = Test-MonitorPresent -InstanceIdPattern $entry.InstanceId
            if ($present) {
                $optionalConnected += $entry.FriendlyName
            }
        }
    }
    
    if ($optionalConnected.Count -gt 0) {
        return @{
            Color = "Yellow"
            Issues = @("Optional connected: " + ($optionalConnected -join ", "))
            Message = "Optional monitor(s) connected."
        }
    }
    
    # All good - only Required monitors connected (Green)
    return @{
        Color = "Green"
        Issues = @()
        Message = "All monitor requirements met."
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

# Convert status color name to System.Drawing.Color
function Get-StatusColor {
    param([string]$ColorName)
    
    switch ($ColorName) {
        "Black"  { return [System.Drawing.Color]::Black }
        "Red"    { return [System.Drawing.Color]::Red }
        "Yellow" { return [System.Drawing.Color]::Yellow }
        "Green"  { return [System.Drawing.Color]::LimeGreen }
        default  { return [System.Drawing.Color]::Gray }
    }
}

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Visible = $true
$notify.Text = "HDMI Dummy Watcher"

$script:menu = New-Object System.Windows.Forms.ContextMenuStrip

# Header item (disabled, just for display)
$script:headerItem = $script:menu.Items.Add("Connected Monitors:")
$script:headerItem.Enabled = $false
$script:headerItem.Font = New-Object System.Drawing.Font($script:headerItem.Font, [System.Drawing.FontStyle]::Bold)

# Separator after header
$script:menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

# Placeholder for monitor list - will be updated dynamically
$script:monitorMenuStartIndex = $script:menu.Items.Count

# Add separator before Exit
$script:exitSeparator = New-Object System.Windows.Forms.ToolStripSeparator

# Exit item
$script:exitItem = New-Object System.Windows.Forms.ToolStripMenuItem("Exit")
$script:exitItem.add_Click({
    $notify.Visible = $false
    $notify.Dispose()
    [System.Windows.Forms.Application]::Exit()
})

$notify.ContextMenuStrip = $script:menu

# Function to update the context menu with connected monitors
function Update-ContextMenu {
    # Remove old monitor items (between header separator and exit separator)
    while ($script:menu.Items.Count -gt $script:monitorMenuStartIndex) {
        $script:menu.Items.RemoveAt($script:monitorMenuStartIndex)
    }
    
    $config = Get-MonitorConfig
    $hasConnected = $false
    
    # Add Required monitors that are connected
    foreach ($entry in $config) {
        if ($entry.Status -eq "Required") {
            $present = Test-MonitorPresent -InstanceIdPattern $entry.InstanceId
            if ($present) {
                $item = $script:menu.Items.Add("[Required] $($entry.FriendlyName)")
                $item.Enabled = $false
                $item.ForeColor = [System.Drawing.Color]::Green
                $hasConnected = $true
            }
        }
    }
    
    # Add Optional monitors that are connected
    foreach ($entry in $config) {
        if ($entry.Status -eq "Optional") {
            $present = Test-MonitorPresent -InstanceIdPattern $entry.InstanceId
            if ($present) {
                $item = $script:menu.Items.Add("[Optional] $($entry.FriendlyName)")
                $item.Enabled = $false
                $item.ForeColor = [System.Drawing.Color]::DarkOrange
                $hasConnected = $true
            }
        }
    }
    
    # If no monitors connected, show a message
    if (-not $hasConnected) {
        $item = $script:menu.Items.Add("(No configured monitors connected)")
        $item.Enabled = $false
        $item.ForeColor = [System.Drawing.Color]::Gray
    }
    
    # Add separator and Exit at the end
    $script:menu.Items.Add($script:exitSeparator)
    $script:menu.Items.Add($script:exitItem)
}

# Update menu when it opens
$script:menu.add_Opening({ Update-ContextMenu })

$script:lastColor = $null
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000  # check every 2 seconds
$timer.Add_Tick({
    $result = Get-OverallStatus

    # Only update if color changed
    if ($script:lastColor -ne $result.Color) {
        $script:lastColor = $result.Color
        
        $notify.Icon = (New-Icon (Get-StatusColor $result.Color))
        $notify.BalloonTipTitle = "Monitor Status: $($result.Color)"
        $notify.BalloonTipText = if ($result.Issues.Count -gt 0) { $result.Issues -join "`n" } else { $result.Message }
        $notify.ShowBalloonTip(3000)
    }
})
$timer.Start()

# Start with correct icon immediately
$initialResult = Get-OverallStatus
$script:lastColor = $initialResult.Color
$notify.Icon = (New-Icon (Get-StatusColor $initialResult.Color))

[System.Windows.Forms.Application]::Run()