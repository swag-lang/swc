#include "pch.h"
#include "Doc/DocMarkdown.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/SyntaxColor.h"

SWC_BEGIN_NAMESPACE();

Utf8 DocMarkdown::makeAnchor(const std::string_view value)
{
    Utf8 result;
    result.reserve(value.size() + 1);
    for (const char c : value)
    {
        if (std::isalnum(static_cast<unsigned char>(c)) || c == '_' || c == '-')
            result += c;
        else
            result += '_';
    }
    if (result.empty())
        result = "_";
    if (std::isdigit(static_cast<unsigned char>(result.front())))
        result.insert(result.begin(), '_');
    return result;
}

namespace
{
    Utf8 resolveReference(const DocRenderContext& renderCtx, const std::string_view name)
    {
        if (renderCtx.references)
        {
            const auto it = renderCtx.references->find(Utf8(name));
            if (it != renderCtx.references->end())
                return std::format("<a href=\"#{}\">{}</a>", it->second, Utf8Helper::escapeHtml(name));

            if (!renderCtx.moduleName.empty() && name.starts_with(renderCtx.moduleName) && name.size() > renderCtx.moduleName.size() && name[renderCtx.moduleName.size()] == '.')
            {
                const auto shortIt = renderCtx.references->find(Utf8(name.substr(renderCtx.moduleName.size() + 1)));
                if (shortIt != renderCtx.references->end())
                    return std::format("<a href=\"#{}\">{}</a>", shortIt->second, Utf8Helper::escapeHtml(name));
            }
        }

        if (renderCtx.externalReferences)
        {
            const auto it = renderCtx.externalReferences->find(Utf8(name));
            if (it != renderCtx.externalReferences->end())
                return std::format("<a href=\"{}\">{}</a>", Utf8Helper::escapeHtml(it->second, true), Utf8Helper::escapeHtml(name));
        }

        if (name.starts_with("Swag."))
        {
            const Utf8 anchor = DocMarkdown::makeAnchor(name);
            return std::format("<a href=\"swag.runtime.html#{}\">{}</a>", anchor, Utf8Helper::escapeHtml(name));
        }

        const size_t separator = name.find('.');
        if (separator != std::string_view::npos && renderCtx.externalModules)
        {
            const auto it = renderCtx.externalModules->find(Utf8(name.substr(0, separator)));
            if (it != renderCtx.externalModules->end())
                return std::format("<a href=\"{}#{}\">{}</a>", Utf8Helper::escapeHtml(it->second, true), DocMarkdown::makeAnchor(name), Utf8Helper::escapeHtml(name));
        }
        return {};
    }
}

Utf8 DocMarkdown::renderTypeName(const DocRenderContext& renderCtx, const std::string_view typeName)
{
    Utf8   result;
    size_t pos = 0;
    while (pos < typeName.size())
    {
        const char c = typeName[pos];
        if (!std::isalpha(static_cast<unsigned char>(c)) && c != '_')
        {
            result += Utf8Helper::escapeHtml(typeName.substr(pos, 1));
            pos++;
            continue;
        }

        size_t end = pos + 1;
        while (end < typeName.size())
        {
            const char tokenChar = typeName[end];
            if (!std::isalnum(static_cast<unsigned char>(tokenChar)) && tokenChar != '_' && tokenChar != '.')
                break;
            end++;
        }
        while (end > pos && typeName[end - 1] == '.')
            end--;

        const std::string_view token     = typeName.substr(pos, end - pos);
        const Utf8             reference = resolveReference(renderCtx, token);
        result += reference.empty() ? Utf8Helper::escapeHtml(token) : reference;
        pos = end;
    }
    return result;
}
namespace
{
    Utf8 renderInline(const DocRenderContext& renderCtx, std::string_view text);

