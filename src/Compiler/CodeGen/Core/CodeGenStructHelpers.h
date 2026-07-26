#pragma once
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;
class SymbolStruct;
class SymbolVariable;
struct SourceCodeRef;

namespace CodeGenStructHelpers
{
    struct StructLikeFieldLayout
    {
        TypeRef  typeRef = TypeRef::invalid();
        uint32_t offset  = 0;
    };

    const SymbolStruct*   variableOwnerStruct(const SymbolVariable& symVar);
    const SymbolStruct*   resolveRuntimeStructType(CodeGen& codeGen, TypeRef typeRef);
    const SymbolStruct*   resolveReceiverRuntimeStruct(CodeGen& codeGen);
    TypeRef               resolveRuntimeLeftTypeRef(CodeGen& codeGen, AstNodeRef leftRef, TypeRef leftTypeRef);
    const SymbolVariable* tryResolveConcreteStructMemberSymbol(CodeGen& codeGen, TypeRef leftTypeRef, const SymbolVariable& memberSym);
    const SymbolVariable* tryResolveConcreteReceiverFieldSymbol(CodeGen& codeGen, const SymbolVariable& fieldSym);
    const SymbolVariable* tryResolveSameGenericFamilyFieldSymbol(const SymbolStruct& runtimeStruct, const SymbolVariable& fieldSym);
    size_t                structLikeFieldIndex(CodeGen& codeGen, TypeRef typeRef, const SourceCodeRef& fieldNameRef);
    StructLikeFieldLayout structLikeFieldLayout(CodeGen& codeGen, TypeRef typeRef, size_t fieldIndex);
}

SWC_END_NAMESPACE();
