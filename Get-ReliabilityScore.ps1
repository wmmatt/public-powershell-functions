function Get-ReliabilityScore {
    <#
    .SYNOPSIS
        Retrieves system reliability data over a 30-day period relative to the latest available entry and gathers recent error events.
    
    .DESCRIPTION
        This function collects entries from Win32_ReliabilityStabilityMetrics, determines the latest entry date, and calculates the average
        SystemStabilityIndex over the 30-day period ending at that date. It then retrieves the last 10 events from the System and Application 
        logs that are of critical (Level 1) or error (Level 2) level. The function returns an object with:
          - LatestReliabilityScoreDate: the date of the latest reliability metric.
          - AverageStabilityScore: the average stability score over the period.
          - ScoreDateRange: a string (yyyy-MM-dd to yyyy-MM-dd) representing the 30-day window.
          - HealthStatus: "Healthy" if the average score is ≥ 7, otherwise "Not healthy".
          - Last10BadLogs: an array of the last 10 error or critical events (including TimeCreated, Level, and Message).
    
    .EXAMPLE
        PS C:\> Get-ReliabilityScore
    #>

    # Define the averaging period as 30 days relative to the latest entry
    $periodDays = 30
    $currentDate = Get-Date

    # Retrieve all entries from Win32_ReliabilityStabilityMetrics
    $allEntries = Get-CimInstance -Namespace root\cimv2 -ClassName Win32_ReliabilityStabilityMetrics
    if (-not $allEntries) {
        Write-Error "No reliability data found. Ensure the RAC task is running."
        return $null
    }

    # Process entries: convert TimeGenerated to DateTime and collect valid entries
    $validEntries = @()
    foreach ($entry in $allEntries) {
        if ($entry.TimeGenerated) {
            try {
                $dt = [datetime]::Parse($entry.TimeGenerated.ToString())
                $validEntries += [PSCustomObject]@{
                    Score         = $entry.SystemStabilityIndex
                    TimeGenerated = $dt
                }
            }
            catch {
                # Skip any entries that fail conversion.
            }
        }
    }

    if ($validEntries.Count -eq 0) {
        Write-Error "Could not parse any valid reliability entries."
        return $null
    }

    # Determine the latest entry's date
    $latestEntry = $validEntries | Sort-Object TimeGenerated -Descending | Select-Object -First 1
    $latestDate = $latestEntry.TimeGenerated

    # Define the 30-day period ending at the latest entry's date
    $startPeriod = $latestDate.AddDays(-$periodDays)

    # Filter entries within that 30-day period
    $periodEntries = $validEntries | Where-Object { $_.TimeGenerated -ge $startPeriod -and $_.TimeGenerated -le $latestDate }
    if ($periodEntries.Count -eq 0) {
        Write-Error "No reliability data found in the period from $startPeriod to $latestDate."
        return $null
    }

    # Calculate the average stability score over the period
    $averageScore = ($periodEntries | Measure-Object -Property Score -Average).Average
    $averageScore = [math]::Round($averageScore, 2)

    # Determine health status based on average score (Healthy if >= 7, else Not healthy)
    $healthStatus = if ($averageScore -ge 7) { "Healthy" } else { "Not healthy" }

    # Retrieve the last 10 error/critical events from System and Application logs
    try {
        $systemErrors = Get-WinEvent -FilterHashtable @{ LogName = "System"; Level = @(1,2) } -MaxEvents 100 -ErrorAction SilentlyContinue
        $appErrors    = Get-WinEvent -FilterHashtable @{ LogName = "Application"; Level = @(1,2) } -MaxEvents 100 -ErrorAction SilentlyContinue
        $combinedLogs = $systemErrors + $appErrors
        
        $last10BadLogs = $combinedLogs |
            Sort-Object TimeCreated -Descending |
            Select-Object -First 10 |
            ForEach-Object {
                [PSCustomObject]@{
                    TimeCreated = $_.TimeCreated
                    Level       = $_.LevelDisplayName
                    Message     = $_.Message
                }
            }
    }
    catch {
        Write-Warning "Error retrieving events from System and Application logs."
        $last10BadLogs = @()
    }

    # Build and return the output object
    return [PSCustomObject]@{
        LatestReliabilityScoreDate = $latestDate
        AverageStabilityScore      = $averageScore
        ScoreDateRange             = "$($startPeriod.ToString('yyyy-MM-dd')) to $($latestDate.ToString('yyyy-MM-dd'))"
        HealthStatus               = $healthStatus
        Last10BadLogs              = $last10BadLogs
    }
}
