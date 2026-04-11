#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result pushStructInitializerChildBindingType(Sema& sema, AstNodeRef childRef, TypeRef targetTypeRef, SpanRef spanArgsRef)
    {
        SmallVector<AstNodeRef> children;
        AstNode::collectChildren(children, sema.ast(), spanArgsRef);

        TypeRef bindingTypeRef = TypeRef::invalid();
        SWC_RESULT(SemaHelpers::resolveStructLikeChildBindingType(sema, children.span(), childRef, targetTypeRef, bindingTypeRef));
        if (!bindingTypeRef.isValid())
            return Result::Continue;

        auto frame = sema.frame();
        frame.pushBindingType(bindingTypeRef);
        sema.pushFramePopOnPostChild(frame, childRef);
        return Result::Continue;
    }
}

Result AstStructDecl::semaPreDecl(Sema& sema) const
{
    auto& sym = SemaHelpers::registerSymbol<SymbolStruct>(sema, *this, tokNameRef);
    sym.setDeclNodeRef(sema.curNodeRef());
    sym.setGenericRoot(spanGenericParamsRef.isValid());

    // Runtime struct
    if (sym.inSwagNamespace(sema.ctx()) && sema.typeMgr().isTypeInfoRuntimeStruct(sym.idRef()))
        sym.addExtraFlag(SymbolStructFlagsE::TypeInfo);

    return Result::SkipChildren;
}

Result AstStructDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);
    const auto& sym = sema.curViewSymbol().sym()->cast<SymbolStruct>();
    SWC_RESULT(Match::ghosting(sema, sym));
    if (sym.isGenericRoot() && !sym.isGenericInstance())
    {
        sema.curViewSymbol().sym()->setSemaCompleted(sema.ctx());
        return Result::SkipChildren;
    }
    return Result::Continue;
}

Result AstStructDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeBodyRef)
    {
        TaskContext& ctx = sema.ctx();

        // Creates symbol with type
        auto&          sym           = sema.curViewSymbol().sym()->cast<SymbolStruct>();
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
    auto& sym = sema.curViewSymbol().sym()->cast<SymbolStruct>();
    if (sym.isGenericRoot() && !sym.isGenericInstance())
        return Result::Continue;

    // Ensure all `impl` blocks (including interface implementations) have been registered
    // before a struct can be marked as completed.
    if (sema.compiler().pendingImplRegistrations() != 0)
        return sema.waitImplRegistrations(sym.idRef(), sym.codeRef());

    sym.removeIgnoredFields();
    SWC_RESULT(sym.canBeCompleted(sema));
    SWC_RESULT(sym.registerSpecOps(sema));
    SWC_RESULT(sym.computeLayout(sema.ctx()));

    // Runtime struct
    if (sym.inSwagNamespace(sema.ctx()))
        sema.typeMgr().registerRuntimeType(sym.idRef(), sym.typeRef());

    if (sym.isGenericInstance())
        return Result::Continue;

    sym.setSemaCompleted(sema.ctx());
    return Result::Continue;
}

Result AstUnionDecl::semaPreDecl(Sema& sema) const
{
    auto& sym = SemaHelpers::registerSymbol<SymbolStruct>(sema, *this, tokNameRef);
    sym.setDeclNodeRef(sema.curNodeRef());
    sym.setGenericRoot(spanGenericParamsRef.isValid());
    sym.addExtraFlag(SymbolStructFlagsE::Union);
    return Result::SkipChildren;
}

Result AstUnionDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);
    const auto& sym = sema.curViewSymbol().sym()->cast<SymbolStruct>();
    SWC_RESULT(Match::ghosting(sema, sym));
    if (sym.isGenericRoot() && !sym.isGenericInstance())
    {
        sema.curViewSymbol().sym()->setSemaCompleted(sema.ctx());
        return Result::SkipChildren;
    }
    return Result::Continue;
}

Result AstUnionDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeBodyRef)
    {
        TaskContext& ctx = sema.ctx();

        auto&          sym           = sema.curViewSymbol().sym()->cast<SymbolStruct>();
        const TypeInfo structType    = TypeInfo::makeStruct(&sym);
        const TypeRef  structTypeRef = ctx.typeMgr().addType(structType);
        sym.setTypeRef(structTypeRef);
        sym.setTyped(ctx);

        sema.pushScopePopOnPostNode(SemaScopeFlagsE::Type);
        sema.curScope().setSymMap(&sym);
    }

    return Result::Continue;
}

Result AstUnionDecl::semaPostNode(Sema& sema)
{
    auto& sym = sema.curViewSymbol().sym()->cast<SymbolStruct>();
    if (sym.isGenericRoot() && !sym.isGenericInstance())
        return Result::Continue;

    if (sema.compiler().pendingImplRegistrations() != 0)
        return sema.waitImplRegistrations(sym.idRef(), sym.codeRef());

    sym.removeIgnoredFields();
    SWC_RESULT(sym.canBeCompleted(sema));
    SWC_RESULT(sym.registerSpecOps(sema));
    SWC_RESULT(sym.computeLayout(sema.ctx()));

    if (sym.isGenericInstance())
        return Result::Continue;

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
    const Symbol& sym = *sema.curViewSymbol().sym();
    return Match::ghosting(sema, sym);
}

Result AstAnonymousStructDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeBodyRef)
    {
        TaskContext& ctx = sema.ctx();

        // Creates symbol with type
        auto&          sym           = sema.curViewSymbol().sym()->cast<SymbolStruct>();
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
    auto& sym = sema.curViewSymbol().sym()->cast<SymbolStruct>();

    // Ensure all `impl` blocks (including interface implementations) have been registered
    // before a struct can be marked as completed.
    if (sema.compiler().pendingImplRegistrations() != 0)
        return sema.waitImplRegistrations(sym.idRef(), sym.codeRef());

    sym.removeIgnoredFields();
    SWC_RESULT(sym.canBeCompleted(sema));
    SWC_RESULT(sym.computeLayout(sema.ctx()));
    sym.setSemaCompleted(sema.ctx());
    sema.setType(sema.curNodeRef(), sym.typeRef());
    return Result::Continue;
}

Result AstStructInitializerList::semaPostNode(Sema& sema) const
{
    SmallVector<AstNodeRef> children;
    AstNode::collectChildren(children, sema.ast(), spanArgsRef);

    SWC_RESULT(SemaHelpers::finalizeAggregateStruct(sema, children));
    SemaNodeView initView = sema.curViewNodeTypeConstant();
    SWC_RESULT(SemaHelpers::attachLiteralRuntimeStorageIfNeeded(sema, *this, initView));

    const SemaNodeView nodeWhatView = sema.viewType(nodeWhatRef);
    SWC_RESULT(Cast::cast(sema, initView, nodeWhatView.typeRef(), CastKind::Initialization));

    return Result::Continue;
}

Result AstStructInitializerList::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeWhatRef)
        return Result::Continue;

    const TypeRef targetTypeRef = sema.viewType(nodeWhatRef).typeRef();
    if (!targetTypeRef.isValid())
        return Result::Continue;

    return pushStructInitializerChildBindingType(sema, childRef, targetTypeRef, spanArgsRef);
}

SWC_END_NAMESPACE();
