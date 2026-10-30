#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroReg.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenSafety.h"
#include "Compiler/CodeGen/Core/CodeGenStructHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTaggedHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

CodeGenNodePayload CodeGen::conditionBindingPayload(TypeRef& outTypeRef, AstNodeRef nodeRef)
{
    const Symbol* symbol = viewSymbol(nodeRef).singleSymbol();
    SWC_ASSERT(symbol);
    outTypeRef = symbol->typeRef();
    if (symbol->isVariable())
    {
        const auto& variable = symbol->cast<SymbolVariable>();

        // Deferred bodies do not cache stack addresses: each emitted copy must
        // materialize a register dominated by its own control-flow path.
        if (variable.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) && localStackBaseReg().isValid())
            return resolveLocalStackPayload(variable);

        const auto* value = variablePayload(variable);
        SWC_ASSERT(value);
        return *value;
    }

    return payload(nodeRef);
}

namespace
{
    // A '*' matches any run of characters; everything else matches itself.
    bool printMicroPatternMatches(std::string_view pattern, std::string_view name)
    {
        const size_t star = pattern.find('*');
        if (star == std::string_view::npos)
            return pattern == name;
        if (!name.starts_with(pattern.substr(0, star)))
            return false;

        const std::string_view rest = pattern.substr(star + 1);
        for (size_t start = star; start <= name.size(); ++start)
        {
            if (printMicroPatternMatches(rest, name.substr(start)))
                return true;
        }

        return false;
    }
}

// '--print-micro' selects a function by its scoped name or by a trailing part of it, so
// 'Lib.Codec.decode', 'Codec.decode' and 'decode' all name the same function.
void CodeGen::appendCommandLinePrintMicroStages(std::vector<Utf8>& stages, std::span<const Utf8> requests, std::string_view scopedName)
{
    for (const Utf8& request : requests)
    {
        const std::string_view value   = request.view();
        const size_t           colon   = value.find(':');
        const std::string_view pattern = value.substr(0, colon);

        bool matches = printMicroPatternMatches(pattern, scopedName);
        for (size_t dot = scopedName.find('.'); !matches && dot != std::string_view::npos; dot = scopedName.find('.', dot + 1))
            matches = printMicroPatternMatches(pattern, scopedName.substr(dot + 1));

        if (matches)
            stages.emplace_back(colon == std::string_view::npos ? std::string_view{"pre-emit"} : value.substr(colon + 1));
    }
}

namespace
{
    const CodeGenFrame::InlineContext* findMatchingInlineContext(std::span<const CodeGenFrame> frames, AstNodeRef rootNodeRef, const SemaInlinePayload* payload)
    {
        if (!payload || rootNodeRef.isInvalid())
            return nullptr;

        for (size_t frameIndex = frames.size(); frameIndex != 0; --frameIndex)
        {
            const CodeGenFrame& frame = frames[frameIndex - 1];
            if (!frame.hasCurrentInlineContext())
                continue;

            const CodeGenFrame::InlineContext& inlineCtx = frame.currentInlineContext();
            if (inlineCtx.rootNodeRef == rootNodeRef && inlineCtx.payload == payload)
                return &inlineCtx;
        }

        return nullptr;
    }

    bool isTemporaryDropBlock(const AstNodeId id)
    {
        return id == AstNodeId::FunctionBody || id == AstNodeId::EmbeddedBlock || id == AstNodeId::TopLevelBlock || id == AstNodeId::SwitchCaseBody;
    }

    bool isLazyEvaluationNode(const AstNodeId id)
    {
        switch (id)
        {
            case AstNodeId::LogicalExpr:
            case AstNodeId::ConditionalExpr:
            case AstNodeId::NullCoalescingExpr:
            case AstNodeId::OptionalChainExpr:
            case AstNodeId::ErrorManagementExpr:
            case AstNodeId::ErrorManagementStmt:
                return true;
            default:
                return false;
        }
    }

    bool isTemporaryDropEvaluationBoundary(const AstNode& parent, const AstNodeRef childRef)
    {
        switch (parent.id())
        {
            case AstNodeId::IfStmt:
            {
                const auto& stmt = parent.cast<AstIfStmt>();
                return childRef == stmt.nodeConditionRef || childRef == stmt.nodeIfBlockRef || childRef == stmt.nodeElseBlockRef;
            }

            case AstNodeId::IfVarDecl:
            {
                const auto& stmt = parent.cast<AstIfVarDecl>();
                return childRef == stmt.nodeVarRef || childRef == stmt.nodeWhereRef || childRef == stmt.nodeIfBlockRef || childRef == stmt.nodeElseBlockRef;
            }

            case AstNodeId::WhileStmt:
            {
                const auto& stmt = parent.cast<AstWhileStmt>();
                return childRef == stmt.nodeExprRef || childRef == stmt.nodeBodyRef;
            }

            case AstNodeId::ForCStyleStmt:
            {
                const auto& stmt = parent.cast<AstForCStyleStmt>();
                return childRef == stmt.nodeVarDeclRef || childRef == stmt.nodeExprRef || childRef == stmt.nodePostStmtRef || childRef == stmt.nodeBodyRef;
            }

            case AstNodeId::ForStmt:
            {
                const auto& stmt = parent.cast<AstForStmt>();
                return childRef == stmt.nodeWhereRef || childRef == stmt.nodeBodyRef;
            }

            case AstNodeId::ForeachStmt:
            {
                const auto& stmt = parent.cast<AstForeachStmt>();
                return childRef == stmt.nodeWhereRef || childRef == stmt.nodeBodyRef;
            }

            case AstNodeId::InfiniteLoopStmt:
                return childRef == parent.cast<AstInfiniteLoopStmt>().nodeBodyRef;
            case AstNodeId::WithStmt:
                return childRef == parent.cast<AstWithStmt>().nodeBodyRef;
            case AstNodeId::WithVarDecl:
                return childRef == parent.cast<AstWithVarDecl>().nodeBodyRef;
            default:
                return false;
        }
    }

    bool isStackAddressPayload(const CodeGen& codeGen, const SymbolVariable& sym, const CodeGenNodePayload& payload)
    {
        if (!payload.isAddress())
            return false;

        if (sym.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
            return true;

        return codeGen.localStackBaseReg().isValid() && sym.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal);
    }

    TypeRef normalizeLifecycleTypeRef(const CodeGen& codeGen, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        return codeGen.typeMgr().unwrapAlias(codeGen.ctx(), typeRef);
    }

    void mergeNodeLoweringMetadata(CodeGenNodePayload& dst, const CodeGenLoweringPayload& src)
    {
        if (!dst.runtimeStorageOverridden && !dst.runtimeStorageSym && src.runtimeStorageSym)
            dst.runtimeStorageSym = src.runtimeStorageSym;
        if (!dst.runtimeFunctionSymbol && src.runtimeFunctionSymbol)
            dst.runtimeFunctionSymbol = src.runtimeFunctionSymbol;

        if (!dst.runtimeArrayFillTypeRef.isValid() && src.runtimeArrayFillTypeRef.isValid())
            dst.runtimeArrayFillTypeRef = src.runtimeArrayFillTypeRef;
        if (!dst.runtimeArrayFillCstRef.isValid() && src.runtimeArrayFillCstRef.isValid())
            dst.runtimeArrayFillCstRef = src.runtimeArrayFillCstRef;

        dst.runtimeSafetyMask |= src.runtimeSafetyMask;
        dst.ownsValue |= src.ownsValue;

        if (!dst.fallibleWrapperConsumed && !dst.hasFallibleWrapper() && src.hasFallibleWrapper())
        {
            dst.fallibleWrapperOwnerRef = src.fallibleWrapperOwnerRef;
            dst.fallibleWrapperTokenId  = src.fallibleWrapperTokenId;
        }
    }

    void mergeNodePayloadMetadata(CodeGenNodePayload& dst, const CodeGenNodePayload& src)
    {
        if (src.runtimeStorageOverridden)
        {
            dst.runtimeStorageSym        = src.runtimeStorageSym;
            dst.runtimeStorageOverridden = true;
        }

        mergeNodeLoweringMetadata(dst, src);
    }

#if SWC_DEV_MODE
    void appendMissingPayloadDebugNode(Utf8& outDetail, const AstNode& node, const AstNodeRef nodeRef, const char* label)
    {
        const std::string_view nodeName = Ast::nodeIdName(node.id());
        outDetail += std::format("  {}={}({:.{}})\n", label, nodeRef.get(), nodeName.data(), static_cast<int>(nodeName.size()));
    }

    Utf8 formatMissingPayloadDebug(CodeGen& codeGen, AstNodeRef queryRef, AstNodeRef resolvedRef, CodeGenNodePayload* payload)
    {
        Utf8 detail = "missing-codegen-payload:\n";

        if (queryRef.isValid())
            appendMissingPayloadDebugNode(detail, codeGen.node(queryRef), queryRef, "query");
        if (resolvedRef.isValid())
            appendMissingPayloadDebugNode(detail, codeGen.node(resolvedRef), resolvedRef, "resolved");
        if (codeGen.curNodeRef().isValid())
            appendMissingPayloadDebugNode(detail, codeGen.curNode(), codeGen.curNodeRef(), "current");

        detail += std::format("  payload={} regValid={}\n", static_cast<void*>(payload), payload && payload->reg.isValid());

        if (queryRef.isValid())
        {
            const SemaNodeView storedView = codeGen.sema().viewStored(queryRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol);
            const SemaNodeView liveView   = codeGen.viewTypeSymbol(queryRef);
            detail += std::format("  query storedType={} liveType={} storedSym={} liveSym={}\n",
                                  storedView.typeRef().isValid() ? storedView.typeRef().get() : 0,
                                  liveView.typeRef().isValid() ? liveView.typeRef().get() : 0,
                                  storedView.sym() != nullptr,
                                  liveView.sym() != nullptr);

            if (const auto* autoMember = codeGen.node(queryRef).safeCast<AstAutoMemberAccessExpr>())
            {
                const AstNodeRef identRef         = autoMember->nodeIdentRef;
                const AstNodeRef resolvedIdentRef = codeGen.resolvedNodeRef(identRef);
                if (identRef.isValid())
                    appendMissingPayloadDebugNode(detail, codeGen.node(identRef), identRef, "auto-ident");
                if (resolvedIdentRef.isValid() && resolvedIdentRef != identRef)
                    appendMissingPayloadDebugNode(detail, codeGen.node(resolvedIdentRef), resolvedIdentRef, "auto-ident-resolved");
            }
        }

        if (resolvedRef.isValid())
        {
            if (const auto* member = codeGen.node(resolvedRef).safeCast<AstMemberAccessExpr>())
            {
                const AstNodeRef leftRef          = member->nodeLeftRef;
                const AstNodeRef rightRef         = member->nodeRightRef;
                const AstNodeRef resolvedRightRef = codeGen.resolvedNodeRef(rightRef);
                if (leftRef.isValid())
                    appendMissingPayloadDebugNode(detail, codeGen.node(leftRef), leftRef, "member-left");
                if (rightRef.isValid())
                    appendMissingPayloadDebugNode(detail, codeGen.node(rightRef), rightRef, "member-right");
                if (resolvedRightRef.isValid() && resolvedRightRef != rightRef)
                    appendMissingPayloadDebugNode(detail, codeGen.node(resolvedRightRef), resolvedRightRef, "member-right-resolved");
            }
        }

        return detail;
    }
#endif

    TypeManager::LifecycleOperator lifecycleOperator(const CodeGenLifecycleKind lifecycleKind)
    {
        switch (lifecycleKind)
        {
            case CodeGenLifecycleKind::Drop:
                return &SymbolStruct::opDrop;
            case CodeGenLifecycleKind::PostCopy:
                return &SymbolStruct::opPostCopy;
            case CodeGenLifecycleKind::PostMove:
                return &SymbolStruct::opPostMove;
        }

        SWC_UNREACHABLE();
    }

    const SymbolFunction* resolveDirectLifecycleFunction(const TypeInfo& typeInfo, const CodeGenLifecycleKind lifecycleKind)
    {
        if (!typeInfo.isStruct())
            return nullptr;

        return (typeInfo.payloadSymStruct().*lifecycleOperator(lifecycleKind))();
    }

