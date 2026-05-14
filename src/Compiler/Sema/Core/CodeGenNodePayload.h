#pragma once
#include "Backend/Micro/MicroReg.h"
#include "Backend/Runtime.h"
#include "Compiler/Lexer/Token.h"
#include "Compiler/Sema/Helpers/SemaSafety.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;
class SymbolVariable;

struct CodeGenNodePayload
{
    enum class StorageKind : uint8_t
    {
        Value,
        Address,
    };

    MicroReg        reg;
    TypeRef         typeRef                      = TypeRef::invalid();
    TypeRef         runtimeArrayFillTypeRef      = TypeRef::invalid();
    StorageKind     storageKind                  = StorageKind::Value;
    bool            materializedPointerLikeValue = false;
    SymbolVariable* runtimeStorageSym            = nullptr;
    SymbolFunction* runtimeFunctionSymbol        = nullptr;
    ConstantRef     runtimeArrayFillCstRef       = ConstantRef::invalid();
    uint16_t        runtimeSafetyMask            = 0;
    AstNodeRef      throwableWrapperOwnerRef     = AstNodeRef::invalid();
    TokenId         throwableWrapperTokenId      = TokenId::Invalid;
    MicroLabelRef   throwableFailLabel           = MicroLabelRef::invalid();
    MicroLabelRef   throwableDoneLabel           = MicroLabelRef::invalid();
    MicroLabelRef   throwableFunctionFailLabel   = MicroLabelRef::invalid();
    MicroLabelRef   throwableFunctionDoneLabel   = MicroLabelRef::invalid();

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

    TypeRef effectiveTypeRef(TypeRef fallbackTypeRef) const
    {
        if (typeRef.isValid())
            return typeRef;
        return fallbackTypeRef;
    }

    void addRuntimeSafety(Runtime::SafetyWhat what)
    {
        runtimeSafetyMask |= SemaSafety::mask(what);
    }

    bool hasRuntimeSafety(Runtime::SafetyWhat what) const
    {
        return SemaSafety::hasMask(runtimeSafetyMask, what);
    }

    bool hasRuntimeArrayFill() const
    {
        return runtimeArrayFillTypeRef.isValid() && runtimeArrayFillCstRef.isValid();
    }

    bool hasThrowableWrapper() const
    {
        return throwableWrapperTokenId != TokenId::Invalid;
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
    }

    void clearThrowableFunctionTarget()
    {
        throwableFunctionFailLabel = MicroLabelRef::invalid();
        throwableFunctionDoneLabel = MicroLabelRef::invalid();
    }
};

SWC_END_NAMESPACE();
