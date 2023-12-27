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
        [string]$Path,
        [string]$Name,
        [int]$Value,
        [string]$Method
    )
    try {
        $currentValue = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
    } catch {
        if ($method -eq 'set') {
            try {
                New-Item -Path $Path -Force -ErrorAction Stop
                Set-ItemProperty -Path $Path -Name $Name -Value $Value
                return $true
            } catch {
                Write-Error "Error creating registry path and setting value: $_"
                return $false
            }
        } elseif($method -eq 'test') {
            return $false
        } else {
            Write-Error '$method was not defined!'
            return $false
        }
    }
    
    if ($currentValue.$Name -eq $Value) {
        return $true
    } else {
        if ($Method -eq 'set') {
            try {
                Set-ItemProperty -Path $Path -Name $Name -Value $Value
                return $true
            } catch {
                Write-Error "Error setting registry value: $_"
                return $false
            }
        }
        return $false
    }
}
