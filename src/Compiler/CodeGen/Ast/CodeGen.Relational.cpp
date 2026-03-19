#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenCompareHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void materializeCompareOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, TypeRef compareTypeRef);

    bool hasPreparedRuntimeStringCompare(CodeGen& codeGen)
    {
        const auto* payload = codeGen.sema().codeGenPayload<CodeGenNodePayload>(codeGen.curNodeRef());
        return payload && payload->runtimeFunctionSymbol != nullptr;
    }

    bool isStringCompareType(CodeGen& codeGen, TypeRef typeRef)
    {
        const TypeRef   unwrappedTypeRef = codeGen.typeMgr().get(typeRef).unwrapAliasEnum(codeGen.ctx(), typeRef);
        const TypeInfo& typeInfo         = codeGen.typeMgr().get(unwrappedTypeRef);
        return typeInfo.isString();
    }

    void appendPreparedStringCompareArg(SmallVector<ABICall::PreparedArg>& outArgs, CodeGen& codeGen, const CallConv& callConv, const CodeGenNodePayload& operandPayload, TypeRef argTypeRef)
    {
        const TypeInfo&                        argType       = codeGen.typeMgr().get(argTypeRef);
        const ABITypeNormalize::NormalizedType normalizedArg = ABITypeNormalize::normalize(codeGen.ctx(), callConv, argTypeRef, ABITypeNormalize::Usage::Argument);

        ABICall::PreparedArg preparedArg;
        preparedArg.srcReg      = operandPayload.reg;
        preparedArg.kind        = ABICall::PreparedArgKind::Direct;
        preparedArg.isFloat     = normalizedArg.isFloat;
        preparedArg.isAddressed = operandPayload.isAddress() && !normalizedArg.isIndirect && !argType.isReference();
        preparedArg.numBits     = normalizedArg.numBits;
        outArgs.push_back(preparedArg);
    }

    Result emitStringCompareBool(CodeGen& codeGen, TokenId tokId, const CodeGenNodePayload& leftPayload, const CodeGenNodePayload& rightPayload)
    {
        SymbolFunction* stringCmpSymbol = nullptr;
        if (const auto* payload = codeGen.sema().codeGenPayload<CodeGenNodePayload>(codeGen.curNodeRef()); payload && payload->runtimeFunctionSymbol != nullptr)
        {
            stringCmpSymbol = payload->runtimeFunctionSymbol;
        }
        else
        {
            const IdentifierRef idRef = codeGen.idMgr().predefined(IdentifierManager::PredefinedName::RuntimeStringCmp);
            if (idRef.isValid())
                stringCmpSymbol = codeGen.compiler().runtimeFunctionSymbol(idRef);
        }

        SWC_ASSERT(stringCmpSymbol != nullptr);
        if (!stringCmpSymbol)
            return Result::Error;

        auto&                             stringCmpFunction = *stringCmpSymbol;
        const CallConvKind                callConvKind      = stringCmpFunction.callConvKind();
        const CallConv&                   callConv          = CallConv::get(callConvKind);
        const auto&                       params            = stringCmpFunction.parameters();
        SmallVector<ABICall::PreparedArg> preparedArgs;
        preparedArgs.reserve(2);

        SWC_ASSERT(params.size() >= 2);
        SWC_ASSERT(params[0] != nullptr);
        SWC_ASSERT(params[1] != nullptr);
        appendPreparedStringCompareArg(preparedArgs, codeGen, callConv, leftPayload, params[0]->typeRef());
        appendPreparedStringCompareArg(preparedArgs, codeGen, callConv, rightPayload, params[1]->typeRef());

        MicroBuilder&               builder      = codeGen.builder();
        const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs.span());
        if (stringCmpFunction.isForeign())
            ABICall::callExtern(builder, callConvKind, &stringCmpFunction, preparedCall);
        else
            ABICall::callLocal(builder, callConvKind, &stringCmpFunction, preparedCall);

        const CodeGenNodePayload&              resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, stringCmpFunction.returnTypeRef(), ABITypeNormalize::Usage::Return);
        SWC_ASSERT(!normalizedRet.isVoid);
        SWC_ASSERT(!normalizedRet.isIndirect);
        SWC_ASSERT(normalizedRet.numBits == 8);
        ABICall::materializeReturnToReg(builder, resultPayload.reg, callConvKind, normalizedRet);

        const MicroCond cond = tokId == TokenId::SymEqualEqual ? MicroCond::NotEqual : MicroCond::Equal;
        builder.emitCmpRegImm(resultPayload.reg, ApInt(0, 64), MicroOpBits::B8);
        builder.emitSetCondReg(resultPayload.reg, cond);
        builder.emitLoadZeroExtendRegReg(resultPayload.reg, resultPayload.reg, MicroOpBits::B32, MicroOpBits::B8);
        return Result::Continue;
    }

    Result emitTypeInfoCompareBool(CodeGen&                  codeGen,
                                   TokenId                   tokId,
                                   const CodeGenNodePayload& leftPayload,
                                   TypeRef                   leftOperandTypeRef,
                                   const CodeGenNodePayload& rightPayload,
                                   TypeRef                   rightOperandTypeRef,
                                   TypeRef                   compareTypeRef)
    {
        MicroReg leftPtrReg, rightPtrReg;
        materializeCompareOperand(leftPtrReg, codeGen, leftPayload, leftOperandTypeRef, compareTypeRef);
        materializeCompareOperand(rightPtrReg, codeGen, rightPayload, rightOperandTypeRef, compareTypeRef);

        MicroBuilder&  builder     = codeGen.builder();
        const MicroReg leftCrcReg  = codeGen.nextVirtualIntRegister();
        const MicroReg rightCrcReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegMem(leftCrcReg, leftPtrReg, offsetof(Runtime::TypeInfo, crc), MicroOpBits::B32);
        builder.emitLoadRegMem(rightCrcReg, rightPtrReg, offsetof(Runtime::TypeInfo, crc), MicroOpBits::B32);

        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        resultPayload.reg                 = codeGen.nextVirtualIntRegister();
        builder.emitCmpRegReg(leftCrcReg, rightCrcReg, MicroOpBits::B32);
        builder.emitSetCondReg(resultPayload.reg, tokId == TokenId::SymEqualEqual ? MicroCond::Equal : MicroCond::NotEqual);
        builder.emitLoadZeroExtendRegReg(resultPayload.reg, resultPayload.reg, MicroOpBits::B32, MicroOpBits::B8);
        return Result::Continue;
    }

    TypeRef resolveCompareTypeRef(CodeGen& codeGen, const SemaNodeView& leftView, const SemaNodeView& rightView)
    {
        if (leftView.type()->isScalarNumeric() && rightView.type()->isScalarNumeric())
        {
            const TypeRef promotedTypeRef = codeGen.typeMgr().promote(leftView.typeRef(), rightView.typeRef(), false);
            if (!promotedTypeRef.isValid())
                return promotedTypeRef;

            const TypeInfo& promotedType = codeGen.typeMgr().get(promotedTypeRef);
            // Widen 32-bit numeric compares to the backend's 64-bit comparison form so arithmetic and
            // relational lowering agree on the register representation.
            if (promotedType.isIntLike() && promotedType.payloadIntLikeBitsOr(64) == 32)
            {
                const TypeInfo::Sign sign = promotedType.isIntUnsigned() ? TypeInfo::Sign::Unsigned : TypeInfo::Sign::Signed;
                return codeGen.typeMgr().typeInt(64, sign);
            }

            if (promotedType.isFloat() && promotedType.payloadFloatBitsOr(64) == 32)
                return codeGen.typeMgr().typeFloat(64);

            return promotedTypeRef;
        }

        return leftView.typeRef();
    }

    void loadCompareOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef)
    {
        outReg                                 = codeGen.nextVirtualRegisterForType(operandTypeRef);
        const TypeInfo&   operandType          = codeGen.typeMgr().get(operandTypeRef);
        const MicroOpBits opBits               = CodeGenTypeHelpers::compareBits(operandType, codeGen.ctx());
        const bool        isAddressBackedValue = operandType.sizeOf(codeGen.ctx()) > sizeof(uint64_t);

        MicroBuilder& builder = codeGen.builder();
        if (operandPayload.isAddress() || (operandPayload.isValue() && isAddressBackedValue))
            builder.emitLoadRegMem(outReg, operandPayload.reg, 0, opBits);
        else
            builder.emitLoadRegReg(outReg, operandPayload.reg, opBits);
    }

    void convertCompareOperand(MicroReg& outReg, CodeGen& codeGen, TypeRef srcTypeRef, TypeRef dstTypeRef)
    {
        if (srcTypeRef == dstTypeRef)
            return;

        const TypeInfo&   srcType = codeGen.typeMgr().get(srcTypeRef);
        const TypeInfo&   dstType = codeGen.typeMgr().get(dstTypeRef);
        const MicroOpBits srcBits = CodeGenTypeHelpers::compareBits(srcType, codeGen.ctx());
        const MicroOpBits dstBits = CodeGenTypeHelpers::compareBits(dstType, codeGen.ctx());

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
            MicroReg srcReg = outReg;
            if (getNumBits(srcBits) < 32 || (dstBits == MicroOpBits::B64 && getNumBits(srcBits) == 32))
            {
                srcReg                        = codeGen.nextVirtualIntRegister();
                const MicroOpBits widenedBits = dstBits == MicroOpBits::B64 ? MicroOpBits::B64 : MicroOpBits::B32;
                if (srcType.isIntSigned())
                    builder.emitLoadSignedExtendRegReg(srcReg, outReg, widenedBits, srcBits);
                else
                    builder.emitLoadZeroExtendRegReg(srcReg, outReg, widenedBits, srcBits);
            }

            const MicroReg dstReg = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitClearReg(dstReg, dstBits);
            builder.emitOpBinaryRegReg(dstReg, srcReg, MicroOp::ConvertIntToFloat, dstBits);
            outReg = dstReg;
            return;
        }

        if (srcType.isFloat() && dstType.isFloat())
        {
            if (srcBits == dstBits)
                return;

            const MicroReg dstReg = codeGen.nextVirtualRegisterForType(dstTypeRef);
            builder.emitClearReg(dstReg, dstBits);
            builder.emitOpBinaryRegReg(dstReg, outReg, MicroOp::ConvertFloatToFloat, srcBits);
            outReg = dstReg;
        }
    }

    void materializeCompareOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, TypeRef compareTypeRef)
    {
        loadCompareOperand(outReg, codeGen, operandPayload, operandTypeRef);
        convertCompareOperand(outReg, codeGen, operandTypeRef, compareTypeRef);
    }

    void widenCompareRegsIfNeeded(MicroReg& leftReg, MicroReg& rightReg, CodeGen& codeGen, const TypeInfo& compareType, MicroOpBits& ioOpBits)
    {
        if (ioOpBits != MicroOpBits::B32)
            return;

        MicroBuilder& builder = codeGen.builder();
        if (compareType.isIntLike())
        {
            constexpr auto widenedBits  = MicroOpBits::B64;
            const MicroReg widenedLeft  = codeGen.nextVirtualIntRegister();
            const MicroReg widenedRight = codeGen.nextVirtualIntRegister();
            if (compareType.isIntSigned())
            {
                builder.emitLoadSignedExtendRegReg(widenedLeft, leftReg, widenedBits, ioOpBits);
                builder.emitLoadSignedExtendRegReg(widenedRight, rightReg, widenedBits, ioOpBits);
            }
            else
            {
                builder.emitLoadZeroExtendRegReg(widenedLeft, leftReg, widenedBits, ioOpBits);
                builder.emitLoadZeroExtendRegReg(widenedRight, rightReg, widenedBits, ioOpBits);
            }

            leftReg  = widenedLeft;
            rightReg = widenedRight;
            ioOpBits = widenedBits;
            return;
        }

        if (compareType.isFloat())
        {
            constexpr auto widenedBits  = MicroOpBits::B64;
            const MicroReg widenedLeft  = codeGen.nextVirtualFloatRegister();
            const MicroReg widenedRight = codeGen.nextVirtualFloatRegister();
            builder.emitClearReg(widenedLeft, widenedBits);
            builder.emitOpBinaryRegReg(widenedLeft, leftReg, MicroOp::ConvertFloatToFloat, ioOpBits);
            builder.emitClearReg(widenedRight, widenedBits);
            builder.emitOpBinaryRegReg(widenedRight, rightReg, MicroOp::ConvertFloatToFloat, ioOpBits);
            leftReg  = widenedLeft;
            rightReg = widenedRight;
            ioOpBits = widenedBits;
        }
    }

    CodeGenCompareHelpers::CompareCondition buildCompareCondition(TokenId tokId, const TypeInfo& compareType)
    {
        using FloatUnorderedMode          = CodeGenCompareHelpers::FloatUnorderedMode;
        const bool unsignedOrFloatCompare = compareType.usesUnsignedConditions();
        switch (tokId)
        {
            case TokenId::SymLess:
                return {.primaryCond        = CodeGenCompareHelpers::lessCond(unsignedOrFloatCompare),
                        .floatUnorderedMode = compareType.isFloat() ? FloatUnorderedMode::RequireOrdered : FloatUnorderedMode::ExcludedByPrimary};
            case TokenId::SymLessEqual:
                return {.primaryCond        = CodeGenCompareHelpers::lessEqualCond(unsignedOrFloatCompare),
                        .floatUnorderedMode = compareType.isFloat() ? FloatUnorderedMode::RequireOrdered : FloatUnorderedMode::ExcludedByPrimary};
            case TokenId::SymGreater:
                return {.primaryCond = CodeGenCompareHelpers::greaterCond(unsignedOrFloatCompare)};
            case TokenId::SymGreaterEqual:
                return {.primaryCond = CodeGenCompareHelpers::greaterEqualCond(unsignedOrFloatCompare)};
            case TokenId::SymEqualEqual:
                return {.primaryCond        = MicroCond::Equal,
                        .floatUnorderedMode = compareType.isFloat() ? FloatUnorderedMode::RequireOrdered : FloatUnorderedMode::ExcludedByPrimary};
            case TokenId::SymBangEqual:
                return {.primaryCond        = MicroCond::NotEqual,
                        .floatUnorderedMode = compareType.isFloat() ? FloatUnorderedMode::AcceptUnordered : FloatUnorderedMode::ExcludedByPrimary};

            default:
                SWC_UNREACHABLE();
        }
    }

    Result emitRelationalBool(CodeGen& codeGen, const AstRelationalExpr& node, TokenId tokId)
    {
        const SemaNodeView leftView  = codeGen.viewType(node.nodeLeftRef);
        const SemaNodeView rightView = codeGen.viewType(node.nodeRightRef);
        SWC_ASSERT(leftView.type() && rightView.type());

        const CodeGenNodePayload& leftPayload         = codeGen.payload(node.nodeLeftRef);
        const CodeGenNodePayload& rightPayload        = codeGen.payload(node.nodeRightRef);
        const TypeRef             leftOperandTypeRef  = leftPayload.typeRef.isValid() ? leftPayload.typeRef : leftView.typeRef();
        const TypeRef             rightOperandTypeRef = rightPayload.typeRef.isValid() ? rightPayload.typeRef : rightView.typeRef();

        const TypeRef compareTypeRef = resolveCompareTypeRef(codeGen, leftView, rightView);
        if ((tokId == TokenId::SymEqualEqual || tokId == TokenId::SymBangEqual) &&
            isStringCompareType(codeGen, compareTypeRef) &&
            hasPreparedRuntimeStringCompare(codeGen))
            return emitStringCompareBool(codeGen, tokId, leftPayload, rightPayload);

        const TypeInfo& compareType = codeGen.typeMgr().get(compareTypeRef);
        if ((tokId == TokenId::SymEqualEqual || tokId == TokenId::SymBangEqual) && compareType.isAnyTypeInfo(codeGen.ctx()))
            return emitTypeInfoCompareBool(codeGen, tokId, leftPayload, leftOperandTypeRef, rightPayload, rightOperandTypeRef, compareTypeRef);

        MicroOpBits opBits = CodeGenTypeHelpers::compareBits(compareType, codeGen.ctx());
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        MicroReg leftReg, rightReg;
        materializeCompareOperand(leftReg, codeGen, leftPayload, leftOperandTypeRef, compareTypeRef);
        materializeCompareOperand(rightReg, codeGen, rightPayload, rightOperandTypeRef, compareTypeRef);
        widenCompareRegsIfNeeded(leftReg, rightReg, codeGen, compareType, opBits);

        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        resultPayload.reg                 = codeGen.nextVirtualIntRegister();
        MicroBuilder& builder             = codeGen.builder();
        builder.emitCmpRegReg(leftReg, rightReg, opBits);

        const CodeGenCompareHelpers::CompareCondition condition = buildCompareCondition(tokId, compareType);
        CodeGenCompareHelpers::emitConditionBool(codeGen, resultPayload.reg, compareType, condition);
        return Result::Continue;
    }

    Result emitThreeWayCompare(CodeGen& codeGen, const AstRelationalExpr& node)
    {
        const SemaNodeView leftView  = codeGen.viewType(node.nodeLeftRef);
        const SemaNodeView rightView = codeGen.viewType(node.nodeRightRef);
        SWC_ASSERT(leftView.type() && rightView.type());

        const CodeGenNodePayload& leftPayload         = codeGen.payload(node.nodeLeftRef);
        const CodeGenNodePayload& rightPayload        = codeGen.payload(node.nodeRightRef);
        const TypeRef             leftOperandTypeRef  = leftPayload.typeRef.isValid() ? leftPayload.typeRef : leftView.typeRef();
        const TypeRef             rightOperandTypeRef = rightPayload.typeRef.isValid() ? rightPayload.typeRef : rightView.typeRef();

        const TypeRef   compareTypeRef = resolveCompareTypeRef(codeGen, leftView, rightView);
        const TypeInfo& compareType    = codeGen.typeMgr().get(compareTypeRef);
        MicroOpBits     opBits         = CodeGenTypeHelpers::compareBits(compareType, codeGen.ctx());
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        MicroReg leftReg, rightReg;
        materializeCompareOperand(leftReg, codeGen, leftPayload, leftOperandTypeRef, compareTypeRef);
        materializeCompareOperand(rightReg, codeGen, rightPayload, rightOperandTypeRef, compareTypeRef);
        widenCompareRegsIfNeeded(leftReg, rightReg, codeGen, compareType, opBits);

        MicroBuilder& builder = codeGen.builder();

        const CodeGenCompareHelpers::CompareCondition lessCond  = buildCompareCondition(TokenId::SymLess, compareType);
        const CodeGenCompareHelpers::CompareCondition greatCond = buildCompareCondition(TokenId::SymGreater, compareType);

        const MicroReg lessReg  = codeGen.nextVirtualIntRegister();
        const MicroReg greatReg = codeGen.nextVirtualIntRegister();
        builder.emitCmpRegReg(leftReg, rightReg, opBits);
        builder.emitSetCondReg(lessReg, lessCond.primaryCond);
        builder.emitLoadZeroExtendRegReg(lessReg, lessReg, MicroOpBits::B32, MicroOpBits::B8);
        builder.emitSetCondReg(greatReg, greatCond.primaryCond);
        builder.emitLoadZeroExtendRegReg(greatReg, greatReg, MicroOpBits::B32, MicroOpBits::B8);

        if (CodeGenCompareHelpers::needsFloatUnorderedHandling(compareType, lessCond))
        {
            const MicroReg orderedReg = codeGen.nextVirtualIntRegister();
            builder.emitSetCondReg(orderedReg, MicroCond::NotParity);
            builder.emitLoadZeroExtendRegReg(orderedReg, orderedReg, MicroOpBits::B32, MicroOpBits::B8);
            builder.emitOpBinaryRegReg(lessReg, orderedReg, MicroOp::And, MicroOpBits::B32);
        }

        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        // `<=>` is reconstructed from two predicates: `left > right` minus `left < right` yields
        // {+1, 0, -1} without needing a dedicated three-way compare opcode.
        builder.emitLoadRegReg(resultPayload.reg, greatReg, MicroOpBits::B32);
        builder.emitOpBinaryRegReg(resultPayload.reg, lessReg, MicroOp::Subtract, MicroOpBits::B32);
        return Result::Continue;
    }
}

Result AstRelationalExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.token(codeRef());
    switch (tok.id)
    {
        case TokenId::SymEqualEqual:
        case TokenId::SymBangEqual:
        case TokenId::SymLess:
        case TokenId::SymLessEqual:
        case TokenId::SymGreater:
        case TokenId::SymGreaterEqual:
            return emitRelationalBool(codeGen, *this, tok.id);

        case TokenId::SymLessEqualGreater:
            return emitThreeWayCompare(codeGen, *this);

        default:
            SWC_UNREACHABLE();
    }
}

SWC_END_NAMESPACE();
