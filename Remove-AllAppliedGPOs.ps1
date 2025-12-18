<#
.SYNOPSIS
    Removes all locally cached GPO settings from a Windows machine.

.DESCRIPTION
    Clears locally applied Group Policy by removing:
    - GroupPolicy and GroupPolicyUsers filesystem folders
    - HKLM:\SOFTWARE\Policies
    - HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies
    - Same paths under each user hive in HKU:\

    Creates timestamped backups before any deletions. Designed for RMM deployment
    to clean up stale GPO settings after policies are removed from domain controllers.

.NOTES
    Run as SYSTEM from RMM. Users in HKU are those currently logged in; offline
    profiles are not modified. A gpupdate /force is triggered at the end to
    reapply any still-enforced domain policies.
#>

#Requires -Version 5.1

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = switch ($Level) {
        'INFO'    { '[INFO]   ' }
        'WARN'    { '[WARN]   ' }
        'ERROR'   { '[ERROR]  ' }
        'SUCCESS' { '[OK]     ' }
    }
    Write-Output "$timestamp $prefix$Message"
}

function Remove-AllGPOSettings {
    
    $dateString = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
    $backupRoot = "$env:SystemDrive\GPO_Backups\$dateString"
    
    Write-Log "Starting GPO removal process"
    Write-Log "Backup location: $backupRoot"
    
    # Create backup directory - abort if this fails since we can't proceed safely
    try {
        New-Item -Path $backupRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Write-Log "Created backup directory" -Level SUCCESS
    }
    catch {
        Write-Log "Failed to create backup directory: $_" -Level ERROR
        Write-Log "Aborting - cannot proceed without backup location" -Level ERROR
        exit 1
    }

    # Filesystem policy folders to process
    $policyFolders = @(
        "$env:windir\System32\GroupPolicy",
        "$env:windir\System32\GroupPolicyUsers"
    )
    
    foreach ($folder in $policyFolders) {
        $folderName = Split-Path $folder -Leaf
        
        if (Test-Path $folder) {
            # Backup first
            try {
                Copy-Item -Path $folder -Destination "$backupRoot\$folderName.bak" -Recurse -Force -ErrorAction Stop
                Write-Log "Backed up $folderName" -Level SUCCESS
            }
            catch {
                Write-Log "Failed to backup $folderName`: $_" -Level ERROR
                Write-Log "Aborting - backup failed" -Level ERROR
                exit 1
            }
            
            # Then remove
            try {
                Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
                Write-Log "Removed $folderName" -Level SUCCESS
            }
            catch {
                Write-Log "Failed to remove $folderName`: $_" -Level ERROR
            }
        }
        else {
            Write-Log "$folderName does not exist, skipping" -Level INFO
        }
        
        # Recreate empty folder - Windows expects these to exist
        if (-not (Test-Path $folder)) {
            try {
                New-Item -Path $folder -ItemType Directory -Force -ErrorAction Stop | Out-Null
                Write-Log "Recreated empty $folderName" -Level SUCCESS
            }
            catch {
                Write-Log "Failed to recreate $folderName`: $_" -Level WARN
            }
        }
    }

    # Machine policy registry keys - these are the two locations where GPO writes machine settings
    $machinePolicyPaths = @(
        @{ RegPath = 'HKLM\SOFTWARE\Policies'; PSPath = 'HKLM:\SOFTWARE\Policies' },
        @{ RegPath = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies'; PSPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies' }
    )
    
    Write-Log "Processing machine policy registry keys..."
    
    foreach ($policy in $machinePolicyPaths) {
        $keyName = $policy.RegPath -replace '\\', '_'
        
        if (Test-Path $policy.PSPath) {
            # Backup using reg.exe - handles export better than PowerShell
            $exportPath = "$backupRoot\$keyName.reg"
            $regResult = reg export $policy.RegPath $exportPath /y 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Backed up $($policy.RegPath)" -Level SUCCESS
            }
            else {
                Write-Log "Failed to backup $($policy.RegPath): $regResult" -Level ERROR
                Write-Log "Aborting - registry backup failed" -Level ERROR
                exit 1
            }
            
            # Remove the key
            try {
                Remove-Item -Path $policy.PSPath -Recurse -Force -ErrorAction Stop
                Write-Log "Removed $($policy.RegPath)" -Level SUCCESS
            }
            catch {
                Write-Log "Failed to remove $($policy.RegPath): $_" -Level ERROR
            }
        }
        else {
            Write-Log "$($policy.RegPath) does not exist, skipping" -Level INFO
        }
    }

    # User policy registry keys - only processes logged-in users since their hives are loaded in HKU
    Write-Log "Processing user policy registry keys..."
    
    $userProfiles = Get-CimInstance -ClassName Win32_UserProfile | Where-Object { $_.Special -eq $false }
    
    if ($userProfiles.Count -eq 0) {
        Write-Log "No user profiles found in HKU (no users logged in)" -Level WARN
    }
    
    foreach ($profile in $userProfiles) {
        $sid = $profile.SID
        $profilePath = $profile.LocalPath
        $userName = Split-Path $profilePath -Leaf
        
        Write-Log "Processing user: $userName ($sid)"
        
        # Check if this user's hive is actually loaded
        if (-not (Test-Path "Registry::HKEY_USERS\$sid")) {
            Write-Log "  Hive not loaded for $userName, skipping" -Level INFO
            continue
        }
        
        # User policy paths mirror the machine paths
        $userPolicyPaths = @(
            @{ RegPath = "HKU\$sid\SOFTWARE\Policies"; PSPath = "Registry::HKEY_USERS\$sid\SOFTWARE\Policies" },
            @{ RegPath = "HKU\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies"; PSPath = "Registry::HKEY_USERS\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies" }
        )
        
        foreach ($policy in $userPolicyPaths) {
            $keyName = "User_$($userName)_$($policy.RegPath -replace '\\', '_' -replace "HKU_$sid_", '')"
            
            if (Test-Path $policy.PSPath) {
                # Backup
                $exportPath = "$backupRoot\$keyName.reg"
                $regPathForExport = $policy.RegPath -replace '^HKU\\', 'HKEY_USERS\'
                $regResult = reg export $regPathForExport $exportPath /y 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "  Backed up $($policy.RegPath)" -Level SUCCESS
                }
                else {
                    Write-Log "  Failed to backup $($policy.RegPath): $regResult" -Level WARN
                }
                
                # Remove
                try {
                    Remove-Item -Path $policy.PSPath -Recurse -Force -ErrorAction Stop
                    Write-Log "  Removed $($policy.RegPath)" -Level SUCCESS
                }
                catch {
                    Write-Log "  Failed to remove $($policy.RegPath): $_" -Level ERROR
                }
            }
            else {
                Write-Log "  $($policy.RegPath) does not exist, skipping" -Level INFO
            }
        }
    }

    # Trigger gpupdate to reapply any policies still enforced by the domain
    Write-Log "Triggering gpupdate to reapply any enforced domain policies..."
    
    try {
        $gpResult = gpupdate /force 2>&1
        Write-Log "gpupdate completed" -Level SUCCESS
    }
    catch {
        Write-Log "gpupdate failed: $_" -Level WARN
    }

    # Done
    Write-Log "GPO removal complete"
    Write-Log "Backups stored at: $backupRoot"
    Write-Log "Note: Domain-enforced policies will reapply on next gpupdate cycle"
    Write-Log "Note: User policies for logged-out users were not modified"
}
