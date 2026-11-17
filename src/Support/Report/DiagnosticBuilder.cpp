#include "pch.h"
#include "Support/Report/DiagnosticBuilder.h"
#include "Compiler/Lexer/Lexer.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/DiagnosticElement.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct DiagnosticArgumentToStringVisitor
    {
        const TaskContext* ctx       = nullptr;
        bool               qualified = false;

        template<typename T0>
        Utf8 operator()(const T0& v) const
        {
            using T = std::decay_t<T0>;
            if constexpr (std::same_as<T, Utf8>)
                return v;
            else if constexpr (std::same_as<T, TokenId>)
                return Token::toName(v);
            else if constexpr (std::same_as<T, DiagnosticId>)
                return Diagnostic::diagIdMessage(v);
            else if constexpr (std::integral<T>)
                return Utf8{std::to_string(v)};
            else if constexpr (std::same_as<T, TypeRef>)
            {
                if (v.isInvalid())
                    return Utf8{"<type unavailable>"};

                const TypeInfo& type = ctx->compiler().typeMgr().get(v);
                return qualified ? type.toFullName(*ctx) : type.toName(*ctx);
            }
            else if constexpr (std::same_as<T, ConstantRef>)
                return ctx->compiler().cstMgr().get(v).toString(*ctx);
            else if constexpr (std::same_as<T, IdentifierRef>)
                return ctx->compiler().idMgr().get(v).name;
            else
                SWC_UNREACHABLE();
        }
    };

    struct DiagnosticSpanColumnLess
    {
        const DiagnosticElement* element = nullptr;
        const TaskContext*       ctx     = nullptr;

        bool operator()(const DiagnosticSpan& lhs, const DiagnosticSpan& rhs) const
        {
            SWC_ASSERT(element != nullptr);
            SWC_ASSERT(ctx != nullptr);

            const SourceCodeRange leftRange  = element->codeRange(lhs, *ctx);
            const SourceCodeRange rightRange = element->codeRange(rhs, *ctx);
            return leftRange.column < rightRange.column;
        }
    };

    std::optional<DiagnosticSeverity> tagToSeverity(std::string_view s)
    {
        if (Utf8Helper::startsWith(s, "[note]"))
            return DiagnosticSeverity::Note;
        if (Utf8Helper::startsWith(s, "[help]"))
            return DiagnosticSeverity::Help;

        return std::nullopt;
    }

    std::string_view stripLeadingTagHeader(std::string_view s)
    {
        std::string_view t = Utf8Helper::trim(s);
        if (!t.empty() && t.front() == '[')
        {
            const size_t close = t.find(']');
            if (close != std::string_view::npos)
                t.remove_prefix(close + 1);
        }

        t = Utf8Helper::trimLeft(t);
        return t;
    }

    std::string_view severityStr(DiagnosticSeverity s)
    {
        switch (s)
        {
            case DiagnosticSeverity::Error:
                return "error";
            case DiagnosticSeverity::Warning:
                return "warning";
            case DiagnosticSeverity::Note:
                return "note";
            case DiagnosticSeverity::Help:
                return "help";
            default:
                SWC_UNREACHABLE();
        }
    }

    // Generic digit counter (no hard cap)
    // A source excerpt is a recognition aid, not a listing: one line, cut at this many bytes.
    constexpr size_t EXCERPT_MAX_BYTES = 200;

    // The source line a span starts on, without its indentation. A line longer than the limit
    // is cut on a character boundary and marked.
    Utf8 sourceExcerpt(const Utf8& codeLine)
    {
        const std::string_view blanks = " \t\r\n";
        const std::string_view line   = codeLine.view();
        const size_t           first  = line.find_first_not_of(blanks);
        if (first == std::string_view::npos)
            return {};

        std::string_view text = line.substr(first, line.find_last_not_of(blanks) - first + 1);
        if (text.size() <= EXCERPT_MAX_BYTES)
            return Utf8{text};

        size_t cutAt = EXCERPT_MAX_BYTES;
        while (cutAt && (static_cast<unsigned char>(text[cutAt]) & 0xc0) == 0x80)
            cutAt--;

        return Utf8{text.substr(0, cutAt)} + " ...";
    }

    bool isAsciiIdentifierHead(const char ch)
    {
        const unsigned char uch = static_cast<unsigned char>(ch);
        return std::isalpha(uch) || ch == '_';
    }

    bool isAsciiIdentifierTail(const char ch)
    {
        const unsigned char uch = static_cast<unsigned char>(ch);
        return std::isalnum(uch) || ch == '_';
    }

    bool isLiteralSuffixAnchor(const char ch)
    {
        const unsigned char uch = static_cast<unsigned char>(ch);
        return std::isalnum(uch) || ch == '_' || ch == '\'' || ch == '"' || ch == ')' || ch == ']' || ch == '}';
    }

    bool isLiteralSuffixQuote(std::string_view msg, const size_t index)
    {
        if (index == 0 || index + 1 >= msg.size() || msg[index] != '\'')
            return false;
        if (!isAsciiIdentifierHead(msg[index + 1]))
            return false;
        return isLiteralSuffixAnchor(msg[index - 1]);
    }

    void removeRedundantEmptyQuotes(Utf8& text)
    {
        Utf8 cleaned;
        cleaned.reserve(text.length());

        for (size_t i = 0; i < text.length(); ++i)
        {
            if (i + 1 < text.length() && text[i] == '\'' && text[i + 1] == '\'')
            {
                const char prev = i ? text[i - 1] : '\0';
                const char next = i + 2 < text.length() ? text[i + 2] : '\0';
                if (!(isLiteralSuffixAnchor(prev) && isAsciiIdentifierHead(next)))
                {
                    ++i;
                    continue;
                }
            }

            cleaned += text[i];
        }

        text = std::move(cleaned);
    }

    bool isInsideQuotedMessageSegment(std::string_view msg, size_t index)
    {
        bool inQuote = false;

        for (size_t i = 0; i < index && i < msg.size(); ++i)
        {
            const char ch = msg[i];
            if (!inQuote)
            {
                if (ch != '\'')
                    continue;

                if (isLiteralSuffixQuote(msg, i))
                {
                    while (i + 1 < index && i + 1 < msg.size() && isAsciiIdentifierTail(msg[i + 1]))
                        ++i;
                    continue;
                }

                inQuote = true;
                continue;
            }

            if (ch == '\\')
            {
                if (i + 1 < index && i + 1 < msg.size())
                    ++i;
                continue;
            }

            if (ch == '\'')
                inQuote = false;
        }

        return inQuote;
    }

    Utf8 escapeQuotedMessageArgument(std::string_view value)
    {
        Utf8 escaped;
        escaped.reserve(value.size());

        for (const char ch : value)
        {
            if (ch == '\\' || ch == '\'')
                escaped += '\\';
            escaped += ch;
        }

        return escaped;
    }

    void removeUnexpandedPlaceholders(Utf8& text)
    {
        Utf8 cleaned;
        cleaned.reserve(text.size());

        size_t index = 0;
        while (index < text.size())
        {
            if (text[index] == '{')
            {
                size_t end = index + 1;
                while (end < text.size() && Utf8Helper::isAsciiWordCharacter(text[end]))
                    ++end;

                if (end > index + 1 && end < text.size() && text[end] == '}')
                {
                    index = end + 1;
                    continue;
                }
            }

            cleaned += text[index++];
        }

        text = std::move(cleaned);
    }
}