    // A bare URL ends at the first character that cannot belong to it. Trailing sentence
    // punctuation is excluded so "see https://swag-lang.org." keeps its final period.
    size_t bareUrlLength(const std::string_view text)
    {
        if (!text.starts_with("http://") && !text.starts_with("https://"))
            return 0;

        size_t end = 0;
        while (end < text.size() && !std::isspace(static_cast<unsigned char>(text[end])) && text[end] != '<' && text[end] != '"' && text[end] != ')')
            end++;
        while (end && (text[end - 1] == '.' || text[end - 1] == ',' || text[end - 1] == ';' || text[end - 1] == ':' || text[end - 1] == '!' || text[end - 1] == '?'))
            end--;
        return end > 8 ? end : 0;
    }

    Utf8 renderInline(const DocRenderContext& renderCtx, const std::string_view text)
    {
        Utf8   result;
        size_t pos = 0;
        while (pos < text.size())
        {
            if (const size_t urlLength = bareUrlLength(text.substr(pos)))
            {
                const std::string_view url = text.substr(pos, urlLength);
                result.append(std::format("<a href=\"{}\">{}</a>", Utf8Helper::escapeHtml(url, true), Utf8Helper::escapeHtml(url)));
                pos += urlLength;
                continue;
            }

            if (text.substr(pos).starts_with("[["))
            {
                const size_t end = text.find("]]", pos + 2);
                if (end != std::string_view::npos)
                {
                    const std::string_view name = text.substr(pos + 2, end - pos - 2);
                    const Utf8             ref  = resolveReference(renderCtx, name);
                    if (!ref.empty())
                    {
                        result += ref;
                        pos = end + 2;
                        continue;
                    }
                }
            }

            if (text.substr(pos).starts_with("!["))
            {
                const size_t nameEnd = text.find(']', pos + 2);
                if (nameEnd != std::string_view::npos && nameEnd + 1 < text.size() && text[nameEnd + 1] == '(')
                {
                    const size_t linkEnd = text.find(')', nameEnd + 2);
                    if (linkEnd != std::string_view::npos)
                    {
                        const auto name = text.substr(pos + 2, nameEnd - pos - 2);
                        const auto link = text.substr(nameEnd + 2, linkEnd - nameEnd - 2);
                        result.append(std::format(R"(<img src="{}" alt="{}">)", Utf8Helper::escapeHtml(link, true), Utf8Helper::escapeHtml(name, true)));
                        pos = linkEnd + 1;
                        continue;
                    }
                }
            }

            if (text[pos] == '[')
            {
                const size_t nameEnd = text.find(']', pos + 1);
                if (nameEnd != std::string_view::npos && nameEnd + 1 < text.size() && text[nameEnd + 1] == '(')
                {
                    const size_t linkEnd = text.find(')', nameEnd + 2);
                    if (linkEnd != std::string_view::npos)
                    {
                        const auto name = text.substr(pos + 1, nameEnd - pos - 1);
                        const auto link = text.substr(nameEnd + 2, linkEnd - nameEnd - 2);
                        result.append(std::format("<a href=\"{}\">{}</a>", Utf8Helper::escapeHtml(link, true), Utf8Helper::escapeHtml(name)));
                        pos = linkEnd + 1;
                        continue;
                    }
                }
            }

            struct Marker
            {
                std::string_view open;
                std::string_view close;
                std::string_view htmlOpen;
                std::string_view htmlClose;
                bool             nested;
            };
            constexpr Marker markers[] = {
                {"***", "***", "<b><i>", "</i></b>", true},
                {"**", "**", "<b>", "</b>", true},
                {"~~", "~~", "<span class=\"strikethrough-text\">", "</span>", true},
                {"`", "`", "<span class=\"code-inline\">", "</span>", false},
            };

            bool matched = false;
            for (const Marker& marker : markers)
            {
                if (!text.substr(pos).starts_with(marker.open))
                    continue;
                const size_t end = text.find(marker.close, pos + marker.open.size());
                if (end == std::string_view::npos)
                    continue;

                const std::string_view inner = text.substr(pos + marker.open.size(), end - pos - marker.open.size());
                result.append(marker.htmlOpen);
                result += marker.nested ? renderInline(renderCtx, inner) : Utf8Helper::escapeHtml(inner);
                result.append(marker.htmlClose);
                pos     = end + marker.close.size();
                matched = true;
                break;
            }
            if (matched)
                continue;

            if (text[pos] == '\'')
            {
                const size_t end = text.find('\'', pos + 1);
                if (end != std::string_view::npos && end > pos + 1)
                {
                    const std::string_view code = text.substr(pos + 1, end - pos - 1);
                    if (code.find_first_of(" \t\r\n") == std::string_view::npos)
                    {
                        result += "<span class=\"code-inline\">";
                        result += Utf8Helper::escapeHtml(code);
                        result += "</span>";
                        pos = end + 1;
                        continue;
                    }
                }
            }

            if (text[pos] == '*' && (pos + 1 >= text.size() || text[pos + 1] != '*'))
            {
                const size_t end = text.find('*', pos + 1);
                if (end != std::string_view::npos && end > pos + 1)
                {
                    result += "<i>";
                    result += renderInline(renderCtx, text.substr(pos + 1, end - pos - 1));
                    result += "</i>";
                    pos = end + 1;
                    continue;
                }
            }

            if (text[pos] == '\\' && pos + 1 < text.size())
            {
                result += Utf8Helper::escapeHtml(text.substr(pos + 1, 1));
                pos += 2;
                continue;
            }

            result += Utf8Helper::escapeHtml(text.substr(pos, 1));
            pos++;
        }
        return result;
    }

