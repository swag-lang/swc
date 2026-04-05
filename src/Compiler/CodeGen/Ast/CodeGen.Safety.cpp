#include "pch.h"
#include "Compiler/CodeGen/Ast/CodeGen.Safety.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr std::string_view K_BOUND_CHECK_MESSAGE = "index is out of bounds";

    CodeGenNodePayload makeAddressPayloadFromConstant(CodeGen& codeGen, ConstantRef cstRef)
    {
        const ConstantValue& cst = codeGen.cstMgr().get(cstRef);
        SWC_ASSERT(cst.isStruct() || cst.isArray());

        const ByteSpan bytes = cst.isStruct() ? cst.getStruct() : cst.getArray();
        const uint64_t addr  = reinterpret_cast<uint64_t>(bytes.data());

        CodeGenNodePayload payload;
        payload.typeRef = cst.typeRef();
        payload.reg     = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegPtrReloc(payload.reg, addr, cstRef);
        payload.setIsAddress();
        return payload;
    }

    void appendDirectPreparedArg(SmallVector<ABICall::PreparedArg>& outArgs, CodeGen& codeGen, const CallConv& callConv, TypeRef argTypeRef, MicroReg srcReg)
    {
        const ABITypeNormalize::NormalizedType normalizedArg = ABITypeNormalize::normalize(codeGen.ctx(), callConv, argTypeRef, ABITypeNormalize::Usage::Argument);

        ABICall::PreparedArg arg;
        arg.srcReg      = srcReg;
        arg.kind        = ABICall::PreparedArgKind::Direct;
        arg.isFloat     = normalizedArg.isFloat;
        arg.isAddressed = false;
        arg.numBits     = normalizedArg.numBits;
        outArgs.push_back(arg);
    }

    SymbolFunction* runtimePanicFunction(CodeGen& codeGen)
    {
        if (const auto* payload = codeGen.sema().codeGenPayload<CodeGenNodePayload>(codeGen.curNodeRef());
            payload && payload->runtimeFunctionSymbol != nullptr)
        {
            return payload->runtimeFunctionSymbol;
        }

        const IdentifierRef idRef = codeGen.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::Panic);
        if (idRef.isInvalid())
            return nullptr;

        return codeGen.compiler().runtimeFunctionSymbol(idRef);
    }

    Result emitRuntimePanicCall(CodeGen& codeGen, SymbolFunction& runtimeFunction, const AstNode& node, std::string_view message)
    {
        codeGen.function().addCallDependency(&runtimeFunction);
        SWC_ASSERT(runtimeFunction.parameters().size() == 2);

        const CallConvKind                callConvKind = runtimeFunction.callConvKind();
        const CallConv&                   callConv     = CallConv::get(callConvKind);
        SmallVector<ABICall::PreparedArg> preparedArgs;
        preparedArgs.reserve(2);

        const ConstantValue  messageTextValue = ConstantValue::makeString(codeGen.ctx(), message);
        const ConstantRef    messageTextRef   = codeGen.cstMgr().addConstant(codeGen.ctx(), messageTextValue);
        const ConstantValue& messageTextCst   = codeGen.cstMgr().get(messageTextRef);
        const ConstantRef    messageCstRef    = CodeGenConstantHelpers::materializeRuntimeBufferConstant(codeGen, codeGen.typeMgr().typeString(), messageTextCst.getString().data(), messageTextCst.getString().size());
        SWC_ASSERT(messageCstRef.isValid());
        const auto messageArg = makeAddressPayloadFromConstant(codeGen, messageCstRef);
        appendDirectPreparedArg(preparedArgs, codeGen, callConv, runtimeFunction.parameters()[0]->typeRef(), messageArg.reg);

        const ConstantRef sourceLocCstRef = ConstantHelpers::makeSourceCodeLocation(codeGen.sema(), node);
        SWC_ASSERT(sourceLocCstRef.isValid());
        const auto sourceLocArg = makeAddressPayloadFromConstant(codeGen, sourceLocCstRef);
        appendDirectPreparedArg(preparedArgs, codeGen, callConv, runtimeFunction.parameters()[1]->typeRef(), sourceLocArg.reg);

        MicroBuilder&               builder      = codeGen.builder();
        const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, callConvKind, preparedArgs.span());
        if (runtimeFunction.isForeign())
            ABICall::callExtern(builder, callConvKind, &runtimeFunction, preparedCall);
        else
            ABICall::callLocal(builder, callConvKind, &runtimeFunction, preparedCall);

        return Result::Continue;
    }

    MicroReg materializeIndexBoundReg(CodeGen& codeGen, const TypeInfo& indexedType, const CodeGenNodePayload& indexedPayload)
    {
        MicroBuilder&  builder  = codeGen.builder();
        const MicroReg countReg = codeGen.nextVirtualIntRegister();

        if (indexedType.isArray())
        {
            const uint64_t count = indexedType.payloadArrayDims().empty() ? 0 : indexedType.payloadArrayDims()[0];
            builder.emitLoadRegImm(countReg, ApInt(count, 64), MicroOpBits::B64);
            return countReg;
        }

        if (indexedType.isString())
        {
            builder.emitLoadRegMem(countReg, indexedPayload.reg, offsetof(Runtime::String, length), MicroOpBits::B64);
            return countReg;
        }

        if (indexedType.isSlice() || indexedType.isAnyVariadic())
        {
            builder.emitLoadRegMem(countReg, indexedPayload.reg, offsetof(Runtime::Slice<std::byte>, count), MicroOpBits::B64);
            return countReg;
        }

        SWC_UNREACHABLE();
    }
}

Result CodeGenSafety::emitBoundCheck(CodeGen& codeGen, AstNodeRef indexRef, const TypeInfo& indexedType, const CodeGenNodePayload& indexedPayload, MicroReg indexReg)
{
    if (!indexedType.isIndexable())
        return Result::Continue;

    const auto* nodePayload = codeGen.sema().codeGenPayload<CodeGenNodePayload>(codeGen.curNodeRef());
    if (!nodePayload || !nodePayload->hasRuntimeSafety(Runtime::SafetyWhat::BoundCheck))
        return Result::Continue;

    SymbolFunction* panicFunction = runtimePanicFunction(codeGen);
    SWC_ASSERT(panicFunction != nullptr);

    MicroBuilder&       builder     = codeGen.builder();
    const MicroReg      countReg    = materializeIndexBoundReg(codeGen, indexedType, indexedPayload);
    const MicroLabelRef inBoundsRef = builder.createLabel();
    builder.emitCmpRegReg(indexReg, countReg, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, inBoundsRef);
    SWC_RESULT(emitRuntimePanicCall(codeGen, *panicFunction, codeGen.node(indexRef), K_BOUND_CHECK_MESSAGE));
    builder.placeLabel(inBoundsRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
