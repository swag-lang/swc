#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
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
    TypeRef unwrapAliasEnumTypeRef(CodeGen& codeGen, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return typeRef;

        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        const TypeRef   unwrappedTypeRef = typeInfo.unwrap(codeGen.ctx(), typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        if (unwrappedTypeRef.isValid())
            return unwrappedTypeRef;

        return typeRef;
    }

    bool isStringCompareType(CodeGen& codeGen, TypeRef typeRef)
    {
        const TypeRef   unwrappedTypeRef = unwrapAliasEnumTypeRef(codeGen, typeRef);
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

        auto&                     stringCmpFunction = *stringCmpSymbol;
        const CallConvKind        callConvKind      = stringCmpFunction.callConvKind();
        const CallConv&           callConv          = CallConv::get(callConvKind);
        const auto&               params            = stringCmpFunction.parameters();
        SmallVector<ABICall::PreparedArg> preparedArgs;
        preparedArgs.reserve(2);

        SWC_ASSERT(params.size() >= 2);
        SWC_ASSERT(params[0] != nullptr);
        SWC_ASSERT(params[1] != nullptr);
        appendPreparedStringCompareArg(preparedArgs, codeGen, callConv, leftPayload, params[0]->typeRef());
        appendPreparedStringCompareArg(preparedArgs, codeGen, callConv, rightPayload, params[1]->typeRef());

        MicroBuilder& builder = codeGen.builder();
        const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs.span());
        if (stringCmpFunction.isForeign())
            ABICall::callExtern(builder, callConvKind, &stringCmpFunction, preparedCall);
        else
            ABICall::callLocal(builder, callConvKind, &stringCmpFunction, preparedCall);

        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
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

    MicroOpBits compareOpBits(const TypeInfo& typeInfo, TaskContext& ctx)
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

        if (typeInfo.isBool())
            return MicroOpBits::B8;

        const uint64_t size = typeInfo.sizeOf(ctx);
        if (size == 1 || size == 2 || size == 4 || size == 8)
            return microOpBitsFromChunkSize(static_cast<uint32_t>(size));

        return MicroOpBits::B64;
    }

    TypeRef resolveCompareTypeRef(CodeGen& codeGen, const SemaNodeView& leftView, const SemaNodeView& rightView)
    {
        if (leftView.type()->isScalarNumeric() && rightView.type()->isScalarNumeric())
            return codeGen.typeMgr().promote(leftView.typeRef(), rightView.typeRef(), false);

        return leftView.typeRef();
    }

    void loadCompareOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef)
    {
        outReg                                 = codeGen.nextVirtualRegisterForType(operandTypeRef);
        const TypeInfo&   operandType          = codeGen.typeMgr().get(operandTypeRef);
        const MicroOpBits opBits               = compareOpBits(operandType, codeGen.ctx());
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
        const MicroOpBits srcBits = compareOpBits(srcType, codeGen.ctx());
        const MicroOpBits dstBits = compareOpBits(dstType, codeGen.ctx());

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
    }

    void materializeCompareOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, TypeRef compareTypeRef)
    {
        loadCompareOperand(outReg, codeGen, operandPayload, operandTypeRef);
        convertCompareOperand(outReg, codeGen, operandTypeRef, compareTypeRef);
    }

    MicroCond relationalCondition(TokenId tokId, bool unsignedOrFloatCompare)
    {
        switch (tokId)
        {
            case TokenId::SymLess:
                return unsignedOrFloatCompare ? MicroCond::Below : MicroCond::Less;
            case TokenId::SymLessEqual:
                return unsignedOrFloatCompare ? MicroCond::BelowOrEqual : MicroCond::LessOrEqual;
            case TokenId::SymGreater:
                return unsignedOrFloatCompare ? MicroCond::Above : MicroCond::Greater;
            case TokenId::SymGreaterEqual:
                return unsignedOrFloatCompare ? MicroCond::AboveOrEqual : MicroCond::GreaterOrEqual;

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

        const TypeRef     compareTypeRef = resolveCompareTypeRef(codeGen, leftView, rightView);
        if ((tokId == TokenId::SymEqualEqual || tokId == TokenId::SymBangEqual) && isStringCompareType(codeGen, compareTypeRef))
            return emitStringCompareBool(codeGen, tokId, leftPayload, rightPayload);

        const TypeInfo&   compareType    = codeGen.typeMgr().get(compareTypeRef);
        const MicroOpBits opBits         = compareOpBits(compareType, codeGen.ctx());
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        MicroReg leftReg, rightReg;
        materializeCompareOperand(leftReg, codeGen, leftPayload, leftOperandTypeRef, compareTypeRef);
        materializeCompareOperand(rightReg, codeGen, rightPayload, rightOperandTypeRef, compareTypeRef);

        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
        resultPayload.reg                 = codeGen.nextVirtualIntRegister();
        MicroBuilder& builder             = codeGen.builder();
        builder.emitCmpRegReg(leftReg, rightReg, opBits);

        auto cond = MicroCond::Equal;
        switch (tokId)
        {
            case TokenId::SymEqualEqual:
                cond = MicroCond::Equal;
                break;
            case TokenId::SymBangEqual:
                cond = MicroCond::NotEqual;
                break;

            case TokenId::SymLess:
            case TokenId::SymLessEqual:
            case TokenId::SymGreater:
            case TokenId::SymGreaterEqual:
                cond = relationalCondition(tokId, compareType.usesUnsignedConditions());
                break;

            default:
                SWC_UNREACHABLE();
        }

        builder.emitSetCondReg(resultPayload.reg, cond);
        builder.emitLoadZeroExtendRegReg(resultPayload.reg, resultPayload.reg, MicroOpBits::B32, MicroOpBits::B8);
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

        const TypeRef     compareTypeRef = resolveCompareTypeRef(codeGen, leftView, rightView);
        const TypeInfo&   compareType    = codeGen.typeMgr().get(compareTypeRef);
        const MicroOpBits opBits         = compareOpBits(compareType, codeGen.ctx());
        SWC_ASSERT(opBits != MicroOpBits::Zero);

        MicroReg leftReg, rightReg;
        materializeCompareOperand(leftReg, codeGen, leftPayload, leftOperandTypeRef, compareTypeRef);
        materializeCompareOperand(rightReg, codeGen, rightPayload, rightOperandTypeRef, compareTypeRef);

        MicroBuilder& builder = codeGen.builder();

        const bool      unsignedOrFloat = compareType.usesUnsignedConditions();
        const MicroCond lessCond        = unsignedOrFloat ? MicroCond::Below : MicroCond::Less;
        const MicroCond greatCond       = unsignedOrFloat ? MicroCond::Above : MicroCond::Greater;

        const MicroReg lessReg  = codeGen.nextVirtualIntRegister();
        const MicroReg greatReg = codeGen.nextVirtualIntRegister();
        builder.emitCmpRegReg(leftReg, rightReg, opBits);
        builder.emitSetCondReg(lessReg, lessCond);
        builder.emitLoadZeroExtendRegReg(lessReg, lessReg, MicroOpBits::B32, MicroOpBits::B8);
        builder.emitSetCondReg(greatReg, greatCond);
        builder.emitLoadZeroExtendRegReg(greatReg, greatReg, MicroOpBits::B32, MicroOpBits::B8);

        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
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
