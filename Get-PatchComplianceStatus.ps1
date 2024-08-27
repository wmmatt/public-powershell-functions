 function Get-PatchComplianceStatus {
    <#
    .DESCRIPTION
        This function checks the latest patch installed on the system via Windows Update or HotFix, determines if it was installed within the last 45 days,
        and returns an object containing the last patch date, whether the system is compliant with the 45-day rule, and the patch details.

    .OUTPUTS
        Returns an object with the following properties:
        - LastPatchDate (string): The date when the last patch was installed.
        - IsCompliant (bool): Whether the last patch was installed within the acceptable timeframe (true/false).
        - PatchName (string): The name or identifier of the last installed patch.

    .EXAMPLE
        Get-PatchComplianceStatus
        This command checks the patch compliance status and returns the last patch date, compliance status, and patch details.
    #>

    # Define the maximum number of days an endpoint can go without patching
    $acceptableDays = 45
    $currentDate = Get-Date
    $acceptableDate = $currentDate.AddDays(-$acceptableDays)

    # Function to get the latest patch installed via Windows Update API
    function Get-LatestPatchviaAPI {
        $Session = New-Object -ComObject Microsoft.Update.Session
        $Searcher = $Session.CreateUpdateSearcher()
        $SearchResult = $Searcher.Search("IsInstalled=1").Updates
        $LatestPatchviaAPI = $SearchResult | Sort-Object -Property LastDeploymentChangeTime | Select-Object -Last 1
        return $LatestPatchviaAPI
    }

    # Function to get the latest patch installed via Get-HotFix/QuickFixEngineering
    function Get-LatestPatchviaHotFix {
        $Hotfixes = Get-HotFix
        $LatestPatchviaHotFix = $Hotfixes | Sort-Object -Property InstalledOn -Descending | Select-Object -First 1
        return $LatestPatchviaHotFix
    }

    # Get the latest patch installed through API
    $LatestPatchviaAPI = Get-LatestPatchviaAPI

    # Get the latest patch installed through Get-HotFix
    $LatestPatchviaHotFix = Get-LatestPatchviaHotFix

    # Determine the most recent patch between the two methods
    if ($LatestPatchviaAPI.LastDeploymentChangeTime -gt $LatestPatchviaHotFix.InstalledOn) {
        $NewestPatch = $LatestPatchviaAPI
        $lastPatchedDate = $NewestPatch.LastDeploymentChangeTime
        $patchName = $NewestPatch.Title
    } else {
        $NewestPatch = $LatestPatchviaHotFix
        $lastPatchedDate = $NewestPatch.InstalledOn
        $patchName = $NewestPatch.HotFixID
    }

    # Determine if the last patch was installed within the acceptable timeframe
    $isCompliant = $lastPatchedDate -ge $acceptableDate

    # Format the last patched date for output
    $lastPatchedDateFormatted = $lastPatchedDate.ToString("MM/dd/yyyy")

    # Return an object with the results
    return @{
        LastPatchDate = $lastPatchedDateFormatted
        IsCompliant   = $isCompliant
        PatchName     = $patchName
    }
}
