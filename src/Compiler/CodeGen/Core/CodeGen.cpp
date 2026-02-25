#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroReg.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    std::atomic<uint64_t> CODE_GEN_RUN_ID = 1;

    uint64_t nextCodeGenRunId()
    {
        const uint64_t runId = CODE_GEN_RUN_ID.fetch_add(1, std::memory_order_relaxed);
        SWC_ASSERT(runId != 0);
        return runId;
    }
}

CodeGen::CodeGen(Sema& sema) :
    sema_(&sema)
{
    setVisitors();
}

Result CodeGen::exec(SymbolFunction& symbolFunc, AstNodeRef root)
{
    visit_.start(ast(), root);
    function_ = &symbolFunc;
    builder_  = &symbolFunc.microInstrBuilder(ctx());

    nextVirtualRegister_ = 1;
    localStackFrameSize_ = 0;
    localStackBaseReg_   = MicroReg::invalid();
    runId_               = nextCodeGenRunId();
    frames_.clear();
    frames_.push_back({});

    MicroBuilderFlags        builderFlags    = MicroBuilderFlagsE::Zero;
    const auto&              attributes      = symbolFunc.attributes();
    Runtime::BuildCfgBackend backendBuildCfg = compiler().buildCfg().backend;
    if (attributes.backendOptimize.has_value())
        backendBuildCfg.optimize = attributes.backendOptimize.value();

    builder_->setPrintPassOptions(symbolFunc.attributes().printMicroPassOptions);
    builder_->setBackendBuildCfg(backendBuildCfg);
    if (compiler().buildCfg().backendDebugInformations)
        builderFlags.add(MicroBuilderFlagsE::DebugInfo);
    builder_->setFlags(builderFlags);
    builder_->setCurrentDebugInfo({});

    const SourceCodeRange codeRange = symbolFunc.codeRange(ctx());
    const SourceView&     srcView   = this->srcView(symbolFunc.srcViewRef());
    const SourceFile*     file      = srcView.file();
    const Utf8            fileName  = file ? FileSystem::formatFileName(&ctx(), file->path()) : Utf8{};
    builder_->setPrintLocation(symbolFunc.getFullScopedName(ctx()), fileName, codeRange.line);

    while (true)
    {
        const AstNodeRef    currentNodeRef = visit_.currentNodeRef();
        const SourceCodeRef currentCodeRef = currentNodeRef.isValid() ? node(currentNodeRef).codeRef() : symbolFunc.codeRef();
        ctx().state().setCodeGenParsing(&symbolFunc, currentNodeRef, currentCodeRef);

        const AstVisitResult result = visit_.step(ctx());
        if (result == AstVisitResult::Pause)
            return Result::Pause;
        if (result == AstVisitResult::Error)
            return Result::Error;
        if (result == AstVisitResult::Stop)
            return Result::Continue;
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

CodeGenNodePayload* CodeGen::safePayload(AstNodeRef nodeRef)
{
    nodeRef = resolvedNodeRef(nodeRef);
    if (nodeRef.isInvalid())
        return nullptr;
    return sema().codeGenPayload<CodeGenNodePayload>(nodeRef);
}

CodeGenNodePayload& CodeGen::payload(AstNodeRef nodeRef)
{
    return *SWC_CHECK_NOT_NULL(safePayload(nodeRef));
}

CodeGen::VariableSymbolCodeGenPayload* CodeGen::safeVariableSymbolPayload(const SymbolVariable& sym) const
{
    return static_cast<VariableSymbolCodeGenPayload*>(sym.codeGenPayload());
}

CodeGen::VariableSymbolCodeGenPayload& CodeGen::ensureVariableSymbolPayload(const SymbolVariable& sym)
{
    VariableSymbolCodeGenPayload* payload = safeVariableSymbolPayload(sym);
    if (!payload)
    {
        payload = compiler().allocate<VariableSymbolCodeGenPayload>();
        const_cast<SymbolVariable&>(sym).setCodeGenPayload(payload);
    }

    return *SWC_CHECK_NOT_NULL(payload);
}

void CodeGen::setVariablePayload(const SymbolVariable& sym, const CodeGenNodePayload& payload)
{
    VariableSymbolCodeGenPayload& symbolPayload = ensureVariableSymbolPayload(sym);
    symbolPayload.runId                         = runId_;
    symbolPayload.payload                       = payload;
    symbolPayload.hasPayload                    = true;
}

const CodeGenNodePayload* CodeGen::variablePayload(const SymbolVariable& sym) const
{
    const VariableSymbolCodeGenPayload* symbolPayload = safeVariableSymbolPayload(sym);
    if (!symbolPayload || symbolPayload->runId != runId_ || !symbolPayload->hasPayload)
        return nullptr;
    return &symbolPayload->payload;
}

void CodeGen::setLocalStackSlot(const SymbolVariable& sym, const LocalStackSlot& slot)
{
    VariableSymbolCodeGenPayload& symbolPayload = ensureVariableSymbolPayload(sym);
    symbolPayload.runId                         = runId_;
    symbolPayload.localSlot                     = slot;
    symbolPayload.hasLocalSlot                  = true;
}

const CodeGen::LocalStackSlot* CodeGen::localStackSlot(const SymbolVariable& sym) const
{
    const VariableSymbolCodeGenPayload* symbolPayload = safeVariableSymbolPayload(sym);
    if (!symbolPayload || symbolPayload->runId != runId_ || !symbolPayload->hasLocalSlot)
        return nullptr;
    return &symbolPayload->localSlot;
}

CodeGenNodePayload& CodeGen::inheritPayload(AstNodeRef dstNodeRef, AstNodeRef srcNodeRef, TypeRef typeRef)
{
    srcNodeRef = resolvedNodeRef(srcNodeRef);

    const CodeGenNodePayload srcPayloadCopy = payload(srcNodeRef);

    if (typeRef.isInvalid())
        typeRef = srcPayloadCopy.typeRef;

    auto& dstPayload       = setPayload(dstNodeRef, typeRef);
    dstPayload.reg         = srcPayloadCopy.reg;
    dstPayload.storageKind = srcPayloadCopy.storageKind;
    return dstPayload;
}

CodeGenNodePayload& CodeGen::setPayload(AstNodeRef nodeRef, TypeRef typeRef)
{
    nodeRef = resolvedNodeRef(nodeRef);
    SWC_ASSERT(nodeRef.isValid());

    CodeGenNodePayload* nodePayload = safePayload(nodeRef);
    if (!nodePayload)
    {
        nodePayload = compiler().allocate<CodeGenNodePayload>();
        sema().setCodeGenPayload(nodeRef, nodePayload);
    }

    nodePayload->reg         = nextVirtualRegister();
    nodePayload->typeRef     = typeRef;
    nodePayload->storageKind = CodeGenNodePayload::StorageKind::Value;
    return *SWC_CHECK_NOT_NULL(nodePayload);
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

CodeGen::IfStmtCodeGenState& CodeGen::setIfStmtCodeGenState(AstNodeRef nodeRef, const IfStmtCodeGenState& value)
{
    nodeRef = resolvedNodeRef(nodeRef);
    SWC_ASSERT(nodeRef.isValid());

    IfStmtCodeGenPayload* payload = sema().codeGenPayload<IfStmtCodeGenPayload>(nodeRef);
    if (!payload)
    {
        payload = compiler().allocate<IfStmtCodeGenPayload>();
        sema().setCodeGenPayload(nodeRef, payload);
    }

    payload->runId = runId_;
    payload->state = value;
    return payload->state;
}

CodeGen::IfStmtCodeGenState* CodeGen::ifStmtCodeGenState(AstNodeRef nodeRef)
{
    nodeRef = resolvedNodeRef(nodeRef);
    if (nodeRef.isInvalid())
        return nullptr;

    IfStmtCodeGenPayload* payload = sema().codeGenPayload<IfStmtCodeGenPayload>(nodeRef);
    if (!payload || payload->runId != runId_)
        return nullptr;
    return &payload->state;
}

void CodeGen::eraseIfStmtCodeGenState(AstNodeRef nodeRef)
{
    nodeRef = resolvedNodeRef(nodeRef);
    if (nodeRef.isInvalid())
        return;

    IfStmtCodeGenPayload* payload = sema().codeGenPayload<IfStmtCodeGenPayload>(nodeRef);
    if (!payload || payload->runId != runId_)
        return;

    payload->state = {};
    payload->runId = 0;
}

CodeGen::SwitchStmtCodeGenState& CodeGen::setSwitchStmtCodeGenState(AstNodeRef nodeRef, const SwitchStmtCodeGenState& value)
{
    nodeRef = resolvedNodeRef(nodeRef);
    SWC_ASSERT(nodeRef.isValid());

    SwitchStmtCodeGenPayload* payload = sema().codeGenPayload<SwitchStmtCodeGenPayload>(nodeRef);
    if (!payload)
    {
        payload = compiler().allocate<SwitchStmtCodeGenPayload>();
        sema().setCodeGenPayload(nodeRef, payload);
    }

    payload->runId = runId_;
    payload->state = value;
    return payload->state;
}

CodeGen::SwitchStmtCodeGenState* CodeGen::switchStmtCodeGenState(AstNodeRef nodeRef)
{
    nodeRef = resolvedNodeRef(nodeRef);
    if (nodeRef.isInvalid())
        return nullptr;

    SwitchStmtCodeGenPayload* payload = sema().codeGenPayload<SwitchStmtCodeGenPayload>(nodeRef);
    if (!payload || payload->runId != runId_)
        return nullptr;
    return &payload->state;
}

void CodeGen::eraseSwitchStmtCodeGenState(AstNodeRef nodeRef)
{
    nodeRef = resolvedNodeRef(nodeRef);
    if (nodeRef.isInvalid())
        return;

    SwitchStmtCodeGenPayload* payload = sema().codeGenPayload<SwitchStmtCodeGenPayload>(nodeRef);
    if (!payload || payload->runId != runId_)
        return;

    payload->state = {};
    payload->runId = 0;
}

void CodeGen::pushFrame(const CodeGenFrame& frame)
{
    frames_.push_back(frame);
}

void CodeGen::popFrame()
{
    SWC_ASSERT(!frames_.empty());
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
    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    RESULT_VERIFY(info.codeGenPreNode(*this, node));

    if (curViewConstant().hasConstant())
        return Result::SkipChildren;

    return Result::Continue;
}

Result CodeGen::postNode(AstNode& node)
{
    builder().setCurrentDebugSourceCodeRef(node.codeRef());
    if (curViewConstant().hasConstant())
        return emitConstant(curNodeRef());

    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    RESULT_VERIFY(info.codeGenPostNode(*this, node));
    return Result::Continue;
}

Result CodeGen::preNodeChild(AstNode& node, AstNodeRef& childRef)
{
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
