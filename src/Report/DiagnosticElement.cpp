#include "pch.h"

#include "Diagnostic.h"
#include "DiagnosticElement.h"

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

void DiagnosticElement::setLocation(const SourceFile* file)
{
    file_ = file;
    len_  = 0;
}

void DiagnosticElement::setLocation(const SourceFile* file, uint32_t offset, uint32_t len)
{
    file_   = file;
    offset_ = offset;
    len_    = len;
}

void DiagnosticElement::setLocation(const SourceCodeLocation& loc)
{
    file_   = loc.file;
    offset_ = loc.offset;
    len_    = loc.len;
}

void DiagnosticElement::inheritLocationFrom(const DiagnosticElement& other)
{
    file_   = other.file_;
    offset_ = other.offset_;
    len_    = other.len_;
}

SourceCodeLocation DiagnosticElement::location(const Context& ctx) const
{
    SourceCodeLocation loc;
    if (!file_)
        return loc;
    loc.fromOffset(ctx, *file_, offset_, len_);
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

SWC_END_NAMESPACE()
