#include "pch.h"
#include "Doc/DocApi.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/ModuleApi/ModuleApi.Source.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/AttributeList.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

Utf8 DocApi::displayNameFor(const std::string_view fullName, const DocItemKind kind)
{
    if (kind == DocItemKind::Namespace)
        return fullName;

    const size_t last = fullName.rfind('.');
    if (last == std::string_view::npos)
        return fullName;
    const size_t previous = last ? fullName.rfind('.', last - 1) : std::string_view::npos;
    if (previous == std::string_view::npos)
        return fullName;
    return fullName.substr(previous + 1);
}

namespace
{
    bool alphabeticLess(const std::string_view lhs, const std::string_view rhs)
    {
        const size_t size = std::min(lhs.size(), rhs.size());
        for (size_t i = 0; i < size; ++i)
        {
            const int left  = std::tolower(static_cast<unsigned char>(lhs[i]));
            const int right = std::tolower(static_cast<unsigned char>(rhs[i]));
            if (left != right)
                return left < right;
        }
        if (lhs.size() != rhs.size())
            return lhs.size() < rhs.size();
        return lhs < rhs;
    }

    int itemSortOrder(const DocItemKind kind)
    {
        return static_cast<int>(kind);
    }
}

std::optional<DocItemKind> DocApi::itemKind(const Symbol& symbol)
{
    if (symbol.isNamespace())
        return DocItemKind::Namespace;
    if (symbol.isStruct())
        return DocItemKind::Struct;
    if (symbol.isInterface())
        return DocItemKind::Interface;
    if (symbol.isEnum())
        return DocItemKind::Enum;
    if (symbol.isConstant())
        return DocItemKind::Constant;
    if (symbol.isAlias())
        return DocItemKind::Alias;
    if (const auto* function = symbol.safeCast<SymbolFunction>())
        return function->isAttribute() ? DocItemKind::Attribute : DocItemKind::Function;
    return std::nullopt;
}

bool DocApi::hasNoDocAttribute(const Symbol& symbol)
{
    const Symbol* scan = &symbol;
    while (scan)
    {
        if (scan->hasAttributes() && scan->attributes().hasRtFlag(RtAttributeFlagsE::NoDoc))
            return true;
        scan = scan->ownerSymMap();
    }
    return false;
}

namespace
{
    bool hasPublicAggregateOwner(const Symbol& symbol)
    {
        const SymbolMap* owner = symbol.ownerSymMap();
        while (owner)
        {
            if ((owner->isStruct() || owner->isInterface() || owner->isEnum()) && !owner->isPublic())
                return false;
            owner = owner->ownerSymMap();
        }
        return true;
    }

    bool isDocumentationSymbol(const CompilerInstance& compiler, const Symbol& symbol, const bool runtime)
    {
        if (symbol.isIgnored() || !symbol.decl() || !symbol.tokRef().isValid() || !symbol.idRef().isValid())
            return false;
        if (!DocApi::itemKind(symbol).has_value() || DocApi::hasNoDocAttribute(symbol))
            return false;

        const SourceFile* file = compiler.sourceViewFile(symbol);
        if (!file)
            return false;
        if (runtime)
            return file->isRuntime();
        if (!ModuleApi::isCurrentModuleSourceFile(*file))
            return false;
        return symbol.isPublic() && hasPublicAggregateOwner(symbol);
    }
}

bool DocApi::isAnonymousAggregateSymbol(const Symbol& symbol)
{
    const auto* symbolStruct = symbol.safeCast<SymbolStruct>();
    if (!symbolStruct || !symbolStruct->decl())
        return false;

    return symbolStruct->decl()->is(AstNodeId::AnonymousStructDecl) ||
           symbolStruct->decl()->is(AstNodeId::AnonymousUnionDecl);
}

bool DocApi::hasCompilerGeneratedIdentifier(const TaskContext& ctx, const Symbol& symbol)
{
    // Source identifiers cannot use the reserved "__" prefix. Sema uses it for
    // unique anonymous aggregates, lambdas, inline temporaries, and other helpers.
    return symbol.idRef().isValid() && symbol.name(ctx).starts_with("__");
}

bool DocApi::isInCompilerGeneratedScope(const TaskContext& ctx, const Symbol& symbol)
{
    // A declaration nested in a reserved scope is implementation state whatever its own
    // spelling, so the whole subtree stays out of the page.
    const Symbol* scan = &symbol;
    while (scan)
    {
        if (hasCompilerGeneratedIdentifier(ctx, *scan))
            return true;
        scan = scan->ownerSymMap();
    }
    return false;
}

