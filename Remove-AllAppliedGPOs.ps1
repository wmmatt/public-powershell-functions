<#
.SYNOPSIS
    Removes all locally cached GPO and Intune/MDM policy settings from a Windows machine.

.DESCRIPTION
    Clears locally applied Group Policy and MDM policies by removing:
    
    GPO Locations:
    - GroupPolicy and GroupPolicyUsers filesystem folders
    - HKLM:\SOFTWARE\Policies
    - HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies
    - Same paths under each user hive in HKU:\
    - Group Policy history and RSoP cache
    
    MDM/Intune Locations:
    - HKLM:\SOFTWARE\Microsoft\PolicyManager
    - HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension
    - HKLM:\SOFTWARE\Microsoft\Enrollments (policy data, not enrollment itself)
    - C:\ProgramData\Microsoft\IntuneManagementExtension
    
    Creates timestamped backups before any deletions. Designed for RMM deployment
    to clean up stale policy settings after policies are removed from management platforms.

.PARAMETER SkipGPUpdate
    If specified, skips the gpupdate /force at the end. Useful when you want
    a clean slate without immediately reapplying domain policies.

.PARAMETER UnenrollMDM
    If specified, unenrolls the device from MDM/Intune before clearing policies.
    WARNING: This removes the device from Intune management entirely.

.PARAMETER WhatIf
    Shows what would be removed without actually removing anything.

.NOTES
    Run as SYSTEM from RMM. Users in HKU are those currently logged in; offline
    profiles are not modified.
    
    IMPORTANT: Removing policies does NOT revert settings to defaults. It only
    removes enforcement. Settings remain at their policy-configured values until
    manually changed or a new policy is applied.
#>

#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$SkipGPUpdate,
    [switch]$UnenrollMDM
)

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

function Backup-RegistryKey {
    param(
        [string]$RegPath,
        [string]$BackupRoot,
        [string]$KeyName
    )
    
    $exportPath = "$BackupRoot\$KeyName.reg"
    $regResult = reg export $RegPath $exportPath /y 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Backed up $RegPath" -Level SUCCESS
        return $true
    }
    else {
        Write-Log "Failed to backup $RegPath : $regResult" -Level ERROR
        return $false
    }
}

function Remove-PolicyRegistryKey {
    param(
        [string]$PSPath,
        [string]$DisplayName,
        [bool]$AbortOnBackupFailure = $true,
        [string]$BackupRoot,
        [string]$RegPath
    )
    
    if (-not (Test-Path $PSPath)) {
        Write-Log "$DisplayName does not exist, skipping" -Level INFO
        return $true
    }
    
    # Backup first
    $keyName = $RegPath -replace '\\', '_' -replace ':', ''
    if (-not (Backup-RegistryKey -RegPath $RegPath -BackupRoot $BackupRoot -KeyName $keyName)) {
        if ($AbortOnBackupFailure) {
            Write-Log "Aborting - registry backup failed for $DisplayName" -Level ERROR
            return $false
        }
    }
    
    # Remove
    if ($PSCmdlet.ShouldProcess($DisplayName, "Remove registry key")) {
        try {
            Remove-Item -Path $PSPath -Recurse -Force -ErrorAction Stop
            Write-Log "Removed $DisplayName" -Level SUCCESS
        }
        catch {
            Write-Log "Failed to remove $DisplayName : $_" -Level ERROR
        }
    }
    
    return $true
}

