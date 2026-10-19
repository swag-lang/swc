#include "pch.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Symbol/SymbolOwnerFunction.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

const SymbolFunction* SymbolVariable::ownerFunction() const noexcept
{
    if (!hasExtraFlag(SymbolVariableFlagsE::FunctionLocal))
        return nullptr;

    return SymbolOwnerFunction::nearest(ownerSymMap());
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

    // Using fields can expose struct values or pointers. Report indirection separately
    // because some lookups cannot compose through borrowed storage.
    const TypeManager& typeMgr = ctx.typeMgr();
    if (!typeRef().isValid())
        return nullptr;

    const TypeInfo& fieldType = typeMgr.unwrapAliasEnumTypeOrSelf(ctx, typeRef());
    if (fieldType.isStruct())
        return &fieldType.payloadSymStruct();

    if (!fieldType.isAnyPointer())
        return nullptr;

    const TypeRef rawPointeeTypeRef = fieldType.payloadTypeRef();
    if (!rawPointeeTypeRef.isValid())
        return nullptr;

    const TypeInfo& pointeeType = typeMgr.unwrapAliasEnumTypeOrSelf(ctx, rawPointeeTypeRef);
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
    // Captures are closure fields. Keep the original local or parameter so escape
    // analysis and debug information refer to the user-visible storage.
    addExtraFlag(SymbolVariableFlagsE::ClosureCapture);
    closureCapturedSource_ = source;
}

void SymbolVariable::setGlobalStorage(DataSegmentKind kind, uint32_t offset)
{
    // Store the data-segment location before publishing GlobalStorage so codegen
    // need not infer global storage from symbol-map ownership.
    globalStorageKind_ = kind;
    offset_            = offset;
    addExtraFlag(SymbolVariableFlagsE::GlobalStorage);
}

SWC_END_NAMESPACE();
