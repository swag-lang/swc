#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenConstantHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenReferenceHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Main/CompilerInstance.h"
#include "Support/Math/Fold.h"

SWC_BEGIN_NAMESPACE();

namespace
{
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

    TypeRef normalizeIntrinsicLifecycleTypeRef(CodeGen& codeGen, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return typeRef;

        const TypeRef rawTypeRef = codeGen.typeMgr().get(typeRef).unwrap(codeGen.ctx(), typeRef, TypeExpandE::Alias);
        if (rawTypeRef.isValid())
            return rawTypeRef;
        return typeRef;
    }

    bool intrinsicInitPreservesAliasType(const TypeInfo& rawType)
    {
        return rawType.isEnum() ||
               rawType.isBool() ||
               rawType.isIntLike() ||
               rawType.isFloat() ||
               rawType.isAnyPointer() ||
               rawType.isReference() ||
               rawType.isCString() ||
               rawType.isTypeInfo() ||
               (rawType.isFunction() && !rawType.isLambdaClosure());
    }

    bool intrinsicInitTypeUsesFloatPayload(CodeGen& codeGen, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        const TypeInfo& typeInfo       = codeGen.typeMgr().get(typeRef);
        const TypeRef   storageTypeRef = typeInfo.unwrapAliasEnum(codeGen.ctx(), typeRef);
        return codeGen.typeMgr().get(storageTypeRef).isFloat();
    }

    TypeRef normalizeIntrinsicInitTypeRef(CodeGen& codeGen, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        if (!typeInfo.isAlias())
            return typeRef;

        const TypeRef rawTypeRef = codeGen.typeMgr().get(typeRef).unwrap(codeGen.ctx(), typeRef, TypeExpandE::Alias);
        if (rawTypeRef.isValid() && !intrinsicInitPreservesAliasType(codeGen.typeMgr().get(rawTypeRef)))
            return rawTypeRef;
        return typeRef;
    }

