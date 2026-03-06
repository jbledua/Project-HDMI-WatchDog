# Project-HDMI-WatchDog

Project-HDMI-WatchDog is a lightweight PowerShell utility that monitors the presence of display adapters (such as dummy HDMI plugs) on a Windows system.

If required adapters are disconnected or unauthorized monitors are connected, the tool displays a warning notification in the system tray so administrators know that the system's display configuration may have changed.

## Features

- **System Tray Icon** - Color-coded status indicator
- **CSV Configuration** - Easy to configure monitor rules
- **Right-click Menu** - View connected Required and Optional monitors
- **Real-time Monitoring** - Checks every 2 seconds for changes

## Status Colors

| Color | Meaning |
|-------|---------|
| 🟢 **Green** | All Required monitors connected, no issues |
| 🟡 **Yellow** | Optional monitor(s) connected |
| 🔴 **Red** | Required monitor missing OR unlisted monitor connected |
| ⚫ **Black** | Blocked monitor detected |

## Getting Started

### 1. Find Your Monitor Device IDs

Run this PowerShell command to list all connected monitors:

```powershell
Get-PnpDevice -Class Monitor | Where-Object { $_.Status -eq "OK" } | Select-Object Status, InstanceId, FriendlyName | Format-Table -AutoSize
```

Example output:
```
Status InstanceId                                  FriendlyName
------ ----------                                  ------------
OK     DISPLAY\IDVED11\5&1732B42C&0&UID4358        Generic PnP Monitor
OK     DISPLAY\SAM7106\5&1732B42C&0&UID4354        Generic PnP Monitor
```

To see ALL monitors (including disconnected ones):

```powershell
Get-PnpDevice -Class Monitor | Select-Object Status, InstanceId, FriendlyName | Format-Table -AutoSize
```

### 2. Configure the CSV File

Create or edit `monitors.csv` in the same folder as `HdmiDummyWatcher.ps1`.

**CSV Format:**
```csv
FriendlyName,InstanceId,Status
```

**Columns:**
- **FriendlyName** - Your custom name for the monitor (for display purposes)
- **InstanceId** - Full or partial Device Instance ID from PowerShell (use enough to uniquely identify)
- **Status** - One of: `Required`, `Optional`, or `Blocked`

**Status Rules:**
- **Required** - Monitor MUST be connected (Red if missing)
- **Optional** - Monitor CAN be connected (Yellow when connected, no warning when disconnected)
- **Blocked** - Monitor must NOT be connected (Black if detected)

### 3. Run the Script

```powershell
.\HdmiDummyWatcher.ps1
```

The script will run in the background with a system tray icon. Right-click the icon to see connected monitors or exit.

## Example Configuration

See `monitors.example.csv` for a template:

```csv
FriendlyName,InstanceId,Status
HDMI Dummy Port 1,REPLACE_WITH_YOUR_DEVICE_ID,Required
HDMI Dummy Port 2,REPLACE_WITH_YOUR_DEVICE_ID,Required
Office Monitor,REPLACE_WITH_YOUR_DEVICE_ID,Optional
Personal Laptop Display,REPLACE_WITH_YOUR_DEVICE_ID,Blocked
```

## Tips

- Use partial InstanceId patterns to match multiple similar devices (e.g., `DISPLAY\IDVED11` matches all IDVED11 monitors)
- Use full InstanceId for exact matching (e.g., `DISPLAY\IDVED11\5&1732B42C&0&UID4358`)
- Common dummy HDMI adapter IDs often contain `IDVED11` or `DEFAULT_MONITOR`
- Samsung monitors typically start with `SAM`, LG with `GSM`, Dell with `DEL`, etc.

## Run at Login (Optional)

To automatically start the watcher when you log in, you can use one of these methods:

### Method 1: Startup Folder (Easiest)

1. Press `Win + R`, type `shell:startup`, and press Enter
2. Create a shortcut to the script in this folder:
   - Right-click in the folder → **New** → **Shortcut**
   - For the location, enter:
     ```
     powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Path\To\HdmiDummyWatcher.ps1"
     ```
   - Replace `C:\Path\To\` with the actual path to your script
   - Name it "HDMI Dummy Watcher"

### Method 2: Task Scheduler (More Control)

1. Open **Task Scheduler** (`taskschd.msc`)
2. Click **Create Task** (not Basic Task)
3. **General tab:**
   - Name: `HDMI Dummy Watcher`
   - Check "Run only when user is logged on"
4. **Triggers tab:**
   - Click **New**
   - Begin the task: **At log on**
   - Specific user: Your username
5. **Actions tab:**
   - Click **New**
   - Action: **Start a program**
   - Program/script: `powershell.exe`
   - Add arguments:
     ```
     -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Path\To\HdmiDummyWatcher.ps1"
     ```
6. **Conditions tab:**
   - Uncheck "Start the task only if the computer is on AC power" (if on laptop)
7. Click **OK** to save

### Method 3: PowerShell Command (Quick Setup)

Run this in an elevated PowerShell prompt to create a scheduled task:

```powershell
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument '-WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Path\To\HdmiDummyWatcher.ps1"'
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "HDMI Dummy Watcher" -Action $Action -Trigger $Trigger -Settings $Settings -Description "Monitors HDMI dummy adapter presence"
```

> **Note:** Replace `C:\Path\To\` with the actual path to your `HdmiDummyWatcher.ps1` script in all methods above.
