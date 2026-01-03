#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Lexer/LangSpec.h"
#include "Parser/AstNodes.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Sema/Symbol/SemaMatch.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

Result AstInterfaceDecl::semaPreDecl(Sema& sema) const
{
    SemaHelpers::registerSymbol<SymbolInterface>(sema, *this, tokNameRef);
    return Result::SkipChildren;
}

void AstInterfaceDecl::semaEnterNode(Sema& sema) const
{
    SemaHelpers::declareSymbol(sema, *this);
}

Result AstInterfaceDecl::semaPreNode(Sema& sema)
{
    const Symbol& sym = sema.symbolOf(sema.curNodeRef());
    return SemaMatch::ghosting(sema, sym);
}

Result AstInterfaceDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    auto& ctx = sema.ctx();

    // Creates symbol with type
    SymbolInterface& sym        = sema.symbolOf(sema.curNodeRef()).cast<SymbolInterface>();
    const TypeInfo   itfType    = TypeInfo::makeInterface(&sym);
    const TypeRef    itfTypeRef = ctx.typeMgr().addType(itfType);
    sym.setTypeRef(itfTypeRef);
    sym.setTyped(sema.ctx());

    sema.pushScope(SemaScopeFlagsE::Type);
    sema.curScope().setSymMap(&sym);

    return Result::Continue;
}

Result AstInterfaceDecl::semaPostNode(Sema& sema)
{
    sema.curSymMap()->setCompleted(sema.ctx());
    sema.popScope();
    return Result::Continue;
}

SWC_END_NAMESPACE()
