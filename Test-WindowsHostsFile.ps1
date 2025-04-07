function Test-WindowsHostsFile.ps1 {
    # Define the path to the hosts file
    $hostsFilePath = "C:\Windows\System32\drivers\etc\hosts"


    # Get contents of the hosts file
    $currentHostsContent = Get-Content -Path $hostsFilePath -Raw
    
    
    # Define the default Windows hosts file content
    $defaultHostsContent = @"
# Copyright (c) 1993-2009 Microsoft Corp.
#
# This is a sample HOSTS file used by Microsoft TCP/IP for Windows.
#
# This file contains the mappings of IP addresses to host names. Each
# entry should be kept on an individual line. The IP address should
# be placed in the first column followed by the corresponding host name.
# The IP address and the host name should be separated by at least one
# space.
#
# Additionally, comments (such as these) may be inserted on individual
# lines or following the machine name denoted by a '#' symbol.
#
# For example:
#
#      102.54.94.97     rhino.acme.com          # source server
#       38.25.63.10     x.acme.com              # x client host

# localhost name resolution is handled within DNS itself.
# 127.0.0.1       localhost
# ::1             localhost  
"@
    
    $currentHostsContent.Length
    $defaultHostsContent.Length
    
    if ($currentHostsContent.Length -eq $defaultHostsContent.Length) {
        return $true
    } else {
        return $false
    }
}