namespace
{
    bool commentStartsOnItsOwnLine(const SourceView& srcView, const Token& token)
    {
        const std::string_view source = srcView.stringView();
        size_t                 offset = std::min<size_t>(token.byteStart, source.size());
        while (offset && source[offset - 1] != '\r' && source[offset - 1] != '\n')
        {
            if (!std::isspace(static_cast<unsigned char>(source[offset - 1])))
                return false;
            offset--;
        }
        return true;
    }
}

void DocApi::appendNormalizedComment(std::vector<Utf8>& outLines, std::string_view text)
{
    if (text.starts_with("//"))
    {
        text.remove_prefix(2);
        if (!text.empty() && text.front() == ' ')
            text.remove_prefix(1);
        outLines.emplace_back(text);
        return;
    }

    if (text.starts_with("/*"))
        text.remove_prefix(2);
    if (text.ends_with("*/"))
        text.remove_suffix(2);

    std::vector<Utf8> lines = Utf8Helper::splitLines(text);
    for (Utf8& line : lines)
    {
        std::string_view view = line;
        while (!view.empty() && (view.front() == ' ' || view.front() == '\t'))
            view.remove_prefix(1);
        if (!view.empty() && view.front() == '*')
        {
            view.remove_prefix(1);
            if (!view.empty() && view.front() == ' ')
                view.remove_prefix(1);
        }
        outLines.emplace_back(view);
    }

    while (!outLines.empty() && Utf8Helper::trim(outLines.front()).empty())
        outLines.erase(outLines.begin());
    while (!outLines.empty() && Utf8Helper::trim(outLines.back()).empty())
        outLines.pop_back();
}

namespace
{
    bool collectLeadingCommentTrivia(std::vector<Utf8>& result, const SourceView& srcView, const TokenRef tokenRef)
    {
        if (!tokenRef.isValid() || tokenRef.get() >= srcView.numTokens() || tokenRef.get() + 1 >= srcView.triviaStart().size())
            return false;

        result.clear();
        const auto [triviaStart, triviaEnd] = srcView.triviaRangeForToken(tokenRef);
        bool hasComment                     = false;
        for (uint32_t i = triviaStart; i < triviaEnd; ++i)
        {
            const SourceTrivia& trivia = srcView.trivia()[i];
            if (trivia.tok.id == TokenId::Whitespace)
            {
                if (Utf8Helper::countLineBreaks(trivia.tok.string(srcView)) >= 2)
                {
                    result.clear();
                    hasComment = false;
                }
                continue;
            }

            if (trivia.tok.id != TokenId::CommentLine && trivia.tok.id != TokenId::CommentBlock)
                continue;
            if (!commentStartsOnItsOwnLine(srcView, trivia.tok))
            {
                result.clear();
                hasComment = false;
                continue;
            }

            DocApi::appendNormalizedComment(result, trivia.tok.string(srcView));
            hasComment = true;
        }

        if (!hasComment)
            result.clear();
        return hasComment;
    }

    std::vector<Utf8> leadingCommentLines(TaskContext& ctx, const SourceFile& file, const AstNodeRef rootRef)
    {
        std::vector<Utf8> result;
        const Ast&        ast = file.ast();
        if (rootRef.isInvalid() || !ast.hasNode(rootRef))
            return result;

        const AstNode&    rootNode   = ast.node(rootRef);
        const SourceView& srcView    = ModuleApi::moduleApiNodeSourceView(ctx, ast, rootRef);
        const TokenRef    startToken = ModuleApi::moduleApiSnippetStartTokRef(ast, rootNode);
        if (!startToken.isValid() || startToken.get() >= srcView.numTokens() || startToken.get() + 1 >= srcView.triviaStart().size())
            return result;

        collectLeadingCommentTrivia(result, srcView, startToken);
        return result;
    }

    std::vector<Utf8> trailingCommentLines(TaskContext& ctx, const SourceFile& file, const AstNodeRef declRef)
    {
        std::vector<Utf8> result;
        const Ast&        ast = file.ast();
        if (declRef.isInvalid() || !ast.hasNode(declRef))
            return result;

        const AstNode& node      = ast.node(declRef);
        const TokenRef endTokRef = node.tokRefEnd(ast);
        if (!endTokRef.isValid())
            return result;

        const SourceView& srcView = ModuleApi::moduleApiNodeSourceView(ctx, ast, declRef);
        if (endTokRef.get() >= srcView.numTokens())
            return result;

        const Token&           token  = srcView.token(endTokRef);
        const std::string_view source = srcView.stringView();
        const size_t           start  = std::min<size_t>(ModuleApi::sourceTokenByteEnd(srcView, token), source.size());
        size_t                 end    = source.find_first_of("\r\n", start);
        if (end == std::string_view::npos)
            end = source.size();

        const std::string_view suffix = source.substr(start, end - start);
        const size_t           line   = suffix.find("//");
        const size_t           block  = suffix.find("/*");
        size_t                 commentPos;
        if (line == std::string_view::npos)
            commentPos = block;
        else if (block == std::string_view::npos)
            commentPos = line;
        else
            commentPos = std::min(line, block);
        if (commentPos == std::string_view::npos)
            return result;

        DocApi::appendNormalizedComment(result, suffix.substr(commentPos));
        return result;
    }
}