    void linkSyntaxClass(Utf8& html, const DocRenderContext& renderCtx, std::string_view cssClass);
}

Utf8 DocMarkdown::renderCodeBlock(const TaskContext& ctx, const std::string_view code, const bool swagSyntax, const DocRenderContext* renderCtx)
{
    // A source file that opens or closes on a documentation comment produces an empty
    // segment on each side of it; an empty frame on the page would only be noise.
    if (Utf8Helper::trim(code).empty())
        return {};

    const Utf8 escaped = Utf8Helper::escapeHtml(code);
    Utf8       rendered;
    if (swagSyntax)
    {
        rendered = SyntaxColorHelper::colorize(ctx, SyntaxColorMode::ForDoc, escaped.view(), true);
        if (renderCtx)
        {
            linkSyntaxClass(rendered, *renderCtx, SYN_CONSTANT);
            linkSyntaxClass(rendered, *renderCtx, SYN_TYPE);
        }
    }
    else
        rendered = std::format("<span class=\"{}\">{}</span>", SYN_CODE, escaped);
    return std::format("<div class=\"code-block\">{}</div>\n", rendered);
}
namespace
{
    struct ListMarker
    {
        size_t indent        = 0;
        size_t contentIndent = 0;
        size_t contentOffset = 0;
        bool   ordered       = false;
    };

    size_t leadingIndent(const std::string_view line)
    {
        size_t result = 0;
        for (const char c : line)
        {
            if (c == ' ')
                result++;
            else if (c == '\t')
                result += 4;
            else
                break;
        }
        return result;
    }

    bool tryReadListMarker(const std::string_view line, ListMarker& outMarker)
    {
        size_t offset = 0;
        size_t indent = 0;
        while (offset < line.size() && (line[offset] == ' ' || line[offset] == '\t'))
        {
            indent += line[offset] == '\t' ? 4 : 1;
            offset++;
        }

        if (offset + 1 < line.size() && (line[offset] == '*' || line[offset] == '-') && line[offset + 1] == ' ')
        {
            outMarker = {
                .indent        = indent,
                .contentIndent = indent + 2,
                .contentOffset = offset + 2,
                .ordered       = false,
            };
            return true;
        }

        const size_t digitsStart = offset;
        while (offset < line.size() && std::isdigit(static_cast<unsigned char>(line[offset])))
            offset++;
        if (offset == digitsStart || offset + 1 >= line.size() || line[offset] != '.' || line[offset + 1] != ' ')
            return false;

        outMarker = {
            .indent        = indent,
            .contentIndent = indent + offset - digitsStart + 2,
            .contentOffset = offset + 2,
            .ordered       = true,
        };
        return true;
    }

