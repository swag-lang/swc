#include "pch.h"

#if SWC_HAS_UNITTEST
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Symbol/Symbol.Module.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/SourceFile.h"
#include "Unittest/UnittestSource.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/TaskContext.h"
#include "Unittest/ABI/AbiTestTypes.h"

SWC_BEGIN_NAMESPACE();

SourceFile& Backend::Unittest::makeCodeGenSource(TaskContext& ctx, std::string_view testName, std::string_view source)
{
    SourceFile& file = swc::Unittest::addTestSource(ctx, "ABI", testName, source);
    auto* module = Symbol::make<SymbolModule>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    auto* nameSpace = Symbol::make<SymbolNamespace>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    nameSpace->setOwnerSymMap(module);
    file.setModuleNamespace(*nameSpace);
    SWC_INTERNAL_CHECK(parseLoadedSourceFile(ctx, file, {}) == Result::Continue);
    return file;
}

TypeRef Backend::Unittest::makeStructType(TaskContext& ctx, const std::span<const TypeRef> fieldTypes, const bool isUnion, const TypeRef tagType)
{
    auto* record = Symbol::make<SymbolStruct>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    if (isUnion)
        record->addExtraFlag(SymbolStructFlagsE::Union);
    if (tagType.isValid())
    {
        record->addExtraFlag(SymbolStructFlagsE::Tagged);
        record->setTaggedTypeRef(tagType);
    }
    for (const TypeRef fieldType : fieldTypes)
    {
        auto* field = Symbol::make<SymbolVariable>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        field->setTypeRef(fieldType);
        record->addField(field);
    }
    SWC_ASSERT(record->computeLayout(ctx) == Result::Continue);
    const TypeRef type = ctx.typeMgr().addType(TypeInfo::makeStruct(record));
    record->setTypeRef(type);
    return type;
}

SWC_END_NAMESPACE();
#endif