std::vector<Utf8> DocApi::symbolCommentLines(TaskContext& ctx, const Symbol& symbol, const SourceFile& file, const AstNodeRef declRef, const AstNodeRef rootRef)
{
    std::vector<Utf8> result;
    if (symbol.isConstant() || symbol.isAlias() || symbol.isVariable() || symbol.isEnumValue())
        result = trailingCommentLines(ctx, file, declRef);
    if (result.empty())
        result = leadingCommentLines(ctx, file, rootRef);
    if (result.empty() && declRef != rootRef)
        result = leadingCommentLines(ctx, file, declRef);
    return result;
}

namespace
{
    AstNodeRef declarationBodyRef(const AstNode& node)
    {
        if (const auto* function = node.safeCast<AstFunctionDecl>())
            return function->nodeBodyRef;
        if (const auto* structDecl = node.safeCast<AstStructDecl>())
            return structDecl->nodeBodyRef;
        if (const auto* unionDecl = node.safeCast<AstUnionDecl>())
            return unionDecl->nodeBodyRef;
        if (const auto* interfaceDecl = node.safeCast<AstInterfaceDecl>())
            return interfaceDecl->nodeBodyRef;
        if (const auto* enumDecl = node.safeCast<AstEnumDecl>())
            return enumDecl->nodeBodyRef;
        return AstNodeRef::invalid();
    }

    Utf8 buildDisplaySignature(TaskContext& ctx, const SourceFile& file, const AstNodeRef declRef, const AstNodeRef rootRef)
    {
        const Ast& ast = file.ast();
        if (declRef.isInvalid() || rootRef.isInvalid() || !ast.hasNode(declRef) || !ast.hasNode(rootRef))
            return {};

        uint32_t startOffset = 0;
        uint32_t endOffset   = 0;
        if (!ModuleApi::tryGetModuleApiSnippetOffsets(ctx, file, rootRef, startOffset, endOffset))
            return {};

        const SourceView& srcView = ModuleApi::moduleApiNodeSourceView(ctx, ast, rootRef);
        const AstNodeRef  bodyRef = declarationBodyRef(ast.node(declRef));
        if (bodyRef.isValid() && ast.hasNode(bodyRef))
        {
            const AstNode& bodyNode = ast.node(bodyRef);
            if (bodyNode.tokRef().isValid())
            {
                const SourceView& bodyView = ModuleApi::moduleApiNodeSourceView(ctx, ast, bodyRef);
                if (&bodyView == &srcView)
                    endOffset = ModuleApi::sourceTokenByteStart(srcView, srcView.token(bodyNode.tokRef()));
            }
        }

        const std::string_view source = srcView.stringView();
        startOffset                   = std::min<uint32_t>(startOffset, static_cast<uint32_t>(source.size()));
        endOffset                     = std::min<uint32_t>(endOffset, static_cast<uint32_t>(source.size()));
        while (endOffset > startOffset && std::isspace(static_cast<unsigned char>(source[endOffset - 1])))
            endOffset--;
        if (startOffset >= endOffset)
            return {};

        Utf8 result = ModuleApi::buildSanitizedModuleApiSnippet(ctx, file, rootRef, startOffset, source.substr(startOffset, endOffset - startOffset), "\n");
        result.trim();
        return result;
    }

    Utf8 sourceCategory(const CompilerInstance& compiler, const SourceFile& file, const bool runtime)
    {
        if (runtime || compiler.cmdLine().modulePath.empty())
            return {};

        const fs::path  sourceRoot = (compiler.cmdLine().modulePath / "src").lexically_normal();
        std::error_code ec;
        const fs::path  relative = fs::relative(file.path().parent_path(), sourceRoot, ec);
        if (ec || relative.empty() || relative == ".")
            return {};

        std::string value = relative.generic_string();
        if (value.starts_with(".."))
            return {};
        return value;
    }

    bool isRestrictedField(const Symbol& symbol)
    {
        const auto* symVar = symbol.safeCast<SymbolVariable>();
        if (!symVar)
            return false;
        const MemberAccess access = symVar->memberAccess();
        return access == MemberAccess::Internal || access == MemberAccess::Private;
    }

