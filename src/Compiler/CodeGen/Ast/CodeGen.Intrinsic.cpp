#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Intrinsic.Payload.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

Result codeGenCallExprCommon(CodeGen& codeGen, AstNodeRef calleeRef);

namespace
{
    CodeGenNodePayload resolveIntrinsicRuntimeStoragePayload(CodeGen& codeGen, const SymbolVariable& storageSym)
    {
        if (const CodeGenNodePayload* symbolPayload = CodeGen::variablePayload(storageSym))
            return *symbolPayload;

        SWC_ASSERT(storageSym.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack));
        SWC_ASSERT(codeGen.localStackBaseReg().isValid());

        CodeGenNodePayload localPayload;
        localPayload.typeRef = storageSym.typeRef();
        localPayload.setIsAddress();
        if (!storageSym.offset())
        {
            localPayload.reg = codeGen.localStackBaseReg();
        }
        else
        {
            MicroBuilder& builder = codeGen.builder();
            localPayload.reg      = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(localPayload.reg, codeGen.localStackBaseReg(), MicroOpBits::B64);
            builder.emitOpBinaryRegImm(localPayload.reg, ApInt(storageSym.offset(), 64), MicroOp::Add, MicroOpBits::B64);
        }

        codeGen.setVariablePayload(storageSym, localPayload);
        return localPayload;
    }

    MicroReg intrinsicRuntimeStorageAddressReg(CodeGen& codeGen)
    {
        const auto* payload = codeGen.sema().codeGenPayload<IntrinsicCallCodeGenPayload>(codeGen.curNodeRef());
        SWC_ASSERT(payload != nullptr);
        SWC_ASSERT(payload->runtimeStorageSym != nullptr);
        const CodeGenNodePayload storagePayload = resolveIntrinsicRuntimeStoragePayload(codeGen, *SWC_NOT_NULL(payload->runtimeStorageSym));
        SWC_ASSERT(storagePayload.isAddress());
        return storagePayload.reg;
    }

    Result codeGenMakeSlice(CodeGen& codeGen, const AstIntrinsicCall& node, bool forString)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 2);

        const AstNodeRef          ptrRef        = children[0];
        const AstNodeRef          sizeRef       = children[1];
        const CodeGenNodePayload& ptrPayload    = codeGen.payload(ptrRef);
        const CodeGenNodePayload& sizePayload   = codeGen.payload(sizeRef);
        const TypeRef             resultTypeRef = codeGen.curViewType().typeRef();

        MicroBuilder& builder = codeGen.builder();

        const MicroReg ptrReg = codeGen.nextVirtualIntRegister();
        if (ptrPayload.isAddress())
            builder.emitLoadRegMem(ptrReg, ptrPayload.reg, 0, MicroOpBits::B64);
        else
            builder.emitLoadRegReg(ptrReg, ptrPayload.reg, MicroOpBits::B64);

        const MicroReg sizeReg = codeGen.nextVirtualIntRegister();
        if (sizePayload.isAddress())
            builder.emitLoadRegMem(sizeReg, sizePayload.reg, 0, MicroOpBits::B64);
        else
            builder.emitLoadRegReg(sizeReg, sizePayload.reg, MicroOpBits::B64);

        const MicroReg runtimeStorageReg = intrinsicRuntimeStorageAddressReg(codeGen);
        const uint64_t countOffset       = forString ? offsetof(Runtime::String, length) : offsetof(Runtime::Slice<std::byte>, count);
        builder.emitLoadMemReg(runtimeStorageReg, offsetof(Runtime::Slice<std::byte>, ptr), ptrReg, MicroOpBits::B64);
        builder.emitLoadMemReg(runtimeStorageReg, countOffset, sizeReg, MicroOpBits::B64);

        CodeGenNodePayload& payload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        payload.reg                 = runtimeStorageReg;
        return Result::Continue;
    }

    MicroReg materializeCountLikeBaseReg(const CodeGen& codeGen, const CodeGenNodePayload& payload)
    {
        SWC_UNUSED(codeGen);
        return payload.reg;
    }

    Result codeGenCountOf(CodeGen& codeGen, AstNodeRef exprRef)
    {
        MicroBuilder&             builder       = codeGen.builder();
        const SemaNodeView        exprView      = codeGen.viewType(exprRef);
        const CodeGenNodePayload& exprPayload   = codeGen.payload(exprRef);
        const TypeInfo* const     exprType      = exprView.type();
        const TypeRef             resultTypeRef = codeGen.curViewType().typeRef();
        SWC_ASSERT(exprType != nullptr);

        if (exprType->isIntUnsigned())
        {
            const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
            const uint32_t            intBits       = exprType->payloadIntBits() ? exprType->payloadIntBits() : 64;
            const MicroOpBits         opBits        = microOpBitsFromBitWidth(intBits);
            if (exprPayload.isAddress())
                builder.emitLoadRegMem(resultPayload.reg, exprPayload.reg, 0, opBits);
            else
                builder.emitLoadRegReg(resultPayload.reg, exprPayload.reg, opBits);
            return Result::Continue;
        }

        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        const MicroReg            baseReg       = materializeCountLikeBaseReg(codeGen, exprPayload);
        if (exprType->isString())
        {
            builder.emitLoadRegMem(resultPayload.reg, baseReg, offsetof(Runtime::String, length), MicroOpBits::B64);
            return Result::Continue;
        }

        if (exprType->isSlice() || exprType->isAnyVariadic())
        {
            builder.emitLoadRegMem(resultPayload.reg, baseReg, offsetof(Runtime::Slice<std::byte>, count), MicroOpBits::B64);
            return Result::Continue;
        }

        SWC_INTERNAL_ERROR();
    }

    Result codeGenDataOf(CodeGen& codeGen, const AstIntrinsicCall& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(!children.empty());

        const AstNodeRef          exprRef     = children[0];
        const CodeGenNodePayload& exprPayload = codeGen.payload(exprRef);
        const SemaNodeView        exprView    = codeGen.viewType(exprRef);
        const CodeGenNodePayload& payload     = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        MicroBuilder&             builder     = codeGen.builder();

        if (exprView.type() && (exprView.type()->isString() || exprView.type()->isSlice() || exprView.type()->isAny()))
            builder.emitLoadRegMem(payload.reg, exprPayload.reg, 0, MicroOpBits::B64);
        else if (exprView.type() && exprView.type()->isArray())
            builder.emitLoadRegReg(payload.reg, exprPayload.reg, MicroOpBits::B64);
        else if (exprPayload.isAddress())
            builder.emitLoadRegMem(payload.reg, exprPayload.reg, 0, MicroOpBits::B64);
        else
            builder.emitLoadRegReg(payload.reg, exprPayload.reg, MicroOpBits::B64);
        return Result::Continue;
    }

    Result codeGenKindOf(CodeGen& codeGen, const AstIntrinsicCall& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(!children.empty());

        const AstNodeRef          exprRef     = children[0];
        const CodeGenNodePayload& exprPayload = codeGen.payload(exprRef);
        CodeGenNodePayload&       result      = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        MicroBuilder&             builder     = codeGen.builder();
        const MicroReg            anyBaseReg  = exprPayload.reg;
        result.reg                            = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(result.reg, anyBaseReg, offsetof(Runtime::Any, type), MicroOpBits::B64);
        return Result::Continue;
    }

    Result codeGenAssert(CodeGen& codeGen, const AstIntrinsicCallExpr& node)
    {
        MicroBuilder&                   builder    = codeGen.builder();
        const Runtime::BuildCfgBackend& backendCfg = builder.backendBuildCfg();
        if (!backendCfg.emitAssert)
            return Result::Continue;

        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        if (children.empty())
            return Result::Continue;

        const AstNodeRef          exprRef     = children[0];
        const CodeGenNodePayload& exprPayload = codeGen.payload(exprRef);
        const MicroReg            condReg     = codeGen.nextVirtualIntRegister();
        constexpr auto            condBits    = MicroOpBits::B8;

        if (exprPayload.isAddress())
            builder.emitLoadRegMem(condReg, exprPayload.reg, 0, condBits);
        else
            builder.emitLoadRegReg(condReg, exprPayload.reg, condBits);

        const MicroLabelRef doneLabel = builder.createLabel();
        builder.emitCmpRegImm(condReg, ApInt(0, 64), condBits);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, doneLabel);
        builder.emitAssertTrap();
        builder.placeLabel(doneLabel);
        return Result::Continue;
    }
}

