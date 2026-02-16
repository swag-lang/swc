#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"
#include "Backend/CodeGen/Micro/MicroReg.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/CompilerInstance.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE();

CodeGen::CodeGen(Sema& sema) :
    sema_(&sema)
{
    setVisitors();
}

Result CodeGen::exec(SymbolFunction& symbolFunc, AstNodeRef root)
{
    visit_.start(ast(), root);
    function_                           = &symbolFunc;
    builder_                            = &symbolFunc.microInstrBuilder(ctx());
    MicroInstrBuilderFlags builderFlags = MicroInstrBuilderFlagsE::Zero;
    builder_->setPrintPassOptions(symbolFunc.attributes().printMicroPassOptions);
    if (ctx().compiler().buildCfg().backendDebugInformations)
        builderFlags.add(MicroInstrBuilderFlagsE::DebugInfo);
    builder_->setFlags(builderFlags);
    builder_->setCurrentDebugInfo({});
    const SourceCodeRange codeRange = symbolFunc.codeRange(ctx());
    const SourceView&     srcView   = sema().srcView(symbolFunc.srcViewRef());
    const SourceFile*     file      = srcView.file();
    builder_->setPrintLocation(symbolFunc.getFullScopedName(ctx()), file ? Utf8(file->path().string()) : Utf8{}, codeRange.line);

    while (true)
    {
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

Ast& CodeGen::ast()
{
    return sema().ast();
}

const Ast& CodeGen::ast() const
{
    return sema().ast();
}

SemaNodeView CodeGen::nodeView(AstNodeRef nodeRef)
{
    return {sema(), nodeRef};
}

SemaNodeView CodeGen::curNodeView()
{
    return nodeView(curNodeRef());
}

const Token& CodeGen::token(const SourceCodeRef& codeRef) const
{
    return sema().token(codeRef);
}

CodeGenNodePayload* CodeGen::payload(AstNodeRef nodeRef) const
{
    return sema().codeGenPayload<CodeGenNodePayload>(nodeRef);
}

CodeGenNodePayload& CodeGen::inheritPayload(AstNodeRef dstNodeRef, AstNodeRef srcNodeRef, TypeRef typeRef)
{
    const CodeGenNodePayload* srcPayload = payload(srcNodeRef);
    SWC_ASSERT(srcPayload != nullptr);

    if (typeRef.isInvalid())
        typeRef = srcPayload->typeRef;

    auto& dstPayload = setPayload(dstNodeRef, typeRef);
    dstPayload.reg   = srcPayload->reg;
    dstPayload.storageKind = srcPayload->storageKind;
    return dstPayload;
}

CodeGenNodePayload& CodeGen::setPayload(AstNodeRef nodeRef, TypeRef typeRef)
{
    CodeGenNodePayload* nodePayload = payload(nodeRef);
    if (!nodePayload)
    {
        nodePayload = sema().compiler().allocate<CodeGenNodePayload>();
        sema().setCodeGenPayload(nodeRef, nodePayload);
    }

    nodePayload->reg     = MicroReg::virtualReg(nextVirtualRegister());
    nodePayload->typeRef = typeRef;
    nodePayload->storageKind = CodeGenNodePayload::StorageKind::Value;
    return *SWC_CHECK_NOT_NULL(nodePayload);
}

void CodeGen::setVisitors()
{
    visit_.setPreNodeVisitor([this](AstNode& node) { return preNode(node); });
    visit_.setPreChildVisitor([this](AstNode& node, AstNodeRef& childRef) { return preNodeChild(node, childRef); });
    visit_.setPostChildVisitor([this](AstNode& node, AstNodeRef& childRef) { return postNodeChild(node, childRef); });
    visit_.setPostNodeVisitor([this](AstNode& node) { return postNode(node); });
}

Result CodeGen::preNode(AstNode& node)
{
    builder().setCurrentDebugSourceCodeRef(node.codeRef());
    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    return info.codeGenPreNode(*this, node);
}

Result CodeGen::postNode(AstNode& node)
{
    builder().setCurrentDebugSourceCodeRef(node.codeRef());
    const AstNodeIdInfo& info = Ast::nodeIdInfos(node.id());
    RESULT_VERIFY(info.codeGenPostNode(*this, node));
    return emitConstant(curNodeRef());
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
