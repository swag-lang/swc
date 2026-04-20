#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/ABICall.h"
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
#include "Main/FileSystem.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct VariableSymbolCodeGenPayload
    {
        CodeGenNodePayload payload;
        bool               hasPayload        = false;
        uint32_t           addressGeneration = 0;
    };

    VariableSymbolCodeGenPayload* safeVariableSymbolPayload(const SymbolVariable& sym)
    {
        return static_cast<VariableSymbolCodeGenPayload*>(sym.codeGenPayload());
    }

    VariableSymbolCodeGenPayload& ensureVariableSymbolPayload(CodeGen& codeGen, const SymbolVariable& sym)
    {
        VariableSymbolCodeGenPayload* payload = safeVariableSymbolPayload(sym);
        if (!payload)
        {
            payload  = codeGen.compiler().allocate<VariableSymbolCodeGenPayload>();
            *payload = {};
            sym.setCodeGenPayload(payload);
        }

        return *(payload);
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

    void mergeSupplementalNodePayloadMetadata(CodeGenNodePayload& dst, const CodeGenNodePayload& src)
    {
        if (!dst.runtimeStorageSym && src.runtimeStorageSym)
            dst.runtimeStorageSym = src.runtimeStorageSym;
        if (!dst.runtimeFunctionSymbol && src.runtimeFunctionSymbol)
            dst.runtimeFunctionSymbol = src.runtimeFunctionSymbol;
        if (!dst.runtimeArrayFillTypeRef.isValid() && src.runtimeArrayFillTypeRef.isValid())
            dst.runtimeArrayFillTypeRef = src.runtimeArrayFillTypeRef;
        if (!dst.runtimeArrayFillCstRef.isValid() && src.runtimeArrayFillCstRef.isValid())
            dst.runtimeArrayFillCstRef = src.runtimeArrayFillCstRef;
        dst.runtimeSafetyMask |= src.runtimeSafetyMask;
        if (!dst.hasThrowableWrapper() && src.hasThrowableWrapper())
        {
            dst.throwableWrapperOwnerRef = src.throwableWrapperOwnerRef;
            dst.throwableWrapperTokenId  = src.throwableWrapperTokenId;
            dst.throwableFailLabel       = src.throwableFailLabel;
            dst.throwableDoneLabel       = src.throwableDoneLabel;
        }
        if (!dst.hasThrowableFunctionTarget() && src.hasThrowableFunctionTarget())
        {
            dst.throwableFunctionFailLabel = src.throwableFunctionFailLabel;
            dst.throwableFunctionDoneLabel = src.throwableFunctionDoneLabel;
        }
    }

    SymbolFunction* resolveDirectLifecycleFunction(const TypeInfo& typeInfo, const CodeGenLifecycleKind lifecycleKind)
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

    bool tryBuildLifecycleActionRec(const CodeGen&               codeGen,
                                    TypeRef                      typeRef,
                                    const CodeGen::LifecycleKind lifecycleKind,
                                    SymbolFunction*&             outFunction,
                                    uint32_t&                    outSizeOf,
                                    uint32_t&                    outCount)
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

            SymbolFunction* elemFunction = nullptr;
            uint32_t        elemSizeOf   = 0;
            uint32_t        elemCount    = 0;
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

        SymbolFunction* lifecycleFunction = resolveDirectLifecycleFunction(typeInfo, lifecycleKind);

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

        SymbolFunction* directLifecycle = resolveDirectLifecycleFunction(typeInfo, lifecycleKind);
        const auto&     fields          = typeInfo.payloadSymStruct().fields();

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
            if (symVar && codeGen.hasLifecycle(symVar->typeRef(), CodeGen::LifecycleKind::Drop))
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
    breakable_.nodeRef          = nodeRef;
    breakable_.kind             = kind;
    currentLoopHasContinueJump_ = false;

    if (kind != BreakContextKind::Switch)
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

        nextVirtualRegister_              = 1;
        localStackFrameSize_              = 0;
        localStackBaseReg_                = MicroReg::invalid();
        currentFunctionIndirectReturnReg_ = MicroReg::invalid();
        currentFunctionClosureContextReg_ = MicroReg::invalid();
        deferScopes_.clear();
        deferredEmitDepth_                = 0;
        currentDeferredAddressGeneration_ = 0;
        nextDeferredAddressGeneration_    = 1;
        hasDeferredStatements_            = containsNodeId(root, AstNodeId::DeferStmt) || functionHasImplicitDrops(*this, symbolFunc);
        clearGvtdScratchLayout();
        frames_.clear();
        frames_.emplace_back();
        symbolFunc.setDebugStackFrameSize(0);
        symbolFunc.setDebugStackBaseReg(MicroReg::invalid());

        for (SymbolVariable* symVar : symbolFunc.parameters())
        {
            SWC_ASSERT(symVar != nullptr);
            if (VariableSymbolCodeGenPayload* payload = safeVariableSymbolPayload(*symVar))
            {
                payload->hasPayload        = false;
                payload->addressGeneration = 0;
            }
            symVar->removeExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack);
            symVar->setCodeGenLocalSize(0);
            symVar->setDebugStackSlotOffset(0);
            symVar->setDebugStackSlotSize(0);
        }

        for (SymbolVariable* symVar : symbolFunc.localVariables())
        {
            SWC_ASSERT(symVar != nullptr);
            if (VariableSymbolCodeGenPayload* payload = safeVariableSymbolPayload(*symVar))
            {
                payload->hasPayload        = false;
                payload->addressGeneration = 0;
            }
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
        const Utf8            fileName  = file ? FileSystem::formatFileName(&ctx(), file->path()) : Utf8{};
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

CodeGenNodePayload& CodeGen::payload(AstNodeRef nodeRef)
{
    CodeGenNodePayload* nodePayload = safePayload(nodeRef);
    SWC_ASSERT(nodePayload != nullptr);
    return *nodePayload;
}

CodeGenNodePayload* CodeGen::safePayload(AstNodeRef nodeRef)
{
    const AstNodeRef resolvedRef = resolvedNodeRef(nodeRef);
    if (resolvedRef.isInvalid())
        return nullptr;

    CodeGenNodePayload* payload = sema().codeGenPayload<CodeGenNodePayload>(resolvedRef);
    if (resolvedRef == nodeRef)
        return payload;

    CodeGenNodePayload* originalPayload = sema().codeGenPayload<CodeGenNodePayload>(nodeRef);
    if (!payload)
        return originalPayload;

    // Preserve sema-time metadata attached to the original syntax node when
    // codegen later operates on a substituted node.
    if (originalPayload && originalPayload != payload)
        mergeSupplementalNodePayloadMetadata(*payload, *originalPayload);

    return payload;
}

void CodeGen::setVariablePayload(const SymbolVariable& sym, const CodeGenNodePayload& payload)
{
    VariableSymbolCodeGenPayload& symbolPayload = ensureVariableSymbolPayload(*this, sym);
    symbolPayload.payload                       = payload;
    symbolPayload.hasPayload                    = true;
    symbolPayload.addressGeneration             = isStackAddressPayload(*this, sym, payload) ? currentDeferredAddressGeneration_ : 0;
}

const CodeGenNodePayload* CodeGen::variablePayload(const SymbolVariable& sym) const
{
    const VariableSymbolCodeGenPayload* symbolPayload = safeVariableSymbolPayload(sym);
    if (!symbolPayload || !symbolPayload->hasPayload)
        return nullptr;
    if (isStackAddressPayload(*this, sym, symbolPayload->payload) &&
        symbolPayload->addressGeneration != currentDeferredAddressGeneration_)
        return nullptr;
    return &symbolPayload->payload;
}

CodeGenNodePayload& CodeGen::inheritPayload(AstNodeRef dstNodeRef, AstNodeRef srcNodeRef, TypeRef typeRef)
{
    srcNodeRef = resolvedNodeRef(srcNodeRef);

    const CodeGenNodePayload srcPayloadCopy = payload(srcNodeRef);

    if (typeRef.isInvalid())
        typeRef = srcPayloadCopy.typeRef;

    CodeGenNodePayload& dstPayload = setPayload(dstNodeRef, typeRef);
    dstPayload.reg                 = srcPayloadCopy.reg;
    dstPayload.storageKind         = srcPayloadCopy.storageKind;
    if (srcPayloadCopy.hasMaterializedPointerLikeValue())
        dstPayload.markMaterializedPointerLikeValue();
    return dstPayload;
}

CodeGenNodePayload& CodeGen::setPayload(AstNodeRef nodeRef, TypeRef typeRef)
{
    nodeRef = resolvedNodeRef(nodeRef);
    SWC_ASSERT(nodeRef.isValid());

    CodeGenNodePayload* nodePayload = safePayload(nodeRef);
    if (!nodePayload)
    {
        nodePayload  = compiler().allocate<CodeGenNodePayload>();
        *nodePayload = {};
        sema().setCodeGenPayload(nodeRef, nodePayload);
    }

    nodePayload->reg         = nextVirtualRegister();
    nodePayload->typeRef     = typeRef;
    nodePayload->storageKind = CodeGenNodePayload::StorageKind::Value;
    nodePayload->clearMaterializedPointerLikeValue();
    return *(nodePayload);
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

MicroReg CodeGen::runtimeStorageAddressReg(AstNodeRef nodeRef)
{
    const CodeGenNodePayload* nodePayload = sema().codeGenPayload<CodeGenNodePayload>(nodeRef);
    if (!nodePayload)
        nodePayload = safePayload(nodeRef);
    SWC_ASSERT(nodePayload != nullptr);
    SWC_ASSERT(nodePayload->runtimeStorageSym != nullptr);
    if (CodeGenFunctionHelpers::usesCallerReturnStorage(*this, *nodePayload->runtimeStorageSym))
    {
        SWC_ASSERT(currentFunctionIndirectReturnReg().isValid());
        return currentFunctionIndirectReturnReg();
    }

    const CodeGenNodePayload storagePayload = resolveLocalStackPayload(*(nodePayload->runtimeStorageSym), !inDeferredEmission());
    SWC_ASSERT(storagePayload.isAddress());
    return storagePayload.reg;
}

bool CodeGen::tryBuildLifecycleAction(const TypeRef typeRef, const LifecycleKind lifecycleKind, SymbolFunction*& outFunction, uint32_t& outSizeOf, uint32_t& outCount) const
{
    return tryBuildLifecycleActionRec(*this, typeRef, lifecycleKind, outFunction, outSizeOf, outCount);
}

bool CodeGen::hasLifecycle(const TypeRef typeRef, const LifecycleKind lifecycleKind) const
{
    return hasLifecycleRec(*this, typeRef, lifecycleKind);
}

Result CodeGen::emitLifecycleAction(SymbolFunction& calledFunction, const MicroReg addressReg)
{
    SWC_ASSERT(addressReg.isValid());

    function().addCallDependency(&calledFunction);

    ABICall::PreparedArg preparedArg;
    preparedArg.srcReg      = addressReg;
    preparedArg.kind        = ABICall::PreparedArgKind::Direct;
    preparedArg.isFloat     = false;
    preparedArg.isSigned    = false;
    preparedArg.isAddressed = false;
    preparedArg.numBits     = 64;

    const CallConvKind          callConvKind = calledFunction.callConvKind();
    const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder(), callConvKind, std::span{&preparedArg, 1});
    if (calledFunction.isForeign())
        ABICall::callExtern(builder(), callConvKind, &calledFunction, preparedCall);
    else
        ABICall::callLocal(builder(), callConvKind, &calledFunction, preparedCall);

    return Result::Continue;
}

Result CodeGen::emitLifecycle(const TypeRef typeRef, const LifecycleKind lifecycleKind, const MicroReg addressReg)
{
    return emitLifecycleRec(*this, typeRef, lifecycleKind, addressReg);
}

Result CodeGen::emitLifecycleAction(SymbolFunction& calledFunction, const MicroReg addressReg, const uint32_t sizeOf, const uint32_t count)
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
    Result emitDeferredDeferStmt(CodeGen& codeGen, const CodeGenDeferredAction& action)
    {
        if (action.bodyRef.isInvalid())
            return Result::Continue;

        const bool needsErr   = action.modifierFlags.has(AstModifierFlagsE::Err);
        const bool needsNoErr = action.modifierFlags.has(AstModifierFlagsE::NoErr);
        if (!needsErr && !needsNoErr)
            return codeGen.emitNodeNow(action.bodyRef);

        const IdentifierRef idRef = codeGen.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::IsErrContext);
        SWC_ASSERT(idRef.isValid());
        if (idRef.isInvalid())
            return Result::Error;

        SymbolFunction* runtimeIsErrContext = codeGen.compiler().runtimeFunctionSymbol(idRef);
        SWC_ASSERT(runtimeIsErrContext != nullptr);
        if (!runtimeIsErrContext)
            return Result::Error;

        const MicroReg      errContextReg = codeGen.nextVirtualIntRegister();
        MicroBuilder&       builder       = codeGen.builder();
        const MicroLabelRef skipLabel     = builder.createLabel();
        SWC_RESULT(CodeGenCallHelpers::emitRuntimeCallWithDirectArgsToReg(codeGen, *runtimeIsErrContext, std::span<const MicroReg>{}, errContextReg));
        builder.emitCmpRegImm(errContextReg, ApInt(0, 64), MicroOpBits::B8);
        builder.emitJumpToLabel(needsErr ? MicroCond::Equal : MicroCond::NotEqual, MicroOpBits::B32, skipLabel);
        SWC_RESULT(codeGen.emitNodeNow(action.bodyRef));
        builder.placeLabel(skipLabel);
        return Result::Continue;
    }

    Result emitDeferredActions(CodeGen& codeGen, const CodeGenDeferScope& deferScope)
    {
        for (size_t i = deferScope.actions.size(); i != 0; --i)
        {
            const auto& action = deferScope.actions[i - 1];
            switch (action.kind)
            {
                case CodeGenDeferredAction::Kind::DeferStmt:
                    SWC_RESULT(emitDeferredDeferStmt(codeGen, action));
                    break;

                case CodeGenDeferredAction::Kind::ImplicitDrop:
                {
                    if (!action.variable || action.lifecycleTypeRef.isInvalid())
                        continue;

                    CodeGenNodePayload variablePayload;
                    if (!resolveDeferredVariableAddress(codeGen, *action.variable, variablePayload))
                        continue;

                    SWC_RESULT(codeGen.emitLifecycle(action.lifecycleTypeRef, action.lifecycleKind, variablePayload.reg));
                    break;
                }
            }
        }

        return Result::Continue;
    }
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

    return emitDeferredActions(*this, deferScope);
}

