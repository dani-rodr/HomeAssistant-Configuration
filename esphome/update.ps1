param(
    [int]$Parallel = 1
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
$yamlFiles = Get-ChildItem -Path $PSScriptRoot -Filter *.yaml | Where-Object { $_.Name -notlike '*.base.yaml' }

if ($yamlFiles.Count -eq 0) {
    Write-Host "No YAML files found in $PSScriptRoot"
    exit 0
}

if ($Parallel -le 1) {
    # Sequential build (show live ESPHome logs)
    foreach ($file in $yamlFiles) {
        Write-Host "[$($file.Name)] compiling..."
        & $python -m esphome run $file.FullName --no-logs  # live logs printed here
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[$($file.Name)] ✅ done"
        }
        else {
            Write-Host "[$($file.Name)] ❌ failed (exit code $LASTEXITCODE)"
        }
    }
}
else {
    # Parallel build
    $jobs = @()
    foreach ($file in $yamlFiles) {
        Write-Host "[$($file.Name)] queued..."
        $jobs += Start-Job -ScriptBlock {
            param($python, $path)
            $name = [System.IO.Path]::GetFileName($path)
            Write-Output "[$name] compiling..."
            & $python -m esphome run $path --no-logs
            Write-Output "[$name] ✅ done"
        } -ArgumentList $python, $file.FullName

        if ($jobs.Count -ge $Parallel) {
            $jobs | Wait-Job | ForEach-Object { Receive-Job $_ }
            $jobs | Remove-Job
            $jobs = @()
        }
    }

    if ($jobs.Count -gt 0) {
        $jobs | Wait-Job | ForEach-Object { Receive-Job $_ }
        $jobs | Remove-Job
    }
}
