#include "pch.h"
#include "Compiler/Sema/Cast/CastFailure.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

void CastFailure::set(AstNodeRef errorNodeRef, DiagnosticId d, TypeRef srcRef, TypeRef dstRef, std::string_view value, DiagnosticId note)
{
    *this      = CastFailure{};
    diagId     = d;
    nodeRef    = errorNodeRef;
    codeRef    = SourceCodeRef::invalid();
    srcTypeRef = srcRef;
    dstTypeRef = dstRef;
    valueStr   = value;
    noteId     = note;
}

bool CastFailure::hasArgument(std::string_view name) const
{
    for (const auto& a : arguments)
    {
        if (a.name == name)
            return true;
    }
    return false;
}

void CastFailure::applyArguments(Diagnostic& diag) const
{
    if (srcTypeRef.isValid())
        diag.addArgument(Diagnostic::ARG_TYPE, srcTypeRef);
    if (dstTypeRef.isValid())
        diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, dstTypeRef);
    if (optTypeRef.isValid())
        diag.addArgument(Diagnostic::ARG_OPT_TYPE, optTypeRef);
    if (!valueStr.empty() && !hasArgument(Diagnostic::ARG_VALUE))
        diag.addArgument(Diagnostic::ARG_VALUE, valueStr);
    for (const auto& arg : arguments)
        diag.addArgument(arg.name, arg.val);
}

void CastFailure::applyArguments(DiagnosticElement& element) const
{
    if (srcTypeRef.isValid())
        element.addArgument(Diagnostic::ARG_TYPE, srcTypeRef);
    if (dstTypeRef.isValid())
        element.addArgument(Diagnostic::ARG_REQUESTED_TYPE, dstTypeRef);
    if (optTypeRef.isValid())
        element.addArgument(Diagnostic::ARG_OPT_TYPE, optTypeRef);
    if (!valueStr.empty() && !hasArgument(Diagnostic::ARG_VALUE))
        element.addArgument(Diagnostic::ARG_VALUE, valueStr);
    for (const auto& arg : arguments)
        element.addArgument(arg.name, arg.val);
}

SWC_END_NAMESPACE();