    const SymbolFunction* resolveEffectiveLifecycleFunction(const CodeGen& codeGen, const TypeInfo& typeInfo, const CodeGenLifecycleKind lifecycleKind)
    {
        if (!typeInfo.isStruct())
            return nullptr;

        const auto& ctx = codeGen.ctx();
        switch (lifecycleKind)
        {
            case CodeGenLifecycleKind::Drop:
                return typeInfo.payloadSymStruct().effectiveOpDrop(ctx);
            case CodeGenLifecycleKind::PostCopy:
                return typeInfo.payloadSymStruct().effectiveOpPostCopy(ctx);
            case CodeGenLifecycleKind::PostMove:
                return typeInfo.payloadSymStruct().effectiveOpPostMove(ctx);
        }

        return nullptr;
    }

    bool tryBuildLifecycleActionRec(const CodeGen& codeGen, TypeRef typeRef, const CodeGen::LifecycleKind lifecycleKind, const SymbolFunction*& outFunction, uint32_t& outSizeOf, uint32_t& outCount)
    {
        outFunction = nullptr;
        outSizeOf   = 0;
        outCount    = 0;

        if (!typeRef.isValid())
            return false;

        const TypeInfo& originalType = codeGen.typeMgr().get(typeRef);
        const TypeInfo& typeInfo     = originalType.unwrapAliasTypeOrSelf(codeGen.ctx());
        if (typeInfo.isArray())
        {
            const uint64_t multiplier = typeInfo.arrayTotalElementCount();
            if (!multiplier)
                return false;

            const SymbolFunction* elemFunction = nullptr;
            uint32_t              elemSizeOf   = 0;
            uint32_t              elemCount    = 0;
            if (!tryBuildLifecycleActionRec(codeGen, typeInfo.payloadArrayElemTypeRef(), lifecycleKind, elemFunction, elemSizeOf, elemCount))
                return false;

            const uint64_t totalCount = multiplier * elemCount;
            SWC_ASSERT(totalCount > 0);
            SWC_ASSERT(totalCount <= std::numeric_limits<uint32_t>::max());

            outFunction = elemFunction;
            outSizeOf   = elemSizeOf;
            outCount    = static_cast<uint32_t>(totalCount);
            return true;
        }

        if (!typeInfo.isStruct())
            return false;

        const SymbolFunction* lifecycleFunction = resolveEffectiveLifecycleFunction(codeGen, typeInfo, lifecycleKind);
        if (!lifecycleFunction)
            return false;

        auto&          mutableCtx = const_cast<TaskContext&>(codeGen.ctx());
        const uint64_t sizeOf     = typeInfo.sizeOf(mutableCtx);
        SWC_ASSERT(sizeOf > 0 && sizeOf <= std::numeric_limits<uint32_t>::max());

        outFunction = lifecycleFunction;
        outSizeOf   = static_cast<uint32_t>(sizeOf);
        outCount    = 1;
        return true;
    }

    // Only the member selected by the tag holds a live value: dispatch on the tag, and leave the
    // inactive storage alone.
    Result emitTaggedUnionLifecycle(CodeGen& codeGen, const SymbolStruct& tagged, const SymbolFunction* directLifecycle, const CodeGenLifecycleKind lifecycleKind, const MicroReg addressReg)
    {
        if (lifecycleKind == CodeGenLifecycleKind::Drop && directLifecycle)
            SWC_RESULT(codeGen.emitLifecycleAction(*directLifecycle, addressReg));

        MicroBuilder&  builder = codeGen.builder();
        const MicroReg tagReg  = CodeGenTaggedHelpers::loadTagAt(codeGen, addressReg, tagged);
        for (const SymbolStructTaggedCase& taggedCase : tagged.taggedCases())
        {
            if (!codeGen.hasLifecycle(taggedCase.member->typeRef(), lifecycleKind))
                continue;

            const MicroLabelRef activeLabel = builder.createLabel();
            const MicroLabelRef nextLabel   = builder.createLabel();
            CodeGenTaggedHelpers::emitJumpIfCase(codeGen, tagReg, tagged, taggedCase.values, activeLabel);
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, nextLabel);
            builder.placeLabel(activeLabel);

            const MicroReg memberAddressReg = codeGen.offsetAddressReg(addressReg, taggedCase.member->offset());
            SWC_RESULT(codeGen.emitLifecycle(taggedCase.member->typeRef(), lifecycleKind, memberAddressReg));
            builder.placeLabel(nextLabel);
        }

        if (lifecycleKind != CodeGenLifecycleKind::Drop && directLifecycle)
            SWC_RESULT(codeGen.emitLifecycleAction(*directLifecycle, addressReg));

        return Result::Continue;
    }

    Result emitLifecycleRec(CodeGen& codeGen, TypeRef typeRef, const CodeGenLifecycleKind lifecycleKind, const MicroReg addressReg)
    {
        typeRef = normalizeLifecycleTypeRef(codeGen, typeRef);
        if (!typeRef.isValid())
            return Result::Continue;

        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        if (typeInfo.isArray())
        {
            const uint64_t totalCount = typeInfo.arrayTotalElementCount();
            if (!totalCount)
                return Result::Continue;

            SWC_ASSERT(totalCount <= std::numeric_limits<uint32_t>::max());
            return codeGen.emitLifecycle(typeInfo.payloadArrayElemTypeRef(), lifecycleKind, addressReg, static_cast<uint32_t>(totalCount));
        }

        if (typeInfo.isAggregate())
        {
            const size_t fieldCount = typeInfo.payloadAggregate().types.size();
            if (!fieldCount)
                return Result::Continue;

            SmallVector<CodeGenStructHelpers::StructLikeFieldLayout, 4> fields;
            fields.reserve(fieldCount);

            CodeGenStructHelpers::StructLikeFieldLayoutCursor cursor;
            for (size_t i = 0; i < fieldCount; ++i)
                fields.push_back(CodeGenStructHelpers::structLikeFieldLayout(codeGen, cursor, typeInfo, i));

            const auto emitFieldLifecycle = [&](const CodeGenStructHelpers::StructLikeFieldLayout& field) {
                if (!codeGen.hasLifecycle(field.typeRef, lifecycleKind))
                    return Result::Continue;

                const MicroReg fieldAddressReg = field.offset ? codeGen.offsetAddressReg(addressReg, field.offset) : addressReg;
                return codeGen.emitLifecycle(field.typeRef, lifecycleKind, fieldAddressReg);
            };

            if (lifecycleKind == CodeGenLifecycleKind::Drop)
            {
                for (size_t i = fields.size(); i != 0; --i)
                    SWC_RESULT(emitFieldLifecycle(fields[i - 1]));
            }
            else
            {
                for (const auto& field : fields)
                    SWC_RESULT(emitFieldLifecycle(field));
            }

            return Result::Continue;
        }

        if (!typeInfo.isStruct())
            return Result::Continue;

        const SymbolFunction* effectiveLifecycle = resolveEffectiveLifecycleFunction(codeGen, typeInfo, lifecycleKind);
        if (effectiveLifecycle && effectiveLifecycle->isSemaCompleted() && effectiveLifecycle->isForeign() &&
            effectiveLifecycle->attributes().hasRtFlag(RtAttributeFlagsE::Implicit) &&
            typeInfo.payloadSymStruct().attributes().hasRtFlag(RtAttributeFlagsE::Opaque))
        {
            // An imported complete wrapper already includes the hidden fields.
            return codeGen.emitLifecycleAction(*effectiveLifecycle, addressReg);
        }

        const SymbolFunction* directLifecycle = resolveDirectLifecycleFunction(typeInfo, lifecycleKind);
        const auto&           fields          = typeInfo.payloadSymStruct().fields();

        if (typeInfo.payloadSymStruct().isTagged())
            return emitTaggedUnionLifecycle(codeGen, typeInfo.payloadSymStruct(), directLifecycle, lifecycleKind, addressReg);

        // Drop must see live fields; post-copy/move run after field state is repaired.
        if (lifecycleKind == CodeGenLifecycleKind::Drop && directLifecycle)
            SWC_RESULT(codeGen.emitLifecycleAction(*directLifecycle, addressReg));

        if (lifecycleKind == CodeGenLifecycleKind::Drop)
        {
            for (size_t i = fields.size(); i != 0; --i)
            {
                const SymbolVariable* field = fields[i - 1];
                if (!field || !codeGen.hasLifecycle(field->typeRef(), lifecycleKind))
                    continue;

                const MicroReg fieldAddressReg = field->offset() ? codeGen.offsetAddressReg(addressReg, field->offset()) : addressReg;
                SWC_RESULT(codeGen.emitLifecycle(field->typeRef(), lifecycleKind, fieldAddressReg));
            }
        }
        else
        {
            for (const SymbolVariable* field : fields)
            {
                if (!field || !codeGen.hasLifecycle(field->typeRef(), lifecycleKind))
                    continue;

                const MicroReg fieldAddressReg = field->offset() ? codeGen.offsetAddressReg(addressReg, field->offset()) : addressReg;
                SWC_RESULT(codeGen.emitLifecycle(field->typeRef(), lifecycleKind, fieldAddressReg));
            }

            if (directLifecycle)
                SWC_RESULT(codeGen.emitLifecycleAction(*directLifecycle, addressReg));
        }

        return Result::Continue;
    }

    bool functionHasImplicitDrops(const CodeGen& codeGen, const SymbolFunction& symbolFunc)
    {
        for (const SymbolVariable* symVar : symbolFunc.parameters())
        {
            if (symVar &&
                symVar->hasExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage) &&
                codeGen.hasLifecycle(symVar->typeRef(), CodeGen::LifecycleKind::Drop))
                return true;
        }

        for (const SymbolVariable* symVar : symbolFunc.localVariables())
        {
            if (symVar && codeGen.hasLifecycle(symVar->typeRef(), CodeGen::LifecycleKind::Drop))
                return true;
        }

        return false;
    }

    bool resolveDeferredVariableAddress(CodeGen& codeGen, const SymbolVariable& symVar, CodeGenNodePayload& outPayload)
    {
        if (symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) && codeGen.localStackBaseReg().isValid())
        {
            outPayload = codeGen.resolveLocalStackPayload(symVar, false);
            return outPayload.isAddress();
        }

        // A local built in the return storage is released where it lives.
        if (CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, symVar))
        {
            outPayload = CodeGenFunctionHelpers::resolveCallerReturnStoragePayload(codeGen, symVar);
            return outPayload.isAddress();
        }

        if (const CodeGenNodePayload* variablePayload = codeGen.variablePayload(symVar))
        {
            outPayload = *variablePayload;
            return outPayload.isAddress();
        }

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        {
            outPayload = CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, codeGen.function(), symVar);
            return outPayload.isAddress();
        }

        return false;
    }
}

void CodeGenFrame::setCurrentBreakContent(AstNodeRef nodeRef, BreakContextKind kind)
{
    breakable_.nodeRef = nodeRef;
    breakable_.kind    = kind;

    if (kind == BreakContextKind::Loop || kind == BreakContextKind::None)
    {
        continuable_.nodeRef        = nodeRef;
        continuable_.kind           = kind;
        currentLoopHasContinueJump_ = false;
    }
}

void CodeGenFrame::setCurrentInlineContext(AstNodeRef rootNodeRef, const SemaInlinePayload* payload, MicroLabelRef doneLabel)
{
    inlineContext_             = {};
    inlineContext_.rootNodeRef = rootNodeRef;
    inlineContext_.payload     = payload;
    inlineContext_.doneLabel   = doneLabel;
    inlineBoundaryRootRef_     = rootNodeRef;
}

CodeGen::CodeGen(Sema& sema) :
    sema_(&sema)
{
    setVisitors();
}

