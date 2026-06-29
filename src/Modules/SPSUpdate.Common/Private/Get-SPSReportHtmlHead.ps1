function Get-SPSReportHtmlHead {
    <#
        .SYNOPSIS
        Returns the document head (with the embedded stylesheet) and the opening body tag.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Title
    )

    $css = @'
:root{--brand:#1f6fb2;--brand-dark:#155a91;--ink:#222;--muted:#666;--line:#e3e3e3;--zebra:#f7f9fb;--bar:#1f6fb2;--bar-bg:#e8eef5}
*{box-sizing:border-box}
body{font-family:'Aptos','Segoe UI',-apple-system,BlinkMacSystemFont,sans-serif;color:var(--ink);margin:0;padding:24px;background:#fff}
h1{color:var(--brand);font-size:22px;margin:0 0 4px}
h2{color:var(--brand);font-size:16px;margin:24px 0 8px;border-bottom:2px solid var(--brand);padding-bottom:4px}
h3{color:var(--brand-dark);font-size:13px;margin:0 0 6px}
.meta{color:var(--muted);font-size:12px;margin-bottom:16px}
.summary{background:#eef5fb;border:1px solid #cfe0ef;border-left:4px solid var(--brand);border-radius:6px;padding:16px;margin-bottom:8px}
.cards{display:flex;flex-wrap:wrap;gap:12px}
.card{background:#fff;border:1px solid var(--line);border-radius:6px;padding:12px 16px;min-width:120px}
.card-value{font-size:24px;font-weight:700;color:var(--brand)}
.card-label{font-size:12px;color:var(--muted)}
.card-sub{font-size:11px;color:var(--muted);margin-top:2px}
.card.accent{background:#eef5fb;border-color:#cfe0ef}
.dist{margin-top:14px}
.dist-row{display:flex;align-items:center;gap:10px;margin:6px 0;font-size:12px}
.dist-name{width:90px;color:var(--brand-dark);font-weight:600}
.dist-track{flex:1;background:var(--bar-bg);border-radius:4px;height:16px;overflow:hidden}
.dist-fill{background:var(--bar);height:100%}
.dist-val{width:170px;text-align:right;color:var(--muted)}
table{border-collapse:collapse;width:100%;font-size:12px}
th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line);vertical-align:top}
th{background:var(--brand);color:#fff;cursor:pointer;user-select:none;position:sticky;top:0}
td.num,th.num{text-align:right}
tbody tr:nth-child(even){background:var(--zebra)}
.controls{display:flex;justify-content:space-between;align-items:center;margin:12px 0;flex-wrap:wrap;gap:8px}
.search{padding:6px 10px;border:1px solid var(--line);border-radius:4px;font-size:13px;width:280px;max-width:100%}
.pager{display:flex;gap:8px;align-items:center;font-size:12px}
.pager button{padding:4px 10px;border:1px solid var(--line);background:#fff;border-radius:4px;cursor:pointer}
.pager button:disabled{opacity:.4;cursor:default}
.footer{color:var(--muted);font-size:11px;margin-top:24px;border-top:1px solid var(--line);padding-top:8px}
'@

    return "<!DOCTYPE html><html lang=`"en`"><head><meta charset=`"utf-8`"><meta name=`"viewport`" content=`"width=device-width, initial-scale=1`"><title>$Title</title><style>$css</style></head><body>"
}
