#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

class Sema;

namespace SemaInline
{
    struct ArgMapping
    {
        IdentifierRef paramIdRef = IdentifierRef::invalid();
        AstNodeRef    argRef     = AstNodeRef::invalid();
    };

    struct Payload
    {
        static constexpr uint32_t MAGIC = 0x4E4C4E49u;

        uint32_t                   magic          = MAGIC;
        AstNodeRef                 callRef        = AstNodeRef::invalid();
        AstNodeRef                 inlineRootRef  = AstNodeRef::invalid();
        const SymbolFunction*      sourceFunction = nullptr;
        TypeRef                    returnTypeRef  = TypeRef::invalid();
        SymbolVariable*            resultVar      = nullptr;
        SmallVector<ArgMapping, 8> argMappings;
    };

    inline bool isInlinePayload(const Payload* payload)
    {
        return payload && payload->magic == Payload::MAGIC;
    }

    bool   canInlineCall(Sema& sema, const SymbolFunction& fn);
    Result tryInlineCall(Sema& sema, AstNodeRef callRef, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg);
}

SWC_END_NAMESPACE();
