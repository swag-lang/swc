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
            if (SymbolVariable* symVar = s->safeCast<SymbolVariable>())
                symVar->addExtraFlag(SymbolVariableFlagsE::ExplicitUndefined);
        }
    }

    void completeConst(Sema& sema, const std::span<Symbol*>& symbols, ConstantRef cstRef, TypeRef typeRef)
    {
        for (auto* s : symbols)
        {
            SymbolConstant& symCst = s->cast<SymbolConstant>();
            symCst.setCstRef(cstRef);
            if (symCst.typeRef().isInvalid())
                symCst.setTypeRef(typeRef);
            symCst.setTyped(sema.ctx());
            symCst.setSemaCompleted(sema.ctx());
        }
    }

    void completeVar(Sema& sema, const std::span<Symbol*>& symbols, TypeRef typeRef)
    {
        for (auto* s : symbols)
        {
            SymbolVariable& symVar = s->cast<SymbolVariable>();
            if (symVar.typeRef().isInvalid())
                symVar.setTypeRef(typeRef);
            symVar.setTyped(sema.ctx());
            symVar.setSemaCompleted(sema.ctx());
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

    struct SemaPostVarDeclArgs
    {
        const AstNode*              owner;
        TokenRef                    tokDiag;
        AstNodeRef                  nodeInitRef;
        AstNodeRef                  nodeTypeRef;
        EnumFlags<AstVarDeclFlagsE> flags;
    };

    Result semaPostVarDeclCommon(Sema& sema, const SemaPostVarDeclArgs& context, const std::span<Symbol*>& symbols)
    {
        SemaNodeView nodeInitView = sema.nodeView(context.nodeInitRef);
        if (context.nodeInitRef.isValid())
            RESULT_VERIFY(SemaCheck::isValueOrTypeInfo(sema, nodeInitView));

        const SemaNodeView nodeTypeView    = sema.nodeView(context.nodeTypeRef);
        TypeRef            explicitTypeRef = nodeTypeView.typeRef;

        if (nodeInitView.typeRef.isValid())
        {
            const TypeRef deducedTypeRef = deduceArrayTypeFromInit(sema, explicitTypeRef, nodeInitView);
            if (deducedTypeRef.isValid())
            {
                explicitTypeRef = deducedTypeRef;
                if (context.nodeTypeRef.isValid())
                    sema.setType(context.nodeTypeRef, explicitTypeRef);
            }
        }

        const TypeInfo* explicitType = explicitTypeRef.isValid() ? &sema.typeMgr().get(explicitTypeRef) : nullptr;

        const bool isConst     = context.flags.has(AstVarDeclFlagsE::Const);
        const bool isLet       = context.flags.has(AstVarDeclFlagsE::Let);
        const bool isParameter = context.flags.has(AstVarDeclFlagsE::Parameter);
        const bool isUsing     = context.flags.has(AstVarDeclFlagsE::Using);

        // Initialized to 'undefined'
        if (context.nodeInitRef.isValid() && nodeInitView.cstRef == sema.cstMgr().cstUndefined())
        {
            if (isConst)
                return SemaError::raise(sema, DiagnosticId::sema_err_const_missing_init, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag});
            if (isLet)
                return SemaError::raise(sema, DiagnosticId::sema_err_let_missing_init, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag});
            if (context.nodeTypeRef.isInvalid())
                return SemaError::raise(sema, DiagnosticId::sema_err_not_type, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag});

            if (!isParameter && explicitTypeRef.isValid() && explicitType && explicitType->isReference())
                return SemaError::raise(sema, DiagnosticId::sema_err_ref_missing_init, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag});

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
                const TypeRef newTypeRef = sema.typeMgr().promote(nodeInitView.typeRef, nodeInitView.typeRef, false);
                RESULT_VERIFY(Cast::cast(sema, nodeInitView, newTypeRef, CastKind::Implicit));
            }
        }

        if (context.nodeInitRef.isValid())
            storeFieldDefaultConstants(symbols, nodeInitView.cstRef);

        if (!sema.curScope().isLocal() && !sema.curScope().isParameters() && !isConst && context.nodeInitRef.isValid())
            RESULT_VERIFY(SemaCheck::isConstant(sema, nodeInitView.nodeRef));

        const TypeRef finalTypeRef = explicitTypeRef.isValid() ? explicitTypeRef : nodeInitView.typeRef;
        const bool    isRefType    = finalTypeRef.isValid() && sema.typeMgr().get(finalTypeRef).isReference();
        if (isConst && isRefType)
            return SemaError::raise(sema, DiagnosticId::sema_err_const_ref_type, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag});

        if (isUsing && finalTypeRef.isValid())
        {
            const TypeInfo& ultimateType = sema.typeMgr().get(finalTypeRef);
            if (!ultimateType.isStruct())
            {
                if (!ultimateType.isAnyPointer() || !sema.typeMgr().get(ultimateType.payloadTypeRef()).isStruct())
                {
                    Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_using_member_type, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag});
                    diag.addArgument(Diagnostic::ARG_TYPE, finalTypeRef);
                    diag.report(sema.ctx());
                    return Result::Error;
                }
            }
        }

        ConstantRef implicitStructCstRef = ConstantRef::invalid();
        if (context.nodeInitRef.isInvalid() && explicitTypeRef.isValid() && explicitType && explicitType->isStruct() && (isConst || isLet))
        {
            RESULT_VERIFY(sema.waitSemaCompleted(explicitType, context.nodeTypeRef));
            implicitStructCstRef = explicitType->payloadSymStruct().computeDefaultValue(sema, explicitTypeRef);
        }
        const bool hasImplicitStructInit = implicitStructCstRef.isValid();

        // Constant
        if (isConst)
        {
            if (context.nodeInitRef.isInvalid())
            {
                if (!hasImplicitStructInit)
                    return SemaError::raise(sema, DiagnosticId::sema_err_const_missing_init, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag});
                completeConst(sema, symbols, implicitStructCstRef, explicitTypeRef);
                return Result::Continue;
            }
            if (nodeInitView.cstRef.isInvalid())
                return SemaError::raiseExprNotConst(sema, nodeInitView.nodeRef);

            completeConst(sema, symbols, nodeInitView.cstRef, nodeInitView.typeRef);
            return Result::Continue;
        }

        // Variable
        if (isLet && context.nodeInitRef.isInvalid() && !hasImplicitStructInit)
            return SemaError::raise(sema, DiagnosticId::sema_err_let_missing_init, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag});
        if (!isLet && !isParameter && isRefType && context.nodeInitRef.isInvalid())
            return SemaError::raise(sema, DiagnosticId::sema_err_ref_missing_init, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag});

        completeVar(sema, symbols, explicitTypeRef.isValid() ? explicitTypeRef : nodeInitView.typeRef);

        if (context.nodeInitRef.isValid() || hasImplicitStructInit)
        {
            for (auto* s : symbols)
            {
                if (SymbolVariable* symVar = s->safeCast<SymbolVariable>())
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
        const SemaNodeView nodeTypeView = sema.nodeView(nodeTypeRef);
        SemaFrame          frame        = sema.frame();
        frame.pushBindingType(nodeTypeView.typeRef);
        sema.pushFramePopOnPostChild(frame, nodeInitRef);
    }

    return Result::Continue;
}

