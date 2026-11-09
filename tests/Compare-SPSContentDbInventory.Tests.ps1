# Tests for Compare-SPSContentDbInventory. Get-SPContentDatabase is stubbed so these run
# cross-platform without SharePoint; the function is dot-sourced so the stub defined in the
# test scope is the one it resolves at call time.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $script:funcPath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/Public/Compare-SPSContentDbInventory.ps1'

    $script:tmpDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("spsupd-drift-" + [guid]::NewGuid())
    New-Item -Path $script:tmpDir -ItemType Directory -Force | Out-Null

    function New-InventoryFile {
        param([string[]] $Seq1, [string[]] $Seq2 = @())
        $obj = [PSCustomObject]@{
            SPContentDatabase1 = @($Seq1 | ForEach-Object { [PSCustomObject]@{ Name = $_ } })
            SPContentDatabase2 = @($Seq2 | ForEach-Object { [PSCustomObject]@{ Name = $_ } })
            SPContentDatabase3 = @()
            SPContentDatabase4 = @()
        }
        $path = Join-Path -Path $script:tmpDir -ChildPath ("inv-" + [guid]::NewGuid() + '.json')
        $obj | ConvertTo-Json -Depth 4 | Set-Content -Path $path -Encoding UTF8
        return $path
    }
}

AfterAll {
    if ($script:tmpDir -and (Test-Path $script:tmpDir)) {
        Remove-Item -Path $script:tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Compare-SPSContentDbInventory' {
    It 'reports no drift when the inventory matches the farm (case-insensitive)' {
        function Get-SPContentDatabase { [CmdletBinding()] param() [PSCustomObject]@{ Name = 'WSS_Content' }; [PSCustomObject]@{ Name = 'dsps_content_a' } }
        . $script:funcPath
        $path = New-InventoryFile -Seq1 @('WSS_Content') -Seq2 @('DSPS_CONTENT_A')

        $r = Compare-SPSContentDbInventory -Path $path

        $r.HasDrift | Should -BeFalse
        $r.InventoryCount | Should -Be 2
        $r.LiveCount | Should -Be 2
        @($r.NotInInventory).Count | Should -Be 0
        @($r.NotInFarm).Count | Should -Be 0
    }

    It 'lists databases added to the farm after the inventory was generated' {
        function Get-SPContentDatabase { [CmdletBinding()] param() 'WSS_Content', 'DB_New1', 'DB_New2' | ForEach-Object { [PSCustomObject]@{ Name = $_ } } }
        . $script:funcPath
        $path = New-InventoryFile -Seq1 @('WSS_Content')

        $r = Compare-SPSContentDbInventory -Path $path

        $r.HasDrift | Should -BeTrue
        $r.NotInInventory | Should -Be @('DB_New1', 'DB_New2')
        @($r.NotInFarm).Count | Should -Be 0
        $r.InventoryCount | Should -Be 1
        $r.LiveCount | Should -Be 3
    }

    It 'lists databases that are in the inventory but no longer attached to the farm' {
        function Get-SPContentDatabase { [CmdletBinding()] param() [PSCustomObject]@{ Name = 'WSS_Content' } }
        . $script:funcPath
        $path = New-InventoryFile -Seq1 @('WSS_Content') -Seq2 @('DB_Gone')

        $r = Compare-SPSContentDbInventory -Path $path

        $r.HasDrift | Should -BeTrue
        $r.NotInFarm | Should -Be @('DB_Gone')
        @($r.NotInInventory).Count | Should -Be 0
    }

    It 'throws when the inventory file does not exist' {
        function Get-SPContentDatabase { [CmdletBinding()] param() $null }
        . $script:funcPath
        { Compare-SPSContentDbInventory -Path (Join-Path $script:tmpDir 'missing.json') } | Should -Throw '*not found*'
    }

    It 'propagates a failure to read the live content databases' {
        function Get-SPContentDatabase { [CmdletBinding()] param() throw 'SharePoint unavailable' }
        . $script:funcPath
        $path = New-InventoryFile -Seq1 @('WSS_Content')
        { Compare-SPSContentDbInventory -Path $path } | Should -Throw '*SharePoint unavailable*'
    }
}
