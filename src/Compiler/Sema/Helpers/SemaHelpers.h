#pragma once
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

namespace SemaHelpers
{
    inline IdentifierRef getUniqueIdentifier(Sema& sema, const std::string_view& name)
    {
        const uint32_t id = sema.compiler().atomicId().fetch_add(1);
        return sema.idMgr().addIdentifierOwned(std::format("{}_{}", name, id));
    }

    inline uint32_t uniqSlotIndex(const TokenId tokenId)
    {
        SWC_ASSERT(Token::isCompilerUniq(tokenId));
        return static_cast<uint32_t>(tokenId) - static_cast<uint32_t>(TokenId::CompilerUniq0);
    }

    inline AstNodeRef uniqSyntaxScopeNodeRef(Sema& sema)
    {
        if (sema.curNode().is(AstNodeId::FunctionBody) || sema.curNode().is(AstNodeId::EmbeddedBlock))
            return sema.curNodeRef();

        for (size_t parentIndex = 0;; parentIndex++)
        {
            const AstNodeRef parentRef = sema.visit().parentNodeRef(parentIndex);
            if (parentRef.isInvalid())
                return AstNodeRef::invalid();

            const AstNodeId parentId = sema.node(parentRef).id();
            if (parentId == AstNodeId::FunctionBody || parentId == AstNodeId::EmbeddedBlock)
                return parentRef;
        }
    }

    inline SemaInlinePayload* mixinInlinePayloadForUniq(Sema& sema)
    {
        auto* inlinePayload = const_cast<SemaInlinePayload*>(sema.frame().currentInlinePayload());
        if (!inlinePayload || !inlinePayload->sourceFunction)
            return nullptr;
        if (!inlinePayload->sourceFunction->attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
            return nullptr;
        if (uniqSyntaxScopeNodeRef(sema) != inlinePayload->inlineRootRef)
            return nullptr;
        return inlinePayload;
    }

    inline IdentifierRef ensureCurrentScopeUniqIdentifier(Sema& sema, const TokenId tokenId)
    {
        SWC_ASSERT(Token::isCompilerUniq(tokenId));
        const uint32_t slot = uniqSlotIndex(tokenId);
        if (auto* inlinePayload = mixinInlinePayloadForUniq(sema))
        {
            const IdentifierRef done = inlinePayload->uniqIdentifiers[slot];
            if (done.isValid())
                return done;

            const IdentifierRef idRef            = getUniqueIdentifier(sema, std::format("__uniq{}", slot));
            inlinePayload->uniqIdentifiers[slot] = idRef;
            return idRef;
        }

        auto&               scope = sema.curScope();
        const IdentifierRef done  = scope.uniqIdentifier(slot);
        if (done.isValid())
            return done;

        const IdentifierRef idRef = getUniqueIdentifier(sema, std::format("__uniq{}", slot));
        scope.setUniqIdentifier(slot, idRef);
        return idRef;
    }

    inline IdentifierRef resolveUniqIdentifier(Sema& sema, const TokenId tokenId)
    {
        SWC_ASSERT(Token::isCompilerUniq(tokenId));
        const uint32_t slot = uniqSlotIndex(tokenId);
        for (const SemaScope* scope = &sema.curScope(); scope; scope = scope->parent())
        {
            const IdentifierRef idRef = scope->uniqIdentifier(slot);
            if (idRef.isValid())
                return idRef;
        }

        if (auto* inlinePayload = mixinInlinePayloadForUniq(sema))
        {
            const IdentifierRef idRef = inlinePayload->uniqIdentifiers[slot];
            if (idRef.isValid())
                return idRef;
        }

        return ensureCurrentScopeUniqIdentifier(sema, tokenId);
    }

    Result checkBinaryOperandTypes(Sema& sema, AstNodeRef nodeRef, TokenId op, AstNodeRef leftRef, AstNodeRef rightRef, const SemaNodeView& leftView, const SemaNodeView& rightView);
    Result castBinaryRightToLeft(Sema& sema, TokenId op, AstNodeRef nodeRef, const SemaNodeView& leftView, SemaNodeView& rightView, CastKind castKind);
    Result intrinsicCountOf(Sema& sema, AstNodeRef targetRef, AstNodeRef exprRef);
    Result finalizeAggregateStruct(Sema& sema, const SmallVector<AstNodeRef>& children);

    void handleSymbolRegistration(Sema& sema, SymbolMap* symbolMap, Symbol* sym);

    template<typename T>
    T& registerSymbol(Sema& sema, const AstNode& node, TokenRef tokNameRef)
    {
        TaskContext& ctx = sema.ctx();

        const Token&        tok   = sema.srcView(node.srcViewRef()).token(tokNameRef);
        const IdentifierRef idRef = Token::isCompilerUniq(tok.id) ? ensureCurrentScopeUniqIdentifier(sema, tok.id) : sema.idMgr().addIdentifier(ctx, {node.srcViewRef(), tokNameRef});
        const SymbolFlags   flags = sema.frame().flagsForCurrentAccess();

        T*         sym       = Symbol::make<T>(ctx, &node, tokNameRef, idRef, flags);
        SymbolMap* symbolMap = SemaFrame::currentSymMap(sema);

        if (sema.curScope().isLocal())
            sema.curScope().addSymbol(sym);
        else
            symbolMap->addSymbol(ctx, sym, true);

        handleSymbolRegistration(sema, symbolMap, sym);
        sym->registerCompilerIf(sema);
        sema.setSymbol(sema.curNodeRef(), sym);

        return *(sym);
    }

    template<typename T>
    T& registerUniqueSymbol(Sema& sema, const AstNode& node, const std::string_view& name)
    {
        TaskContext&        ctx         = sema.ctx();
        const Utf8          privateName = Utf8("__") + Utf8(name);
        const IdentifierRef idRef       = getUniqueIdentifier(sema, privateName);
        const SymbolFlags   flags       = sema.frame().flagsForCurrentAccess();

        T* sym = Symbol::make<T>(ctx, &node, node.tokRef(), idRef, flags);

        if (sema.curScope().isLocal() && !sema.curScope().symMap())
        {
            sema.curScope().addSymbol(sym);
        }
        else
        {
            SymbolMap* symMap = SemaFrame::currentSymMap(sema);
            symMap->addSymbol(ctx, sym, true);
        }

        sema.setSymbol(sema.curNodeRef(), sym);

        return *(sym);
    }

    template<typename T>
    void declareSymbol(Sema& sema, const T& node)
    {
        const AstNodeRef curNodeRef = sema.curNodeRef();
        if (!sema.viewSymbol(curNodeRef).hasSymbol())
            node.semaPreDecl(sema);
        SemaNodeView view = sema.viewSymbol(curNodeRef);
        SWC_ASSERT(view.hasSymbol());
        Symbol& sym = *view.sym();
        sym.registerAttributes(sema);
        sym.setDeclared(sema.ctx());
    }
}

SWC_END_NAMESPACE();
