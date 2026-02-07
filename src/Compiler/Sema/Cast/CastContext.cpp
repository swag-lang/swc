#include "pch.h"
#include "Compiler/Sema/Cast/CastContext.h"

SWC_BEGIN_NAMESPACE();

CastContext::CastContext(CastKind kind) :
    kind(kind)
{
}

Result CastContext::fail(DiagnosticId d, TypeRef srcRef, TypeRef dstRef, std::string_view value, DiagnosticId note)
{
    failure.set(errorNodeRef, d, srcRef, dstRef, value, note);
    return Result::Error;
}

void CastContext::setConstantFoldingSrc(ConstantRef v)
{
    srcConstRef = v;
    outConstRef = v;
}

void CastContext::setConstantFoldingResult(ConstantRef v)
{
    outConstRef = v;
}

SWC_END_NAMESPACE();

