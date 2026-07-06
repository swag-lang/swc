#include "pch.h"
#include "Compiler/ModuleApi/ModuleApi.Export.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"

SWC_BEGIN_NAMESPACE();
using namespace ModuleApi::Export;

namespace
{
    struct ModuleApiDependencyCollector
    {
        TaskContext*                      ctx;
        std::vector<const Symbol*>        symbols;
        std::unordered_set<const Symbol*> symbolSet;
        std::unordered_set<const Symbol*> visitedSymbols;
        std::unordered_set<TypeRef>       visitedTypeRefs;
    };

    bool isGeneratedModuleApiTypeSymbol(const Symbol& symbol)
    {
        return symbol.isAlias() || symbol.isStruct() || symbol.isEnum() || symbol.isInterface();
    }

    void collectModuleApiSymbolDependencies(ModuleApiDependencyCollector& collector, const Symbol& symbol);
    void collectModuleApiTypeRefDependencies(ModuleApiDependencyCollector& collector, TypeRef typeRef);

    void collectModuleApiTypeSymbolDependency(ModuleApiDependencyCollector& collector, const Symbol& symbol)
    {
        if (!isCurrentModuleSymbol(collector.ctx->compiler(), symbol))
            return;
        if (isWholeFileExportedSymbol(collector.ctx->compiler(), symbol))
            return;
        if (!symbol.isPublic() || !isGeneratedModuleApiTypeSymbol(symbol))
            return;

        if (collector.symbolSet.insert(&symbol).second)
            collector.symbols.push_back(&symbol);
    }

    void collectModuleApiGenericArgDependencies(ModuleApiDependencyCollector& collector, std::span<const GenericInstanceKey> genericArgs)
    {
        for (const GenericInstanceKey& arg : genericArgs)
        {
            if (arg.typeRef.isValid())
            {
                collectModuleApiTypeRefDependencies(collector, arg.typeRef);
                continue;
            }

            if (arg.cstRef.isValid())
                collectModuleApiTypeRefDependencies(collector, collector.ctx->cstMgr().get(arg.cstRef).typeRef());
        }
    }

    void collectModuleApiFunctionDependencies(ModuleApiDependencyCollector& collector, const SymbolFunction& symbolFunction)
    {
        if (const SymbolImpl* symImpl = symbolFunction.declImplContext())
        {
            if (symImpl->isForStruct() && symImpl->symStruct())
                collectModuleApiTypeSymbolDependency(collector, *symImpl->symStruct());
            else if (symImpl->isForEnum() && symImpl->symEnum())
                collectModuleApiTypeSymbolDependency(collector, *symImpl->symEnum());
            else if (symImpl->isForInterface() && symImpl->symInterface())
                collectModuleApiTypeSymbolDependency(collector, *symImpl->symInterface());

            if (symImpl->symInterface())
                collectModuleApiTypeSymbolDependency(collector, *symImpl->symInterface());
        }

        if (symbolFunction.isGenericInstance())
        {
            SmallVector<GenericInstanceKey> genericArgs;
            if (symbolFunction.tryGetGenericInstanceArgs(*collector.ctx, genericArgs))
                collectModuleApiGenericArgDependencies(collector, genericArgs.span());
        }

        if (symbolFunction.returnTypeRef().isValid() && symbolFunction.returnTypeRef() != collector.ctx->typeMgr().typeVoid())
            collectModuleApiTypeRefDependencies(collector, symbolFunction.returnTypeRef());

        for (const SymbolVariable* param : symbolFunction.parameters())
        {
            if (param && param->typeRef().isValid())
                collectModuleApiTypeRefDependencies(collector, param->typeRef());
        }
    }

    void collectModuleApiTypeRefDependencies(ModuleApiDependencyCollector& collector, const TypeRef typeRef)
    {
        if (!typeRef.isValid() || !collector.visitedTypeRefs.insert(typeRef).second)
            return;

        const TypeInfo& type = collector.ctx->typeMgr().get(typeRef);
        if (type.isAlias())
        {
            const SymbolAlias& alias = type.payloadSymAlias();
            collectModuleApiTypeSymbolDependency(collector, alias);
            collectModuleApiTypeRefDependencies(collector, alias.underlyingTypeRef());
            return;
        }

        if (type.isStruct())
        {
            const SymbolStruct& symbolStruct = type.payloadSymStruct();
            collectModuleApiTypeSymbolDependency(collector, symbolStruct);
            if (symbolStruct.isGenericInstance())
            {
                SmallVector<GenericInstanceKey> genericArgs;
                if (symbolStruct.tryGetGenericInstanceArgs(genericArgs))
                    collectModuleApiGenericArgDependencies(collector, genericArgs.span());
            }

            return;
        }

        if (type.isInterface())
        {
            collectModuleApiTypeSymbolDependency(collector, type.payloadSymInterface());
            return;
        }

        if (type.isEnum())
        {
            collectModuleApiTypeSymbolDependency(collector, type.payloadSymEnum());
            return;
        }

        if (type.isArray())
        {
            collectModuleApiTypeRefDependencies(collector, type.payloadArrayElemTypeRef());
            return;
        }

        if (type.isSlice() || type.isAnyPointer() || type.isReference() || type.isTypeValue() || type.isTypedVariadic() || type.isCodeBlock())
        {
            collectModuleApiTypeRefDependencies(collector, type.payloadTypeRef());
            return;
        }

        if (type.isFunction())
        {
            collectModuleApiFunctionDependencies(collector, type.payloadSymFunction());
            return;
        }

        if (type.isAggregateStruct() || type.isAggregateArray())
        {
            for (const TypeRef childTypeRef : type.payloadAggregate().types)
                collectModuleApiTypeRefDependencies(collector, childTypeRef);
        }
    }