    std::string_view removeLeadingIndent(const std::string_view line, const size_t indent)
    {
        size_t offset  = 0;
        size_t removed = 0;
        while (offset < line.size() && removed < indent && (line[offset] == ' ' || line[offset] == '\t'))
        {
            removed += line[offset] == '\t' ? 4 : 1;
            offset++;
        }
        return line.substr(offset);
    }

    enum class TableAlign : uint8_t
    {
        Default,
        Left,
        Center,
        Right,
    };

    const char* tableAlignClass(const TableAlign align)
    {
        switch (align)
        {
            case TableAlign::Left:
                return " class=\"align-left\"";
            case TableAlign::Center:
                return " class=\"align-center\"";
            case TableAlign::Right:
                return " class=\"align-right\"";
            case TableAlign::Default:
                return "";
        }
        SWC_UNREACHABLE();
    }

    bool tryReadTableSeparatorCell(std::string_view cell, TableAlign& outAlign)
    {
        cell                = Utf8Helper::trim(cell);
        const bool leading  = cell.starts_with(':');
        const bool trailing = cell.ends_with(':');
        if (leading)
            cell.remove_prefix(1);
        if (trailing && !cell.empty())
            cell.remove_suffix(1);
        if (cell.size() < 3 || !std::ranges::all_of(cell, [](const char c) { return c == '-'; }))
            return false;

        if (leading && trailing)
            outAlign = TableAlign::Center;
        else if (trailing)
            outAlign = TableAlign::Right;
        else if (leading)
            outAlign = TableAlign::Left;
        else
            outAlign = TableAlign::Default;
        return true;
    }

    std::vector<Utf8> splitTableRow(std::string_view line)
    {
        line = Utf8Helper::trim(line);
        if (!line.empty() && line.front() == '|')
            line.remove_prefix(1);
        if (!line.empty() && line.back() == '|')
            line.remove_suffix(1);

        std::vector<Utf8> cells;
        size_t            start = 0;
        while (start <= line.size())
        {
            size_t end = line.find('|', start);
            if (end == std::string_view::npos)
                end = line.size();
            cells.emplace_back(Utf8Helper::trim(line.substr(start, end - start)));
            if (end == line.size())
                break;
            start = end + 1;
        }
        return cells;
    }

    bool isExplicitMarkdownBlockStart(const std::string_view line)
    {
        if (line.empty() || line == "---" || line.starts_with("```") || line.starts_with(">") || line.starts_with("# ") || line.starts_with("## ") || line.starts_with("### ") || line.starts_with("#### ") || line.starts_with("##### ") || line.starts_with("###### "))
            return true;
        if (line.starts_with("+ ") || line.starts_with("<html>"))
            return true;
        return line.starts_with("|");
    }

    bool isMarkdownBlockStart(std::span<const Utf8> lines, const size_t index)
    {
        const std::string_view raw  = lines[index];
        const std::string_view line = Utf8Helper::trim(raw);
        if (isExplicitMarkdownBlockStart(line))
            return true;
        if (raw.starts_with("    ") || raw.starts_with("\t"))
            return true;
        ListMarker marker;
        return tryReadListMarker(raw, marker);
    }

