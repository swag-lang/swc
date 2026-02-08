#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Support/Report/DiagnosticDef.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void markExplicitUndefined(const std::span<Symbol*>& symbols)
    {
        for (const auto& s : symbols)
        {
            if (const auto symVar = s->safeCast<SymbolVariable>())
                symVar->addExtraFlag(SymbolVariableFlagsE::ExplicitUndefined);
        }
    }

    void completeConst(Sema& sema, const std::span<Symbol*>& symbols, ConstantRef cstRef, TypeRef typeRef)
    {
        for (auto* s : symbols)
        {
            auto& symCst = s->cast<SymbolConstant>();
            symCst.setCstRef(cstRef);
            if (symCst.typeRef().isInvalid())
                symCst.setTypeRef(typeRef);
            symCst.setTyped(sema.ctx());
            symCst.setCompleted(sema.ctx());
        }
    }

    void completeVar(Sema& sema, const std::span<Symbol*>& symbols, TypeRef typeRef)
    {
        for (auto* s : symbols)
        {
            auto& symVar = s->cast<SymbolVariable>();
            if (symVar.typeRef().isInvalid())
                symVar.setTypeRef(typeRef);
            symVar.setTyped(sema.ctx());
            symVar.setCompleted(sema.ctx());
        }
    }

    bool deduceArrayDimsFromType(Sema& sema, TypeRef typeRef, SmallVector4<uint64_t>& outDims)
    {
        const TypeInfo& type = sema.typeMgr().get(typeRef);
        if (type.isArray())
        {
            const auto& dims = type.payloadArrayDims();
            outDims.insert(outDims.end(), dims.begin(), dims.end());

            const TypeRef   elemTypeRef = type.payloadArrayElemTypeRef();
            const TypeInfo& elemType    = sema.typeMgr().get(elemTypeRef);
            if (elemType.isArray() || elemType.isAggregateArray())
                return deduceArrayDimsFromType(sema, elemTypeRef, outDims);
            return true;
        }

        if (type.isAggregateArray())
        {
            const auto& elemTypes = type.payloadAggregate().types;
            if (elemTypes.empty())
                return false;

            outDims.push_back(elemTypes.size());

            SmallVector4<uint64_t> innerDims;
            bool                   hasInner = false;
            for (const auto elemTypeRef : elemTypes)
            {
                const TypeInfo& elemType = sema.typeMgr().get(elemTypeRef);
                if (!elemType.isArray() && !elemType.isAggregateArray())
                {
                    if (hasInner)
                        return false;
                    continue;
                }

                SmallVector4<uint64_t> nextInner;
                if (!deduceArrayDimsFromType(sema, elemTypeRef, nextInner))
                    return false;

                if (!hasInner)
                {
                    innerDims = std::move(nextInner);
                    hasInner  = true;
                }
                else if (nextInner.size() != innerDims.size() || !std::equal(nextInner.begin(), nextInner.end(), innerDims.begin()))
                {
                    return false;
                }
            }

            if (hasInner)
                outDims.insert(outDims.end(), innerDims.begin(), innerDims.end());
            return true;
        }

        return false;
    }

    struct ExplicitArrayNode
    {
        SmallVector4<uint64_t> dims;
        TypeInfoFlags          flags;
    };

    bool collectExplicitArrayNodes(Sema& sema, TypeRef typeRef, std::vector<ExplicitArrayNode>& outNodes, TypeRef& outBaseTypeRef)
    {
        while (typeRef.isValid())
        {
            const TypeInfo& type = sema.typeMgr().get(typeRef);
            if (!type.isArray())
                break;
            SmallVector4<uint64_t> dims;
            const auto&            payloadDims = type.payloadArrayDims();
            dims.insert(dims.end(), payloadDims.begin(), payloadDims.end());
            outNodes.push_back({std::move(dims), type.flags()});
            typeRef = type.payloadArrayElemTypeRef();
        }

        outBaseTypeRef = typeRef;
        return !outNodes.empty();
    }

    TypeRef deduceArrayTypeFromInit(Sema& sema, TypeRef explicitTypeRef, const SemaNodeView& initView)
    {
        if (explicitTypeRef.isInvalid() || initView.typeRef.isInvalid())
            return TypeRef::invalid();

        std::vector<ExplicitArrayNode> nodes;
        TypeRef                        baseTypeRef = TypeRef::invalid();
        if (!collectExplicitArrayNodes(sema, explicitTypeRef, nodes, baseTypeRef))
            return TypeRef::invalid();

        bool   hasUnknown       = false;
        size_t explicitDimCount = 0;
        for (const auto& node : nodes)
        {
            if (node.dims.empty())
            {
                hasUnknown = true;
                explicitDimCount += 1;
            }
            else
            {
                explicitDimCount += node.dims.size();
            }
        }

        if (!hasUnknown)
            return TypeRef::invalid();

        SmallVector4<uint64_t> initDims;
        if (!deduceArrayDimsFromType(sema, initView.typeRef, initDims))
            return TypeRef::invalid();

        if (nodes.size() == 1 && nodes[0].dims.empty())
        {
            if (initDims.empty())
                return TypeRef::invalid();
            if (initDims.size() > 1)
            {
                TypeRef elemTypeRef = baseTypeRef;
                for (uint64_t& initDim : std::ranges::reverse_view(initDims))
                {
                    SmallVector4<uint64_t> oneDim;
                    oneDim.push_back(initDim);
                    const TypeInfo arrayType = TypeInfo::makeArray(oneDim.span(), elemTypeRef, nodes[0].flags);
                    elemTypeRef              = sema.typeMgr().addType(arrayType);
                }

                return elemTypeRef;
            }

            nodes[0].dims = std::move(initDims);
        }
        else
        {
            if (initDims.size() != explicitDimCount)
                return TypeRef::invalid();

            size_t dimIndex = 0;
            for (auto& node : nodes)
            {
                if (node.dims.empty())
                {
                    node.dims.push_back(initDims[dimIndex++]);
                    continue;
                }

                for (auto dim : node.dims)
                {
                    if (initDims[dimIndex++] != dim)
                        return TypeRef::invalid();
                }
            }
        }

        TypeRef elemTypeRef = baseTypeRef;
        for (auto& node : std::ranges::reverse_view(nodes))
        {
            const TypeInfo arrayType = TypeInfo::makeArray(node.dims.span(), elemTypeRef, node.flags);
            elemTypeRef              = sema.typeMgr().addType(arrayType);
        }

        return elemTypeRef;
    }

    void storeFieldDefaultConstants(const std::span<Symbol*>& symbols, ConstantRef cstRef)
    {
        if (cstRef.isInvalid())
            return;

        for (auto* s : symbols)
        {
            auto* symVar = s->safeCast<SymbolVariable>();
            if (!symVar)
                continue;
            if (!symVar->ownerSymMap() || !symVar->ownerSymMap()->safeCast<SymbolStruct>())
                continue;
            symVar->setDefaultValueRef(cstRef);
        }
    }

    Result semaPostVarDeclCommon(Sema&                       sema,
                                 const AstNode&              owner,
                                 TokenRef                    tokDiag,
                                 AstNodeRef                  nodeInitRef,
                                 AstNodeRef                  nodeTypeRef,
                                 EnumFlags<AstVarDeclFlagsE> flags,
                                 const std::span<Symbol*>&   symbols)
    {
        SemaNodeView nodeInitView(sema, nodeInitRef);
        if (nodeInitRef.isValid())
            RESULT_VERIFY(SemaCheck::isValueOrTypeInfo(sema, nodeInitView));

        const SemaNodeView nodeTypeView(sema, nodeTypeRef);
        TypeRef            explicitTypeRef = nodeTypeView.typeRef;

        if (nodeInitView.typeRef.isValid())
        {
            const TypeRef deducedTypeRef = deduceArrayTypeFromInit(sema, explicitTypeRef, nodeInitView);
            if (deducedTypeRef.isValid())
            {
                explicitTypeRef = deducedTypeRef;
                if (nodeTypeRef.isValid())
                    sema.setType(nodeTypeRef, explicitTypeRef);
            }
        }

        const TypeInfo* explicitType = explicitTypeRef.isValid() ? &sema.typeMgr().get(explicitTypeRef) : nullptr;

        const bool isConst     = flags.has(AstVarDeclFlagsE::Const);
        const bool isLet       = flags.has(AstVarDeclFlagsE::Let);
        const bool isParameter = flags.has(AstVarDeclFlagsE::Parameter);
        const bool isUsing     = flags.has(AstVarDeclFlagsE::Using);

        // Initialized to 'undefined'
        if (nodeInitRef.isValid() && nodeInitView.cstRef == sema.cstMgr().cstUndefined())
        {
            if (isConst)
                return SemaError::raise(sema, DiagnosticId::sema_err_const_missing_init, SourceCodeRef{owner.srcViewRef(), tokDiag});
            if (isLet)
                return SemaError::raise(sema, DiagnosticId::sema_err_let_missing_init, SourceCodeRef{owner.srcViewRef(), tokDiag});
            if (nodeTypeRef.isInvalid())
                return SemaError::raise(sema, DiagnosticId::sema_err_not_type, SourceCodeRef{owner.srcViewRef(), tokDiag});

            if (!isParameter && explicitTypeRef.isValid() && explicitType && explicitType->isReference())
                return SemaError::raise(sema, DiagnosticId::sema_err_ref_missing_init, SourceCodeRef{owner.srcViewRef(), tokDiag});

            markExplicitUndefined(symbols);
        }

        // Implicit cast from initializer to the specified type
        if (nodeInitView.typeRef.isValid() && explicitTypeRef.isValid())
        {
            RESULT_VERIFY(Cast::cast(sema, nodeInitView, explicitTypeRef, CastKind::Initialization));
        }
        else if (nodeInitView.cstRef.isValid())
        {
            ConstantRef newCstRef;
            RESULT_VERIFY(Cast::concretizeConstant(sema, newCstRef, nodeInitView.nodeRef, nodeInitView.cstRef, TypeInfo::Sign::Unknown));
            nodeInitView.setCstRef(sema, newCstRef);

            if (nodeInitView.type->isInt())
            {
                const TypeRef newTypeRef = sema.typeMgr().promote(nodeInitView.typeRef, nodeInitView.typeRef, true);
                RESULT_VERIFY(Cast::cast(sema, nodeInitView, newTypeRef, CastKind::Implicit));
            }
        }

        if (nodeInitRef.isValid())
            storeFieldDefaultConstants(symbols, nodeInitView.cstRef);

        if (!sema.curScope().isLocal() && !sema.curScope().isParameters() && !isConst && nodeInitRef.isValid())
            RESULT_VERIFY(SemaCheck::isConstant(sema, nodeInitView.nodeRef));

        const TypeRef finalTypeRef = explicitTypeRef.isValid() ? explicitTypeRef : nodeInitView.typeRef;
        const bool    isRefType    = finalTypeRef.isValid() && sema.typeMgr().get(finalTypeRef).isReference();
        if (isConst && isRefType)
            return SemaError::raise(sema, DiagnosticId::sema_err_const_ref_type, SourceCodeRef{owner.srcViewRef(), tokDiag});

        if (isUsing && finalTypeRef.isValid())
        {
            const TypeInfo& ultimateType = sema.typeMgr().get(finalTypeRef);
            if (!ultimateType.isStruct())
            {
                if (!ultimateType.isAnyPointer() || !sema.typeMgr().get(ultimateType.payloadTypeRef()).isStruct())
                {
                    auto diag = SemaError::report(sema, DiagnosticId::sema_err_using_member_type, SourceCodeRef{owner.srcViewRef(), tokDiag});
                    diag.addArgument(Diagnostic::ARG_TYPE, finalTypeRef);
                    diag.report(sema.ctx());
                    return Result::Error;
                }
            }
        }

        ConstantRef implicitStructCstRef = ConstantRef::invalid();
        if (nodeInitRef.isInvalid() && explicitTypeRef.isValid() && explicitType && explicitType->isStruct() && (isConst || isLet))
        {
            RESULT_VERIFY(sema.waitCompleted(explicitType, nodeTypeRef));
            implicitStructCstRef = explicitType->payloadSymStruct().computeDefaultValue(sema, explicitTypeRef);
        }
        const bool hasImplicitStructInit = implicitStructCstRef.isValid();

        // Constant
        if (isConst)
        {
            if (nodeInitRef.isInvalid())
            {
                if (!hasImplicitStructInit)
                    return SemaError::raise(sema, DiagnosticId::sema_err_const_missing_init, SourceCodeRef{owner.srcViewRef(), tokDiag});
                completeConst(sema, symbols, implicitStructCstRef, explicitTypeRef);
                return Result::Continue;
            }
            if (nodeInitView.cstRef.isInvalid())
                return SemaError::raiseExprNotConst(sema, nodeInitView.nodeRef);

            completeConst(sema, symbols, nodeInitView.cstRef, nodeInitView.typeRef);
            return Result::Continue;
        }

        // Variable
        if (isLet && nodeInitRef.isInvalid() && !hasImplicitStructInit)
            return SemaError::raise(sema, DiagnosticId::sema_err_let_missing_init, SourceCodeRef{owner.srcViewRef(), tokDiag});
        if (!isLet && !isParameter && isRefType && nodeInitRef.isInvalid())
            return SemaError::raise(sema, DiagnosticId::sema_err_ref_missing_init, SourceCodeRef{owner.srcViewRef(), tokDiag});

        completeVar(sema, symbols, explicitTypeRef.isValid() ? explicitTypeRef : nodeInitView.typeRef);

        if (nodeInitRef.isValid() || hasImplicitStructInit)
        {
            for (auto* s : symbols)
            {
                if (const auto symVar = s->safeCast<SymbolVariable>())
                    symVar->addExtraFlag(SymbolVariableFlagsE::Initialized);
            }
        }

        return Result::Continue;
    }
}

