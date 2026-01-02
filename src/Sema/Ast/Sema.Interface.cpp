#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Lexer/LangSpec.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisitResult.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Sema/Symbol/SemaMatch.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

AstStepResult AstInterfaceDecl::semaPreDecl(Sema& sema) const
{
    SemaHelpers::declareNamedSymbol<SymbolInterface>(sema, *this, tokNameRef);
    return AstStepResult::SkipChildren;
}

void AstInterfaceDecl::semaEnterNode(Sema& sema)
{
    Symbol& sym = sema.symbolOf(sema.curNodeRef());
    sym.registerAttributes(sema);
    sym.setDeclared(sema.ctx());
}

AstStepResult AstInterfaceDecl::semaPreNode(Sema& sema)
{
    const Symbol& sym = sema.symbolOf(sema.curNodeRef());
    return SemaMatch::ghosting(sema, sym);
}

AstStepResult AstInterfaceDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return AstStepResult::Continue;

    auto& ctx = sema.ctx();

    // Creates symbol with type
    SymbolInterface& sym        = sema.symbolOf(sema.curNodeRef()).cast<SymbolInterface>();
    const TypeInfo   itfType    = TypeInfo::makeInterface(&sym);
    const TypeRef    itfTypeRef = ctx.typeMgr().addType(itfType);
    sym.setTypeRef(itfTypeRef);
    sym.setTyped(sema.ctx());

    sema.pushScope(SemaScopeFlagsE::Type);
    sema.curScope().setSymMap(&sym);

    return AstStepResult::Continue;
}

AstStepResult AstInterfaceDecl::semaPostNode(Sema& sema)
{
    sema.curSymMap()->setCompleted(sema.ctx());
    sema.popScope();
    return AstStepResult::Continue;
}

SWC_END_NAMESPACE()
