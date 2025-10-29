#include "pch.h"

#include "Core/Utf8Helper.h"
#include "Diagnostic.h"
#include "DiagnosticElement.h"

SWC_BEGIN_NAMESPACE()

DiagnosticElement::DiagnosticElement(DiagnosticId id) :
    id_(id),
    severity_(Diagnostic::diagIdSeverity(id))
{
}

SourceCodeLocation DiagnosticElement::location(const Context& ctx) const
{
    SourceCodeLocation loc;
    loc.fromOffset(ctx, *file_, offset_, len_);
    return loc;
}

std::string_view DiagnosticElement::idName() const
{
    return Diagnostic::diagIdName(id_);
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
