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
    MicroOpBits intrinsicNumericOpBits(const TypeInfo& typeInfo)
    {
        if (typeInfo.isFloat())
        {
            const uint32_t floatBits = typeInfo.payloadFloatBits() ? typeInfo.payloadFloatBits() : 64;
            return microOpBitsFromBitWidth(floatBits);
        }

        if (typeInfo.isIntLike())
        {
            const uint32_t intBits = typeInfo.payloadIntLikeBits() ? typeInfo.payloadIntLikeBits() : 64;
            return microOpBitsFromBitWidth(intBits);
        }

        return MicroOpBits::Zero;
    }

    void loadIntrinsicNumericOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef)
    {
        outReg                        = codeGen.nextVirtualRegisterForType(operandTypeRef);
        const TypeInfo&   operandType = codeGen.typeMgr().get(operandTypeRef);
        const MicroOpBits opBits      = intrinsicNumericOpBits(operandType);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        MicroBuilder& builder = codeGen.builder();
        if (operandPayload.isAddress())
            builder.emitLoadRegMem(outReg, operandPayload.reg, 0, opBits);
        else
            builder.emitLoadRegReg(outReg, operandPayload.reg, opBits);
    }

    void convertIntrinsicNumericOperand(MicroReg& outReg, CodeGen& codeGen, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (srcTypeRef == dstTypeRef)
            return;

        const TypeInfo&   srcType = codeGen.typeMgr().get(srcTypeRef);
        const TypeInfo&   dstType = codeGen.typeMgr().get(dstTypeRef);
        const MicroOpBits srcBits = intrinsicNumericOpBits(srcType);
        const MicroOpBits dstBits = intrinsicNumericOpBits(dstType);
        SWC_ASSERT(srcBits != MicroOpBits::Zero);
        SWC_ASSERT(dstBits != MicroOpBits::Zero);

        MicroBuilder& builder = codeGen.builder();

        if (srcType.isIntLike() && dstType.isIntLike())
        {
            const MicroReg dstReg = codeGen.nextVirtualIntRegister();
            if (srcBits == dstBits)
            {
                builder.emitLoadRegReg(dstReg, outReg, dstBits);
                outReg = dstReg;
                return;
            }

            if (getNumBits(srcBits) > getNumBits(dstBits))
            {
                builder.emitLoadRegReg(dstReg, outReg, dstBits);
                outReg = dstReg;
                return;
            }

            if (srcType.isIntSigned())
                builder.emitLoadSignedExtendRegReg(dstReg, outReg, dstBits, srcBits);
            else
                builder.emitLoadZeroExtendRegReg(dstReg, outReg, dstBits, srcBits);
            outReg = dstReg;
            return;
        }

        if (srcType.isIntLike() && dstType.isFloat())
        {
            const MicroReg dstReg = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitClearReg(dstReg, dstBits);
            builder.emitOpBinaryRegReg(dstReg, outReg, MicroOp::ConvertIntToFloat, dstBits);
            outReg = dstReg;
            return;
        }

        if (srcType.isFloat() && dstType.isFloat())
        {
            builder.emitOpBinaryRegReg(outReg, outReg, MicroOp::ConvertFloatToFloat, srcBits);
            return;
        }

        SWC_INTERNAL_ERROR();
    }

    void materializeIntrinsicNumericOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, TypeRef resultTypeRef)
    {
        loadIntrinsicNumericOperand(outReg, codeGen, operandPayload, operandTypeRef);
        convertIntrinsicNumericOperand(outReg, codeGen, operandTypeRef, resultTypeRef);
    }

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

    Result codeGenSqrt(CodeGen& codeGen, const AstIntrinsicCallExpr& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 1);

        const AstNodeRef          exprRef       = children[0];
        const CodeGenNodePayload& exprPayload   = codeGen.payload(exprRef);
        const TypeRef             resultTypeRef = codeGen.curViewType().typeRef();
        const TypeInfo&           resultType    = codeGen.typeMgr().get(resultTypeRef);
        SWC_ASSERT(resultType.isFloat());

        const uint32_t    floatBits = resultType.payloadFloatBits() ? resultType.payloadFloatBits() : 64;
        const MicroOpBits opBits    = microOpBitsFromBitWidth(floatBits);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        MicroBuilder&       builder       = codeGen.builder();
        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        resultPayload.reg                 = codeGen.nextVirtualRegisterForType(resultTypeRef);
        if (exprPayload.isAddress())
            builder.emitLoadRegMem(resultPayload.reg, exprPayload.reg, 0, opBits);
        else
            builder.emitLoadRegReg(resultPayload.reg, exprPayload.reg, opBits);
        builder.emitOpBinaryRegReg(resultPayload.reg, resultPayload.reg, MicroOp::FloatSqrt, opBits);
        return Result::Continue;
    }

    Result codeGenAbs(CodeGen& codeGen, const AstIntrinsicCallExpr& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 1);

        const AstNodeRef          exprRef         = children[0];
        const CodeGenNodePayload& exprPayload     = codeGen.payload(exprRef);
        const SemaNodeView        exprView        = codeGen.viewType(exprRef);
        const TypeRef             exprTypeRef     = exprPayload.typeRef.isValid() ? exprPayload.typeRef : exprView.typeRef();
        const TypeRef             resultTypeRef   = codeGen.curViewType().typeRef();
        const TypeInfo&           resultType      = codeGen.typeMgr().get(resultTypeRef);
        const MicroOpBits         opBits          = intrinsicNumericOpBits(resultType);
        CodeGenNodePayload&       resultPayload   = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
        MicroBuilder&             builder         = codeGen.builder();
        MicroReg                  materializedReg = MicroReg::invalid();

        SWC_ASSERT(opBits != MicroOpBits::Zero);
        materializeIntrinsicNumericOperand(materializedReg, codeGen, exprPayload, exprTypeRef, resultTypeRef);

        if (resultType.isFloat())
        {
            resultPayload.reg = codeGen.nextVirtualRegisterForType(resultTypeRef);
            builder.emitLoadRegReg(resultPayload.reg, materializedReg, opBits);

            const uint64_t mask    = opBits == MicroOpBits::B32 ? 0x7FFFFFFFu : 0x7FFFFFFFFFFFFFFFull;
            const MicroReg maskReg = codeGen.nextVirtualRegisterForType(resultTypeRef);
            builder.emitLoadRegImm(maskReg, ApInt(mask, 64), opBits);
            builder.emitOpBinaryRegReg(resultPayload.reg, maskReg, MicroOp::FloatAnd, opBits);
            return Result::Continue;
        }

        SWC_ASSERT(resultType.isIntLike());
        resultPayload.reg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(resultPayload.reg, materializedReg, opBits);
        if (resultType.isIntLikeUnsigned())
            return Result::Continue;

        const MicroLabelRef doneLabel = builder.createLabel();
        builder.emitCmpRegImm(resultPayload.reg, ApInt(0, 64), opBits);
        builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B32, doneLabel);
        builder.emitOpUnaryReg(resultPayload.reg, MicroOp::Negate, opBits);
        builder.placeLabel(doneLabel);
        return Result::Continue;
    }

    Result codeGenMinMax(CodeGen& codeGen, const AstIntrinsicCallExpr& node, bool isMin)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(children.size() == 2);

        const AstNodeRef          leftRef             = children[0];
        const AstNodeRef          rightRef            = children[1];
        const CodeGenNodePayload& leftPayload         = codeGen.payload(leftRef);
        const CodeGenNodePayload& rightPayload        = codeGen.payload(rightRef);
        const SemaNodeView        leftView            = codeGen.viewType(leftRef);
        const SemaNodeView        rightView           = codeGen.viewType(rightRef);
        const TypeRef             leftOperandTypeRef  = leftPayload.typeRef.isValid() ? leftPayload.typeRef : leftView.typeRef();
        const TypeRef             rightOperandTypeRef = rightPayload.typeRef.isValid() ? rightPayload.typeRef : rightView.typeRef();
        const TypeRef             resultTypeRef       = codeGen.curViewType().typeRef();
        const TypeInfo&           resultType          = codeGen.typeMgr().get(resultTypeRef);
        const MicroOpBits         opBits              = intrinsicNumericOpBits(resultType);
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        MicroReg leftReg, rightReg;
        materializeIntrinsicNumericOperand(leftReg, codeGen, leftPayload, leftOperandTypeRef, resultTypeRef);
        materializeIntrinsicNumericOperand(rightReg, codeGen, rightPayload, rightOperandTypeRef, resultTypeRef);

        MicroBuilder&       builder       = codeGen.builder();
        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);

        if (resultType.isFloat())
        {
            resultPayload.reg = codeGen.nextVirtualRegisterForType(resultTypeRef);
            builder.emitLoadRegReg(resultPayload.reg, leftReg, opBits);
            builder.emitOpBinaryRegReg(resultPayload.reg, rightReg, isMin ? MicroOp::FloatMin : MicroOp::FloatMax, opBits);
            return Result::Continue;
        }

        SWC_ASSERT(resultType.isIntLike());
        resultPayload.reg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(resultPayload.reg, leftReg, opBits);
        builder.emitCmpRegReg(leftReg, rightReg, opBits);

        auto takeLeftCond = MicroCond::Equal;
        if (resultType.isIntLikeUnsigned())
            takeLeftCond = isMin ? MicroCond::BelowOrEqual : MicroCond::AboveOrEqual;
        else
            takeLeftCond = isMin ? MicroCond::LessOrEqual : MicroCond::GreaterOrEqual;

        const MicroLabelRef doneLabel = builder.createLabel();
        builder.emitJumpToLabel(takeLeftCond, MicroOpBits::B32, doneLabel);
        builder.emitLoadRegReg(resultPayload.reg, rightReg, opBits);
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
        case TokenId::IntrinsicSqrt:
            return codeGenSqrt(codeGen, *this);
        case TokenId::IntrinsicAbs:
            return codeGenAbs(codeGen, *this);
        case TokenId::IntrinsicMin:
            return codeGenMinMax(codeGen, *this, true);
        case TokenId::IntrinsicMax:
            return codeGenMinMax(codeGen, *this, false);
        case TokenId::IntrinsicBreakpoint:
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