Result AstSingleVarDecl::semaPreDecl(Sema& sema) const
{
    if (hasFlag(AstVarDeclFlagsE::Const))
        SemaHelpers::registerSymbol<SymbolConstant>(sema, *this, tokNameRef);
    else
    {
        SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokNameRef);
        if (hasFlag(AstVarDeclFlagsE::Let))
        {
            SymbolVariable& symVar = sema.symbolOf(sema.curNodeRef()).cast<SymbolVariable>();
            symVar.addExtraFlag(SymbolVariableFlagsE::Let);
        }
    }

    return Result::SkipChildren;
}

Result AstSingleVarDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);
    const Symbol& sym = sema.symbolOf(sema.curNodeRef());
    return Match::ghosting(sema, sym);
}

Result AstSingleVarDecl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeTypeRef && nodeInitRef.isValid())
    {
        const SemaNodeView nodeTypeView(sema, nodeTypeRef);
        auto               frame = sema.frame();
        frame.pushBindingType(nodeTypeView.typeRef);
        sema.pushFramePopOnPostChild(frame, nodeInitRef);
    }

    return Result::Continue;
}

Result AstSingleVarDecl::semaPostNode(Sema& sema) const
{
    Symbol& sym   = sema.symbolOf(sema.curNodeRef());
    Symbol* one[] = {&sym};
    return semaPostVarDeclCommon(sema, *this, tokNameRef, nodeInitRef, nodeTypeRef, flags(), std::span<Symbol*>{one});
}

