function Get-SPSReportHtmlHead {
    <#
        .SYNOPSIS
        Returns the document head (with the embedded stylesheet) and the opening body wrapper.

        .DESCRIPTION
        Emits the dark/light themed stylesheet shared by the SPSUpdate dashboard (aligned with
        the SPSConfigKit DSC dashboard look): CSS variables, a summary card with a donut and KPIs,
        phase cards with grid tables, and status pills. Fully self-contained (no external assets).
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Title,

        [Parameter()]
        [System.Int32]
        $RefreshSeconds = 0
    )

    $css = @'
:root{
  --background:hsl(216 13% 15%);--bg-glow:hsl(216 20% 22%);--card:hsl(216 13% 13%);--card-2:hsl(216 13% 17%);
  --foreground:hsl(219 18% 82%);--muted-fg:hsl(216 12% 60%);--border:hsl(216 6% 26%);
  --primary:hsl(213 90% 62%);--primary-2:hsl(199 89% 55%);--ok:hsl(152 58% 45%);--warn:hsl(38 92% 55%);
  --err:hsl(3 85% 56%);--info:hsl(199 89% 55%);--muted:hsl(216 12% 55%);
  --shadow:0 10px 30px rgba(0,0,0,.35);--card-tint:rgba(255,255,255,.04);--card-tint-2:rgba(255,255,255,.01);
  --hover:rgba(255,255,255,.02);--radius:14px;
}
html[data-theme="light"]{
  --background:hsl(210 20% 97%);--bg-glow:hsl(213 60% 92%);--card:hsl(0 0% 100%);--card-2:hsl(214 20% 96%);
  --foreground:hsl(216 25% 22%);--muted-fg:hsl(216 12% 42%);--border:hsl(216 15% 85%);
  --primary:hsl(213 82% 48%);--primary-2:hsl(199 85% 42%);--ok:hsl(152 55% 38%);--warn:hsl(35 85% 44%);
  --err:hsl(3 72% 48%);--info:hsl(199 85% 42%);--muted:hsl(216 12% 50%);
  --shadow:0 8px 24px rgba(20,35,60,.10);--card-tint:rgba(255,255,255,0);--card-tint-2:rgba(255,255,255,0);
  --hover:rgba(20,40,80,.03);
}
*{box-sizing:border-box}
body{margin:0;padding:32px;background:radial-gradient(1200px 600px at 15% -10%,var(--bg-glow) 0%,transparent 60%),var(--background);
  color:var(--foreground);font-family:'Segoe UI',system-ui,-apple-system,sans-serif;-webkit-font-smoothing:antialiased;
  transition:background-color .2s ease,color .2s ease}