    bool canDocumentMember(const CompilerInstance& compiler, const Symbol& symbol, const bool runtime)
    {
        if (symbol.isIgnored() || DocApi::hasNoDocAttribute(symbol) || !symbol.decl() || !symbol.tokRef().isValid())
            return false;
        if (isRestrictedField(symbol))
            return false;
        const SourceFile* file = compiler.sourceViewFile(symbol);
        if (!file)
            return false;
        if (runtime)
            return file->isRuntime();
        return ModuleApi::isCurrentModuleSourceFile(*file) && (symbol.isPublic() || symbol.isEnumValue());
    }

    std::vector<Utf8> sameLineCommentLines(const SourceCodeRange& range)
    {
        std::vector<Utf8> result;
        if (!range.srcView)
            return result;

        const std::string_view source = range.srcView->stringView();
        const size_t           start  = std::min<size_t>(range.offset + range.len, source.size());
        size_t                 end    = source.find_first_of("\r\n", start);
        if (end == std::string_view::npos)
            end = source.size();

        const std::string_view suffix = source.substr(start, end - start);
        const size_t           line   = suffix.find("//");
        const size_t           block  = suffix.find("/*");
        size_t                 commentPos;
        if (line == std::string_view::npos)
            commentPos = block;
        else if (block == std::string_view::npos)
            commentPos = line;
        else
            commentPos = std::min(line, block);
        if (commentPos != std::string_view::npos)
            DocApi::appendNormalizedComment(result, suffix.substr(commentPos));
        return result;
    }

    std::vector<Utf8> memberCommentLines(TaskContext& ctx, const Symbol& symbol)
    {
        const SourceFile* file = ctx.compiler().ownerSourceFile(symbol.srcViewRef());
        if (!file)
            file = ctx.compiler().sourceViewFile(symbol);
        if (!file)
            return {};

        AstNodeRef declRef;
        if (!ModuleApi::tryFindReachableNodeRef(file->ast(), symbol.decl(), declRef))
        {
            if (file->ast().hasSourceView() && symbol.srcViewRef() != file->ast().srcView().ref())
                declRef = file->ast().tryFindNodeRef(symbol.decl());
            if (declRef.isInvalid())
                return {};
        }

        const AstNodeRef  rootRef = ModuleApi::findExportDeclRoot(*file, declRef);
        std::vector<Utf8> result  = DocApi::symbolCommentLines(ctx, symbol, *file, declRef, rootRef);
        if (!result.empty())
            return result;

        // A `using name: union` member is represented by its anonymous aggregate declaration,
        // whose AST end token is not the member name. The physical name line still carries an
        // ordinary trailing field comment.
        return sameLineCommentLines(symbol.codeRange(ctx));
    }

    Utf8 sourceTypeName(TaskContext& ctx, const SourceFile& file, const AstNodeRef typeRef)
    {
        if (typeRef.isInvalid() || !file.ast().hasNode(typeRef))
            return {};

        const AstNode& typeNode = file.ast().node(typeRef);
        if (typeNode.is(AstNodeId::AnonymousStructDecl))
            return "struct { ... }";
        if (typeNode.is(AstNodeId::AnonymousUnionDecl))
            return "union { ... }";

        std::string_view source;
        if (!ModuleApi::tryGetModuleApiSnippet(ctx, file, typeRef, source))
            return {};
        Utf8 result(source);
        result.trim();
        return result;
    }

    bool hasSourceNoDocAttribute(TaskContext& ctx, const SourceFile& file, const AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid() || !file.ast().hasNode(nodeRef) || !file.ast().node(nodeRef).is(AstNodeId::AttributeList))
            return false;

