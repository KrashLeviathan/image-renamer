# ============================================================================
# Image Geolocation Renamer - Core Logic (PowerShell)
# This script is called by the companion .bat file.
# ============================================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RenamedDir = Join-Path $ScriptDir "Renamed"
$PendingDir = Join-Path $ScriptDir "Pending"
$OriginalDir = Join-Path $ScriptDir "Original"
$LogsDir = Join-Path $ScriptDir "Logs"
$ExifToolPath = Join-Path $ScriptDir "exiftool.exe"

# Generate Log File Name based on current timestamp
$TimestampForLog = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFileName = "image_rename_log_$TimestampForLog.txt"
$LogFilePath = Join-Path $LogsDir $LogFileName

# Ensure Renamed directory exists
if (-not (Test-Path $RenamedDir)) {
    New-Item -ItemType Directory -Path $RenamedDir | Out-Null
}

# Ensure Pending directory exists
if (-not (Test-Path $PendingDir)) {
    New-Item -ItemType Directory -Path $PendingDir | Out-Null
}

# Ensure Original directory exists
if (-not (Test-Path $OriginalDir)) {
    New-Item -ItemType Directory -Path $OriginalDir | Out-Null
}

# Ensure Logs directory exists
if (-not (Test-Path $LogsDir)) {
    New-Item -ItemType Directory -Path $LogsDir | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    
    # Write to console
    if ($Level -eq "ERROR") {
        Write-Host $LogEntry -ForegroundColor Red
    } elseif ($Level -eq "WARN") {
        Write-Host $LogEntry -ForegroundColor Yellow
    } else {
        Write-Host $LogEntry
    }
    
    # Write to file
    Add-Content -Path $LogFilePath -Value $LogEntry
}

Write-Log "Starting Image Geolocation Renaming Process."

# Check if ExifTool exists
if (-not (Test-Path $ExifToolPath)) {
    Write-Log "exiftool.exe not found in $ScriptDir. Please download it and place it in the folder." "ERROR"
    exit
}

# Get all common image formats in the current directory (excluding subdirectories)
$SupportedExtensions = @('.jpg', '.jpeg', '.png', '.heic')
$ImageFiles = Get-ChildItem -Path $PendingDir -File | Where-Object {
    $SupportedExtensions -contains $_.Extension.ToLower()
}

if ($ImageFiles.Count -eq 0) {
    Write-Log "No image files found in the directory." "WARN"
    exit
}

Write-Log "Found $($ImageFiles.Count) image(s) to process."

# OpenStreetMap Nominatim requires a valid User-Agent identifying the app/script.
$UserAgent = "WindowsImageRenamerScript/1.0"

foreach ($File in $ImageFiles) {
    # Copy to Original directory for backup
    Write-Log "Backing up '$($File.Name)' to Original directory."
    Copy-Item -Path $File.FullName -Destination $OriginalDir -Force

    # 1. Parse Original Timestamp from Filename
    # Expecting format like: YYYYMMDD_HHMISS.jpg
    $BaseName = $File.BaseName
    $Extension = $File.Extension
    
    # Simple regex to extract the date/time portion if it matches the pattern
    if ($BaseName -match "(\d{8}_\d{6})") {
        $OriginalTimestamp = $matches[1]
    } else {
        Write-Log "File '$($File.Name)' does not match expected filename pattern (YYYYMMDD_HHMISS). Using entire basename." "WARN"
        $OriginalTimestamp = $BaseName
    }
    
    # 2. Extracting GPS data using ExifTool
    # -n outputs numerical values (e.g., 40.7005 instead of 40 deg 42' 1.98")
    $ExifOutput = & $ExifToolPath -n -GPSLatitude -GPSLongitude $File.FullName
    
    $Latitude = $null
    $Longitude = $null
    
    foreach ($line in $ExifOutput) {
        if ($line -match "GPS Latitude\s+:\s+([-\d\.]+)") {
            $Latitude = $matches[1]
        }
        if ($line -match "GPS Longitude\s+:\s+([-\d\.]+)") {
            $Longitude = $matches[1]
        }
    }
    
    if ([string]::IsNullOrWhiteSpace($Latitude) -or [string]::IsNullOrWhiteSpace($Longitude)) {
        Write-Log "Skipping '$($File.Name)': No GPS coordinates found in metadata." "WARN"
        continue
    }
    
    Write-Log "Processing '$($File.Name)' - Lat: $Latitude, Lon: $Longitude"
    
    # 3. Querying the reverse geocoding API
    # Use OpenStreetMap's Nominatim API
    $ApiUrl = "https://nominatim.openstreetmap.org/reverse?format=json&lat=$Latitude&lon=$Longitude&zoom=10&addressdetails=1"
    
    try {
        $Response = Invoke-RestMethod -Uri $ApiUrl -Headers @{"User-Agent" = $UserAgent}
        
        $Address = $Response.address
        $State = $Address.state
        
        # Fallback logic for city name
        $City = $null
        if ($Address.city) { $City = $Address.city }
        elseif ($Address.town) { $City = $Address.town }
        elseif ($Address.village) { $City = $Address.village }
        elseif ($Address.municipality) { $City = $Address.municipality }
        elseif ($Address.county) { $City = $Address.county }
    
        if ([string]::IsNullOrWhiteSpace($State) -or [string]::IsNullOrWhiteSpace($City)) {
            Write-Log "Skipping '$($File.Name)': API returned incomplete location data (State: '$State', City: '$City')." "ERROR"
            continue
        }
    
        # 4. Constructing the new filename and moving the file
        # Format: "State--City--YYYYMMDD_HHMISS.extension"
        
        # Clean potential invalid characters from City/State names
        $InvalidChars = [System.IO.Path]::GetInvalidFileNameChars()
        $SafeState = $State -replace "[$InvalidChars]", "_"
        $SafeCity = $City -replace "[$InvalidChars]", "_"
        
        $NewFileName = "$SafeState--$SafeCity--$OriginalTimestamp$Extension"
        $NewFilePath = Join-Path $RenamedDir $NewFileName
        
        # Handle duplicate filenames in destination
        $Counter = 1
        $FinalNewFilePath = $NewFilePath
        $FinalNewFileName = $NewFileName
        
        while (Test-Path $FinalNewFilePath) {
            $FinalNewFileName = "$SafeState, $SafeCity - $OriginalTimestamp ($Counter)$Extension"
            $FinalNewFilePath = Join-Path $RenamedDir $FinalNewFileName
            $Counter++
        }
    
        # Move and Rename
        Move-Item -Path $File.FullName -Destination $FinalNewFilePath -ErrorAction Stop
        
        Write-Log "`"$($File.Name)`" --> `"$FinalNewFileName`""
    
    } catch {
        Write-Log "Failed to process '$($File.Name)': $($_.Exception.Message)" "ERROR"
    }
    
    # 5. Applying mandatory sleep to respect API limits
    # Nominatim Acceptable Use Policy requires a maximum of 1 request per second.
    Start-Sleep -Seconds 2 
}

Write-Log "Script execution finished."
