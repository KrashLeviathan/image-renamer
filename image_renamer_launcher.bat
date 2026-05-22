:: ============================================================================
:: Image Geolocation Renamer - Launcher
::
:: INSTRUCTIONS:
:: 1. Place this .bat file and 'rename_logic.ps1' in the folder with your images.
:: 2. Download exiftool (Windows Executable) from https://exiftool.org/
:: 3. Rename the downloaded 'exiftool(-k).exe' to exactly 'exiftool.exe'.
:: 4. Place 'exiftool.exe' in the same folder as these scripts.
:: 5. Double-click this .bat file to run the script.
:: ============================================================================
@echo off
echo Launching Image Geolocation Renamer...
echo Bypassing execution policy for this session only...

:: Run the PowerShell script located in the same directory as this batch file
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0rename_logic.ps1"

echo.
echo Process complete.
pause