function Remove-AllGPOAndMDMSettings {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    
    $dateString = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
    $backupRoot = "$env:SystemDrive\Policy_Backups\$dateString"
    
    Write-Log "=========================================="
    Write-Log "Starting Policy Removal Process"
    Write-Log "=========================================="
    Write-Log "Backup location: $backupRoot"
    Write-Log "Skip GPUpdate: $SkipGPUpdate"
    Write-Log "Unenroll MDM: $UnenrollMDM"
    Write-Log "WhatIf Mode: $WhatIfPreference"
    Write-Log ""
    
    # Create backup directory
    if ($PSCmdlet.ShouldProcess($backupRoot, "Create backup directory")) {
        try {
            New-Item -Path $backupRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
            Write-Log "Created backup directory" -Level SUCCESS
        }
        catch {
            Write-Log "Failed to create backup directory: $_" -Level ERROR
            Write-Log "Aborting - cannot proceed without backup location" -Level ERROR
            return
        }
    }

    #region MDM Unenrollment
    if ($UnenrollMDM) {
        Write-Log ""
        Write-Log "=========================================="
        Write-Log "MDM Unenrollment"
        Write-Log "=========================================="
        
        # Find MDM enrollments
        $enrollmentsPath = "HKLM:\SOFTWARE\Microsoft\Enrollments"
        if (Test-Path $enrollmentsPath) {
            $enrollments = Get-ChildItem -Path $enrollmentsPath -ErrorAction SilentlyContinue | 
                Where-Object { $_.PSChildName -match '^[{]?[0-9a-fA-F-]+[}]?$' }
            
            foreach ($enrollment in $enrollments) {
                $enrollmentId = $enrollment.PSChildName
                $providerID = (Get-ItemProperty -Path $enrollment.PSPath -Name "ProviderID" -ErrorAction SilentlyContinue).ProviderID
                
                Write-Log "Found enrollment: $enrollmentId (Provider: $providerID)"
                
                if ($PSCmdlet.ShouldProcess("MDM Enrollment $enrollmentId", "Unenroll device")) {
                    try {
                        # Use the built-in MDM unenrollment
                        $enrollmentPath = "HKLM:\SOFTWARE\Microsoft\Enrollments\$enrollmentId"
                        $upn = (Get-ItemProperty -Path $enrollmentPath -Name "UPN" -ErrorAction SilentlyContinue).UPN
                        
                        # Trigger unenrollment via scheduled task (the supported method)
                        $taskExists = Get-ScheduledTask -TaskName "PushLaunch" -TaskPath "\Microsoft\Windows\DeviceManagement\*" -ErrorAction SilentlyContinue
                        
                        if ($providerID -eq "MS DM Server") {
                            # Intune enrollment - use dsregcmd for Azure AD joined devices
                            Write-Log "Attempting MDM unenrollment..." -Level INFO
                            
                            # Check if Azure AD joined
                            $dsregStatus = dsregcmd /status 2>&1
                            $isAADJoined = $dsregStatus -match "AzureAdJoined\s*:\s*YES"
                            
                            if ($isAADJoined) {
                                Write-Log "Device is Azure AD joined - using dsregcmd /leave" -Level INFO
                                $result = Start-Process -FilePath "dsregcmd.exe" -ArgumentList "/leave" -Wait -PassThru -NoNewWindow
                                if ($result.ExitCode -eq 0) {
                                    Write-Log "MDM unenrollment initiated successfully" -Level SUCCESS
                                }
                                else {
                                    Write-Log "dsregcmd /leave returned exit code: $($result.ExitCode)" -Level WARN
                                }
                            }
                            else {
                                # For non-AAD joined but MDM enrolled, remove enrollment directly
                                Write-Log "Device not Azure AD joined - removing enrollment registry keys" -Level INFO
                            }
                        }
                    }
                    catch {
                        Write-Log "MDM unenrollment failed: $_" -Level ERROR
                    }
                }
            }
        }
        else {
            Write-Log "No MDM enrollments found" -Level INFO
        }
        
        # Give unenrollment time to process
        Write-Log "Waiting 10 seconds for unenrollment to process..."
        Start-Sleep -Seconds 10
    }
    #endregion

    #region Filesystem Policy Folders (GPO)
    Write-Log ""
    Write-Log "=========================================="
    Write-Log "GPO Filesystem Folders"
    Write-Log "=========================================="
    
    $policyFolders = @(
        "$env:windir\System32\GroupPolicy",
        "$env:windir\System32\GroupPolicyUsers"
    )
    
    foreach ($folder in $policyFolders) {
        $folderName = Split-Path $folder -Leaf
        
        if (Test-Path $folder) {
            # Backup first
            if ($PSCmdlet.ShouldProcess($folder, "Backup folder")) {
                try {
                    Copy-Item -Path $folder -Destination "$backupRoot\$folderName.bak" -Recurse -Force -ErrorAction Stop
                    Write-Log "Backed up $folderName" -Level SUCCESS
                }
                catch {
                    Write-Log "Failed to backup $folderName : $_" -Level ERROR
                    Write-Log "Aborting - backup failed" -Level ERROR
                    return
                }
            }
            
            # Remove
            if ($PSCmdlet.ShouldProcess($folder, "Remove folder")) {
                try {
                    Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
                    Write-Log "Removed $folderName" -Level SUCCESS
                }
                catch {
                    Write-Log "Failed to remove $folderName : $_" -Level ERROR
                }
            }
        }
        else {
            Write-Log "$folderName does not exist, skipping" -Level INFO
        }
        
        # Recreate empty folder
        if ($PSCmdlet.ShouldProcess($folder, "Recreate empty folder")) {
            if (-not (Test-Path $folder)) {
                try {
                    New-Item -Path $folder -ItemType Directory -Force -ErrorAction Stop | Out-Null
                    Write-Log "Recreated empty $folderName" -Level SUCCESS
                }
                catch {
                    Write-Log "Failed to recreate $folderName : $_" -Level WARN
                }
            }
        }
    }
    #endregion

    #region MDM/Intune Filesystem
    Write-Log ""
    Write-Log "=========================================="
    Write-Log "MDM/Intune Filesystem Folders"
    Write-Log "=========================================="
    
    $mdmFolders = @(
        "$env:ProgramData\Microsoft\IntuneManagementExtension",
        "$env:windir\System32\config\systemprofile\AppData\Local\mdm"
    )
    
    foreach ($folder in $mdmFolders) {
        $folderName = $folder -replace '[:\\]', '_'
        
        if (Test-Path $folder) {
            # Backup
            if ($PSCmdlet.ShouldProcess($folder, "Backup MDM folder")) {
                try {
                    Copy-Item -Path $folder -Destination "$backupRoot\MDM_$folderName.bak" -Recurse -Force -ErrorAction Stop
                    Write-Log "Backed up $folder" -Level SUCCESS
                }
                catch {
                    Write-Log "Failed to backup $folder : $_" -Level WARN
                    # Don't abort for MDM folders - less critical
                }
            }
            
            # Remove
            if ($PSCmdlet.ShouldProcess($folder, "Remove MDM folder")) {
                try {
                    Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
                    Write-Log "Removed $folder" -Level SUCCESS
                }
                catch {
                    Write-Log "Failed to remove $folder : $_" -Level ERROR
                }
            }
        }
        else {
            Write-Log "$folder does not exist, skipping" -Level INFO
        }
    }
    #endregion

    #region Machine Policy Registry Keys (GPO)
    Write-Log ""
    Write-Log "=========================================="
    Write-Log "GPO Machine Registry Keys"
    Write-Log "=========================================="
    
    $machinePolicyPaths = @(
        @{ RegPath = 'HKLM\SOFTWARE\Policies'; PSPath = 'HKLM:\SOFTWARE\Policies' },
        @{ RegPath = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies'; PSPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies' }
    )
    
    foreach ($policy in $machinePolicyPaths) {
        $result = Remove-PolicyRegistryKey -PSPath $policy.PSPath -DisplayName $policy.RegPath `
            -BackupRoot $backupRoot -RegPath $policy.RegPath -AbortOnBackupFailure $true
        if (-not $result) { return }
    }
    #endregion

    #region MDM/Intune Registry Keys
    Write-Log ""
    Write-Log "=========================================="
    Write-Log "MDM/Intune Registry Keys"
    Write-Log "=========================================="
    
    $mdmRegistryPaths = @(
        @{ RegPath = 'HKLM\SOFTWARE\Microsoft\PolicyManager'; PSPath = 'HKLM:\SOFTWARE\Microsoft\PolicyManager' },
        @{ RegPath = 'HKLM\SOFTWARE\Microsoft\IntuneManagementExtension'; PSPath = 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension' },
        # Note: We don't delete the Enrollments key itself if not unenrolling, just the policy subkeys
        @{ RegPath = 'HKLM\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts'; PSPath = 'HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts' }
    )
    
    foreach ($policy in $mdmRegistryPaths) {
        # MDM paths use non-aborting backup failure since these may not exist on non-Intune machines
        $null = Remove-PolicyRegistryKey -PSPath $policy.PSPath -DisplayName $policy.RegPath `
            -BackupRoot $backupRoot -RegPath $policy.RegPath -AbortOnBackupFailure $false
    }
    
    # Handle Enrollments subkeys (policy data under each enrollment GUID)
    if (-not $UnenrollMDM) {
        $enrollmentsPath = "HKLM:\SOFTWARE\Microsoft\Enrollments"
        if (Test-Path $enrollmentsPath) {
            $enrollments = Get-ChildItem -Path $enrollmentsPath -ErrorAction SilentlyContinue | 
                Where-Object { $_.PSChildName -match '^[{]?[0-9a-fA-F-]+[}]?$' }
            
            foreach ($enrollment in $enrollments) {
                $policySubkeys = @("DMClient", "PolicyManager", "FirstSync")
                foreach ($subkey in $policySubkeys) {
                    $subkeyPath = Join-Path $enrollment.PSPath $subkey
                    if (Test-Path $subkeyPath) {
                        $regPath = "HKLM\SOFTWARE\Microsoft\Enrollments\$($enrollment.PSChildName)\$subkey"
                        $null = Remove-PolicyRegistryKey -PSPath $subkeyPath -DisplayName $regPath `
                            -BackupRoot $backupRoot -RegPath $regPath -AbortOnBackupFailure $false
                    }
                }
            }
        }
    }
    #endregion

    #region GP History and RSoP Cache
    Write-Log ""
    Write-Log "=========================================="
    Write-Log "GP History and RSoP Cache"
    Write-Log "=========================================="
    
    $historyPaths = @(
        @{ RegPath = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\History'; PSPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\History' },
        @{ RegPath = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State'; PSPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State' },
        @{ RegPath = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\Scripts'; PSPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\Scripts' }
    )
    
    foreach ($policy in $historyPaths) {
        $null = Remove-PolicyRegistryKey -PSPath $policy.PSPath -DisplayName $policy.RegPath `
            -BackupRoot $backupRoot -RegPath $policy.RegPath -AbortOnBackupFailure $false
    }
    
    # Clear RSoP WMI data
    if ($PSCmdlet.ShouldProcess("RSoP WMI Namespace", "Clear RSoP data")) {
        Write-Log "Clearing RSoP WMI data..."
        try {
            # The RSoP data regenerates on next gpupdate, so we just need to trigger a refresh
            $null = Get-CimInstance -Namespace "root\rsop\computer" -ClassName "__Namespace" -ErrorAction SilentlyContinue | 
                Remove-CimInstance -ErrorAction SilentlyContinue
            Write-Log "RSoP WMI data cleared" -Level SUCCESS
        }
        catch {
            Write-Log "Could not clear RSoP WMI data (may require reboot): $_" -Level WARN
        }
    }
    #endregion

    #region User Policy Registry Keys
    Write-Log ""
    Write-Log "=========================================="
    Write-Log "User Policy Registry Keys"
    Write-Log "=========================================="
    
    $userProfiles = Get-CimInstance -ClassName Win32_UserProfile | Where-Object { $_.Special -eq $false }
    
    if ($userProfiles.Count -eq 0) {
        Write-Log "No user profiles found in HKU (no users logged in)" -Level WARN
    }
    
    foreach ($profile in $userProfiles) {
        $sid = $profile.SID
        $profilePath = $profile.LocalPath
        $userName = Split-Path $profilePath -Leaf
        
        # Check if hive is loaded
        if (-not (Test-Path "Registry::HKEY_USERS\$sid")) {
            Write-Log "Hive not loaded for $userName, skipping" -Level INFO
            continue
        }
        
        Write-Log "Processing user: $userName ($sid)"
        
        # GPO user policy paths
        $userPolicyPaths = @(
            @{ RegPath = "HKU\$sid\SOFTWARE\Policies"; PSPath = "Registry::HKEY_USERS\$sid\SOFTWARE\Policies" },
            @{ RegPath = "HKU\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies"; PSPath = "Registry::HKEY_USERS\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies" },
            @{ RegPath = "HKU\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy"; PSPath = "Registry::HKEY_USERS\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy" }
        )
        
        foreach ($policy in $userPolicyPaths) {
            if (Test-Path $policy.PSPath) {
                $keyName = "User_${userName}_$($policy.RegPath -replace '\\', '_' -replace "HKU_${sid}_", '')"
                $regPathForExport = $policy.RegPath -replace '^HKU\\', 'HKEY_USERS\'
                
                # Backup
                if ($PSCmdlet.ShouldProcess($policy.RegPath, "Backup user registry key")) {
                    $exportPath = "$backupRoot\$keyName.reg"
                    $regResult = reg export $regPathForExport $exportPath /y 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "  Backed up $($policy.RegPath)" -Level SUCCESS
                    }
                    else {
                        Write-Log "  Failed to backup $($policy.RegPath): $regResult" -Level WARN
                    }
                }
                
                # Remove
                if ($PSCmdlet.ShouldProcess($policy.RegPath, "Remove user registry key")) {
                    try {
                        Remove-Item -Path $policy.PSPath -Recurse -Force -ErrorAction Stop
                        Write-Log "  Removed $($policy.RegPath)" -Level SUCCESS
                    }
                    catch {
                        Write-Log "  Failed to remove $($policy.RegPath): $_" -Level ERROR
                    }
                }
            }
            else {
                Write-Log "  $($policy.RegPath) does not exist, skipping" -Level INFO
            }
        }
    }
    #endregion

    #region GPUpdate
    if (-not $SkipGPUpdate) {
        Write-Log ""
        Write-Log "=========================================="
        Write-Log "Triggering GPUpdate"
        Write-Log "=========================================="
        
        if ($PSCmdlet.ShouldProcess("Group Policy", "Force update")) {
            try {
                $gpResult = gpupdate /force 2>&1
                Write-Log "gpupdate completed" -Level SUCCESS
            }
            catch {
                Write-Log "gpupdate failed: $_" -Level WARN
            }
        }
    }
    else {
        Write-Log ""
        Write-Log "Skipping gpupdate as requested" -Level INFO
    }
    #endregion

    #region Summary
    Write-Log ""
    Write-Log "=========================================="
    Write-Log "Summary"
    Write-Log "=========================================="
    Write-Log "Policy removal complete" -Level SUCCESS
    Write-Log "Backups stored at: $backupRoot"
    Write-Log ""
    Write-Log "IMPORTANT NOTES:" -Level WARN
    Write-Log "  - Removing policies does NOT revert settings to defaults"
    Write-Log "  - Settings remain at their policy-configured values"
    Write-Log "  - Only the enforcement/lock is removed"
    Write-Log "  - Domain/Intune policies will reapply if device is still managed"
    Write-Log "  - User policies for logged-out users were not modified"
    Write-Log "  - A reboot may be required for some changes to take effect"
    #endregion
}

# Execute
Remove-AllGPOAndMDMSettings

