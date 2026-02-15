#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/MachineCode/ABI/CallConv.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Backend/MachineCode/Micro/MicroReg.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Type/TypeManager.h"
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
    if (symbolFunc.attributes().hasRtFlag(RtAttributeFlagsE::PrintMicroRaw))
        builderFlags.add(MicroInstrBuilderFlagsE::PrintBeforePasses);
    if (symbolFunc.attributes().hasRtFlag(RtAttributeFlagsE::PrintMicro))
        builderFlags.add(MicroInstrBuilderFlagsE::PrintBeforeEncode);
    if (ctx().compiler().buildCfg().backendDebugInformations)
        builderFlags.add(MicroInstrBuilderFlagsE::DebugInfo);
    builder_->setFlags(builderFlags);
    builder_->setCurrentDebugInfo({});
    const SourceCodeRange codeRange = symbolFunc.codeRange(ctx());
    const SourceView&     srcView   = sema().srcView(symbolFunc.srcViewRef());
    const SourceFile*     file      = srcView.file();
    builder_->setPrintLocation(std::string(symbolFunc.getFullScopedName(ctx())), file ? file->path().string() : std::string{}, codeRange.line);

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

Result CodeGen::emitConstReturnValue(const SemaNodeView& exprView)
{
    SWC_ASSERT(exprView.cst);
    SWC_ASSERT(exprView.type);

    auto&       instrBuilder = builder();
    const auto& callConv     = CallConv::host();
    const auto& cst          = *exprView.cst;
    const auto& ty           = *exprView.type;

    if (ty.isBool())
    {
        instrBuilder.encodeLoadRegImm(callConv.intReturn, cst.getBool() ? 1 : 0, MicroOpBits::B8, EncodeFlagsE::Zero);
        return Result::Continue;
    }

    if (ty.isIntLike())
    {
        uint64_t value = 0;
        if (cst.isInt())
            value = cst.getInt().isUnsigned() ? cst.getInt().as64() : std::bit_cast<uint64_t>(cst.getInt().as64Signed());
        else if (cst.isChar())
            value = cst.getChar();
        else if (cst.isRune())
            value = cst.getRune();
        else
            return Result::Continue;

        const MicroOpBits bits = microOpBitsFromBitWidth(ty.payloadIntLikeBits());
        SWC_ASSERT(bits != MicroOpBits::Zero);
        instrBuilder.encodeLoadRegImm(callConv.intReturn, value, bits, EncodeFlagsE::Zero);
        return Result::Continue;
    }

    if (ty.isEnum())
    {
        const TypeInfo&      underlyingTy   = ctx().typeMgr().get(ty.payloadSymEnum().underlyingTypeRef());
        const ConstantValue* enumStorageCst = &cst;
        if (cst.isEnumValue())
            enumStorageCst = &sema().cstMgr().get(cst.getEnumValue());
        if (!enumStorageCst->isInt())
            return Result::Continue;

        const uint64_t    value = enumStorageCst->getInt().isUnsigned() ? enumStorageCst->getInt().as64() : std::bit_cast<uint64_t>(enumStorageCst->getInt().as64Signed());
        const MicroOpBits bits  = microOpBitsFromBitWidth(underlyingTy.payloadIntLikeBits());
        SWC_ASSERT(bits != MicroOpBits::Zero);
        instrBuilder.encodeLoadRegImm(callConv.intReturn, value, bits, EncodeFlagsE::Zero);
        return Result::Continue;
    }

    if (ty.isFloat())
    {
        const MicroOpBits bits = microOpBitsFromBitWidth(ty.payloadFloatBits());
        SWC_ASSERT(bits != MicroOpBits::Zero);
        const uint64_t raw = bits == MicroOpBits::B32 ? static_cast<uint64_t>(std::bit_cast<uint32_t>(cst.getFloat().asFloat())) : std::bit_cast<uint64_t>(cst.getFloat().asDouble());
        instrBuilder.encodeLoadRegImm(callConv.intReturn, raw, bits, EncodeFlagsE::Zero);
        instrBuilder.encodeLoadRegReg(callConv.floatReturn, callConv.intReturn, bits, EncodeFlagsE::Zero);
        return Result::Continue;
    }

    if (ty.isValuePointer())
    {
        instrBuilder.encodeLoadRegImm(callConv.intReturn, cst.getValuePointer(), MicroOpBits::B64, EncodeFlagsE::Zero);
        return Result::Continue;
    }

    if (ty.isBlockPointer())
    {
        instrBuilder.encodeLoadRegImm(callConv.intReturn, cst.getBlockPointer(), MicroOpBits::B64, EncodeFlagsE::Zero);
        return Result::Continue;
    }

    return Result::Continue;
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

    auto& dstPayload           = setPayload(dstNodeRef, typeRef);
    dstPayload.virtualRegister = srcPayload->virtualRegister;
    return dstPayload;
}

MicroReg CodeGen::payloadVirtualReg(AstNodeRef nodeRef) const
{
    const CodeGenNodePayload* nodePayload = payload(nodeRef);
    return payloadVirtualReg(*SWC_CHECK_NOT_NULL(nodePayload));
}

MicroReg CodeGen::payloadVirtualReg(const CodeGenNodePayload& nodePayload)
{
    SWC_ASSERT(nodePayload.virtualRegister != 0);
    return MicroReg::virtualReg(nodePayload.virtualRegister);
}

CodeGenNodePayload& CodeGen::setPayload(AstNodeRef nodeRef, TypeRef typeRef)
{
    CodeGenNodePayload* nodePayload = payload(nodeRef);
    if (!nodePayload)
    {
        nodePayload = sema().compiler().allocate<CodeGenNodePayload>();
        sema().setCodeGenPayload(nodeRef, nodePayload);
    }

    nodePayload->virtualRegister = nextVirtualRegister();
    nodePayload->typeRef         = typeRef;
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
    return info.codeGenPostNode(*this, node);
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
