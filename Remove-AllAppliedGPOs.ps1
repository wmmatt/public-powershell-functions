function Remove-AllAppliedGPOs {
    <#
    .DESCRIPTION
        This function clears all locally applied Group Policy Objects (GPOs) by removing local policy files and registry entries.
        It creates a backup of current GPO settings before deletion.

    .WARNING
        This action is **irreversible** using this script alone. Ensure backups are stored correctly and test in a non-production environment.

    .OUTPUTS
        A success message confirming GPOs have been cleared.

    .EXAMPLE
        Remove-AllAppliedGPOs
        Clears all applied GPOs from the system and stores a backup before deletion.
    #>

    # Set date & time string for backup
    $dateString = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $backupPath = "$env:SystemDrive\GPO_Backups\$dateString"

    # Create backup directory
    New-Item -Path $backupPath -ItemType Directory -Force | Out-Null

    # Backup GroupPolicy folders
    Copy-Item -Path "$env:windir\System32\GroupPolicy" -Destination "$backupPath\GroupPolicy.bak" -Recurse -Force -ErrorAction Stop
    Copy-Item -Path "$env:windir\System32\GroupPolicyUsers" -Destination "$backupPath\GroupPolicyUsers.bak" -Recurse -Force -ErrorAction Stop

    # Remove the Group Policy folders
    Remove-Item -Path "$env:windir\System32\GroupPolicy" -Recurse -Force -ErrorAction Stop
    Remove-Item -Path "$env:windir\System32\GroupPolicyUsers" -Recurse -Force -ErrorAction Stop
    New-Item -Path "$env:windir\System32\GroupPolicy" -ItemType Directory -Force | Out-Null

    # Backup & Remove Computer Policies (Registry)
    reg export "HKLM\SOFTWARE\Policies" "$backupPath\Policies_Backup.reg" /y
    Remove-Item -Path "HKLM:\SOFTWARE\Policies" -Recurse -Force -ErrorAction Stop

    # Remove User-Based GPOs in Registry (Ensure User Hives Are Loaded)
    $UserProfiles = Get-WmiObject -Class Win32_UserProfile | Where-Object { $_.Special -eq $false }
    foreach ($profile in $UserProfiles) {
        $SID = $profile.SID
        $UserHive = "Registry::HKEY_USERS\$SID\SOFTWARE\Policies"
        
        if (Test-Path $UserHive) {
            reg export "HKEY_USERS\$SID\SOFTWARE\Policies" "$backupPath\Policies_Backup_$SID.reg" /y
            Remove-Item -Path $UserHive -Recurse -Force -ErrorAction Stop
        }
    }

    # Refresh policies (instead of gpupdate)
    secedit /refreshpolicy machine_policy /enforce

    Write-Output "All locally applied GPOs have been cleared. Backup stored at: $backupPath"
}
