function Enable-ExchangeUnifiedAuditLogIngestion {
    <#
    .SYNOPSIS
    Installs and imports the ExchangeOnlineManagement module if needed, connects to Exchange Online, checks the Unified Audit Log Ingestion status, and enables it if disabled.

    .DESCRIPTION
    This function guides you through:
        1. Installing the Exchange Online Management module (if not already installed)
        2. Importing the module
        3. Prompting for your Office 365 admin credentials and connecting to Exchange Online
        4. Checking if Unified Audit Log Ingestion is enabled
        5. Enabling Unified Audit Log Ingestion if it is currently disabled

        Make sure to run this in a standard PowerShell console (not ISE) for proper UI support during authentication.
    #>

    # 1. Check if the ExchangeOnlineManagement module is installed; install it if not found.
    Set-ExecutionPolicy Bypass -Scope CurrentUser -Force

    if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
        Write-Output "ExchangeOnlineManagement module is not installed. Installing now..."
        Install-Module -Name ExchangeOnlineManagement -Force -AllowClobber
    }
    else {
        Write-Output "ExchangeOnlineManagement module is already installed."
    }

    # 2. Import the ExchangeOnlineManagement module.
    Write-Output "Importing ExchangeOnlineManagement module..."
    Import-Module ExchangeOnlineManagement -ErrorAction Stop

    # 3. Prompt for your admin credentials and connect to Exchange Online.
    Write-Output "Connecting to Exchange Online..."
    Connect-ExchangeOnline

    # 4. Retrieve the current audit log configuration.
    Write-Output "Retrieving current audit log configuration..."
    $auditConfig = Get-AdminAuditLogConfig

    # 5. Check the Unified Audit Log Ingestion status and enable it if it's disabled.
    if ($auditConfig.UnifiedAuditLogIngestionEnabled -eq $false) {
        Write-Output "Unified Audit Log Ingestion is currently DISABLED. Enabling it now..."
        Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true
        Write-Output "Unified Audit Log Ingestion has been ENABLED."
    }
    else {
        Write-Output "Unified Audit Log Ingestion is already enabled."
    }

    # 6. Display the current audit log ingestion status.
    Write-Output "Current Audit Log Ingestion status:"
    Get-AdminAuditLogConfig | Format-List UnifiedAuditLogIngestionEnabled

    Write-Output "Function execution completed."
}