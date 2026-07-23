#pragma once
#include "Backend/Runtime.h"
#include "Compiler/Lexer/Token.h"
#include "Compiler/Sema/Helpers/SemaSafety.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;
class SymbolVariable;

struct CodeGenLoweringPayload
{
    TypeRef         runtimeArrayFillTypeRef            = TypeRef::invalid();
    SymbolVariable* runtimeStorageSym                  = nullptr;
    SymbolFunction* runtimeFunctionSymbol              = nullptr;
    ConstantRef     runtimeArrayFillCstRef             = ConstantRef::invalid();
    uint16_t        runtimeSafetyMask                  = 0;
    AstNodeRef      throwableWrapperOwnerRef           = AstNodeRef::invalid();
    TokenId         throwableWrapperTokenId            = TokenId::Invalid;
    bool            ifVarDeclWhereUsesConditionBinding = false;
    bool            assumeNullable                     = false;

    void addRuntimeSafety(Runtime::SafetyWhat what)
    {
        runtimeSafetyMask |= SemaSafety::mask(what);
    }

    void removeRuntimeSafety(Runtime::SafetyWhat what)
    {
        runtimeSafetyMask &= static_cast<uint16_t>(~SemaSafety::mask(what));
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
};

SWC_END_NAMESPACE();
