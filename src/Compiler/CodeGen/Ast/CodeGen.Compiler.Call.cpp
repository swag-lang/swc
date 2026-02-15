#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/MicroAbiCall.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct NormalizedCallReturn
    {
        bool     isVoid           = true;
        bool     isFloat          = false;
        bool     isIndirect       = false;
        uint8_t  numBits          = 0;
        uint32_t indirectByteSize = 0;
    };

    NormalizedCallReturn normalizeCallReturn(CodeGen& codeGen, const CallConv& callConv, TypeRef typeRef)
    {
        constexpr NormalizedCallReturn out;
        if (typeRef.isInvalid())
            return out;

        auto&           ctx      = codeGen.ctx();
        const TypeRef   expanded = ctx.typeMgr().get(typeRef).unwrap(ctx, typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        const TypeInfo& ty       = ctx.typeMgr().get(expanded);

        if (ty.isVoid())
            return out;

        if (ty.isBool())
            return {.isVoid = false, .isFloat = false, .isIndirect = false, .numBits = 8};

        if (ty.isCharRune())
            return {.isVoid = false, .isFloat = false, .isIndirect = false, .numBits = 32};

        if (ty.isInt() && ty.payloadIntBits() != 0 && ty.payloadIntBits() <= 64)
            return {.isVoid = false, .isFloat = false, .isIndirect = false, .numBits = static_cast<uint8_t>(ty.payloadIntBits())};

        if (ty.isFloat() && (ty.payloadFloatBits() == 32 || ty.payloadFloatBits() == 64))
            return {.isVoid = false, .isFloat = true, .isIndirect = false, .numBits = static_cast<uint8_t>(ty.payloadFloatBits())};

        if (ty.isPointerLike() || ty.isNull())
            return {.isVoid = false, .isFloat = false, .isIndirect = false, .numBits = 64};

        if (ty.isStruct())
        {
            const uint64_t rawSize = ty.sizeOf(ctx);
            SWC_ASSERT(rawSize <= std::numeric_limits<uint32_t>::max());
            const uint32_t size        = static_cast<uint32_t>(rawSize);
            const auto     passingKind = callConv.classifyStructReturnPassing(size);
            if (passingKind == StructArgPassingKind::ByValue)
            {
                SWC_ASSERT(size == 1 || size == 2 || size == 4 || size == 8);
                return {.isVoid = false, .isFloat = false, .isIndirect = false, .numBits = static_cast<uint8_t>(size * 8)};
            }

            return {.isVoid = false, .isFloat = false, .isIndirect = true, .numBits = 64, .indirectByteSize = size};
        }

        SWC_ASSERT(false);
        return out;
    }

    void buildPreparedABIArguments(CodeGen& codeGen, std::span<const ResolvedCallArgument> args, SmallVector<MicroABICall::PreparedArg>& outArgs)
    {
        outArgs.clear();
        outArgs.reserve(args.size());

        for (const auto& arg : args)
        {
            const AstNodeRef argRef     = arg.argRef;
            const auto*      argPayload = codeGen.payload(argRef);
            SWC_ASSERT(argPayload != nullptr);

            MicroABICall::PreparedArg preparedArg;
            preparedArg.srcReg = CodeGen::payloadVirtualReg(*argPayload);

            const auto argView = codeGen.nodeView(argRef);
            if (argView.type)
            {
                preparedArg.isFloat = argView.type->isFloat();
                if (preparedArg.isFloat)
                    preparedArg.numBits = static_cast<uint8_t>(argView.type->payloadFloatBits());
            }

            switch (arg.passKind)
            {
                case CallArgumentPassKind::Direct:
                    preparedArg.kind = MicroABICall::PreparedArgKind::Direct;
                    break;

                case CallArgumentPassKind::InterfaceObject:
                    preparedArg.kind = MicroABICall::PreparedArgKind::InterfaceObject;
                    break;

                default:
                    SWC_UNREACHABLE();
            }

            outArgs.push_back(preparedArg);
        }
    }
}