.wrap{max-width:1200px;margin:0 auto}
.mono{font-family:'Cascadia Code','Consolas',ui-monospace,monospace;font-size:12.5px}
header.page{margin-bottom:22px;position:relative}
header.page .eyebrow{font-family:'Cascadia Code','Consolas',ui-monospace,monospace;text-transform:uppercase;letter-spacing:.18em;font-size:11px;color:var(--muted-fg);margin:0 0 8px}
header.page h1{margin:0;font-size:30px;font-weight:700;letter-spacing:-.01em;background:linear-gradient(92deg,var(--primary),var(--primary-2));-webkit-background-clip:text;background-clip:text;color:transparent}
header.page .sub{color:var(--muted-fg);margin:8px 0 0;font-size:13.5px}
.meta-chips{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}
.chip{display:inline-flex;align-items:center;gap:7px;background:var(--card-2);border:1px solid var(--border);border-radius:999px;padding:6px 12px;font-size:12.5px;color:var(--muted-fg)}
.chip b{color:var(--foreground);font-weight:600}
.theme-toggle{position:absolute;top:0;right:0;display:inline-flex;align-items:center;gap:8px;background:var(--card-2);color:var(--muted-fg);border:1px solid var(--border);border-radius:999px;padding:8px 14px;font:inherit;font-size:13px;cursor:pointer;box-shadow:var(--shadow)}
.theme-toggle:hover{color:var(--foreground);border-color:var(--primary)}
.grid-top{display:grid;grid-template-columns:360px 1fr;gap:20px;margin-bottom:24px}
@media(max-width:860px){.grid-top{grid-template-columns:1fr}}
.card{background:linear-gradient(180deg,var(--card-tint),var(--card-tint-2)),var(--card);border:1px solid var(--border);border-radius:var(--radius);box-shadow:var(--shadow)}
.summary-card{padding:22px;display:flex;align-items:center;gap:22px}
.donut-wrap{position:relative;width:148px;height:148px;flex:0 0 auto}
.donut-wrap .center{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center}
.donut-wrap .pct{font-size:30px;font-weight:700;line-height:1}
.donut-wrap .pct-label{font-size:10px;color:var(--muted-fg);text-transform:uppercase;letter-spacing:.12em;margin-top:4px}
.legend{display:flex;flex-direction:column;gap:9px;flex:1 1 auto;min-width:0}
.legend .row{display:flex;align-items:center;gap:10px;font-size:13.5px}
.legend .dot{width:11px;height:11px;border-radius:3px;flex:0 0 auto}
.legend .n{margin-left:auto;font-weight:600;font-variant-numeric:tabular-nums}
.kpis{padding:22px;display:grid;grid-template-columns:repeat(4,1fr);gap:14px;align-content:start}
@media(max-width:620px){.kpis{grid-template-columns:repeat(2,1fr)}}
.kpi{background:var(--card-2);border:1px solid var(--border);border-radius:10px;padding:14px 16px}
.kpi .val{font-size:26px;font-weight:700;font-variant-numeric:tabular-nums}
.kpi .lbl{font-size:11.5px;color:var(--muted-fg);text-transform:uppercase;letter-spacing:.1em;margin-top:2px}
.kpi.ok .val{color:var(--ok)}.kpi.warn .val{color:var(--warn)}.kpi.err .val{color:var(--err)}.kpi.total .val{color:var(--primary)}
.alert{display:flex;gap:12px;align-items:flex-start;padding:14px 18px;margin-bottom:22px;border-radius:12px;background:color-mix(in srgb,var(--warn) 12%,transparent);border:1px solid color-mix(in srgb,var(--warn) 35%,transparent);font-size:13.5px}
.alert svg{width:18px;height:18px;color:var(--warn);flex:0 0 auto;margin-top:1px}
.phase-card{margin-bottom:22px;overflow:hidden}
.phase-head{display:flex;align-items:center;gap:12px;padding:16px 20px;border-bottom:1px solid var(--border);background:var(--card-2)}
.phase-head .icon{width:20px;height:20px;color:var(--primary);flex:0 0 auto}
.phase-head h2{margin:0;font-size:15.5px;font-weight:650;letter-spacing:-.01em;border:none;padding:0;color:var(--foreground)}
.phase-head .count{margin-left:auto;font-size:12.5px;color:var(--muted-fg)}
table.grid{width:100%;border-collapse:collapse}
table.grid thead th{text-align:left;font-size:11.5px;text-transform:uppercase;letter-spacing:.08em;color:var(--muted-fg);padding:12px 20px;border-bottom:1px solid var(--border);background:transparent}
table.grid thead th.num,table.grid tbody td.num{text-align:right;font-variant-numeric:tabular-nums}
table.grid tbody td{padding:12px 20px;border-bottom:1px solid var(--border);font-size:13.5px;vertical-align:top}
table.grid tbody tr:last-child td{border-bottom:none}
table.grid tbody tr:hover{background:var(--hover)}
td .srv{font-weight:600}
td .sub2{color:var(--muted-fg);font-size:12px}
.master-tag{font-size:10px;text-transform:uppercase;letter-spacing:.1em;color:var(--primary);border:1px solid color-mix(in srgb,var(--primary) 40%,transparent);border-radius:5px;padding:1px 6px;margin-left:8px;vertical-align:middle}
.pill{display:inline-flex;align-items:center;gap:6px;font-size:12px;font-weight:600;padding:3px 10px;border-radius:999px;color:var(--pill);background:color-mix(in srgb,var(--pill) 16%,transparent);border:1px solid color-mix(in srgb,var(--pill) 35%,transparent)}
.pill::before{content:'';width:7px;height:7px;border-radius:50%;background:var(--pill)}
.pill.done{--pill:var(--ok)}.pill.running{--pill:var(--info)}.pill.failed{--pill:var(--err)}
.pill.pending{--pill:var(--muted)}.pill.skipped{--pill:var(--muted)}.pill.reboot{--pill:var(--warn)}
.ok-txt{color:var(--ok)}.warn-txt{color:var(--warn)}.muted-txt{color:var(--muted-fg)}
.footer{color:var(--muted-fg);font-size:12px;text-align:center;margin-top:26px}
.footer a{color:inherit}
/* ---- ContentDatabase inventory report (Export-SPSUpdateDbReport) ---- */
.meta{color:var(--muted-fg);font-size:12px;margin-bottom:16px}
.summary{background:var(--card-2);border:1px solid var(--border);border-left:4px solid var(--primary);border-radius:var(--radius);padding:16px;margin-bottom:12px}
.summary h3{color:var(--foreground);font-size:14px;margin:0 0 10px}
.cards{display:flex;flex-wrap:wrap;gap:12px}
.cards .card{padding:12px 16px;min-width:120px}
.card-value{font-size:24px;font-weight:700;color:var(--primary)}
.card-label{font-size:12px;color:var(--muted-fg)}
.card-sub{font-size:11px;color:var(--muted-fg);margin-top:2px}
.dist{margin-top:14px}
.dist-row{display:flex;align-items:center;gap:10px;margin:6px 0;font-size:12px}
.dist-name{width:90px;color:var(--foreground);font-weight:600}
.dist-track{flex:1;background:var(--card);border:1px solid var(--border);border-radius:4px;height:16px;overflow:hidden}
.dist-fill{background:var(--primary);height:100%}
.dist-val{width:170px;text-align:right;color:var(--muted-fg)}
.controls{display:flex;justify-content:space-between;align-items:center;margin:12px 0;flex-wrap:wrap;gap:8px}
.search{padding:6px 10px;border:1px solid var(--border);border-radius:4px;font-size:13px;width:280px;max-width:100%;background:var(--card);color:var(--foreground)}
.pager{display:flex;gap:8px;align-items:center;font-size:12px}
.pager button{padding:4px 10px;border:1px solid var(--border);background:var(--card-2);color:var(--foreground);border-radius:4px;cursor:pointer}
.pager button:disabled{opacity:.4;cursor:default}
.badge{display:inline-block;padding:2px 8px;border-radius:10px;font-size:11px;font-weight:600;color:#fff}
.badge.Pending{background:var(--muted)}.badge.Running{background:var(--info)}.badge.Done{background:var(--ok)}
.badge.Failed{background:var(--err)}.badge.Warning{background:var(--warn);color:#222}.badge.Skipped{background:var(--muted)}
table:not(.grid){border-collapse:collapse;width:100%;font-size:12px}
table:not(.grid) thead th{text-align:left;padding:8px 10px;border-bottom:1px solid var(--border);color:var(--muted-fg);background:var(--card-2);position:sticky;top:0;cursor:pointer}
table:not(.grid) tbody td{padding:7px 10px;border-bottom:1px solid var(--border);vertical-align:top}
table:not(.grid) td.num,table:not(.grid) th.num{text-align:right;font-variant-numeric:tabular-nums}
table:not(.grid) tbody tr:nth-child(even){background:var(--hover)}
'@

    $refreshTag = if ($RefreshSeconds -gt 0) { "<meta http-equiv=`"refresh`" content=`"$RefreshSeconds`">" } else { '' }
    return "<!DOCTYPE html><html lang=`"en`" data-theme=`"dark`"><head><meta charset=`"utf-8`"><meta name=`"viewport`" content=`"width=device-width, initial-scale=1`">$refreshTag<title>$Title</title><style>$css</style></head><body><div class=`"wrap`">"
}
