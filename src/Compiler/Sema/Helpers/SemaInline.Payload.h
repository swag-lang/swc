#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

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
}

SWC_END_NAMESPACE();