Result CodeGen::emitDeferredActionsForReturn()
{
    if (!hasDeferredStatements_)
        return Result::Continue;

    SmallVector<CodeGenDeferScope> pendingScopes;
    pendingScopes.reserve(deferScopes_.size());
    for (size_t i = deferScopes_.size(); i != 0; --i)
        pendingScopes.push_back(deferScopes_[i - 1]);

    for (const auto& deferScope : pendingScopes)
        SWC_RESULT(emitDeferredActions(*this, deferScope));
    return Result::Continue;
}

Result CodeGen::emitDeferredActionsUntilScopeRef(AstNodeRef scopeRef)
{
    if (!hasDeferredStatements_)
        return Result::Continue;

    scopeRef = resolvedNodeRef(scopeRef);
    if (scopeRef.isInvalid())
        return Result::Continue;

    SmallVector<CodeGenDeferScope> pendingScopes;
    for (size_t i = deferScopes_.size(); i != 0; --i)
    {
        const auto& deferScope = deferScopes_[i - 1];
        pendingScopes.push_back(deferScope);
        if (deferScope.scopeRef == scopeRef)
            break;
    }

    for (const auto& deferScope : pendingScopes)
        SWC_RESULT(emitDeferredActions(*this, deferScope));
    return Result::Continue;
}