Result CodeGen::exec(SymbolFunction& symbolFunc, AstNodeRef root)
{
    if (completed_)
        return Result::Continue;

    if (!started_)
    {
        // Initialize per-function state once. A paused visitor resumes with its
        // saved cursor and the same function/root pair.
        root_     = root;
        function_ = &symbolFunc;
        builder_  = &symbolFunc.microInstrBuilder(ctx());
        visit_.start(ast(), root);

        nextVirtualRegister_ = 1;
        localStackFrameSize_ = 0;
        localStackBaseReg_   = MicroReg::invalid();
        vectorZeroReg_       = MicroReg::invalid();
        bodyEntryRef_        = MicroInstrRef::invalid();

        currentFunctionIndirectReturnStackOffset_ = 0xFFFFFFFFu;
        currentFunctionIndirectReturnReg_         = MicroReg::invalid();
        currentFunctionClosureContextReg_         = MicroReg::invalid();

        deferScopes_.clear();
        deferredEmissionCursors_.clear();
        deferredEmitDepth_                = 0;
        currentDeferredAddressGeneration_ = 0;
        nextDeferredAddressGeneration_    = 1;

        // The drop test reads the function's variables; the other one walks its whole body.
        hasDeferredStatements_ = (symbolFunc.attributes().effectiveRuntimeSafetyMask(buildCfg().safetyGuards) & static_cast<uint16_t>(Runtime::SafetyWhat::ValueBorrow)) || functionHasImplicitDrops(*this, symbolFunc) || containsDeferredActions(root);

        variablePayloads_ = {};
        variablePayloadChunks_.clear();
        variablePayloadCount_ = 0;

        moveElisionVars_.clear();
        elidedImplicitDrops_.clear();
        returnStorageLocals_.clear();
        returnStorageLocalContexts_.clear();
        replacingReturns_.clear();
        demotedReturnStorages_.clear();
        returnReplacedLocal_ = nullptr;
        temporaryDrops_.clear();
        returnMoveOutVar_    = nullptr;
        moveElisionAnalyzed_ = false;

        clearGlobalsToDropScratchLayout();

        frames_.clear();
        frames_.emplace_back();

        symbolFunc.setDebugStackFrameSize(0);
        symbolFunc.setDebugStackBaseReg(MicroReg::invalid());

        for (SymbolVariable* symVar : symbolFunc.parameters())
        {
            SWC_ASSERT(symVar != nullptr);
            symVar->removeExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack);
            symVar->setCodeGenLocalSize(0);
            symVar->setDebugStackSlotOffset(0);
            symVar->setDebugStackSlotSize(0);
        }

        for (SymbolVariable* symVar : symbolFunc.localVariables())
        {
            SWC_ASSERT(symVar != nullptr);
            symVar->removeExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack);
        }

        MicroBuilderFlags        builderFlags     = MicroBuilderFlagsE::Zero;
        const AttributeList&     attributes       = symbolFunc.attributes();
        const Runtime::BuildCfg& compilerBuildCfg = buildCfg();
        Runtime::BuildCfgBackend backendBuildCfg  = compilerBuildCfg.backend;

        // A per-function Optimize(false) disables optimization. Optimize(true)
        // enables it without lowering the level already requested by the build.
        if (attributes.backendOptimize.has_value())
        {
            if (!attributes.backendOptimize.value())
                backendBuildCfg.optimLevel = Runtime::BuildCfgBackendOptimLevel::O0;
            else if (!backendBuildCfg.optimizes())
                backendBuildCfg.optimLevel = Runtime::BuildCfgBackendOptimLevel::O1;
        }

        builder_->setBackendBuildCfg(backendBuildCfg);
        builder_->setFlags(builderFlags);
        builder_->setCurrentDebugSourceCodeRef(SourceCodeRef::invalid());
        builder_->setCurrentDebugNoStep(false);

        const auto& requests = ctx().cmdLine().printMicro;
        if (requests.empty())
            builder_->setPrintPassOptions(symbolFunc.attributes().printMicroPassOptions);
        else
        {
            std::vector<Utf8> stages = symbolFunc.attributes().printMicroPassOptions;
            appendCommandLinePrintMicroStages(stages, requests, symbolFunc.getFullScopedName(ctx()).view());
            builder_->setPrintPassOptions(stages);
        }

        builder_->setPrintSymbol(&symbolFunc);

        started_ = true;
    }
    else
    {
        // A resumed codegen job must be the same logical job. Reusing the object for a
        // different function would mix virtual register numbering, payloads and defer state.
        SWC_ASSERT(function_ == &symbolFunc);
        SWC_ASSERT(root_ == root);
    }

    TypeRef sourceLocTypeRef = TypeRef::invalid();
    SWC_RESULT(sema().waitPredefined(IdentifierManager::PredefinedName::SourceCodeLocation, sourceLocTypeRef, symbolFunc.codeRef()));

    while (true)
    {
        const AstNodeRef currentNodeRef = visit_.currentNodeRef();
        TaskState&       taskState      = ctx().state();
        if (taskState.kind != TaskStateKind::CodeGenParsing || taskState.codeGenFunction != &symbolFunc || taskState.nodeRef != currentNodeRef)
        {
            const AstNode*      currentNode    = visit_.currentNode();
            const SourceCodeRef currentCodeRef = currentNode ? currentNode->codeRef() : node(currentNodeRef).codeRef();
            taskState.setCodeGenParsing(&symbolFunc, currentNodeRef, currentCodeRef);
        }

        // The visitor drives all node-specific emission. The outer loop only preserves
        // resumability: a Pause keeps the partially built microcode and visitor cursor.
        const AstVisitResult result = visit_.step(ctx());
        if (result == AstVisitResult::Pause)
            return Result::Pause;
        if (result == AstVisitResult::Error)
        {
            completed_ = true;
            return Result::Error;
        }

        if (result == AstVisitResult::Stop)
        {
            completed_ = true;
            return Result::Continue;
        }
    }
}

TaskContext& CodeGen::ctx()
{
    return sema().ctx();
}

const TaskContext& CodeGen::ctx() const
{
    return sema().ctx();
}

CompilerInstance& CodeGen::compiler()
{
    return sema().compiler();
}

const CompilerInstance& CodeGen::compiler() const
{
    return sema().compiler();
}

const Runtime::BuildCfg& CodeGen::buildCfg() const
{
    return compiler().buildCfg();
}

ConstantManager& CodeGen::cstMgr()
{
    return sema().cstMgr();
}

const ConstantManager& CodeGen::cstMgr() const
{
    return sema().cstMgr();
}

TypeManager& CodeGen::typeMgr()
{
    return sema().typeMgr();
}

const TypeManager& CodeGen::typeMgr() const
{
    return sema().typeMgr();
}

TypeGen& CodeGen::typeGen()
{
    return sema().typeGen();
}

const TypeGen& CodeGen::typeGen() const
{
    return sema().typeGen();
}

IdentifierManager& CodeGen::idMgr()
{
    return sema().idMgr();
}

const IdentifierManager& CodeGen::idMgr() const
{
    return sema().idMgr();
}

Ast& CodeGen::ast()
{
    return sema().ast();
}

const Ast& CodeGen::ast() const
{
    return sema().ast();
}

SourceView& CodeGen::srcView(SourceViewRef srcViewRef)
{
    return sema().srcView(srcViewRef);
}

const SourceView& CodeGen::srcView(SourceViewRef srcViewRef) const
{
    return sema().srcView(srcViewRef);
}

const Token& CodeGen::token(const SourceCodeRef& codeRef) const
{
    return sema().token(codeRef);
}

void CodeGen::appendResolvedCallArguments(AstNodeRef nodeRef, SmallVector<ResolvedCallArgument>& out) const
{
    sema().appendResolvedCallArguments(nodeRef, out);
}

TypeRef CodeGen::transparentPayloadTypeRef()
{
    if (resolvedNodeRef(curNodeRef()) != curNodeRef())
    {
        const TypeRef storedTypeRef = sema().viewStored(curNodeRef(), SemaNodeViewPartE::Type).typeRef();
        if (storedTypeRef.isValid())
            return storedTypeRef;
    }

    return curViewType().typeRef();
}

const CodeGenLoweringPayload* CodeGen::loweringPayload(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return nullptr;

    return sema().loweringPayload<CodeGenLoweringPayload>(nodeRef);
}

const SymbolVariable* CodeGen::runtimeStorageSymbol(AstNodeRef nodeRef) const
{
    const auto* exactPayload = loweringPayload(nodeRef);
    if (exactPayload && exactPayload->runtimeStorageSym != nullptr)
        return exactPayload->runtimeStorageSym;

    const AstNodeRef resolvedRef = resolvedNodeRef(nodeRef);
    if (resolvedRef.isInvalid())
        return nullptr;
    if (resolvedRef != nodeRef)
    {
        const auto* resolvedPayload = loweringPayload(resolvedRef);
        if (resolvedPayload && resolvedPayload->runtimeStorageSym != nullptr)
            return resolvedPayload->runtimeStorageSym;
    }

    const auto* payload = static_cast<const CodeGenNodePayload*>(nodePayloads_.find(resolvedRef));
    if (payload && payload->runtimeStorageSym != nullptr)
        return payload->runtimeStorageSym;

    return nullptr;
}

void CodeGen::mergeLoweringNodePayloadMetadata(CodeGenNodePayload& payload, AstNodeRef nodeRef, AstNodeRef resolvedRef) const
{
    if (resolvedRef.isInvalid())
        return;

    if (const auto* resolvedPayload = loweringPayload(resolvedRef))
        mergeNodeLoweringMetadata(payload, *resolvedPayload);

    if (resolvedRef == nodeRef)
        return;

    if (const auto* originalPayload = loweringPayload(nodeRef))
        mergeNodeLoweringMetadata(payload, *originalPayload);
}

CodeGenNodePayload& CodeGen::payload(AstNodeRef nodeRef)
{
    const AstNodeRef    queryNodeRef = nodeRef;
    const AstNodeRef    resolvedRef  = resolvedNodeRef(nodeRef);
    CodeGenNodePayload* nodePayload  = safePayload(nodeRef, resolvedRef);

    // A void inline expansion can have side effects without a result register.
    // Re-emit only missing payloads or values still owed, never an already emitted void.
    const bool emittedWithoutValue = nodePayload && nodePayload->typeRef.isValid() && nodePayload->typeRef == typeMgr().typeVoid();
    if (!emittedWithoutValue && (!nodePayload || !nodePayload->reg.isValid()) && nodeRef.isValid() && resolvedRef != curNodeRef())
    {
        // Skipped substituted children materialize when a parent consumes their value.
        const Result materializeResult = emitNodeNow(nodeRef);
        SWC_ASSERT(materializeResult != Result::Pause);
        if (materializeResult == Result::Continue)
            nodePayload = safePayload(nodeRef);
    }

#if SWC_DEV_MODE
    if (!nodePayload)
    {
        const Utf8 detail = formatMissingPayloadDebug(*this, queryNodeRef, resolvedNodeRef(queryNodeRef), nodePayload);
        swcAssertDetail("nodePayload != nullptr", __FILE__, __LINE__, detail.view());
    }
#endif
    SWC_ASSERT(nodePayload != nullptr);
    return *nodePayload;
}

// A folded call retains its stored constant when a cast substitutes the node.
// Re-emitting it would borrow the conversion's storage: sema allocated no call
// result slot, so the runtime result would overwrite the conversion's own value.
bool CodeGen::keepsFoldedConstant(AstNodeRef nodeRef)
{
    if (nodeRef.isInvalid() || resolvedNodeRef(nodeRef) == nodeRef)
        return false;
    if (!sema().isFoldedTypedConstStored(nodeRef))
        return false;

    return sema().viewStored(nodeRef, SemaNodeViewPartE::Constant).hasConstant();
}

CodeGenNodePayload* CodeGen::safePayload(AstNodeRef nodeRef)
{
    return safePayload(nodeRef, resolvedNodeRef(nodeRef));
}

