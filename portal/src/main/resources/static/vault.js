(function () {
  'use strict';
  document.addEventListener('DOMContentLoaded', function () {
    var wire = function (id, handler) {
      var node = document.getElementById(id);
      if (node && window.Control) node.onclick = handler;
    };
    wire('create', function () { window.Control.create(); });
    wire('find', function () { window.Control.find(); });
    wire('approve', function () { window.Control.approve(); });
  });
})();