Result AstMultiVarDecl::semaPreDecl(Sema& sema) const
{
    SmallVector<TokenRef> tokNames;
    sema.ast().appendTokens(tokNames, spanNamesRef);

    SmallVector<const Symbol*> symbols;
    for (const auto& tokNameRef : tokNames)
    {
        if (hasFlag(AstVarDeclFlagsE::Const))
        {
            Symbol& sym = SemaHelpers::registerSymbol<SymbolConstant>(sema, *this, tokNameRef);
            symbols.push_back(&sym);
        }
        else
        {
            Symbol& sym = SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokNameRef);
            symbols.push_back(&sym);
            if (hasFlag(AstVarDeclFlagsE::Let))
            {
                SymbolVariable& symVar = sema.symbolOf(sema.curNodeRef()).cast<SymbolVariable>();
                symVar.addExtraFlag(SymbolVariableFlagsE::Let);
            }
        }
    }

    sema.setSymbolList(sema.curNodeRef(), symbols.span());
    return Result::SkipChildren;
}

Result AstMultiVarDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
    {
        if (!sema.hasSymbolList(sema.curNodeRef()))
            semaPreDecl(sema);
        const auto symbols = sema.getSymbolList(sema.curNodeRef());
        for (const auto sym : symbols)
        {
            sym->registerAttributes(sema);
            sym->setDeclared(sema.ctx());
        }
    }

    const auto symbols = sema.getSymbolList(sema.curNodeRef());
    for (const auto sym : symbols)
    {
        RESULT_VERIFY(Match::ghosting(sema, *sym));
    }

    return Result::Continue;
}

