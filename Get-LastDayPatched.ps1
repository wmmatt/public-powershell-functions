# Function to get the latest patch installed via Windows Update API
function Get-LastDayPatched {
    function Get-LatestPatchviaAPI {
        $Session = New-Object -ComObject Microsoft.Update.Session
        $Searcher = $Session.CreateUpdateSearcher()
        $SearchResult = $Searcher.Search("IsInstalled=1").Updates
        $LatestPatchviaAPI = $SearchResult | Sort-Object -Property LastDeploymentChangeTime | Select-Object -Last 1
        return $LatestPatchviaAPI
    }

    # Function to get the latest patch installed via Get-hotFix/QuickFixEngineering
    function Get-LatestPatchviaHotFix {
        $Hotfixes = Get-HotFix
        $LatestPatchviaHotFix = $Hotfixes | Sort-Object -Property Date -Descending | Select-Object -First 1
        return $LatestPatchviaHotFix
    }

    # Get the latest patch installed through API
    $LatestPatchviaAPI = Get-LatestPatchviaAPI

    # Get the latest patch installed through Get-HotFix
    $LatestPatchviaHotFix = Get-LatestPatchviaHotFix

    # Compare the installation dates to determine the newest patch
    if ($LatestPatchviaAPI.LastDeploymentChangeTime -gt $LatestPatchviaHotFix.Date) {
        $NewestPatch = $LatestPatchviaAPI
        
        # Display information about the newest installed patch
        # if you want to display latest patch name use: $($NewestPatch.Title)"
        return ($NewestPatch.LastDeploymentChangeTime).ToString("MM/dd/yyyy")
    } else {
        $NewestPatch = $LatestPatchviaHotFix

        # Display information about the newest installed patch
        # if you want to display latest patch name use: $($NewestPatch.HotFixID)
        return ($NewestPatch.Date).ToString("MM/dd/yyyy")
    }
}
