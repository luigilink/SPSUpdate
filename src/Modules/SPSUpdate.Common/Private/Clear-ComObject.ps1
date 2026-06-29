function Clear-ComObject {
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [System.Object]
        $ComObject
    )

    if ($null -eq $ComObject) {
        return
    }

    try {
        if ([System.Runtime.InteropServices.Marshal]::IsComObject($ComObject)) {
            [void][System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($ComObject)
        }
    }
    catch {
        Write-Verbose -Message "Unable to release COM object: $($_.Exception.Message)"
    }
}
