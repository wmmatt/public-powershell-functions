function Confirm-RegistryValue {
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
                New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
                Set-ItemProperty -Path $Path -Name $Name -Value $Value | Out-Null
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
