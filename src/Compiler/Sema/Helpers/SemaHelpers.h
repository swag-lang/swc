#pragma once
#include "Backend/Runtime.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

namespace SemaHelpers
{
    inline const Runtime::BuildCfg& buildCfg(const Sema& sema)
    {
        return sema.compiler().buildCfg();
    }

    inline const Runtime::BuildCfgBackend& buildCfgBackend(const Sema& sema)
    {
        return buildCfg(sema).backend;
    }

    inline Runtime::BuildCfgBackendKind buildCfgBackendKind(const Sema& sema)
    {
        return buildCfg(sema).backendKind;
    }

    inline bool isNativeBuild(const Sema& sema)
    {
        return buildCfgBackendKind(sema) != Runtime::BuildCfgBackendKind::None;
    }

    inline bool isNativeExecutableBuild(const Sema& sema)
    {
        return buildCfgBackendKind(sema) == Runtime::BuildCfgBackendKind::Executable;
    }

    inline SymbolFunction* currentFunction(const Sema& sema)
    {
        return sema.frame().currentFunction();
    }

    inline bool isCurrentFunction(const Sema& sema)
    {
        return currentFunction(sema) != nullptr;
    }

    inline bool isGlobalScope(const Sema& sema)
    {
        return !isCurrentFunction(sema);
    }

    inline void addCurrentFunctionCallDependency(const Sema& sema, SymbolFunction* calleeSym)
    {
        if (SymbolFunction* currentFn = currentFunction(sema); currentFn && calleeSym)
            currentFn->addCallDependency(calleeSym);
    }

    inline Result addCurrentFunctionLocalVariable(Sema& sema, SymbolVariable& symVar, TypeRef typeRef)
    {
        if (!isCurrentFunction(sema) || !typeRef.isValid())
            return Result::Continue;

        const TypeInfo& symType = sema.typeMgr().get(typeRef);
        SWC_RESULT(sema.waitSemaCompleted(&symType, sema.curNodeRef()));
        currentFunction(sema)->addLocalVariable(sema.ctx(), &symVar);
        return Result::Continue;
    }

    inline Result addCurrentFunctionLocalVariable(Sema& sema, SymbolVariable& symVar)
    {
        return addCurrentFunctionLocalVariable(sema, symVar, symVar.typeRef());
    }

    inline bool isOptimizeEnabled(const Sema& sema)
    {
        return buildCfgBackend(sema).optimize;
    }

    inline bool needsPersistentCompilerRunReturn(const Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        const auto needsPersistent = [&](auto&& self, TypeRef rawTypeRef) -> bool {
            if (!rawTypeRef.isValid())
                return false;

            const TypeInfo& typeInfo = sema.typeMgr().get(rawTypeRef);
            if (typeInfo.isAlias())
            {
                return self(self, typeInfo.unwrap(sema.ctx(), rawTypeRef, TypeExpandE::Alias));
            }

            if (typeInfo.isEnum())
            {
                return self(self, typeInfo.unwrap(sema.ctx(), rawTypeRef, TypeExpandE::Enum));
            }

            if (typeInfo.isString() || typeInfo.isSlice() || typeInfo.isAny() || typeInfo.isInterface() || typeInfo.isCString())
                return true;

            if (typeInfo.isArray())
            {
                return self(self, typeInfo.payloadArrayElemTypeRef());
            }

            if (typeInfo.isStruct())
            {
                for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
                {
                    if (field && self(self, field->typeRef()))
                        return true;
                }
            }

            return false;
        };

        return needsPersistent(needsPersistent, typeRef);
    }

    inline bool isConstExprRequired(const Sema& sema)
    {
        return sema.frame().hasContextFlag(SemaFrameContextFlagsE::RequireConstExpr);
    }

    inline bool isRunExprContext(const Sema& sema)
    {
        return sema.frame().hasContextFlag(SemaFrameContextFlagsE::RunExpr);
    }

    const SymbolFunction* currentLocationFunction(const Sema& sema);
    AstNodeRef            defaultArgumentExprRef(const SymbolVariable& param);
    bool                  isDirectCallerLocationDefault(const Sema& sema, const SymbolVariable& param);
    AstNodeRef            unwrapCallCalleeRef(Sema& sema, AstNodeRef nodeRef);
    void                  pushConstExprRequirement(Sema& sema, AstNodeRef childRef);
    IdentifierRef         getUniqueIdentifier(Sema& sema, const std::string_view& name);
    uint32_t              uniqSlotIndex(TokenId tokenId);
    AstNodeRef            uniqSyntaxScopeNodeRef(Sema& sema);
    SemaInlinePayload*    mixinInlinePayloadForUniq(Sema& sema);
    IdentifierRef         ensureCurrentScopeUniqIdentifier(Sema& sema, TokenId tokenId);
    IdentifierRef         resolveUniqIdentifier(Sema& sema, TokenId tokenId);
    Result                checkBinaryOperandTypes(Sema& sema, AstNodeRef nodeRef, TokenId op, AstNodeRef leftRef, AstNodeRef rightRef, const SemaNodeView& leftView, const SemaNodeView& rightView);
    Result                castBinaryRightToLeft(Sema& sema, TokenId op, AstNodeRef nodeRef, const SemaNodeView& leftView, SemaNodeView& rightView, CastKind castKind);
    Result                intrinsicCountOf(Sema& sema, AstNodeRef targetRef, AstNodeRef exprRef);
    Result                finalizeAggregateStruct(Sema& sema, const SmallVector<AstNodeRef>& children);
    void                  handleSymbolRegistration(Sema& sema, SymbolMap* symbolMap, Symbol* sym);

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
