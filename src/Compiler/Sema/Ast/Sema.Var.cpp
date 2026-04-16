#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Support/Report/DiagnosticDef.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    SymbolVariable* getVariableSymbol(Symbol* symbol)
    {
        return symbol ? symbol->safeCast<SymbolVariable>() : nullptr;
    }

    bool isGlobalStorageVariable(const SymbolVariable& symVar)
    {
        if (symVar.attributes().hasRtFlag(RtAttributeFlagsE::Global))
            return true;

        const SymbolMap* const owner = symVar.ownerSymMap();
        if (!owner)
            return false;

        return owner->isModule() || owner->isNamespace();
    }

    bool needsStandaloneVariableStorage(const SymbolVariable& symVar)
    {
        const SymbolMap* const owner = symVar.ownerSymMap();
        return !owner || !owner->isStruct();
    }

    bool isAllZeroBytes(ByteSpan bytes)
    {
        for (const std::byte value : bytes)
        {
            if (value != std::byte{})
                return false;
        }

        return true;
    }

    DataSegment& globalStorageSegment(CompilerInstance& compiler, DataSegmentKind kind)
    {
        switch (kind)
        {
            case DataSegmentKind::GlobalZero:
                return compiler.globalZeroSegment();
            case DataSegmentKind::GlobalInit:
                return compiler.globalInitSegment();
            case DataSegmentKind::Compiler:
                return compiler.compilerSegment();
            case DataSegmentKind::Zero:
                return compiler.constantSegment();
        }

        SWC_UNREACHABLE();
    }

    bool tryResolveFunctionAddressInitializer(Sema& sema, AstNodeRef initRef, SymbolFunction*& outTargetFunction)
    {
        outTargetFunction = nullptr;
        if (!initRef.isValid())
            return false;

        const auto* unaryExpr = sema.node(initRef).safeCast<AstUnaryExpr>();
        if (!unaryExpr)
            return false;
        if (sema.token(unaryExpr->codeRef()).id != TokenId::SymAmpersand)
            return false;

        SmallVector<Symbol*> symbols;
        sema.viewSymbol(unaryExpr->nodeExprRef).getSymbols(symbols);
        if (symbols.size() != 1)
            return false;
        if (!symbols.front()->isFunction())
            return false;

        outTargetFunction = &symbols.front()->cast<SymbolFunction>();
        return true;
    }

    Result reportConstRefType(Sema& sema, const SourceCodeRef& codeRef, TypeRef typeRef)
    {
        return SemaError::raiseTypeArgumentError(sema, DiagnosticId::sema_err_const_ref_type, codeRef, typeRef);
    }

    Result reportRefMissingInit(Sema& sema, const SourceCodeRef& codeRef, TypeRef typeRef)
    {
        return SemaError::raiseTypeArgumentError(sema, DiagnosticId::sema_err_ref_missing_init, codeRef, typeRef);
    }

    bool isRetValTypeNode(const Sema& sema, AstNodeRef nodeTypeRef)
    {
        return nodeTypeRef.isValid() && sema.node(nodeTypeRef).is(AstNodeId::RetValType);
    }

    struct VarDeclAffectInitInfo
    {
        bool        handled            = false;
        ConstantRef defaultValueCstRef = ConstantRef::invalid();
    };

    void markRetValVariables(std::span<Symbol*> symbols)
    {
        for (Symbol* s : symbols)
        {
            if (auto* const symVar = getVariableSymbol(s))
                symVar->addExtraFlag(SymbolVariableFlagsE::RetVal);
        }
    }

    AstNodeRef makeVarInitReceiverRef(Sema& sema, SymbolVariable& symVar, AstNodeRef valueRef)
    {
        const TokenRef tokRef            = valueRef.isValid() ? Cast::userDefinedLiteralValueTokRef(sema, valueRef) : sema.curNode().tokRef();
        auto [receiverRef, receiverNode] = sema.ast().makeNode<AstNodeId::Identifier>(tokRef);
        sema.setSymbol(receiverRef, &symVar);
        sema.setIsValue(*receiverNode);
        sema.setIsLValue(*receiverNode);
        return receiverRef;
    }

    Result allocateGlobalStorage(Sema& sema, SymbolVariable& symVar)
    {
        if (symVar.hasGlobalStorage())
            return Result::Continue;
        if (!isGlobalStorageVariable(symVar))
            return Result::Continue;

        TaskContext&    ctx      = sema.ctx();
        const TypeInfo& typeInfo = ctx.typeMgr().get(symVar.typeRef());
        SWC_RESULT(sema.waitSemaCompleted(&typeInfo, sema.curNodeRef()));
        TypeRef storageTypeRef = symVar.typeRef();
        if (typeInfo.isAlias())
        {
            const TypeRef unwrappedTypeRef = typeInfo.unwrap(ctx, storageTypeRef, TypeExpandE::Alias);
            if (unwrappedTypeRef.isValid())
                storageTypeRef = unwrappedTypeRef;
        }

        const TypeInfo& storageTypeInfo = ctx.typeMgr().get(storageTypeRef);

        const uint64_t sizeU64 = storageTypeInfo.sizeOf(ctx);
        if (!sizeU64)
            return Result::Continue;
        SWC_ASSERT(sizeU64 <= std::numeric_limits<uint32_t>::max());
        const uint32_t size      = static_cast<uint32_t>(sizeU64);
        uint32_t       alignment = storageTypeInfo.alignOf(ctx);
        if (!alignment)
            alignment = 1;

        const bool      isCompilerGlobal   = symVar.attributes().hasRtFlag(RtAttributeFlagsE::Compiler);
        const bool      explicitUndefined  = symVar.hasExtraFlag(SymbolVariableFlagsE::ExplicitUndefined);
        const bool      hasInitializerData = symVar.cstRef().isValid() && !explicitUndefined;
        const bool      hasFunctionInit    = symVar.globalFunctionInit() != nullptr && !explicitUndefined;
        DataSegmentKind storageKind        = isCompilerGlobal ? DataSegmentKind::Compiler : DataSegmentKind::GlobalZero;
        if (!isCompilerGlobal && explicitUndefined)
            storageKind = DataSegmentKind::GlobalInit;
        if (!isCompilerGlobal && hasFunctionInit)
            storageKind = DataSegmentKind::GlobalInit;

        SWC_ASSERT(!(isCompilerGlobal && hasFunctionInit));

        std::vector<std::byte> loweredBytes;
        if (hasInitializerData)
        {
            loweredBytes.resize(size);
            std::memset(loweredBytes.data(), 0, loweredBytes.size());
            SWC_RESULT(ConstantLower::lowerToBytes(sema, ByteSpanRW{loweredBytes.data(), loweredBytes.size()}, symVar.cstRef(), storageTypeRef));

            if (!isCompilerGlobal && !isAllZeroBytes(loweredBytes))
                storageKind = DataSegmentKind::GlobalInit;
            else if (!isCompilerGlobal)
                storageKind = DataSegmentKind::GlobalZero;
        }

        DataSegment& segment = globalStorageSegment(ctx.compiler(), storageKind);
        uint32_t     offset  = 0;
        if (hasInitializerData)
        {
            if (storageKind == DataSegmentKind::GlobalInit)
            {
                SWC_RESULT(ConstantLower::materializeStaticPayload(offset, sema, segment, storageTypeRef, ByteSpan{loweredBytes.data(), loweredBytes.size()}));
            }
            else
            {
                const std::pair<ByteSpan, Ref> addRes = segment.addSpan(ByteSpan{loweredBytes.data(), loweredBytes.size()}, alignment);
                offset                                = addRes.second;
            }
        }
        else if (hasFunctionInit)
        {
            SWC_ASSERT(storageKind == DataSegmentKind::GlobalInit);
            SWC_ASSERT(storageTypeInfo.isFunction());

            const std::pair<uint32_t, std::byte*> res = segment.reserveBytes(size, alignment, true);
            offset                                    = res.first;
        }
        else
        {
            const bool zeroInit = !explicitUndefined;
            offset              = segment.reserveBlock(size, alignment, zeroInit);
        }

        symVar.setGlobalStorage(storageKind, offset);
        return Result::Continue;
    }

    void completeConst(Sema& sema, const std::span<Symbol*>& symbols, ConstantRef cstRef, TypeRef typeRef)
    {
        for (Symbol* s : symbols)
        {
            auto& symCst = s->cast<SymbolConstant>();
            symCst.setCstRef(cstRef);
            if (symCst.typeRef().isInvalid())
                symCst.setTypeRef(typeRef);
            symCst.setTyped(sema.ctx());
            symCst.setSemaCompleted(sema.ctx());
        }
    }

    Result completeVar(Sema& sema, const std::span<Symbol*>& symbols, TypeRef typeRef)
    {
        for (Symbol* s : symbols)
        {
            auto& symVar = s->cast<SymbolVariable>();
            if (symVar.typeRef().isInvalid())
                symVar.setTypeRef(typeRef);

            if (!symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) && needsStandaloneVariableStorage(symVar))
            {
                if (sema.isCurrentFunction() && !symVar.attributes().hasRtFlag(RtAttributeFlagsE::Global))
                {
                    // Local type fields are part of the type layout and must not be rewritten as stack locals.
                    SWC_RESULT(SemaHelpers::addCurrentFunctionLocalVariable(sema, symVar));
                }
                else
                    SWC_RESULT(allocateGlobalStorage(sema, symVar));
            }

            symVar.setTyped(sema.ctx());
            symVar.setSemaCompleted(sema.ctx());
            sema.compiler().registerNativeGlobalVariable(&symVar);
        }

        return Result::Continue;
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
        if (explicitTypeRef.isInvalid() || initView.typeRef().isInvalid())
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
        if (!deduceArrayDimsFromType(sema, initView.typeRef(), initDims))
            return TypeRef::invalid();

        if (nodes.size() == 1 && nodes[0].dims.empty())
        {
            if (initDims.empty())
                return TypeRef::invalid();
            if (initDims.size() > 1)
            {
                TypeRef elemTypeRef = baseTypeRef;
                for (const uint64_t& initDim : std::ranges::reverse_view(initDims))
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

        for (Symbol* s : symbols)
        {
            auto* const symVar = getVariableSymbol(s);
            if (!symVar)
                continue;

            const SymbolMap* const owner = symVar->ownerSymMap();
            if (!owner || !owner->isStruct())
                continue;
            symVar->setDefaultValueRef(cstRef);
        }
    }

    void storeParameterDefaultConstants(const std::span<Symbol*>& symbols, bool isParameter, ConstantRef cstRef)
    {
        if (!isParameter || cstRef.isInvalid())
            return;

        for (Symbol* s : symbols)
        {
            auto* const symVar = getVariableSymbol(s);
            if (!symVar)
                continue;

            symVar->setDefaultValueRef(cstRef);
        }
    }

    void storeVariableDefaultConstants(const std::span<Symbol*>& symbols, ConstantRef cstRef)
    {
        if (cstRef.isInvalid())
            return;

        for (Symbol* s : symbols)
        {
            auto* const symVar = getVariableSymbol(s);
            if (!symVar)
                continue;

            symVar->setDefaultValueRef(cstRef);
        }
    }

    void storeLetConstants(const std::span<Symbol*>& symbols, bool isLet, ConstantRef cstRef)
    {
        if (!isLet || cstRef.isInvalid())
            return;

        for (Symbol* s : symbols)
        {
            auto* const symVar = getVariableSymbol(s);
            if (!symVar)
                continue;

            symVar->setCstRef(cstRef);
        }
    }

    void storeGlobalVariableConstants(const std::span<Symbol*>& symbols, ConstantRef cstRef)
    {
        if (cstRef.isInvalid())
            return;

        for (Symbol* s : symbols)
        {
            auto* const symVar = getVariableSymbol(s);
            if (!symVar)
                continue;

            if (!isGlobalStorageVariable(*symVar))
                continue;
            symVar->setCstRef(cstRef);
        }
    }

    void storeDestructuringLetConstants(Sema& sema, const std::span<Symbol*>& symbols, const std::span<const SymbolVariable*>& fields, const std::span<const size_t>& fieldIndices, ConstantRef cstRef)
    {
        if (symbols.empty() || symbols.size() != fields.size() || cstRef.isInvalid())
            return;

        TaskContext&         ctx                 = sema.ctx();
        const ConstantValue& cst                 = sema.cstMgr().get(cstRef);
        const bool           fromAggregateStruct = cst.isAggregateStruct();
        const bool           fromStructBytes     = cst.isStruct();
        if (!fromAggregateStruct && !fromStructBytes)
            return;

        const std::vector<ConstantRef>* aggregateValues = fromAggregateStruct ? &cst.getAggregateStruct() : nullptr;
        const ByteSpan                  structBytes     = fromStructBytes ? cst.getStruct() : ByteSpan{};

        const size_t count = symbols.size();
        for (size_t i = 0; i < count; ++i)
        {
            Symbol* const               sym        = symbols[i];
            const SymbolVariable* const field      = fields[i];
            const size_t                fieldIndex = i < fieldIndices.size() ? fieldIndices[i] : i;
            auto* const                 symVar     = getVariableSymbol(sym);
            if (!symVar)
                continue;

            ConstantRef fieldCstRef = ConstantRef::invalid();
            if (aggregateValues)
            {
                if (fieldIndex < aggregateValues->size())
                    fieldCstRef = (*aggregateValues)[fieldIndex];
            }
            else if (field)
            {
                const TypeRef   fieldTypeRef = field->typeRef();
                const TypeInfo& fieldType    = sema.typeMgr().get(fieldTypeRef);
                const uint64_t  fieldOffset  = field->offset();
                const uint64_t  fieldSize    = fieldType.sizeOf(ctx);
                if (fieldOffset + fieldSize > structBytes.size())
                    continue;

                const auto fieldBytes = ByteSpan{structBytes.data() + fieldOffset, fieldSize};
                fieldCstRef           = ConstantHelpers::materializeStaticPayloadConstant(sema, fieldTypeRef, fieldBytes);
            }

            if (fieldCstRef.isValid())
                symVar->setCstRef(fieldCstRef);
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

    Result tryResolveVarDeclAffectInit(Sema&                      sema,
                                       const SemaPostVarDeclArgs& context,
                                       const std::span<Symbol*>&  symbols,
                                       bool                       isConst,
                                       bool                       isParameter,
                                       TypeRef                    explicitTypeRef,
                                       const TypeInfo*            explicitType,
                                       SemaNodeView&              nodeInitView,
                                       VarDeclAffectInitInfo&     outInfo)
    {
        outInfo = {};

        if (isConst || isParameter)
            return Result::Continue;
        if (!sema.curScope().isLocal())
            return Result::Continue;
        if (symbols.size() != 1 || context.nodeInitRef.isInvalid())
            return Result::Continue;
        if (!explicitTypeRef.isValid() || !explicitType || !explicitType->isStruct())
            return Result::Continue;
        if (!nodeInitView.typeRef().isValid())
            return Result::Continue;

        auto* const symVar = getVariableSymbol(symbols.front());
        if (!symVar)
            return Result::Continue;

        const AstNodeRef receiverRef = makeVarInitReceiverRef(sema, *symVar, context.nodeInitRef);
        bool             handled     = false;
        SWC_RESULT(SemaSpecOp::tryResolveVarInitAffect(sema, receiverRef, context.nodeInitRef, handled));
        if (!handled)
        {
            CastRequest castRequest(CastKind::Initialization);
            castRequest.errorNodeRef = nodeInitView.nodeRef();
            castRequest.setConstantFoldingSrc(nodeInitView.cstRef());
            const Result castAllowedResult = Cast::castAllowed(sema, castRequest, nodeInitView.typeRef(), explicitTypeRef);
            if (castAllowedResult == Result::Pause)
                return Result::Pause;
            if (castAllowedResult == Result::Continue)
                return Result::Continue;
            return Result::Continue;
        }

        symVar->addExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage);
        outInfo.handled = true;

        const auto* payload = sema.semaPayload<VarInitSpecOpPayload>(sema.curNodeRef());
        if (payload &&
            payload->calledFn &&
            !payload->calledFn->attributes().hasRtFlag(RtAttributeFlagsE::Complete))
        {
            SWC_RESULT(sema.waitSemaCompleted(explicitType, context.nodeTypeRef));
            outInfo.defaultValueCstRef = explicitType->payloadSymStruct().computeDefaultValue(sema, explicitTypeRef);
        }

        nodeInitView.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        return Result::Continue;
    }

    Result reportMissingInitializer(Sema& sema, DiagnosticId id, const SemaPostVarDeclArgs& context, const std::span<Symbol*>& symbols)
    {
        const SourceCodeRef where{context.owner->srcViewRef(), context.tokDiag};
        if (symbols.size() == 1 && symbols[0])
        {
            auto diag = SemaError::report(sema, id, where);
            diag.addArgument(Diagnostic::ARG_SYM, symbols[0]->name(sema.ctx()));
            diag.report(sema.ctx());
            return Result::Error;
        }

        return SemaError::raise(sema, id, where);
    }

    Result checkUndefinedInit(Sema& sema, const SemaPostVarDeclArgs& context, const std::span<Symbol*>& symbols, bool isConst, bool isLet, bool isParameter, TypeRef explicitTypeRef, const TypeInfo* explicitType, const SemaNodeView& nodeInitView, bool& isExplicitUndefinedInit)
    {
        if (context.nodeInitRef.isInvalid() || nodeInitView.cstRef() != sema.cstMgr().cstUndefined())
            return Result::Continue;

        if (isConst)
            return reportMissingInitializer(sema, DiagnosticId::sema_err_const_missing_init, context, symbols);
        if (isLet)
            return reportMissingInitializer(sema, DiagnosticId::sema_err_let_missing_init, context, symbols);
        if (context.nodeTypeRef.isInvalid())
            return SemaError::raise(sema, DiagnosticId::sema_err_not_type, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag});
        if (!isParameter && explicitTypeRef.isValid() && explicitType && explicitType->isReference())
            return reportRefMissingInit(sema, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag}, explicitTypeRef);

        isExplicitUndefinedInit = true;
        return Result::Continue;
    }

    Result castOrConcretizeInit(Sema& sema, const SemaPostVarDeclArgs& context, bool codeParameterDefault, TypeRef explicitTypeRef, SemaNodeView& nodeInitView)
    {
        SWC_UNUSED(context);

        if (codeParameterDefault)
            return Result::Continue;

        if (nodeInitView.typeRef().isValid() && explicitTypeRef.isValid())
            return Cast::cast(sema, nodeInitView, explicitTypeRef, CastKind::Initialization);

        if (nodeInitView.cstRef().isValid())
        {
            ConstantRef newCstRef;
            SWC_RESULT(Cast::concretizeConstant(sema, newCstRef, nodeInitView.nodeRef(), nodeInitView.cstRef(), TypeInfo::Sign::Unknown));
            sema.setConstant(nodeInitView.nodeRef(), newCstRef);
            nodeInitView.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);

            if (nodeInitView.type()->isInt())
            {
                const TypeRef newTypeRef = sema.typeMgr().promote(nodeInitView.typeRef(), nodeInitView.typeRef(), false);
                SWC_RESULT(Cast::cast(sema, nodeInitView, newTypeRef, CastKind::Implicit));
            }
        }

        return Result::Continue;
    }

    Result concretizeAggregateArray(Sema& sema, const SemaPostVarDeclArgs& context, TypeRef explicitTypeRef, TypeRef& finalTypeRef, SemaNodeView& nodeInitView)
    {
        TypeManager& typeMgr = sema.typeMgr();

        if (explicitTypeRef.isValid() || finalTypeRef.isInvalid() || !typeMgr.get(finalTypeRef).isAggregateArray())
            return Result::Continue;

        const auto& elemTypes = typeMgr.get(finalTypeRef).payloadAggregate().types;
        if (elemTypes.empty())
            return Result::Continue;

        // All elements must be compatible (same kind, or all numeric).
        const TypeInfo& firstElem = typeMgr.get(elemTypes[0]);
        for (size_t i = 1; i < elemTypes.size(); ++i)
        {
            const TypeInfo& ei = typeMgr.get(elemTypes[i]);
            if (ei.kind() != firstElem.kind() && !(firstElem.isScalarNumeric() && ei.isScalarNumeric()))
                return Result::Continue;
        }

        // Determine the element type. For nested aggregates (e.g. [[1,2],[3,4]]),
        // recursively concretize the inner aggregate first, then wrap with the
        // outer dimension to produce [2][2] s32 (not [2, 2] s32).
        TypeRef elemTypeRef = elemTypes[0];
        if (typeMgr.get(elemTypeRef).isAggregateArray())
        {
            // Get the concretized inner element type from the constant value.
            if (nodeInitView.cstRef().isValid())
            {
                const ConstantValue& cst = sema.cstMgr().get(nodeInitView.cstRef());
                if (cst.isAggregateArray())
                {
                    const auto& values = cst.getAggregateArray();
                    if (!values.empty())
                        elemTypeRef = sema.cstMgr().get(values[0]).typeRef();
                }
            }

            // If the inner element is still an aggregate, walk to the leaf type
            // and build nested array types from the inside out.
            if (typeMgr.get(elemTypeRef).isAggregateArray())
            {
                SmallVector4<uint64_t> innerDims;
                if (!deduceArrayDimsFromType(sema, elemTypeRef, innerDims) || innerDims.empty())
                    return Result::Continue;
                TypeRef leafTypeRef = elemTypeRef;
                while (typeMgr.get(leafTypeRef).isAggregateArray())
                {
                    const auto& inner = typeMgr.get(leafTypeRef).payloadAggregate().types;
                    if (inner.empty())
                        break;
                    leafTypeRef = inner[0];
                }
                // Build innermost array first, then wrap each outer dimension.
                elemTypeRef = leafTypeRef;
                for (unsigned long long& innerDim : std::views::reverse(innerDims))
                {
                    SmallVector4<uint64_t> d;
                    d.push_back(innerDim);
                    elemTypeRef = typeMgr.addType(TypeInfo::makeArray(d, elemTypeRef));
                }
            }
        }
        else
        {
            // Leaf element: get the concretized type from the constant.
            if (nodeInitView.cstRef().isValid())
            {
                const ConstantValue& cst = sema.cstMgr().get(nodeInitView.cstRef());
                if (cst.isAggregateArray())
                {
                    const auto& values = cst.getAggregateArray();
                    if (!values.empty())
                        elemTypeRef = sema.cstMgr().get(values[0]).typeRef();
                }
            }
        }

        SmallVector4<uint64_t> outerDim;
        outerDim.push_back(elemTypes.size());
        finalTypeRef = typeMgr.addType(TypeInfo::makeArray(outerDim, elemTypeRef));
        if (context.nodeInitRef.isValid())
            SWC_RESULT(Cast::cast(sema, nodeInitView, finalTypeRef, CastKind::Initialization));

        return Result::Continue;
    }

    Result validateFinalType(Sema& sema, const SemaPostVarDeclArgs& context, TypeRef finalTypeRef, bool isConst, bool isParameter, bool isUsing)
    {
        if (finalTypeRef.isInvalid())
            return Result::Continue;

        const TypeInfo& finalType = sema.typeMgr().get(finalTypeRef);

        if (isConst && finalType.isReference())
            return reportConstRefType(sema, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag}, finalTypeRef);

        if (finalType.isCodeBlock())
        {
            const auto* currentFn        = sema.currentFunction();
            const bool  allowedCodeParam = isParameter && currentFn &&
                                          (currentFn->attributes().hasRtFlag(RtAttributeFlagsE::Macro) ||
                                           currentFn->attributes().hasRtFlag(RtAttributeFlagsE::Mixin));
            if (!allowedCodeParam)
            {
                const SourceCodeRef errorRef = context.nodeTypeRef.isValid() ? sema.node(context.nodeTypeRef).codeRef() : sema.node(context.nodeInitRef).codeRef();
                return SemaError::raiseCodeTypeRestricted(sema, errorRef, finalTypeRef);
            }
        }

        if (isUsing)
        {
            if (!finalType.isStruct())
            {
                if (!finalType.isAnyPointer() || !sema.typeMgr().get(finalType.payloadTypeRef()).isStruct())
                {
                    Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_using_member_type, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag});
                    diag.addArgument(Diagnostic::ARG_TYPE, finalTypeRef);
                    diag.report(sema.ctx());
                    return Result::Error;
                }
            }
        }

        return Result::Continue;
    }

    Result semaPostVarDeclCommon(Sema& sema, const SemaPostVarDeclArgs& context, const std::span<Symbol*>& symbols)
    {
        SemaNodeView nodeInitView = sema.viewNodeTypeConstant(context.nodeInitRef);
        if (context.nodeInitRef.isValid())
            SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, nodeInitView));

        const SemaNodeView nodeTypeView    = sema.viewType(context.nodeTypeRef);
        TypeRef            explicitTypeRef = nodeTypeView.typeRef();

        if (nodeInitView.typeRef().isValid())
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

        const bool            isConst                 = context.flags.has(AstVarDeclFlagsE::Const);
        const bool            isLet                   = context.flags.has(AstVarDeclFlagsE::Let);
        const bool            isParameter             = context.flags.has(AstVarDeclFlagsE::Parameter);
        const bool            isUsing                 = context.flags.has(AstVarDeclFlagsE::Using);
        const bool            codeParameterDefault    = isParameter && explicitType && explicitType->isCodeBlock();
        bool                  isExplicitUndefinedInit = false;
        SymbolFunction*       globalFunctionInit      = nullptr;
        VarDeclAffectInitInfo affectInitInfo;

        SWC_RESULT(checkUndefinedInit(sema, context, symbols, isConst, isLet, isParameter, explicitTypeRef, explicitType, nodeInitView, isExplicitUndefinedInit));
        SWC_RESULT(tryResolveVarDeclAffectInit(sema, context, symbols, isConst, isParameter, explicitTypeRef, explicitType, nodeInitView, affectInitInfo));
        if (!affectInitInfo.handled)
            SWC_RESULT(castOrConcretizeInit(sema, context, codeParameterDefault, explicitTypeRef, nodeInitView));

        if (context.nodeInitRef.isValid() && !affectInitInfo.handled)
            storeFieldDefaultConstants(symbols, nodeInitView.cstRef());

        const bool allowGlobalFunctionAddressInit = !sema.curScope().isLocal() &&
                                                    !sema.curScope().isParameters() &&
                                                    !isConst &&
                                                    tryResolveFunctionAddressInitializer(sema, context.nodeInitRef, globalFunctionInit);

        if (!sema.curScope().isLocal() && !sema.curScope().isParameters() && !isConst && context.nodeInitRef.isValid() && !allowGlobalFunctionAddressInit)
            SWC_RESULT(SemaCheck::isConstant(sema, nodeInitView.nodeRef()));

        TypeRef finalTypeRef = explicitTypeRef.isValid() ? explicitTypeRef : nodeInitView.typeRef();

        SWC_RESULT(concretizeAggregateArray(sema, context, explicitTypeRef, finalTypeRef, nodeInitView));

        SWC_RESULT(validateFinalType(sema, context, finalTypeRef, isConst, isParameter, isUsing));

        const SymbolMap* fieldOwnerSymMap      = !symbols.empty() && symbols[0] ? symbols[0]->ownerSymMap() : nullptr;
        const bool       directSelfStructField = explicitTypeRef.isValid() &&
                                           explicitType &&
                                           explicitType->isStruct() &&
                                           fieldOwnerSymMap &&
                                           fieldOwnerSymMap->isStruct() &&
                                           &explicitType->payloadSymStruct() == &fieldOwnerSymMap->cast<SymbolStruct>();

        ConstantRef implicitStructCstRef = ConstantRef::invalid();
        if (context.nodeInitRef.isInvalid() && !isParameter && explicitTypeRef.isValid() && explicitType && explicitType->isStruct())
        {
            if (!directSelfStructField)
            {
                SWC_RESULT(sema.waitSemaCompleted(explicitType, context.nodeTypeRef));
                implicitStructCstRef = explicitType->payloadSymStruct().computeDefaultValue(sema, explicitTypeRef);
            }
        }
        const bool hasImplicitStructInit = implicitStructCstRef.isValid();

        // Constant
        if (isConst)
        {
            if (context.nodeInitRef.isInvalid())
            {
                if (!hasImplicitStructInit)
                    return reportMissingInitializer(sema, DiagnosticId::sema_err_const_missing_init, context, symbols);
                completeConst(sema, symbols, implicitStructCstRef, explicitTypeRef);
                return Result::Continue;
            }
            if (nodeInitView.cstRef().isInvalid())
                return SemaError::raiseExprNotConst(sema, nodeInitView.nodeRef());

            completeConst(sema, symbols, nodeInitView.cstRef(), nodeInitView.typeRef());
            return Result::Continue;
        }

        // Variable
        if (isLet && context.nodeInitRef.isInvalid() && !hasImplicitStructInit)
            return reportMissingInitializer(sema, DiagnosticId::sema_err_let_missing_init, context, symbols);
        const bool isRefType = finalTypeRef.isValid() && sema.typeMgr().get(finalTypeRef).isReference();
        if (!isLet && !isParameter && isRefType && context.nodeInitRef.isInvalid())
            return reportRefMissingInit(sema, SourceCodeRef{context.owner->srcViewRef(), context.tokDiag}, finalTypeRef);

        const ConstantRef initCstRef        = affectInitInfo.handled ? ConstantRef::invalid() : (context.nodeInitRef.isValid() ? nodeInitView.cstRef() : implicitStructCstRef);
        const ConstantRef variableDefaultCf = affectInitInfo.handled ? affectInitInfo.defaultValueCstRef : initCstRef;
        storeLetConstants(symbols, isLet, initCstRef);
        storeGlobalVariableConstants(symbols, initCstRef);
        storeParameterDefaultConstants(symbols, isParameter, context.nodeInitRef.isValid() ? initCstRef : ConstantRef::invalid());
        storeVariableDefaultConstants(symbols, variableDefaultCf);

        if (allowGlobalFunctionAddressInit)
        {
            for (Symbol* s : symbols)
            {
                auto* const symVar = getVariableSymbol(s);
                if (!symVar)
                    continue;
                if (!isGlobalStorageVariable(*symVar))
                    continue;
                symVar->setGlobalFunctionInit(globalFunctionInit);
                sema.compiler().registerNativeGlobalFunctionInitTarget(globalFunctionInit);
            }
        }

        if (context.nodeInitRef.isValid() || hasImplicitStructInit)
        {
            // Check if the init expression is a #callerlocation default
            bool isCallerLocation = false;
            if (context.nodeInitRef.isValid())
            {
                const AstNode& initNode = sema.node(context.nodeInitRef);
                if (initNode.is(AstNodeId::CompilerLiteral))
                {
                    const Token& tok = sema.token(initNode.codeRef());
                    isCallerLocation = tok.id == TokenId::CompilerCallerLocation;
                }
            }

            for (Symbol* s : symbols)
            {
                auto& symVar = s->cast<SymbolVariable>();
                if (isExplicitUndefinedInit)
                    symVar.addExtraFlag(SymbolVariableFlagsE::ExplicitUndefined);
                if (isCallerLocation)
                    symVar.addExtraFlag(SymbolVariableFlagsE::CallerLocationDefault);
                symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
            }
        }

        SWC_RESULT(completeVar(sema, symbols, explicitTypeRef.isValid() ? explicitTypeRef : nodeInitView.typeRef()));
        return Result::Continue;
    }

    bool requiresConstExprInitializer(const Sema& sema, EnumFlags<AstVarDeclFlagsE> flags)
    {
        if (flags.has(AstVarDeclFlagsE::Const))
            return true;
        if (flags.has(AstVarDeclFlagsE::Parameter))
            return true;
        return !sema.curScope().isLocal() && !sema.curScope().isParameters();
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
            auto& symVar = sema.curViewSymbol().sym()->cast<SymbolVariable>();
            symVar.addExtraFlag(SymbolVariableFlagsE::Let);
        }
    }

    return Result::SkipChildren;
}

