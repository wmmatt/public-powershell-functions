function Reset-WindowsUpdate {
    <#
    .DESCRIPTION
        This function resets the Windows Update components and settings, including stopping related services, removing certain files and registry keys,
        resetting services, re-registering DLLs, and forcing a Windows Update check.

    .OUTPUTS
        Outputs a status message indicating the success or failure of the operation.

    .EXAMPLE
        Reset-WindowsUpdate
        This command resets the Windows Update components and forces a check for new updates.
    #>

    # Set date & time string for backup files
    $dateString = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")

    try {
        # Define the update services to be managed
        $updateServices = 'BITS', 'wuauserv', 'appidsvc', 'cryptsvc'

        # Stop Windows Update related services
        $updateServices | ForEach-Object {
            Stop-Service -Name $_ -Force -ErrorAction Stop
        }

        # Remove QMGR Data files
        Remove-Item "$env:ALLUSERSPROFILE\Application Data\Microsoft\Network\Downloader\qmgr*.dat" -ErrorAction SilentlyContinue

        # Rename SoftwareDistribution and CatRoot2 folders for backup and allow them to be recreated
        Rename-Item -Path "$env:SystemRoot\SoftwareDistribution" -NewName "$env:SystemRoot\SoftwareDistribution.bak.$dateString" -ErrorAction SilentlyContinue -Force
        Rename-Item -Path "$env:SystemRoot\System32\Catroot2" -NewName "$env:SystemRoot\System32\Catroot2.bak.$dateString" -ErrorAction SilentlyContinue -Force

        # Remove old Windows Update log file
        Remove-Item "$env:SystemRoot\WindowsUpdate.log" -ErrorAction SilentlyContinue

        # Reset Windows Update service security descriptors
        sc.exe sdset bits 'D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)'
        sc.exe sdset wuauserv 'D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)'

        # Register necessary DLL files
        $dlls = 'atl.dll', 'urlmon.dll', 'mshtml.dll', 'shdocvw.dll', 'browseui.dll', 'jscript.dll', 'vbscript.dll', 'scrrun.dll', 'msxml.dll', 'msxml3.dll', 'msxml6.dll', 'actxprxy.dll', 'softpub.dll', 'wintrust.dll', 'dssenh.dll', 'rsaenh.dll', 'gpkcsp.dll', 'sccbase.dll', 'slbcsp.dll', 'cryptdlg.dll', 'oleaut32.dll', 'ole32.dll', 'shell32.dll', 'initpki.dll', 'wuapi.dll', 'wuaueng.dll', 'wuaueng1.dll', 'wucltui.dll', 'wups.dll', 'wups2.dll', 'wuweb.dll', 'qmgr.dll', 'qmgrprxy.dll', 'wucltux.dll', 'muweb.dll', 'wuwebv.dll'

        $dlls | ForEach-Object {
            regsvr32.exe /s $_
        }

        # Remove WSUS client settings from the registry
        Remove-ItemProperty -Path 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate' -Name 'AccountDomainSid' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate' -Name 'PingID' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate' -Name 'SusClientId' -ErrorAction SilentlyContinue

        # Reset WinSock and WinHTTP settings
        netsh winsock reset
        netsh winhttp reset proxy

        # Delete all BITS jobs
        Get-BitsTransfer | Remove-BitsTransfer -ErrorAction SilentlyContinue

        # Start Windows Update related services
        $updateServices | ForEach-Object {
            Start-Service -Name $_ -ErrorAction Stop
        }

        # Force Windows Update to check for updates
        (New-Object -ComObject Microsoft.Update.AutoUpdate).DetectNow()
        usoclient startinteractivescan

        # Ensure Windows Update services are set to auto start
        $updateAutoServices = 'BITS','wuauserv','appidsvc','cryptsvc','UsoSvc'
        $updateAutoServices | ForEach-Object {
            Set-Service -Name $_ -StartupType Automatic -ErrorAction SilentlyContinue
        }

        Write-Output "Windows Update components have been reset successfully."

    } catch {
        Write-Error "An error occurred during the Windows Update reset: $_"
    }
}
