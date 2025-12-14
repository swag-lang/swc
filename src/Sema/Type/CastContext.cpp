#include "pch.h"
#include "Sema/Type/CastContext.h"

SWC_BEGIN_NAMESPACE()

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

bool CastContext::isFolding() const
{
    return fold != nullptr && fold->srcConstRef.isValid();
}

ConstantRef CastContext::foldSrc() const
{
    return fold ? fold->srcConstRef : ConstantRef::invalid();
}

void CastContext::setFoldOut(ConstantRef v) const
{
    if (fold && fold->outConstRef)
        *fold->outConstRef = v;
}

SWC_END_NAMESPACE()
