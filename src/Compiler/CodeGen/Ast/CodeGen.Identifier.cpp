#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
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
        const CodeGenNodePayload* symbolPayload = codeGen.variablePayload(symVar);
        if (symbolPayload)
            return *symbolPayload;

        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
        {
            const SymbolFunction& symbolFunc = codeGen.function();
            return CodeGenHelpers::materializeFunctionParameter(codeGen, symbolFunc, symVar);
        }

        SWC_UNREACHABLE();
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

            default:
                SWC_UNREACHABLE();
        }
    }

    void materializeSingleVarFromInit(CodeGen& codeGen, const SymbolVariable& symVar, AstNodeRef initRef)
    {
        MicroBuilder& builder = codeGen.builder();
        if (initRef.isInvalid())
            return;

        const CodeGenNodePayload* initPayload = codeGen.payload(initRef);
        if (!initPayload)
            return;

        CodeGenNodePayload symbolPayload;
        symbolPayload.typeRef     = symVar.typeRef();
        symbolPayload.storageKind = initPayload->storageKind;

        if (initPayload->isAddress())
        {
            symbolPayload.reg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegReg(symbolPayload.reg, initPayload->reg, MicroOpBits::B64);
        }
        else
        {
            const MicroOpBits copyBits = identifierPayloadCopyBits(codeGen, symVar.typeRef());
            symbolPayload.reg          = codeGen.nextVirtualRegisterForType(symVar.typeRef());
            builder.emitLoadRegReg(symbolPayload.reg, initPayload->reg, copyBits);
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
        CodeGenHelpers::materializeFunctionParameter(codeGen, symbolFunc, symVar);
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
            CodeGenHelpers::materializeFunctionParameter(codeGen, symbolFunc, symVar);
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
