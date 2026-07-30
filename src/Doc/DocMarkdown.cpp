#include "pch.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/ModuleApi/ModuleApi.Export.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/AttributeList.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/SourceFile.h"
#include "Doc/DocInternal.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/TaskContext.h"
#include "Main/Version.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/SyntaxColor.h"

SWC_BEGIN_NAMESPACE();

namespace DocInternal
{

    std::string_view trimView(std::string_view value)
    {
        while (!value.empty() && std::isspace(static_cast<unsigned char>(value.front())))
            value.remove_prefix(1);
        while (!value.empty() && std::isspace(static_cast<unsigned char>(value.back())))
            value.remove_suffix(1);
        return value;
    }

    Utf8 trimCopy(std::string_view value)
    {
        return Utf8(trimView(value));
    }

    std::vector<Utf8> splitLines(const std::string_view text)
    {
        std::vector<Utf8> result;
        size_t            start = 0;
        while (start <= text.size())
        {
            size_t end = text.find_first_of("\r\n", start);
            if (end == std::string_view::npos)
                end = text.size();
            result.emplace_back(text.substr(start, end - start));
            if (end == text.size())
                break;
            if (text[end] == '\r' && end + 1 < text.size() && text[end + 1] == '\n')
                end++;
            start = end + 1;
        }
        return result;
    }

    Utf8 escapeHtml(const std::string_view text, const bool attribute)
    {
        Utf8 result;
        result.reserve(text.size());
        for (const char c : text)
        {
            switch (c)
            {
                case '&':
                    result += "&amp;";
                    break;
                case '<':
                    result += "&lt;";
                    break;
                case '>':
                    result += "&gt;";
                    break;
                case '"':
                    if (attribute)
                        result += "&quot;";
                    else
                        result += c;
                    break;
                default:
                    result += c;
                    break;
            }
        }
        return result;
    }

    Utf8 makeAnchor(const std::string_view value)
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

    Utf8 lastNamePart(const std::string_view value)
    {
        const size_t pos = value.rfind('.');
        if (pos == std::string_view::npos)
            return Utf8(value);
        return Utf8(value.substr(pos + 1));
    }

    Utf8 resolveReference(const RenderContext& renderCtx, const std::string_view name)
    {
        if (renderCtx.references)
        {
            const auto it = renderCtx.references->find(Utf8(name));
            if (it != renderCtx.references->end())
                return std::format("<a href=\"#{}\">{}</a>", it->second, escapeHtml(name));

            if (!renderCtx.moduleName.empty() && name.starts_with(renderCtx.moduleName) && name.size() > renderCtx.moduleName.size() && name[renderCtx.moduleName.size()] == '.')
            {
                const auto shortIt = renderCtx.references->find(Utf8(name.substr(renderCtx.moduleName.size() + 1)));
                if (shortIt != renderCtx.references->end())
                    return std::format("<a href=\"#{}\">{}</a>", shortIt->second, escapeHtml(name));
            }
        }

        if (renderCtx.externalReferences)
        {
            const auto it = renderCtx.externalReferences->find(Utf8(name));
            if (it != renderCtx.externalReferences->end())
                return std::format("<a href=\"{}\">{}</a>", escapeHtml(it->second, true), escapeHtml(name));
        }

        if (name.starts_with("Swag."))
        {
            const Utf8 anchor = makeAnchor(name);
            return std::format("<a href=\"swag.runtime.html#{}\">{}</a>", anchor, escapeHtml(name));
        }

        const size_t separator = name.find('.');
        if (separator != std::string_view::npos && renderCtx.externalModules)
        {
            const auto it = renderCtx.externalModules->find(Utf8(name.substr(0, separator)));
            if (it != renderCtx.externalModules->end())
                return std::format("<a href=\"{}#{}\">{}</a>", escapeHtml(it->second, true), makeAnchor(name), escapeHtml(name));
        }
        return {};
    }

