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

    // The excerpt is a window around the actual span, even when it starts late on a line.
    constexpr size_t EXCERPT_MAX_BYTES = 200;

    Utf8 sourceExcerpt(std::string_view line, uint32_t column)
    {
        constexpr std::string_view blanks = " \t\r\n";
        const size_t               first  = line.find_first_not_of(blanks);
        if (first == std::string_view::npos)
            return {};

        const size_t end   = line.find_last_not_of(blanks) + 1;
        size_t       start = first;
        if (end - first > EXCERPT_MAX_BYTES)
        {
            size_t focus = 0;
            for (uint32_t current = 1; current < column && focus < end; ++current)
            {
                ++focus;
                while (focus < end && (static_cast<unsigned char>(line[focus]) & 0xc0) == 0x80)
                    ++focus;
            }

            constexpr size_t before = EXCERPT_MAX_BYTES / 3;
            if (focus > first + before)
                start = std::min(focus - before, end - EXCERPT_MAX_BYTES);
            while ((static_cast<unsigned char>(line[start]) & 0xc0) == 0x80)
                ++start;
        }

        size_t stop = std::min(start + EXCERPT_MAX_BYTES, end);
        while (stop < end && (static_cast<unsigned char>(line[stop]) & 0xc0) == 0x80)
            --stop;

        Utf8 excerpt;
        if (start > first)
            excerpt += "... ";
        excerpt += line.substr(start, stop - start);
        if (stop < end)
            excerpt += " ...";
        return excerpt;
    }

    uint32_t endColumn(const TaskContext& ctx, const SourceCodeRange& range)
    {
        if (!range.len)
            return range.column;

        SourceCodeRange end;
        end.fromOffset(ctx, *range.srcView, range.offset + range.len, 0);
        return end.line == range.line ? end.column : range.column;
    }

    void appendDiagnosticText(Utf8& out, std::string_view text)
    {
        for (const unsigned char byte : text)
        {
            if (byte >= ' ' && byte <= '~')
                out += static_cast<char>(byte);
            else
                out += std::format("\\x{:02X}", byte);
        }
    }

    bool isAsciiIdentifierHead(const char ch)
    {
        const unsigned char uch = static_cast<unsigned char>(ch);
        return std::isalpha(uch) || ch == '_';
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

    size_t placeholderEnd(std::string_view message, size_t start)
    {
        size_t end = start + 1;
        while (end < message.size() && (Utf8Helper::isAsciiWordCharacter(message[end]) || message[end] == '-'))
            ++end;

        return end > start + 1 && end < message.size() && message[end] == '}' ? end : std::string_view::npos;
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

    // Render notes before help, so the information needed to choose a repair stays
    // with the error. Only the catalog can create a new diagnostic record.
    SmallVector<PendingHelp> helps;
    for (const auto& element : diag_->elements())
    {
        const auto parts = parseParts(resolveMessageTemplate(element->id(), element.get()));
        SWC_ASSERT(!parts.empty());
        for (size_t i = 0; i < parts.size(); ++i)
        {
            const DiagnosticSeverity severity = i == 0 ? element->severity() : parts[i].tag.value_or(DiagnosticSeverity::Note);
            const DiagnosticElement* location = i == 0 ? element.get() : nullptr;
            Utf8                     message  = buildMessage(parts[i].text, element.get());
            if (!location && Utf8Helper::trim(message).empty())
                continue;
            if (severity == DiagnosticSeverity::Help)
                helps.push_back({.element = location, .message = std::move(message)});
            else
                writeElement(severity, location, message);
        }
    }

    for (const PendingHelp& help : helps)
        writeElement(DiagnosticSeverity::Help, help.element, help.message);

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
            if (c == '\'' && !isLiteralSuffixQuote(msg, i))
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
        const std::string_view                  body = sev ? stripLeadingTagHeader(raw) : raw;
        out.push_back({.tag = sev, .text = body});
    }

    return out;
}

void DiagnosticBuilder::writeLocation(const DiagnosticElement& el)
{
    const SourceCodeRange codeRange = el.codeRange(0, *ctx_);

    SWC_ASSERT(el.srcView());
    const uint32_t columnEnd = endColumn(*ctx_, codeRange);
    if (el.srcView()->fileRef().isValid())
    {
        const SourceFile& file = ctx_->compiler().file(el.srcView()->fileRef());
        appendDiagnosticText(out_, file.formatFileLocation(codeRange.line, codeRange.column, columnEnd));
    }
    else
    {
        appendDiagnosticText(out_, FileSystem::formatPathLocation(fs::path{}, codeRange.line, codeRange.column, columnEnd));
    }
}

