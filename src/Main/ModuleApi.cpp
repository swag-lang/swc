#include "pch.h"
#include "Main/ModuleApi.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isModuleApiDeclWrapper(const AstNode& node)
    {
        return node.is(AstNodeId::AccessModifier) ||
               node.is(AstNodeId::AttributeList) ||
               node.is(AstNodeId::VarDeclList);
    }

    bool isModuleApiForbiddenContainer(const AstNode& node)
    {
        return node.is(AstNodeId::FunctionDecl) ||
               node.is(AstNodeId::StructDecl) ||
               node.is(AstNodeId::EnumDecl) ||
               node.is(AstNodeId::InterfaceDecl) ||
               node.is(AstNodeId::Impl);
    }

    bool collectModuleApiNodePath(const Ast& ast, const AstNodeRef currentRef, const AstNodeRef targetRef, SmallVector<AstNodeRef>& ioPath)
    {
        if (!currentRef.isValid() || ast.isAdditionalNode(currentRef))
            return false;

        ioPath.push_back(currentRef);
        if (currentRef == targetRef)
            return true;

        SmallVector<AstNodeRef> childRefs;
        ast.node(currentRef).collectChildrenFromAst(childRefs, ast);
        for (const AstNodeRef childRef : childRefs)
        {
            if (collectModuleApiNodePath(ast, childRef, targetRef, ioPath))
                return true;
        }

        ioPath.pop_back();
        return false;
    }

    bool extractNamespacePathFromOwner(const SymbolMap* symMap, std::vector<IdentifierRef>& outNamespacePath)
    {
        outNamespacePath.clear();
        while (symMap)
        {
            if (symMap->isModule())
                break;

            if (symMap->isImpl() || symMap->isStruct() || symMap->isEnum() || symMap->isInterface())
            {
                symMap = symMap->ownerSymMap();
                continue;
            }

            if (!symMap->isNamespace())
                return false;

            const SymbolMap* ownerSymMap = symMap->ownerSymMap();
            if (ownerSymMap && ownerSymMap->isModule())
            {
                symMap = ownerSymMap;
                continue;
            }

            if (symMap->idRef().isValid())
                outNamespacePath.push_back(symMap->idRef());

            symMap = ownerSymMap;
        }

        std::ranges::reverse(outNamespacePath);
        return true;
    }

    bool isCurrentModuleSymbol(TaskContext& ctx, const Symbol& symbol)
    {
        const SourceFile* sourceFile = ctx.compiler().sourceViewFile(symbol);
        return sourceFile && ModuleApi::isCurrentModuleSourceFile(*sourceFile);
    }

    const SymbolImpl* implContextForPublicSymbol(const Symbol& symbol)
    {
        const SymbolMap* symMap = symbol.ownerSymMap();
        if (const auto* symbolFunction = symbol.safeCast<SymbolFunction>())
            return symbolFunction->declImplContext();

        if (symMap && symMap->isImpl())
            return &symMap->cast<SymbolImpl>();

        return nullptr;
    }

    const SymbolMap* implTargetSymMap(const SymbolImpl& symImpl)
    {
        if (symImpl.isForStruct())
            return symImpl.symStruct();
        if (symImpl.isForEnum())
            return symImpl.symEnum();
        if (symImpl.isForInterface())
            return symImpl.symInterface();
        return nullptr;
    }

    const SymbolMap* namespaceOwnerSymMapForPublicSymbol(TaskContext& ctx, const Symbol& symbol)
    {
        const SymbolMap*  symMap  = symbol.ownerSymMap();
        const SymbolImpl* symImpl = implContextForPublicSymbol(symbol);

        if (symImpl)
        {
            const SymbolMap* targetSymMap = implTargetSymMap(*symImpl);
            if (targetSymMap && isCurrentModuleSymbol(ctx, *targetSymMap))
                symMap = targetSymMap;
        }

        return symMap;
    }

    void appendNamespacePathTokens(TaskContext& ctx, const Ast& ast, SpanRef spanNameRef, IdentifierRef moduleNamespaceIdRef, std::vector<IdentifierRef>& outNamespacePath)
    {
        SmallVector<TokenRef> nameRefs;
        ast.appendTokens(nameRefs, spanNameRef);
        for (const TokenRef nameRef : nameRefs)
        {
            if (!nameRef.isValid())
                continue;

            const std::string_view name = ast.srcView().tokenString(nameRef);
            if (name.empty() || name == ".")
                continue;

            const IdentifierRef idRef = ctx.idMgr().addIdentifier(name);
            if (outNamespacePath.empty() && idRef == moduleNamespaceIdRef)
                continue;

            outNamespacePath.push_back(idRef);
        }
    }

    bool extractLexicalNamespacePath(TaskContext& ctx, const SourceFile& file, AstNodeRef declRef, std::vector<IdentifierRef>& outNamespacePath)
    {
        outNamespacePath.clear();
        const AstNodeRef rootRef = file.ast().root();
        if (rootRef.isInvalid())
            return false;

        SmallVector<AstNodeRef> nodePath;
        if (!collectModuleApiNodePath(file.ast(), rootRef, declRef, nodePath))
            return false;

        IdentifierRef moduleNamespaceIdRef = IdentifierRef::invalid();
        if (const SymbolNamespace* moduleNamespace = file.moduleNamespace())
            moduleNamespaceIdRef = moduleNamespace->idRef();

        const AstNode& rootNode = file.ast().node(rootRef);
        if (rootNode.is(AstNodeId::File))
        {
            SmallVector<AstNodeRef> globalRefs;
            file.ast().appendNodes(globalRefs, rootNode.cast<AstFile>().spanGlobalsRef);
            for (const AstNodeRef globalRef : globalRefs)
            {
                if (globalRef.isInvalid())
                    continue;

                const AstNode& globalNode = file.ast().node(globalRef);
                if (globalNode.isNot(AstNodeId::CompilerGlobal))
                    continue;

                const auto& global = globalNode.cast<AstCompilerGlobal>();
                if (global.mode == AstCompilerGlobal::Mode::Namespace)
                    appendNamespacePathTokens(ctx, file.ast(), global.spanNameRef, moduleNamespaceIdRef, outNamespacePath);
            }
        }

        for (const AstNodeRef nodeRef : nodePath)
        {
            const AstNode& node = file.ast().node(nodeRef);
            if (node.is(AstNodeId::NamespaceDecl))
                appendNamespacePathTokens(ctx, file.ast(), node.cast<AstNamespaceDecl>().spanNameRef, moduleNamespaceIdRef, outNamespacePath);
        }

        return true;
    }

    bool shouldUseLexicalNamespacePath(TaskContext& ctx, const Symbol& symbol)
    {
        const SymbolImpl* symImpl = implContextForPublicSymbol(symbol);
        if (!symImpl)
            return false;

        const SymbolMap* targetSymMap = implTargetSymMap(*symImpl);
        return targetSymMap && !isCurrentModuleSymbol(ctx, *targetSymMap);
    }

    bool isGeneratedSourceDecl(const SourceFile& file, const AstNodeRef declRef)
    {
        if (declRef.isInvalid() || !file.ast().hasSourceView())
            return false;

        const AstNode& node = file.ast().node(declRef);
        return node.srcViewRef().isValid() && node.srcViewRef() != file.ast().srcView().ref();
    }
}

