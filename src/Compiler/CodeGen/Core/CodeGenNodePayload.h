#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

struct CodeGenNodePayload : CodeGenLoweringPayload
{
    enum class StorageKind : uint8_t
    {
        Value,
        Address,
    };

    MicroReg      reg;
    SourceCodeRef sourceCodeRef = SourceCodeRef::invalid();
    TypeRef       typeRef       = TypeRef::invalid();
    StorageKind   storageKind   = StorageKind::Value;

    bool materializedPointerLikeValue = false;
    bool runtimeStorageOverridden     = false;

    bool          fallibleWrapperConsumed = false;
    MicroLabelRef fallibleFailLabel       = MicroLabelRef::invalid();
    MicroLabelRef fallibleDoneLabel       = MicroLabelRef::invalid();

    MicroLabelRef fallibleFunctionFailLabel = MicroLabelRef::invalid();
    MicroLabelRef fallibleFunctionDoneLabel = MicroLabelRef::invalid();

    void setIsValue() { storageKind = StorageKind::Value; }
    bool isValue() const { return storageKind == StorageKind::Value; }
    void setIsAddress() { storageKind = StorageKind::Address; }
    bool isAddress() const { return storageKind == StorageKind::Address; }

    void setValueOrAddress(bool isIndirect)
    {
        if (isIndirect)
            setIsAddress();
        else
            setIsValue();
    }

    void markMaterializedPointerLikeValue() { materializedPointerLikeValue = true; }
    void clearMaterializedPointerLikeValue() { materializedPointerLikeValue = false; }
    bool hasMaterializedPointerLikeValue() const { return materializedPointerLikeValue; }

    void setRuntimeStorageSymbol(SymbolVariable* sym)
    {
        runtimeStorageSym        = sym;
        runtimeStorageOverridden = true;
    }

    TypeRef effectiveTypeRef(TypeRef fallbackTypeRef) const
    {
        if (typeRef.isValid())
            return typeRef;

        return fallbackTypeRef;
    }

    void clearFallibleWrapper()
    {
        fallibleWrapperOwnerRef = AstNodeRef::invalid();
        fallibleWrapperTokenId  = TokenId::Invalid;
        fallibleFailLabel       = MicroLabelRef::invalid();
        fallibleDoneLabel       = MicroLabelRef::invalid();
        fallibleWrapperConsumed = true;
    }

    void clearFallibleFunctionTarget()
    {
        fallibleFunctionFailLabel = MicroLabelRef::invalid();
        fallibleFunctionDoneLabel = MicroLabelRef::invalid();
    }
};

enum class ConditionalExprStage : uint8_t
{
    TrueBranch,
    FalseBranch,
};

// Branch state belongs to the original expression. Its value may be shared with
// a substitute, but that must not alias labels or require a larger value payload.
struct ConditionalExprCodeGenPayload
{
    MicroLabelRef        falseLabel = MicroLabelRef::invalid();
    MicroLabelRef        doneLabel  = MicroLabelRef::invalid();
    ConditionalExprStage stage      = ConditionalExprStage::TrueBranch;
};

struct NullCoalescingCodeGenPayload
{
    MicroLabelRef falseLabel = MicroLabelRef::invalid();
    MicroLabelRef doneLabel  = MicroLabelRef::invalid();
};

struct LogicalExprCodeGenPayload
{
    MicroLabelRef doneLabel = MicroLabelRef::invalid();
};

struct AssertCodeGenPayload
{
    MicroLabelRef doneLabel = MicroLabelRef::invalid();
};

// Lowering state of an OptionalChainExpr root. Created before the chain body is
// generated so every '?.' link can jump to 'falseLabel' when its left side is null.
// A fused chain (scalar result consumed by 'orelse') leaves its labels valid for the
// enclosing coalescing to adopt; a standalone chain invalidates them once placed.
struct OptionalChainCodeGenPayload
{
    MicroLabelRef falseLabel = MicroLabelRef::invalid();
    MicroLabelRef doneLabel  = MicroLabelRef::invalid();
};

SWC_END_NAMESPACE();