    Utf8 renderList(const DocRenderContext& renderCtx, std::span<const Utf8> lines, size_t& index, const uint32_t headingOffset)
    {
        ListMarker firstMarker;
        SWC_ASSERT(tryReadListMarker(lines[index], firstMarker));

        Utf8 result;
        result += firstMarker.ordered ? "<ol>\n" : "<ul>\n";
        while (index < lines.size())
        {
            ListMarker marker;
            if (!tryReadListMarker(lines[index], marker) || marker.indent != firstMarker.indent || marker.ordered != firstMarker.ordered)
                break;

            std::vector<Utf8> itemLines;
            itemLines.emplace_back(Utf8Helper::trim(std::string_view(lines[index]).substr(marker.contentOffset)));
            index++;

            bool followsBlankLine = false;
            while (index < lines.size())
            {
                const std::string_view raw  = lines[index];
                const std::string_view line = Utf8Helper::trim(raw);
                if (line.empty())
                {
                    itemLines.emplace_back();
                    followsBlankLine = true;
                    index++;
                    continue;
                }

                ListMarker nextMarker;
                const bool hasMarker = tryReadListMarker(raw, nextMarker);
                if (hasMarker && nextMarker.indent <= marker.indent)
                    break;

                const size_t indent = leadingIndent(raw);
                if ((followsBlankLine || isMarkdownBlockStart(lines, index)) && indent <= marker.indent)
                    break;

                if (hasMarker || isExplicitMarkdownBlockStart(line))
                    itemLines.emplace_back(removeLeadingIndent(raw, marker.contentIndent));
                else
                    itemLines.emplace_back(line);
                followsBlankLine = false;
                index++;
            }

            Utf8 item = DocMarkdown::renderLines(renderCtx, itemLines, headingOffset);
            if (item.starts_with("<p>"))
            {
                item.erase(0, 3);
                const size_t paragraphEnd = item.find("</p>\n");
                if (paragraphEnd != Utf8::npos)
                    item.erase(paragraphEnd, paragraphEnd + 5 == item.size() ? 5 : 4);
            }
            result.append(std::format("<li>{}</li>\n", item));
        }
        result += firstMarker.ordered ? "</ol>\n" : "</ul>\n";
        return result;
    }
}

