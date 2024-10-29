function Get-DefenderLicensedStatus {
    # Define the registry path and property name
    $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status"
    $propertyName = "OnboardingState"

    # Check if the registry key and property exist and retrieve the value
    $onboardingState = Get-ItemProperty -Path $registryPath -Name $propertyName -EA 0

    # Return $true if the value is 1, otherwise return $false
    if ($onboardingState.$propertyName -eq 1) {
        return $true
    } else {
        return $false
    }
}
