#include "pch.h"
#include "DiagnosticElement.h"
#include "Diagnostic.h"
#include "Compiler/Lexer/SourceView.h"
#include "Support/Core/Utf8Helper.h"

SWC_BEGIN_NAMESPACE();

DiagnosticElement::DiagnosticElement(DiagnosticId id) :
    id_(id),
    severity_(Diagnostic::diagIdSeverity(id))
{
}

DiagnosticElement::DiagnosticElement(DiagnosticSeverity severity, DiagnosticId id) :
    id_(id),
    severity_(severity)
{
}

void DiagnosticElement::addSpan(const SourceView* srcView, uint32_t offset, uint32_t len, DiagnosticSeverity severity, const Utf8& message)
{
    SWC_ASSERT(!srcView_ || srcView_ == srcView);
    srcView_ = srcView;

    if (!len)
        return;
    DiagnosticSpan span;
    span.offset   = offset;
    span.len      = len;
    span.severity = severity;
    span.message  = message;
    spans_.push_back(span);
}

void DiagnosticElement::addSpan(const SourceCodeRange& codeRange, const Utf8& message, DiagnosticSeverity severity)
{
    SWC_ASSERT(!srcView_ || codeRange.srcView == srcView_);
    srcView_ = codeRange.srcView;

    if (!codeRange.len)
        return;
    DiagnosticSpan span;
    span.offset   = codeRange.offset;
    span.len      = codeRange.len;
    span.severity = severity;
    span.message  = message;
    spans_.push_back(span);
}

void DiagnosticElement::addSpan(const SourceCodeRange& codeRange, DiagnosticId diagId, DiagnosticSeverity severity)
{
    SWC_ASSERT(!srcView_ || codeRange.srcView == srcView_);
    srcView_ = codeRange.srcView;

    DiagnosticSpan span;
    span.offset    = codeRange.offset;
    span.len       = codeRange.len;
    span.severity  = severity;
    span.messageId = diagId;
    spans_.push_back(span);
}

SourceCodeRange DiagnosticElement::codeRange(uint32_t spanIndex, const TaskContext& ctx) const
{
    if (!srcView_ || spans_.empty())
        return {};
    return codeRange(spans_[spanIndex], ctx);
}

SourceCodeRange DiagnosticElement::codeRange(const DiagnosticSpan& span, const TaskContext& ctx) const
{
    if (!srcView_)
        return {};

    SourceCodeRange codeRange;
    codeRange.fromOffset(ctx, *srcView_, span.offset, span.len);

    // Truncate at the first newline if necessary.
    const auto str = srcView_->codeView(span.offset, span.len);
    const auto pos = str.find_first_of("\n\r");
    if (pos != std::string_view::npos)
        codeRange.len = static_cast<uint32_t>(pos);

    return codeRange;
}

std::string_view DiagnosticElement::idName() const
{
    return Diagnostic::diagIdName(id_);
}

bool DiagnosticElement::isNoteOrHelp() const
{
    return severity_ == DiagnosticSeverity::Note || severity_ == DiagnosticSeverity::Help;
}

void DiagnosticElement::addArgument(std::string_view name, std::string_view arg)
{
    Utf8 sanitized;
    sanitized.reserve(arg.size());

    auto       ptr = reinterpret_cast<const char8_t*>(arg.data());
    const auto end = ptr + arg.size();
    while (ptr < end)
    {
        auto [buf, wc, eat] = Utf8Helper::decodeOneChar(ptr, end);
        if (!buf)
        {
            ptr++;
            continue;
        }

        if ((wc < 128 && !std::isprint(static_cast<int>(wc))) || wc >= 128)
        {
            char hex[10];
            (void) std::snprintf(hex, sizeof(hex), "\\x%02X", static_cast<uint32_t>(wc));
            sanitized += hex;
            ptr = buf;
        }
        else if (wc == '\t' || wc == '\n' || wc == '\r')
        {
            sanitized += ' ';
            ptr = buf;
        }
        else
        {
            while (ptr < buf)
                sanitized += static_cast<char>(*ptr++);
        }
    }

    // Replace it if the same argument already exists
    for (auto& a : arguments_)
    {
        if (a.name == name)
        {
            a.val = std::move(sanitized);
            return;
        }
    }

    arguments_.emplace_back(DiagnosticArgument{.name = name, .val = std::move(sanitized)});
}

// Format a string by replacing registered arguments
Utf8 DiagnosticElement::message() const
{
    if (!message_.empty())
        return message_;

    Utf8 result{Diagnostic::diagIdMessage(id_)};
    return result;
}

void DiagnosticElement::setMessage(Utf8 m)
{
    message_ = std::move(m);
}

SWC_END_NAMESPACE();
