#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isFunctionLocalVariable(const CodeGen& codeGen, const SymbolVariable& symVar)
    {
        const auto& locals = codeGen.function().localVariables();
        return std::ranges::find(locals, const_cast<SymbolVariable*>(&symVar)) != locals.end();
    }

    CodeGenNodePayload makeLocalStackPayload(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        SWC_ASSERT(codeGen.localStackBaseReg().isValid());

        CodeGenNodePayload localPayload;
        localPayload.typeRef = symVar.typeRef();
        localPayload.setIsAddress();
        if (!symVar.offset())
        {
            localPayload.reg = codeGen.localStackBaseReg();
        }
        else
        {
            MicroBuilder& builder = codeGen.builder();
            localPayload.reg      = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(localPayload.reg, codeGen.localStackBaseReg(), MicroOpBits::B64);
            builder.emitOpBinaryRegImm(localPayload.reg, ApInt(symVar.offset(), 64), MicroOp::Add, MicroOpBits::B64);
        }

        return localPayload;
    }

    MicroOpBits identifierPayloadCopyBits(CodeGen& codeGen, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return MicroOpBits::B64;

        const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
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

        return MicroOpBits::B64;
    }

    CodeGenNodePayload resolveIdentifierVariablePayload(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        const CodeGenNodePayload* symbolPayload = CodeGen::variablePayload(symVar);
        if (symbolPayload)
            return *symbolPayload;

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        {
            const SymbolFunction& symbolFunc = codeGen.function();
            return CodeGenFunctionHelpers::materializeFunctionParameter(codeGen, symbolFunc, symVar);
        }

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
        {
            CodeGenNodePayload localPayload = makeLocalStackPayload(codeGen, symVar);
            codeGen.setVariablePayload(symVar, localPayload);
            return localPayload;
        }

        if (codeGen.localStackBaseReg().isValid() && isFunctionLocalVariable(codeGen, symVar))
        {
            CodeGenNodePayload localPayload = makeLocalStackPayload(codeGen, symVar);
            codeGen.setVariablePayload(symVar, localPayload);
            return localPayload;
        }

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

        ByteSpan payloadBytes;
        if (defaultValue.isStruct())
            payloadBytes = defaultValue.getStruct();
        else if (defaultValue.isArray())
            payloadBytes = defaultValue.getArray();
        else
            return false;

        SWC_ASSERT(payloadBytes.size() == localSize);
        MicroBuilder&  builder    = codeGen.builder();
        const MicroReg payloadReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegPtrReloc(payloadReg, reinterpret_cast<uint64_t>(payloadBytes.data()), defaultValueRef);
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

            default:
                if (symbol.isType())
                    return;
                SWC_UNREACHABLE();
        }
    }

    void materializeSingleVarFromInit(CodeGen& codeGen, const SymbolVariable& symVar, AstNodeRef initRef)
    {
        MicroBuilder& builder  = codeGen.builder();
        const bool    skipInit = symVar.hasExtraFlag(SymbolVariableFlagsE::ExplicitUndefined);
        if (symVar.hasGlobalStorage())
            return;

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) && codeGen.localStackBaseReg().isValid())
        {
            const uint32_t localSize = symVar.codeGenLocalSize();
            SWC_ASSERT(localSize > 0);
            CodeGenNodePayload symbolPayload;
            symbolPayload.typeRef = symVar.typeRef();
            symbolPayload.setIsAddress();

            if (!symVar.offset())
            {
                symbolPayload.reg = codeGen.localStackBaseReg();
            }
            else
            {
                symbolPayload.reg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegReg(symbolPayload.reg, codeGen.localStackBaseReg(), MicroOpBits::B64);
                builder.emitOpBinaryRegImm(symbolPayload.reg, ApInt(symVar.offset(), 64), MicroOp::Add, MicroOpBits::B64);
            }

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
                            codeGen.setVariablePayload(symVar, symbolPayload);
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
            }

            codeGen.setVariablePayload(symVar, symbolPayload);
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
}

Result AstIdentifier::codeGenPostNode(CodeGen& codeGen)
{
    const SemaNodeView view = codeGen.curViewSymbol();
    SWC_ASSERT(view.sym());
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
        materializeSingleVarFromInit(codeGen, symVar, nodeInitRef);
    }

    return Result::Continue;
}

Result AstMultiVarDecl::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView view = codeGen.curViewSymbolList();
    SWC_ASSERT(!view.symList().empty());

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
        }
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