Result AstCallExpr::codeGenPostNode(CodeGen& codeGen) const
{
    MicroInstrBuilder&    builder        = codeGen.builder();
    const auto            calleeView     = codeGen.nodeView(nodeExprRef);
    const auto*           calleePayload  = codeGen.payload(calleeView.nodeRef);
    SWC_ASSERT(calleePayload != nullptr);
    const SymbolFunction& calledFunction = codeGen.curNodeView().sym->cast<SymbolFunction>();
    const CallConvKind    callConvKind   = calledFunction.callConvKind();
    const CallConv&       callConv       = CallConv::get(callConvKind);
    const auto            normalizedRet  = normalizeCallReturn(codeGen, callConv, codeGen.curNodeView().typeRef);

    SmallVector<ResolvedCallArgument>      args;
    SmallVector<MicroABICall::PreparedArg> preparedArgs;
    codeGen.sema().appendResolvedCallArguments(codeGen.curNodeRef(), args);
    buildPreparedABIArguments(codeGen, args, preparedArgs);
    if (normalizedRet.isIndirect)
    {
        SWC_ASSERT(!callConv.intArgRegs.empty());
        SWC_ASSERT(normalizedRet.indirectByteSize != 0);

        void* indirectRetStorage = codeGen.ctx().compiler().allocateArray<uint8_t>(normalizedRet.indirectByteSize);

        MicroReg hiddenRetArgSrcReg = MicroReg::invalid();
        MicroReg hiddenRetArgTmpReg = MicroReg::invalid();
        SWC_ASSERT(callConv.tryPickIntScratchRegs(hiddenRetArgSrcReg, hiddenRetArgTmpReg));
        builder.encodeLoadRegImm(hiddenRetArgSrcReg, reinterpret_cast<uint64_t>(indirectRetStorage), MicroOpBits::B64, EncodeFlagsE::Zero);

        MicroABICall::PreparedArg hiddenRetArg;
        hiddenRetArg.srcReg  = hiddenRetArgSrcReg;
        hiddenRetArg.kind    = MicroABICall::PreparedArgKind::Direct;
        hiddenRetArg.isFloat = false;
        hiddenRetArg.numBits = 64;
        preparedArgs.insert(preparedArgs.begin(), hiddenRetArg);
    }

    const uint32_t numAbiArgs  = MicroABICall::prepareArgs(builder, callConvKind, preparedArgs);
    const auto&    nodePayload = codeGen.setPayload(codeGen.curNodeRef(), codeGen.curNodeView().typeRef);
    const MicroReg resultReg   = CodeGen::payloadVirtualReg(nodePayload);

    auto* resultStorage = codeGen.ctx().compiler().allocate<uint64_t>();
    *resultStorage      = 0;

    MicroABICall::Return retMeta;
    retMeta.valuePtr   = resultStorage;
    retMeta.isVoid     = normalizedRet.isVoid;
    retMeta.isFloat    = normalizedRet.isFloat;
    retMeta.isIndirect = normalizedRet.isIndirect;
    retMeta.numBits    = normalizedRet.numBits;
    const MicroReg calleeReg = CodeGen::payloadVirtualReg(*calleePayload);
    MicroABICall::callByReg(builder, callConvKind, calleeReg, numAbiArgs, retMeta);

    if (normalizedRet.isIndirect)
    {
        builder.encodeLoadRegImm(resultReg, reinterpret_cast<uint64_t>(resultStorage), MicroOpBits::B64, EncodeFlagsE::Zero);
        builder.encodeLoadMemReg(resultReg, 0, callConv.intReturn, MicroOpBits::B64, EncodeFlagsE::Zero);
        return Result::Continue;
    }

    builder.encodeLoadRegImm(resultReg, reinterpret_cast<uint64_t>(resultStorage), MicroOpBits::B64, EncodeFlagsE::Zero);
    return Result::Continue;
}

SWC_END_NAMESPACE();