CodeGenNodePayload* CodeGen::safePayload(AstNodeRef nodeRef, const AstNodeRef resolvedRef)
{
    if (resolvedRef.isInvalid())
        return nullptr;

    auto* payload = static_cast<CodeGenNodePayload*>(nodePayloads_.find(resolvedRef));
    if (!payload)
    {
        const bool hasPayload = loweringPayload(resolvedRef) != nullptr || (resolvedRef != nodeRef && loweringPayload(nodeRef) != nullptr);
        if (!hasPayload)
            return nullptr;

        // A newly allocated payload already receives its lowering metadata.
        return &ensureNodePayload<CodeGenNodePayload>(nodeRef);
    }

    mergeLoweringNodePayloadMetadata(*payload, nodeRef, resolvedRef);
    return payload;
}

CodeGen::VariablePayloadState& CodeGen::ensureVariablePayloadState(const SymbolVariable& sym)
{
    if (VariablePayloadState* state = variablePayloads_.find(&sym))
        return *state;

    const uint32_t slot = variablePayloadCount_ % K_VARIABLE_PAYLOAD_CHUNK;
    if (!slot)
        variablePayloadChunks_.push_back(std::make_unique<VariablePayloadState[]>(K_VARIABLE_PAYLOAD_CHUNK));
    ++variablePayloadCount_;

    VariablePayloadState& state = variablePayloadChunks_.back()[slot];
    state                       = {};
    variablePayloads_.set(&sym, &state);
    return state;
}

void CodeGen::setVariablePayload(const SymbolVariable& sym, const CodeGenNodePayload& payload)
{
    if (sym.hasGlobalStorage())
        return;

    const bool isStackAddress = isStackAddressPayload(*this, sym, payload);
    if (inDeferredEmission() && isStackAddress)
        return;

    VariablePayloadState& symbolPayload = ensureVariablePayloadState(sym);
    symbolPayload.payload               = payload;
    symbolPayload.hasPayload            = true;
    symbolPayload.addressGeneration     = isStackAddress ? currentDeferredAddressGeneration_ : 0;
}

const CodeGenNodePayload* CodeGen::variablePayload(const SymbolVariable& sym) const
{
    if (sym.hasGlobalStorage())
        return nullptr;

    const VariablePayloadState* state = variablePayloads_.find(&sym);
    if (!state || !state->hasPayload)
        return nullptr;

    const VariablePayloadState& symbolPayload = *state;
    if (isStackAddressPayload(*this, sym, symbolPayload.payload) &&
        symbolPayload.addressGeneration != currentDeferredAddressGeneration_)
        return nullptr;

    return &symbolPayload.payload;
}

CodeGenNodePayload& CodeGen::inheritPayload(AstNodeRef dstNodeRef, AstNodeRef srcNodeRef, TypeRef typeRef)
{
    CodeGenNodePayload srcPayloadCopy;
    if (resolvedNodeRef(srcNodeRef) == resolvedNodeRef(dstNodeRef))
    {
        const auto* originalPayload = safeNodePayload<CodeGenNodePayload>(srcNodeRef);
        if (originalPayload && originalPayload->reg.isValid())
            srcPayloadCopy = *originalPayload;
        else
            srcPayloadCopy = payload(srcNodeRef);
    }
    else
    {
        srcPayloadCopy = payload(srcNodeRef);
    }

    if (typeRef.isInvalid())
        typeRef = srcPayloadCopy.typeRef;

    CodeGenNodePayload& dstPayload = setPayload(dstNodeRef, typeRef);
    dstPayload.reg                 = srcPayloadCopy.reg;
    if (srcPayloadCopy.sourceCodeRef.isValid())
        dstPayload.sourceCodeRef = srcPayloadCopy.sourceCodeRef;
    dstPayload.storageKind = srcPayloadCopy.storageKind;
    if (srcPayloadCopy.hasMaterializedPointerLikeValue())
        dstPayload.markMaterializedPointerLikeValue();

    mergeNodePayloadMetadata(dstPayload, srcPayloadCopy);
    return dstPayload;
}

CodeGenNodePayload& CodeGen::setPayload(AstNodeRef nodeRef, TypeRef typeRef)
{
    // Transparent substitutes store the original value in the substitute's payload
    // slot. Keep the node's stored type so consumers use the real operand width;
    // a context bool type must not make a 64-bit pointer read as one byte.
    const AstNodeRef resolvedRef = resolvedNodeRef(nodeRef);
    const AstNode&   payloadNode = node(nodeRef);
    if (resolvedRef.isValid() && resolvedRef != nodeRef && typeRef.isValid() && typeRef == viewType(nodeRef).typeRef())
    {
        // Cast-like nodes already convert to the resolved context type, so their
        // register really does hold a value of that type.
        if (payloadNode.isNot(AstNodeId::CastExpr) &&
            payloadNode.isNot(AstNodeId::AutoCastExpr) &&
            payloadNode.isNot(AstNodeId::AsCastExpr) &&
            payloadNode.isNot(AstNodeId::IsTypeExpr))
        {
            const TypeRef storedTypeRef = sema().viewStored(nodeRef, SemaNodeViewPartE::Type).typeRef();
            if (storedTypeRef.isValid())
                typeRef = storedTypeRef;
        }
    }

    CodeGenNodePayload& nodePayload = ensureNodePayload<CodeGenNodePayload>(nodeRef);

    nodePayload.reg           = nextVirtualIntRegister();
    nodePayload.sourceCodeRef = payloadNode.codeRef();
    if (const auto* memberAccess = payloadNode.safeCast<AstMemberAccessExpr>())
    {
        const CodeGenNodePayload* leftPayload = safePayload(memberAccess->nodeLeftRef);
        if (leftPayload && leftPayload->sourceCodeRef.isValid())
            nodePayload.sourceCodeRef = leftPayload->sourceCodeRef;
    }

    nodePayload.typeRef     = typeRef;
    nodePayload.storageKind = CodeGenNodePayload::StorageKind::Value;
    nodePayload.clearMaterializedPointerLikeValue();
    mergeLoweringNodePayloadMetadata(nodePayload, nodeRef, resolvedRef);
    return nodePayload;
}

CodeGenNodePayload& CodeGen::setPayloadValue(AstNodeRef nodeRef, TypeRef typeRef)
{
    CodeGenNodePayload& nodePayload = setPayload(nodeRef, typeRef);
    nodePayload.setIsValue();
    return nodePayload;
}

CodeGenNodePayload& CodeGen::setPayloadAddress(AstNodeRef nodeRef, TypeRef typeRef)
{
    CodeGenNodePayload& nodePayload = setPayload(nodeRef, typeRef);
    nodePayload.setIsAddress();
    return nodePayload;
}

CodeGenNodePayload& CodeGen::setPayloadAddressReg(AstNodeRef nodeRef, const MicroReg reg, TypeRef typeRef)
{
    SWC_ASSERT(reg.isValid());
    CodeGenNodePayload& nodePayload = setPayloadAddress(nodeRef, typeRef);
    nodePayload.reg                 = reg;
    return nodePayload;
}

MicroReg CodeGen::offsetAddressReg(const MicroReg baseReg, const uint32_t offset, const bool forbidBaseReg)
{
    SWC_ASSERT(baseReg.isValid());
    if (!offset)
        return baseReg;

    const MicroReg addressReg = nextVirtualIntRegister();
    if (forbidBaseReg && baseReg.isInt())
        builder().addVirtualRegForbiddenPhysReg(addressReg, baseReg);

    builder().emitLoadRegReg(addressReg, baseReg, MicroOpBits::B64);
    builder().emitOpBinaryRegImm(addressReg, ApInt(offset, 64), MicroOp::Add, MicroOpBits::B64);
    return addressReg;
}

// Define one zero vector at body entry for unsigned widening. The definition
// dominates every use, and the allocator can rematerialize it instead of spilling.
// Place it after the prologue and parameter copies so stack adjustments remain
// mergeable and incoming arguments are read before their registers are reused.
MicroReg CodeGen::vectorZeroRegister()
{
    if (vectorZeroReg_.isValid())
        return vectorZeroReg_;

    vectorZeroReg_ = nextVirtualFloatRegister();

    MicroStorage&       instrs    = builder().instructions();
    const MicroInstrRef beforeRef = instrs.findNextInstructionRef(bodyEntryRef_);
    if (!beforeRef.isValid())
    {
        builder().emitClearReg(vectorZeroReg_, MicroOpBits::B128);
        return vectorZeroReg_;
    }

    std::array<MicroInstrOperand, 2> clearOps;
    clearOps[0].reg    = vectorZeroReg_;
    clearOps[1].opBits = MicroOpBits::B128;
    instrs.insertSyntheticBefore(builder().operands(), beforeRef, MicroInstrOpcode::ClearReg, clearOps);
    return vectorZeroReg_;
}

CodeGenNodePayload CodeGen::resolveLocalStackPayload(const SymbolVariable& sym, const bool cache)
{
    if (cache)
    {
        if (const CodeGenNodePayload* symbolPayload = variablePayload(sym))
            return *symbolPayload;
    }

    SWC_ASSERT(localStackBaseReg().isValid());

    CodeGenNodePayload localPayload;
    localPayload.typeRef = sym.typeRef();
    localPayload.setIsAddress();
    localPayload.reg = offsetAddressReg(localStackBaseReg(), sym.offset());
    if (cache)
        setVariablePayload(sym, localPayload);

    return localPayload;
}

MicroReg CodeGen::ensureCurrentFunctionIndirectReturnReg(const CallConvKind callConvKind)
{
    if (currentFunctionIndirectReturnReg_.isValid())
        return currentFunctionIndirectReturnReg_;

    // The hidden return pointer arrives via a prologue spill or the first integer
    // argument register. Use a stable virtual copy that later calls cannot clobber.
    if (hasCurrentFunctionIndirectReturnStackOffset() && localStackBaseReg().isValid())
    {
        MicroBuilder&           builder = this->builder();
        const ScopedDebugNoStep noStep(builder, true);
        const MicroReg          outputStorageReg = nextVirtualIntRegister();
        builder.emitLoadRegMem(outputStorageReg, localStackBaseReg(), currentFunctionIndirectReturnStackOffset(), MicroOpBits::B64);
        return outputStorageReg;
    }

    const CallConv& callConv = CallConv::get(callConvKind);
    SWC_ASSERT(!callConv.intArgRegs.empty());

    MicroBuilder&           builder = this->builder();
    const ScopedDebugNoStep noStep(builder, true);
    const MicroReg          outputStorageReg = nextVirtualIntRegister();
    builder.emitLoadRegReg(outputStorageReg, callConv.intArgRegs[0], MicroOpBits::B64);
    builder.preserveVirtualCopy(outputStorageReg);
    currentFunctionIndirectReturnReg_ = outputStorageReg;
    return outputStorageReg;
}

MicroReg CodeGen::runtimeStorageAddressReg(AstNodeRef nodeRef)
{
    const SymbolVariable* storageSym = runtimeStorageSymbol(nodeRef);
    SWC_ASSERT(storageSym != nullptr);
    if (CodeGenFunctionHelpers::usesCallerReturnStorage(*this, *storageSym))
        return ensureCurrentFunctionIndirectReturnReg(function().callConvKind());

    // Inline result temporaries have no declaration. Recompute their address:
    // a return in one branch cannot supply a definition dominating other branches.
    const bool               isInlineResult = frame().hasCurrentInlineContext() && frame().currentInlineContext().payload->resultVar == storageSym;
    const CodeGenNodePayload storagePayload = resolveLocalStackPayload(*storageSym, !inDeferredEmission() && !isInlineResult);
    SWC_ASSERT(storagePayload.isAddress());
    return storagePayload.reg;
}

bool CodeGen::tryBuildLifecycleAction(const TypeRef typeRef, const LifecycleKind lifecycleKind, const SymbolFunction*& outFunction, uint32_t& outSizeOf, uint32_t& outCount) const
{
    return tryBuildLifecycleActionRec(*this, typeRef, lifecycleKind, outFunction, outSizeOf, outCount);
}

bool CodeGen::hasLifecycle(const TypeRef typeRef, const LifecycleKind lifecycleKind) const
{
    return typeMgr().hasLifecycleOperator(ctx(), typeRef, lifecycleOperator(lifecycleKind));
}

