# Examples
#     .\update.ps1 -StartFrom "kitchen-motion-sensor.yaml"
#     Compiles from "kitchen-motion-sensor.yaml" onward.

#     .\update.ps1 -File "smart-plug-2"
#     Compiles only the "smart-plug-2.yaml" file.

param(
    [string]$StartFrom = "",
    [string]$File = ""
)

# --- Resolve Python path explicitly ---
$python = (Get-Command python).Source

# --- Check and update ESPHome ---
$installedVersion = (& $python -m pip show esphome | Select-String "^Version:").ToString().Split(':')[1].Trim()
Write-Host "Installed ESPHome version: $installedVersion"

# Get latest version from PyPI
$latestVersion = Invoke-RestMethod -Uri "https://pypi.org/pypi/esphome/json" | Select-Object -ExpandProperty info | Select-Object -ExpandProperty version
Write-Host "Latest ESPHome version: $latestVersion"

if ($installedVersion -ne $latestVersion) {
    Write-Host "Updating ESPHome..."
    & $python -m pip install --upgrade esphome
}
else {
    Write-Host "ESPHome is up to date."
}

# --- Compile YAML files ---
# Use the esphome folder if your YAMLs are inside it
$yamlDir = "$PSScriptRoot"
Set-Location $yamlDir

$yamlFiles = Get-ChildItem -Path $yamlDir -Filter *.yaml |
Where-Object { $_.Name -notlike '*.base.yaml' -and $_.Name -ine 'secrets.yaml' }

if ($File -ne "") {
    # Compile a specific file only (case-insensitive, supports base name)
    $yamlFiles = $yamlFiles | Where-Object { $_.Name -ieq $File -or $_.BaseName -ieq $File }
}
elseif ($StartFrom -ne "") {
    # Compile from a specific file onward
    $found = $false
    $yamlFiles = $yamlFiles | Where-Object {
        if (-not $found -and ($_.Name -ieq $StartFrom -or $_.BaseName -ieq $StartFrom)) { $found = $true }
        $found
    }
}

if ($yamlFiles.Count -eq 0) {
    Write-Host "No YAML files found in $yamlDir"
    exit 0
}

Write-Host "Files to be compiled:"
$yamlFiles | ForEach-Object { Write-Host " - $($_)" }

# Initialize a list to store results
$results = @()

# Sequential build (show live ESPHome logs)
foreach ($file in $yamlFiles) {
    Write-Host "[$($file)] compiling..."

    # Build the command as an array of strings
    $cmd = @($python, "-m", "esphome", "run", $file, "--no-logs")

    # Call the command properly
    & $cmd[0] $cmd[1..($cmd.Count - 1)]

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[$file] done"
        $results += [PSCustomObject]@{
            File   = $file
            Status = "Success"
        }
    }
    else {
        Write-Host "[$file] failed (exit code $LASTEXITCODE)"
        Write-Host "Command that was run:"
        Write-Host "    $($cmd -join ' ')"
        $results += [PSCustomObject]@{
            File   = $file
            Status = "Failed (exit code $LASTEXITCODE)"
        }
    }
}

# --- Summary ---
Write-Host ""
Write-Host "Compilation Summary:"
$results | ForEach-Object {
    Write-Host " - $($_.File): $($_.Status)"
}