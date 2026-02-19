#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"

SWC_BEGIN_NAMESPACE();

Result AstStructDecl::semaPreDecl(Sema& sema) const
{
    auto& sym = SemaHelpers::registerSymbol<SymbolStruct>(sema, *this, tokNameRef);

    // Runtime struct
    if (sym.inSwagNamespace(sema.ctx()) && sema.typeMgr().isTypeInfoRuntimeStruct(sym.idRef()))
        sym.addExtraFlag(SymbolStructFlagsE::TypeInfo);

    return Result::SkipChildren;
}

Result AstStructDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);
    const Symbol& sym = sema.symbolOf(sema.curNodeRef());
    return Match::ghosting(sema, sym);
}

Result AstStructDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeBodyRef)
    {
        TaskContext& ctx = sema.ctx();

        // Creates symbol with type
        SymbolStruct&  sym           = sema.symbolOf(sema.curNodeRef()).cast<SymbolStruct>();
        const TypeInfo structType    = TypeInfo::makeStruct(&sym);
        const TypeRef  structTypeRef = ctx.typeMgr().addType(structType);
        sym.setTypeRef(structTypeRef);
        sym.setTyped(ctx);

        sema.pushScopePopOnPostNode(SemaScopeFlagsE::Type);
        sema.curScope().setSymMap(&sym);
    }

    return Result::Continue;
}

Result AstStructDecl::semaPostNode(Sema& sema)
{
    SymbolStruct& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolStruct>();

    // Ensure all `impl` blocks (including interface implementations) have been registered
    // before a struct can be marked as completed.
    if (sema.compiler().pendingImplRegistrations() != 0)
        return sema.waitImplRegistrations(sym.idRef(), sym.codeRef());

    sym.removeIgnoredFields();
    RESULT_VERIFY(sym.canBeCompleted(sema));
    RESULT_VERIFY(sym.registerSpecOps(sema));
    RESULT_VERIFY(sym.computeLayout(sema.ctx()));

    // Runtime struct
    if (sym.inSwagNamespace(sema.ctx()))
        sema.typeMgr().registerRuntimeType(sym.idRef(), sym.typeRef());

    sym.setSemaCompleted(sema.ctx());
    return Result::Continue;
}

Result AstAnonymousStructDecl::semaPreDecl(Sema& sema) const
{
    SemaHelpers::registerUniqueSymbol<SymbolStruct>(sema, *this, "anonymous_struct");
    return Result::SkipChildren;
}

Result AstAnonymousStructDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);
    const Symbol& sym = sema.symbolOf(sema.curNodeRef());
    return Match::ghosting(sema, sym);
}

Result AstAnonymousStructDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeBodyRef)
    {
        TaskContext& ctx = sema.ctx();

        // Creates symbol with type
        SymbolStruct&  sym           = sema.symbolOf(sema.curNodeRef()).cast<SymbolStruct>();
        const TypeInfo structType    = TypeInfo::makeStruct(&sym);
        const TypeRef  structTypeRef = ctx.typeMgr().addType(structType);
        sym.setTypeRef(structTypeRef);
        sym.setTyped(ctx);

        sema.pushScopePopOnPostNode(SemaScopeFlagsE::Type);
        sema.curScope().setSymMap(&sym);
    }

    return Result::Continue;
}

Result AstAnonymousStructDecl::semaPostNode(Sema& sema)
{
    SymbolStruct& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolStruct>();

    // Ensure all `impl` blocks (including interface implementations) have been registered
    // before a struct can be marked as completed.
    if (sema.compiler().pendingImplRegistrations() != 0)
        return sema.waitImplRegistrations(sym.idRef(), sym.codeRef());

    sym.removeIgnoredFields();
    RESULT_VERIFY(sym.canBeCompleted(sema));
    RESULT_VERIFY(sym.computeLayout(sema.ctx()));
    sym.setSemaCompleted(sema.ctx());
    sema.setType(sema.curNodeRef(), sym.typeRef());
    return Result::Continue;
}

Result AstStructInitializerList::semaPostNode(Sema& sema) const
{
    SmallVector<AstNodeRef> children;
    AstNode::collectChildren(children, sema.ast(), spanArgsRef);

    RESULT_VERIFY(SemaHelpers::finalizeAggregateStruct(sema, children));

    const SemaNodeView nodeWhatView = sema.nodeViewType(nodeWhatRef);
    SemaNodeView       initView     = sema.curNodeViewNodeTypeConstant();
    RESULT_VERIFY(Cast::cast(sema, initView, nodeWhatView.typeRef, CastKind::Initialization));

    return Result::Continue;
}

SWC_END_NAMESPACE();

