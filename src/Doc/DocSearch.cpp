#include "pch.h"
#include "Doc/DocSearch.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // The reader types a name and reaches it; everything the box needs is the index the page
    // appends below, so the page keeps working from a file:// URL and asks for nothing.
    constexpr std::string_view SEARCH_SCRIPT = R"JS((function (rows) {
    "use strict";

    var nav = document.querySelector(".site-nav");
    if (!nav || !rows.length)
        return;

    var KINDS = {
        n: "namespace", s: "struct", i: "interface", e: "enum",
        c: "const", a: "alias", t: "attr", f: "func", h: "section",
        v: "field", k: "case"
    };
    var LIMIT = 30;

    // A row is "kind|name|anchor|summary". The summary is the remainder of the row, so it
    // is the only field allowed to hold the separator.
    var items = [];
    for (var r = 0; r < rows.length; r++) {
        var row = rows[r];
        var kindEnd = row.indexOf("|");
        var nameEnd = row.indexOf("|", kindEnd + 1);
        var anchorEnd = row.indexOf("|", nameEnd + 1);
        var name = row.slice(kindEnd + 1, nameEnd);
        items.push({
            kind: KINDS[row.slice(0, kindEnd)] || "func",
            name: name,
            lower: name.toLowerCase(),
            anchor: row.slice(nameEnd + 1, anchorEnd),
            detail: row.slice(anchorEnd + 1)
        });
    }

    // Where a name really starts: after a qualifier, and at every word boundary inside it.
    function isBoundary(name, at) {
        if (!at)
            return true;
        var previous = name.charAt(at - 1);
        if (previous === "." || previous === "_")
            return true;
        return previous === previous.toLowerCase() && name.charAt(at) !== name.charAt(at).toLowerCase();
    }

    // An exact name wins, then one starting on a boundary, then any substring, then the
    // characters merely in order. A shorter name breaks a tie, so "add" stays above
    // "addRange" for the same query.
    function rank(item, query) {
        var lower = item.lower;
        var positions = [];
        var value;
        var at = lower.indexOf(query);
        if (at >= 0) {
            value = lower.length === query.length ? 1000 : (isBoundary(item.name, at) ? 800 : 600);
            value -= at * 0.5;
            for (var c = 0; c < query.length; c++)
                positions.push(at + c);
        } else {
            var typed = 0;
            var run = 0;
            value = 300;
            for (var i = 0; i < lower.length && typed < query.length; i++) {
                if (lower.charAt(i) !== query.charAt(typed)) {
                    run = 0;
                    continue;
                }
                run++;
                value += run + (isBoundary(item.name, i) ? 6 : 0);
                positions.push(i);
                typed++;
            }
            if (typed < query.length)
                return null;
            value -= (positions[positions.length - 1] - positions[0]) * 0.4;
        }
        return { value: value - lower.length * 0.2, positions: positions, item: item };
    }

    function search(query) {
        var found = [];
        for (var i = 0; i < items.length; i++) {
            var hit = rank(items[i], query);
            if (hit)
                found.push(hit);
        }
        found.sort(function (left, right) {
            if (left.value !== right.value)
                return right.value - left.value;
            if (left.item.name === right.item.name)
                return 0;
            return left.item.name < right.item.name ? -1 : 1;
        });
        return found;
    }

    function escape(text) {
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function highlight(name, positions) {
        var html = "";
        var done = 0;
        var at = 0;
        while (at < positions.length) {
            var start = positions[at];
            var end = start + 1;
            while (at + 1 < positions.length && positions[at + 1] === end) {
                end++;
                at++;
            }
            html += escape(name.slice(done, start)) + "<mark>" + escape(name.slice(start, end)) + "</mark>";
            done = end;
            at++;
        }
        return html + escape(name.slice(done));
    }

    var form = document.createElement("form");
    form.className = "site-search";
    form.setAttribute("role", "search");

    var input = document.createElement("input");
    input.type = "search";
    input.className = "site-search-input";
    input.placeholder = "Search this page";
    input.setAttribute("aria-label", "Search this page");
    input.setAttribute("aria-controls", "search-panel");
    input.setAttribute("aria-expanded", "false");
    input.setAttribute("autocomplete", "off");
    input.setAttribute("spellcheck", "false");

    var shortcut = document.createElement("kbd");
    shortcut.className = "site-search-shortcut";
    shortcut.textContent = "/";

    var panel = document.createElement("div");
    panel.id = "search-panel";
    panel.className = "search-panel";
    panel.setAttribute("role", "listbox");
    panel.hidden = true;

    form.appendChild(input);
    form.appendChild(shortcut);
    form.appendChild(panel);
    nav.insertBefore(form, nav.querySelector(".site-links"));

    var hits = [];
    var current = -1;

    function close() {
        panel.hidden = true;
        input.setAttribute("aria-expanded", "false");
    }

    function select(at) {
        var rendered = panel.querySelectorAll(".search-hit");
        for (var i = 0; i < rendered.length; i++) {
            var isCurrent = i === at;
            rendered[i].classList.toggle("is-current", isCurrent);
            rendered[i].setAttribute("aria-selected", isCurrent ? "true" : "false");
            if (isCurrent)
                rendered[i].scrollIntoView({ block: "nearest" });
        }
        current = at;
    }

    function render() {
        var query = input.value.trim().toLowerCase();
        if (!query) {
            hits = [];
            close();
            return;
        }

        var found = search(query);
        hits = found.slice(0, LIMIT);

        var html = "";
        for (var i = 0; i < hits.length; i++) {
            var item = hits[i].item;
            html += '<a class="search-hit search-hit-' + item.kind + '" role="option" href="#' + item.anchor + '">' +
                '<span class="kind-chip kind-' + item.kind + '">' + item.kind + "</span>" +
                '<span class="search-hit-name">' + highlight(item.name, hits[i].positions) + "</span>" +
                (item.detail ? '<span class="search-hit-detail">' + escape(item.detail) + "</span>" : "");
            html += "</a>";
        }
        if (!hits.length)
            html = '<p class="search-none">No match on this page.</p>';
        else if (found.length > hits.length)
            html += '<p class="search-more">' + hits.length + " of " + found.length + " matches</p>";

        panel.innerHTML = html;
        panel.hidden = false;
        input.setAttribute("aria-expanded", "true");
        select(hits.length ? 0 : -1);
    }

    function open(at) {
        if (at < 0 || at >= hits.length)
            return;
        window.location.hash = "#" + hits[at].item.anchor;
        close();
    }

    input.addEventListener("input", render);
    input.addEventListener("focus", render);

    input.addEventListener("keydown", function (event) {
        if (event.key === "ArrowDown")
            select(Math.min(current + 1, hits.length - 1));
        else if (event.key === "ArrowUp")
            select(Math.max(current - 1, 0));
        else if (event.key === "Enter")
            open(current);
        else if (event.key === "Escape") {
            input.value = "";
            close();
            input.blur();
        } else
            return;
        event.preventDefault();
    });

    form.addEventListener("submit", function (event) {
        event.preventDefault();
        open(current);
    });

    panel.addEventListener("click", function () {
        close();
    });

    document.addEventListener("click", function (event) {
        if (!form.contains(event.target))
            close();
    });

    // The box is reachable without the mouse from anywhere on the page, and the browser's
    // own find stays available: "/" is only taken when nothing else is being typed into.
    document.addEventListener("keydown", function (event) {
        if (event.defaultPrevented || event.altKey)
            return;
        var active = document.activeElement;
        var typing = active && (active.tagName === "INPUT" || active.tagName === "TEXTAREA" || active.isContentEditable);
        var takes = (event.key === "/" && !typing) || ((event.ctrlKey || event.metaKey) && event.key === "k");
        if (!takes)
            return;
        event.preventDefault();
        input.focus();
        input.select();
    });
})
)JS";

    Utf8 escapeScriptString(const std::string_view text)
    {
        Utf8 result;
        result.reserve(text.size() + 8);
        for (const char c : text)
        {
            switch (c)
            {
                case '"':
                    result += "\\\"";
                    break;
                case '\\':
                    result += "\\\\";
                    break;
                case '\n':
                case '\r':
                case '\t':
                    result += ' ';
                    break;
                // The index lives inside an inline element, where the HTML parser still looks for
                // the end of the script before the language does.
                case '<':
                    result += "\\u003C";
                    break;
                default:
                    result += c;
                    break;
            }
        }
        return result;
    }
}

