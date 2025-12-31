#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Lexer/LangSpec.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisitResult.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Sema/Helpers/SemaMatch.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstInterfaceDecl::semaPreDecl(Sema& sema) const
{
    SemaHelpers::declareNamedSymbol<SymbolInterface>(sema, *this, tokNameRef);
    return AstVisitStepResult::SkipChildren;
}

void AstInterfaceDecl::semaEnterNode(Sema& sema)
{
    Symbol& sym = sema.symbolOf(sema.curNodeRef());
    sym.registerAttributes(sema);
    sym.setDeclared(sema.ctx());
}

AstVisitStepResult AstInterfaceDecl::semaPreNode(Sema& sema)
{
    const Symbol& sym = sema.symbolOf(sema.curNodeRef());
    return SemaMatch::ghosting(sema, sym);
}

AstVisitStepResult AstInterfaceDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return AstVisitStepResult::Continue;

    auto& ctx = sema.ctx();

    // Creates symbol with type
    SymbolInterface& sym        = sema.symbolOf(sema.curNodeRef()).cast<SymbolInterface>();
    const TypeInfo   itfType    = TypeInfo::makeInterface(&sym);
    const TypeRef    itfTypeRef = ctx.typeMgr().addType(itfType);
    sym.setTypeRef(itfTypeRef);

    sema.pushScope(SemaScopeFlagsE::Type);
    sema.curScope().setSymMap(&sym);

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstInterfaceDecl::semaPostNode(Sema& sema)
{
    sema.curSymMap()->setComplete(sema.ctx());
    sema.popScope();
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