// The indented lines under a located element: the source line its first span starts on, then one
// 'line:column-end' line per span that carries a label or is not the first one.
void DiagnosticBuilder::writeSpans(const DiagnosticElement& el)
{
    constexpr std::string_view indent = "    ";

    const SourceCodeRange first   = el.codeRange(0, *ctx_);
    const Utf8            excerpt = sourceExcerpt(el.srcView()->codeLine(*ctx_, first.line), first.column);
    if (!excerpt.empty())
    {
        out_ += indent;
        appendDiagnosticText(out_, excerpt);
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
        out_ += std::format("{}:{}-{}", codeRange.line, codeRange.column, endColumn(*ctx_, codeRange));
        if (!label.empty())
        {
            out_ += ": ";
            appendDiagnosticText(out_, label);
        }

        out_ += "\n";
    }
}

// One element is one line, '<location>: <severity>[<id>]: <message>', followed by its indented
// span lines. An element without a source location starts at its severity.
void DiagnosticBuilder::writeElement(DiagnosticSeverity severity, const DiagnosticElement* element, std::string_view message)
{
    if (element && element->hasSpans())
    {
        writeLocation(*element);
        out_ += ": ";
    }

    out_ += severityStr(severity);
    if (severity == DiagnosticSeverity::Error || severity == DiagnosticSeverity::Warning)
    {
        SWC_ASSERT(element);
        out_ += std::format("[{}]", Diagnostic::diagIdName(element->id()));
    }
    out_ += ": ";
    appendDiagnosticText(out_, message);
    out_ += "\n";

    if (element && element->hasSpans())
        writeSpans(*element);
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

Utf8 DiagnosticBuilder::buildMessage(std::string_view message, const DiagnosticElement* element) const
{
    SmallVector<TypeRef> qualifiedTypes;
    collectQualifiedTypes(qualifiedTypes, element);

    Utf8 result;
    result.reserve(message.size());

    bool missingArgument = false;
    for (size_t i = 0; i < message.size(); ++i)
    {
        if (message[i] != '{')
        {
            result += message[i];
            continue;
        }

        const size_t end = placeholderEnd(message, i);
        if (end == std::string_view::npos)
        {
            result += message[i];
            continue;
        }

        const auto                name     = message.substr(i, end - i + 1);
        const DiagnosticArgument* argument = nullptr;
        if (element)
        {
            const auto& args = element->arguments();
            const auto  it   = std::ranges::find(args, name, &DiagnosticArgument::name);
            if (it != args.end())
                argument = &*it;
        }
        if (!argument)
        {
            const auto& args = diag_->arguments();
            const auto  it   = std::ranges::find(args, name, &DiagnosticArgument::name);
            if (it != args.end())
                argument = &*it;
        }

        if (argument)
        {
            const TypeRef* typeRef   = std::get_if<TypeRef>(&argument->val);
            const bool     qualified = typeRef && std::ranges::find(qualifiedTypes, *typeRef) != qualifiedTypes.end();
            result += argumentToString(*argument, qualified);
        }
        else
        {
            missingArgument = true;
        }

        i = end;
    }

    // Incomplete variants are a fallback. Keep cleanup away from normal
    // substitutions so paths, literal text and generated source stay intact.
    if (missingArgument)
    {
        removeRedundantEmptyQuotes(result);
        result.replace_loop(" , ", ", ");
        result.replace_loop("  ", " ", true);
    }

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

        const size_t end = placeholderEnd(msg, i);
        if (end == std::string_view::npos)
            continue;

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
    return buildMessage(resolveMessageTemplate(element.id(), &element), &element);
}

Utf8 DiagnosticBuilder::formatReasonMessage(const DiagnosticElement& element) const
{
    Utf8 reason;
    for (const Part& part : parseParts(resolveMessageTemplate(element.id(), &element)))
    {
        if (part.tag == DiagnosticSeverity::Help)
            continue;
        if (!reason.empty())
            reason += "; ";
        reason += buildMessage(part.text, &element);
    }
    return reason;
}

SWC_END_NAMESPACE();