Result CodeGen::emitDeferredActionsUntilBreakOwner(AstNodeRef breakOwnerRef)
{
    if (!hasDeferredStatements_)
        return Result::Continue;

    breakOwnerRef = resolvedNodeRef(breakOwnerRef);
    if (breakOwnerRef.isInvalid())
        return Result::Continue;

    SmallVector<CodeGenDeferScope> pendingScopes;
    for (size_t i = deferScopes_.size(); i != 0; --i)
    {
        const auto& deferScope = deferScopes_[i - 1];
        pendingScopes.push_back(deferScope);
        if (deferScope.breakOwnerRef == breakOwnerRef)
            break;
    }

    for (const auto& deferScope : pendingScopes)
        SWC_RESULT(emitDeferredActions(*this, deferScope));
    return Result::Continue;
}

Result CodeGen::emitDeferredActionsUntilSwitchCase(AstNodeRef switchCaseRef)
{
    if (!hasDeferredStatements_)
        return Result::Continue;

    switchCaseRef = resolvedNodeRef(switchCaseRef);
    if (switchCaseRef.isInvalid())
        return Result::Continue;

    SmallVector<CodeGenDeferScope> pendingScopes;
    for (size_t i = deferScopes_.size(); i != 0; --i)
    {
        const auto& deferScope = deferScopes_[i - 1];
        pendingScopes.push_back(deferScope);
        if (deferScope.switchCaseRef == switchCaseRef)
            break;
    }

    for (const auto& deferScope : pendingScopes)
        SWC_RESULT(emitDeferredActions(*this, deferScope));
    return Result::Continue;
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

        if (currentFrame.hasCurrentInlineContext() &&
            parentFrame.hasCurrentInlineContext() &&
            currentFrame.currentInlineContext().rootNodeRef == parentFrame.currentInlineContext().rootNodeRef &&
            currentFrame.currentInlineContext().payload == parentFrame.currentInlineContext().payload)
        {
            const MicroLabelRef childDoneLabel = currentFrame.currentInlineContext().doneLabel;
            if (childDoneLabel.isValid())
            {
                const MicroLabelRef parentDoneLabel = parentFrame.currentInlineContext().doneLabel;
                SWC_ASSERT(parentDoneLabel == MicroLabelRef::invalid() || parentDoneLabel == childDoneLabel);
                if (parentDoneLabel == MicroLabelRef::invalid())
                    parentFrame.setCurrentInlineDoneLabel(childDoneLabel);
            }
        }

        // Inline/macro expansion runs inside a copied frame. If that copy records a `continue`,
        // propagate the flag back so the enclosing loop still materializes its continue block.
        if (currentFrame.hasCurrentInlineContext() &&
            currentFrame.currentLoopHasContinueJump() &&
            currentFrame.currentBreakableKind() == CodeGenFrame::BreakContextKind::Loop &&
            parentFrame.currentBreakableKind() == currentFrame.currentBreakableKind() &&
            parentFrame.currentBreakContext().nodeRef == currentFrame.currentBreakContext().nodeRef &&
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
        const TypeInfo& typeInfo = typeMgr().get(typeRef);
        if (typeInfo.isFloat())
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

    const SemaInlinePayload* inlinePayload = sema().inlinePayload(curNodeRef());
    if (inlinePayload && inlinePayload->inlineRootRef == curNodeRef())
    {
        CodeGenFrame frame = this->frame();
        frame.setCurrentInlineContext(curNodeRef(), inlinePayload, MicroLabelRef::invalid());
        pushFrame(frame);
    }

    if (curViewConstant().hasConstant())
        return Result::SkipChildren;

    return Result::Continue;
}

Result CodeGen::postNode(AstNode& node)
{
    builder().setCurrentDebugSourceCodeRef(node.codeRef());
    if (curViewConstant().hasConstant())
    {
        SWC_RESULT(emitConstant(curNodeRef()));
    }
    else
    {
        const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
        SWC_RESULT(info.codeGenPostNode(*this, node));
    }

    if (frame().hasCurrentInlineContext() && frame().currentInlineContext().rootNodeRef == curNodeRef())
    {
        const CodeGenFrame::InlineContext inlineCtx = frame().currentInlineContext();
        SWC_ASSERT(inlineCtx.payload != nullptr);

        if (inlineCtx.doneLabel.isValid())
            builder().placeLabel(inlineCtx.doneLabel);

        auto* inlineNodePayload    = compiler().allocate<CodeGenNodePayload>();
        *inlineNodePayload         = {};
        inlineNodePayload->typeRef = inlineCtx.payload->returnTypeRef;
        if (inlineCtx.payload->returnTypeRef != typeMgr().typeVoid())
        {
            SWC_ASSERT(inlineCtx.payload->resultVar != nullptr);
            const SymbolVariable& resultVar = *inlineCtx.payload->resultVar;
            SWC_ASSERT(resultVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack));
            SWC_ASSERT(localStackBaseReg().isValid());

            inlineNodePayload->setIsAddress();
            inlineNodePayload->reg = offsetAddressReg(localStackBaseReg(), resultVar.offset());
        }
        sema().setCodeGenPayload(curNodeRef(), inlineNodePayload);

        popFrame();
    }

    return Result::Continue;
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
