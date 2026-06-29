function Get-SPSReportCardHtml {
    <#
        .SYNOPSIS
        Builds the HTML for one summary "card" (a big number plus a label).
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        $Value,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Label,

        [Parameter()]
        [System.String]
        $Sub = '',

        [Parameter()]
        [ValidateSet('', 'accent')]
        [System.String]
        $Tone = ''
    )

    $encValue = ConvertTo-SPSHtmlEncoded -Value ("$Value")
    $encLabel = ConvertTo-SPSHtmlEncoded -Value $Label
    $encSub = ConvertTo-SPSHtmlEncoded -Value $Sub
    $toneClass = if ([string]::IsNullOrEmpty($Tone)) { '' } else { " $Tone" }
    $subHtml = if ([string]::IsNullOrEmpty($encSub)) { '' } else { "<div class=`"card-sub`">$encSub</div>" }
    return "<div class=`"card$toneClass`"><div class=`"card-value`">$encValue</div><div class=`"card-label`">$encLabel</div>$subHtml</div>"
}

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

function Get-SPSReportDistributionHtml {
    <#
        .SYNOPSIS
        Builds the per-sequence distribution bars (count / MB / percentage).
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object[]]
        $Sequences
    )

    $rowsHtml = ''
    foreach ($seq in $Sequences) {
        $pct = [double]$seq.Percent
        $encName = ConvertTo-SPSHtmlEncoded -Value $seq.Name
        $valText = '{0} db &middot; {1:N0} MB &middot; {2:N1}%' -f $seq.Count, $seq.SizeMB, $pct
        $rowsHtml += "<div class=`"dist-row`"><div class=`"dist-name`">$encName</div>" +
        "<div class=`"dist-track`"><div class=`"dist-fill`" style=`"width:$([System.Math]::Round($pct,1))%`"></div></div>" +
        "<div class=`"dist-val`">$valText</div></div>"
    }
    return "<div class=`"dist`">$rowsHtml</div>"
}

function Get-SPSReportHtmlScript {
    <#
        .SYNOPSIS
        Returns the vanilla-JavaScript block that renders the interactive table.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param ()

    $js = @'
(function(){
  var node = document.getElementById('spsReportData');
  var data = JSON.parse(node.textContent || node.innerText);
  var cols = data.columns || [];
  var rows = data.rows || [];
  var pageSize = 50, page = 1, sortField = null, sortDir = 1, view = rows;
  var search = document.getElementById('spsSearch');
  var thead = document.getElementById('spsThead');
  var tbody = document.getElementById('spsTbody');
  var info = document.getElementById('spsPageInfo');
  var prev = document.getElementById('spsPrev');
  var next = document.getElementById('spsNext');

  function isNum(c){ return c.type === 'num'; }
  function buildHead(){
    var tr = document.createElement('tr');
    cols.forEach(function(c){
      var th = document.createElement('th');
      if (isNum(c)) { th.className = 'num'; }
      th.textContent = c.label + '  \u2195';
      th.addEventListener('click', function(){
        if (sortField === c.field) { sortDir = -sortDir; } else { sortField = c.field; sortDir = 1; }
        applySort(); render();
      });
      tr.appendChild(th);
    });
    thead.appendChild(tr);
  }
  function applyFilter(){
    var q = (search.value || '').trim().toLowerCase();
    if (!q) { view = rows; }
    else {
      view = rows.filter(function(r){
        return cols.some(function(c){
          var v = r[c.field];
          return v != null && String(v).toLowerCase().indexOf(q) !== -1;
        });
      });
    }
    page = 1;
  }
  function applySort(){
    if (!sortField) { return; }
    var col = null;
    cols.forEach(function(c){ if (c.field === sortField) { col = c; } });
    var numeric = col && isNum(col);
    view = view.slice().sort(function(a,b){
      var x = a[sortField], y = b[sortField];
      if (numeric) {
        x = parseFloat(x); y = parseFloat(y);
        if (isNaN(x)) { x = -Infinity; } if (isNaN(y)) { y = -Infinity; }
        return (x - y) * sortDir;
      }
      x = x == null ? '' : String(x).toLowerCase();
      y = y == null ? '' : String(y).toLowerCase();
      if (x < y) { return -1 * sortDir; }
      if (x > y) { return 1 * sortDir; }
      return 0;
    });
  }
  function render(){
    var totalPages = Math.max(1, Math.ceil(view.length / pageSize));
    if (page > totalPages) { page = totalPages; }
    var start = (page - 1) * pageSize;
    var slice = view.slice(start, start + pageSize);
    tbody.innerHTML = '';
    slice.forEach(function(r){
      var tr = document.createElement('tr');
      cols.forEach(function(c){
        var td = document.createElement('td');
        if (isNum(c)) { td.className = 'num'; }
        td.textContent = r[c.field] == null ? '' : r[c.field];
        tr.appendChild(td);
      });
      tbody.appendChild(tr);
    });
    info.textContent = view.length + ' rows \u00b7 page ' + page + '/' + totalPages;
    prev.disabled = page <= 1;
    next.disabled = page >= totalPages;
  }
  search.addEventListener('input', function(){ applyFilter(); applySort(); render(); });
  prev.addEventListener('click', function(){ if (page > 1) { page--; render(); } });
  next.addEventListener('click', function(){ page++; render(); });
  buildHead(); render();
})();
'@

    return "<script>$js</script>"
}
