#include "pch.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Main/ModuleApi.h"

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

    const SymbolMap* namespaceOwnerSymMapForPublicSymbol(const Symbol& symbol)
    {
        const SymbolMap*  symMap  = symbol.ownerSymMap();
        const SymbolImpl* symImpl = nullptr;
        if (const auto* symbolFunction = symbol.safeCast<SymbolFunction>())
            symImpl = symbolFunction->declImplContext();
        else if (symMap && symMap->isImpl())
            symImpl = &symMap->cast<SymbolImpl>();

        if (symImpl)
        {
            if (symImpl->isForStruct() && symImpl->symStruct())
                symMap = symImpl->symStruct();
            else if (symImpl->isForEnum() && symImpl->symEnum())
                symMap = symImpl->symEnum();
            else if (symImpl->isForInterface() && symImpl->symInterface())
                symMap = symImpl->symInterface();
        }

        return symMap;
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

    bool extractPublicNamespacePath(const Symbol& symbol, std::vector<IdentifierRef>& outNamespacePath)
    {
        return extractNamespacePathFromOwner(namespaceOwnerSymMapForPublicSymbol(symbol), outNamespacePath);
    }
}

SWC_END_NAMESPACE();
