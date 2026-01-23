#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Lexer/LangSpec.h"
#include "Parser/AstNodes.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Match/Match.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

Result AstInterfaceDecl::semaPreDecl(Sema& sema) const
{
    SemaHelpers::registerSymbol<SymbolInterface>(sema, *this, tokNameRef);
    return Result::SkipChildren;
}

Result AstInterfaceDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);
    const Symbol& sym = sema.symbolOf(sema.curNodeRef());
    return Match::ghosting(sema, sym);
}

Result AstInterfaceDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    auto& ctx = sema.ctx();

    // Creates symbol with type
    SymbolInterface& symItf     = sema.symbolOf(sema.curNodeRef()).cast<SymbolInterface>();
    const TypeInfo   itfType    = TypeInfo::makeInterface(&symItf);
    const TypeRef    itfTypeRef = ctx.typeMgr().addType(itfType);
    symItf.setTypeRef(itfTypeRef);
    symItf.setTyped(sema.ctx());

    SemaFrame frame = sema.frame();
    frame.setInterface(&symItf);
    sema.pushFrameAutoPopOnPostNode(frame);
    sema.pushScopeAutoPopOnPostNode(SemaScopeFlagsE::Type | SemaScopeFlagsE::Interface);
    sema.curScope().setSymMap(&symItf);

    return Result::Continue;
}

Result AstInterfaceDecl::semaPostNode(Sema& sema)
{
    auto& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolInterface>();
    RESULT_VERIFY(sym.canBeCompleted(sema));
    sym.setCompleted(sema.ctx());
    return Result::Continue;
}

SWC_END_NAMESPACE();