DiagnosticBuilder::DiagnosticBuilder(const TaskContext& ctx, const Diagnostic& diag) :
    ctx_(&ctx),
    diag_(&diag)
{
}

Utf8 DiagnosticBuilder::build()
{
    if (diag_->elements().empty())
        return {};

    // Make a copy of elements to modify them if necessary
    SmallVector<std::unique_ptr<DiagnosticElement>> elements;
    elements.reserve(diag_->elements().size());
    for (const std::shared_ptr<DiagnosticElement>& e : diag_->elements())
        elements.push_back(std::make_unique<DiagnosticElement>(*e));

    // Add elements by splitting messages parts
    expandMessageParts(elements);

    for (const std::unique_ptr<DiagnosticElement>& e : elements)
        writeElement(*e);

    return out_;
}

// Quoted semicolons belong to the message text, even after an escaped quote.
SmallVector<std::string_view> DiagnosticBuilder::splitMessage(std::string_view msg)
{
    SmallVector<std::string_view> parts;
    size_t                        start   = 0;
    bool                          inQuote = false;

    for (size_t i = 0; i < msg.size(); ++i)
    {
        const char c = msg[i];
        if (inQuote)
        {
            if (c == '\\')
            {
                if (i + 1 < msg.size())
                    ++i;
            }
            else if (c == '\'')
            {
                inQuote = false;
            }
        }
        else
        {
            if (c == '\'')
                inQuote = true;
            else if (c == ';')
            {
                const std::string_view p = Utf8Helper::trim(msg.substr(start, i - start));
                if (!p.empty())
                    parts.emplace_back(p);

                start = i + 1;
            }
        }
    }

    if (start <= msg.size())
    {
        const std::string_view p = Utf8Helper::trim(msg.substr(start));
        if (!p.empty())
            parts.emplace_back(p);
    }

    return parts;
}