    void collectModuleApiSymbolDependencies(ModuleApiDependencyCollector& collector, const Symbol& symbol)
    {
        if (!collector.visitedSymbols.insert(&symbol).second)
            return;

        if (const auto* symbolAlias = symbol.safeCast<SymbolAlias>())
        {
            if (const Symbol* aliasedSymbol = symbolAlias->aliasedSymbol())
                collectModuleApiTypeSymbolDependency(collector, *aliasedSymbol);
            collectModuleApiTypeRefDependencies(collector, symbolAlias->underlyingTypeRef());
            return;
        }

        if (const auto* symbolEnum = symbol.safeCast<SymbolEnum>())
        {
            collectModuleApiTypeRefDependencies(collector, symbolEnum->underlyingTypeRef());
            return;
        }

        if (const auto* symbolInterface = symbol.safeCast<SymbolInterface>())
        {
            for (const SymbolFunction* function : symbolInterface->functions())
            {
                if (function)
                    collectModuleApiFunctionDependencies(collector, *function);
            }

            return;
        }

        if (const auto* symbolStruct = symbol.safeCast<SymbolStruct>())
        {
            if (symbolStruct->isGenericInstance())
            {
                SmallVector<GenericInstanceKey> genericArgs;
                if (symbolStruct->tryGetGenericInstanceArgs(genericArgs))
                    collectModuleApiGenericArgDependencies(collector, genericArgs.span());
            }

            if (isModuleApiOpaqueType(*symbolStruct))
                return;

            for (const SymbolVariable* field : symbolStruct->fields())
            {
                if (field && !field->isIgnored() && field->typeRef().isValid())
                    collectModuleApiTypeRefDependencies(collector, field->typeRef());
            }

            return;
        }

        if (const auto* symbolFunction = symbol.safeCast<SymbolFunction>())
            collectModuleApiFunctionDependencies(collector, *symbolFunction);
    }

    std::unordered_map<const Symbol*, size_t> buildGeneratedRootTypeIndexMap(std::span<const ModuleApiGeneratedRoot> roots)
    {
        std::unordered_map<const Symbol*, size_t> result;
        for (size_t index = 0; index < roots.size(); ++index)
        {
            const Symbol* symbol = roots[index].symbol;
            if (symbol && isGeneratedModuleApiTypeSymbol(*symbol))
                result.emplace(symbol, index);
        }

        return result;
    }
}

namespace ModuleApi::Export
{
    void sortGeneratedModuleApiRoots(TaskContext& ctx, std::vector<ModuleApiGeneratedRoot>& roots)
    {
        if (roots.size() < 2)
            return;

        const std::unordered_map<const Symbol*, size_t> rootIndexByTypeSymbol = buildGeneratedRootTypeIndexMap(roots);
        std::vector<std::vector<size_t>>                dependencies;
        dependencies.resize(roots.size());

        for (size_t index = 0; index < roots.size(); ++index)
        {
            const Symbol* symbol = roots[index].symbol;
            if (!symbol)
                continue;

            ModuleApiDependencyCollector collector{.ctx = &ctx};
            collectModuleApiSymbolDependencies(collector, *symbol);
            for (const Symbol* dependencySymbol : collector.symbols)
            {
                const auto it = rootIndexByTypeSymbol.find(dependencySymbol);
                if (it != rootIndexByTypeSymbol.end() && it->second != index)
                    dependencies[index].push_back(it->second);
            }
        }

        std::vector<ModuleApiGeneratedRoot> sortedRoots;
        sortedRoots.reserve(roots.size());

        enum class VisitState : uint8_t
        {
            Unvisited,
            Visiting,
            Done,
        };

        std::vector visitStates(roots.size(), VisitState::Unvisited);
        auto        visitRoot = [&](auto&& self, const size_t index) -> void {
            switch (visitStates[index])
            {
                case VisitState::Done:
                case VisitState::Visiting:
                    return;

                default:
                    break;
            }

            visitStates[index] = VisitState::Visiting;
            for (const size_t dependencyIndex : dependencies[index])
                self(self, dependencyIndex);

            visitStates[index] = VisitState::Done;
            sortedRoots.push_back(std::move(roots[index]));
        };

        for (size_t index = 0; index < roots.size(); ++index)
            visitRoot(visitRoot, index);

        roots = std::move(sortedRoots);
    }
}

SWC_END_NAMESPACE();
