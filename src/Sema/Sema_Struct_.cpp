#include "pch.h"
#include "Lexer/LangSpec.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisitResult.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaFrame.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Sema/Helpers/SemaMatch.h"
#include "Sema/Helpers/SemaNodeView.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstStructDecl::semaPreDecl(Sema& sema) const
{
    auto& ctx = sema.ctx();

    const IdentifierRef idRef     = sema.idMgr().addIdentifier(ctx, srcViewRef(), tokNameRef);
    const SymbolFlags   flags     = sema.frame().flagsForCurrentAccess();
    SymbolMap*          symbolMap = SemaFrame::currentSymMap(sema);

    SymbolStruct* sym = Symbol::make<SymbolStruct>(ctx, srcViewRef(), tokNameRef, idRef, flags);
    if (!symbolMap->addSymbol(ctx, sym, true))
        return AstVisitStepResult::Stop;
    sym->registerCompilerIf(sema);
    sema.setSymbol(sema.curNodeRef(), sym);

    return AstVisitStepResult::Continue;
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

    sema.pushScope(SemaScopeFlagsE::Type);
    sema.curScope().setSymMap(&sym);

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

AstVisitStepResult AstStructDecl::semaPostNode(Sema& sema)
{
    sema.curSymMap()->setComplete(sema.ctx());
    sema.popScope();
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