SmallVector<DiagnosticBuilder::Part> DiagnosticBuilder::parseParts(std::string_view msg)
{
    SmallVector<Part> out;
    for (const std::string_view raw : splitMessage(msg))
    {
        if (raw.empty())
            continue;

        const std::optional<DiagnosticSeverity> sev  = tagToSeverity(raw);
        const std::string_view                  body = stripLeadingTagHeader(raw);
        out.push_back({.tag = sev, .text = Utf8(body)});
    }

    return out;
}

// Copies a message, resolving the escapes a quoted argument carries: inside quotes, '\\' is a
// backslash and '\'' is a quote that does not close the segment.
void DiagnosticBuilder::writeMessage(const std::string_view msg)
{
    bool inQuote = false;
    Utf8 quotedBuf;
    quotedBuf.reserve(32);

    for (size_t i = 0; i < msg.size(); ++i)
    {
        const char ch = msg[i];

        if (!inQuote)
        {
            if (ch == '\'' && !isLiteralSuffixQuote(msg, i))
            {
                inQuote   = true;
                quotedBuf = '\'';
            }
            else
            {
                out_ += ch;
            }
        }
        else if (ch == '\\')
        {
            // Handling '\\' first is essential, otherwise '\\'' would be misparsed as a backslash
            // followed by an escaped quote instead of an escaped backslash followed by the closing
            // delimiter.
            if (i + 1 < msg.size() && (msg[i + 1] == '\\' || msg[i + 1] == '\''))
                quotedBuf += msg[++i];
            else
                quotedBuf += '\\';
        }
        else if (ch == '\'' && quotedBuf.size() == 1)
        {
            quotedBuf += ch;
        }
        else if (ch == '\'')
        {
            quotedBuf += '\'';
            out_ += quotedBuf;
            inQuote = false;
            quotedBuf.clear();
        }
        else
        {
            quotedBuf += ch;
        }
    }

    // A message that ends inside a quoted segment keeps what was read.
    if (inQuote)
        out_ += quotedBuf;
}

void DiagnosticBuilder::writeLocation(const DiagnosticElement& el)
{
    const SourceCodeRange codeRange = el.codeRange(0, *ctx_);

    SWC_ASSERT(el.srcView());
    if (el.srcView()->fileRef().isValid())
    {
        const SourceFile& file = ctx_->compiler().file(el.srcView()->fileRef());
        out_ += file.formatFileLocation(ctx_, codeRange.line, codeRange.column, codeRange.column + codeRange.len);
    }
    else
    {
        out_ += FileSystem::formatFileLocation(ctx_, fs::path{}, codeRange.line, codeRange.column, codeRange.column + codeRange.len);
    }
}

// The indented lines under a located element: the source line its first span starts on, then one
// 'line:column-end' line per span that carries a label or is not the first one.
void DiagnosticBuilder::writeSpans(const DiagnosticElement& el)
{
    constexpr std::string_view indent = "    ";

    const Utf8 excerpt = sourceExcerpt(el.srcView()->codeLine(*ctx_, el.codeRange(0, *ctx_).line));
    if (!excerpt.empty())
    {
        out_ += indent;
        out_ += excerpt;
        out_ += "\n";
    }

    for (uint32_t i = 0; i < el.spans().size(); ++i)
    {
        const DiagnosticSpan& span = el.span(i);

        Utf8 label = span.message;
        if (label.empty() && span.messageId != DiagnosticId::None)
            label = Utf8(resolveMessageTemplate(span.messageId, &el));
        if (!label.empty())
            label = buildMessage(label, &el);
        if (label.empty() && i == 0)
            continue;

        const SourceCodeRange codeRange = el.codeRange(span, *ctx_);
        out_ += indent;
        out_ += std::format("{}:{}-{}", codeRange.line, codeRange.column, codeRange.column + codeRange.len);
        if (!label.empty())
        {
            out_ += ": ";
            writeMessage(label);
        }

        out_ += "\n";
    }
}

