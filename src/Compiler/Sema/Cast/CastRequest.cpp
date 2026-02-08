#include "pch.h"
#include "Compiler/Sema/Cast/CastRequest.h"

SWC_BEGIN_NAMESPACE();

CastRequest::CastRequest(CastKind kind) :
    kind(kind)
{
}

Result CastRequest::fail(DiagnosticId d, TypeRef srcRef, TypeRef dstRef, std::string_view value, DiagnosticId note)
{
    failure.set(errorNodeRef, d, srcRef, dstRef, value, note);
    if (errorCodeRef.isValid())
        failure.codeRef = errorCodeRef;
    return Result::Error;
}

void CastRequest::setConstantFoldingSrc(ConstantRef v)
{
    srcConstRef = v;
    outConstRef = v;
}

void CastRequest::setConstantFoldingResult(ConstantRef v)
{
    outConstRef = v;
}

SWC_END_NAMESPACE();