char DocSearch::kindLetter(const DocItemKind kind)
{
    switch (kind)
    {
        case DocItemKind::Namespace:
            return 'n';
        case DocItemKind::Struct:
            return 's';
        case DocItemKind::Interface:
            return 'i';
        case DocItemKind::Enum:
            return 'e';
        case DocItemKind::Constant:
            return 'c';
        case DocItemKind::Alias:
            return 'a';
        case DocItemKind::Attribute:
            return 't';
        case DocItemKind::Function:
            return 'f';
    }
    SWC_UNREACHABLE();
}

// A result row shows one line of prose under the name, so the markup a summary carries for the
// page is dropped rather than displayed: the row is text, and a long one is cut.
Utf8 DocSearch::summarize(const std::string_view markdown)
{
    Utf8   result;
    size_t index = 0;
    while (index < markdown.size() && (markdown[index] == '#' || markdown[index] == '>' || markdown[index] == '-' || markdown[index] == ' '))
        index++;

    bool wasSpace = false;
    while (index < markdown.size())
    {
        const char c = markdown[index];
        if (c == '`' || c == '*' || c == '_')
        {
            index++;
            continue;
        }

        // A link shows its text, and a symbol reference shows the symbol.
        if (c == '[')
        {
            const bool   isReference = markdown.compare(index, 2, "[[") == 0;
            const size_t markerSize  = isReference ? 2 : 1;
            const size_t end         = markdown.find(isReference ? "]]" : "]", index);
            if (end != std::string_view::npos)
            {
                result.append(markdown.substr(index + markerSize, end - index - markerSize));
                index = end + markerSize;
                if (index < markdown.size() && markdown[index] == '(')
                {
                    const size_t target = markdown.find(')', index);
                    index               = target == std::string_view::npos ? markdown.size() : target + 1;
                }
                wasSpace = false;
                continue;
            }
        }

        const bool isSpace = c == ' ' || c == '\t' || c == '\r' || c == '\n';
        if (!isSpace || !wasSpace)
            result += isSpace ? ' ' : c;
        wasSpace = isSpace;
        index++;
    }

    return Utf8Helper::truncate(Utf8Helper::trim(result), {.maxChars = 110});
}

