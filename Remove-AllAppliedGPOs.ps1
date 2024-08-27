function Remove-AllAppliedGPOs {
    <#
    .DESCRIPTION
        This function clears all Group Policy Objects (GPOs) by removing the contents of specific directories and registry keys. 
        It also creates a backup of the current GPO settings with a timestamp before clearing them.

    .WARNING
        This operation is irreversible through this script. Make sure to review the necessity and impact of this action before proceeding.
        It is recommended to test in a controlled environment before applying to production systems.

    .OUTPUTS
        Outputs a status message indicating the success or failure of the operation.

    .EXAMPLE
        Remove-AllAppliedGPOs
        This command clears all the GPOs from the system and backs up the existing policies before deletion.
    #>

    # Set date & time string for backup files
    $dateString = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")

    try {
        # Backup the contents of GPO folders in the Windows directory
        $gpUserBackup = "GroupPolicyUsers.bak.$dateString"
        $gpBackup = "GroupPolicy.bak.$dateString"

        Copy-Item -Path "$env:windir\System32\GroupPolicyUsers" -Destination $gpUserBackup -Recurse -Force -ErrorAction Stop
        Copy-Item -Path "$env:windir\System32\GroupPolicy" -Destination $gpBackup -Recurse -Force -ErrorAction Stop

        # Remove the contents of GPO folders
        Remove-Item "$env:windir\System32\GroupPolicyUsers\*" -Recurse -Force -ErrorAction Stop
        Remove-Item "$env:windir\System32\GroupPolicy\*" -Recurse -Force -ErrorAction Stop

        # Backup and delete Computer level GPO configurations in the registry
        $policyBackupPath = "HKLM:\SOFTWARE\Policies.bak.$dateString"
        Rename-Item -Path "HKLM:\SOFTWARE\Policies" -NewName $policyBackupPath -Force -ErrorAction Stop

        # Delete user-based GPOs under HKEY_CURRENT_USER for each user
        $UserProfiles = Get-WmiObject -Class Win32_UserProfile | Where-Object { $_.Special -eq $false }
        $UserProfiles | ForEach-Object {
            $SID = $_.SID
            $UserHive = "Registry::HKEY_USERS\$SID\SOFTWARE\Policies"

            if (Test-Path $UserHive) {
                Remove-Item -Path $UserHive -Recurse -Force -ErrorAction Stop
            }
        }

        # Force Group Policy update to apply changes
        gpupdate /force

        Write-Output "All GPOs have been cleared and backed up successfully."

    } catch {
        Write-Error "An error occurred during the operation: $_"
    }
}
