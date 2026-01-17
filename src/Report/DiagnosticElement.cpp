#include "pch.h"
#include "DiagnosticElement.h"
#include "Core/Utf8Helper.h"
#include "Diagnostic.h"

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

void DiagnosticElement::addSpan(const SourceCodeLocation& loc, const Utf8& message, DiagnosticSeverity severity)
{
    SWC_ASSERT(!srcView_ || loc.srcView == srcView_);
    srcView_ = loc.srcView;

    if (!loc.len)
        return;
    DiagnosticSpan span;
    span.offset   = loc.offset;
    span.len      = loc.len;
    span.severity = severity;
    span.message  = message;
    spans_.push_back(span);
}

void DiagnosticElement::addSpan(const SourceCodeLocation& loc, DiagnosticId diagId, DiagnosticSeverity severity)
{
    SWC_ASSERT(!srcView_ || loc.srcView == srcView_);
    srcView_ = loc.srcView;

    DiagnosticSpan span;
    span.offset    = loc.offset;
    span.len       = loc.len;
    span.severity  = severity;
    span.messageId = diagId;
    spans_.push_back(span);
}

SourceCodeLocation DiagnosticElement::location(uint32_t spanIndex, const TaskContext& ctx) const
{
    if (!srcView_ || spans_.empty())
        return {};
    return location(spans_[spanIndex], ctx);
}

SourceCodeLocation DiagnosticElement::location(const DiagnosticSpan& span, const TaskContext& ctx) const
{
    if (!srcView_)
        return {};
    SourceCodeLocation loc;
    loc.fromOffset(ctx, *srcView_, span.offset, span.len);
    return loc;
}

std::string_view DiagnosticElement::idName() const
{
    return Diagnostic::diagIdName(id_);
}

bool DiagnosticElement::isNoteOrHelp() const
{
    return severity_ == DiagnosticSeverity::Note || severity_ == DiagnosticSeverity::Help;
}

void DiagnosticElement::addArgument(std::string_view name, std::string_view arg, bool quoted)
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
            a.val    = std::move(sanitized);
            a.quoted = quoted;
            return;
        }
    }

    arguments_.emplace_back(DiagnosticArgument{.name = name, .quoted = quoted, .val = std::move(sanitized)});
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