// Guides and prose pages are documents rather than symbol lists, so their headings are what a
// reader looks for. They are read back from the rendered page, which is where an anchor is
// final: nothing else has to agree with the renderer about how one is spelled.
void DocSearch::collectHeadings(std::vector<DocSearchEntry>& outEntries, const std::string_view html)
{
    constexpr std::string_view idAttribute = " id=\"";

    size_t index = 0;
    while ((index = html.find("<h", index)) != std::string_view::npos)
    {
        index += 2;
        if (index >= html.size() || html[index] < '1' || html[index] > '6')
            continue;

        const char level = html[index++];
        if (html.compare(index, idAttribute.size(), idAttribute) != 0)
            continue;

        index += idAttribute.size();
        const size_t anchorEnd = html.find('"', index);
        if (anchorEnd == std::string_view::npos)
            break;
        const std::string_view anchor = html.substr(index, anchorEnd - index);

        const size_t textStart = html.find('>', anchorEnd);
        if (textStart == std::string_view::npos)
            break;
        const Utf8   closing = std::format("</h{}>", level);
        const size_t textEnd = html.find(closing.view(), textStart);
        if (textEnd == std::string_view::npos)
            break;

        Utf8 title;
        for (size_t at = textStart + 1; at < textEnd; at++)
        {
            if (html[at] == '<')
            {
                const size_t tagEnd = html.find('>', at);
                at                  = tagEnd == std::string_view::npos ? textEnd : tagEnd;
                continue;
            }
            title += html[at];
        }

        title.replace_loop("&amp;", "&");
        title.replace_loop("&lt;", "<");
        title.replace_loop("&gt;", ">");
        title.replace_loop("&quot;", "\"");
        title.replace_loop("&#39;", "'");
        title.trim();
        if (!title.empty() && !anchor.empty())
            outEntries.push_back({.name = std::move(title), .anchor = Utf8(anchor), .kind = 'h'});

        index = textEnd;
    }
}

Utf8 DocSearch::script(const DocPageOptions& options, const std::span<const DocSearchEntry> entries)
{
    // A landing page is read whole, so a box searching its six headings costs the reader a
    // control and saves them nothing. The script only appears where scrolling stops working.
    constexpr size_t minEntries = 8;

    if (!options.hasSearch || entries.size() < minEntries)
        return {};

    Utf8   result   = "<script>\n";
    size_t capacity = SEARCH_SCRIPT.size() + 32;
    for (const DocSearchEntry& entry : entries)
        capacity += entry.name.size() + entry.anchor.size() + entry.detail.size() + 8;
    result.reserve(capacity);
    result.append(SEARCH_SCRIPT);
    result += "([\n";
    for (const DocSearchEntry& entry : entries)
    {
        SWC_ASSERT(!entry.name.contains("|") && !entry.anchor.contains("|"));
        result.append(std::format("\"{}|{}|{}|{}\",\n", entry.kind, escapeScriptString(entry.name), escapeScriptString(entry.anchor), escapeScriptString(entry.detail)));
    }
    result += "]);\n</script>\n";
    return result;
}

SWC_END_NAMESPACE();
