(function () {
  'use strict';
  window.Comms = {
    note: function (caseId, text) {
      return fetch('/api/zt01/case/' + caseId + '/claim', {
        method: 'POST',
        credentials: 'same-origin',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ method: 'giftcard', reference: text })
      });
    }
  };
})();