    Utf8 renderTypeName(const RenderContext& renderCtx, const std::string_view typeName)
    {
        Utf8   result;
        size_t pos = 0;
        while (pos < typeName.size())
        {
            const char c = typeName[pos];
            if (!std::isalpha(static_cast<unsigned char>(c)) && c != '_')
            {
                result += escapeHtml(typeName.substr(pos, 1));
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
            result += reference.empty() ? escapeHtml(token) : reference;
            pos = end;
        }
        return result;
    }

    Utf8 renderInline(const RenderContext& renderCtx, const std::string_view text)
    {
        Utf8   result;
        size_t pos = 0;
        while (pos < text.size())
        {
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
                        result.append(std::format("<img src=\"{}\" alt=\"{}\">", escapeHtml(link, true), escapeHtml(name, true)));
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
                        result.append(std::format("<a href=\"{}\">{}</a>", escapeHtml(link, true), escapeHtml(name)));
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
            };
            constexpr Marker markers[] = {
                {"***", "***", "<b><i>", "</i></b>"},
                {"**", "**", "<b>", "</b>"},
                {"~~", "~~", "<span class=\"strikethrough-text\">", "</span>"},
                {"`", "`", "<span class=\"code-inline\">", "</span>"},
            };

            bool matched = false;
            for (const Marker& marker : markers)
            {
                if (!text.substr(pos).starts_with(marker.open))
                    continue;
                const size_t end = text.find(marker.close, pos + marker.open.size());
                if (end == std::string_view::npos)
                    continue;

                result.append(marker.htmlOpen);
                result += escapeHtml(text.substr(pos + marker.open.size(), end - pos - marker.open.size()));
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
                        result += escapeHtml(code);
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
                    result += escapeHtml(text.substr(pos + 1, end - pos - 1));
                    result += "</i>";
                    pos = end + 1;
                    continue;
                }
            }

            if (text[pos] == '\\' && pos + 1 < text.size())
            {
                result += escapeHtml(text.substr(pos + 1, 1));
                pos += 2;
                continue;
            }

            result += escapeHtml(text.substr(pos, 1));
            pos++;
        }
        return result;
    }

    void linkSyntaxClass(Utf8& html, const RenderContext& renderCtx, std::string_view cssClass);

    Utf8 renderCodeBlock(TaskContext& ctx, const std::string_view code, const bool swagSyntax, const RenderContext* renderCtx)
    {
        const Utf8 escaped = escapeHtml(code);
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

    bool isOrderedListLine(const std::string_view line)
    {
        const std::string_view value = trimView(line);
        size_t                 i     = 0;
        while (i < value.size() && std::isdigit(static_cast<unsigned char>(value[i])))
            i++;
        return i > 0 && i + 1 < value.size() && value[i] == '.' && value[i + 1] == ' ';
    }

    bool isTableSeparatorCell(std::string_view cell)
    {
        cell = trimView(cell);
        if (!cell.empty() && cell.front() == ':')
            cell.remove_prefix(1);
        if (!cell.empty() && cell.back() == ':')
            cell.remove_suffix(1);
        return cell.size() >= 3 && std::ranges::all_of(cell, [](const char c) { return c == '-'; });
    }

    std::vector<Utf8> splitTableRow(std::string_view line)
    {
        line = trimView(line);
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
            cells.emplace_back(trimView(line.substr(start, end - start)));
            if (end == line.size())
                break;
            start = end + 1;
        }
        return cells;
    }

    bool isMarkdownBlockStart(std::span<const Utf8> lines, const size_t index)
    {
        const std::string_view raw  = lines[index];
        const std::string_view line = trimView(raw);
        if (line.empty() || line == "---" || line.starts_with("```") || line.starts_with(">") || line.starts_with("# ") || line.starts_with("## ") || line.starts_with("### ") || line.starts_with("#### ") || line.starts_with("##### ") || line.starts_with("###### "))
            return true;
        if (raw.starts_with("    ") || raw.starts_with("\t"))
            return true;
        if (line.starts_with("* ") || line.starts_with("- ") || line.starts_with("+ ") || isOrderedListLine(line))
            return true;
        if (line.starts_with("<html>"))
            return true;
        return line.starts_with("|") && index + 1 < lines.size();
    }

    Utf8 renderMarkdownLines(const RenderContext& renderCtx, std::span<const Utf8> lines, const uint32_t headingOffset)
    {
        Utf8   result;
        size_t index = 0;
        while (index < lines.size())
        {
            const std::string_view raw  = lines[index];
            const std::string_view line = trimView(raw);
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
                while (index < lines.size() && !trimView(lines[index]).starts_with("```"))
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
                    const std::string_view title     = trimView(line.substr(level + 1));
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
                    std::string_view quoteLine = trimView(lines[index]);
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
                    const PageOptions& options = *renderCtx.options;
                    const QuoteKind    kinds[] = {
                        {"NOTE:", "note", "Note", &options.quoteIconNote, &options.quoteTitleNote},
                        {"TIP:", "tip", "Tip", &options.quoteIconTip, &options.quoteTitleTip},
                        {"WARNING:", "warning", "Warning", &options.quoteIconWarning, &options.quoteTitleWarning},
                        {"ATTENTION:", "attention", "Attention", &options.quoteIconAttention, &options.quoteTitleAttention},
                        {"EXAMPLE:", "example", "Example", &options.quoteIconExample, &options.quoteTitleExample},
                    };
                    for (const QuoteKind& candidate : kinds)
                    {
                        if (!trimView(quoteLines.front()).starts_with(candidate.marker))
                            continue;
                        kind                   = candidate.css;
                        defaultTitle           = candidate.title;
                        icon                   = *candidate.icon;
                        title                  = candidate.configuredTitle->empty() ? Utf8(defaultTitle) : *candidate.configuredTitle;
                        std::string_view first = trimView(quoteLines.front());
                        first.remove_prefix(std::strlen(candidate.marker));
                        quoteLines.front() = trimCopy(first);
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
                    result.append(std::format("<span class=\"blockquote-title\">{}</span></div>\n", escapeHtml(title)));
                }
                result += renderMarkdownLines(renderCtx, quoteLines, headingOffset);
                result += "</div>\n";
                continue;
            }

            if (line.starts_with("|") && index + 1 < lines.size())
            {
                const std::vector<Utf8> header    = splitTableRow(line);
                const std::vector<Utf8> separator = splitTableRow(lines[index + 1]);
                const bool              isTable   = !header.empty() &&
                                     separator.size() == header.size() &&
                                     std::ranges::all_of(separator, [](const Utf8& cell) { return isTableSeparatorCell(cell); });
                if (isTable)
                {
                    result += "<table class=\"table-markdown\">\n<tr>";
                    for (const Utf8& cell : header)
                        result.append(std::format("<th>{}</th>", renderInline(renderCtx, cell)));
                    result += "</tr>\n";
                    index += 2;
                    while (index < lines.size() && trimView(lines[index]).starts_with("|"))
                    {
                        std::vector<Utf8> cells = splitTableRow(lines[index++]);
                        cells.resize(header.size());
                        result += "<tr>";
                        for (const Utf8& cell : cells)
                            result.append(std::format("<td>{}</td>", renderInline(renderCtx, cell)));
                        result += "</tr>\n";
                    }
                    result += "</table>\n";
                    continue;
                }
            }

            if (line.starts_with("* ") || line.starts_with("- ") || isOrderedListLine(line))
            {
                const bool ordered = isOrderedListLine(line);
                result += ordered ? "<ol>\n" : "<ul>\n";
                while (index < lines.size())
                {
                    std::string_view item = trimView(lines[index]);
                    if (ordered)
                    {
                        if (!isOrderedListLine(item))
                            break;
                        item.remove_prefix(item.find('.') + 1);
                    }
                    else
                    {
                        if (!item.starts_with("* ") && !item.starts_with("- "))
                            break;
                        item.remove_prefix(1);
                    }
                    item = trimView(item);
                    result.append(std::format("<li>{}</li>\n", renderInline(renderCtx, item)));
                    index++;
                }
                result += ordered ? "</ol>\n" : "</ul>\n";
                continue;
            }

            if (line.starts_with("+ "))
            {
                while (index < lines.size() && trimView(lines[index]).starts_with("+ "))
                {
                    std::string_view title = trimView(lines[index]);
                    title.remove_prefix(2);
                    result.append(std::format("<div class=\"description-list-title\"><p>{}</p></div>\n", renderInline(renderCtx, title)));
                    index++;

                    std::vector<Utf8> description;
                    while (index < lines.size() && (lines[index].starts_with("    ") || lines[index].starts_with("\t") || trimView(lines[index]).empty()))
                    {
                        std::string_view descriptionLine = lines[index++];
                        if (descriptionLine.starts_with("    "))
                            descriptionLine.remove_prefix(4);
                        else if (descriptionLine.starts_with("\t"))
                            descriptionLine.remove_prefix(1);
                        description.emplace_back(descriptionLine);
                    }
                    result += "<div class=\"description-list-block\">\n";
                    result += renderMarkdownLines(renderCtx, description, headingOffset);
                    result += "</div>\n";
                }
                continue;
            }

            Utf8 paragraph;
            while (index < lines.size())
            {
                if (!paragraph.empty() && isMarkdownBlockStart(lines, index))
                    break;
                const std::string_view paragraphLine = trimView(lines[index]);
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

    std::vector<Utf8> summaryLines(std::span<const Utf8> lines)
    {
        for (const Utf8& line : lines)
        {
            if (trimView(line).empty())
                continue;
            return {line};
        }
        return {};
    }

    void linkSyntaxClass(Utf8& html, const RenderContext& renderCtx, const std::string_view cssClass)
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

    Utf8 codeHtml(TaskContext& ctx, const RenderContext& renderCtx, const std::string_view code)
    {
        if (code.empty())
            return {};
        return renderCodeBlock(ctx, code, true, &renderCtx);
    }
}

SWC_END_NAMESPACE();
