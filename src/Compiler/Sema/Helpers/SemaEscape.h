#pragma once
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;
class SymbolVariable;

namespace SemaEscape
{
    bool   typeCanCarryBorrow(Sema& sema, TypeRef typeRef);
    Result checkVariableInitializer(Sema& sema, const SymbolVariable& symVar, AstNodeRef initRef, TypeRef targetTypeRef);
    Result applyAssignment(Sema& sema, AstNodeRef leftRef, AstNodeRef rightRef);
    Result checkReturn(Sema& sema, AstNodeRef returnRef, AstNodeRef exprRef, TypeRef returnTypeRef, const SymbolFunction* inlineSourceFn);
    void   bindForeachAddressAlias(Sema& sema, const SymbolVariable& symVar, AstNodeRef exprRef);
}

SWC_END_NAMESPACE();