Result CodeGen::emitLifecycleAction(const SymbolFunction& calledFunction, const MicroReg addressReg)
{
    SWC_ASSERT(addressReg.isValid());

    MicroReg stableAddressReg = addressReg;
    if (addressReg.isValid())
    {
        stableAddressReg = nextVirtualIntRegister();
        if (addressReg.isInt())
            builder().addVirtualRegForbiddenPhysReg(stableAddressReg, addressReg);
        builder().emitLoadRegReg(stableAddressReg, addressReg, MicroOpBits::B64);
    }

    return CodeGenCallHelpers::emitRuntimeCallWithDirectArgs(*this, calledFunction, std::span<const MicroReg>{&stableAddressReg, 1});
}

Result CodeGen::emitLifecycle(const TypeRef typeRef, const LifecycleKind lifecycleKind, const MicroReg addressReg)
{
    if (hasLifecycle(typeRef, lifecycleKind))
        SWC_RESULT(CodeGenSafety::emitValueBorrowWrite(*this, addressReg, typeMgr().get(typeRef).sizeOf(ctx())));

    return emitLifecycleRec(*this, typeRef, lifecycleKind, addressReg);
}

void CodeGen::registerTemporaryDrop(AstNodeRef valueRef, TypeRef typeRef, const SymbolVariable& storage)
{
    if (hasTemporaryDrop(storage))
        return;

    const auto* valuePayload = safePayload(valueRef);
    const bool  ownsValue    = valuePayload && valuePayload->ownsValue;

    const auto isAncestorRef = [this](const AstNodeRef candidateRef) {
        for (size_t up = 0;; ++up)
        {
            const AstNodeRef parentRef = visit_.parentNodeRef(up);
            if (parentRef.isInvalid())
                return false;
            if (parentRef == candidateRef)
                return true;
        }
    };

    AstNodeRef               callerInlineRootRef = AstNodeRef::invalid();
    const SemaInlinePayload* lastExaminedPayload = nullptr;
    for (size_t i = frames_.size(); i != 0 && callerInlineRootRef.isInvalid(); --i)
    {
        const CodeGenFrame& candidateFrame = frames_[i - 1];
        if (!candidateFrame.hasCurrentInlineContext())
            continue;

        const SemaInlinePayload* inlinePayload = candidateFrame.currentInlineContext().payload;
        SWC_ASSERT(inlinePayload != nullptr);

        // Loop and switch frames inherit this payload. Rechecking it cannot change the
        // ancestor match while the visitor remains at the same node.
        if (inlinePayload == lastExaminedPayload || inlinePayload->materializedArgRefs.empty())
            continue;

        lastExaminedPayload = inlinePayload;

        for (const AstNodeRef materializedArgRef : inlinePayload->materializedArgRefs)
        {
            if (isAncestorRef(materializedArgRef))
            {
                callerInlineRootRef = inlinePayload->inlineRootRef;
                break;
            }
        }
    }

    AstNodeRef flushRootRef = valueRef;
    for (size_t up = 0;; ++up)
    {
        const AstNodeRef parentRef = visit_.parentNodeRef(up);
        if (parentRef.isInvalid())
            return;

        const AstNode& parent    = node(parentRef);
        const auto*    intrinsic = parent.safeCast<AstIntrinsicCallExpr>();
        if (intrinsic && intrinsic->intrinsicId == TokenId::IntrinsicAssert)
        {
            // The condition is always evaluated, but diagnostic arguments exist only on the
            // non-returning failure path. Never drop their storage at the successful join.
            const AstNodeRef conditionRef = ast().nthNode(intrinsic->spanChildrenRef, 0);
            if (resolvedNodeRef(flushRootRef) == resolvedNodeRef(conditionRef))
                break;

            return;
        }

        if (isLazyEvaluationNode(parent.id()))
        {
            if (!ownsValue)
                return;

            if (parent.is(AstNodeId::ConditionalExpr))
            {
                // Only owning conditionals flush inside the producing branch. A drop past
                // another conditional's join could destroy an unconstructed temporary.
                const auto* conditionalLowering = loweringPayload(parentRef);
                if (!conditionalLowering || !conditionalLowering->ownsValue)
                    return;

                flushRootRef = parentRef;
            }

            break;
        }

        // Inline argument temporaries belong to the caller expression. Cross the
        // clone root before choosing their enclosing statement boundary.
        if (callerInlineRootRef.isValid())
        {
            flushRootRef = parentRef;
            if (parentRef == callerInlineRootRef)
                callerInlineRootRef.setInvalid();

            continue;
        }

        if (isTemporaryDropEvaluationBoundary(parent, flushRootRef))
            break;

        if (isTemporaryDropBlock(parent.id()))
            break;

        flushRootRef = parentRef;
    }

    temporaryDrops_.push_back({flushRootRef, typeRef, &storage});
}

Result CodeGen::emitTemporaryDropsForFailure(AstNodeRef scopeRef)
{
    // Emit failure-edge cleanups without retiring success-edge cleanups. Nested
    // handlers leave earlier sibling operands intact. Every queued temporary is
    // initialized, including ordinary call results without an explicit owned move.
    for (size_t i = temporaryDrops_.size(); i != 0; --i)
    {
        const CodeGenTemporaryDrop drop = temporaryDrops_[i - 1];
        if (!drop.storageSym)
            continue;

        for (size_t up = 0;; ++up)
        {
            // The failure expression itself can own completed operand temporaries.
            const AstNodeRef parentRef = up ? visit_.parentNodeRef(up - 1) : curNodeRef();
            if (parentRef.isInvalid())
                break;
            if (parentRef == drop.flushRootRef)
            {
                const CodeGenNodePayload storage = resolveLocalStackPayload(*drop.storageSym, false);
                SWC_RESULT(emitLifecycle(drop.typeRef, LifecycleKind::Drop, storage.reg));
                break;
            }

            if (parentRef == scopeRef)
                break;
        }
    }

    return Result::Continue;
}

bool CodeGen::hasTemporaryDrop(const SymbolVariable& storage) const
{
    for (const CodeGenTemporaryDrop& drop : temporaryDrops_)
    {
        if (drop.storageSym == &storage)
            return true;
    }

    return false;
}

void CodeGen::cancelTemporaryDrop(const SymbolVariable& storage)
{
    for (CodeGenTemporaryDrop& drop : temporaryDrops_)
    {
        if (drop.storageSym == &storage)
        {
            drop.storageSym = nullptr;
            break;
        }
    }

    while (!temporaryDrops_.empty() && !temporaryDrops_.back().storageSym)
        temporaryDrops_.pop_back();
}

Result CodeGen::flushTemporaryDrops(const AstNodeRef rootRef)
{
    for (size_t i = temporaryDrops_.size(); i != 0; --i)
    {
        CodeGenTemporaryDrop& drop = temporaryDrops_[i - 1];
        if (drop.storageSym == nullptr || drop.flushRootRef != rootRef)
            continue;

        const SymbolVariable* storageSym = drop.storageSym;
        drop.storageSym                  = nullptr;

        const CodeGenNodePayload storagePayload = resolveLocalStackPayload(*storageSym, false);
        SWC_RESULT(emitLifecycle(drop.typeRef, LifecycleKind::Drop, storagePayload.reg));
    }

    // Retire the inactive suffix so later nodes do not scan dead temporary history.
    // Keep inner inactive entries until later temporaries finish, preserving order
    // without moving live entries.
    while (!temporaryDrops_.empty() && !temporaryDrops_.back().storageSym)
        temporaryDrops_.pop_back();

    return Result::Continue;
}

Result CodeGen::emitLifecycleAction(const SymbolFunction& calledFunction, const MicroReg addressReg, const uint32_t sizeOf, const uint32_t count)
{
    if (!count)
        return Result::Continue;

    if (count == 1)
        return emitLifecycleAction(calledFunction, addressReg);

    SWC_ASSERT(sizeOf != 0);

    const MicroReg cursorReg = nextVirtualIntRegister();
    builder().emitLoadRegReg(cursorReg, addressReg, MicroOpBits::B64);
    for (uint32_t i = 0; i < count; i++)
    {
        SWC_RESULT(emitLifecycleAction(calledFunction, cursorReg));
        if (i + 1 != count)
            builder().emitOpBinaryRegImm(cursorReg, ApInt(sizeOf, 64), MicroOp::Add, MicroOpBits::B64);
    }

    return Result::Continue;
}

Result CodeGen::emitLifecycle(const TypeRef typeRef, const LifecycleKind lifecycleKind, const MicroReg addressReg, const uint32_t count)
{
    if (!count)
        return Result::Continue;

    if (count == 1)
        return emitLifecycle(typeRef, lifecycleKind, addressReg);

    const TypeRef normalizedTypeRef = normalizeLifecycleTypeRef(*this, typeRef);
    SWC_ASSERT(normalizedTypeRef.isValid());
    if (normalizedTypeRef.isInvalid())
        return Result::Continue;

    auto&           mutableCtx = const_cast<TaskContext&>(ctx());
    const TypeInfo& typeInfo   = typeMgr().get(normalizedTypeRef);
    const uint64_t  sizeOf     = typeInfo.sizeOf(mutableCtx);
    SWC_ASSERT(sizeOf > 0 && sizeOf <= std::numeric_limits<uint32_t>::max());

    const MicroReg cursorReg = nextVirtualIntRegister();
    builder().emitLoadRegReg(cursorReg, addressReg, MicroOpBits::B64);
    for (uint32_t i = 0; i < count; i++)
    {
        SWC_RESULT(emitLifecycle(normalizedTypeRef, lifecycleKind, cursorReg));
        if (i + 1 != count)
            builder().emitOpBinaryRegImm(cursorReg, ApInt(sizeOf, 64), MicroOp::Add, MicroOpBits::B64);
    }

    return Result::Continue;
}

Result CodeGen::emitLifecycle(const TypeRef typeRef, const LifecycleKind lifecycleKind, const MicroReg addressReg, const MicroReg countReg)
{
    const TypeRef normalizedTypeRef = normalizeLifecycleTypeRef(*this, typeRef);
    SWC_ASSERT(normalizedTypeRef.isValid());
    if (normalizedTypeRef.isInvalid())
        return Result::Continue;

    auto&           mutableCtx = const_cast<TaskContext&>(ctx());
    const TypeInfo& typeInfo   = typeMgr().get(normalizedTypeRef);
    const uint64_t  sizeOf     = typeInfo.sizeOf(mutableCtx);
    SWC_ASSERT(sizeOf > 0 && sizeOf <= std::numeric_limits<uint32_t>::max());

    const CodeGenMemoryHelpers::ElementLoop loop = CodeGenMemoryHelpers::beginElementLoop(*this, addressReg, countReg);
    SWC_RESULT(emitLifecycle(normalizedTypeRef, lifecycleKind, loop.cursorReg));
    CodeGenMemoryHelpers::endElementLoop(*this, loop, sizeOf);
    return Result::Continue;
}

void CodeGen::pushDeferScope(AstNodeRef scopeRef, AstNodeRef breakOwnerRef, AstNodeRef switchCaseRef)
{
    if (!hasDeferredStatements_)
        return;

    // Store resolved anchors: later substitutions/inlining can change surface refs, but
    // defer emission needs to compare against the semantic owner of returns/breaks/cases.
    if (scopeRef.isValid())
        scopeRef = resolvedNodeRef(scopeRef);
    if (breakOwnerRef.isValid())
        breakOwnerRef = resolvedNodeRef(breakOwnerRef);
    if (switchCaseRef.isValid())
        switchCaseRef = resolvedNodeRef(switchCaseRef);

    auto& deferScope         = deferScopes_.emplace_back();
    deferScope.scopeRef      = scopeRef;
    deferScope.breakOwnerRef = breakOwnerRef;
    deferScope.switchCaseRef = switchCaseRef;
    deferScope.entryRef      = builder().instructions().lastInstructionRef();
}

CodeGenDeferScope& CodeGen::lifetimeDeferScope()
{
    // Borrow guards delimit argument evaluation, not the lifetime of a local
    // declared by that expression (for example, a named catch capture).
    for (size_t index = deferScopes_.size(); index != 0; --index)
    {
        if (!deferScopes_[index - 1].borrowOnly)
            return deferScopes_[index - 1];
    }

    SWC_ASSERT(!deferScopes_.empty());
    return deferScopes_.back();
}

