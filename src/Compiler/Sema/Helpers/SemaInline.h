#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Core/SemaScope.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolImpl;

namespace SemaInline
{
    bool   canInlineCall(Sema& sema, const SymbolFunction& fn);
    Result tryInlineCall(Sema& sema, AstNodeRef callRef, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, std::span<AstNodeRef> sourceArgs = {});
}

struct SemaInlinePayload
{
    bool returnsToCallerSite() const { return sourceFunction && sourceFunction->attributes().hasRtFlag(RtAttributeFlagsE::CalleeReturn); }

    const SymbolFunction*                            sourceFunction      = nullptr;
    SemaInlinePayload*                               parentInlinePayload = nullptr;
    SemaScope*                                       callerScope         = nullptr;
    const SymbolImpl*                                callerImpl          = nullptr;
    SemaScope*                                       upLookupScope       = nullptr;
    bool                                             crossAstInline      = false;
    SymbolVariable*                                  resultVar           = nullptr;
    SmallVector<SemaClone::ParamBinding, 6>          argMappings;
    SmallVector2<SymbolVariable*>                    callerBindingVars;
    SmallVector2<TypeRef>                            callerBindingTypes;
    SmallVector2<SymbolVariable*>                    localVariables;
    std::array<IdentifierRef, 10>                    aliasIdentifiers = {};
    std::array<IdentifierRef, SemaScope::UNIQ_COUNT> uniqIdentifiers  = {};
    // Declared '#code' parameter names of the callee ('stmt: #code(v, dbl)'), in slot
    // order. Fallback names for slots with no call-site alias/binder, and the naming
    // contract for '#inject' value bindings. Bit k of the mask: parameter k is 'var'.
    // When a parameter is typed ('#code(line: &String)'), its type node (owned by
    // codeParamSourceAst) types the synthesized binding declaration.
    SmallVector2<IdentifierRef> codeParamNames;
    SmallVector2<AstNodeRef>    codeParamTypeNodes;
    const Ast*                  codeParamSourceAst = nullptr;
    uint32_t                    codeParamVarMask   = 0;
    AstNodeRef                  callRef            = AstNodeRef::invalid();
    AstNodeRef                  inlineRootRef      = AstNodeRef::invalid();
    TypeRef                     returnTypeRef      = TypeRef::invalid();
};

namespace SemaInline
{
    inline bool hasReturnContext(const SemaInlinePayload& payload) { return !payload.returnsToCallerSite() && payload.returnTypeRef.isValid(); }

    inline SemaInlinePayload* returnContextPayload(SemaInlinePayload* payload)
    {
        while (payload && !hasReturnContext(*payload))
            payload = payload->parentInlinePayload;
        return payload;
    }

    inline const SemaInlinePayload* returnContextPayload(const SemaInlinePayload* payload)
    {
        while (payload && !hasReturnContext(*payload))
            payload = payload->parentInlinePayload;
        return payload;
    }
}

struct SemaInlineContextOverride
{
    const SemaInlinePayload* targetInlinePayload = nullptr;
};

SWC_END_NAMESPACE();
