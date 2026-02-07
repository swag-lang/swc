#include "pch.h"
#include "Compiler/Sema/Cast/CastContext.h"

SWC_BEGIN_NAMESPACE();

CastContext::CastContext(CastKind kind) :
    kind(kind)
{
}

void CastContext::fail(DiagnosticId d, TypeRef srcRef, TypeRef dstRef, std::string_view value, DiagnosticId note)
{
    failure.set(errorNodeRef, d, srcRef, dstRef, value, note);
}

SWC_END_NAMESPACE();