void CodeGen::initializeLocalStorageAtScopeEntry(const SymbolVariable& symVar)
{
    SWC_ASSERT(!deferScopes_.empty());
    SWC_ASSERT(symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack));
    SWC_ASSERT(localStackBaseReg().isValid());

    // A catch capture can be in a short-circuited expression. Its enclosing scope still owns
    // cleanup, so the empty owner must exist even when that expression is never evaluated.
    MicroStorage&       instructions = builder().instructions();
    const MicroInstrRef beforeRef    = instructions.findNextInstructionRef(lifetimeDeferScope().entryRef);
    const uint32_t      sizeOf       = CodeGenFunctionHelpers::checkedTypeSizeInBytes(*this, typeMgr().get(symVar.typeRef()));

    for (uint32_t offset = 0; offset < sizeOf;)
    {
        const uint32_t    remaining = sizeOf - offset;
        const uint32_t    width     = remaining >= 8 ? 8 : remaining >= 4 ? 4
                                                       : remaining >= 2   ? 2
                                                                          : 1;
        const MicroOpBits bits      = microOpBitsFromBitWidth(width * 8);
        const uint64_t    address   = symVar.offset() + offset;
        if (beforeRef.isValid())
        {
            std::array<MicroInstrOperand, 4> ops;
            ops[0].reg      = localStackBaseReg();
            ops[1].opBits   = bits;
            ops[2].valueU64 = address;
            ops[3].setImmediateValue(ApInt(0, width * 8));
            instructions.insertSyntheticBefore(builder().operands(), beforeRef, MicroInstrOpcode::LoadMemImm, ops);
        }
        else
            builder().emitLoadMemImm(localStackBaseReg(), address, ApInt(0, width * 8), bits);

        offset += width;
    }
}

void CodeGen::registerDefer(const AstNodeRef deferStmtRef, const AstNodeRef bodyRef, const AstModifierFlags modifierFlags)
{
    if (!hasDeferredStatements_)
        return;

    SWC_ASSERT(!deferScopes_.empty());
    if (deferScopes_.empty())
        return;

    auto& action         = lifetimeDeferScope().actions.emplace_back();
    action.kind          = CodeGenDeferredAction::Kind::DeferStmt;
    action.deferStmtRef  = resolvedNodeRef(deferStmtRef);
    action.bodyRef       = resolvedNodeRef(bodyRef);
    action.modifierFlags = modifierFlags;
}

void CodeGen::registerValueBorrowEnd(uint32_t recordOffset)
{
    SWC_ASSERT(!deferScopes_.empty());

    auto& action              = deferScopes_.back().actions.emplace_back();
    action.kind               = CodeGenDeferredAction::Kind::EndValueBorrow;
    action.borrowRecordOffset = recordOffset;
}

bool CodeGen::hasOpenLocalValueBorrow() const
{
    if (valueBorrowSites.empty())
        return false;

    // Call-site records precede parameter records in the frame. Incoming parameters
    // borrow storage that existed before this frame, so they cannot cover its locals.
    const uint32_t lastLocalRecordOffset = valueBorrowSites.back().stackOffset;
    for (const CodeGenDeferScope& scope : deferScopes_)
    {
        for (const CodeGenDeferredAction& action : scope.actions)
        {
            if (action.kind == CodeGenDeferredAction::Kind::EndValueBorrow && action.borrowRecordOffset <= lastLocalRecordOffset)
                return true;
        }
    }

    return false;
}

// Whether a borrow this function opened and has not yet released could cover `local`.
// Distinct variables never share storage, so a borrow whose argument is another variable's
// own value cannot reach it. Any other argument shape, an address through a pointer for
// instance, could name the local, and counts as covering it.
bool CodeGen::openLocalValueBorrowMayCover(const SymbolVariable& local)
{
    if (valueBorrowSites.empty())
        return false;

    const auto borrowedVariable = [&](const ValueBorrowSite& site) -> const SymbolVariable* {
        AstNodeRef ref = resolvedNodeRef(site.expressionRef);
        if (ref.isValid() && site.addressHome)
            ref = resolvedNodeRef(node(ref).cast<AstSingleVarDecl>().nodeInitRef);
        while (ref.isValid() && (node(ref).is(AstNodeId::ParenExpr) || node(ref).is(AstNodeId::CastExpr)))
            ref = resolvedNodeRef(node(ref).is(AstNodeId::ParenExpr) ? node(ref).cast<AstParenExpr>().nodeExprRef : node(ref).cast<AstCastExpr>().nodeExprRef);
        if (ref.isInvalid() || !node(ref).is(AstNodeId::Identifier))
            return nullptr;

        const Symbol* symbol = viewSymbol(ref).sym();
        const auto*   symVar = symbol ? symbol->safeCast<SymbolVariable>() : nullptr;
        if (!symVar || !symVar->isFrameVariable() || symVar->isClosureCapture() || symVar->hasGlobalStorage())
            return nullptr;

        // A pointer's value is an address: what it borrows lies outside the variable.
        const TypeInfo& type = typeMgr().unwrapAliasEnumTypeOrSelf(ctx(), symVar->typeRef());
        return type.isPointerLikeOrReference() ? nullptr : symVar;
    };

    const uint32_t lastLocalRecordOffset = valueBorrowSites.back().stackOffset;
    for (const CodeGenDeferScope& scope : deferScopes_)
    {
        for (const CodeGenDeferredAction& action : scope.actions)
        {
            if (action.kind != CodeGenDeferredAction::Kind::EndValueBorrow || action.borrowRecordOffset > lastLocalRecordOffset)
                continue;
            for (const ValueBorrowSite& site : valueBorrowSites)
            {
                if (site.stackOffset != action.borrowRecordOffset)
                    continue;
                const SymbolVariable* borrowed = borrowedVariable(site);
                if (!borrowed || borrowed == &local)
                    return true;
            }
        }
    }

    return false;
}

AstNodeRef CodeGen::currentFallibleScope()
{
    for (size_t index = deferScopes_.size(); index != 0; --index)
    {
        const AstNodeRef          scopeRef = deferScopes_[index - 1].scopeRef;
        const CodeGenNodePayload* payload  = safePayload(scopeRef);
        if (payload && payload->hasFallibleWrapper() && payload->fallibleFailLabel.isValid())
            return scopeRef;
    }
    return AstNodeRef::invalid();
}

void CodeGen::registerErrorScopePop()
{
    SWC_ASSERT(!deferScopes_.empty());

    auto& action = deferScopes_.back().actions.emplace_back();
    action.kind  = CodeGenDeferredAction::Kind::PopErrorScope;
}

void CodeGen::registerImplicitDrop(const SymbolVariable& symVar, const CodeGenFunctionHelpers::FunctionParameterInfo* paramInfo)
{
    if (!hasDeferredStatements_)
        return;
    if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
    {
        if (CodeGenFunctionHelpers::isBorrowedIndirectParameter(*this, function(), symVar, paramInfo))
            return;

        // A by-value aggregate parameter is a transport image of the caller's value: ownership
        // stays with the caller, exactly as for a borrowed indirect parameter.
        if (CodeGenFunctionHelpers::isByValueAggregateParameter(*this, function(), symVar, paramInfo))
            return;
        if (!symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) &&
            !CodeGenFunctionHelpers::canUseIncomingIndirectParameterAsAddressableParameter(*this, function(), symVar, paramInfo))
            return;
    }

    if (!symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) &&
        !symVar.hasExtraFlag(SymbolVariableFlagsE::Initialized))
        return;

    if (!hasLifecycle(symVar.typeRef(), LifecycleKind::Drop))
        return;

    SWC_ASSERT(!deferScopes_.empty());
    if (deferScopes_.empty())
        return;

    auto& action            = lifetimeDeferScope().actions.emplace_back();
    action.kind             = CodeGenDeferredAction::Kind::ImplicitDrop;
    action.variable         = &symVar;
    action.lifecycleTypeRef = symVar.typeRef();
    action.lifecycleKind    = LifecycleKind::Drop;
    action.modifierFlags    = AstModifierFlagsE::Zero;
}

void CodeGen::addReturnStorageLocal(const SymbolVariable& symVar, const SemaInlinePayload* returnContext)
{
    returnStorageLocals_.insert(&symVar);
    if (returnContext)
        returnStorageLocalContexts_.set(&symVar, returnContext);
}

void CodeGen::addReplacingReturn(AstNodeRef returnRef, const SymbolVariable& symVar, const SymbolVariable* demotedStorage)
{
    replacingReturns_.push_back({returnRef, &symVar});
    if (demotedStorage)
        demotedReturnStorages_.insert(demotedStorage);
}

const SymbolVariable* CodeGen::returnReplacedLocal(AstNodeRef returnRef) const
{
    for (const auto& [ref, symVar] : replacingReturns_)
    {
        if (ref == returnRef)
            return symVar;
    }

    return nullptr;
}

void CodeGen::registerImplicitParameterDrops(std::span<const CodeGenFunctionHelpers::FunctionParameterInfo> paramInfos)
{
    const auto& params = function().parameters();
    SWC_ASSERT(paramInfos.size() == params.size());

    for (size_t i = 0; i < params.size(); ++i)
    {
        const SymbolVariable* symVar = params[i];
        if (symVar)
            registerImplicitDrop(*symVar, &paramInfos[i]);
    }
}

Result CodeGen::emitDeferredAction(const CodeGenDeferredAction& action)
{
    switch (action.kind)
    {
        case CodeGenDeferredAction::Kind::EndValueBorrow:
            return CodeGenSafety::emitValueBorrowEnd(*this, action.borrowRecordOffset);

        case CodeGenDeferredAction::Kind::PopErrorScope:
        {
            const IdentifierRef idRef = idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::PopErr);
            SWC_ASSERT(idRef.isValid());
            const SymbolFunction* popErr = compiler().runtimeFunctionSymbol(idRef);
            SWC_ASSERT(popErr != nullptr);
            return CodeGenCallHelpers::emitRuntimeCallWithDirectArgs(*this, *popErr, std::span<const MicroReg>{});
        }

        case CodeGenDeferredAction::Kind::DeferStmt:
        {
            if (action.bodyRef.isInvalid())
                return Result::Continue;

            const auto emitBody = [&]() -> Result {
                // Match the semantic scope of the deferred body, including a single statement.
                // New owners must not be appended to the outer scope already being unwound.
                pushDeferScope(action.deferStmtRef);
                SWC_RESULT(emitNodeNow(action.bodyRef));
                return popDeferScope();
            };

            const bool needsErr   = action.modifierFlags.has(AstModifierFlagsE::Fail);
            const bool needsNoErr = action.modifierFlags.has(AstModifierFlagsE::NoFail);
            if (!needsErr && !needsNoErr)
                return emitBody();

            const IdentifierRef idRef = idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::IsErrContext);
            SWC_ASSERT(idRef.isValid());
            if (idRef.isInvalid())
                return Result::Error;

            const SymbolFunction* runtimeIsErrContext = compiler().runtimeFunctionSymbol(idRef);
            SWC_ASSERT(runtimeIsErrContext != nullptr);
            if (!runtimeIsErrContext)
                return Result::Error;

            const MicroReg      errContextReg = nextVirtualIntRegister();
            MicroBuilder&       builder       = this->builder();
            const MicroLabelRef skipLabel     = builder.createLabel();
            SWC_RESULT(CodeGenCallHelpers::emitRuntimeCallWithDirectArgsToReg(*this, *runtimeIsErrContext, std::span<const MicroReg>{}, errContextReg));
            builder.emitCmpRegImm(errContextReg, ApInt(0, 64), MicroOpBits::B8);
            builder.emitJumpToLabel(needsErr ? MicroCond::Equal : MicroCond::NotEqual, MicroOpBits::B32, skipLabel);
            SWC_RESULT(emitBody());
            builder.placeLabel(skipLabel);
            return Result::Continue;
        }

        case CodeGenDeferredAction::Kind::ImplicitDrop:
        {
            if (!action.variable || action.lifecycleTypeRef.isInvalid())
                return Result::Continue;

            // The local was consumed by a '#move' that proved it dead: no drop.
            if (isImplicitDropElided(*action.variable))
                return Result::Continue;

            // This return moved ownership into its result, or released the local it replaced.
            if (action.variable == returnMoveOutVar_ || action.variable == returnReplacedLocal_)
                return Result::Continue;

            CodeGenNodePayload variablePayload;
            if (!resolveDeferredVariableAddress(*this, *action.variable, variablePayload))
                return Result::Continue;

            SWC_RESULT(emitLifecycle(action.lifecycleTypeRef, action.lifecycleKind, variablePayload.reg));

            // Replace stale bytes in dropped storage when lifecycle poisoning is active.
            if (CodeGenSafety::hasLifecycleRuntimeSafety(*this))
                SWC_RESULT(CodeGenSafety::emitLifecyclePoison(*this, variablePayload.reg, typeMgr().get(action.lifecycleTypeRef).sizeOf(ctx())));

            return Result::Continue;
        }
    }

    return Result::Continue;
}

