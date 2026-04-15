#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenConstantHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    MicroOpBits identifierPayloadCopyBits(CodeGen& codeGen, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return MicroOpBits::B64;

        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        return CodeGenTypeHelpers::copyBits(typeInfo);
    }

    CodeGenNodePayload resolveIdentifierVariablePayload(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        if (symVar.isClosureCapture())
            return CodeGenFunctionHelpers::resolveClosureCapturePayload(codeGen, symVar);

        if (CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, symVar))
            return CodeGenFunctionHelpers::resolveCallerReturnStoragePayload(codeGen, symVar);

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        {
            const SymbolFunction& symbolFunc = codeGen.function();
            return CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, symbolFunc, symVar);
        }

        const CodeGenNodePayload* symbolPayload = codeGen.variablePayload(symVar);
        if (symbolPayload)
            return *symbolPayload;

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
            return codeGen.resolveLocalStackPayload(symVar);
        if (codeGen.localStackBaseReg().isValid() && symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal))
            return codeGen.resolveLocalStackPayload(symVar);

        if (symVar.hasGlobalStorage())
        {
            CodeGenNodePayload globalPayload;
            globalPayload.typeRef = symVar.typeRef();
            globalPayload.setIsAddress();
            globalPayload.reg = codeGen.nextVirtualIntRegister();
            codeGen.builder().emitLoadRegDataSegmentReloc(globalPayload.reg, symVar.globalStorageKind(), symVar.offset());
            return globalPayload;
        }

        SWC_UNREACHABLE();
    }

    bool emitDefaultValueToLocalStack(CodeGen& codeGen, const SymbolVariable& symVar, const MicroReg dstReg, uint32_t localSize)
    {
        const ConstantRef defaultValueRef = symVar.defaultValueRef();
        if (defaultValueRef.isInvalid())
            return false;

        const ConstantValue& defaultValue = codeGen.cstMgr().get(defaultValueRef);

        ByteSpan rawBytes;
        if (defaultValue.isStruct())
        {
            SWC_ASSERT(defaultValue.getStruct().size() == localSize);
            rawBytes = defaultValue.getStruct();
        }
        else if (defaultValue.isArray())
        {
            SWC_ASSERT(defaultValue.getArray().size() == localSize);
            rawBytes = defaultValue.getArray();
        }
        else
            return false;

        // Classify the payload so we can avoid materializing a static constant + memcpy
        // for the common cases where the default is mostly (or entirely) zero.
        bool allZero = true;
        for (const std::byte b : rawBytes)
        {
            if (b != std::byte{})
            {
                allZero = false;
                break;
            }
        }
        if (allZero)
        {
            CodeGenMemoryHelpers::emitMemZero(codeGen, dstReg, localSize);
            return true;
        }

        constexpr uint32_t sparseChunkSize  = 8;
        constexpr uint32_t sparseStoreLimit = 4;
        if (localSize >= sparseChunkSize * 2 && (localSize % sparseChunkSize) == 0)
        {
            uint32_t nonZeroChunks = 0;
            for (uint32_t off = 0; off < localSize; off += sparseChunkSize)
            {
                for (uint32_t i = 0; i < sparseChunkSize; ++i)
                {
                    if (rawBytes[off + i] != std::byte{})
                    {
                        ++nonZeroChunks;
                        break;
                    }
                }
                if (nonZeroChunks > sparseStoreLimit)
                    break;
            }
            if (nonZeroChunks <= sparseStoreLimit)
            {
                MicroBuilder& builder = codeGen.builder();
                CodeGenMemoryHelpers::emitMemZero(codeGen, dstReg, localSize);
                for (uint32_t off = 0; off < localSize; off += sparseChunkSize)
                {
                    uint64_t value = 0;
                    for (uint32_t i = 0; i < sparseChunkSize; ++i)
                        value |= static_cast<uint64_t>(static_cast<uint8_t>(rawBytes[off + i])) << (i * 8);
                    if (value != 0)
                        builder.emitLoadMemImm(dstReg, off, ApInt(value, 64), MicroOpBits::B64);
                }
                return true;
            }
        }

        const ConstantRef safeDefaultValueRef = CodeGenConstantHelpers::ensureStaticPayloadConstant(codeGen, defaultValueRef, symVar.typeRef());
        if (safeDefaultValueRef.isInvalid())
            return false;

        ByteSpan             payloadBytes;
        const ConstantValue& safeDefaultValue = codeGen.cstMgr().get(safeDefaultValueRef);
        if (safeDefaultValue.isStruct())
            payloadBytes = safeDefaultValue.getStruct();
        else if (safeDefaultValue.isArray())
            payloadBytes = safeDefaultValue.getArray();
        else
            return false;

        MicroBuilder&  builder    = codeGen.builder();
        const MicroReg payloadReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegPtrReloc(payloadReg, reinterpret_cast<uint64_t>(payloadBytes.data()), safeDefaultValueRef);
        CodeGenMemoryHelpers::emitMemCopy(codeGen, dstReg, payloadReg, localSize);
        return true;
    }

    void codeGenIdentifierVariable(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        const CodeGenNodePayload symbolPayload = resolveIdentifierVariablePayload(codeGen, symVar);
        CodeGenNodePayload&      payload       = codeGen.setPayload(codeGen.curNodeRef(), symVar.typeRef());
        payload.reg                            = symbolPayload.reg;
        payload.storageKind                    = symbolPayload.storageKind;
    }

    void codeGenIdentifierFromSymbol(CodeGen& codeGen, const Symbol& symbol)
    {
        switch (symbol.kind())
        {
            case SymbolKind::Variable:
                codeGenIdentifierVariable(codeGen, symbol.cast<SymbolVariable>());
                return;

            case SymbolKind::Function:
                return;

            case SymbolKind::Namespace:
            case SymbolKind::Module:
                return;

            case SymbolKind::Alias:
            {
                const auto* aliased = symbol.cast<SymbolAlias>().aliasedSymbol();
                if (aliased)
                    codeGenIdentifierFromSymbol(codeGen, *aliased);
                return;
            }

            default:
                if (symbol.isType())
                    return;
                SWC_UNREACHABLE();
        }
    }

    void storePayloadToAddress(CodeGen& codeGen, MicroReg dstReg, const CodeGenNodePayload& srcPayload, uint32_t copySize)
    {
        MicroBuilder& builder = codeGen.builder();
        if (srcPayload.isAddress())
        {
            CodeGenMemoryHelpers::emitMemCopy(codeGen, dstReg, srcPayload.reg, copySize);
            return;
        }

        if (copySize > 8)
        {
            CodeGenMemoryHelpers::emitMemCopy(codeGen, dstReg, srcPayload.reg, copySize);
            return;
        }

        auto copyBits = MicroOpBits::Zero;
        if (copySize == 1)
            copyBits = MicroOpBits::B8;
        else if (copySize == 2)
            copyBits = MicroOpBits::B16;
        else if (copySize == 4)
            copyBits = MicroOpBits::B32;
        else
            copyBits = MicroOpBits::B64;
        builder.emitLoadMemReg(dstReg, 0, srcPayload.reg, copyBits);
    }

    void materializeSingleVarFromPayload(CodeGen& codeGen, const SymbolVariable& symVar, const CodeGenNodePayload& initPayload)
    {
        if (symVar.hasGlobalStorage())
            return;

        const uint32_t valueSize = CodeGenFunctionHelpers::checkedTypeSizeInBytes(codeGen, codeGen.typeMgr().get(symVar.typeRef()));
        if (CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, symVar))
        {
            const CodeGenNodePayload symbolPayload = CodeGenFunctionHelpers::resolveCallerReturnStoragePayload(codeGen, symVar);
            storePayloadToAddress(codeGen, symbolPayload.reg, initPayload, valueSize);
            return;
        }

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) && codeGen.localStackBaseReg().isValid())
        {
            const CodeGenNodePayload symbolPayload = codeGen.resolveLocalStackPayload(symVar);
            storePayloadToAddress(codeGen, symbolPayload.reg, initPayload, valueSize);
            return;
        }

        CodeGenNodePayload symbolPayload;
        symbolPayload.typeRef     = symVar.typeRef();
        symbolPayload.storageKind = initPayload.storageKind;
        MicroBuilder& builder     = codeGen.builder();
        if (initPayload.isAddress())
        {
            symbolPayload.reg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(symbolPayload.reg, initPayload.reg, MicroOpBits::B64);
        }
        else
        {
            const MicroOpBits copyBits = identifierPayloadCopyBits(codeGen, symVar.typeRef());
            symbolPayload.reg          = codeGen.nextVirtualRegisterForType(symVar.typeRef());
            builder.emitLoadRegReg(symbolPayload.reg, initPayload.reg, copyBits);
        }

        codeGen.setVariablePayload(symVar, symbolPayload);
    }

    void materializeAggregateSourceAddress(CodeGen& codeGen, AstNodeRef storageNodeRef, TypeRef sourceTypeRef, const CodeGenNodePayload& sourcePayload, MicroReg& outAddressReg)
    {
        outAddressReg = MicroReg::invalid();
        if (sourcePayload.isAddress())
        {
            outAddressReg = sourcePayload.reg;
            return;
        }

        const uint64_t sourceSize = codeGen.typeMgr().get(sourceTypeRef).sizeOf(codeGen.ctx());
        SWC_ASSERT(sourceSize && sourceSize < std::numeric_limits<uint32_t>::max());

        const CodeGenNodePayload* storagePayload = codeGen.safePayload(storageNodeRef);
        SWC_ASSERT(storagePayload && storagePayload->runtimeStorageSym != nullptr);

        outAddressReg = codeGen.runtimeStorageAddressReg(storageNodeRef);
        storePayloadToAddress(codeGen, outAddressReg, sourcePayload, static_cast<uint32_t>(sourceSize));
    }

    void materializeSingleVarFromInit(CodeGen& codeGen, const SymbolVariable& symVar, AstNodeRef initRef)
    {
        MicroBuilder& builder  = codeGen.builder();
        const bool    skipInit = symVar.hasExtraFlag(SymbolVariableFlagsE::ExplicitUndefined);
        if (symVar.hasGlobalStorage())
            return;

        if (CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, symVar))
        {
            const uint32_t localSize = CodeGenFunctionHelpers::checkedTypeSizeInBytes(codeGen, codeGen.typeMgr().get(symVar.typeRef()));
            SWC_ASSERT(localSize > 0);
            const CodeGenNodePayload symbolPayload = CodeGenFunctionHelpers::resolveCallerReturnStoragePayload(codeGen, symVar);

            if (skipInit)
                return;

            const AstNodeRef resolvedInitRef = initRef.isValid() ? codeGen.viewZero(initRef).nodeRef() : AstNodeRef::invalid();
            const auto*      initNodePayload = resolvedInitRef.isValid() ? codeGen.sema().codeGenPayload<CodeGenNodePayload>(resolvedInitRef) : nullptr;
            if (initNodePayload && initNodePayload->runtimeStorageSym == &symVar)
                return;

            if (initRef.isValid())
            {
                const CodeGenNodePayload& initPayload = codeGen.payload(initRef);
                if (initPayload.isAddress())
                {
                    CodeGenMemoryHelpers::emitMemCopy(codeGen, symbolPayload.reg, initPayload.reg, localSize);
                }
                else
                {
                    if (localSize > 8)
                    {
                        CodeGenMemoryHelpers::emitMemCopy(codeGen, symbolPayload.reg, initPayload.reg, localSize);
                        return;
                    }

                    auto copyBits = MicroOpBits::Zero;
                    if (localSize == 1)
                        copyBits = MicroOpBits::B8;
                    else if (localSize == 2)
                        copyBits = MicroOpBits::B16;
                    else if (localSize == 4)
                        copyBits = MicroOpBits::B32;
                    else
                        copyBits = MicroOpBits::B64;
                    builder.emitLoadMemReg(symbolPayload.reg, 0, initPayload.reg, copyBits);
                }
            }
            else
            {
                if (!emitDefaultValueToLocalStack(codeGen, symVar, symbolPayload.reg, localSize))
                    CodeGenMemoryHelpers::emitMemZero(codeGen, symbolPayload.reg, localSize);
            }

            return;
        }

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) && codeGen.localStackBaseReg().isValid())
        {
            // Stack locals are committed to memory immediately, so later address-taking observes a stable
            // location, regardless of how the initializer was produced.
            const uint32_t localSize = symVar.codeGenLocalSize();
            SWC_ASSERT(localSize > 0);
            const CodeGenNodePayload symbolPayload   = codeGen.resolveLocalStackPayload(symVar);
            const AstNodeRef         resolvedInitRef = initRef.isValid() ? codeGen.viewZero(initRef).nodeRef() : AstNodeRef::invalid();
            const auto*              initNodePayload = resolvedInitRef.isValid() ? codeGen.sema().codeGenPayload<CodeGenNodePayload>(resolvedInitRef) : nullptr;

            if (initNodePayload && initNodePayload->runtimeStorageSym == &symVar)
                return;

            if (!skipInit)
            {
                if (initRef.isValid())
                {
                    const CodeGenNodePayload& initPayload = codeGen.payload(initRef);
                    if (initPayload.isAddress())
                    {
                        CodeGenMemoryHelpers::emitMemCopy(codeGen, symbolPayload.reg, initPayload.reg, localSize);
                    }
                    else
                    {
                        if (localSize > 8)
                        {
                            CodeGenMemoryHelpers::emitMemCopy(codeGen, symbolPayload.reg, initPayload.reg, localSize);
                            return;
                        }

                        auto copyBits = MicroOpBits::Zero;
                        if (localSize == 1)
                            copyBits = MicroOpBits::B8;
                        else if (localSize == 2)
                            copyBits = MicroOpBits::B16;
                        else if (localSize == 4)
                            copyBits = MicroOpBits::B32;
                        else
                            copyBits = MicroOpBits::B64;
                        builder.emitLoadMemReg(symbolPayload.reg, 0, initPayload.reg, copyBits);
                    }
                }
                else
                {
                    // Prefer the declared default storage blob before falling back to zero-init for plain
                    // uninitialized stack locals.
                    if (!emitDefaultValueToLocalStack(codeGen, symVar, symbolPayload.reg, localSize))
                        CodeGenMemoryHelpers::emitMemZero(codeGen, symbolPayload.reg, localSize);
                }
            }
            return;
        }

        if (skipInit)
            return;

        if (initRef.isInvalid())
        {
            CodeGenNodePayload symbolPayload;
            symbolPayload.typeRef = symVar.typeRef();
            symbolPayload.setIsValue();
            symbolPayload.reg = codeGen.nextVirtualRegisterForType(symVar.typeRef());
            builder.emitClearReg(symbolPayload.reg, identifierPayloadCopyBits(codeGen, symVar.typeRef()));
            codeGen.setVariablePayload(symVar, symbolPayload);
            return;
        }

        const CodeGenNodePayload& initPayload = codeGen.payload(initRef);

        CodeGenNodePayload symbolPayload;
        symbolPayload.typeRef     = symVar.typeRef();
        symbolPayload.storageKind = initPayload.storageKind;

        if (initPayload.isAddress())
        {
            symbolPayload.reg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(symbolPayload.reg, initPayload.reg, MicroOpBits::B64);
        }
        else
        {
            const MicroOpBits copyBits = identifierPayloadCopyBits(codeGen, symVar.typeRef());
            symbolPayload.reg          = codeGen.nextVirtualRegisterForType(symVar.typeRef());
            builder.emitLoadRegReg(symbolPayload.reg, initPayload.reg, copyBits);
        }

        codeGen.setVariablePayload(symVar, symbolPayload);
    }

    Result emitVarInitSpecOp(CodeGen& codeGen, const SymbolVariable& symVar, SymbolFunction& calledFn)
    {
        materializeSingleVarFromInit(codeGen, symVar, AstNodeRef::invalid());

        SmallVector<ResolvedCallArgument> resolvedArgs;
        codeGen.sema().appendResolvedCallArguments(codeGen.curNodeRef(), resolvedArgs);
        SWC_ASSERT(!resolvedArgs.empty() && resolvedArgs[0].argRef.isValid());

        const CodeGenNodePayload receiverPayload = resolveIdentifierVariablePayload(codeGen, symVar);
        CodeGenNodePayload&      receiverArg     = codeGen.setPayload(resolvedArgs[0].argRef, symVar.typeRef());
        receiverArg.reg                          = receiverPayload.reg;
        receiverArg.typeRef                      = receiverPayload.typeRef;
        receiverArg.storageKind                  = receiverPayload.storageKind;

        codeGen.sema().setSymbol(codeGen.curNodeRef(), &calledFn);
        return CodeGenCallHelpers::codeGenCallExprCommon(codeGen, AstNodeRef::invalid());
    }
}

