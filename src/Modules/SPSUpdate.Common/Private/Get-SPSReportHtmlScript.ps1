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