        std::string_view source;
        if (!ModuleApi::tryGetModuleApiSnippet(ctx, file, nodeRef, source))
            return false;
        const size_t attributesEnd = source.find(']');
        return attributesEnd != std::string_view::npos && source.substr(0, attributesEnd).find("Swag.NoDoc") != std::string_view::npos;
    }

    bool hasSourceNoDocAttribute(TaskContext& ctx, const Symbol& symbol)
    {
        const SourceFile* file = ctx.compiler().ownerSourceFile(symbol.srcViewRef());
        if (!file)
            file = ctx.compiler().sourceViewFile(symbol);
        if (!file)
            return false;

        AstNodeRef declRef;
        if (!ModuleApi::tryFindReachableNodeRef(file->ast(), symbol.decl(), declRef))
        {
            if (file->ast().hasSourceView() && symbol.srcViewRef() != file->ast().srcView().ref())
                declRef = file->ast().tryFindNodeRef(symbol.decl());
            if (declRef.isInvalid())
                return false;
        }
        return hasSourceNoDocAttribute(ctx, *file, ModuleApi::findExportDeclRoot(*file, declRef));
    }

    // 'rootRef' is the outermost wrapper the declaration sits in — its access modifier, its
    // attribute list — which is where a leading documentation comment is written.
    void appendGenericMember(TaskContext& ctx, DocItem& item, const SourceFile& file, const AstNodeRef declRef, const AstNodeRef rootRef, const AstVarDeclBase& declaration, const TokenRef nameRef, std::unordered_set<Utf8>& seenNames)
    {
        if (!nameRef.isValid())
            return;

        const Ast&        ast     = file.ast();
        const SourceView& srcView = ModuleApi::moduleApiNodeSourceView(ctx, ast, declRef);
        if (nameRef.get() >= srcView.numTokens())
            return;

        Utf8 name = srcView.token(nameRef).string(srcView);
        if (name.empty() || !seenNames.insert(name).second)
            return;

        DocMember member;
        member.name     = std::move(name);
        member.fullName = item.fullName;
        member.fullName += ".";
        member.fullName += member.name;
        member.typeName = sourceTypeName(ctx, file, declaration.nodeTypeRef);

        member.commentLines = trailingCommentLines(ctx, file, declRef);
        if (member.commentLines.empty())
            member.commentLines = leadingCommentLines(ctx, file, rootRef);
        if (member.commentLines.empty() && rootRef != declRef)
            member.commentLines = leadingCommentLines(ctx, file, declRef);
        if (member.commentLines.empty())
        {
            const SourceCodeRange nameRange = srcView.token(nameRef).codeRange(ctx, srcView);
            member.commentLines             = sameLineCommentLines(nameRange);
        }
        item.members.push_back(std::move(member));
    }

    void collectGenericMemberNode(TaskContext& ctx, DocItem& item, const SourceFile& file, const AstNodeRef nodeRef, const bool restricted, const AstNodeRef rootRef, std::unordered_set<Utf8>& seenNames)
    {
        const Ast& ast = file.ast();
        if (nodeRef.isInvalid() || !ast.hasNode(nodeRef))
            return;

        // The outermost wrapper is what a leading comment is written above, so it is kept as the
        // members' comment root once the walk enters one.
        const AstNodeRef childRootRef = rootRef.isValid() ? rootRef : nodeRef;

        const AstNode& node = ast.node(nodeRef);
        if (const auto* access = node.safeCast<AstAccessModifier>())
        {
            const SourceView& srcView = ModuleApi::moduleApiNodeSourceView(ctx, ast, nodeRef);
            const TokenId     tokenId = srcView.token(node.tokRef()).id;

            // 'readonly' alone names no level, so it leaves in place the one already in effect.
            bool childRestricted = restricted;
            if (tokenId == TokenId::KwdPublic)
                childRestricted = false;
            else if (tokenId == TokenId::KwdInternal || tokenId == TokenId::KwdPrivate)
                childRestricted = true;

            collectGenericMemberNode(ctx, item, file, access->nodeWhatRef, childRestricted, childRootRef, seenNames);
            return;
        }

        if (const auto* attributes = node.safeCast<AstAttributeList>())
        {
            if (hasSourceNoDocAttribute(ctx, file, nodeRef))
                return;
            collectGenericMemberNode(ctx, item, file, attributes->nodeBodyRef, restricted, childRootRef, seenNames);
            return;
        }

        if (node.is(AstNodeId::VarDeclList))
        {
            SmallVector<AstNodeRef> children;
            node.collectChildrenFromAst(children, ast);
            for (const AstNodeRef childRef : children)
                collectGenericMemberNode(ctx, item, file, childRef, restricted, childRootRef, seenNames);
            return;
        }

        if (node.is(AstNodeId::AggregateBody))
        {
            SmallVector<AstNodeRef> children;
            node.collectChildrenFromAst(children, ast);
            for (const AstNodeRef childRef : children)
                collectGenericMemberNode(ctx, item, file, childRef, restricted, AstNodeRef::invalid(), seenNames);
            return;
        }

        if (restricted)
            return;
        if (const auto* single = node.safeCast<AstSingleVarDecl>())
        {
            if (single->hasFlag(AstVarDeclFlagsE::Const))
                return;
            appendGenericMember(ctx, item, file, nodeRef, childRootRef, *single, single->tokNameRef, seenNames);
            return;
        }
        if (const auto* multiple = node.safeCast<AstMultiVarDecl>())
        {
            if (multiple->hasFlag(AstVarDeclFlagsE::Const))
                return;
            SmallVector<TokenRef> names;
            ast.appendTokens(names, multiple->spanNamesRef);
            for (const TokenRef nameRef : names)
                appendGenericMember(ctx, item, file, nodeRef, childRootRef, *multiple, nameRef, seenNames);
        }
    }

    void collectItemMembers(TaskContext& ctx, DocItem& item, const bool runtime)
    {
        if (item.overloads.empty() || !item.overloads.front().symbol)
            return;

        const Symbol& owner = *item.overloads.front().symbol;
        if (!owner.isSymMap() || (owner.isStruct() && ModuleApi::isModuleApiOpaqueType(owner)))
            return;

        std::unordered_set<Utf8>   seenNames;
        std::vector<const Symbol*> members;
        owner.asSymMap()->getAllSymbols(members);
        for (const Symbol* member : members)
        {
            if (!member || !canDocumentMember(ctx.compiler(), *member, runtime))
                continue;
            if (!((owner.isEnum() && member->isEnumValue()) ||
                  ((owner.isStruct() || owner.isInterface()) && (member->isVariable() || member->isConstant()))))
                continue;

            DocMember row;
            row.symbol       = member;
            row.name         = Utf8(member->name(ctx));
            row.fullName     = member->getFullScopedName(ctx);
            row.commentLines = memberCommentLines(ctx, *member);
            if (row.name.empty() || row.fullName.empty() || !seenNames.insert(row.name).second)
                continue;
            item.members.push_back(std::move(row));
        }

        const auto* ownerStruct = owner.safeCast<SymbolStruct>();
        if (ownerStruct && ownerStruct->isGenericRoot() && !ownerStruct->isGenericInstance())
        {
            const SourceFile* file = item.overloads.front().file;
            AstNodeRef        declRef;
            if (file && ModuleApi::tryFindReachableNodeRef(file->ast(), owner.decl(), declRef))
            {
                const AstNodeRef bodyRef = declarationBodyRef(file->ast().node(declRef));
                if (bodyRef.isValid() && file->ast().hasNode(bodyRef))
                {
                    SmallVector<AstNodeRef> children;
                    file->ast().node(bodyRef).collectChildrenFromAst(children, file->ast());
                    // A member is 'internal' unless it says otherwise, so the walk starts closed.
                    for (const AstNodeRef childRef : children)
                        collectGenericMemberNode(ctx, item, *file, childRef, true, AstNodeRef::invalid(), seenNames);
                }
            }
        }

        std::ranges::sort(item.members, [](const DocMember& lhs, const DocMember& rhs) {
            if (lhs.name != rhs.name)
                return alphabeticLess(lhs.name, rhs.name);
            return alphabeticLess(lhs.fullName, rhs.fullName);
        });
    }
}