Utf8 DocMarkdown::renderLines(const DocRenderContext& renderCtx, std::span<const Utf8> lines, const uint32_t headingOffset)
{
    Utf8   result;
    size_t index = 0;
    while (index < lines.size())
    {
        const std::string_view raw  = lines[index];
        const std::string_view line = Utf8Helper::trim(raw);
        if (line.empty())
        {
            index++;
            continue;
        }

        if (line.starts_with("<html>"))
        {
            std::string_view first = line.substr(6);
            if (!first.empty())
            {
                result.append(first);
                result += "\n";
            }
            index++;
            while (index < lines.size())
            {
                const std::string_view rawLine = lines[index++];
                const size_t           endPos  = rawLine.find("</html>");
                if (endPos != std::string_view::npos)
                {
                    result.append(rawLine.substr(0, endPos));
                    result += "\n";
                    break;
                }
                result.append(rawLine);
                result += "\n";
            }
            continue;
        }

        if (line.starts_with("```"))
        {
            const bool swagSyntax = line == "```swag";
            index++;
            Utf8 code;
            while (index < lines.size() && !Utf8Helper::trim(lines[index]).starts_with("```"))
            {
                code += lines[index++];
                code += "\n";
            }
            if (index < lines.size())
                index++;
            result += renderCodeBlock(*renderCtx.ctx, code, swagSyntax, &renderCtx);
            continue;
        }

        if (raw.starts_with("    ") || raw.starts_with("\t"))
        {
            Utf8 code;
            while (index < lines.size())
            {
                std::string_view codeLine = lines[index];
                if (codeLine.starts_with("    "))
                    codeLine.remove_prefix(4);
                else if (codeLine.starts_with("\t"))
                    codeLine.remove_prefix(1);
                else
                    break;
                code.append(codeLine);
                code += "\n";
                index++;
            }
            result += renderCodeBlock(*renderCtx.ctx, code, false);
            continue;
        }

        if (line == "---")
        {
            result += "<hr>\n";
            index++;
            continue;
        }

        if (line.front() == '#')
        {
            size_t level = 0;
            while (level < line.size() && line[level] == '#')
                level++;
            if (level < line.size() && line[level] == ' ')
            {
                const std::string_view title     = Utf8Helper::trim(line.substr(level + 1));
                const uint32_t         htmlLevel = std::clamp<uint32_t>(static_cast<uint32_t>(level) + headingOffset, 1, 6);
                Utf8                   anchor    = makeAnchor(title);
                if (!renderCtx.headingAnchorPrefix.empty())
                    anchor = std::format("{}_{}", renderCtx.headingAnchorPrefix, anchor);
                result.append(std::format("<h{} id=\"{}\">{}</h{}>\n", htmlLevel, anchor, renderInline(renderCtx, title), htmlLevel));
                index++;
                continue;
            }
        }

        if (line.starts_with(">"))
        {
            std::vector<Utf8> quoteLines;
            while (index < lines.size())
            {
                std::string_view quoteLine = Utf8Helper::trim(lines[index]);
                if (!quoteLine.starts_with(">"))
                    break;
                quoteLine.remove_prefix(1);
                if (!quoteLine.empty() && quoteLine.front() == ' ')
                    quoteLine.remove_prefix(1);
                quoteLines.emplace_back(quoteLine);
                index++;
            }

            std::string_view kind;
            std::string_view defaultTitle;
            Utf8             icon;
            Utf8             title;
            if (!quoteLines.empty())
            {
                struct QuoteKind
                {
                    const char* marker;
                    const char* css;
                    const char* title;
                    const Utf8* icon;
                    const Utf8* configuredTitle;
                };
                const DocPageOptions& options = *renderCtx.options;
                const QuoteKind       kinds[] = {
                    {"NOTE:", "note", "Note", &options.quoteIconNote, &options.quoteTitleNote},
                    {"TIP:", "tip", "Tip", &options.quoteIconTip, &options.quoteTitleTip},
                    {"WARNING:", "warning", "Warning", &options.quoteIconWarning, &options.quoteTitleWarning},
                    {"ATTENTION:", "attention", "Attention", &options.quoteIconAttention, &options.quoteTitleAttention},
                    {"EXAMPLE:", "example", "Example", &options.quoteIconExample, &options.quoteTitleExample},
                };
                for (const QuoteKind& candidate : kinds)
                {
                    if (!Utf8Helper::trim(quoteLines.front()).starts_with(candidate.marker))
                        continue;
                    kind                   = candidate.css;
                    defaultTitle           = candidate.title;
                    icon                   = *candidate.icon;
                    title                  = candidate.configuredTitle->empty() ? Utf8(defaultTitle) : *candidate.configuredTitle;
                    std::string_view first = Utf8Helper::trim(quoteLines.front());
                    first.remove_prefix(std::strlen(candidate.marker));
                    quoteLines.front() = Utf8(Utf8Helper::trim(first));
                    break;
                }
            }

            if (kind.empty())
            {
                result += "<div class=\"blockquote blockquote-default\">\n";
            }
            else
            {
                result.append(std::format("<div class=\"blockquote blockquote-{}\">\n", kind));
                result += "<div class=\"blockquote-title-block\">";
                if (!icon.empty())
                {
                    result += icon;
                    result += " ";
                }
                result.append(std::format("<span class=\"blockquote-title\">{}</span></div>\n", Utf8Helper::escapeHtml(title)));
            }
            result += renderLines(renderCtx, quoteLines, headingOffset);
            result += "</div>\n";
            continue;
        }

        if (line.starts_with("|"))
        {
            std::vector<std::vector<Utf8>> rows;
            while (index < lines.size() && Utf8Helper::trim(lines[index]).starts_with("|"))
                rows.push_back(splitTableRow(lines[index++]));

            // A separator on the second line promotes the first row to a header and fixes
            // the column alignments. Without one the run is still a table, simply without
            // a header row; that headerless form is a long-standing Swag spelling.
            std::vector<TableAlign> aligns;
            bool                    hasHeader = rows.size() > 1;
            if (hasHeader)
            {
                for (const Utf8& cell : rows[1])
                {
                    TableAlign align = TableAlign::Default;
                    if (!tryReadTableSeparatorCell(cell, align))
                    {
                        hasHeader = false;
                        break;
                    }
                    aligns.push_back(align);
                }
                hasHeader &= aligns.size() == rows.front().size();
            }
            if (!hasHeader)
                aligns.clear();

            size_t columnCount = 0;
            for (const std::vector<Utf8>& row : rows)
                columnCount = std::max(columnCount, row.size());
            aligns.resize(columnCount, TableAlign::Default);

            const auto appendRow = [&](const std::vector<Utf8>& row, const std::string_view tag) {
                result += "<tr>";
                for (size_t column = 0; column < columnCount; ++column)
                {
                    const Utf8 cell = column < row.size() ? row[column] : Utf8();
                    result.append(std::format("<{}{}>{}</{}>", tag, tableAlignClass(aligns[column]), renderInline(renderCtx, cell), tag));
                }
                result += "</tr>\n";
            };

            result += "<table class=\"table-markdown\">\n";
            size_t firstBodyRow = 0;
            if (hasHeader)
            {
                result += "<thead>\n";
                appendRow(rows.front(), "th");
                result += "</thead>\n";
                firstBodyRow = 2;
            }
            result += "<tbody>\n";
            for (size_t row = firstBodyRow; row < rows.size(); ++row)
                appendRow(rows[row], "td");
            result += "</tbody>\n</table>\n";
            continue;
        }

        ListMarker listMarker;
        if (tryReadListMarker(raw, listMarker))
        {
            result += renderList(renderCtx, lines, index, headingOffset);
            continue;
        }

        if (line.starts_with("+ "))
        {
            while (index < lines.size() && Utf8Helper::trim(lines[index]).starts_with("+ "))
            {
                std::string_view title = Utf8Helper::trim(lines[index]);
                title.remove_prefix(2);
                result.append(std::format("<div class=\"description-list-title\"><p>{}</p></div>\n", renderInline(renderCtx, title)));
                index++;

                std::vector<Utf8> description;
                while (index < lines.size() && (lines[index].starts_with("    ") || lines[index].starts_with("\t") || Utf8Helper::trim(lines[index]).empty()))
                {
                    std::string_view descriptionLine = lines[index++];
                    if (descriptionLine.starts_with("    "))
                        descriptionLine.remove_prefix(4);
                    else if (descriptionLine.starts_with("\t"))
                        descriptionLine.remove_prefix(1);
                    description.emplace_back(descriptionLine);
                }
                result += "<div class=\"description-list-block\">\n";
                result += renderLines(renderCtx, description, headingOffset);
                result += "</div>\n";
            }
            continue;
        }

        Utf8 paragraph;
        while (index < lines.size())
        {
            if (!paragraph.empty() && isMarkdownBlockStart(lines, index))
                break;
            const std::string_view paragraphLine = Utf8Helper::trim(lines[index]);
            if (paragraphLine.empty())
                break;
            if (!paragraph.empty())
                paragraph += " ";
            paragraph.append(paragraphLine);
            index++;
        }
        if (!paragraph.empty())
            result.append(std::format("<p>{}</p>\n", renderInline(renderCtx, paragraph)));
        else
            index++;
    }
    return result;
}
namespace
{
    void linkSyntaxClass(Utf8& html, const DocRenderContext& renderCtx, const std::string_view cssClass)
    {
        const Utf8 open = std::format("<span class=\"{}\">", cssClass);
        size_t     pos  = 0;
        while ((pos = html.find(open, pos)) != Utf8::npos)
        {
            const size_t textStart = pos + open.size();
            const size_t textEnd   = html.find("</span>", textStart);
            if (textEnd == Utf8::npos)
                break;

            const std::string_view name = html.subView(textStart, textEnd - textStart);
            if (name.find('<') == std::string_view::npos && name.find('&') == std::string_view::npos)
            {
                const Utf8 reference = resolveReference(renderCtx, name);
                if (!reference.empty())
                {
                    html.replace(textStart, textEnd - textStart, reference);
                    pos = textStart + reference.size();
                    continue;
                }
            }
            pos = textEnd + 7;
        }
    }
}

SWC_END_NAMESPACE();