Result CodeGen::emitDeferredActionsInScope(const size_t scopeIndex, const size_t actionCount, const bool popErrorScope)
{
    SWC_ASSERT(scopeIndex < deferScopes_.size());
    if (scopeIndex >= deferScopes_.size())
        return Result::Continue;

    // Run actions in LIFO order. A nested return/break resumes at the cursor,
    // skipping the action already being emitted.
    const size_t clampedActionCount = std::min(actionCount, deferScopes_[scopeIndex].actions.size());
    deferredEmissionCursors_.push_back({.scopeIndex = scopeIndex, .nextActionCount = clampedActionCount});

    auto result = Result::Continue;
    for (size_t i = clampedActionCount; i != 0; --i)
    {
        deferredEmissionCursors_.back().nextActionCount = i - 1;

        // Emitting a deferred body can grow the scope stack. Keep no reference into it alive
        // across that emission, and copy the action before its owning scope can move.
        const CodeGenDeferredAction action = deferScopes_[scopeIndex].actions[i - 1];
        if (action.kind == CodeGenDeferredAction::Kind::PopErrorScope && !popErrorScope)
            continue;

        result = emitDeferredAction(action);
        if (result != Result::Continue || currentInstructionBlocksFallthrough())
            break;
    }

    deferredEmissionCursors_.pop_back();
    return result;
}

Result CodeGen::emitDeferredActionsFrom(const size_t startScopeIndex, const size_t startActionCount, const size_t stopScopeIndex, const bool hasStopScope, const bool popStopErrorScope)
{
    if (startScopeIndex >= deferScopes_.size())
        return Result::Continue;

    for (size_t scopeCursor = startScopeIndex + 1; scopeCursor != 0; --scopeCursor)
    {
        const size_t scopeIndex  = scopeCursor - 1;
        size_t       actionCount = scopeIndex == startScopeIndex ? startActionCount : deferScopes_[scopeIndex].actions.size();

        // A return or failure inside a defer first leaves its new inner scopes. When it
        // reaches an already-running outer scope, resume after that scope's current action.
        for (const auto& cursor : deferredEmissionCursors_)
        {
            if (cursor.scopeIndex == scopeIndex)
                actionCount = std::min(actionCount, cursor.nextActionCount);
        }

        SWC_RESULT(emitDeferredActionsInScope(scopeIndex, actionCount, !hasStopScope || scopeIndex != stopScopeIndex || popStopErrorScope));
        if (currentInstructionBlocksFallthrough() || (hasStopScope && scopeIndex == stopScopeIndex))
            break;
    }

    return Result::Continue;
}

bool CodeGen::findInnermostDeferScopeIndex(AstNodeRef scopeRef, size_t& outScopeIndex) const
{
    outScopeIndex = 0;
    for (size_t i = deferScopes_.size(); i != 0; --i)
    {
        if (deferScopes_[i - 1].scopeRef == scopeRef)
        {
            outScopeIndex = i - 1;
            return true;
        }
    }

    return false;
}

Result CodeGen::popDeferScope()
{
    if (!hasDeferredStatements_)
        return Result::Continue;

    SWC_ASSERT(!deferScopes_.empty());
    if (deferScopes_.empty())
        return Result::Continue;

    // Keep the scope and its cursor live while an action runs. An early exit from that
    // action must still be able to finish this scope's remaining cleanup exactly once.
    if (!currentInstructionBlocksFallthrough())
        SWC_RESULT(emitDeferredActionsInScope(deferScopes_.size() - 1, deferScopes_.back().actions.size(), false));

    deferScopes_.pop_back();
    return Result::Continue;
}

Result CodeGen::emitDeferredActionsForReturn()
{
    if (!hasDeferredStatements_)
        return Result::Continue;

    if (deferScopes_.empty())
        return Result::Continue;

    return emitDeferredActionsFrom(deferScopes_.size() - 1, deferScopes_.back().actions.size(), 0, false);
}

Result CodeGen::emitDeferredActionsUntilScopeRef(AstNodeRef scopeRef, const bool popErrorScope)
{
    if (!hasDeferredStatements_)
        return Result::Continue;

    scopeRef = resolvedNodeRef(scopeRef);
    if (scopeRef.isInvalid())
        return Result::Continue;

    size_t stopScopeIndex = 0;
    if (!findInnermostDeferScopeIndex(scopeRef, stopScopeIndex))
        return Result::Continue;

    // A failure jumps into its handler; that handler still owns the pushed frame.
    return emitDeferredActionsFrom(deferScopes_.size() - 1, deferScopes_.back().actions.size(), stopScopeIndex, true, popErrorScope);
}

Result CodeGen::emitDeferredActionsDownTo(size_t stopScopeIndex)
{
    if (deferScopes_.empty())
        return Result::Continue;

    return emitDeferredActionsFrom(deferScopes_.size() - 1, deferScopes_.back().actions.size(), stopScopeIndex, true);
}

Result CodeGen::emitDeferredActionsUntilOwner(AstNodeRef CodeGenDeferScope::* ownerField, AstNodeRef ownerRef)
{
    if (!hasDeferredStatements_)
        return Result::Continue;

    ownerRef = resolvedNodeRef(ownerRef);
    if (ownerRef.isInvalid())
        return Result::Continue;

    for (size_t i = deferScopes_.size(); i != 0; --i)
    {
        if (deferScopes_[i - 1].*ownerField == ownerRef)
            return emitDeferredActionsDownTo(i - 1);
    }

    return Result::Continue;
}

Result CodeGen::emitDeferredActionsUntilBreakOwner(AstNodeRef breakOwnerRef)
{
    return emitDeferredActionsUntilOwner(&CodeGenDeferScope::breakOwnerRef, breakOwnerRef);
}

Result CodeGen::emitDeferredActionsUntilSwitchCase(AstNodeRef switchCaseRef)
{
    return emitDeferredActionsUntilOwner(&CodeGenDeferScope::switchCaseRef, switchCaseRef);
}

bool CodeGen::currentInstructionBlocksFallthrough() const
{
    const MicroStorage& instructions = builder().instructions();
    const MicroInstrRef ref          = instructions.findPreviousInstructionRef(MicroInstrRef::invalid());
    if (!ref.isValid())
        return false;

    const MicroInstr* inst = instructions.ptr(ref);
    if (!inst)
        return false;

    if (inst->op == MicroInstrOpcode::Label)
        return false;

    if (inst->op == MicroInstrOpcode::Ret || inst->op == MicroInstrOpcode::Trap || inst->op == MicroInstrOpcode::JumpReg)
        return true;

    const MicroInstrOperand* ops = inst->ops(builder().operands());
    return ops && MicroInstrInfo::isUnconditionalJumpInstruction(*inst, ops);
}

void CodeGen::invalidateNodePayloadRegs(AstNodeRef nodeRef)
{
    if (nodeRef.isInvalid())
        return;

    // Invalidate the substituted tree that emission actually visits, including
    // inline expansions, operator rewrites, and lowered loops. Cached registers
    // from an earlier emission need not be defined along the new control-flow path.
    RefSet<AstNodeRef>      visited;
    SmallVector<AstNodeRef> stack;
    stack.push_back(nodeRef);
    while (!stack.empty())
    {
        const AstNodeRef rawRef = stack.back();
        stack.pop_back();
        if (rawRef.isInvalid())
            continue;

        const AstNodeRef currentRef = resolvedNodeRef(rawRef);
        if (currentRef.isInvalid() || !visited.insert(currentRef))
            continue;

        // Invalidation only visits state created by an earlier emission. Avoid
        // allocating payloads from sema metadata for nodes not emitted yet.
        auto* payload = static_cast<CodeGenNodePayload*>(nodePayloads_.find(currentRef));
        if (payload)
        {
            payload->reg = MicroReg::invalid();

            // A catch in a defer can be emitted for both a try failure and a normal return.
            // Consuming its handler belongs to one emission, not to the shared AST node.
            if (payload->fallibleWrapperConsumed)
            {
                payload->fallibleWrapperConsumed = false;
                mergeLoweringNodePayloadMetadata(*payload, currentRef, currentRef);
            }
        }

        node(currentRef).collectChildrenFromAst(stack, ast());
    }
}

bool CodeGen::containsDeferredActions(AstNodeRef nodeRef)
{
    if (nodeRef.isInvalid())
        return false;

    RefSet<AstNodeRef>      visited;
    SmallVector<AstNodeRef> stack;
    stack.push_back(nodeRef);
    while (!stack.empty())
    {
        const AstNodeRef rawRef = stack.back();
        stack.pop_back();
        if (rawRef.isInvalid())
            continue;

        // The root is the function being emitted. Its value can be wrapped in a conversion at
        // the enclosing call site; following that substitution would hide its body and defers.
        const AstNodeRef currentRef = rawRef == nodeRef ? rawRef : sema().resolvedNodeRef(rawRef);
        if (currentRef.isInvalid())
            continue;
        if (!visited.insert(currentRef))
            continue;

        const AstNode& currentNode = ast().node(currentRef);
        if (const auto* lowering = loweringPayload(currentRef); lowering && lowering->valueBorrowSafetyOverride == 1)
            return true;
        if (const auto* expansion = sema().inlinePayload(currentRef); expansion && ((expansion->runtimeSafetyMask | expansion->callerRuntimeSafetyMask) & static_cast<uint16_t>(Runtime::SafetyWhat::ValueBorrow)))
            return true;
        if (currentNode.id() == AstNodeId::DeferStmt || currentNode.id() == AstNodeId::ErrorManagementExpr || currentNode.id() == AstNodeId::ErrorManagementStmt)
            return true;

        currentNode.collectChildrenFromAst(stack, ast());
    }

    return false;
}

Result CodeGen::emitNodeNow(AstNodeRef nodeRef)
{
    nodeRef = resolvedNodeRef(nodeRef);
    if (nodeRef.isInvalid())
        return Result::Continue;

    invalidateNodePayloadRegs(nodeRef);

    AstVisit savedVisit = std::move(visit_);
    visit_              = {};
    setVisitors();
    visit_.start(ast(), nodeRef);

    const uint32_t savedDeferredAddressGeneration = currentDeferredAddressGeneration_;
    currentDeferredAddressGeneration_             = nextDeferredAddressGeneration_++;
    SWC_ASSERT(currentDeferredAddressGeneration_ != 0);
    ++deferredEmitDepth_;

    auto result = Result::Continue;
    while (true)
    {
        const AstVisitResult visitResult = visit_.step(ctx());
        if (visitResult == AstVisitResult::Continue)
            continue;

        if (visitResult == AstVisitResult::Pause)
            result = Result::Pause;
        else if (visitResult == AstVisitResult::Error)
            result = Result::Error;

        break;
    }

    --deferredEmitDepth_;
    currentDeferredAddressGeneration_ = savedDeferredAddressGeneration;
    visit_                            = std::move(savedVisit);

    if (curNodeRef().isValid())
        builder().setCurrentDebugSourceCodeRef(node(curNodeRef()).codeRef());

    return result;
}

