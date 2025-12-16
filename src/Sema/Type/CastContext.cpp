#include "pch.h"
#include "Sema/Type/CastContext.h"

SWC_BEGIN_NAMESPACE()

void CastFailure::set(AstNodeRef errorNodeRef, DiagnosticId d, TypeRef srcRef, TypeRef dstRef, std::string_view value, DiagnosticId note)
{
    *this      = CastFailure{};
    diagId     = d;
    nodeRef    = errorNodeRef;
    srcTypeRef = srcRef;
    dstTypeRef = dstRef;
    valueStr   = std::string(value);
    noteId     = note;
}

CastContext::CastContext(CastKind kind) :
    kind(kind)
{
}

void CastContext::fail(DiagnosticId d, TypeRef srcRef, TypeRef dstRef, std::string_view value, DiagnosticId note)
{
    failure.set(errorNodeRef, d, srcRef, dstRef, value, note);
}

SWC_END_NAMESPACE()