Result AstSingleVarDecl::semaPostNode(Sema& sema) const
{
    Symbol&                   sym     = sema.symbolOf(sema.curNodeRef());
    Symbol*                   one[]   = {&sym};
    const SemaPostVarDeclArgs context = {this, tokNameRef, nodeInitRef, nodeTypeRef, flags()};
    return semaPostVarDeclCommon(sema, context, std::span<Symbol*>{one});
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
        const std::span<Symbol*> symbols = sema.getSymbolList(sema.curNodeRef());
        for (Symbol* sym : symbols)
        {
            sym->registerAttributes(sema);
            sym->setDeclared(sema.ctx());
        }
    }

    const std::span<Symbol*> symbols = sema.getSymbolList(sema.curNodeRef());
    for (const Symbol* sym : symbols)
    {
        RESULT_VERIFY(Match::ghosting(sema, *sym));
    }

    return Result::Continue;
}

Result AstMultiVarDecl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeTypeRef && nodeInitRef.isValid())
    {
        const SemaNodeView nodeTypeView = sema.nodeView(nodeTypeRef);
        SemaFrame          frame        = sema.frame();
        frame.pushBindingType(nodeTypeView.typeRef);
        sema.pushFramePopOnPostChild(frame, nodeInitRef);
    }

    return Result::Continue;
}

Result AstMultiVarDecl::semaPostNode(Sema& sema) const
{
    const std::span<Symbol*> symbols = sema.getSymbolList(sema.curNodeRef());
    const SemaPostVarDeclArgs context = {this, tokRef(), nodeInitRef, nodeTypeRef, flags()};
    return semaPostVarDeclCommon(sema, context, symbols);
}

Result AstVarDeclDestructuring::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeInitView = sema.nodeView(nodeInitRef);
    if (!nodeInitView.type->isStruct())
    {
        Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_decomposition_not_struct, nodeInitView.nodeRef);
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
        Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_decomposition_too_many_names, nodeRef(sema.ast()));
        diag.addArgument(Diagnostic::ARG_COUNT, static_cast<uint32_t>(fields.size()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    if (tokNames.size() < fields.size())
    {
        Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_decomposition_not_enough_names, nodeRef(sema.ast()));
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
        sym.setSemaCompleted(sema.ctx());

        RESULT_VERIFY(Match::ghosting(sema, sym));
    }

    sema.setSymbolList(sema.curNodeRef(), symbols.span());
    const SemaPostVarDeclArgs context = {this, tokRef(), nodeInitRef, AstNodeRef::invalid(), flags()};
    return semaPostVarDeclCommon(sema, context, symbols.span());
}

Result AstInitializerExpr::semaPostNode(Sema& sema)
{
    constexpr AstModifierFlags allowed = AstModifierFlagsE::NoDrop |
                                         AstModifierFlagsE::Ref |
                                         AstModifierFlagsE::ConstRef |
                                         AstModifierFlagsE::Move |
                                         AstModifierFlagsE::MoveRaw;
    RESULT_VERIFY(SemaCheck::modifiers(sema, *this, modifierFlags, allowed));

    sema.inheritPayload(*this, nodeExprRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
