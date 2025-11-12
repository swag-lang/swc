#include "pch.h"
#include "DiagnosticElement.h"
#include "Diagnostic.h"

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
    SWC_ASSERT(!file_ || loc.file == file_);
    file_ = loc.file;

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
    SWC_ASSERT(!file_ || loc.file == file_);
    file_ = loc.file;

    DiagnosticSpan span;
    span.offset    = loc.offset;
    span.len       = loc.len;
    span.severity  = severity;
    span.messageId = diagId;
    spans_.push_back(span);
}

SourceCodeLocation DiagnosticElement::location(uint32_t spanIndex, const TaskContext& ctx) const
{
    if (!file_ || spans_.empty())
        return {};
    return location(spans_[spanIndex], ctx);
}

SourceCodeLocation DiagnosticElement::location(const DiagnosticSpan& span, const TaskContext& ctx) const
{
    if (!file_)
        return {};
    SourceCodeLocation loc;
    loc.fromOffset(ctx, *file_, span.offset, span.len);
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
