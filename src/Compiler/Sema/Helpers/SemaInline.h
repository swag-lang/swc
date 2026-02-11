#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

class Sema;

namespace SemaInline
{
    struct ParamBinding
    {
        IdentifierRef idRef;
        AstNodeRef    exprRef;
    };

    struct CloneContext final : ::swc::CloneContext
    {
        std::span<const ParamBinding> bindings;

        explicit CloneContext(std::span<const ParamBinding> inBindings) :
            bindings(inBindings)
        {
        }
    };

    bool tryInlineCall(Sema& sema, AstNodeRef callRef, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg);
}

SWC_END_NAMESPACE();