Result AstSingleVarDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);
    const Symbol& sym = *sema.curViewSymbol().sym();
    return Match::ghosting(sema, sym);
}

Result AstSingleVarDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeInitRef && requiresConstExprInitializer(sema, flags()))
        SemaHelpers::pushConstExprRequirement(sema, childRef);
    return Result::Continue;
}

Result AstSingleVarDecl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeTypeRef)
    {
        const bool isRetVal = isRetValTypeNode(sema, nodeTypeRef);
        if (isRetVal)
            sema.curViewSymbol().sym()->cast<SymbolVariable>().addExtraFlag(SymbolVariableFlagsE::RetVal);

        if (nodeInitRef.isValid())
        {
            const SemaNodeView nodeTypeView = sema.viewType(nodeTypeRef);
            SemaFrame          frame        = sema.frame();
            frame.pushBindingType(nodeTypeView.typeRef());
            const bool bindArrayRuntimeStorage =
                !hasFlag(AstVarDeclFlagsE::Const) &&
                sema.curScope().isLocal() &&
                nodeTypeView.typeRef().isValid() &&
                sema.typeMgr().get(nodeTypeView.typeRef()).isArray();
            const bool bindClosureRuntimeStorage = nodeTypeView.typeRef().isValid() && sema.typeMgr().get(nodeTypeView.typeRef()).isLambdaClosure();
            if (bindArrayRuntimeStorage ||
                (isRetVal && SemaHelpers::currentFunctionUsesIndirectReturnStorage(sema)) ||
                bindClosureRuntimeStorage)
                frame.setCurrentRuntimeStorage(nodeInitRef, &sema.curViewSymbol().sym()->cast<SymbolVariable>());
            sema.pushFramePopOnPostChild(frame, nodeInitRef);
        }
    }

    return Result::Continue;
}