Result AstMultiVarDecl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeTypeRef && nodeInitRef.isValid())
    {
        const SemaNodeView nodeTypeView(sema, nodeTypeRef);
        auto               frame = sema.frame();
        frame.pushBindingType(nodeTypeView.typeRef);
        sema.pushFramePopOnPostChild(frame, nodeInitRef);
    }

    return Result::Continue;
}

Result AstMultiVarDecl::semaPostNode(Sema& sema) const
{
    const auto symbols = sema.getSymbolList(sema.curNodeRef());
    return semaPostVarDeclCommon(sema, *this, tokRef(), nodeInitRef, nodeTypeRef, flags(), symbols);
}

Result AstVarDeclDestructuring::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeInitView(sema, nodeInitRef);
    if (!nodeInitView.type->isStruct())
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_decomposition_not_struct, nodeInitView.nodeRef);
        diag.addArgument(Diagnostic::ARG_TYPE, nodeInitView.typeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    const SymbolStruct& symStruct = nodeInitView.type->payloadSymStruct();
    const auto&         fields    = symStruct.fields();

    SmallVector<TokenRef> tokNames;
    sema.ast().appendTokens(tokNames, spanNamesRef);

    if (tokNames.size() > fields.size())
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_decomposition_too_many_names, nodeRef(sema.ast()));
        diag.addArgument(Diagnostic::ARG_COUNT, static_cast<uint32_t>(fields.size()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    if (tokNames.size() < fields.size())
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_decomposition_not_enough_names, nodeRef(sema.ast()));
        diag.addArgument(Diagnostic::ARG_COUNT, static_cast<uint32_t>(fields.size()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    SmallVector<Symbol*> symbols;
    for (size_t i = 0; i < tokNames.size(); i++)
    {
        const auto& tokNameRef = tokNames[i];
        if (tokNameRef.isInvalid())
            continue;

        SymbolVariable& sym = SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokNameRef);
        if (hasFlag(AstVarDeclFlagsE::Let))
            sym.addExtraFlag(SymbolVariableFlagsE::Let);
        sym.setDeclared(sema.ctx());

        symbols.push_back(&sym);

        const SymbolVariable* field = fields[i];
        sym.setTypeRef(field->typeRef());
        sym.setTyped(sema.ctx());
        sym.setCompleted(sema.ctx());

        RESULT_VERIFY(Match::ghosting(sema, sym));
    }

    sema.setSymbolList(sema.curNodeRef(), symbols.span());
    return semaPostVarDeclCommon(sema, *this, tokRef(), nodeInitRef, AstNodeRef::invalid(), flags(), symbols.span());
}

SWC_END_NAMESPACE();