    TypeRef intrinsicLifecycleTargetTypeRef(CodeGen& codeGen, TypeRef whatTypeRef, const bool hasExplicitCount)
    {
        whatTypeRef = normalizeIntrinsicLifecycleTypeRef(codeGen, whatTypeRef);
        if (!whatTypeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& whatType = codeGen.typeMgr().get(whatTypeRef);
        if (whatType.isReference() || whatType.isAnyPointer())
            whatTypeRef = normalizeIntrinsicLifecycleTypeRef(codeGen, whatType.payloadTypeRef());

        if (!hasExplicitCount)
            return whatTypeRef;

        while (whatTypeRef.isValid())
        {
            const TypeInfo& currentType = codeGen.typeMgr().get(whatTypeRef);
            if (!currentType.isArray())
                break;
            whatTypeRef = normalizeIntrinsicLifecycleTypeRef(codeGen, currentType.payloadArrayElemTypeRef());
        }

        return whatTypeRef;
    }

    MicroReg materializeIntrinsicLifecycleAddress(CodeGen& codeGen, AstNodeRef whatRef)
    {
        const CodeGenNodePayload& whatPayload = codeGen.payload(whatRef);
        const TypeRef             whatTypeRef = whatPayload.effectiveTypeRef(codeGen.viewType(whatRef).typeRef());
        SWC_ASSERT(whatTypeRef.isValid());
        if (whatTypeRef.isInvalid())
            return MicroReg::invalid();

        const TypeRef   normalizedWhatTypeRef = normalizeIntrinsicLifecycleTypeRef(codeGen, whatTypeRef);
        const TypeInfo& whatType              = codeGen.typeMgr().get(normalizedWhatTypeRef);
        if (whatType.isReference() || whatType.isAnyPointer())
        {
            if (!whatPayload.isAddress())
                return whatPayload.reg;

            const MicroReg pointerReg = codeGen.nextVirtualIntRegister();
            codeGen.builder().emitLoadRegMem(pointerReg, whatPayload.reg, 0, MicroOpBits::B64);
            return pointerReg;
        }

        SWC_ASSERT(whatPayload.isAddress());
        return whatPayload.reg;
    }

    MicroReg materializeIntrinsicLifecycleCountReg(CodeGen& codeGen, AstNodeRef countRef)
    {
        const CodeGenNodePayload& countPayload = codeGen.payload(countRef);
        const MicroReg            countReg     = codeGen.nextVirtualIntRegister();
        if (countPayload.isAddress())
            codeGen.builder().emitLoadRegMem(countReg, countPayload.reg, 0, MicroOpBits::B64);
        else
            codeGen.builder().emitLoadRegReg(countReg, countPayload.reg, MicroOpBits::B64);
        return countReg;
    }

    struct IntrinsicInitTarget
    {
        TypeRef  fillTypeRef   = TypeRef::invalid();
        uint32_t implicitCount = 1;
    };

    IntrinsicInitTarget resolveIntrinsicInitTarget(CodeGen& codeGen, TypeRef whatTypeRef)
    {
        IntrinsicInitTarget result;
        result.fillTypeRef = normalizeIntrinsicInitTypeRef(codeGen, whatTypeRef);
        if (!result.fillTypeRef.isValid())
            return result;

        const TypeInfo& whatType = codeGen.typeMgr().get(result.fillTypeRef);
        if (whatType.isReference() || whatType.isAnyPointer())
            result.fillTypeRef = normalizeIntrinsicInitTypeRef(codeGen, whatType.payloadTypeRef());

        uint64_t totalCount = 1;
        while (result.fillTypeRef.isValid())
        {
            const TypeInfo& currentType = codeGen.typeMgr().get(result.fillTypeRef);
            if (!currentType.isArray())
                break;

            for (const uint64_t dim : currentType.payloadArrayDims())
            {
                totalCount *= dim;
                SWC_ASSERT(totalCount <= std::numeric_limits<uint32_t>::max());
            }

            result.fillTypeRef = normalizeIntrinsicInitTypeRef(codeGen, currentType.payloadArrayElemTypeRef());
        }

        result.implicitCount = static_cast<uint32_t>(totalCount);
        return result;
    }

    void collectIntrinsicInitArgs(SmallVector<AstNodeRef>& outArgs, const Ast& ast, const AstIntrinsicInit& node)
    {
        ast.appendNodes(outArgs, node.spanArgsRef);
    }

    bool intrinsicInitTreatsArgsAsStructTuple(CodeGen& codeGen, TypeRef fillTypeRef, const SmallVector<AstNodeRef>& args)
    {
        if (args.empty() || !fillTypeRef.isValid())
            return false;

        const TypeInfo& fillType = codeGen.typeMgr().get(fillTypeRef);
        if (!fillType.isStruct())
            return false;
        if (args.size() != 1)
            return true;

        const SemaNodeView argView = codeGen.viewType(args.front());
        if (!argView.type())
            return true;
        if (argView.typeRef() == fillTypeRef)
            return false;

        return !argView.type()->isStruct() && !argView.type()->isAggregateStruct();
    }

    CodeGenNodePayload makeIntrinsicInitZeroScalarPayload(CodeGen& codeGen, TypeRef fillTypeRef)
    {
        CodeGenNodePayload result;
        result.typeRef = fillTypeRef;
        result.reg     = codeGen.nextVirtualRegisterForType(fillTypeRef);
        result.setIsValue();

        const TypeInfo& fillType  = codeGen.typeMgr().get(fillTypeRef);
        const auto      storeBits = CodeGenTypeHelpers::scalarStoreBits(fillType, codeGen.ctx());
        if (storeBits == MicroOpBits::Zero)
        {
            const ConstantRef zeroCstRef = codeGen.cstMgr().addZeroPayloadConstant(codeGen.ctx(), fillTypeRef);
            SWC_ASSERT(zeroCstRef.isValid());
            return makeAddressPayloadFromConstant(codeGen, zeroCstRef);
        }

        codeGen.builder().emitClearReg(result.reg, storeBits);
        return result;
    }

    Result emitIntrinsicInitStore(CodeGen& codeGen, TypeRef fillTypeRef, const CodeGenNodePayload& srcPayload, MicroReg dstAddressReg)
    {
        TaskContext&    ctx       = codeGen.ctx();
        const TypeInfo& fillType  = codeGen.typeMgr().get(fillTypeRef);
        const auto      storeBits = CodeGenTypeHelpers::scalarStoreBits(fillType, ctx);
        if (storeBits != MicroOpBits::Zero)
        {
            MicroBuilder& builder = codeGen.builder();
            MicroReg      srcReg  = srcPayload.reg;
            if (srcPayload.isAddress())
            {
                srcReg = codeGen.nextVirtualRegisterForType(fillTypeRef);
                builder.emitLoadRegMem(srcReg, srcPayload.reg, 0, storeBits);
            }

            builder.emitLoadMemReg(dstAddressReg, 0, srcReg, storeBits);
            return Result::Continue;
        }

        const uint64_t sizeOf = fillType.sizeOf(ctx);
        SWC_ASSERT(sizeOf > 0 && sizeOf <= std::numeric_limits<uint32_t>::max());
        if (srcPayload.isAddress())
        {
            CodeGenMemoryHelpers::emitMemCopy(codeGen, dstAddressReg, srcPayload.reg, static_cast<uint32_t>(sizeOf));
            return Result::Continue;
        }

        CodeGenMemoryHelpers::storePayloadToAddress(codeGen, dstAddressReg, srcPayload, static_cast<uint32_t>(sizeOf));
        return Result::Continue;
    }

    Result buildIntrinsicInitTuplePayload(CodeGen& codeGen, const AstIntrinsicInit& node, TypeRef fillTypeRef, const SmallVector<AstNodeRef>& args, CodeGenNodePayload& outPayload)
    {
        SWC_UNUSED(node);

        const TypeInfo& fillType = codeGen.typeMgr().get(fillTypeRef);
        SWC_ASSERT(fillType.isStruct());

        const MicroReg storageReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
        SWC_RESULT(CodeGenFunctionHelpers::emitStructDefaultValue(codeGen, fillTypeRef, storageReg));

        const auto& fields = fillType.payloadSymStruct().fields();
        for (size_t i = 0; i < args.size(); ++i)
        {
            SWC_ASSERT(fields[i] != nullptr);
            const MicroReg fieldAddressReg = fields[i]->offset() ? codeGen.offsetAddressReg(storageReg, fields[i]->offset()) : storageReg;
            SWC_RESULT(emitIntrinsicInitStore(codeGen, fields[i]->typeRef(), codeGen.payload(args[i]), fieldAddressReg));
        }

        outPayload.typeRef = fillTypeRef;
        outPayload.reg     = storageReg;
        outPayload.setIsAddress();
        return Result::Continue;
    }

    bool tryIntrinsicInitConstantCount(CodeGen& codeGen, AstNodeRef countRef, uint32_t& outCount)
    {
        outCount = 0;
        if (!countRef.isValid())
            return false;

        const SemaNodeView countView = codeGen.viewTypeConstant(countRef);
        if (countView.cstRef().isInvalid() || !countView.type() || !countView.type()->isIntLike())
            return false;

        const ConstantValue& countCst = codeGen.cstMgr().get(countView.cstRef());
        const uint64_t       count    = countCst.getIntLike().as64();
        SWC_ASSERT(count <= std::numeric_limits<uint32_t>::max());
        outCount = static_cast<uint32_t>(count);
        return true;
    }

    Result emitIntrinsicInitRepeatConst(CodeGen& codeGen, TypeRef fillTypeRef, const CodeGenNodePayload& srcPayload, MicroReg dstAddressReg, uint32_t count)
    {
        if (!count)
            return Result::Continue;
        if (count == 1)
            return emitIntrinsicInitStore(codeGen, fillTypeRef, srcPayload, dstAddressReg);

        const TypeInfo& fillType = codeGen.typeMgr().get(fillTypeRef);
        const uint64_t  sizeOf   = fillType.sizeOf(codeGen.ctx());
        SWC_ASSERT(sizeOf > 0 && sizeOf <= std::numeric_limits<uint32_t>::max());

        const auto storeBits = CodeGenTypeHelpers::scalarStoreBits(fillType, codeGen.ctx());
        if (storeBits != MicroOpBits::Zero && !intrinsicInitTypeUsesFloatPayload(codeGen, fillTypeRef))
        {
            MicroReg fillReg = srcPayload.reg;
            if (srcPayload.isAddress())
            {
                fillReg = codeGen.nextVirtualIntRegister();
                codeGen.builder().emitLoadRegMem(fillReg, srcPayload.reg, 0, storeBits);
            }

            CodeGenMemoryHelpers::emitMemFill(codeGen, dstAddressReg, fillReg, static_cast<uint32_t>(sizeOf), count);
            return Result::Continue;
        }

        if (srcPayload.isAddress())
        {
            CodeGenMemoryHelpers::emitMemRepeatCopy(codeGen, dstAddressReg, srcPayload.reg, static_cast<uint32_t>(sizeOf), count);
            return Result::Continue;
        }

        const MicroReg cursorReg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegReg(cursorReg, dstAddressReg, MicroOpBits::B64);
        for (uint32_t i = 0; i < count; ++i)
        {
            SWC_RESULT(emitIntrinsicInitStore(codeGen, fillTypeRef, srcPayload, cursorReg));
            if (i + 1 != count)
                codeGen.builder().emitOpBinaryRegImm(cursorReg, ApInt(sizeOf, 64), MicroOp::Add, MicroOpBits::B64);
        }

        return Result::Continue;
    }

    Result emitIntrinsicInitRepeatRuntime(CodeGen& codeGen, TypeRef fillTypeRef, const CodeGenNodePayload& srcPayload, MicroReg dstAddressReg, MicroReg countReg)
    {
        const TypeInfo& fillType = codeGen.typeMgr().get(fillTypeRef);
        const uint64_t  sizeOf   = fillType.sizeOf(codeGen.ctx());
        SWC_ASSERT(sizeOf > 0);

        MicroBuilder&       builder   = codeGen.builder();
        const MicroLabelRef loopLabel = builder.createLabel();
        const MicroLabelRef doneLabel = builder.createLabel();
        const MicroReg      cursorReg = codeGen.nextVirtualIntRegister();
        const MicroReg      iterReg   = codeGen.nextVirtualIntRegister();

        builder.emitLoadRegReg(cursorReg, dstAddressReg, MicroOpBits::B64);
        builder.emitLoadRegReg(iterReg, countReg, MicroOpBits::B64);
        builder.emitCmpRegImm(iterReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);

        builder.placeLabel(loopLabel);
        SWC_RESULT(emitIntrinsicInitStore(codeGen, fillTypeRef, srcPayload, cursorReg));
        builder.emitOpBinaryRegImm(cursorReg, ApInt(sizeOf, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(iterReg, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitCmpRegImm(iterReg, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B32, loopLabel);
        builder.placeLabel(doneLabel);
        return Result::Continue;
    }

    Result emitIntrinsicInitStmt(CodeGen& codeGen, const AstIntrinsicInit& node)
    {
        SmallVector<AstNodeRef> args;
        collectIntrinsicInitArgs(args, codeGen.ast(), node);

        const CodeGenNodePayload* whatPayload = codeGen.safePayload(node.nodeWhatRef);
        if ((!whatPayload || !whatPayload->reg.isValid()) && node.nodeWhatRef.isValid())
            SWC_RESULT(codeGen.emitNodeNow(node.nodeWhatRef));

        const IntrinsicInitTarget targetInfo = resolveIntrinsicInitTarget(codeGen, codeGen.viewType(node.nodeWhatRef).typeRef());
        SWC_ASSERT(targetInfo.fillTypeRef.isValid());
        if (targetInfo.fillTypeRef.isInvalid())
            return Result::Continue;

        const MicroReg dstAddressReg = materializeIntrinsicLifecycleAddress(codeGen, node.nodeWhatRef);
        SWC_ASSERT(dstAddressReg.isValid());
        if (!dstAddressReg.isValid())
            return Result::Continue;

        const TypeInfo& fillType         = codeGen.typeMgr().get(targetInfo.fillTypeRef);
        uint32_t        constantCount    = 0;
        const bool      hasConstantCount = tryIntrinsicInitConstantCount(codeGen, node.nodeCountRef, constantCount);
        if (args.empty() && fillType.isStruct())
        {
            if (hasConstantCount)
                return CodeGenFunctionHelpers::emitStructDefaultValue(codeGen, targetInfo.fillTypeRef, dstAddressReg, constantCount);

            if (node.nodeCountRef.isValid())
            {
                const MicroReg countReg = materializeIntrinsicLifecycleCountReg(codeGen, node.nodeCountRef);
                return CodeGenFunctionHelpers::emitStructDefaultValue(codeGen, targetInfo.fillTypeRef, dstAddressReg, countReg);
            }

            return CodeGenFunctionHelpers::emitStructDefaultValue(codeGen, targetInfo.fillTypeRef, dstAddressReg, targetInfo.implicitCount);
        }

        CodeGenNodePayload srcPayload;
        if (args.empty())
        {
            srcPayload = makeIntrinsicInitZeroScalarPayload(codeGen, targetInfo.fillTypeRef);
        }
        else if (intrinsicInitTreatsArgsAsStructTuple(codeGen, targetInfo.fillTypeRef, args))
        {
            SWC_RESULT(buildIntrinsicInitTuplePayload(codeGen, node, targetInfo.fillTypeRef, args, srcPayload));
        }
        else
        {
            srcPayload = codeGen.payload(args.front());
        }

        if (hasConstantCount)
            return emitIntrinsicInitRepeatConst(codeGen, targetInfo.fillTypeRef, srcPayload, dstAddressReg, constantCount);

        if (node.nodeCountRef.isValid())
        {
            const MicroReg countReg = materializeIntrinsicLifecycleCountReg(codeGen, node.nodeCountRef);
            return emitIntrinsicInitRepeatRuntime(codeGen, targetInfo.fillTypeRef, srcPayload, dstAddressReg, countReg);
        }

        return emitIntrinsicInitRepeatConst(codeGen, targetInfo.fillTypeRef, srcPayload, dstAddressReg, targetInfo.implicitCount);
    }

    Result emitIntrinsicLifecycleStmt(CodeGen& codeGen, AstNodeRef whatRef, AstNodeRef countRef, const CodeGen::LifecycleKind lifecycleKind)
    {
        const TypeRef targetTypeRef = intrinsicLifecycleTargetTypeRef(codeGen, codeGen.viewType(whatRef).typeRef(), countRef.isValid());
        if (!codeGen.hasLifecycle(targetTypeRef, lifecycleKind))
            return Result::Continue;

        const CodeGenNodePayload* whatPayload = codeGen.safePayload(whatRef);
        if ((!whatPayload || !whatPayload->reg.isValid()) && whatRef.isValid())
            SWC_RESULT(codeGen.emitNodeNow(whatRef));

        const MicroReg addressReg = materializeIntrinsicLifecycleAddress(codeGen, whatRef);
        SWC_ASSERT(addressReg.isValid());
        if (!addressReg.isValid())
            return Result::Continue;

        if (countRef.isValid())
        {
            const MicroReg countReg = materializeIntrinsicLifecycleCountReg(codeGen, countRef);
            return codeGen.emitLifecycle(targetTypeRef, lifecycleKind, addressReg, countReg);
        }

        return codeGen.emitLifecycle(targetTypeRef, lifecycleKind, addressReg);
    }

    MicroReg materializeCountLikeBaseReg(const CodeGen& codeGen, const CodeGenNodePayload& payload)
    {
        SWC_UNUSED(codeGen);
        return payload.reg;
    }

    using CodeGenFunctionHelpers::resolveStoredVariablePayload;

    CodeGenNodePayload countOfExprPayload(CodeGen& codeGen, AstNodeRef exprRef)
    {
        if (const auto* payload = codeGen.safePayload(exprRef))
        {
            if (payload->reg.isValid())
                return *payload;
        }

        // `@countof` can target a stored symbol not reached through the current AST walk, so fall
        // back to sema-owned symbol/type views before using the transient node payload.
        const SemaNodeView storedView = codeGen.sema().viewStored(exprRef, SemaNodeViewPartE::Symbol);
        if (storedView.sym() && storedView.sym()->isVariable())
        {
            const auto& symVar = storedView.sym()->cast<SymbolVariable>();
            if (symVar.isClosureCapture() ||
                CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, symVar) ||
                symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
                symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) ||
                symVar.hasGlobalStorage() ||
                codeGen.variablePayload(symVar) ||
                (codeGen.localStackBaseReg().isValid() && symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal)))
                return resolveStoredVariablePayload(codeGen, symVar);
        }

        return codeGen.payload(exprRef);
    }

    SemaNodeView countOfExprView(CodeGen& codeGen, AstNodeRef exprRef)
    {
        const SemaNodeView storedView = codeGen.sema().viewStored(exprRef, SemaNodeViewPartE::Type);
        if (storedView.type() != nullptr)
            return storedView;
        return codeGen.viewType(exprRef);
    }

    Result codeGenCountOf(CodeGen& codeGen, AstNodeRef exprRef)
    {
        const auto* countPayload = codeGen.sema().semaPayload<CountOfSpecOpPayload>(codeGen.curNodeRef());
        if (countPayload && countPayload->calledFn != nullptr)
        {
            codeGen.sema().setSymbol(codeGen.curNodeRef(), countPayload->calledFn);
            return CodeGenCallHelpers::codeGenCallExprCommon(codeGen, AstNodeRef::invalid());
        }

        MicroBuilder&      builder       = codeGen.builder();
        const SemaNodeView exprView      = countOfExprView(codeGen, exprRef);
        CodeGenNodePayload exprPayload   = countOfExprPayload(codeGen, exprRef);
        TypeRef            exprTypeRef   = exprPayload.effectiveTypeRef(exprView.typeRef());
        const TypeRef      resultTypeRef = codeGen.curViewType().typeRef();
        CodeGenReferenceHelpers::unwrapAliasRefPayload(codeGen, exprPayload, exprTypeRef);
        SWC_ASSERT(exprTypeRef.isValid());
        const TypeInfo& exprType = codeGen.typeMgr().get(exprTypeRef);

        if (exprType.isInt())
        {
            const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
            const uint32_t            intBits       = exprType.payloadIntBitsOr(64);
            const MicroOpBits         opBits        = microOpBitsFromBitWidth(intBits);
            if (exprPayload.isAddress())
                builder.emitLoadRegMem(resultPayload.reg, exprPayload.reg, 0, opBits);
            else
                builder.emitLoadRegReg(resultPayload.reg, exprPayload.reg, opBits);
            return Result::Continue;
        }

        // The runtime element count is always a natural-width `u64` (slice/string `count`/`length`
        // fields, or a byte scan for C strings), so type the produced value as `u64` rather than the
        // surrounding context type. Using the context type (e.g. `bool` for `if !@countof(s)`) made the
        // value be loaded as 64 bits but compared/consumed at the narrower width, so counts that are a
        // multiple of 256 (low byte zero) were wrongly seen as zero. Any narrowing the context needs is
        // handled by the normal conversion path on the consumer side.
        const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.typeMgr().typeU64());
        const MicroReg            baseReg       = materializeCountLikeBaseReg(codeGen, exprPayload);
        if (exprType.isCString())
        {
            // C strings do not carry a cached length in their runtime representation, so count bytes until
            // the terminating zero.
            const MicroReg cstrReg = codeGen.nextVirtualIntRegister();
            if (exprPayload.isAddress())
                builder.emitLoadRegMem(cstrReg, baseReg, 0, MicroOpBits::B64);
            else
                builder.emitLoadRegReg(cstrReg, baseReg, MicroOpBits::B64);

            builder.emitClearReg(resultPayload.reg, MicroOpBits::B64);

            const MicroLabelRef loopLabel = builder.createLabel();
            const MicroLabelRef doneLabel = builder.createLabel();
            builder.emitCmpRegImm(cstrReg, ApInt(0, 64), MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);

            const MicroReg scanReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(scanReg, cstrReg, MicroOpBits::B64);
            builder.placeLabel(loopLabel);

            const MicroReg charReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(charReg, scanReg, 0, MicroOpBits::B8);
            builder.emitCmpRegImm(charReg, ApInt(0, 64), MicroOpBits::B8);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);
            builder.emitOpBinaryRegImm(scanReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(resultPayload.reg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, loopLabel);
            builder.placeLabel(doneLabel);
            return Result::Continue;
        }

        if (exprType.isString())
        {
            builder.emitLoadRegMem(resultPayload.reg, baseReg, offsetof(Runtime::String, length), MicroOpBits::B64);
            return Result::Continue;
        }

        if (exprType.isSlice() || exprType.isAnyVariadic())
        {
            builder.emitLoadRegMem(resultPayload.reg, baseReg, offsetof(Runtime::Slice<std::byte>, count), MicroOpBits::B64);
            return Result::Continue;
        }

        SWC_INTERNAL_ERROR();
    }

}

