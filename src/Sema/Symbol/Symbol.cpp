#include "pch.h"
#include "Sema/Symbol/Symbol.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Sema/Symbol/IdentifierManager.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

void Symbol::setFullComplete(TaskContext& ctx)
{
    SWC_ASSERT(flags_.hasNot(SymbolFlagsE::FullComplete));
    flags_.add(SymbolFlagsE::FullComplete);
    ctx.compiler().notifySymbolFullComplete();
}

std::string_view Symbol::name(const TaskContext& ctx) const
{
    const Identifier& id = ctx.compiler().idMgr().get(idRef_);
    return id.name;
}

const TypeInfo& Symbol::typeInfo(const TaskContext& ctx) const
{
    SWC_ASSERT(typeRef_.isValid());
    return ctx.typeMgr().get(typeRef_);
}

SWC_END_NAMESPACE()
