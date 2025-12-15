#include "pch.h"
#include "Sema/Type/CastContext.h"

SWC_BEGIN_NAMESPACE()

void CastFailure::reset(AstNodeRef errorNodeRef)
{
    *this      = CastFailure{};
    diagId     = DiagnosticId::None;
    noteId     = DiagnosticId::None;
    nodeRef    = errorNodeRef;
    srcTypeRef = TypeRef{};
    dstTypeRef = TypeRef{};
    valueStr.clear();
}

void CastFailure::set(AstNodeRef errorNodeRef, DiagnosticId d, TypeRef src, TypeRef dst)
{
    *this      = CastFailure{};
    diagId     = d;
    nodeRef    = errorNodeRef;
    srcTypeRef = src;
    dstTypeRef = dst;
}

void CastFailure::setValueNote(AstNodeRef errorNodeRef, DiagnosticId d, TypeRef src, TypeRef dst, std::string_view value, DiagnosticId note)
{
    *this      = CastFailure{};
    diagId     = d;
    nodeRef    = errorNodeRef;
    srcTypeRef = src;
    dstTypeRef = dst;
    valueStr   = std::string(value);
    noteId     = note;
}

CastContext::CastContext(CastKind kind) :
    kind(kind)
{
}

void CastContext::resetFailure()
{
    failure.reset(errorNodeRef);
}

void CastContext::fail(DiagnosticId d, TypeRef src, TypeRef dst)
{
    failure.set(errorNodeRef, d, src, dst);
}

void CastContext::failValueNote(DiagnosticId d, TypeRef src, TypeRef dst, std::string_view value, DiagnosticId note)
{
    failure.setValueNote(errorNodeRef, d, src, dst, value, note);
}

SWC_END_NAMESPACE()
