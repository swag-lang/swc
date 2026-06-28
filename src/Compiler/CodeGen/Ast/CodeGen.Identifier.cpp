#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenCallHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenConstantHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenStructHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool functionVariableDeclSymbolMatches(const AstNode* decl, TokenRef tokRef, const SymbolVariable* symVar)
    {
        if (!symVar || symVar->decl() != decl)
            return false;
        return !tokRef.isValid() || symVar->tokRef() == tokRef;
    }

    void tryRecoverFunctionLocalSymbolMatch(Symbol*& ioBestMatch, const CodeGen& codeGen, const TokenRef nodeTokRef, const std::string_view identifierName, const Symbol* symbol)
    {
        if (!symbol || symbol->isIgnored() || symbol->name(codeGen.ctx()) != identifierName)
            return;
        if (symbol->tokRef().isValid() && symbol->tokRef().get() > nodeTokRef.get())
            return;
        if (!ioBestMatch ||
            !ioBestMatch->tokRef().isValid() ||
            (symbol->tokRef().isValid() && ioBestMatch->tokRef().get() < symbol->tokRef().get()))
            ioBestMatch = const_cast<Symbol*>(symbol);
    }

    const SymbolVariable* findFunctionVariableDeclSymbol(const CodeGen& codeGen, const AstNodeRef declRef, const TokenRef tokRef)
    {
        if (!declRef.isValid())
            return nullptr;

        const AstNode* const decl = &codeGen.node(declRef);

        for (const SymbolVariable* symVar : codeGen.function().parameters())
        {
            if (functionVariableDeclSymbolMatches(decl, tokRef, symVar))
                return symVar;
        }

        for (const SymbolVariable* symVar : codeGen.function().localVariables())
        {
            if (functionVariableDeclSymbolMatches(decl, tokRef, symVar))
                return symVar;
        }

        return nullptr;
    }

    const SymbolVariable* canonicalFunctionVariableSymbol(const CodeGen& codeGen, const SymbolVariable& symVar)
    {
        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) &&
            symVar.hasParameterIndex() &&
            symVar.parameterIndex() < codeGen.function().parameters().size())
        {
            if (const SymbolVariable* canonicalParam = codeGen.function().parameters()[symVar.parameterIndex()])
                return canonicalParam;
        }

        return &symVar;
    }

    void recoverFunctionVariableDeclSymbols(const CodeGen& codeGen, const AstNodeRef declRef, std::span<const TokenRef> tokRefs, SmallVector<Symbol*>& outSymbols)
    {
        outSymbols.clear();
        outSymbols.reserve(tokRefs.size());

        for (const TokenRef tokRef : tokRefs)
        {
            if (tokRef.isInvalid())
                continue;

            const SymbolVariable* symVar = findFunctionVariableDeclSymbol(codeGen, declRef, tokRef);
            if (symVar)
                outSymbols.push_back(const_cast<SymbolVariable*>(symVar));
        }
    }

    Symbol* recoverFunctionLocalIdentifierSymbol(const CodeGen& codeGen, AstNodeRef nodeRef)
    {
        if (!nodeRef.isValid())
            return nullptr;

        const AstNode& node = codeGen.node(nodeRef);
        if (node.isNot(AstNodeId::Identifier) || !node.tokRef().isValid())
            return nullptr;

        const SourceView&      srcView        = codeGen.ast().srcView();
        const std::string_view identifierName = srcView.tokenString(node.tokRef());
        if (identifierName.empty())
            return nullptr;

        Symbol* bestMatch = nullptr;

        for (const SymbolVariable* symVar : codeGen.function().parameters())
            tryRecoverFunctionLocalSymbolMatch(bestMatch, codeGen, node.tokRef(), identifierName, symVar);

        for (const SymbolVariable* symVar : codeGen.function().localVariables())
            tryRecoverFunctionLocalSymbolMatch(bestMatch, codeGen, node.tokRef(), identifierName, symVar);

        if (bestMatch)
            return bestMatch;

        std::vector<const Symbol*> localSymbols;
        codeGen.function().getAllSymbols(localSymbols, true);

        for (const Symbol* symbol : localSymbols)
            tryRecoverFunctionLocalSymbolMatch(bestMatch, codeGen, node.tokRef(), identifierName, symbol);

        return bestMatch;
    }

    Symbol* recoverIdentifierSymbol(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        if (!nodeRef.isValid())
            return nullptr;

        if (Symbol* symbol = codeGen.sema().viewStored(nodeRef, SemaNodeViewPartE::Symbol).sym())
            return symbol;

        const AstNodeRef resolvedRef = codeGen.resolvedNodeRef(nodeRef);
        if (resolvedRef.isValid() && resolvedRef != nodeRef)
        {
            if (Symbol* symbol = codeGen.sema().viewStored(resolvedRef, SemaNodeViewPartE::Symbol).sym())
                return symbol;

            if (const SymbolVariable* symVar = findFunctionVariableDeclSymbol(codeGen, resolvedRef, TokenRef::invalid()))
                return const_cast<SymbolVariable*>(symVar);
        }

        return recoverFunctionLocalIdentifierSymbol(codeGen, nodeRef);
    }

    SymbolVariable* implicitMeReceiver(CodeGen& codeGen)
    {
        const auto& params = codeGen.function().parameters();
        if (params.empty() || !params.front())
            return nullptr;

        SymbolVariable* receiver = params.front();
        if (receiver->idRef() != codeGen.sema().idMgr().predefined(IdentifierManager::PredefinedName::Me))
            return nullptr;

        return receiver;
    }

    bool tryResolveImplicitReceiverFieldPayload(CodeGen& codeGen, const SymbolVariable& symVar, CodeGenNodePayload& outPayload)
    {
        // A static (per-impl) data member has its own global storage; even though it
        // is nominally a member of the receiver struct, it must never be addressed
        // relative to the receiver instance. Let it fall through to the global path.
        if (symVar.hasGlobalStorage())
            return false;

        const SymbolVariable* receiver = implicitMeReceiver(codeGen);
        if (!receiver)
            return false;

        const SymbolStruct* receiverStruct = CodeGenStructHelpers::resolveReceiverRuntimeStruct(codeGen);
        if (!receiverStruct)
            return false;

        const SymbolVariable* concreteField = CodeGenStructHelpers::tryResolveSameGenericFamilyFieldSymbol(*receiverStruct, symVar);
        const SymbolVariable& resolvedField = concreteField ? *concreteField : symVar;
        const SymbolStruct*   fieldOwner    = CodeGenStructHelpers::variableOwnerStruct(resolvedField);
        if (!fieldOwner || !fieldOwner->sameGenericFamily(*receiverStruct))
            return false;

        const CodeGenNodePayload receiverPayload = CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, codeGen.function(), *receiver);
        const TypeRef            receiverTypeRef = codeGen.typeMgr().unwrapAliasEnum(codeGen.ctx(), receiver->typeRef());
        if (receiverTypeRef.isInvalid())
            return false;

        const TypeInfo& receiverType = codeGen.typeMgr().get(receiverTypeRef);
        if (!receiverType.isPointerOrReference())
            return false;

        MicroReg baseAddressReg = receiverPayload.reg;
        if (receiverPayload.isAddress())
        {
            baseAddressReg = codeGen.nextVirtualIntRegister();
            codeGen.builder().emitLoadRegMem(baseAddressReg, receiverPayload.reg, 0, MicroOpBits::B64);
        }

        outPayload.typeRef = resolvedField.typeRef();
        outPayload.reg     = codeGen.nextVirtualIntRegister();
        outPayload.setIsAddress();
        codeGen.builder().emitLoadAddressRegMem(outPayload.reg, baseAddressReg, resolvedField.offset(), MicroOpBits::B64);
        return true;
    }

    MicroOpBits identifierPayloadCopyBits(CodeGen& codeGen, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return MicroOpBits::B64;

        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
        return CodeGenTypeHelpers::copyBits(typeInfo);
    }

    CodeGenNodePayload resolveIdentifierVariablePayload(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        const SymbolVariable& payloadSym = *canonicalFunctionVariableSymbol(codeGen, symVar);
        CodeGenNodePayload    implicitFieldPayload;
        if (tryResolveImplicitReceiverFieldPayload(codeGen, payloadSym, implicitFieldPayload))
            return implicitFieldPayload;

        if (payloadSym.isClosureCapture())
            return CodeGenFunctionHelpers::resolveClosureCapturePayload(codeGen, payloadSym);

        if (CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, payloadSym))
            return CodeGenFunctionHelpers::resolveCallerReturnStoragePayload(codeGen, payloadSym);

        if (payloadSym.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        {
            const SymbolFunction& symbolFunc = codeGen.function();
            return CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, symbolFunc, payloadSym);
        }

        const CodeGenNodePayload* symbolPayload = codeGen.variablePayload(payloadSym);
        if (symbolPayload)
            return *symbolPayload;

        if (payloadSym.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
            return codeGen.resolveLocalStackPayload(payloadSym);
        if (codeGen.localStackBaseReg().isValid() && payloadSym.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal))
            return codeGen.resolveLocalStackPayload(payloadSym);

        if (payloadSym.hasGlobalStorage())
        {
            CodeGenNodePayload globalPayload;
            globalPayload.typeRef = payloadSym.typeRef();
            globalPayload.setIsAddress();
            globalPayload.reg = codeGen.nextVirtualIntRegister();
            codeGen.builder().emitLoadRegDataSegmentReloc(globalPayload.reg, payloadSym.globalStorageKind(), payloadSym.offset());
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

        std::span<const std::byte> rawBytes;
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

        std::span<const std::byte> payloadBytes;
        const ConstantValue&       safeDefaultValue = codeGen.cstMgr().get(safeDefaultValueRef);
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

    bool shouldSkipVariableDefaultInit(const SymbolVariable& symVar)
    {
        if (symVar.hasExtraFlag(SymbolVariableFlagsE::ExplicitUndefined))
            return true;
        if (symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal))
            return false;
        return symVar.hasExtraFlag(SymbolVariableFlagsE::ImplicitUndefinedInit);
    }

    Result emitVariableDefaultValueToAddress(CodeGen& codeGen, const SymbolVariable& symVar, const MicroReg dstReg, uint32_t localSize)
    {
        const TypeInfo& symType        = codeGen.typeMgr().get(symVar.typeRef());
        TypeRef         storageTypeRef = symVar.typeRef();
        if (const TypeRef unwrappedTypeRef = symType.unwrap(codeGen.ctx(), symVar.typeRef(), TypeExpandE::Alias); unwrappedTypeRef.isValid())
            storageTypeRef = unwrappedTypeRef;

        const TypeInfo& storageType = codeGen.typeMgr().get(storageTypeRef);
        if (storageType.isStruct())
        {
            const auto& symStruct = storageType.payloadSymStruct();
            symStruct.computeImplicitDefaultFlags(codeGen.sema());
            if (symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal) && symStruct.hasImplicitAllUndefinedDefault())
            {
                CodeGenMemoryHelpers::emitMemZero(codeGen, dstReg, localSize);
                return Result::Continue;
            }

            SWC_RESULT(CodeGenFunctionHelpers::emitStructDefaultValue(codeGen, symVar.typeRef(), dstReg));
            return Result::Continue;
        }

        if (!emitDefaultValueToLocalStack(codeGen, symVar, dstReg, localSize))
            CodeGenMemoryHelpers::emitMemZero(codeGen, dstReg, localSize);
        return Result::Continue;
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

    void materializeSingleVarFromPayload(CodeGen& codeGen, const SymbolVariable& symVar, const CodeGenNodePayload& initPayload)
    {
        if (symVar.hasGlobalStorage())
            return;

        const uint32_t valueSize = CodeGenFunctionHelpers::checkedTypeSizeInBytes(codeGen, codeGen.typeMgr().get(symVar.typeRef()));
        if (CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, symVar))
        {
            const CodeGenNodePayload symbolPayload = CodeGenFunctionHelpers::resolveCallerReturnStoragePayload(codeGen, symVar);
            CodeGenMemoryHelpers::storePayloadToAddress(codeGen, symbolPayload.reg, initPayload, valueSize);
            return;
        }

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) && codeGen.localStackBaseReg().isValid())
        {
            const CodeGenNodePayload symbolPayload = codeGen.resolveLocalStackPayload(symVar);
            CodeGenMemoryHelpers::storePayloadToAddress(codeGen, symbolPayload.reg, initPayload, valueSize);
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
        CodeGenMemoryHelpers::storePayloadToAddress(codeGen, outAddressReg, sourcePayload, static_cast<uint32_t>(sourceSize));
    }

    bool initPayloadAliasesSymbolStorage(const CodeGen& codeGen, const SymbolVariable& symVar, AstNodeRef payloadNodeRef, const CodeGenNodePayload& initPayload)
    {
        if (!initPayload.isAddress() || initPayload.runtimeStorageSym != &symVar)
            return false;
        if (initPayload.runtimeStorageOverridden)
            return true;
        return payloadNodeRef.isValid() && codeGen.node(payloadNodeRef).is(AstNodeId::TryCatchExpr);
    }

    bool varInitNeedsPostCopy(CodeGen& codeGen, AstNodeRef initRef, const CodeGenNodePayload& initPayload)
    {
        const AstNodeRef resolvedInitRef = initRef.isValid() ? codeGen.viewZero(initRef).nodeRef() : AstNodeRef::invalid();
        if (resolvedInitRef.isValid() && codeGen.sema().isLValue(resolvedInitRef))
            return true;
        return initPayload.runtimeStorageSym != nullptr;
    }

    Result emitVarInitPostCopy(CodeGen& codeGen, const SymbolVariable& symVar, AstNodeRef initRef, const CodeGenNodePayload& initPayload, const CodeGenNodePayload& symbolPayload)
    {
        if (!symbolPayload.isAddress())
            return Result::Continue;
        if (initPayloadAliasesSymbolStorage(codeGen, symVar, initRef, initPayload))
            return Result::Continue;
        if (initPayload.isAddress() && initPayload.reg == symbolPayload.reg)
            return Result::Continue;
        if (!varInitNeedsPostCopy(codeGen, initRef, initPayload))
            return Result::Continue;
        if (!codeGen.hasLifecycle(symVar.typeRef(), CodeGen::LifecycleKind::PostCopy))
            return Result::Continue;
        return codeGen.emitLifecycle(symVar.typeRef(), CodeGen::LifecycleKind::PostCopy, symbolPayload.reg);
    }

    Result materializeSingleVarFromInit(CodeGen& codeGen, const SymbolVariable& symVar, AstNodeRef initRef)
    {
        MicroBuilder& builder  = codeGen.builder();
        const bool    skipInit = shouldSkipVariableDefaultInit(symVar);
        if (symVar.hasGlobalStorage())
            return Result::Continue;

        if (CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, symVar))
        {
            if (skipInit)
                return Result::Continue;

            const uint32_t localSize = CodeGenFunctionHelpers::checkedTypeSizeInBytes(codeGen, codeGen.typeMgr().get(symVar.typeRef()));
            SWC_ASSERT(localSize > 0);
            const CodeGenNodePayload symbolPayload = CodeGenFunctionHelpers::resolveCallerReturnStoragePayload(codeGen, symVar);

            const auto* initNodePayload = initRef.isValid() ? codeGen.safeNodePayload<CodeGenNodePayload>(initRef) : nullptr;
            if ((!initNodePayload || !initPayloadAliasesSymbolStorage(codeGen, symVar, initRef, *initNodePayload)) && initRef.isValid())
            {
                const AstNodeRef resolvedInitRef = codeGen.viewZero(initRef).nodeRef();
                if (resolvedInitRef.isValid() && resolvedInitRef != initRef)
                    initNodePayload = codeGen.safeNodePayload<CodeGenNodePayload>(resolvedInitRef);
            }

            if (initNodePayload && initPayloadAliasesSymbolStorage(codeGen, symVar, initRef, *initNodePayload))
                return Result::Continue;

            if (initRef.isValid())
            {
                const CodeGenNodePayload& initPayload = codeGen.payload(initRef);
                if (initPayloadAliasesSymbolStorage(codeGen, symVar, initRef, initPayload))
                    return Result::Continue;
                if (initPayload.isAddress())
                {
                    CodeGenMemoryHelpers::emitMemCopy(codeGen, symbolPayload.reg, initPayload.reg, localSize);
                    SWC_RESULT(emitVarInitPostCopy(codeGen, symVar, initRef, initPayload, symbolPayload));
                }
                else
                {
                    if (localSize > 8)
                    {
                        CodeGenMemoryHelpers::emitMemCopy(codeGen, symbolPayload.reg, initPayload.reg, localSize);
                        SWC_RESULT(emitVarInitPostCopy(codeGen, symVar, initRef, initPayload, symbolPayload));
                        return Result::Continue;
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
                    SWC_RESULT(emitVarInitPostCopy(codeGen, symVar, initRef, initPayload, symbolPayload));
                }
            }
            else
            {
                SWC_RESULT(emitVariableDefaultValueToAddress(codeGen, symVar, symbolPayload.reg, localSize));
            }

            return Result::Continue;
        }

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) && codeGen.localStackBaseReg().isValid())
        {
            // Stack locals are committed to memory immediately, so later address-taking observes a stable
            // location, regardless of how the initializer was produced.
            const uint32_t localSize = symVar.codeGenLocalSize();
            SWC_ASSERT(localSize > 0);
            const CodeGenNodePayload symbolPayload   = codeGen.resolveLocalStackPayload(symVar);
            const auto*              initNodePayload = initRef.isValid() ? codeGen.safeNodePayload<CodeGenNodePayload>(initRef) : nullptr;
            if ((!initNodePayload || !initPayloadAliasesSymbolStorage(codeGen, symVar, initRef, *initNodePayload)) && initRef.isValid())
            {
                const AstNodeRef resolvedInitRef = codeGen.viewZero(initRef).nodeRef();
                if (resolvedInitRef.isValid() && resolvedInitRef != initRef)
                    initNodePayload = codeGen.safeNodePayload<CodeGenNodePayload>(resolvedInitRef);
            }

            if (initNodePayload && initPayloadAliasesSymbolStorage(codeGen, symVar, initRef, *initNodePayload))
                return Result::Continue;

            if (!skipInit)
            {
                if (initRef.isValid())
                {
                    const CodeGenNodePayload& initPayload = codeGen.payload(initRef);
                    if (initPayloadAliasesSymbolStorage(codeGen, symVar, initRef, initPayload))
                        return Result::Continue;
                    if (initPayload.isAddress())
                    {
                        CodeGenMemoryHelpers::emitMemCopy(codeGen, symbolPayload.reg, initPayload.reg, localSize);
                        SWC_RESULT(emitVarInitPostCopy(codeGen, symVar, initRef, initPayload, symbolPayload));
                    }
                    else
                    {
                        if (localSize > 8)
                        {
                            CodeGenMemoryHelpers::emitMemCopy(codeGen, symbolPayload.reg, initPayload.reg, localSize);
                            SWC_RESULT(emitVarInitPostCopy(codeGen, symVar, initRef, initPayload, symbolPayload));
                            return Result::Continue;
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
                        SWC_RESULT(emitVarInitPostCopy(codeGen, symVar, initRef, initPayload, symbolPayload));
                    }
                }
                else
                {
                    SWC_RESULT(emitVariableDefaultValueToAddress(codeGen, symVar, symbolPayload.reg, localSize));
                }
            }
            return Result::Continue;
        }

        if (skipInit)
            return Result::Continue;

        if (initRef.isInvalid())
        {
            CodeGenNodePayload symbolPayload;
            symbolPayload.typeRef = symVar.typeRef();
            symbolPayload.setIsValue();
            symbolPayload.reg = codeGen.nextVirtualRegisterForType(symVar.typeRef());
            builder.emitClearReg(symbolPayload.reg, identifierPayloadCopyBits(codeGen, symVar.typeRef()));
            codeGen.setVariablePayload(symVar, symbolPayload);
            return Result::Continue;
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
        return Result::Continue;
    }

    Result emitVarInitSpecOp(CodeGen& codeGen, const SymbolVariable& symVar, SymbolFunction& calledFn)
    {
        SWC_RESULT(materializeSingleVarFromInit(codeGen, symVar, AstNodeRef::invalid()));

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

Result AstAnonymousUnionDecl::codeGenPreNode(const CodeGen& codeGen)
{
    SWC_UNUSED(codeGen);
    return Result::SkipChildren;
}

Result AstIdentifier::codeGenPostNode(CodeGen& codeGen)
{
    const SemaNodeView view      = codeGen.curViewSymbol();
    const Symbol*      symbol    = view.sym();
    const AstNodeRef   parentRef = codeGen.visit().parentNodeRef();
    if (!view.sym())
    {
        if (codeGen.curNode().codeRef().isValid() &&
            codeGen.token(codeGen.curNode().codeRef()).id == TokenId::SymSingleQuote &&
            parentRef.isValid() &&
            codeGen.node(parentRef).is(AstNodeId::CastExpr))
            return Result::Continue;

        if (parentRef.isValid() &&
            (codeGen.node(parentRef).is(AstNodeId::NamedType) ||
             codeGen.node(parentRef).is(AstNodeId::IntrinsicCallExpr) ||
             codeGen.node(parentRef).is(AstNodeId::AutoMemberAccessExpr) ||
             codeGen.node(parentRef).is(AstNodeId::CompilerTypeExpr) ||
             codeGen.node(parentRef).is(AstNodeId::StructInitializerList) ||
             codeGen.node(parentRef).is(AstNodeId::SuffixLiteral) ||
             codeGen.node(parentRef).is(AstNodeId::QuotedExpr) ||
             codeGen.node(parentRef).is(AstNodeId::QuotedListExpr)))
            return Result::Continue;
    }

    const bool         isConstantBinding = codeGen.curNode().cast<AstIdentifier>().hasFlag(AstIdentifierFlagsE::ConstantBinding);
    const SemaNodeView constView         = isConstantBinding
                                               ? codeGen.sema().viewStored(codeGen.curNodeRef(), SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant)
                                               : codeGen.curViewTypeConstant();
    if (constView.hasConstant())
    {
        CodeGenNodePayload constantPayload;
        SWC_INTERNAL_CHECK(CodeGenCallHelpers::materializeTypedConstantPayload(codeGen, constantPayload, constView.typeRef(), constView.cstRef()));
        codeGen.setNodePayload<CodeGenNodePayload>(codeGen.curNodeRef(), constantPayload);
        return Result::Continue;
    }

    if (!view.sym())
    {
        symbol = recoverIdentifierSymbol(codeGen, codeGen.curNodeRef());
        SWC_ASSERT(symbol);
        if (!symbol)
            return Result::Error;
    }

    codeGenIdentifierFromSymbol(codeGen, *symbol);
    return Result::Continue;
}

Result AstSingleVarDecl::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView    view         = codeGen.curViewSymbol();
    const SymbolVariable* recoveredSym = !view.sym() ? findFunctionVariableDeclSymbol(codeGen, codeGen.curNodeRef(), tokNameRef) : nullptr;
    SWC_ASSERT(view.sym() || recoveredSym);
    const SymbolVariable& symVar = view.sym() ? view.sym()->cast<SymbolVariable>() : *recoveredSym;

    if (hasFlag(AstVarDeclFlagsE::Parameter))
    {
        const SymbolFunction& symbolFunc = codeGen.function();
        CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, symbolFunc, symVar);
    }
    else
    {
        const auto* initPayload = codeGen.sema().semaPayload<VarInitSpecOpPayload>(codeGen.curNodeRef());
        if (initPayload && initPayload->calledFn != nullptr)
        {
            SWC_RESULT(emitVarInitSpecOp(codeGen, symVar, *initPayload->calledFn));
        }
        else
        {
            SWC_RESULT(materializeSingleVarFromInit(codeGen, symVar, nodeInitRef));
        }
        codeGen.registerImplicitDrop(symVar);
    }

    return Result::Continue;
}