Result AstStructDecl::codeGenPreNode(const CodeGen& codeGen)
{
    SWC_UNUSED(codeGen);
    return Result::SkipChildren;
}

Result AstUnionDecl::codeGenPreNode(const CodeGen& codeGen)
{
    SWC_UNUSED(codeGen);
    return Result::SkipChildren;
}

Result AstAnonymousStructDecl::codeGenPreNode(const CodeGen& codeGen)
{
    SWC_UNUSED(codeGen);
    return Result::SkipChildren;
}

Result AstIdentifier::codeGenPostNode(CodeGen& codeGen)
{
    const SemaNodeView view = codeGen.curViewSymbol();
    if (!view.sym())
    {
        const AstNodeRef parentRef = codeGen.visit().parentNodeRef();
        if (parentRef.isValid() &&
            (codeGen.node(parentRef).is(AstNodeId::NamedType) ||
             codeGen.node(parentRef).is(AstNodeId::QuotedExpr) ||
             codeGen.node(parentRef).is(AstNodeId::QuotedListExpr)))
            return Result::Continue;

        SWC_ASSERT(view.sym());
    }

    codeGenIdentifierFromSymbol(codeGen, *view.sym());
    return Result::Continue;
}

Result AstSingleVarDecl::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView view = codeGen.curViewSymbol();
    SWC_ASSERT(view.sym());
    const SymbolVariable& symVar = view.sym()->cast<SymbolVariable>();

    if (hasFlag(AstVarDeclFlagsE::Parameter))
    {
        const SymbolFunction& symbolFunc = codeGen.function();
        CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, symbolFunc, symVar);
    }
    else
    {
        if (const auto* initPayload = codeGen.sema().semaPayload<VarInitSpecOpPayload>(codeGen.curNodeRef());
            initPayload && initPayload->calledFn != nullptr)
        {
            SWC_RESULT(emitVarInitSpecOp(codeGen, symVar, *initPayload->calledFn));
        }
        else
        {
            materializeSingleVarFromInit(codeGen, symVar, nodeInitRef);
        }
        codeGen.registerImplicitDrop(symVar);
    }

    return Result::Continue;
}