// One element is one line, '<location>: <severity>[<id>]: <message>', followed by its indented
// span lines. An element without a source location starts at its severity.
void DiagnosticBuilder::writeElement(const DiagnosticElement& el)
{
    if (el.hasSpans())
    {
        writeLocation(el);
        out_ += ": ";
    }

    out_ += severityStr(el.severity());
    if (!el.isNoteOrHelp())
        out_ += std::format("[{}]", Diagnostic::diagIdName(el.id()));
    out_ += ": ";

    Utf8 msg = el.message();
    if (msg.empty())
        msg = buildMessage(Utf8(resolveMessageTemplate(el.id(), &el)), &el);
    writeMessage(msg);
    out_ += "\n";

    if (el.hasSpans())
        writeSpans(el);
}

// Two different types that print the same short name ('Foo' declared in two namespaces) would make
// a message such as "has type 'Foo', but needs 'Foo'" read as nonsense: those are printed qualified.
void DiagnosticBuilder::collectQualifiedTypes(SmallVector<TypeRef>& qualifiedTypes, const DiagnosticElement* el) const
{
    SmallVector<TypeRef> types;
    const auto           collect = [&](const DiagnosticArguments& arguments) {
        for (const auto& arg : arguments)
        {
            if (const TypeRef* typeRef = std::get_if<TypeRef>(&arg.val); typeRef && !typeRef->isInvalid())
                types.push_back(*typeRef);
        }
    };

    if (el)
        collect(el->arguments());
    collect(diag_->arguments());

    for (size_t i = 0; i < types.size(); ++i)
    {
        const Utf8 name = ctx_->compiler().typeMgr().get(types[i]).toName(*ctx_);
        for (size_t j = i + 1; j < types.size(); ++j)
        {
            if (types[j] == types[i] || ctx_->compiler().typeMgr().get(types[j]).toName(*ctx_) != name)
                continue;
            qualifiedTypes.push_back(types[i]);
            qualifiedTypes.push_back(types[j]);
        }
    }
}

void DiagnosticBuilder::replaceArgsInString(Utf8& result, const DiagnosticArguments& arguments, const SmallVector<TypeRef>& qualifiedTypes) const
{
    for (const auto& arg : arguments)
    {
        const TypeRef* typeRef   = std::get_if<TypeRef>(&arg.val);
        const bool     qualified = typeRef && std::ranges::find(qualifiedTypes, *typeRef) != qualifiedTypes.end();
        const Utf8     raw       = argumentToString(arg, qualified);
        size_t         pos       = 0;
        while ((pos = result.find(arg.name, pos)) != Utf8::npos)
        {
            const bool insideQuote = isInsideQuotedMessageSegment(result, pos);
            const Utf8 value       = insideQuote ? escapeQuotedMessageArgument(raw) : raw;
            result.replace(pos, arg.name.length(), value);
            pos += value.length();
        }
    }
}

Utf8 DiagnosticBuilder::buildMessage(const Utf8& msg, const DiagnosticElement* el) const
{
    Utf8 result = msg;

    SmallVector<TypeRef> qualifiedTypes;
    collectQualifiedTypes(qualifiedTypes, el);

    // Replace placeholders from the element first
    if (el)
        replaceArgsInString(result, el->arguments(), qualifiedTypes);

    // Then from the diagnostic
    replaceArgsInString(result, diag_->arguments(), qualifiedTypes);

    // Clean some stuff
    removeUnexpandedPlaceholders(result);
    removeRedundantEmptyQuotes(result);
    result.replace_loop(" , ", ", ");
    result.replace_loop("  ", " ", true);

    return result;
}

