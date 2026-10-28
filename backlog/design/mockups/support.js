// Minimal offline runtime for the Instrument mockups.
//
// The mockups were authored as Design Components: static markup, `{{path}}` holes, `<sc-for>`
// repetitions, and one `renderVals()` class. This file expands them in a plain browser so a page
// can be opened from disk or captured headlessly. It supports exactly what the mockups use.
(function () {
    window.DCLogic = class {
        constructor() { this.props = {}; this.state = {}; }
        setState() {}
    };

    function lookup(scope, path) {
        return path.trim().split('.').reduce(function (o, k) { return o == null ? undefined : o[k]; }, scope);
    }

    function fill(text, scope) {
        return text.replace(/\{\{\s*([^}]+?)\s*\}\}/g, function (_, p) {
            var v = lookup(scope, p);
            return v == null ? '' : String(v);
        });
    }

    function expand(node, scope) {
        if (node.nodeType === 3) {
            if (node.nodeValue.indexOf('{{') >= 0) node.nodeValue = fill(node.nodeValue, scope);
            return;
        }
        if (node.nodeType !== 1) return;

        if (node.tagName === 'SC-FOR') {
            var list = lookup(scope, node.getAttribute('list').replace(/[{}]/g, '')) || [];
            var name = node.getAttribute('as');
            var frag = document.createDocumentFragment();
            list.forEach(function (item, index) {
                var inner = Object.create(scope);
                inner[name] = item;
                inner.$index = index;
                Array.prototype.forEach.call(node.childNodes, function (child) {
                    var copy = child.cloneNode(true);
                    frag.appendChild(copy);
                    expand(copy, inner);
                });
            });
            node.replaceWith(frag);
            return;
        }

        Array.prototype.forEach.call(node.attributes, function (a) {
            if (a.value.indexOf('{{') >= 0) a.value = fill(a.value, scope);
        });
        Array.prototype.slice.call(node.childNodes).forEach(function (child) { expand(child, scope); });
    }

    document.addEventListener('DOMContentLoaded', function () {
        var script = document.querySelector('script[data-dc-script]');
        var root = document.querySelector('x-dc');
        if (!script || !root) return;
        var Component = new Function('DCLogic', script.textContent + '\nreturn Component;')(window.DCLogic);
        expand(root, new Component().renderVals() || {});
    });
})();
