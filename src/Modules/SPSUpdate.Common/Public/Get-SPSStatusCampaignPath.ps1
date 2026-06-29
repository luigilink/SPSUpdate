function Get-SPSStatusCampaignPath {
    <#
        .SYNOPSIS
        Resolves the campaign folder of the patching status store.

        .DESCRIPTION
        Builds the folder that holds the status scope files for one patching campaign:
        <root>\<Application>-<ConfigurationName>-<FarmName>. The root is the configured
        StatusStorePath (a UNC share shared by every server) when provided, otherwise it
        falls back to a local 'status' folder under the Results folder (in which case
        ProductUpdate runs launched on other servers are not captured centrally).

        The folder is created when -CreateIfMissing is specified.

        .PARAMETER StatusStorePath
        The configured StatusStorePath (UNC share). Empty to use the local fallback.

        .PARAMETER ResultsFolder
        The local Results folder used for the fallback when StatusStorePath is empty.

        .PARAMETER Application
        Application code (from the config).

        .PARAMETER Environment
        Environment/configuration name (from the config).

        .PARAMETER FarmName
        Farm name (from the config).

        .PARAMETER CreateIfMissing
        Create the campaign folder if it does not exist.

        .EXAMPLE
        Get-SPSStatusCampaignPath -StatusStorePath $cfg.StatusStorePath -ResultsFolder $results -Application 'contoso' -Environment 'PROD' -FarmName 'CONTENT' -CreateIfMissing
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter()]
        [AllowEmptyString()]
        [System.String]
        $StatusStorePath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $ResultsFolder,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Application,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Environment,

        [Parameter(Mandatory = $true)]
        [System.String]
        $FarmName,

        [Parameter()]
        [switch]
        $CreateIfMissing
    )

    if ([string]::IsNullOrWhiteSpace($StatusStorePath)) {
        $root = Join-Path -Path $ResultsFolder -ChildPath 'status'
    }
    else {
        $root = $StatusStorePath
    }

    $campaignName = ('{0}-{1}-{2}' -f $Application, $Environment, $FarmName) -replace '[^A-Za-z0-9_.-]', '_'
    $campaignPath = Join-Path -Path $root -ChildPath $campaignName

    if ($CreateIfMissing -and -not (Test-Path -Path $campaignPath)) {
        $null = New-Item -Path $campaignPath -ItemType Directory -Force
    }

    return $campaignPath
}