Result AstMultiVarDecl::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView view = codeGen.curViewSymbolList();
    SWC_ASSERT(!view.symList().empty());

    // Constants are fully resolved during sema and need no runtime codegen.
    if (hasFlag(AstVarDeclFlagsE::Const))
        return Result::Continue;

    if (hasFlag(AstVarDeclFlagsE::Parameter))
    {
        const SymbolFunction& symbolFunc = codeGen.function();
        for (Symbol* sym : view.symList())
        {
            const SymbolVariable& symVar = sym->cast<SymbolVariable>();
            CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, symbolFunc, symVar);
        }
    }
    else
    {
        for (Symbol* sym : view.symList())
        {
            const SymbolVariable& symVar = sym->cast<SymbolVariable>();
            materializeSingleVarFromInit(codeGen, symVar, nodeInitRef);
            codeGen.registerImplicitDrop(symVar);
        }
    }

    return Result::Continue;
}

Result AstVarDeclDestructuring::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView initView = codeGen.viewType(nodeInitRef);
    SWC_ASSERT(initView.type() && (initView.type()->isStruct() || initView.type()->isAggregateStruct()));

    // Aggregate struct literals have no runtime layout. Initialize each
    // decomposed variable from its compile-time constant value.
    if (initView.type()->isAggregateStruct())
    {
        MicroBuilder&            builder = codeGen.builder();
        const SemaNodeView       view    = codeGen.curViewSymbolList();
        const std::span<Symbol*> symbols = view.symList();

        for (Symbol* sym : symbols)
        {
            auto& symVar = sym->cast<SymbolVariable>();
            if (symVar.hasGlobalStorage())
                continue;
            if (symVar.hasExtraFlag(SymbolVariableFlagsE::Let))
                continue;

            if (symVar.cstRef().isValid())
            {
                const ConstantValue& cst = codeGen.cstMgr().get(symVar.cstRef());

                CodeGenNodePayload fieldPayload;
                fieldPayload.typeRef = symVar.typeRef();
                fieldPayload.setIsValue();

                if (cst.isInt())
                {
                    fieldPayload.reg = codeGen.nextVirtualIntRegister();
                    builder.emitLoadRegImm(fieldPayload.reg, ApInt(static_cast<uint64_t>(cst.getInt().asI64()), 64), MicroOpBits::B64);
                }
                else if (cst.isBool())
                {
                    fieldPayload.reg = codeGen.nextVirtualIntRegister();
                    builder.emitLoadRegImm(fieldPayload.reg, ApInt(cst.getBool() ? 1 : 0, 64), MicroOpBits::B64);
                }
                else if (cst.isFloat())
                {
                    fieldPayload.reg = codeGen.nextVirtualFloatRegister();
                    const auto bits  = std::bit_cast<uint64_t>(cst.getFloat().asDouble());
                    builder.emitLoadRegImm(fieldPayload.reg, ApInt(bits, 64), MicroOpBits::B64);
                }
                else if (cst.isString())
                {
                    const std::string_view strVal    = cst.getString();
                    const ConstantRef      strCstRef = CodeGenConstantHelpers::materializeRuntimeBufferConstant(codeGen, symVar.typeRef(), strVal.data(), strVal.size());
                    const ConstantValue&   strCst    = codeGen.cstMgr().get(strCstRef);
                    fieldPayload.reg                 = codeGen.nextVirtualIntRegister();
                    builder.emitLoadRegPtrReloc(fieldPayload.reg, reinterpret_cast<uint64_t>(strCst.getStruct().data()), strCstRef);
                }
                else if (cst.isValuePointer())
                {
                    fieldPayload.reg = codeGen.nextVirtualIntRegister();
                    builder.emitLoadRegPtrReloc(fieldPayload.reg, cst.getValuePointer(), symVar.cstRef());
                }
                else
                {
                    fieldPayload.reg = codeGen.nextVirtualIntRegister();
                    builder.emitClearReg(fieldPayload.reg, identifierPayloadCopyBits(codeGen, symVar.typeRef()));
                }

                materializeSingleVarFromPayload(codeGen, symVar, fieldPayload);
            }
            else
            {
                materializeSingleVarFromInit(codeGen, symVar, AstNodeRef::invalid());
            }

            codeGen.registerImplicitDrop(symVar);
        }

        return Result::Continue;
    }

    const CodeGenNodePayload& initPayload = codeGen.payload(nodeInitRef);
    MicroReg                  baseAddress = MicroReg::invalid();
    materializeAggregateSourceAddress(codeGen, codeGen.curNodeRef(), initView.typeRef(), initPayload, baseAddress);

    const auto&              fields  = initView.type()->payloadSymStruct().fields();
    const SemaNodeView       view    = codeGen.curViewSymbolList();
    const std::span<Symbol*> symbols = view.symList();
    SmallVector<TokenRef>    tokNames;
    codeGen.ast().appendTokens(tokNames, spanNamesRef);

    size_t symbolIndex = 0;
    for (size_t i = 0; i < tokNames.size(); ++i)
    {
        if (tokNames[i].isInvalid())
            continue;

        SWC_ASSERT(symbolIndex < symbols.size());
        SWC_ASSERT(i < fields.size() && fields[i] != nullptr);
        const SymbolVariable& field  = *fields[i];
        const SymbolVariable& symVar = symbols[symbolIndex++]->cast<SymbolVariable>();

        CodeGenNodePayload fieldPayload;
        fieldPayload.typeRef = field.typeRef();
        fieldPayload.setIsAddress();
        fieldPayload.reg = codeGen.offsetAddressReg(baseAddress, field.offset());

        materializeSingleVarFromPayload(codeGen, symVar, fieldPayload);
        codeGen.registerImplicitDrop(symVar);
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
