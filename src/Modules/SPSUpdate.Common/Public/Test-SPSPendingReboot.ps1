function Test-SPSPendingReboot {
    [CmdletBinding()]
    param ()

    $rebootReasons = New-Object -TypeName System.Collections.Generic.List[string]

    $registryChecks = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'; Reason = 'WindowsUpdateRebootRequired' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'; Reason = 'ComponentBasedServicingRebootPending' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootInProgress'; Reason = 'ComponentBasedServicingRebootInProgress' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\ServerManager\CurrentRebootAttempts'; Reason = 'ServerManagerCurrentRebootAttempts' }
    )

    foreach ($check in $registryChecks) {
        if (Test-Path -Path $check.Path -ErrorAction SilentlyContinue) {
            $rebootReasons.Add($check.Reason)
        }
    }

    # WindowsUpdate\Services\Pending can exist even after reboot; require at least one child entry.
    $wuServicesPendingPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Services\Pending'
    if (Test-Path -Path $wuServicesPendingPath -ErrorAction SilentlyContinue) {
        $wuPendingEntries = Get-ChildItem -Path $wuServicesPendingPath -ErrorAction SilentlyContinue
        if ($null -ne $wuPendingEntries -and $wuPendingEntries.Count -gt 0) {
            $rebootReasons.Add('WindowsUpdateServicesPending')
        }
    }

    $sessionManager = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue
    if ($null -ne $sessionManager -and $null -ne $sessionManager.PendingFileRenameOperations -and $sessionManager.PendingFileRenameOperations.Count -gt 0) {
        $rebootReasons.Add('PendingFileRenameOperations')
    }

    $activeComputerName = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -Name ComputerName -ErrorAction SilentlyContinue
    $pendingComputerName = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name ComputerName -ErrorAction SilentlyContinue
    if ($null -ne $activeComputerName -and $null -ne $pendingComputerName -and $activeComputerName.ComputerName -ne $pendingComputerName.ComputerName) {
        $rebootReasons.Add('PendingComputerRename')
    }

    if (Test-Path -Path 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Reboot Management\RebootData' -ErrorAction SilentlyContinue) {
        $rebootReasons.Add('ConfigMgrRebootPending')
    }

    return [PSCustomObject]@{
        IsPending = ($rebootReasons.Count -gt 0)
        Reasons   = $rebootReasons.ToArray()
    }
}
