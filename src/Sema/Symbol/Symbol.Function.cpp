#include "pch.h"
#include "Sema/Symbol/Symbol.Function.h"
#include "Sema/Symbol/Symbol.Variable.h"
#include "Sema/Core/Sema.h"

SWC_BEGIN_NAMESPACE();

Utf8 SymbolFunction::computeName(const TaskContext& ctx) const
{
    Utf8 out;
    out += hasFuncFlag(SymbolFunctionFlagsE::Method) ? "mtd" : "func";
    out += hasFuncFlag(SymbolFunctionFlagsE::Closure) ? "||" : "";
    out += "(";
    for (size_t i = 0; i < parameters_.size(); ++i)
    {
        if (i != 0)
            out += ", ";

        if (parameters_[i]->idRef().isValid())
        {
            out += parameters_[i]->name(ctx);
            out += ": ";
        }

        const TypeInfo& paramType = ctx.typeMgr().get(parameters_[i]->typeRef());
        out += paramType.toName(ctx);
    }
    out += ")";

    if (returnType_.isValid())
    {
        out += "->";
        const TypeInfo& returnType = ctx.typeMgr().get(returnType_);
        out += returnType.toName(ctx);
    }

    out += hasFuncFlag(SymbolFunctionFlagsE::Throwable) ? " throw" : "";
    return out;
}

void SymbolFunction::setFuncFlags(EnumFlags<AstFunctionFlagsE> parserFlags)
{
    if (parserFlags.has(AstFunctionFlagsE::Method))
        addFuncFlag(SymbolFunctionFlagsE::Method);
    if (parserFlags.has(AstFunctionFlagsE::Throwable))
        addFuncFlag(SymbolFunctionFlagsE::Throwable);
    if (parserFlags.has(AstFunctionFlagsE::Closure))
        addFuncFlag(SymbolFunctionFlagsE::Closure);
}

SWC_END_NAMESPACE();