Result AstMultiVarDecl::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView       view = codeGen.curViewSymbolList();
    SmallVector<TokenRef>    tokNames;
    SmallVector<Symbol*>     recoveredSymbols;
    std::span<Symbol* const> symbols = view.symList();
    if (symbols.empty())
    {
        codeGen.ast().appendTokens(tokNames, spanNamesRef);
        recoverFunctionVariableDeclSymbols(codeGen, codeGen.curNodeRef(), tokNames.span(), recoveredSymbols);
        symbols = recoveredSymbols.span();
    }

    SWC_ASSERT(!symbols.empty());

    // Constants are fully resolved during sema and need no runtime codegen.
    if (hasFlag(AstVarDeclFlagsE::Const))
        return Result::Continue;

    if (hasFlag(AstVarDeclFlagsE::Parameter))
    {
        const SymbolFunction& symbolFunc = codeGen.function();
        for (Symbol* sym : symbols)
        {
            const SymbolVariable& symVar = sym->cast<SymbolVariable>();
            CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, symbolFunc, symVar);
        }
    }
    else
    {
        for (Symbol* sym : symbols)
        {
            const SymbolVariable& symVar = sym->cast<SymbolVariable>();
            SWC_RESULT(materializeSingleVarFromInit(codeGen, symVar, nodeInitRef));
            codeGen.registerImplicitDrop(symVar);
        }
    }

    return Result::Continue;
}

