function Get-WindowsRegistryValue {
    param (
        [string]$Path,
        [string]$Name
    )
    try {
        $value = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        return $value
    } catch {
        Write-Error "Error retrieving registry value: $_"
    }
}