void DocApi::collectSymbolTree(std::vector<const Symbol*>& outSymbols, std::unordered_set<const Symbol*>& seen, const SymbolMap& symbolMap)
{
    std::vector<const Symbol*> symbols;
    symbolMap.getAllSymbols(symbols);
    for (const Symbol* symbol : symbols)
    {
        if (!symbol || !seen.insert(symbol).second)
            continue;
        outSymbols.push_back(symbol);
        if (symbol->isSymMap())
            collectSymbolTree(outSymbols, seen, *symbol->asSymMap());
    }
}

namespace
{
    const Symbol* documentationImplOwner(const SymbolImpl& impl)
    {
        if (impl.isForStruct())
            return impl.symStruct();
        if (impl.isForEnum())
            return impl.symEnum();
        if (impl.isForInterface())
            return impl.symInterface();
        return nullptr;
    }

    const Symbol* documentationOwner(const Symbol& symbol)
    {
        if (const auto* function = symbol.safeCast<SymbolFunction>())
        {
            if (const SymbolStruct* owner = function->ownerStruct())
                return owner;
        }

        const SymbolMap* owner = symbol.ownerSymMap();
        while (owner)
        {
            if (owner->isStruct() || owner->isInterface() || owner->isEnum())
                return owner;
            if (owner->isImpl())
            {
                if (const Symbol* result = documentationImplOwner(owner->cast<SymbolImpl>()))
                    return result;
            }
            owner = owner->ownerSymMap();
        }
        return nullptr;
    }

    Utf8 documentationNamespace(const TaskContext& ctx, const Symbol& symbol, const Symbol* owner)
    {
        const Symbol*    scopedSymbol = owner ? owner : &symbol;
        const SymbolMap* scope        = scopedSymbol->ownerSymMap();
        while (scope)
        {
            if (scope->isNamespace())
                return scope->getFullScopedName(ctx);
            scope = scope->ownerSymMap();
        }
        return {};
    }
}

