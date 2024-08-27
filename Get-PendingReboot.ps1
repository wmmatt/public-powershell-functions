function Get-PendingReboot {
    <#
    .DESCRIPTION
        Checks multiple registry locations for signs of a pending reboot and aggregates any findings.
    .OUTPUTS
        Returns an object with the following keys:
        - HasPendingReboots (bool): Indicates if any pending reboots were detected.
        - Entries (array): Contains details (path, name, value) for each detected pending reboot.
        - Output (string): A list of registry paths where pending reboots were found.
    #>

    $out = @()
    $entries = @()

    # Define registry keys and values to check
    $keys = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Updates'; Name = 'UpdateExeVolatile'; ValueCheck = '1' },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'; Name = 'PendingFileRenameOperations' },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'; Name = 'PendingFileRenameOperations2' },
        @{ Path = 'HKLM:\SYSTEM\CurrentSet001\Control\Session'; Name = 'Manager' },
        @{ Path = 'HKLM:\SYSTEM\CurrentSet002\Control\Session'; Name = 'Manager' },
        @{ Path = 'HKLM:\SYSTEM\CurrentSet003\Control\Session'; Name = 'Manager' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update'; Name = 'RebootRequired' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Services'; Name = 'Pending' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'; Name = 'Mandatory' },
        @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing'; Name = 'PackagesPending' },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon'; Name = 'JoinDomain' },
        @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon'; Name = 'AvoidSpnSet' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update'; Name = 'PostRebootReporting' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; Name = 'DVDRebootSignal' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing'; Name = 'RebootPending' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing'; Name = 'RebootInProgress' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\ServerManager'; Name = 'CurrentRebootAttempts' }
    )

    # Iterate over each key-value pair to check for pending reboot indicators
    $keys | ForEach-Object {
        $path = $_.Path
        $name = $_.Name
        $fullPath = "$path\$name"

        # Attempt to retrieve the registry value
        $value = $null
        try {
            $value = Get-ItemPropertyValue -Path $path -Name $name -ErrorAction Stop
        } Catch {
            # If the key does not exist, move to the next item
            return
        }

        # Check if the value meets the required condition (if any)
        If ($_.ValueCheck -and ($value -ne $_.ValueCheck)) {
            return
        }

        # Add the detected pending reboot information to the output arrays
        $out += "Reboot pending at $fullPath"

        $entries += @{
            Path = $path
            Name = $name
            Value = $value
        }
    }

    # Return a summary object with the results
    Return @{
        Entries = $entries
        HasPendingReboots = $entries.Length -gt 0
        Output = ($out -join "`n")
    }
}
