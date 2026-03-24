#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroReg.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
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
            payload = codeGen.compiler().allocate<VariableSymbolCodeGenPayload>();
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

}

void CodeGenFrame::setCurrentBreakContent(AstNodeRef nodeRef, BreakContextKind kind)
{
    breakable_.nodeRef          = nodeRef;
    breakable_.kind             = kind;
    currentLoopHasContinueJump_ = false;
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
        hasDeferredStatements_            = containsNodeId(root, AstNodeId::DeferStmt);
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
    nodeRef = resolvedNodeRef(nodeRef);
    if (nodeRef.isInvalid())
        return nullptr;
    return sema().codeGenPayload<CodeGenNodePayload>(nodeRef);
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
    return dstPayload;
}

CodeGenNodePayload& CodeGen::setPayload(AstNodeRef nodeRef, TypeRef typeRef)
{
    nodeRef = resolvedNodeRef(nodeRef);
    SWC_ASSERT(nodeRef.isValid());

    CodeGenNodePayload* nodePayload = safePayload(nodeRef);
    if (!nodePayload)
    {
        nodePayload                    = compiler().allocate<CodeGenNodePayload>();
        nodePayload->runtimeStorageSym = nullptr;
        sema().setCodeGenPayload(nodeRef, nodePayload);
    }

    nodePayload->reg         = nextVirtualRegister();
    nodePayload->typeRef     = typeRef;
    nodePayload->storageKind = CodeGenNodePayload::StorageKind::Value;
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
    action.deferStmtRef  = resolvedNodeRef(deferStmtRef);
    action.bodyRef       = resolvedNodeRef(bodyRef);
    action.modifierFlags = modifierFlags;
}

namespace
{
    Result emitDeferredActions(CodeGen& codeGen, const CodeGenDeferScope& deferScope)
    {
        for (size_t i = deferScope.actions.size(); i != 0; --i)
        {
            const auto& action = deferScope.actions[i - 1];
            SWC_ASSERT(action.modifierFlags == AstModifierFlagsE::Zero);
            if (action.bodyRef.isInvalid())
                continue;

            SWC_RESULT(codeGen.emitNodeNow(action.bodyRef));
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

    CodeGenDeferScope deferScope = std::move(deferScopes_.back());
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

bool CodeGen::containsNodeId(AstNodeRef nodeRef, const AstNodeId nodeId) const
{
    if (nodeRef.isInvalid())
        return false;

    SmallVector<AstNodeRef> stack;
    stack.push_back(nodeRef);
    while (!stack.empty())
    {
        const AstNodeRef currentRef = stack.back();
        stack.pop_back();

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

    const SemaInlinePayload* inlinePayload = sema().semaPayload<SemaInlinePayload>(curNodeRef());
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