namespace ModuleApi
{
    bool isCurrentModuleSourceFile(const SourceFile& sourceFile)
    {
        if (sourceFile.isImportedApi())
            return false;

        if (sourceFile.hasFlag(FileFlagsE::ModuleSrc))
            return true;

        return sourceFile.hasFlag(FileFlagsE::CustomSrc) && sourceFile.moduleNamespace() != nullptr;
    }
}

namespace ModuleApi::Internal
{
    bool tryFindNodeRef(const Ast& ast, const AstNode* targetNode, AstNodeRef& outNodeRef)
    {
        outNodeRef = AstNodeRef::invalid();
        if (!targetNode)
            return false;

        const AstNodeRef rootRef = ast.root();
        if (rootRef.isInvalid())
            return false;

        Ast::visit(ast, rootRef, [&](const AstNodeRef nodeRef, const AstNode& node) {
            if (&node != targetNode)
                return Ast::VisitResult::Continue;

            outNodeRef = nodeRef;
            return Ast::VisitResult::Stop;
        });

        return outNodeRef.isValid();
    }

    AstNodeRef findExportDeclRoot(const SourceFile& file, const AstNodeRef declRef)
    {
        const AstNodeRef rootRef = file.ast().root();
        if (rootRef.isInvalid())
            return AstNodeRef::invalid();
        if (isGeneratedSourceDecl(file, declRef))
            return declRef;

        SmallVector<AstNodeRef> nodePath;
        if (!collectModuleApiNodePath(file.ast(), rootRef, declRef, nodePath))
            return AstNodeRef::invalid();

        AstNodeRef exportRootRef = declRef;
        for (size_t i = nodePath.size(); i > 1; --i)
        {
            const AstNodeRef parentRef = nodePath[i - 2];
            const AstNode&   parent    = file.ast().node(parentRef);
            if (!isModuleApiDeclWrapper(parent))
                break;

            exportRootRef = parentRef;
        }

        return exportRootRef;
    }