Result AstIntrinsicValue::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.token(codeRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicIndex:
        {
            const MicroReg indexReg = codeGen.frame().currentLoopIndexReg();
            SWC_ASSERT(indexReg.isValid());

            TypeRef indexTypeRef = codeGen.frame().currentLoopIndexTypeRef();
            if (indexTypeRef.isInvalid())
                indexTypeRef = codeGen.curViewType().typeRef();

            const CodeGenNodePayload& payload = codeGen.setPayloadValue(codeGen.curNodeRef(), indexTypeRef);
            auto                      opBits  = MicroOpBits::B64;
            if (indexTypeRef.isValid())
            {
                const uint64_t sizeOfType = codeGen.typeMgr().get(indexTypeRef).sizeOf(codeGen.ctx());
                if (sizeOfType == 1 || sizeOfType == 2 || sizeOfType == 4 || sizeOfType == 8)
                    opBits = microOpBitsFromChunkSize(static_cast<uint32_t>(sizeOfType));
            }

            codeGen.builder().emitLoadRegReg(payload.reg, indexReg, opBits);
            return Result::Continue;
        }

        default:
            SWC_UNREACHABLE();
    }
}

Result AstIntrinsicInit::codeGenPostNode(CodeGen& codeGen) const
{
    return emitIntrinsicInitStmt(codeGen, *this);
}

Result AstIntrinsicDrop::codeGenPostNode(CodeGen& codeGen) const
{
    return emitIntrinsicLifecycleStmt(codeGen, nodeWhatRef, nodeCountRef, CodeGen::LifecycleKind::Drop);
}

Result AstIntrinsicPostCopy::codeGenPostNode(CodeGen& codeGen) const
{
    return emitIntrinsicLifecycleStmt(codeGen, nodeWhatRef, nodeCountRef, CodeGen::LifecycleKind::PostCopy);
}

Result AstIntrinsicPostMove::codeGenPostNode(CodeGen& codeGen) const
{
    return emitIntrinsicLifecycleStmt(codeGen, nodeWhatRef, nodeCountRef, CodeGen::LifecycleKind::PostMove);
}

Result AstCountOfExpr::codeGenPostNode(CodeGen& codeGen) const
{
    return codeGenCountOf(codeGen, nodeExprRef);
}

SWC_END_NAMESPACE();
