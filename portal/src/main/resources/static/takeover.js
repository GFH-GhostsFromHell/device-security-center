(function () {
  'use strict';

  function api(path, options) {
    return fetch('/api/zt01' + path, Object.assign({ credentials: 'same-origin' }, options))
      .then(function (response) {
        return response.text().then(function (text) {
          var body = text ? JSON.parse(text) : {};
          if (!response.ok) throw new Error(body.message || body.error || response.status);
          return body;
        });
      });
  }

  function show(id, message) {
    var node = document.getElementById(id);
    if (node) node.textContent = message;
  }

  function clock(deadline) {
    var target = new Date(deadline).getTime();
    var node = document.getElementById('clock');
    if (!node) return;
    setInterval(function () {
      var left = Math.max(0, target - Date.now());
      var s = Math.floor(left / 1000);
      var d = Math.floor(s / 86400); s -= d * 86400;
      var h = Math.floor(s / 3600); s -= h * 3600;
      var m = Math.floor(s / 60); s -= m * 60;
      var pad = function (n) { return String(n).padStart(2, '0'); };
      node.textContent = (d ? d + ':' : '') + pad(h) + ':' + pad(m) + ':' + pad(s);
    }, 1000);
  }

  function renderCase(data) {
    var area = document.getElementById('caseArea');
    if (!area) return;
    var claims = (data.claims || []).map(function (c) {
      return '<tr><td>' + c.method + '</td><td><code>' + c.reference + '</code></td>' +
        '<td>' + c.confirmations + '</td><td>' + (c.verified ? 'yes' : 'no') + '</td></tr>';
    }).join('');
    area.innerHTML =
      '<h2>Case ' + data.case_id + '</h2><div class="card"><dl>' +
      '<dt>State</dt><dd><span class="pill">' + data.state + '</span></dd>' +
      '<dt>Label</dt><dd>' + (data.label || '') + '</dd>' +
      '<dt>Amount</dt><dd>' + data.price_sats + ' sats</dd>' +
      '<dt>Address</dt><dd><span class="addr">' + (data.pay_address || '-') + '</span></dd>' +
      '<dt>Deadline</dt><dd>' + (data.deadline_at || '-') + '</dd></dl></div>' +
      '<h2>Claims</h2><div class="card"><table><thead><tr><th>Method</th><th>Reference</th><th>Conf</th><th>Verified</th></tr></thead>' +
      '<tbody>' + (claims || '<tr><td colspan="4" class="mute">none</td></tr>') + '</tbody></table>' +
      '<div class="row" style="margin-top:12px"><button id="verify">Verify</button></div></div>';

    var verify = document.getElementById('verify');
    if (verify) verify.onclick = function () {
      api('/case/' + data.case_id + '/verify', { method: 'POST' }).then(renderCase)
        .catch(function (e) { alert(e.message); });
    };
  }

  window.Control = {
    create: function () {
      show('createError', '');
      api('/case', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          label: document.getElementById('label').value,
          windowHours: Number(document.getElementById('hours').value),
          priceSats: Number(document.getElementById('price').value),
          address: document.getElementById('address').value
        })
      }).then(function (data) {
        document.getElementById('releaseCase').value = data.case_id;
        renderCase(data);
      }).catch(function (e) { show('createError', e.message); });
    },
    find: function () {
      var id = document.getElementById('lookup').value.trim();
      if (id) api('/case/' + id).then(renderCase).catch(function (e) { alert(e.message); });
    },
    approve: function () {
      show('releaseError', '');
      var id = document.getElementById('releaseCase').value.trim();
      api('/release/' + id, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          wrappedKey: document.getElementById('releaseKey').value.trim(),
          windowMinutes: Number(document.getElementById('releaseWindow').value)
        })
      }).then(function () { show('releaseError', 'approved'); })
        .catch(function (e) { show('releaseError', e.message); });
    }
  };

  window.Takeover = {
    boot: function () {
      var id = new URLSearchParams(location.search).get('case');
      if (!id) { show('state', 'no case in the URL'); return; }
      document.getElementById('caseId').textContent = 'CASE ' + id;
      api('/case/' + id).then(function (data) {
        document.getElementById('amount').textContent = data.price_sats + ' sats';
        document.getElementById('address').textContent = data.pay_address || '-';
        show('state', data.state);
        if (data.deadline_at) clock(data.deadline_at);
        document.getElementById('copy').onclick = function () {
          navigator.clipboard.writeText(data.pay_address || '');
        };
        document.getElementById('claim').onclick = function () {
          api('/case/' + id + '/claim', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ method: 'giftcard', reference: 'PENDING', amountSats: 0 })
          }).then(function () { show('state', 'claim lodged'); })
            .catch(function (e) { show('error', e.message); });
        };
      }).catch(function (e) { show('error', e.message); });
    }
  };
})();
