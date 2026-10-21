#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Core/SemaScope.h"
#include "Compiler/Sema/Helpers/SemaCloneTypes.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolImpl;
struct SemaInlinePayload;

namespace SemaInline
{
    const SemaInlinePayload* expansionPayload(Sema& sema, AstNodeRef nodeRef);

    bool   canInlineCall(Sema& sema, const SymbolFunction& fn);
    Result tryInlineCall(Sema& sema, AstNodeRef callRef, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, std::span<AstNodeRef> sourceArgs = {});
}

struct SemaInlinePayload
{
    bool returnsToCallerSite() const { return sourceFunction && sourceFunction->attributes().hasRtFlag(RtAttributeFlagsE::CalleeReturn); }

    const SymbolFunction* sourceFunction      = nullptr;
    SemaInlinePayload*    parentInlinePayload = nullptr;

    SemaScope*        callerScope   = nullptr;
    const SymbolImpl* callerImpl    = nullptr;
    SemaScope*        upLookupScope = nullptr;

    bool     crossAstInline          = false;
    uint16_t runtimeSafetyMask       = 0;
    uint16_t callerRuntimeSafetyMask = 0;

    SymbolVariable* resultVar = nullptr;

    SmallVector<SemaClone::ParamBinding, 6> argMappings;
    SmallVector2<SymbolVariable*>           callerBindingVars;
    SmallVector2<TypeRef>                   callerBindingTypes;
    SmallVector2<AstNodeRef>                materializedArgRefs;

    SmallVector2<SymbolVariable*> localVariables;

    std::array<IdentifierRef, 10> aliasIdentifiers = {};
    std::array<SourceCodeRef, 10> aliasNameRefs    = {}; // where the call site wrote each alias

    TokenRef sourceEndRef = TokenRef::invalid(); // last token of 'sourceFunction', once asked

    std::array<IdentifierRef, SemaScope::UNIQ_COUNT> uniqIdentifiers = {};

    // Declared #code slot names provide fallbacks for missing call-site aliases/binders
    // and define #inject value names. Type nodes belong to codeParamSourceAst;
    // bit k of codeParamVarMask marks a var parameter.
    SmallVector2<IdentifierRef> codeParamNames;
    SmallVector2<AstNodeRef>    codeParamTypeNodes;

    const Ast* codeParamSourceAst = nullptr;
    uint32_t   codeParamVarMask   = 0;

    AstNodeRef callRef       = AstNodeRef::invalid();
    AstNodeRef inlineRootRef = AstNodeRef::invalid();
    // The call site in source terms. Node references depend on when the clone was appended.
    SourceCodeRef callSite;
    TypeRef       returnTypeRef = TypeRef::invalid();

    // Drop caller flow-narrowing facts from this first callee-origin statement onward.
    // Earlier materialized argument bindings remain caller code and retain those facts.
    // Invalid for macros/mixins, which expand textually as caller code.
    AstNodeRef narrowFactsBodyStartRef = AstNodeRef::invalid();
};

namespace SemaInline
{
    inline const SemaClone::ParamBinding* findArgumentBinding(const SemaInlinePayload* payload, IdentifierRef idRef)
    {
        while (payload)
        {
            for (const auto& binding : payload->argMappings)
            {
                if (binding.idRef == idRef)
                    return &binding;
            }

            payload = payload->parentInlinePayload;
        }

        return nullptr;
    }

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
