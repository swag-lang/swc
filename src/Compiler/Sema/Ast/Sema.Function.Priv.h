#pragma once

SWC_BEGIN_NAMESPACE();

class Sema;

namespace SemaFunction::Internal
{
    Result concretizeImplicitReturnTypeIfNeeded(Sema& sema, AstNodeRef exprRef, TypeRef& ioTypeRef);
    Result resolveReturnTypeRef(Sema& sema, AstNodeRef exprRef, TypeRef& outTypeRef);
    Result validateReturnStatementValue(Sema& sema, AstNodeRef returnRef, AstNodeRef exprRef, TypeRef returnTypeRef);
}

SWC_END_NAMESPACE();
