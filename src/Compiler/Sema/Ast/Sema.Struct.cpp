#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Literal.Payload.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result completeLiteralRuntimeStorageSymbol(Sema& sema, SymbolVariable& symVar, TypeRef typeRef)
    {
        symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
        symVar.setTypeRef(typeRef);

        if (SymbolFunction* currentFunc = sema.frame().currentFunction())
        {
            const TypeInfo& symType = sema.typeMgr().get(typeRef);
            SWC_RESULT_VERIFY(sema.waitSemaCompleted(&symType, sema.curNodeRef()));
            currentFunc->addLocalVariable(sema.ctx(), &symVar);
        }

        symVar.setTyped(sema.ctx());
        symVar.setSemaCompleted(sema.ctx());
        return Result::Continue;
    }

    SymbolVariable& registerUniqueLiteralRuntimeStorageSymbol(Sema& sema, const AstNode& node)
    {
        TaskContext&        ctx         = sema.ctx();
        const IdentifierRef idRef       = SemaHelpers::getUniqueIdentifier(sema, "__literal_runtime_storage");
        const SymbolFlags   flags       = sema.frame().flagsForCurrentAccess();
        auto*               symVariable = Symbol::make<SymbolVariable>(ctx, &node, node.tokRef(), idRef, flags);
        if (sema.curScope().isLocal() && !sema.curScope().symMap())
        {
            sema.curScope().addSymbol(symVariable);
        }
        else
        {
            SymbolMap* symMap = SemaFrame::currentSymMap(sema);
            SWC_ASSERT(symMap != nullptr);
            symMap->addSymbol(ctx, symVariable, true);
        }

        return *(symVariable);
    }

    Result attachLiteralRuntimeStorageIfNeeded(Sema& sema, const AstNode& node, const SemaNodeView& literalView)
    {
        if (!literalView.type())
            return Result::Continue;
        if (literalView.hasConstant())
            return Result::Continue;
        if (!literalView.type()->isAggregateStruct() && !literalView.type()->isAggregateArray())
            return Result::Continue;
        if (sema.frame().currentFunction() == nullptr)
            return Result::Continue;

        auto& storageSym = registerUniqueLiteralRuntimeStorageSymbol(sema, node);
        storageSym.registerAttributes(sema);
        storageSym.setDeclared(sema.ctx());
        SWC_RESULT_VERIFY(Match::ghosting(sema, storageSym));
        SWC_RESULT_VERIFY(completeLiteralRuntimeStorageSymbol(sema, storageSym, literalView.typeRef()));

        auto* payload = sema.codeGenPayload<LiteralExprCodeGenPayload>(sema.curNodeRef());
        if (!payload)
        {
            payload = sema.compiler().allocate<LiteralExprCodeGenPayload>();
            sema.setCodeGenPayload(sema.curNodeRef(), payload);
        }

        payload->runtimeStorageSym = &storageSym;
        return Result::Continue;
    }
}

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
    const Symbol& sym = *sema.curViewSymbol().sym();
    return Match::ghosting(sema, sym);
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

    // Ensure all `impl` blocks (including interface implementations) have been registered
    // before a struct can be marked as completed.
    if (sema.compiler().pendingImplRegistrations() != 0)
        return sema.waitImplRegistrations(sym.idRef(), sym.codeRef());

    sym.removeIgnoredFields();
    SWC_RESULT_VERIFY(sym.canBeCompleted(sema));
    SWC_RESULT_VERIFY(sym.registerSpecOps(sema));
    SWC_RESULT_VERIFY(sym.computeLayout(sema.ctx()));

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
    SWC_RESULT_VERIFY(sym.canBeCompleted(sema));
    SWC_RESULT_VERIFY(sym.computeLayout(sema.ctx()));
    sym.setSemaCompleted(sema.ctx());
    sema.setType(sema.curNodeRef(), sym.typeRef());
    return Result::Continue;
}

Result AstStructInitializerList::semaPostNode(Sema& sema) const
{
    SmallVector<AstNodeRef> children;
    AstNode::collectChildren(children, sema.ast(), spanArgsRef);

    SWC_RESULT_VERIFY(SemaHelpers::finalizeAggregateStruct(sema, children));
    SemaNodeView initView = sema.curViewNodeTypeConstant();
    SWC_RESULT_VERIFY(attachLiteralRuntimeStorageIfNeeded(sema, *this, initView));

    const SemaNodeView nodeWhatView = sema.viewType(nodeWhatRef);
    SWC_RESULT_VERIFY(Cast::cast(sema, initView, nodeWhatView.typeRef(), CastKind::Initialization));

    return Result::Continue;
}

SWC_END_NAMESPACE();