void CodeGen::clearGlobalsToDropScratchLayout()
{
    globalsToDropScratchEntries_.clear();
    globalsToDropScratchOffset_ = 0;
    globalsToDropScratchSize_   = 0;
}

void CodeGen::setGlobalsToDropScratchLayout(uint32_t offset, uint32_t size, std::span<const CodeGenGlobalToDropEntry> entries)
{
    globalsToDropScratchOffset_ = offset;
    globalsToDropScratchSize_   = size;
    globalsToDropScratchEntries_.clear();
    globalsToDropScratchEntries_.append(entries.data(), entries.size());
}

void CodeGen::pushFrame(const CodeGenFrame& frame)
{
    frames_.push_back(frame);
}

void CodeGen::popFrame()
{
    SWC_ASSERT(!frames_.empty());
    if (frames_.size() >= 2)
    {
        const CodeGenFrame& currentFrame = frames_.back();
        CodeGenFrame&       parentFrame  = frames_[frames_.size() - 2];

        if (currentFrame.hasCurrentInlineContext())
        {
            const CodeGenFrame::InlineContext& childInlineCtx = currentFrame.currentInlineContext();
            const MicroLabelRef                childDoneLabel = childInlineCtx.doneLabel;
            if (childDoneLabel.isValid())
            {
                for (size_t frameIndex = frames_.size() - 1; frameIndex != 0; --frameIndex)
                {
                    CodeGenFrame& ancestorFrame = frames_[frameIndex - 1];
                    if (!ancestorFrame.hasCurrentInlineContext())
                        continue;

                    const CodeGenFrame::InlineContext& ancestorInlineCtx = ancestorFrame.currentInlineContext();
                    if (ancestorInlineCtx.rootNodeRef != childInlineCtx.rootNodeRef || ancestorInlineCtx.payload != childInlineCtx.payload)
                        continue;

                    const MicroLabelRef ancestorDoneLabel = ancestorInlineCtx.doneLabel;
                    SWC_ASSERT(ancestorDoneLabel == MicroLabelRef::invalid() || ancestorDoneLabel == childDoneLabel);
                    if (ancestorDoneLabel == MicroLabelRef::invalid())
                        ancestorFrame.setCurrentInlineDoneLabel(childDoneLabel);

                    break;
                }
            }
        }

        // Copied frames, such as switch cases and inline expansions, can record
        // a `continue` targeting the inherited loop context.
        if (currentFrame.currentLoopHasContinueJump() &&
            currentFrame.currentContinuableKind() == CodeGenFrame::BreakContextKind::Loop &&
            parentFrame.currentContinuableKind() == currentFrame.currentContinuableKind() &&
            parentFrame.currentContinueContext().nodeRef == currentFrame.currentContinueContext().nodeRef &&
            parentFrame.currentLoopContinueLabel() == currentFrame.currentLoopContinueLabel())
        {
            parentFrame.setCurrentLoopHasContinueJump(true);
        }
    }

    frames_.pop_back();
}

MicroReg CodeGen::nextVirtualRegisterForType(TypeRef typeRef)
{
    if (typeRef.isInvalid())
        return nextVirtualIntRegister();

    return nextVirtualRegisterForType(typeRef, typeMgr().get(typeRef));
}

MicroReg CodeGen::nextVirtualRegisterForType(TypeRef typeRef, const TypeInfo& typeInfo)
{
    const TypeInfo* registerType = &typeInfo;
    if (registerType->isAlias())
    {
        const TypeInfo* resolvedType = registerType->unwrapAliasEnumType(ctx());
        registerType                 = resolvedType ? resolvedType : &typeMgr().get(typeRef);
    }

    if (registerType->isFloat() || registerType->isSimd())
        return nextVirtualFloatRegister();

    return nextVirtualIntRegister();
}

void CodeGen::setVisitors()
{
    visit_.setMode(AstVisitMode::ResolveBeforeCallbacks);
    visit_.setNodeRefResolver([this](const AstNodeRef nodeRef) { return sema().resolvedNodeRef(nodeRef); });
    visit_.setPreNodeVisitor([this](AstNode& node) { return preNode(node); });
    visit_.setPreChildVisitor([this](AstNode& node, AstNodeRef& childRef) { return preNodeChild(node, childRef); });
    visit_.setPostChildVisitor([this](AstNode& node, AstNodeRef& childRef) { return postNodeChild(node, childRef); });
    visit_.setPostNodeVisitor([this](AstNode& node) { return postNode(node); });
}

Result CodeGen::preNode(AstNode& node)
{
    builder().setCurrentDebugSourceCodeRef(node.codeRef());
    // Compiler queries have already resolved their result during semantic analysis.
    // In particular, a #decltype operand names a type without running that operand.
    if (node.id() == AstNodeId::Attribute || node.id() == AstNodeId::CompilerCallOne)
        return Result::SkipChildren;

    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    if (valueBorrowValueScopeRefs.contains(curNodeRef()))
    {
        pushDeferScope(curNodeRef());
        deferScopes_.back().borrowOnly = true;
    }

    SWC_RESULT(info.codeGenPreNode(*this, node));

    const AstNodeRef currentNodeRef   = curNodeRef();
    void*            rawInlinePayload = nullptr;
    void*            rawOverride      = nullptr;
    sema().inlineContext(currentNodeRef, rawInlinePayload, rawOverride);

    const auto* inlinePayload  = static_cast<const SemaInlinePayload*>(rawInlinePayload);
    const auto* inlineOverride = static_cast<const SemaInlineContextOverride*>(rawOverride);

    if (inlinePayload && inlinePayload->inlineRootRef == currentNodeRef)
    {
        CodeGenFrame frame = this->frame();
        frame.setCurrentInlineContext(currentNodeRef, inlinePayload, MicroLabelRef::invalid());
        if (inlinePayload->resultVar && inlinePayload->returnTypeRef.isValid())
        {
            MicroReg        resultStorageReg = MicroReg::invalid();
            SymbolVariable* resultStorageSym = nullptr;
            if (CodeGenFunctionHelpers::tryUseDirectVarInitStorage(*this, currentNodeRef, inlinePayload->returnTypeRef, resultStorageReg, resultStorageSym))
            {
                frame.currentInlineContext().resultStorageReg = resultStorageReg;
                frame.currentInlineContext().resultStorageSym = resultStorageSym;
            }
            else if (CodeGenFunctionHelpers::tryUseDirectReturnStorage(*this, currentNodeRef, inlinePayload->returnTypeRef, resultStorageReg, resultStorageSym))
            {
                // A returned expansion builds its result where the enclosing return goes, as a call does.
                frame.currentInlineContext().resultStorageReg    = resultStorageReg;
                frame.currentInlineContext().resultStorageSym    = resultStorageSym;
                frame.currentInlineContext().directReturnStorage = true;
            }
        }

        pushFrame(frame);
    }
    else if (inlineOverride)
    {
        CodeGenFrame frame = this->frame();
        if (const SemaInlinePayload* targetInlinePayload = inlineOverride->targetInlinePayload)
        {
            const CodeGenFrame::InlineContext* matchingInlineCtx = findMatchingInlineContext(frames(), targetInlinePayload->inlineRootRef, targetInlinePayload);
            const MicroLabelRef                doneLabel         = matchingInlineCtx ? matchingInlineCtx->doneLabel : MicroLabelRef::invalid();
            frame.setCurrentInlineContext(targetInlinePayload->inlineRootRef, targetInlinePayload, doneLabel);
            if (matchingInlineCtx)
            {
                frame.currentInlineContext().resultStorageReg    = matchingInlineCtx->resultStorageReg;
                frame.currentInlineContext().resultStorageSym    = matchingInlineCtx->resultStorageSym;
                frame.currentInlineContext().directReturnStorage = matchingInlineCtx->directReturnStorage;
            }

            // Without an outer frame, this is a locally compiled function (for example
            // inside a macro). Place any return's doneLabel at this boundary because
            // the enclosing expansion cannot place it.
            frame.currentInlineContext().noOuterDoneLabel = matchingInlineCtx == nullptr;
        }
        else
        {
            frame.clearCurrentInlineContext();
        }

        frame.setCurrentInlineBoundaryRootRef(currentNodeRef);
        pushFrame(frame);
    }

    if (curViewConstant().hasConstant() || keepsFoldedConstant(currentNodeRef))
        return Result::SkipChildren;

    return Result::Continue;
}

Result CodeGen::postNode(AstNode& node)
{
    builder().setCurrentDebugSourceCodeRef(node.codeRef());
    auto result = Result::Continue;
    if (curViewConstant().hasConstant() || keepsFoldedConstant(curNodeRef()))
    {
        result = emitConstant(curNodeRef());
    }
    else
    {
        const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
        result                    = info.codeGenPostNode(*this, node);
    }

    if (result == Result::Pause || result == Result::Error)
        return result;

    if (frame().hasCurrentInlineBoundary() && frame().currentInlineBoundaryRootRef() == curNodeRef())
    {
        if (frame().hasCurrentInlineContext() && frame().currentInlineContext().rootNodeRef == curNodeRef())
        {
            const CodeGenFrame::InlineContext inlineCtx = frame().currentInlineContext();
            SWC_ASSERT(inlineCtx.payload != nullptr);

            if (inlineCtx.doneLabel.isValid())
                builder().placeLabel(inlineCtx.doneLabel);

            clearNodePayload<CodeGenNodePayload>(curNodeRef());
            auto& inlineNodePayload   = ensureNodePayload<CodeGenNodePayload>(curNodeRef());
            inlineNodePayload.typeRef = inlineCtx.payload->returnTypeRef;
            if (inlineCtx.payload->returnTypeRef != typeMgr().typeVoid())
            {
                SWC_ASSERT(inlineCtx.payload->resultVar != nullptr);
                // A result built in the enclosing function's return slot has no symbol, like a call's.
                SymbolVariable* resultStorageSym = inlineCtx.resultStorageSym ? inlineCtx.resultStorageSym : inlineCtx.payload->resultVar;
                inlineNodePayload.setIsAddress();
                inlineNodePayload.setRuntimeStorageSymbol(inlineCtx.directReturnStorage ? inlineCtx.resultStorageSym : resultStorageSym);
                if (inlineCtx.resultStorageReg.isValid())
                    inlineNodePayload.reg = inlineCtx.resultStorageReg;
                else
                {
                    // This undeclared result temporary needs a fresh address at the join;
                    // a cached return-branch definition would not dominate every path.
                    inlineNodePayload.reg = resolveLocalStackPayload(*resultStorageSym, false).reg;
                }
            }
        }
        else if (frame().hasCurrentInlineContext() && frame().currentInlineContext().noOuterDoneLabel)
        {
            // A locally compiled function's inline root can live in the caller's AST,
            // so rootNodeRef need not match curNodeRef. Place return targets here when
            // preNode found no outer frame to place them; noOuterDoneLabel records
            // that requirement.
            const MicroLabelRef doneLabel = frame().currentInlineContext().doneLabel;
            if (doneLabel.isValid())
                builder().placeLabel(doneLabel);
        }

        popFrame();
    }

    if (valueBorrowValueScopeRefs.contains(curNodeRef()))
        SWC_RESULT(popDeferScope());

    SWC_RESULT(CodeGenSafety::emitValueBorrowSite(*this, curNodeRef()));
    SWC_RESULT(flushTemporaryDrops(curNodeRef()));

    return result;
}

Result CodeGen::preNodeChild(AstNode& node, AstNodeRef& childRef)
{
    if (sema().isImplicitCodeBlockArg(curNodeRef(), childRef))
        return Result::SkipChildren;

    if (childRef.isValid())
        builder().setCurrentDebugSourceCodeRef(this->node(childRef).codeRef());

    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    return info.codeGenPreNodeChild(*this, node, childRef);
}

Result CodeGen::postNodeChild(AstNode& node, AstNodeRef& childRef)
{
    if (childRef.isValid())
        builder().setCurrentDebugSourceCodeRef(this->node(childRef).codeRef());

    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    return info.codeGenPostNodeChild(*this, node, childRef);
}

SWC_END_NAMESPACE();
