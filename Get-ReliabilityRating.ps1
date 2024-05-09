# This is a WIP


# Function to group most common events
Function Get-SortedReliabilityRecords {
    Param ([string]$computer = “.”)
    Get-WmiObject -Class win32_reliabilityRecords -ComputerName $computer |
    Group-Object -Property sourcename, eventidentifier -NoElement |
    Sort-Object -Descending count | Format-Table -AutoSize -Property count, @{Label = “Source, EventID”;Expression = {$_.name} }
}


# Get average reliability score
Get-Ciminstance Win32_ReliabilityStabilityMetrics | Measure-Object -Average -Maximum  -Minimum -Property systemStabilityIndex


# Pull an itemized list of all errors 
# Event 19 is a successful event, so filtering it out to hide success and only show problems
Get-CimInstance -ClassName Win32_ReliabilityRecords | Where-Object { $_.EventIdentifier -ne 19 }


# Grouped output of all errors
Get-CimInstance -ClassName Win32_ReliabilityRecords | Select ProductName | Group-Object -Property productname -NoElement | Sort-Object count -Descending


# Get hardware scores
Get-Ciminstance Win32_ReliabilityStabilityMetrics | Measure-Object -Average -Maximum  -Minimum -Property systemStabilityIndex