void DocApi::collectDocItems(TaskContext& ctx, std::vector<DocItem>& outItems, const bool runtime)
{
    CompilerInstance&                             compiler = ctx.compiler();
    std::vector<const Symbol*>                    symbols;
    std::unordered_set<const Symbol*>             seen;
    std::unordered_map<const Symbol*, AstNodeRef> publicRootRefs;
    if (runtime)
    {
        if (compiler.symModule())
            collectSymbolTree(symbols, seen, *compiler.symModule());
        if (compiler.importRootNamespace())
            collectSymbolTree(symbols, seen, *compiler.importRootNamespace());
    }
    else
    {
        ModuleApiFileEntries        fallbackPublicEntries;
        const ModuleApiFileEntries* publicEntries = compiler.moduleApiPublicEntries();
        if (!publicEntries)
        {
            if (ModuleApi::collectPublicEntries(ctx, fallbackPublicEntries) != Result::Continue)
                return;
            publicEntries = &fallbackPublicEntries;
        }

        for (const ModuleApiFileEntry& fileEntry : *publicEntries | std::views::values)
        {
            for (const ModuleApiPublicEntry& entry : fileEntry.publicEntries)
            {
                if (!entry.symbol || !seen.insert(entry.symbol).second)
                    continue;

                symbols.push_back(entry.symbol);
                publicRootRefs.emplace(entry.symbol, entry.rootRef);

                // Nested types and interface methods are exported through their
                // aggregate root rather than as independent module API entries.
                // Collect the public symbol tree so each of them still receives
                // its own canonical, top-level documentation section.
                if (entry.symbol->isSymMap())
                {
                    std::vector<const Symbol*>        members;
                    std::unordered_set<const Symbol*> nestedSeen;
                    collectSymbolTree(members, nestedSeen, *entry.symbol->asSymMap());
                    for (const Symbol* member : members)
                    {
                        if (!member || !isDocumentationSymbol(compiler, *member, false) || !seen.insert(member).second)
                            continue;
                        symbols.push_back(member);
                    }
                }

                // A generic root does not run the semantic pass for its body, so methods
                // declared by its impl blocks are attached to the root rather than published
                // in its symbol map. They still describe the generic API itself.
                const auto* genericStruct = entry.symbol->safeCast<SymbolStruct>();
                if (genericStruct && genericStruct->isGenericRoot() && !genericStruct->isGenericInstance())
                {
                    for (const SymbolFunction* method : genericStruct->declaredMethods())
                    {
                        if (!method || !isDocumentationSymbol(compiler, *method, false) || hasSourceNoDocAttribute(ctx, *method) || !seen.insert(method).second)
                            continue;
                        symbols.push_back(method);
                    }
                }
            }
        }
    }

    struct DocItemCandidate
    {
        const SourceFile* file = nullptr;
        DocItemKind       kind = DocItemKind::Function;
        Utf8              fullName;
        Utf8              ownerName;
        Utf8              namespaceName;
        DocOverload       overload;
        bool              valid = false;
    };

    // Sema is complete, so every candidate can be derived independently. The indexed slots
    // keep the subsequent merge in the original symbol order and preserve deterministic HTML.
    std::vector<DocItemCandidate> candidates(symbols.size());
    const auto&                   resolvedPublicRootRefs = publicRootRefs;
    JobManager&                   jobMgr                 = ctx.global().jobMgr();
    jobMgr.parallelForIndexed(ctx, static_cast<uint32_t>(symbols.size()), JobKind::ModuleApiExport, compiler.jobClientId(), [&](TaskContext& workerCtx, const uint32_t index) {
        const Symbol* symbol = symbols[index];
        if (!symbol || hasNoDocAttribute(*symbol))
            return;
        const std::optional<DocItemKind> kind = itemKind(*symbol);
        if (!kind.has_value())
            return;
        if (runtime && !isDocumentationSymbol(compiler, *symbol, true))
            return;
        if (isAnonymousAggregateSymbol(*symbol) || isInCompilerGeneratedScope(workerCtx, *symbol))
            return;
        if (const auto* function = symbol->safeCast<SymbolFunction>())
        {
            const SymbolImpl* impl = function->declImplContext();
            if (impl && impl->isForInterface())
                return;
        }

        const SourceFile* file = compiler.ownerSourceFile(symbol->srcViewRef());
        if (!file)
            file = compiler.sourceViewFile(*symbol);
        if (!file)
            return;

        AstNodeRef declRef;
        if (!ModuleApi::tryFindReachableNodeRef(file->ast(), symbol->decl(), declRef))
        {
            if (file->ast().hasSourceView() && symbol->srcViewRef() != file->ast().srcView().ref())
                declRef = file->ast().tryFindNodeRef(symbol->decl());
        }
        if (declRef.isInvalid() || ModuleApi::isGeneratedSourceDecl(*file, declRef))
            return;

        AstNodeRef rootRef = ModuleApi::findExportDeclRoot(*file, declRef);
        if (!runtime)
        {
            const auto it = resolvedPublicRootRefs.find(symbol);
            if (it != resolvedPublicRootRefs.end())
                rootRef = it->second;
        }
        if (rootRef.isInvalid())
            return;

        Utf8 fullName = symbol->getFullScopedName(workerCtx);
        if (fullName.empty())
            return;

        // A method declared in an 'impl' block is scoped by its type alone, while the
        // same symbol seen from an importing module carries the whole path. Qualifying it
        // here keeps one spelling, so a cross-module link reaches the anchor it names.
        const Symbol* owner = documentationOwner(*symbol);
        Utf8          ownerName;
        if (owner)
        {
            ownerName = owner->getFullScopedName(workerCtx);
            if (!ownerName.empty())
            {
                Utf8 qualified = ownerName;
                qualified += ".";
                if (!fullName.starts_with(qualified.view()))
                {
                    const size_t lastPart = fullName.view().rfind('.');
                    qualified.append(lastPart == std::string_view::npos ? fullName.view() : fullName.view().substr(lastPart + 1));
                    fullName = std::move(qualified);
                }
            }
        }

        DocItemCandidate& candidate     = candidates[index];
        candidate.file                  = file;
        candidate.kind                  = *kind;
        candidate.fullName              = std::move(fullName);
        candidate.ownerName             = std::move(ownerName);
        candidate.namespaceName         = documentationNamespace(workerCtx, *symbol, owner);
        candidate.overload.symbol       = symbol;
        candidate.overload.file         = file;
        candidate.overload.signature    = buildDisplaySignature(workerCtx, *file, declRef, rootRef);
        candidate.overload.commentLines = symbolCommentLines(workerCtx, *symbol, *file, declRef, rootRef);
        candidate.overload.sourceLine   = symbol->codeRange(workerCtx).line + 1;
        candidate.valid                 = true;
    });

    std::unordered_map<Utf8, size_t>            itemIndices;
    std::unordered_set<Utf8>                    overloadKeys;
    std::unordered_map<const SourceFile*, Utf8> sourceCategories;
    for (DocItemCandidate& candidate : candidates)
    {
        if (!candidate.valid)
            continue;

        Utf8 itemKey;
        itemKey.append(std::to_string(itemSortOrder(candidate.kind)));
        itemKey += ":";
        itemKey += candidate.fullName;

        Utf8 overloadKey = itemKey;
        overloadKey += "\n";
        overloadKey += candidate.overload.signature;
        overloadKey += "\n";
        overloadKey.append(candidate.file->path().generic_string());
        overloadKey += ":";
        overloadKey.append(std::to_string(candidate.overload.sourceLine));
        if (!overloadKeys.insert(overloadKey).second)
            continue;

        const auto [it, inserted] = itemIndices.emplace(itemKey, outItems.size());
        if (inserted)
        {
            const auto [categoryIt, categoryInserted] = sourceCategories.try_emplace(candidate.file);
            if (categoryInserted)
                categoryIt->second = sourceCategory(compiler, *candidate.file, runtime);

            DocItem item;
            item.kind          = candidate.kind;
            item.fullName      = candidate.fullName;
            item.displayName   = displayNameFor(candidate.fullName, candidate.kind);
            item.category      = categoryIt->second;
            item.ownerName     = candidate.ownerName;
            item.namespaceName = candidate.namespaceName;
            outItems.push_back(std::move(item));
        }
        outItems[it->second].overloads.push_back(std::move(candidate.overload));
    }

    for (DocItem& item : outItems)
    {
        std::ranges::sort(item.overloads, [](const DocOverload& lhs, const DocOverload& rhs) {
            const std::string lhsPath = lhs.file ? lhs.file->path().generic_string() : std::string{};
            const std::string rhsPath = rhs.file ? rhs.file->path().generic_string() : std::string{};
            if (lhsPath != rhsPath)
                return lhsPath < rhsPath;
            if (lhs.sourceLine != rhs.sourceLine)
                return lhs.sourceLine < rhs.sourceLine;
            return lhs.signature < rhs.signature;
        });
    }

    std::ranges::sort(outItems, [](const DocItem& lhs, const DocItem& rhs) {
        const int lhsOrder = itemSortOrder(lhs.kind);
        const int rhsOrder = itemSortOrder(rhs.kind);
        if (lhsOrder != rhsOrder)
            return lhsOrder < rhsOrder;
        if (lhs.category != rhs.category)
            return alphabeticLess(lhs.category, rhs.category);
        return alphabeticLess(lhs.fullName, rhs.fullName);
    });

    for (DocItem& item : outItems)
        collectItemMembers(ctx, item, runtime);
}
SWC_END_NAMESPACE();
