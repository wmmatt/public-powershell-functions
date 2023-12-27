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
        [string]$User,  # Username of the local user account to test
        [string]$Pass   # Password of the local user account to test
    )

    # Adding the necessary .NET assembly for account management
    Add-Type -assemblyname System.DirectoryServices.AccountManagement 

    # Creating a new context for local machine account management
    $test = New-Object System.DirectoryServices.AccountManagement.PrincipalContext([System.DirectoryServices.AccountManagement.ContextType]::Machine)

    # Validating the credentials against the local machine account
    $test.ValidateCredentials($user, $pass)
}
