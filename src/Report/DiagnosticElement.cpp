#include "pch.h"

#include "Diagnostic.h"
#include "DiagnosticElement.h"
#include "Os/Os.h"

SWC_BEGIN_NAMESPACE()

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

void DiagnosticElement::addSpan(const SourceFile* file, uint32_t offset, uint32_t len, DiagnosticSeverity severity, const Utf8& message)
{
    SWC_ASSERT(!file_ || file_ == file);
    file_ = file;

    DiagnosticSpan span;
    span.offset   = offset;
    span.len      = len;
    span.severity = severity;
    span.message  = message;
    spans_.push_back(span);
}

void DiagnosticElement::addSpan(const SourceCodeLocation& loc, const Utf8& message, DiagnosticSeverity severity)
{
    SWC_ASSERT(!file_ || loc.file == file_);
    file_ = loc.file;

    DiagnosticSpan span;
    span.offset   = loc.offset;
    span.len      = loc.len;
    span.severity = severity;
    span.message  = message;
    spans_.push_back(span);
}

void DiagnosticElement::addSpan(const SourceCodeLocation& loc, DiagnosticId diagId, DiagnosticSeverity severity)
{
    SWC_ASSERT(!file_ || loc.file == file_);
    file_ = loc.file;

    DiagnosticSpan span;
    span.offset    = loc.offset;
    span.len       = loc.len;
    span.severity  = severity;
    span.messageId = diagId;
    spans_.push_back(span);
}

SourceCodeLocation DiagnosticElement::location(uint32_t spanIndex, const Context& ctx) const
{
    SourceCodeLocation loc;
    if (!file_ || spans_.empty())
        return loc;
    SWC_ASSERT(spanIndex < spans_.size());
    loc.fromOffset(ctx, *file_, spans_[spanIndex].offset, spans_[spanIndex].len);
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

SWC_END_NAMESPACE()