Result AstSingleVarDecl::semaPostNode(Sema& sema) const
{
    Symbol&                   sym     = *sema.curViewSymbol().sym();
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
            const Symbol& sym = SemaHelpers::registerSymbol<SymbolConstant>(sema, *this, tokNameRef);
            symbols.push_back(&sym);
        }
        else
        {
            const Symbol& sym = SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokNameRef);
            symbols.push_back(&sym);
            if (hasFlag(AstVarDeclFlagsE::Let))
            {
                auto& symVar = sema.curViewSymbol().sym()->cast<SymbolVariable>();
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
        SemaNodeView nodeSymbolsView = sema.curViewSymbolList();
        if (!nodeSymbolsView.hasSymbolList())
            semaPreDecl(sema);
        nodeSymbolsView.recompute(sema, SemaNodeViewPartE::Symbol);
        const std::span<Symbol*> symbols = nodeSymbolsView.symList();
        SemaHelpers::ensureCurrentLocalScopeSymbols(sema, symbols);
        for (Symbol* sym : symbols)
        {
            sym->registerAttributes(sema);
            sym->setDeclared(sema.ctx());
        }
    }

    const std::span<Symbol*> symbols = sema.curViewSymbolList().symList();
    for (const Symbol* sym : symbols)
    {
        SWC_RESULT(Match::ghosting(sema, *sym));
    }

    return Result::Continue;
}

