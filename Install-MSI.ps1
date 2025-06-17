# Ensure TLS 1.2 is enabled
[Net.ServicePointManager]::SecurityProtocol = 3072

# Load Get-ApplicationInstallStatus function
$script = iwr 'https://raw.githubusercontent.com/wmmatt/public-powershell-functions/refs/heads/main/Get-InstalledApplication.ps1' -UseBasicParsing
iex $script.Content

function Install-MSIFromUrl {
    param (
        [Parameter(Mandatory)]
        [string]$Url,
        [string]$ExpectedHash,
        [string]$InstallArgs = "/qn /norestart",
        [int]$TimeoutMinutes = 5,
        [string]$AppName  # As it appears in Programs and Features
    )

    # Check if already installed
    if ($AppName) {
        Write-Host "Checking if $AppName is already installed..."
        if (Get-ApplicationInstallStatus -AppName $AppName) {
            Write-Host "$AppName is already installed. Skipping install."
            return $true
        }
    }

    # Create a temp path for the MSI
    $tempPath = Join-Path $env:TEMP ([System.IO.Path]::GetRandomFileName() + ".msi")

    try {
        # Download MSI file
        Write-Host "Downloading MSI from $Url..."
        Invoke-WebRequest -Uri $Url -OutFile $tempPath -UseBasicParsing -Headers @{ 'User-Agent' = 'Mozilla/5.0' }

        # Verify SHA256 hash if provided
        if ($ExpectedHash) {
            $actualHash = (Get-FileHash -Path $tempPath -Algorithm SHA256).Hash
            if ($actualHash.ToUpper() -ne $ExpectedHash.ToUpper()) {
                throw "Hash mismatch! Expected $ExpectedHash, got $actualHash"
            }
            Write-Host "Hash verified successfully."
        }

        # Wait for msiexec to be available
        $timeout = [datetime]::Now.AddMinutes($TimeoutMinutes)
        while ((Get-Process -Name "msiexec" -ErrorAction SilentlyContinue) -and [datetime]::Now -lt $timeout) {
            Write-Host "Waiting for msiexec to be free..."
            Start-Sleep -Seconds 5
        }

        if ([datetime]::Now -ge $timeout) {
            throw "Timed out waiting for Windows Installer to be ready."
        }

        # Run the MSI install
        Write-Host "Installing MSI..."
        $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$tempPath`" $InstallArgs" -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "MSI installation failed with exit code $($proc.ExitCode)"
        }

        # Confirm installation
        if ($AppName) {
            Write-Host "Verifying installation of $AppName..."
            if (-not (Get-ApplicationInstallStatus -AppName $AppName)) {
                throw "$AppName did not install successfully."
            }
            Write-Host "$AppName installed successfully."
        }

        # Clean up only after successful install
        if (Test-Path $tempPath) {
            Remove-Item $tempPath -Force
        }

        return $true

    } catch {
        Write-Error "Install failed: $_"
        return $false
    }
}
