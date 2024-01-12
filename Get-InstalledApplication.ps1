Function Get-ApplicationInstallStatus {
    <#
    .SYNOPSIS
    Get-ApplicationInstallStatus

    .DESCRIPTION
    By default, this will search both the system (all users) and user install paths to verify an application
    is installed. RMMs (at the time of this writing) do not report user only installed applications, so this
    is handy to find those user installed applications!

    .PARAMETER AppName
    Use the name of the application exactly as seen in add/remove programs inside of single quotes

    .PARAMETER SystemInstallsOnly
    This is the equivalent of only applications that were installed for "all users" or "everyone" at install

    .PARAMETER UserInstallsOnly
    Many modern applications install directly to the user registry hive. Without defining this param, it will
    not be obvious if the application was found to be installed at the system level, or the user level. Use
    this parameter if you need to determine if an app is installed for this user only.

    .EXAMPLE
    C:\PS> Get-InstalledApp -ApplicationName 'Google Chrome'
    C:\PS> Get-InstalledApp -ApplicationName 'Google Chrome' -SystemInstallOnly $true
    C:\PS> Get-InstalledApp -ApplicationName 'Microsoft Teams' -UserInstallsOnly $true
    #>


    [CmdletBinding()]

    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [Parameter(Mandatory = $false)]
        [boolean]$SystemInstallsOnly,
        [Parameter(Mandatory = $false)]
        [boolean]$UserInstallsOnly
    )

    $installed = @()

    if (!$UserInstallsOnly) {
        $installed += New-Object psobject -prop @{
            sys32 = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName -eq $AppName }
            sys64 = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName -eq $AppName }
        }
    }

    if (!$SystemInstallsOnly) {
        New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS | Out-Null
        $installed += New-Object psobject -prop @{
            user32 = Get-ItemProperty "HKU:\*\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName -eq $AppName }
            user64 = Get-ItemProperty "HKU:\*\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName -eq $AppName }
        }
    }
        

    # any of these are true then we know the app was found to be installed, so output $true
    if ($installed.sys32 -or $installed.sys64 -or $installed.user32 -or $installed.user64) {
        return $true
    } else {
        return $false
    }
}
