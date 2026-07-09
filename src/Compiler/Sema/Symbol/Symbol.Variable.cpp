#include "pch.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

const SymbolFunction* SymbolVariable::ownerFunction() const noexcept
{
    if (!hasExtraFlag(SymbolVariableFlagsE::FunctionLocal))
        return nullptr;

    const SymbolMap* map = ownerSymMap();
    while (map)
    {
        if (map->isFunction())
            return &map->cast<SymbolFunction>();
        map = map->ownerSymMap();
    }

    return nullptr;
}

bool SymbolVariable::isUsingField() const noexcept
{
    const AstNode* fieldDecl = decl();
    if (!fieldDecl)
        return false;

    if (fieldDecl->is(AstNodeId::SingleVarDecl))
        return fieldDecl->cast<AstSingleVarDecl>().hasFlag(AstVarDeclFlagsE::Using);
    if (fieldDecl->is(AstNodeId::MultiVarDecl))
        return fieldDecl->cast<AstMultiVarDecl>().hasFlag(AstVarDeclFlagsE::Using);

    return false;
}

const SymbolStruct* SymbolVariable::usingTargetStruct(const TaskContext& ctx) const
{
    bool isPointer = false;
    return usingTargetStruct(ctx, isPointer);
}

const SymbolStruct* SymbolVariable::usingTargetStruct(const TaskContext& ctx, bool& outIsPointer) const
{
    outIsPointer = false;

    // A using field exposes members/operators of either a struct value or a pointer
    // to a struct. Report pointer-ness separately because some lookups intentionally
    // refuse to compose through borrowed/indirect storage.
    const TypeManager& typeMgr = ctx.typeMgr();
    if (!typeRef().isValid())
        return nullptr;

    const TypeRef fieldTypeRef = typeMgr.get(typeRef()).unwrapAliasEnum(ctx, typeRef());
    if (!fieldTypeRef.isValid())
        return nullptr;

    const TypeInfo& fieldType = typeMgr.get(fieldTypeRef);
    if (fieldType.isStruct())
        return &fieldType.payloadSymStruct();

    if (!fieldType.isAnyPointer())
        return nullptr;

    const TypeRef rawPointeeTypeRef = fieldType.payloadTypeRef();
    if (!rawPointeeTypeRef.isValid())
        return nullptr;

    const TypeRef pointeeTypeRef = typeMgr.get(rawPointeeTypeRef).unwrapAliasEnum(ctx, rawPointeeTypeRef);
    if (!pointeeTypeRef.isValid())
        return nullptr;

    const TypeInfo& pointeeType = typeMgr.get(pointeeTypeRef);
    if (!pointeeType.isStruct())
        return nullptr;

    outIsPointer = true;
    return &pointeeType.payloadSymStruct();
}

void SymbolVariable::setClosureCaptureByRef(bool value) noexcept
{
    if (value)
        addExtraFlag(SymbolVariableFlagsE::ClosureCaptureByRef);
    else
        removeExtraFlag(SymbolVariableFlagsE::ClosureCaptureByRef);
}

void SymbolVariable::setClosureCapturedSource(SymbolVariable* source) noexcept
{
    // The capture symbol is the closure field; the source points back to the
    // original local/parameter so escape analysis and debug info can report the
    // user-visible storage.
    addExtraFlag(SymbolVariableFlagsE::ClosureCapture);
    closureCapturedSource_ = source;
}

void SymbolVariable::setGlobalStorage(DataSegmentKind kind, uint32_t offset)
{
    // Global variables are addressed through a data segment plus offset. Mark the
    // storage kind atomically with the offset so later codegen paths do not have to
    // infer globals from symbol-map ownership.
    globalStorageKind_ = kind;
    offset_            = offset;
    addExtraFlag(SymbolVariableFlagsE::GlobalStorage);
}

SWC_END_NAMESPACE();