void DiagnosticBuilder::collectUniqueArgNames(std::vector<std::string_view>& argNames, const DiagnosticArguments& args)
{
    for (const auto& arg : args)
    {
        const std::string_view name = arg.name;
        if (std::ranges::find(argNames, name) == argNames.end())
            argNames.push_back(name);
    }
}

uint32_t DiagnosticBuilder::countReplacedArgs(std::string_view msg, const DiagnosticElement* el) const
{
    std::vector<std::string_view> argNames;
    argNames.reserve(diag_->arguments().size() + (el ? el->arguments().size() : 0));

    if (el)
        collectUniqueArgNames(argNames, el->arguments());
    collectUniqueArgNames(argNames, diag_->arguments());

    uint32_t count = 0;
    for (const std::string_view name : argNames)
    {
        if (msg.find(name) != std::string_view::npos)
            ++count;
    }

    return count;
}

uint32_t DiagnosticBuilder::countMessagePlaceholders(std::string_view msg)
{
    SmallVector<std::string_view> placeholders;

    for (size_t i = 0; i < msg.size(); ++i)
    {
        if (msg[i] != '{')
            continue;

        const size_t end = msg.find('}', i + 1);
        if (end == std::string_view::npos)
            break;

        const std::string_view placeholder = msg.substr(i, end - i + 1);
        if (std::ranges::find(placeholders, placeholder) == placeholders.end())
            placeholders.push_back(placeholder);
        i = end;
    }

    return static_cast<uint32_t>(placeholders.size());
}

std::string_view DiagnosticBuilder::resolveMessageTemplate(DiagnosticId id, const DiagnosticElement* el) const
{
    const std::span<const std::string_view> msgs = Diagnostic::diagIdMessages(id);
    SWC_ASSERT(!msgs.empty());

    uint32_t bestCount   = countReplacedArgs(msgs[0], el);
    uint32_t bestMissing = countMessagePlaceholders(msgs[0]) - bestCount;
    size_t   bestIndex   = 0;

    for (size_t i = 1; i < msgs.size(); ++i)
    {
        const uint32_t count   = countReplacedArgs(msgs[i], el);
        const uint32_t missing = countMessagePlaceholders(msgs[i]) - count;

        // Prefer templates that can be rendered completely. Otherwise unrelated
        // arguments (for example '{sym}' from the source expression) can make a
        // call-specific alternate win even when '{index}' is missing.
        if (bestMissing == 0)
        {
            if (missing != 0)
                continue;
            if (count <= bestCount)
                continue;
        }
        else if (missing != 0 && (count < bestCount || (count == bestCount && missing >= bestMissing)))
        {
            continue;
        }

        bestCount   = count;
        bestMissing = missing;
        bestIndex   = i;
    }

    return msgs[bestIndex];
}

// Helper function to convert variant argument to string
Utf8 DiagnosticBuilder::argumentToString(const DiagnosticArgument& arg, bool qualified) const
{
    return std::visit(DiagnosticArgumentToStringVisitor{ctx_, qualified}, arg.val);
}

Utf8 DiagnosticBuilder::formatMessage(const DiagnosticElement& element) const
{
    return buildMessage(Utf8(resolveMessageTemplate(element.id(), &element)), &element);
}

void DiagnosticBuilder::expandMessageParts(SmallVector<std::unique_ptr<DiagnosticElement>>& elements) const
{
    if (elements.empty())
        return;

    // Process elements from back to front to avoid invalidating iterators
    // and to maintain proper ordering when inserting new elements
    for (size_t idx = elements.size(); idx-- > 0;)
    {
        DiagnosticElement* element = elements[idx].get();
        const Utf8         msg     = formatMessage(*element);
        SmallVector<Part>  parts   = parseParts(std::string_view(msg));

        // Base element keeps the first part
        element->setMessage(Utf8(parts[0].text));
        parts.erase(parts.begin());
        if (parts.empty())
            continue;

        // Insert additional parts right after the current element
        size_t insertPos = idx + 1;
        for (const auto& p : parts)
        {
            const DiagnosticSeverity sev = p.tag.value_or(DiagnosticSeverity::Note);

            auto extra = std::make_unique<DiagnosticElement>(sev, element->id());
            extra->setMessage(Utf8(p.text));

            elements.insert(elements.begin() + insertPos, std::move(extra));
            ++insertPos;
        }
    }
}

SWC_END_NAMESPACE();