Result AstCountOfExpr::codeGenPostNode(CodeGen& codeGen) const
{
    return codeGenCountOf(codeGen, nodeExprRef);
}

Result AstIntrinsicCall::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.token(codeRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicDataOf:
            return codeGenDataOf(codeGen, *this);
        case TokenId::IntrinsicKindOf:
            return codeGenKindOf(codeGen, *this);
        case TokenId::IntrinsicMakeSlice:
            return codeGenMakeSlice(codeGen, *this, false);
        case TokenId::IntrinsicMakeString:
            return codeGenMakeSlice(codeGen, *this, true);

        default:
            SWC_UNREACHABLE();
    }
}

Result AstIntrinsicCallExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.token(codeRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicAssert:
            return codeGenAssert(codeGen, *this);

        case TokenId::IntrinsicBcBreakpoint:
            codeGen.builder().emitBreakpoint();
            return Result::Continue;

        case TokenId::IntrinsicCompiler:
        {
            const uint64_t      compilerIfAddress = reinterpret_cast<uint64_t>(&codeGen.compiler().runtimeCompiler());
            const ConstantValue compilerIfCst     = ConstantValue::makeValuePointer(codeGen.ctx(), codeGen.typeMgr().typeVoid(), compilerIfAddress, TypeInfoFlagsE::Const);
            const ConstantRef   compilerIfCstRef  = codeGen.cstMgr().addConstant(codeGen.ctx(), compilerIfCst);
            const SemaNodeView  view              = codeGen.curViewType();
            const auto&         payload           = codeGen.setPayloadValue(codeGen.curNodeRef(), view.typeRef());
            codeGen.builder().emitLoadRegPtrReloc(payload.reg, compilerIfAddress, compilerIfCstRef);
            return Result::Continue;
        }

        default:
            return codeGenCallExprCommon(codeGen, nodeExprRef);
    }
}

SWC_END_NAMESPACE();
