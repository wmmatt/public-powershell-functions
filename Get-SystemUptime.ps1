 function Get-SystemUptime {
    <#
    .DESCRIPTION
        This function retrieves the uptime of the current Windows machine, showing how long the system has been running since the last boot.

    .OUTPUTS
        Returns an object with the following properties:
        - UptimeDays (int): The number of days the system has been running.
        - UptimeHours (int): The number of hours (excluding full days) the system has been running.
        - UptimeMinutes (int): The number of minutes (excluding full hours) the system has been running.
        - LastBootTime (datetime): The date and time when the system was last booted.

    .EXAMPLE
        Get-SystemUptime
        This command retrieves the current system's uptime and displays the days, hours, and minutes since the last boot.
    #>

    # Retrieve the last boot time from the system
    $lastBootTime = (Get-CimInstance -ClassName win32_operatingsystem).LastBootUpTime

    # Calculate the difference between the current time and the last boot time
    $uptime = New-TimeSpan -Start $lastBootTime -End (Get-Date)

    # Prepare the output object
    return @{
        UptimeDays   = [math]::Floor($uptime.TotalDays)
        UptimeHours  = $uptime.Hours
        UptimeMinutes = $uptime.Minutes
        LastBootTime = $lastBootTime
    }
}
