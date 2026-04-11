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

void CastFailure::mergeArguments(const DiagnosticArguments& other)
{
    for (const auto& arg : other)
    {
        std::visit(
            [&](const auto& value) {
                addArgument(arg.name, value);
            },
            arg.val);
    }
}

namespace
{
    template<typename T>
    void applyArgumentsTo(const CastFailure& failure, T& target)
    {
        if (failure.srcTypeRef.isValid())
            target.addArgument(Diagnostic::ARG_TYPE, failure.srcTypeRef);
        if (failure.dstTypeRef.isValid())
            target.addArgument(Diagnostic::ARG_REQUESTED_TYPE, failure.dstTypeRef);
        if (failure.optTypeRef.isValid())
            target.addArgument(Diagnostic::ARG_OPT_TYPE, failure.optTypeRef);
        if (!failure.valueStr.empty() && !failure.hasArgument(Diagnostic::ARG_VALUE))
            target.addArgument(Diagnostic::ARG_VALUE, failure.valueStr);
        for (const auto& arg : failure.arguments)
            target.addArgument(arg.name, arg.val);
    }
}

void CastFailure::applyArguments(Diagnostic& diag) const
{
    applyArgumentsTo(*this, diag);
}

void CastFailure::applyArguments(DiagnosticElement& element) const
{
    applyArgumentsTo(*this, element);
}

SWC_END_NAMESPACE();
