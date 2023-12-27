function Confirm-RegistryValue {
    <#
        .DESCRIPTION
        Checks for a specific value of the key/name you specify and returns $true if the value matches, or $false if the value does not match.

        .EXAMPLE
        PS> Confirm-RegistryValue -Path 'HKLM:\\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' -Name 'UseLogonCredential' -Value 0 -Method test
        True

        PS> Confirm-RegistryValue -Path 'HKLM:\\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' -Name 'UseLogonCredential' -Value 1 -Method test
        False

        PS> Confirm-RegistryValue -Path 'HKLM:\\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' -Name 'UseLogonCredential' -Value 1 -Method set
        True
    #>

    param (
        [string]$Path,     # Registry path to check
        [string]$Name,     # Registry key name to check
        [int]$Value,       # The value to compare against or set
        [string]$Method    # Operation mode: 'test' or 'set'
    )
    
    try {
        # Attempt to get the current registry value
        $currentValue = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
    } catch {
        # If the registry path/key does not exist
        if ($method -eq 'set') {
            # If in 'set' mode, try to create the path and set the value
            try {
                New-Item -Path $Path -Force -ErrorAction Stop
                Set-ItemProperty -Path $Path -Name $Name -Value $Value
                return $true
            } catch {
                # If creating the path or setting the value fails, return error
                Write-Error "Error creating registry path and setting value: $_"
                return $false
            }
        } else {
            # Return $false if $method is not 'set'
            return $false
        }
    }
    
    # Check if the current registry value matches the expected value
    if ($currentValue.$Name -eq $Value) {
        return $true
    } else {
        # If values do not match and method is 'set'
        if ($Method -eq 'set') {
            try {
                # Attempt to set the registry value
                Set-ItemProperty -Path $Path -Name $Name -Value $Value
                return $true
            } catch {
                # Return error if setting the value fails
                Write-Error "Error setting registry value: $_"
                return $false
            }
        }
        # Return $false if values do not match and method is not 'set'
        return $false
    }
}
