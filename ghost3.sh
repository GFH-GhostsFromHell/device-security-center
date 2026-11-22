#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

w(){ mkdir -p "$(dirname "$1")"; cat > "$1"; }

w portal/src/main/resources/static/zt01.css <<'EOF'
:root { color-scheme: dark; --bg:#0b0d10; --panel:#0f1216; --line:#232a33; --ink:#d7dbe0; --mute:#7d8894; --accent:#E23A3A; }
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--ink); font:14px/1.6 ui-monospace,Consolas,monospace; }
header { display:flex; gap:12px; align-items:center; padding:14px 22px; border-bottom:1px solid var(--line); }
header .mark { color:var(--accent); font-weight:700; letter-spacing:.14em; }
header .division { color:var(--mute); font-size:10.5px; letter-spacing:.16em; text-transform:uppercase; }
header .spacer { flex:1; }
main { max-width:860px; margin:0 auto; padding:28px 22px 80px; }
h1 { font-size:20px; margin:0 0 4px; }
h2 { font-size:13px; letter-spacing:.18em; text-transform:uppercase; color:var(--mute); margin:34px 0 12px; }
.card { border:1px solid var(--line); border-radius:4px; background:var(--panel); padding:18px; }
dl { display:grid; grid-template-columns:auto 1fr; gap:8px 20px; margin:0; }
dt { color:var(--mute); font-size:10.5px; letter-spacing:.12em; text-transform:uppercase; padding-top:3px; }
dd { margin:0; }
code, .addr { background:#171c22; padding:2px 6px; border-radius:3px; font-size:12px; word-break:break-all; }
button { background:var(--accent); color:#fff; border:0; padding:9px 18px; border-radius:3px; font:inherit; font-size:12px; letter-spacing:.06em; text-transform:uppercase; cursor:pointer; }
button.ghost { background:transparent; color:var(--ink); border:1px solid var(--line); }
input { background:var(--panel); border:1px solid var(--line); color:var(--ink); font:inherit; font-size:13px; padding:9px; border-radius:3px; width:100%; }
label.field { display:block; margin-bottom:14px; }
label.field span { display:block; color:var(--mute); font-size:10.5px; letter-spacing:.12em; text-transform:uppercase; margin-bottom:6px; }
.row { display:flex; gap:10px; align-items:center; flex-wrap:wrap; }
.grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(180px,1fr)); gap:14px; }
.pill { display:inline-block; padding:2px 8px; border-radius:20px; font-size:10.5px; letter-spacing:.1em; text-transform:uppercase; border:1px solid var(--line); color:var(--mute); }
.big { font-size:30px; color:var(--accent); letter-spacing:.06em; }
.mute { color:var(--mute); font-size:12px; }
.error { color:var(--accent); font-size:12.5px; min-height:18px; }
table { width:100%; border-collapse:collapse; font-size:12px; }
th { text-align:left; color:var(--mute); font-size:10.5px; letter-spacing:.12em; text-transform:uppercase; padding:6px 8px; border-bottom:1px solid var(--line); }
td { padding:6px 8px; border-bottom:1px solid #161b21; }
EOF

w portal/src/main/resources/static/ghost.html <<'EOF'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ZT-01 // Control</title>
  <link rel="stylesheet" href="/zt01.css">
</head>
<body>
  <header><span class="mark">ZT-01</span><span class="division">Zero Trust Security Division</span><span class="spacer"></span></header>
  <main>
    <h1>Case control</h1>
    <p class="mute">Open a case, price it, verify the payment, release the key.</p>
    <h2>Open a case</h2>
    <div class="card">
      <div class="grid">
        <label class="field"><span>Label</span><input id="label" placeholder="workstation-04"></label>
        <label class="field"><span>Window (hours)</span><input id="hours" type="number" min="1" max="720" value="24"></label>
        <label class="field"><span>Amount (sats)</span><input id="price" type="number" min="0" value="150000"></label>
        <label class="field"><span>Pay address</span><input id="address" placeholder="bc1q..."></label>
      </div>
      <div class="row"><button id="create">Open case</button><span class="error" id="createError"></span></div>
    </div>
    <h2>Look up a case</h2>
    <div class="card"><div class="row">
      <input id="lookup" placeholder="case id" style="flex:1"><button class="ghost" id="find">Load</button>
    </div></div>
    <div id="caseArea"></div>
    <h2>Release</h2>
    <div class="card">
      <div class="grid">
        <label class="field"><span>Case id</span><input id="releaseCase"></label>
        <label class="field"><span>Wrapped key (base64)</span><input id="releaseKey"></label>
        <label class="field"><span>Window (minutes)</span><input id="releaseWindow" type="number" min="1" value="15"></label>
      </div>
      <div class="row"><button id="approve">Approve release</button><span class="error" id="releaseError"></span></div>
    </div>
  </main>
  <script src="/vault.js">
