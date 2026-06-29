# =====================================================================================
# SPSUpdate.Common - module loader
#
# Dot-sources every *.ps1 in Private/ and Public/, then exports only the public
# function names (read from the Public folder) plus any aliases declared in the
# manifest. Private functions remain accessible inside the module but are hidden
# from callers.
# =====================================================================================

$script:ModuleRoot = $PSScriptRoot

$private = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private\*.ps1') -ErrorAction SilentlyContinue)
$public  = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public\*.ps1')  -ErrorAction SilentlyContinue)

foreach ($file in @($private + $public)) {
    try {
        . $file.FullName
    }
    catch {
        Write-Error -Message "Failed to import function file '$($file.FullName)': $_"
    }
}

if ($public.Count -gt 0) {
    Export-ModuleMember -Function $public.BaseName -Alias 'Copy-SPSSideBySideFilesAllServers'
}
