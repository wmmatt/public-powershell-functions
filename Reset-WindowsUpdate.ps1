<#
.SYNOPSIS
    Resets Windows Update components and forces an update check.

.DESCRIPTION
    Stops update services, clears caches and queues, resets service security
    descriptors, re-registers DLLs, resets network settings, and restarts
    services. Designed for RMM deployment to fix stuck or broken Windows Update.

.NOTES
    Run as SYSTEM from RMM. Creates backups of SoftwareDistribution and 
    Catroot2 folders with timestamps before removal.
#>

#Requires -Version 5.1

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = switch ($Level) {
        'INFO'    { '[INFO]   ' }
        'WARN'    { '[WARN]   ' }
        'ERROR'   { '[ERROR]  ' }
        'SUCCESS' { '[OK]     ' }
    }
    Write-Output "$timestamp $prefix$Message"
}

function Reset-WindowsUpdate {
    
    $dateString = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
    
    Write-Log "Starting Windows Update reset"
    
    # Services we need to stop, then restart
    $updateServices = @('BITS', 'wuauserv', 'appidsvc', 'cryptsvc')
    
    # Services that should be set to auto-start (includes UsoSvc for modern Windows)
    $autoStartServices = @('BITS', 'wuauserv', 'appidsvc', 'cryptsvc', 'UsoSvc')
    
    # Clear BITS jobs before stopping service - cmdlet needs service running
    Write-Log "Clearing BITS transfer queue..."
    try {
        $bitsJobs = Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue
        if ($bitsJobs) {
            $bitsJobs | Remove-BitsTransfer -ErrorAction SilentlyContinue
            Write-Log "Cleared $($bitsJobs.Count) BITS jobs" -Level SUCCESS
        }
        else {
            Write-Log "No BITS jobs to clear" -Level INFO
        }
    }
    catch {
        Write-Log "Could not clear BITS jobs: $_" -Level WARN
    }
    
    # Stop services
    Write-Log "Stopping Windows Update services..."
    foreach ($service in $updateServices) {
        try {
            $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq 'Running') {
                Stop-Service -Name $service -Force -ErrorAction Stop
                Write-Log "Stopped $service" -Level SUCCESS
            }
            else {
                Write-Log "$service already stopped or not found" -Level INFO
            }
        }
        catch {
            Write-Log "Failed to stop $service`: $_" -Level WARN
        }
    }
    
    # Give services a moment to fully stop
    Start-Sleep -Seconds 3
    
    # Remove QMGR data files (BITS queue database)
    Write-Log "Removing QMGR data files..."
    $qmgrPath = "$env:ALLUSERSPROFILE\Application Data\Microsoft\Network\Downloader\qmgr*.dat"
    $qmgrFiles = Get-Item $qmgrPath -ErrorAction SilentlyContinue
    if ($qmgrFiles) {
        Remove-Item $qmgrPath -Force -ErrorAction SilentlyContinue
        Write-Log "Removed QMGR data files" -Level SUCCESS
    }
    else {
        Write-Log "No QMGR data files found" -Level INFO
    }
    
    # Backup and rename SoftwareDistribution folder
    Write-Log "Backing up SoftwareDistribution folder..."
    $sdPath = "$env:SystemRoot\SoftwareDistribution"
    if (Test-Path $sdPath) {
        try {
            Rename-Item -Path $sdPath -NewName "SoftwareDistribution.bak.$dateString" -Force -ErrorAction Stop
            Write-Log "Renamed SoftwareDistribution to SoftwareDistribution.bak.$dateString" -Level SUCCESS
        }
        catch {
            Write-Log "Failed to rename SoftwareDistribution: $_" -Level WARN
        }
    }
    else {
        Write-Log "SoftwareDistribution folder not found" -Level INFO
    }
    
    # Backup and rename Catroot2 folder
    Write-Log "Backing up Catroot2 folder..."
    $catroot2Path = "$env:SystemRoot\System32\Catroot2"
    if (Test-Path $catroot2Path) {
        try {
            Rename-Item -Path $catroot2Path -NewName "Catroot2.bak.$dateString" -Force -ErrorAction Stop
            Write-Log "Renamed Catroot2 to Catroot2.bak.$dateString" -Level SUCCESS
        }
        catch {
            Write-Log "Failed to rename Catroot2: $_" -Level WARN
        }
    }
    else {
        Write-Log "Catroot2 folder not found" -Level INFO
    }
    
    # Remove old Windows Update log
    $wuLog = "$env:SystemRoot\WindowsUpdate.log"
    if (Test-Path $wuLog) {
        Remove-Item $wuLog -Force -ErrorAction SilentlyContinue
        Write-Log "Removed old WindowsUpdate.log" -Level SUCCESS
    }
    
    # Reset service security descriptors
    Write-Log "Resetting service security descriptors..."
    $null = sc.exe sdset bits 'D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)'
    $null = sc.exe sdset wuauserv 'D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)'
    Write-Log "Reset BITS and wuauserv security descriptors" -Level SUCCESS
    
    # Re-register DLLs that actually exist and are COM servers on modern Windows
    Write-Log "Re-registering Windows Update DLLs..."
    $dlls = @(
        'atl.dll',
        'urlmon.dll',
        'mshtml.dll',
        'shdocvw.dll',
        'browseui.dll',
        'jscript.dll',
        'vbscript.dll',
        'scrrun.dll',
        'msxml3.dll',
        'msxml6.dll',
        'actxprxy.dll',
        'softpub.dll',
        'wintrust.dll',
        'dssenh.dll',
        'rsaenh.dll',
        'cryptdlg.dll',
        'oleaut32.dll',
        'initpki.dll',
        'wuapi.dll',
        'wuaueng.dll',
        'wups.dll',
        'wups2.dll',
        'qmgr.dll',
        'qmgrprxy.dll',
        'wucltux.dll'
    )
    
    $registered = 0
    foreach ($dll in $dlls) {
        $result = regsvr32.exe /s $dll 2>&1
        $registered++
    }
    Write-Log "Attempted registration of $registered DLLs" -Level SUCCESS
    
    # Remove WSUS client settings that can cause update issues
    Write-Log "Clearing WSUS client identifiers..."
    $wuRegPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate'
    $propsToRemove = @('AccountDomainSid', 'PingID', 'SusClientId')
    
    foreach ($prop in $propsToRemove) {
        try {
            $existing = Get-ItemProperty -Path $wuRegPath -Name $prop -ErrorAction SilentlyContinue
            if ($existing) {
                Remove-ItemProperty -Path $wuRegPath -Name $prop -ErrorAction Stop
                Write-Log "Removed $prop from registry" -Level SUCCESS
            }
        }
        catch {
            Write-Log "Could not remove $prop`: $_" -Level WARN
        }
    }
    
    # Reset WinSock catalog
    Write-Log "Resetting WinSock..."
    $null = netsh winsock reset 2>&1
    Write-Log "WinSock reset complete" -Level SUCCESS
    
    # Reset WinHTTP proxy
    Write-Log "Resetting WinHTTP proxy..."
    $null = netsh winhttp reset proxy 2>&1
    Write-Log "WinHTTP proxy reset complete" -Level SUCCESS
    
    # Start services back up
    Write-Log "Starting Windows Update services..."
    $failedServices = @()
    
    foreach ($service in $updateServices) {
        try {
            Start-Service -Name $service -ErrorAction Stop
            
            # Verify it actually started
            $svc = Get-Service -Name $service
            if ($svc.Status -eq 'Running') {
                Write-Log "Started $service" -Level SUCCESS
            }
            else {
                Write-Log "$service started but status is $($svc.Status)" -Level WARN
                $failedServices += $service
            }
        }
        catch {
            Write-Log "Failed to start $service`: $_" -Level ERROR
            $failedServices += $service
        }
    }
    
    # Set services to auto-start
    Write-Log "Setting services to automatic startup..."
    foreach ($service in $autoStartServices) {
        try {
            Set-Service -Name $service -StartupType Automatic -ErrorAction SilentlyContinue
        }
        catch {
            Write-Log "Could not set $service to automatic: $_" -Level WARN
        }
    }
    Write-Log "Startup types configured" -Level SUCCESS
    
    # Trigger update detection
    Write-Log "Triggering Windows Update detection..."
    try {
        $autoUpdate = New-Object -ComObject Microsoft.Update.AutoUpdate
        $autoUpdate.DetectNow()
        Write-Log "DetectNow triggered via COM" -Level SUCCESS
    }
    catch {
        Write-Log "COM DetectNow failed: $_" -Level WARN
    }
    
    try {
        $null = usoclient startinteractivescan 2>&1
        Write-Log "UsoClient scan triggered" -Level SUCCESS
    }
    catch {
        Write-Log "UsoClient failed: $_" -Level WARN
    }
    
    # Summary
    Write-Log "Windows Update reset complete"
    if ($failedServices.Count -gt 0) {
        Write-Log "WARNING: These services failed to start: $($failedServices -join ', ')" -Level WARN
        Write-Log "A reboot may be required" -Level WARN
    }
    else {
        Write-Log "All services running normally" -Level SUCCESS
    }
}
