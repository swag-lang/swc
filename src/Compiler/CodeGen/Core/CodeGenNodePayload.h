#pragma once
#include "Support/Core/RefTypes.h"
#include "Backend/Micro/MicroReg.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"

SWC_BEGIN_NAMESPACE();

struct CodeGenNodePayload : CodeGenLoweringPayload
{
    enum class StorageKind : uint8_t
    {
        Value,
        Address,
    };

    MicroReg      reg;
    TypeRef       typeRef                  = TypeRef::invalid();
    StorageKind   storageKind              = StorageKind::Value;
    bool          materializedPointerLikeValue = false;
    bool          runtimeStorageOverridden = false;
    bool          throwableWrapperConsumed = false;
    MicroLabelRef throwableFailLabel       = MicroLabelRef::invalid();
    MicroLabelRef throwableDoneLabel       = MicroLabelRef::invalid();
    MicroLabelRef throwableFunctionFailLabel = MicroLabelRef::invalid();
    MicroLabelRef throwableFunctionDoneLabel = MicroLabelRef::invalid();

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
        runtimeStorageSym = sym;
        runtimeStorageOverridden = true;
    }

    TypeRef effectiveTypeRef(TypeRef fallbackTypeRef) const
    {
        if (typeRef.isValid())
            return typeRef;
        return fallbackTypeRef;
    }

    bool hasThrowableFunctionTarget() const
    {
        return throwableFunctionFailLabel.isValid();
    }

    void clearThrowableWrapper()
    {
        throwableWrapperOwnerRef = AstNodeRef::invalid();
        throwableWrapperTokenId  = TokenId::Invalid;
        throwableFailLabel       = MicroLabelRef::invalid();
        throwableDoneLabel       = MicroLabelRef::invalid();
        throwableWrapperConsumed = true;
    }

    void clearThrowableFunctionTarget()
    {
        throwableFunctionFailLabel = MicroLabelRef::invalid();
        throwableFunctionDoneLabel = MicroLabelRef::invalid();
    }
};

SWC_END_NAMESPACE();
