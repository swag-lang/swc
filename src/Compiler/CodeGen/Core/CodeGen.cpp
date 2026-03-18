#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroReg.h"
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
        bool               hasPayload = false;
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
        clearGvtdScratchLayout();
        frames_.clear();
        frames_.emplace_back();
        symbolFunc.setDebugStackFrameSize(0);
        symbolFunc.setDebugStackBaseReg(MicroReg::invalid());

        for (SymbolVariable* symVar : symbolFunc.parameters())
        {
            SWC_ASSERT(symVar != nullptr);
            if (VariableSymbolCodeGenPayload* payload = safeVariableSymbolPayload(*symVar))
                payload->hasPayload = false;
            symVar->setCodeGenLocalSize(0);
            symVar->setDebugStackSlotOffset(0);
            symVar->setDebugStackSlotSize(0);
        }

        for (SymbolVariable* symVar : symbolFunc.localVariables())
        {
            SWC_ASSERT(symVar != nullptr);
            if (VariableSymbolCodeGenPayload* payload = safeVariableSymbolPayload(*symVar))
                payload->hasPayload = false;
            symVar->removeExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack);
        }

        MicroBuilderFlags        builderFlags    = MicroBuilderFlagsE::Zero;
        const AttributeList&     attributes      = symbolFunc.attributes();
        Runtime::BuildCfgBackend backendBuildCfg = compiler().buildCfg().backend;
        if (attributes.backendOptimize.has_value())
            backendBuildCfg.optimize = attributes.backendOptimize.value();

        builder_->setBackendBuildCfg(backendBuildCfg);
        if (compiler().buildCfg().backend.debugInfo)
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
}

const CodeGenNodePayload* CodeGen::variablePayload(const SymbolVariable& sym)
{
    const VariableSymbolCodeGenPayload* symbolPayload = safeVariableSymbolPayload(sym);
    if (!symbolPayload || !symbolPayload->hasPayload)
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
        nodePayload = compiler().allocate<CodeGenNodePayload>();
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

CodeGenNodePayload CodeGen::resolveLocalStackPayload(const SymbolVariable& sym)
{
    if (const CodeGenNodePayload* symbolPayload = variablePayload(sym))
        return *symbolPayload;

    SWC_ASSERT(localStackBaseReg().isValid());

    // Stack-backed symbols are reused heavily during codegen, so cache the computed
    // address payload once instead of rebuilding the same base+offset sequence.
    CodeGenNodePayload localPayload;
    localPayload.typeRef = sym.typeRef();
    localPayload.setIsAddress();
    localPayload.reg = offsetAddressReg(localStackBaseReg(), sym.offset());
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
    const CodeGenNodePayload storagePayload = resolveLocalStackPayload(*(nodePayload->runtimeStorageSym));
    SWC_ASSERT(storagePayload.isAddress());
    return storagePayload.reg;
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
