function Test-WindowsLocalCredential {
    <#
    .DESCRIPTION
        Returns $true if the cred was good, returns $false of the cred was bad. Works on local users only.
    .EXAMPLE
        PS> Test-WindowsLocalCredential -User Administrator -Pass seCuREPASS44!
        True

        PS> Test-WindowsLocalCredential -User Administrator -Pass seCuREPASS44!999
        False
    #>
    param (
        [string]$User,
        [string]$Pass
    )

    Add-Type -assemblyname System.DirectoryServices.AccountManagement 
    $test = New-Object System.DirectoryServices.AccountManagement.PrincipalContext([System.DirectoryServices.AccountManagement.ContextType]::Machine)
    $test.ValidateCredentials($user,$pass)
}
