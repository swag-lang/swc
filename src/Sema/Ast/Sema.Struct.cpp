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

AstVisitStepResult AstStructDecl::semaPreDecl(Sema& sema) const
{
    SemaHelpers::declareNamedSymbol<SymbolStruct>(sema, *this, tokNameRef);
    return AstVisitStepResult::SkipChildren;
}

void AstStructDecl::semaEnterNode(Sema& sema)
{
    Symbol& sym = sema.symbolOf(sema.curNodeRef());
    sym.registerAttributes(sema);
    sym.setDeclared(sema.ctx());
}

AstVisitStepResult AstStructDecl::semaPreNode(Sema& sema)
{
    const Symbol& sym = sema.symbolOf(sema.curNodeRef());
    return SemaMatch::ghosting(sema, sym);
}

AstVisitStepResult AstStructDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return AstVisitStepResult::Continue;

    auto& ctx = sema.ctx();

    // Creates symbol with type
    SymbolStruct&  sym           = sema.symbolOf(sema.curNodeRef()).cast<SymbolStruct>();
    const TypeInfo structType    = TypeInfo::makeStruct(&sym);
    const TypeRef  structTypeRef = ctx.typeMgr().addType(structType);
    sym.setTypeRef(structTypeRef);
    sym.setTyped(sema.ctx());

    sema.pushScope(SemaScopeFlagsE::Type);
    sema.curScope().setSymMap(&sym);

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstStructDecl::semaPostNode(Sema& sema)
{
    SymbolStruct& sym = sema.curSymMap()->cast<SymbolStruct>();
    sym.computeLayout(sema);
    sym.setCompleted(sema.ctx());
    sema.popScope();
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
