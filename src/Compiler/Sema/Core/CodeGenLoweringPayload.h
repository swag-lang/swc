#pragma once
#include "Backend/RuntimeSafety.h"
#include "Compiler/Lexer/Token.h"
#include "Compiler/Sema/Helpers/SemaSafety.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;
class SymbolVariable;

struct CodeGenLoweringPayload
{
    TypeRef         runtimeArrayFillTypeRef = TypeRef::invalid();
    ConstantRef     runtimeArrayFillCstRef  = ConstantRef::invalid();
    SymbolVariable* runtimeStorageSym       = nullptr;

    // Reattach this node's original storage after a folded cast or a sema pause,
    // avoiding a fresh frame slot on every rerun.
    SymbolVariable* registeredRuntimeStorageSym = nullptr;

    SymbolVariable* errBindingSym      = nullptr; // the captured-error local 'Swag.err' reads
    SymbolVariable* errOwnerSym        = nullptr; // lexical owner of the captured error view
    SymbolVariable* errHandlerOwnerSym = nullptr; // owner while a catch handler is active

    SymbolFunction* runtimeFunctionSymbol = nullptr;

    AstNodeRef fallibleWrapperOwnerRef = AstNodeRef::invalid();
    TokenId    fallibleWrapperTokenId  = TokenId::Invalid;
    uint16_t   runtimeSafetyMask       = 0;

    int8_t valueBorrowSafetyOverride          = -1; // Local override; otherwise use the function or inline body.
    bool   ifVarDeclWhereUsesConditionBinding = false;
    bool   notNullUnwrap                      = false;
    bool   catchCoalescesNull                 = false; // 'catch e orelse V' with a nullable result

    // A UFCS pointer parameter receives the receiver's address as its value;
    // the receiver's bits are never converted numerically.
    bool ufcsReceiverAddress = false;

    bool dynamicCast         = false;
    bool assumedDynamicCast  = false;
    bool fallibleDynamicCast = false;
    bool runtimeTypeCast     = false;
    bool runtimeValueCast    = false;

    bool moveValue = false;
    bool ownsValue = false;

    // A tagged-union payload access asserted by a postfix '!': lowering checks the active case
    // when the Switch guard is enabled.
    bool taggedCaseAsserted = false;

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

    bool hasDynamicCastCheck() const
    {
        return fallibleDynamicCast || hasRuntimeSafety(Runtime::SafetyWhat::Assume) || hasRuntimeSafety(Runtime::SafetyWhat::DynCast);
    }

    bool hasFallibleWrapper() const
    {
        return fallibleWrapperTokenId != TokenId::Invalid;
    }
};

#if !SWC_HAS_REF_DEBUG_INFO
static_assert(sizeof(void*) != 8 || sizeof(CodeGenLoweringPayload) == 80);
#endif

SWC_END_NAMESPACE();
