#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;
class SymbolStruct;
class SymbolVariable;
class TypeInfo;
struct SourceCodeRef;

namespace SemaHelpers
{
    struct DestructuringField;
}

namespace CodeGenStructHelpers
{
    struct StructLikeFieldLayout
    {
        TypeRef  typeRef = TypeRef::invalid();
        uint32_t offset  = 0;
    };

    // Reuse only within one traversal of the same aggregate type.
    struct StructLikeFieldLayoutCursor
    {
        size_t   nextFieldIndex = 0;
        uint64_t offset         = 0;
    };

    const SymbolStruct* variableOwnerStruct(const SymbolVariable& symVar);
    const SymbolStruct* resolveRuntimeStructType(CodeGen& codeGen, TypeRef typeRef);
    const SymbolStruct* resolveReceiverRuntimeStruct(CodeGen& codeGen);
    TypeRef             resolveRuntimeLeftTypeRef(CodeGen& codeGen, AstNodeRef leftRef, TypeRef leftTypeRef);

    const SymbolVariable* tryResolveConcreteStructMemberSymbol(CodeGen& codeGen, TypeRef leftTypeRef, const SymbolVariable& memberSym);
    const SymbolVariable* tryResolveConcreteReceiverFieldSymbol(CodeGen& codeGen, const SymbolVariable& fieldSym);
    const SymbolVariable* tryResolveSameGenericFamilyFieldSymbol(const SymbolStruct& runtimeStruct, const SymbolVariable& fieldSym);

    bool   destructuringSourceIsLValue(CodeGen& codeGen, AstNodeRef sourceRef);
    Result emitDropDestructuringRemainder(CodeGen& codeGen, MicroReg source, std::span<const SemaHelpers::DestructuringField> fields);

    void emitRecordOrTupleCast(CodeGen& codeGen, MicroReg destination, MicroReg source, TypeRef sourceType, TypeRef targetType);

    size_t                structLikeFieldIndex(CodeGen& codeGen, const TypeInfo& typeInfo, const SourceCodeRef& fieldNameRef);
    size_t                structLikeFieldCount(const TypeInfo& typeInfo);
    StructLikeFieldLayout structLikeFieldLayout(CodeGen& codeGen, StructLikeFieldLayoutCursor& cursor, const TypeInfo& typeInfo, size_t fieldIndex);
}

SWC_END_NAMESPACE();