    bool hasExplicitPublicAccessModifier(const SourceFile& file, const AstNodeRef declRef)
    {
        const AstNodeRef rootRef = file.ast().root();
        if (rootRef.isInvalid() || !file.ast().hasSourceView())
            return false;

        SmallVector<AstNodeRef> nodePath;
        if (!collectModuleApiNodePath(file.ast(), rootRef, declRef, nodePath))
            return false;

        for (size_t i = nodePath.size(); i > 1; --i)
        {
            const AstNodeRef parentRef = nodePath[i - 2];
            const AstNode&   parent    = file.ast().node(parentRef);
            if (!isModuleApiDeclWrapper(parent))
                break;

            if (parent.is(AstNodeId::AccessModifier) && parent.tokRef().isValid() && file.ast().srcView().token(parent.tokRef()).id == TokenId::KwdPublic)
                return true;
        }

        return false;
    }

    bool isExportedPublicDeclScope(const SourceFile& file, const AstNodeRef declRef, const Symbol& symbol)
    {
        const AstNodeRef rootRef = file.ast().root();
        if (rootRef.isInvalid())
            return false;
        if (isGeneratedSourceDecl(file, declRef))
            return true;

        SmallVector<AstNodeRef> nodePath;
        if (!collectModuleApiNodePath(file.ast(), rootRef, declRef, nodePath))
            return false;

        for (size_t i = 0; i + 1 < nodePath.size(); ++i)
        {
            const AstNode& node = file.ast().node(nodePath[i]);
            if (node.is(AstNodeId::Impl))
            {
                if (symbol.isFunction() || symbol.isConstant() || symbol.isAlias() || symbol.isStruct() || symbol.isEnum() || symbol.isInterface())
                    continue;
                return false;
            }

            if (isModuleApiForbiddenContainer(node))
                return false;
        }

        return true;
    }

    bool extractPublicNamespacePath(TaskContext& ctx, const SourceFile& file, AstNodeRef declRef, const Symbol& symbol, std::vector<IdentifierRef>& outNamespacePath)
    {
        if (shouldUseLexicalNamespacePath(ctx, symbol))
        {
            if (extractLexicalNamespacePath(ctx, file, declRef, outNamespacePath))
                return true;
        }

        return extractNamespacePathFromOwner(namespaceOwnerSymMapForPublicSymbol(ctx, symbol), outNamespacePath);
    }
}

SWC_END_NAMESPACE();