Result AstVarDeclDestructuring::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView initView      = codeGen.viewType(nodeInitRef);
    const SemaNodeView initConstView = codeGen.viewTypeConstant(nodeInitRef);
    SWC_ASSERT(initView.type() && (initView.type()->isStruct() || initView.type()->isAggregateStruct()));

    SmallVector<TokenRef> tokNames;
    codeGen.ast().appendTokens(tokNames, spanNamesRef);

    const SemaNodeView       view = codeGen.curViewSymbolList();
    SmallVector<Symbol*>     recoveredSymbols;
    std::span<Symbol* const> symbols = view.symList();
    if (symbols.empty())
    {
        recoverFunctionVariableDeclSymbols(codeGen, codeGen.curNodeRef(), tokNames.span(), recoveredSymbols);
        symbols = recoveredSymbols.span();
    }

    SWC_ASSERT(!symbols.empty());

    // Aggregate struct literals can be purely compile-time values or runtime
    // temporaries materialized in scratch storage. Handle the constant case
    // directly, and otherwise destructure from the runtime aggregate layout.
    if (initView.type()->isAggregateStruct())
    {
        if (initConstView.hasConstant())
        {
            MicroBuilder& builder = codeGen.builder();
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
                    SWC_RESULT(materializeSingleVarFromInit(codeGen, symVar, AstNodeRef::invalid()));
                }

                codeGen.registerImplicitDrop(symVar);
            }
        }
        else
        {
            const CodeGenNodePayload& initPayload = codeGen.payload(nodeInitRef);
            MicroReg                  baseAddress = MicroReg::invalid();
            materializeAggregateSourceAddress(codeGen, codeGen.curNodeRef(), initView.typeRef(), initPayload, baseAddress);

            const auto& aggregateTypes = initView.type()->payloadAggregate().types;
            uint64_t    offset         = 0;
            size_t      symbolIndex    = 0;
            for (size_t i = 0; i < tokNames.size(); ++i)
            {
                SWC_ASSERT(i < aggregateTypes.size());
                const TypeRef  fieldTypeRef = aggregateTypes[i];
                const auto&    fieldType    = codeGen.typeMgr().get(fieldTypeRef);
                const uint32_t fieldAlign   = std::max<uint32_t>(fieldType.alignOf(codeGen.ctx()), 1);
                const uint64_t fieldSize    = fieldType.sizeOf(codeGen.ctx());
                if (fieldSize)
                    offset = ((offset + static_cast<uint64_t>(fieldAlign) - 1) / static_cast<uint64_t>(fieldAlign)) * static_cast<uint64_t>(fieldAlign);

                if (tokNames[i].isValid())
                {
                    SWC_ASSERT(symbolIndex < symbols.size());
                    const SymbolVariable& symVar = symbols[symbolIndex++]->cast<SymbolVariable>();

                    CodeGenNodePayload fieldPayload;
                    fieldPayload.typeRef = fieldTypeRef;
                    fieldPayload.setIsAddress();
                    fieldPayload.reg = codeGen.offsetAddressReg(baseAddress, static_cast<uint32_t>(offset));

                    materializeSingleVarFromPayload(codeGen, symVar, fieldPayload);
                    codeGen.registerImplicitDrop(symVar);
                }

                offset += fieldSize;
            }
        }

        return Result::Continue;
    }

    const CodeGenNodePayload& initPayload = codeGen.payload(nodeInitRef);
    MicroReg                  baseAddress = MicroReg::invalid();
    materializeAggregateSourceAddress(codeGen, codeGen.curNodeRef(), initView.typeRef(), initPayload, baseAddress);

    const auto& fields = initView.type()->payloadSymStruct().fields();

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
