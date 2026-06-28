#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroReg.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    MicroLabelRef findMatchingInlineDoneLabel(std::span<const CodeGenFrame> frames, AstNodeRef rootNodeRef, const SemaInlinePayload* payload)
    {
        if (!payload || rootNodeRef.isInvalid())
            return MicroLabelRef::invalid();

        for (size_t frameIndex = frames.size(); frameIndex != 0; --frameIndex)
        {
            const CodeGenFrame& frame = frames[frameIndex - 1];
            if (!frame.hasCurrentInlineContext())
                continue;

            const CodeGenFrame::InlineContext& inlineCtx = frame.currentInlineContext();
            if (inlineCtx.rootNodeRef == rootNodeRef && inlineCtx.payload == payload)
                return inlineCtx.doneLabel;
        }

        return MicroLabelRef::invalid();
    }

    bool hasMatchingInlineFrame(std::span<const CodeGenFrame> frames, AstNodeRef rootNodeRef, const SemaInlinePayload* payload)
    {
        if (!payload || rootNodeRef.isInvalid())
            return false;

        for (size_t frameIndex = frames.size(); frameIndex != 0; --frameIndex)
        {
            const CodeGenFrame& frame = frames[frameIndex - 1];
            if (!frame.hasCurrentInlineContext())
                continue;
            const CodeGenFrame::InlineContext& inlineCtx = frame.currentInlineContext();
            if (inlineCtx.rootNodeRef == rootNodeRef && inlineCtx.payload == payload)
                return true;
        }

        return false;
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

        const TypeRef rawTypeRef = codeGen.typeMgr().get(typeRef).unwrap(codeGen.ctx(), typeRef, TypeExpandE::Alias);
        if (rawTypeRef.isValid())
            return rawTypeRef;
        return typeRef;
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
        if (!dst.throwableWrapperConsumed && !dst.hasThrowableWrapper() && src.hasThrowableWrapper())
        {
            dst.throwableWrapperOwnerRef = src.throwableWrapperOwnerRef;
            dst.throwableWrapperTokenId  = src.throwableWrapperTokenId;
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

    const SymbolFunction* resolveDirectLifecycleFunction(const TypeInfo& typeInfo, const CodeGenLifecycleKind lifecycleKind)
    {
        if (!typeInfo.isStruct())
            return nullptr;

        switch (lifecycleKind)
        {
            case CodeGenLifecycleKind::Drop:
                return typeInfo.payloadSymStruct().opDrop();
            case CodeGenLifecycleKind::PostCopy:
                return typeInfo.payloadSymStruct().opPostCopy();
            case CodeGenLifecycleKind::PostMove:
                return typeInfo.payloadSymStruct().opPostMove();
        }

        return nullptr;
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

    uint64_t arrayTotalElementCount(const TypeInfo& typeInfo)
    {
        uint64_t total = 1;
        for (const uint64_t dim : typeInfo.payloadArrayDims())
            total *= dim;
        return total;
    }

    bool hasLifecycleRec(const CodeGen& codeGen, TypeRef typeRef, const CodeGenLifecycleKind lifecycleKind)
    {
        typeRef = normalizeLifecycleTypeRef(codeGen, typeRef);
        if (!typeRef.isValid())
            return false;

        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        if (typeInfo.isArray())
        {
            if (!arrayTotalElementCount(typeInfo))
                return false;

            return hasLifecycleRec(codeGen, typeInfo.payloadArrayElemTypeRef(), lifecycleKind);
        }

        if (!typeInfo.isStruct())
            return false;

        if (resolveDirectLifecycleFunction(typeInfo, lifecycleKind))
            return true;

        for (const SymbolVariable* field : typeInfo.payloadSymStruct().fields())
        {
            if (field && hasLifecycleRec(codeGen, field->typeRef(), lifecycleKind))
                return true;
        }

        return false;
    }

    bool tryBuildLifecycleActionRec(const CodeGen& codeGen, TypeRef typeRef, const CodeGen::LifecycleKind lifecycleKind, const SymbolFunction*& outFunction, uint32_t& outSizeOf, uint32_t& outCount)
    {
        outFunction = nullptr;
        outSizeOf   = 0;
        outCount    = 0;
        if (!typeRef.isValid())
            return false;

        const TypeInfo& originalType = codeGen.typeMgr().get(typeRef);
        const TypeRef   rawTypeRef   = originalType.unwrap(codeGen.ctx(), typeRef, TypeExpandE::Alias);
        if (rawTypeRef.isValid() && rawTypeRef != typeRef)
            typeRef = rawTypeRef;

        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        if (typeInfo.isArray())
        {
            const uint64_t multiplier = arrayTotalElementCount(typeInfo);
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

    Result emitLifecycleRec(CodeGen& codeGen, TypeRef typeRef, const CodeGenLifecycleKind lifecycleKind, const MicroReg addressReg)
    {
        typeRef = normalizeLifecycleTypeRef(codeGen, typeRef);
        if (!typeRef.isValid())
            return Result::Continue;

        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        if (typeInfo.isArray())
        {
            const uint64_t totalCount = arrayTotalElementCount(typeInfo);
            if (!totalCount)
                return Result::Continue;

            SWC_ASSERT(totalCount <= std::numeric_limits<uint32_t>::max());
            return codeGen.emitLifecycle(typeInfo.payloadArrayElemTypeRef(), lifecycleKind, addressReg, static_cast<uint32_t>(totalCount));
        }

        if (!typeInfo.isStruct())
            return Result::Continue;

        const SymbolFunction* directLifecycle = resolveDirectLifecycleFunction(typeInfo, lifecycleKind);
        const auto&           fields          = typeInfo.payloadSymStruct().fields();

        // A user-defined drop must see its fields still alive. Post-copy and post-move run after the
        // contained fields have repaired their own state.
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

    if (kind == BreakContextKind::Loop || kind == BreakContextKind::Scope || kind == BreakContextKind::None)
    {
        continuable_.nodeRef        = nodeRef;
        continuable_.kind           = kind;
        currentLoopHasContinueJump_ = false;
    }

    if (kind != BreakContextKind::Switch && kind != BreakContextKind::Scope)
    {
        currentLoopIndexReg_     = MicroReg::invalid();
        currentLoopIndexTypeRef_ = TypeRef::invalid();
    }
}

void CodeGenFrame::setCurrentLoopIndex(MicroReg reg, TypeRef typeRef)
{
    currentLoopIndexReg_     = reg;
    currentLoopIndexTypeRef_ = typeRef;
}

void CodeGenFrame::setCurrentInlineContext(AstNodeRef rootNodeRef, const SemaInlinePayload* payload, MicroLabelRef doneLabel)
{
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
        root_     = root;
        function_ = &symbolFunc;
        builder_  = &symbolFunc.microInstrBuilder(ctx());
        visit_.start(ast(), root);

        nextVirtualRegister_                      = 1;
        localStackFrameSize_                      = 0;
        localStackBaseReg_                        = MicroReg::invalid();
        currentFunctionIndirectReturnStackOffset_ = 0xFFFFFFFFu;
        currentFunctionIndirectReturnReg_         = MicroReg::invalid();
        currentFunctionClosureContextReg_         = MicroReg::invalid();
        deferScopes_.clear();
        deferredEmissionCursors_.clear();
        deferredEmitDepth_                = 0;
        currentDeferredAddressGeneration_ = 0;
        nextDeferredAddressGeneration_    = 1;
        hasDeferredStatements_            = containsNodeId(root, AstNodeId::DeferStmt) || functionHasImplicitDrops(*this, symbolFunc);
        variablePayloads_.clear();
        clearGvtdScratchLayout();
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
        if (attributes.backendOptimize.has_value())
            backendBuildCfg.optimize = attributes.backendOptimize.value();

        builder_->setBackendBuildCfg(backendBuildCfg);
        if (compilerBuildCfg.backend.debugInfo)
            builderFlags.add(MicroBuilderFlagsE::DebugInfo);
        builder_->setFlags(builderFlags);
        builder_->setCurrentDebugSourceCodeRef(SourceCodeRef::invalid());
        builder_->setCurrentDebugNoStep(false);

        const SourceCodeRange codeRange = symbolFunc.codeRange(ctx());
        const SourceView&     srcView   = this->srcView(symbolFunc.srcViewRef());
        const SourceFile*     file      = srcView.file();
        const Utf8            fileName  = file ? file->formattedFileName(&ctx()) : Utf8{};
        builder_->setPrintPassOptions(symbolFunc.attributes().printMicroPassOptions);
        builder_->setPrintLocation(symbolFunc.getFullScopedName(ctx()), fileName, codeRange.line);

        started_ = true;
    }
    else
    {
        SWC_ASSERT(function_ == &symbolFunc);
        SWC_ASSERT(root_ == root);
    }

    TypeRef sourceLocTypeRef = TypeRef::invalid();
    SWC_RESULT(sema().waitPredefined(IdentifierManager::PredefinedName::SourceCodeLocation, sourceLocTypeRef, symbolFunc.codeRef()));

    while (true)
    {
        const AstNodeRef    currentNodeRef = visit_.currentNodeRef();
        const SourceCodeRef currentCodeRef = currentNodeRef.isValid() ? node(currentNodeRef).codeRef() : symbolFunc.codeRef();
        ctx().state().setCodeGenParsing(&symbolFunc, currentNodeRef, currentCodeRef);

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
    if (const auto* exactPayload = loweringPayload(nodeRef); exactPayload && exactPayload->runtimeStorageSym != nullptr)
        return exactPayload->runtimeStorageSym;

    const auto* payload = const_cast<CodeGen*>(this)->safePayload(nodeRef);
    if (payload && payload->runtimeStorageSym != nullptr)
        return payload->runtimeStorageSym;
    return nullptr;
}

void CodeGen::mergeLoweringNodePayloadMetadata(CodeGenNodePayload& payload, AstNodeRef nodeRef) const
{
    const AstNodeRef resolvedRef = resolvedNodeRef(nodeRef);
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
    CodeGenNodePayload* nodePayload  = safePayload(nodeRef);
    if ((!nodePayload || !nodePayload->reg.isValid()) && nodeRef.isValid() && resolvedNodeRef(nodeRef) != curNodeRef())
    {
        // Some substituted children are intentionally skipped during the main walk and are
        // only materialized when a parent eventually consumes their runtime value.
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

CodeGenNodePayload* CodeGen::safePayload(AstNodeRef nodeRef)
{
    const AstNodeRef resolvedRef = resolvedNodeRef(nodeRef);
    if (resolvedRef.isInvalid())
        return nullptr;

    CodeGenNodePayload* payload = safeNodePayload<CodeGenNodePayload>(resolvedRef);
    if (!payload)
    {
        const bool hasPayload = loweringPayload(resolvedRef) != nullptr || (resolvedRef != nodeRef && loweringPayload(nodeRef) != nullptr);
        if (!hasPayload)
            return nullptr;

        payload = &ensureNodePayload<CodeGenNodePayload>(nodeRef);
    }

    mergeLoweringNodePayloadMetadata(*payload, nodeRef);
    return payload;
}

void CodeGen::setVariablePayload(const SymbolVariable& sym, const CodeGenNodePayload& payload)
{
    if (sym.hasGlobalStorage())
        return;

    if (inDeferredEmission() && isStackAddressPayload(*this, sym, payload))
        return;

    VariablePayloadState& symbolPayload = variablePayloads_[&sym];
    symbolPayload.payload               = payload;
    symbolPayload.hasPayload            = true;
    symbolPayload.addressGeneration     = isStackAddressPayload(*this, sym, payload) ? currentDeferredAddressGeneration_ : 0;
}

const CodeGenNodePayload* CodeGen::variablePayload(const SymbolVariable& sym) const
{
    if (sym.hasGlobalStorage())
        return nullptr;

    const auto it = variablePayloads_.find(&sym);
    if (it == variablePayloads_.end() || !it->second.hasPayload)
        return nullptr;
    const VariablePayloadState& symbolPayload = it->second;
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
    dstPayload.storageKind         = srcPayloadCopy.storageKind;
    if (srcPayloadCopy.hasMaterializedPointerLikeValue())
        dstPayload.markMaterializedPointerLikeValue();
    mergeNodePayloadMetadata(dstPayload, srcPayloadCopy);
    return dstPayload;
}

CodeGenNodePayload& CodeGen::setPayload(AstNodeRef nodeRef, TypeRef typeRef)
{
    CodeGenNodePayload& nodePayload = ensureNodePayload<CodeGenNodePayload>(nodeRef);

    nodePayload.reg         = nextVirtualRegister();
    nodePayload.typeRef     = typeRef;
    nodePayload.storageKind = CodeGenNodePayload::StorageKind::Value;
    nodePayload.clearMaterializedPointerLikeValue();
    mergeLoweringNodePayloadMetadata(nodePayload, nodeRef);
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

MicroReg CodeGen::offsetAddressReg(const MicroReg baseReg, const uint32_t offset)
{
    SWC_ASSERT(baseReg.isValid());
    if (!offset)
        return baseReg;

    const MicroReg addressReg = nextVirtualIntRegister();
    if (baseReg.isInt())
        builder().addVirtualRegForbiddenPhysReg(addressReg, baseReg);
    builder().emitLoadRegReg(addressReg, baseReg, MicroOpBits::B64);
    builder().emitOpBinaryRegImm(addressReg, ApInt(offset, 64), MicroOp::Add, MicroOpBits::B64);
    return addressReg;
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

    const CodeGenNodePayload storagePayload = resolveLocalStackPayload(*storageSym, !inDeferredEmission());
    SWC_ASSERT(storagePayload.isAddress());
    return storagePayload.reg;
}

bool CodeGen::tryBuildLifecycleAction(const TypeRef typeRef, const LifecycleKind lifecycleKind, const SymbolFunction*& outFunction, uint32_t& outSizeOf, uint32_t& outCount) const
{
    return tryBuildLifecycleActionRec(*this, typeRef, lifecycleKind, outFunction, outSizeOf, outCount);
}

bool CodeGen::hasLifecycle(const TypeRef typeRef, const LifecycleKind lifecycleKind) const
{
    return hasLifecycleRec(*this, typeRef, lifecycleKind);
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
    return emitLifecycleRec(*this, typeRef, lifecycleKind, addressReg);
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

    MicroBuilder& builder   = this->builder();
    const auto    loopLabel = builder.createLabel();
    const auto    doneLabel = builder.createLabel();
    const auto    cursorReg = nextVirtualIntRegister();
    const auto    iterReg   = nextVirtualIntRegister();
    builder.emitLoadRegReg(cursorReg, addressReg, MicroOpBits::B64);
    builder.emitLoadRegReg(iterReg, countReg, MicroOpBits::B64);
    builder.emitCmpRegImm(iterReg, ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);

    builder.placeLabel(loopLabel);
    SWC_RESULT(emitLifecycle(normalizedTypeRef, lifecycleKind, cursorReg));
    builder.emitOpBinaryRegImm(cursorReg, ApInt(sizeOf, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(iterReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitCmpRegImm(iterReg, ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B32, loopLabel);
    builder.placeLabel(doneLabel);
    return Result::Continue;
}

void CodeGen::pushDeferScope(AstNodeRef scopeRef, AstNodeRef breakOwnerRef, AstNodeRef switchCaseRef)
{
    if (!hasDeferredStatements_)
        return;

    if (scopeRef.isValid())
        scopeRef = resolvedNodeRef(scopeRef);
    if (breakOwnerRef.isValid())
        breakOwnerRef = resolvedNodeRef(breakOwnerRef);
    if (switchCaseRef.isValid())
        switchCaseRef = resolvedNodeRef(switchCaseRef);

    CodeGenDeferScope deferScope;
    deferScope.scopeRef      = scopeRef;
    deferScope.breakOwnerRef = breakOwnerRef;
    deferScope.switchCaseRef = switchCaseRef;
    deferScopes_.push_back(std::move(deferScope));
}

void CodeGen::registerDefer(const AstNodeRef deferStmtRef, const AstNodeRef bodyRef, const AstModifierFlags modifierFlags)
{
    if (!hasDeferredStatements_)
        return;

    SWC_ASSERT(!deferScopes_.empty());
    if (deferScopes_.empty())
        return;

    auto& action         = deferScopes_.back().actions.emplace_back();
    action.kind          = CodeGenDeferredAction::Kind::DeferStmt;
    action.deferStmtRef  = resolvedNodeRef(deferStmtRef);
    action.bodyRef       = resolvedNodeRef(bodyRef);
    action.modifierFlags = modifierFlags;
}

void CodeGen::registerImplicitDrop(const SymbolVariable& symVar)
{
    if (!hasDeferredStatements_)
        return;
    if (symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal))
        return;
    if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
    {
        if (CodeGenFunctionHelpers::isBorrowedIndirectParameter(*this, function(), symVar))
            return;
        if (!symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) &&
            !CodeGenFunctionHelpers::canUseIncomingIndirectParameterAsAddressableParameter(*this, function(), symVar))
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

    auto& action            = deferScopes_.back().actions.emplace_back();
    action.kind             = CodeGenDeferredAction::Kind::ImplicitDrop;
    action.variable         = &symVar;
    action.lifecycleTypeRef = symVar.typeRef();
    action.lifecycleKind    = LifecycleKind::Drop;
    action.modifierFlags    = AstModifierFlagsE::Zero;
}

void CodeGen::registerImplicitParameterDrops()
{
    for (const SymbolVariable* symVar : function().parameters())
    {
        if (symVar)
            registerImplicitDrop(*symVar);
    }
}

namespace
{
}

Result CodeGen::emitDeferredAction(const CodeGenDeferredAction& action)
{
    switch (action.kind)
    {
        case CodeGenDeferredAction::Kind::DeferStmt:
        {
            if (action.bodyRef.isInvalid())
                return Result::Continue;

            const bool needsErr   = action.modifierFlags.has(AstModifierFlagsE::Err);
            const bool needsNoErr = action.modifierFlags.has(AstModifierFlagsE::NoErr);
            if (!needsErr && !needsNoErr)
                return emitNodeNow(action.bodyRef);

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
            SWC_RESULT(emitNodeNow(action.bodyRef));
            builder.placeLabel(skipLabel);
            return Result::Continue;
        }

        case CodeGenDeferredAction::Kind::ImplicitDrop:
        {
            if (!action.variable || action.lifecycleTypeRef.isInvalid())
                return Result::Continue;

            CodeGenNodePayload variablePayload;
            if (!resolveDeferredVariableAddress(*this, *action.variable, variablePayload))
                return Result::Continue;

            return emitLifecycle(action.lifecycleTypeRef, action.lifecycleKind, variablePayload.reg);
        }
    }

    return Result::Continue;
}

Result CodeGen::emitDeferredActionsInScope(const size_t scopeIndex, const size_t actionCount)
{
    SWC_ASSERT(scopeIndex < deferScopes_.size());
    if (scopeIndex >= deferScopes_.size())
        return Result::Continue;

    const auto&  deferScope         = deferScopes_[scopeIndex];
    const size_t clampedActionCount = std::min(actionCount, deferScope.actions.size());
    deferredEmissionCursors_.push_back({.scopeIndex = scopeIndex, .nextActionCount = clampedActionCount});

    auto result = Result::Continue;
    for (size_t i = clampedActionCount; i != 0; --i)
    {
        deferredEmissionCursors_.back().nextActionCount = i - 1;
        const auto& action                              = deferScope.actions[i - 1];
        result                                          = emitDeferredAction(action);
        if (result != Result::Continue)
            break;
    }

    deferredEmissionCursors_.pop_back();
    return result;
}

Result CodeGen::emitDeferredActionsFrom(const size_t startScopeIndex, const size_t startActionCount, const size_t stopScopeIndex, const bool hasStopScope)
{
    if (startScopeIndex >= deferScopes_.size())
        return Result::Continue;

    for (size_t scopeCursor = startScopeIndex + 1; scopeCursor != 0; --scopeCursor)
    {
        const size_t scopeIndex  = scopeCursor - 1;
        const size_t actionCount = scopeIndex == startScopeIndex ? startActionCount : deferScopes_[scopeIndex].actions.size();
        SWC_RESULT(emitDeferredActionsInScope(scopeIndex, actionCount));
        if (hasStopScope && scopeIndex == stopScopeIndex)
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

    const CodeGenDeferScope deferScope = std::move(deferScopes_.back());
    deferScopes_.pop_back();

    if (currentInstructionBlocksFallthrough())
        return Result::Continue;

    for (size_t i = deferScope.actions.size(); i != 0; --i)
        SWC_RESULT(emitDeferredAction(deferScope.actions[i - 1]));
    return Result::Continue;
}

Result CodeGen::emitDeferredActionsForReturn()
{
    if (!hasDeferredStatements_)
        return Result::Continue;

    if (deferScopes_.empty())
        return Result::Continue;

    if (!deferredEmissionCursors_.empty())
    {
        const auto& cursor = deferredEmissionCursors_.back();
        return emitDeferredActionsFrom(cursor.scopeIndex, cursor.nextActionCount, 0, false);
    }

    return emitDeferredActionsFrom(deferScopes_.size() - 1, deferScopes_.back().actions.size(), 0, false);
}

Result CodeGen::emitDeferredActionsUntilScopeRef(AstNodeRef scopeRef)
{
    if (!hasDeferredStatements_)
        return Result::Continue;

    scopeRef = resolvedNodeRef(scopeRef);
    if (scopeRef.isInvalid())
        return Result::Continue;

    size_t stopScopeIndex = 0;
    if (!findInnermostDeferScopeIndex(scopeRef, stopScopeIndex))
        return Result::Continue;

    if (!deferredEmissionCursors_.empty())
    {
        const auto& cursor = deferredEmissionCursors_.back();
        return emitDeferredActionsFrom(cursor.scopeIndex, cursor.nextActionCount, stopScopeIndex, true);
    }

    return emitDeferredActionsFrom(deferScopes_.size() - 1, deferScopes_.back().actions.size(), stopScopeIndex, true);
}

Result CodeGen::emitDeferredActionsUntilBreakOwner(AstNodeRef breakOwnerRef)
{
    if (!hasDeferredStatements_)
        return Result::Continue;

    breakOwnerRef = resolvedNodeRef(breakOwnerRef);
    if (breakOwnerRef.isInvalid())
        return Result::Continue;

    size_t stopScopeIndex = 0;
    bool   foundStopScope = false;
    for (size_t i = deferScopes_.size(); i != 0; --i)
    {
        if (deferScopes_[i - 1].breakOwnerRef == breakOwnerRef)
        {
            stopScopeIndex = i - 1;
            foundStopScope = true;
            break;
        }
    }

    if (!foundStopScope)
        return Result::Continue;

    if (!deferredEmissionCursors_.empty())
    {
        const auto& cursor = deferredEmissionCursors_.back();
        return emitDeferredActionsFrom(cursor.scopeIndex, cursor.nextActionCount, stopScopeIndex, true);
    }

    return emitDeferredActionsFrom(deferScopes_.size() - 1, deferScopes_.back().actions.size(), stopScopeIndex, true);
}

Result CodeGen::emitDeferredActionsUntilSwitchCase(AstNodeRef switchCaseRef)
{
    if (!hasDeferredStatements_)
        return Result::Continue;

    switchCaseRef = resolvedNodeRef(switchCaseRef);
    if (switchCaseRef.isInvalid())
        return Result::Continue;

    size_t stopScopeIndex = 0;
    bool   foundStopScope = false;
    for (size_t i = deferScopes_.size(); i != 0; --i)
    {
        if (deferScopes_[i - 1].switchCaseRef == switchCaseRef)
        {
            stopScopeIndex = i - 1;
            foundStopScope = true;
            break;
        }
    }

    if (!foundStopScope)
        return Result::Continue;

    if (!deferredEmissionCursors_.empty())
    {
        const auto& cursor = deferredEmissionCursors_.back();
        return emitDeferredActionsFrom(cursor.scopeIndex, cursor.nextActionCount, stopScopeIndex, true);
    }

    return emitDeferredActionsFrom(deferScopes_.size() - 1, deferScopes_.back().actions.size(), stopScopeIndex, true);
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

    if (inst->op == MicroInstrOpcode::Ret || inst->op == MicroInstrOpcode::JumpReg)
        return true;

    const MicroInstrOperand* ops = inst->ops(builder().operands());
    return ops && MicroInstrInfo::isUnconditionalJumpInstruction(*inst, ops);
}

void CodeGen::invalidateNodePayloadRegs(AstNodeRef nodeRef)
{
    if (nodeRef.isInvalid())
        return;

    SmallVector<AstNodeRef> stack;
    stack.push_back(nodeRef);
    while (!stack.empty())
    {
        const AstNodeRef currentRef = stack.back();
        stack.pop_back();

        if (CodeGenNodePayload* payload = safePayload(currentRef))
            payload->reg = MicroReg::invalid();

        SmallVector<AstNodeRef> children;
        node(currentRef).collectChildrenFromAst(children, ast());
        for (const AstNodeRef childRef : children)
        {
            if (childRef.isValid())
                stack.push_back(childRef);
        }
    }
}

bool CodeGen::containsNodeId(AstNodeRef nodeRef, const AstNodeId nodeId)
{
    if (nodeRef.isInvalid())
        return false;

    std::unordered_set<AstNodeRef> visited;
    SmallVector<AstNodeRef>        stack;
    stack.push_back(nodeRef);
    while (!stack.empty())
    {
        const AstNodeRef rawRef = stack.back();
        stack.pop_back();

        const AstNodeRef currentRef = sema().viewZero(rawRef).nodeRef();
        if (currentRef.isInvalid())
            continue;
        if (!visited.insert(currentRef).second)
            continue;

        const AstNode& currentNode = ast().node(currentRef);
        if (currentNode.id() == nodeId)
            return true;

        SmallVector<AstNodeRef> children;
        currentNode.collectChildrenFromAst(children, ast());
        for (const AstNodeRef childRef : children)
        {
            if (childRef.isValid())
                stack.push_back(childRef);
        }
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

void CodeGen::clearGvtdScratchLayout()
{
    gvtdScratchEntries_.clear();
    gvtdScratchOffset_ = 0;
    gvtdScratchSize_   = 0;
}

void CodeGen::setGvtdScratchLayout(uint32_t offset, uint32_t size, std::span<const CodeGenGvtdEntry> entries)
{
    gvtdScratchOffset_ = offset;
    gvtdScratchSize_   = size;
    gvtdScratchEntries_.clear();
    gvtdScratchEntries_.reserve(entries.size());
    for (const auto& entry : entries)
        gvtdScratchEntries_.push_back(entry);
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
    if (typeRef.isValid())
    {
        const TypeInfo& typeInfo        = typeMgr().get(typeRef);
        TypeRef         resolvedTypeRef = typeRef;
        if (typeInfo.isAlias())
            resolvedTypeRef = typeInfo.unwrapAliasEnum(ctx(), typeRef);

        const TypeInfo& resolvedTypeInfo = typeMgr().get(resolvedTypeRef);
        if (resolvedTypeInfo.isFloat())
            return nextVirtualFloatRegister();
    }

    return nextVirtualIntRegister();
}

void CodeGen::setVisitors()
{
    visit_.setMode(AstVisitMode::ResolveBeforeCallbacks);
    visit_.setNodeRefResolver([this](const AstNodeRef nodeRef) { return sema().viewZero(nodeRef).nodeRef(); });
    visit_.setPreNodeVisitor([this](AstNode& node) { return preNode(node); });
    visit_.setPreChildVisitor([this](AstNode& node, AstNodeRef& childRef) { return preNodeChild(node, childRef); });
    visit_.setPostChildVisitor([this](AstNode& node, AstNodeRef& childRef) { return postNodeChild(node, childRef); });
    visit_.setPostNodeVisitor([this](AstNode& node) { return postNode(node); });
}

Result CodeGen::preNode(AstNode& node)
{
    builder().setCurrentDebugSourceCodeRef(node.codeRef());
    if (node.id() == AstNodeId::Attribute)
        return Result::SkipChildren;

    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    SWC_RESULT(info.codeGenPreNode(*this, node));

    const AstNodeRef currentNodeRef = curNodeRef();
    if (const SemaInlinePayload* inlinePayload = sema().inlinePayload(currentNodeRef);
        inlinePayload && inlinePayload->inlineRootRef == currentNodeRef)
    {
        CodeGenFrame frame = this->frame();
        frame.setCurrentInlineContext(currentNodeRef, inlinePayload, MicroLabelRef::invalid());
        pushFrame(frame);
    }
    else if (const auto* inlineOverride = sema().inlineContextOverride<SemaInlineContextOverride>(currentNodeRef))
    {
        CodeGenFrame frame = this->frame();
        if (const SemaInlinePayload* targetInlinePayload = inlineOverride->targetInlinePayload)
        {
            const MicroLabelRef doneLabel = findMatchingInlineDoneLabel(frames(), targetInlinePayload->inlineRootRef, targetInlinePayload);
            frame.setCurrentInlineContext(targetInlinePayload->inlineRootRef, targetInlinePayload, doneLabel);
            // When no matching frame is found in the frame stack, we are inside a locally
            // compiled function (e.g., a local function inside a macro expansion). In that
            // case, any doneLabel created by emitInlineReturn must be placed at this boundary
            // since the outer expansion won't do it.
            frame.currentInlineContextRef().noOuterDoneLabel = !hasMatchingInlineFrame(frames(), targetInlinePayload->inlineRootRef, targetInlinePayload);
        }
        else
        {
            frame.clearCurrentInlineContext();
        }

        frame.setCurrentInlineBoundaryRootRef(currentNodeRef);
        pushFrame(frame);
    }

    if (curViewConstant().hasConstant())
        return Result::SkipChildren;

    return Result::Continue;
}

Result CodeGen::postNode(AstNode& node)
{
    builder().setCurrentDebugSourceCodeRef(node.codeRef());
    auto result = Result::Continue;
    if (curViewConstant().hasConstant())
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
                const SymbolVariable& resultVar = *inlineCtx.payload->resultVar;
                SWC_ASSERT(resultVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack));
                SWC_ASSERT(localStackBaseReg().isValid());

                inlineNodePayload.setIsAddress();
                inlineNodePayload.reg = offsetAddressReg(localStackBaseReg(), resultVar.offset());
            }
        }
        else if (frame().hasCurrentInlineContext() && frame().currentInlineContext().noOuterDoneLabel)
        {
            // When the inline boundary is inside a locally compiled function (e.g., a local
            // function inside a macro expansion), the inline root lives in the caller's AST
            // context and rootNodeRef won't match curNodeRef. Any doneLabel created by
            // emitInlineReturn for a 'return' inside the injected code must still be placed
            // at the boundary so jumps to it resolve correctly. We only do this when
            // noOuterDoneLabel is set, meaning no matching outer label was found in preNode,
            // so the outer expansion won't place it.
            const MicroLabelRef doneLabel = frame().currentInlineContext().doneLabel;
            if (doneLabel.isValid())
                builder().placeLabel(doneLabel);
        }

        popFrame();
    }

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
