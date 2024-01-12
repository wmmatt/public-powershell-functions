Function Get-InstalledService {
    <#
    .SYNOPSIS
    Get-InstalledService

    .DESCRIPTION
    This is to verify that a given list of services exists, and optionally that they are all running.
    If all services are present, and running (if you specify to check that), it will output $true. If
    any services are missing, or in the stopped state (if you specify to check that), it will output $false

    .PARAMETER ServiceNameArray
    Use a single service name, or a list of services in single quotes separated by commas. Note this 
    the name of the service, not the display name of the service.

    .PARAMETER VerifyServiceRunning
    Define this as $true if you wish to also verify the services don't only exist, but are also running.

    .EXAMPLE
    C:\PS> Get-InstalledService -ServiceNameArray 'swprv'
    C:\PS> Get-InstalledService -ServiceNameArray 'swprv','uhssvc' -VerifyServiceRunning $true
    #>


    [CmdletBinding()]

    param(
        [Parameter(Mandatory = $true)]
        [array]$ServiceNameArray,
        [Parameter(Mandatory = $false)]
        [boolean]$VerifyServiceRunning
    )

    if (!$VerifyServiceRunning) {
        try {
            Get-Service -Name $ServiceNameArray -ErrorAction Stop | Out-Null
            return $true
        } catch {
            return $false
        }
    } else {
        try {
            Get-Service -Name $ServiceNameArray -ErrorAction Stop | Out-Null
            $ServiceNameArray | ForEach {
                $status = Get-Service -Name $_ | Where { $_.Status -ne 'Running' }
                if ($status) {
                    throw
                }
            }
            return $true
        } catch {
            return $false
        }
    }
}