Result AstMultiVarDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeInitRef && requiresConstExprInitializer(sema, flags()))
        SemaHelpers::pushConstExprRequirement(sema, childRef);
    return Result::Continue;
}

Result AstMultiVarDecl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeTypeRef)
    {
        if (isRetValTypeNode(sema, nodeTypeRef))
            markRetValVariables(sema.curViewSymbolList().symList());

        if (nodeInitRef.isValid())
        {
            const SemaNodeView nodeTypeView = sema.viewType(nodeTypeRef);
            SemaFrame          frame        = sema.frame();
            frame.pushBindingType(nodeTypeView.typeRef());
            sema.pushFramePopOnPostChild(frame, nodeInitRef);
        }
    }

    return Result::Continue;
}

Result AstMultiVarDecl::semaPostNode(Sema& sema) const
{
    const std::span<Symbol*>  symbols = sema.curViewSymbolList().symList();
    const SemaPostVarDeclArgs context = {this, tokRef(), nodeInitRef, nodeTypeRef, flags()};
    return semaPostVarDeclCommon(sema, context, symbols);
}

Result AstVarDeclDestructuring::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeInitView = sema.viewType(nodeInitRef);
    const bool         isStruct     = nodeInitView.type()->isStruct();
    const bool         isAggregate  = nodeInitView.type()->isAggregateStruct();
    if (!isStruct && !isAggregate)
    {
        Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_decomposition_not_struct, nodeInitView.nodeRef());
        diag.addArgument(Diagnostic::ARG_TYPE, nodeInitView.typeRef());
        diag.report(sema.ctx());
        return Result::Error;
    }

    const auto*  structFields   = isStruct ? &nodeInitView.type()->payloadSymStruct().fields() : nullptr;
    const auto*  aggregateTypes = isAggregate ? &nodeInitView.type()->payloadAggregate().types : nullptr;
    const size_t fieldCount     = isStruct ? structFields->size() : aggregateTypes->size();

    SmallVector<TokenRef> tokNames;
    sema.ast().appendTokens(tokNames, spanNamesRef);

    if (tokNames.size() > fieldCount)
    {
        Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_decomposition_too_many_names, nodeRef(sema.ast()));
        diag.addArgument(Diagnostic::ARG_COUNT, static_cast<uint32_t>(fieldCount));
        diag.report(sema.ctx());
        return Result::Error;
    }

    if (tokNames.size() < fieldCount)
    {
        Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_decomposition_not_enough_names, nodeRef(sema.ast()));
        diag.addArgument(Diagnostic::ARG_COUNT, static_cast<uint32_t>(fieldCount));
        diag.report(sema.ctx());
        return Result::Error;
    }

    SmallVector<Symbol*>               symbols;
    SmallVector<const SymbolVariable*> fieldsForSymbols;
    SmallVector<size_t>                fieldIndices;
    for (size_t i = 0; i < tokNames.size(); i++)
    {
        const auto& tokNameRef = tokNames[i];
        if (tokNameRef.isInvalid())
            continue;

        auto& sym = SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokNameRef);
        if (hasFlag(AstVarDeclFlagsE::Let))
            sym.addExtraFlag(SymbolVariableFlagsE::Let);
        sym.setDeclared(sema.ctx());

        symbols.push_back(&sym);
        fieldIndices.push_back(i);

        if (isStruct)
        {
            const SymbolVariable* field = (*structFields)[i];
            sym.setTypeRef(field->typeRef());
            fieldsForSymbols.push_back(field);
        }
        else
        {
            TypeRef elemTypeRef = (*aggregateTypes)[i];

            // Concretize unresolved literal types using the init constant.
            if (sema.typeMgr().get(elemTypeRef).sizeOf(sema.ctx()) == 0)
            {
                const SemaNodeView initCstView = sema.viewNodeTypeConstant(nodeInitRef);
                if (initCstView.cstRef().isValid())
                {
                    const ConstantValue& aggCst = sema.cstMgr().get(initCstView.cstRef());
                    if (aggCst.isAggregateStruct() && i < aggCst.getAggregateStruct().size())
                    {
                        const ConstantRef    elemCstRef = aggCst.getAggregateStruct()[i];
                        const ConstantValue& elemCst    = sema.cstMgr().get(elemCstRef);
                        if (elemCst.isInt())
                            elemTypeRef = sema.typeMgr().typeS32();
                        else if (elemCst.isFloat())
                            elemTypeRef = sema.typeMgr().typeF64();
                        else if (elemCst.isBool())
                            elemTypeRef = sema.typeMgr().typeBool();
                    }
                }
            }

            sym.setTypeRef(elemTypeRef);
            fieldsForSymbols.push_back(nullptr);
        }

        sym.setTyped(sema.ctx());
        sym.setSemaCompleted(sema.ctx());

        SWC_RESULT(Match::ghosting(sema, sym));
    }

    sema.setSymbolList(sema.curNodeRef(), symbols.span());
    const SemaPostVarDeclArgs context = {this, tokRef(), nodeInitRef, AstNodeRef::invalid(), flags()};
    SWC_RESULT(semaPostVarDeclCommon(sema, context, symbols.span()));

    const SemaNodeView refreshedInitView = sema.viewNodeTypeConstant(nodeInitRef);
    SWC_RESULT(SemaHelpers::attachRuntimeStorageIfNeeded(sema, *this, refreshedInitView.typeRef(), "__decomp_runtime_storage"));
    storeDestructuringLetConstants(sema, symbols.span(), fieldsForSymbols.span(), std::span<const size_t>{fieldIndices.data(), fieldIndices.size()}, refreshedInitView.cstRef());

    return Result::Continue;
}

Result AstInitializerExpr::semaPostNode(Sema& sema)
{
    constexpr AstModifierFlags allowed = AstModifierFlagsE::NoDrop |
                                         AstModifierFlagsE::Ref |
                                         AstModifierFlagsE::ConstRef |
                                         AstModifierFlagsE::Move |
                                         AstModifierFlagsE::MoveRaw;
    SWC_RESULT(SemaCheck::modifiers(sema, *this, modifierFlags, allowed));

    sema.inheritPayload(*this, nodeExprRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
