#include "pch.h"
#include "Compiler/Lexer/Lexer.h"
#include "Compiler/ModuleApi/ModuleApi.Export.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/SourceFile.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();
using namespace ModuleApi::Export;

namespace
{
    bool isModuleApiDeclWrapper(const AstNode& node)
    {
        return node.is(AstNodeId::AccessModifier) ||
               node.is(AstNodeId::AttributeList) ||
               node.is(AstNodeId::VarDeclList);
    }

    TokenRef moduleApiCallExprEndTokRef(const Ast& ast, const AstNode& node)
    {
        if (!node.is(AstNodeId::CallExpr) || !ast.hasSourceView())
            return TokenRef::invalid();

        const TokenRef openTokRef = node.tokRef();
        if (!openTokRef.isValid())
            return TokenRef::invalid();

        const SourceView& srcView = ast.srcView();
        if (srcView.token(openTokRef).id != TokenId::SymLeftParen)
            return TokenRef::invalid();

        uint32_t parenBalance = 0;
        for (uint32_t tokIndex = openTokRef.get(); tokIndex < srcView.tokens().size(); ++tokIndex)
        {
            const TokenId tokenId = srcView.token(TokenRef(tokIndex)).id;
            if (tokenId == TokenId::SymLeftParen)
                parenBalance++;
            else if (tokenId == TokenId::SymRightParen)
            {
                SWC_ASSERT(parenBalance != 0);
                parenBalance--;
                if (!parenBalance)
                    return TokenRef(tokIndex);
            }
        }

        return TokenRef::invalid();
    }

    TokenRef moduleApiFunctionBodyEndTokRef(const Ast& ast, const AstFunctionDecl& functionDecl)
    {
        if (!functionDecl.nodeBodyRef.isValid() || ast.isAdditionalNode(functionDecl.nodeBodyRef))
            return TokenRef::invalid();

        const AstNode& bodyNode = ast.node(functionDecl.nodeBodyRef);
        if (functionDecl.hasFlag(AstFunctionFlagsE::Short))
        {
            const TokenRef callEndTokRef = moduleApiCallExprEndTokRef(ast, bodyNode);
            if (callEndTokRef.isValid())
                return callEndTokRef;
        }

        TokenRef bodyStartTokRef = moduleApiSnippetStartTokRef(ast, bodyNode);
        if (!bodyStartTokRef.isValid())
            bodyStartTokRef = bodyNode.tokRef();

        const TokenRef bodyEndTokRef = bodyNode.tokRefEnd(ast);
        if (!bodyEndTokRef.isValid())
            return TokenRef::invalid();

        if (!ast.hasSourceView() || !bodyStartTokRef.isValid())
            return bodyEndTokRef;

        const SourceView& srcView = ast.srcView();
        if (srcView.token(bodyStartTokRef).id != TokenId::SymLeftCurly)
            return bodyEndTokRef;

        uint32_t curlyBalance = 0;
        for (uint32_t tokIndex = bodyStartTokRef.get(); tokIndex < srcView.tokens().size(); ++tokIndex)
        {
            const TokenId tokenId = srcView.token(TokenRef(tokIndex)).id;
            if (tokenId == TokenId::SymLeftCurly)
                curlyBalance++;
            else if (tokenId == TokenId::SymRightCurly)
            {
                SWC_ASSERT(curlyBalance != 0);
                curlyBalance--;
                if (!curlyBalance)
                    return TokenRef(tokIndex);
            }
        }

        return bodyEndTokRef;
    }

    AstNodeRef moduleApiAggregateBodyRef(const AstNode& declNode)
    {
        switch (declNode.id())
        {
            case AstNodeId::StructDecl:
                return declNode.cast<AstStructDecl>().nodeBodyRef;

            case AstNodeId::UnionDecl:
                return declNode.cast<AstUnionDecl>().nodeBodyRef;

            case AstNodeId::EnumDecl:
                return declNode.cast<AstEnumDecl>().nodeBodyRef;

            case AstNodeId::InterfaceDecl:
                return declNode.cast<AstInterfaceDecl>().nodeBodyRef;

            default:
                return AstNodeRef::invalid();
        }
    }

    TokenRef moduleApiAggregateBodyEndTokRef(const Ast& ast, const AstNode& declNode)
    {
        const AstNodeRef bodyRef = moduleApiAggregateBodyRef(declNode);
        if (!bodyRef.isValid() || ast.isAdditionalNode(bodyRef))
            return TokenRef::invalid();

        const AstNode& bodyNode = ast.node(bodyRef);
        if (!bodyNode.tokRef().isValid())
            return TokenRef::invalid();

        const TokenRef bodyEndTokRef = bodyNode.tokRefEnd(ast);
        if (!bodyEndTokRef.isValid())
            return TokenRef::invalid();
        if (!ast.hasSourceView())
            return bodyEndTokRef;

        const SourceView& srcView = ast.srcView();
        if (srcView.token(bodyNode.tokRef()).id != TokenId::SymLeftCurly)
            return bodyEndTokRef;

        uint32_t curlyBalance = 0;
        for (uint32_t tokIndex = bodyNode.tokRef().get(); tokIndex < srcView.tokens().size(); ++tokIndex)
        {
            const TokenId tokenId = srcView.token(TokenRef(tokIndex)).id;
            if (tokenId == TokenId::SymLeftCurly)
                curlyBalance++;
            else if (tokenId == TokenId::SymRightCurly)
            {
                SWC_ASSERT(curlyBalance != 0);
                curlyBalance--;
                if (!curlyBalance)
                    return TokenRef(tokIndex);
            }
        }

        return bodyEndTokRef;
    }

    TokenRef moduleApiSnippetEndTokRef(const Ast& ast, const AstNode& node)
    {
        if (isModuleApiDeclWrapper(node))
        {
            SmallVector<AstNodeRef> childRefs;
            node.collectChildrenFromAst(childRefs, ast);
            for (size_t i = childRefs.size(); i > 0; --i)
            {
                const AstNodeRef childRef = childRefs[i - 1];
                if (!childRef.isValid() || !ast.hasNode(childRef))
                    continue;

                const TokenRef childEndTokRef = moduleApiSnippetEndTokRef(ast, ast.node(childRef));
                if (childEndTokRef.isValid())
                    return childEndTokRef;
            }
        }

        if (const TokenRef bodyEndTokRef = moduleApiAggregateBodyEndTokRef(ast, node); bodyEndTokRef.isValid())
            return bodyEndTokRef;

        if (const auto* functionDecl = node.safeCast<AstFunctionDecl>())
        {
            const TokenRef bodyEndTokRef = moduleApiFunctionBodyEndTokRef(ast, *functionDecl);
            if (bodyEndTokRef.isValid())
                return bodyEndTokRef;
        }

        return node.tokRefEnd(ast);
    }

    struct ModuleApiDelimiterBalance
    {
        uint32_t paren  = 0;
        uint32_t square = 0;
        uint32_t curly  = 0;

        bool empty() const
        {
            return !paren && !square && !curly;
        }
    };

    void updateModuleApiDelimiterBalance(ModuleApiDelimiterBalance& balance, const TokenId tokenId)
    {
        switch (tokenId)
        {
            case TokenId::SymLeftParen:
                balance.paren++;
                break;

            case TokenId::SymRightParen:
                if (balance.paren)
                    balance.paren--;
                break;

            case TokenId::SymLeftBracket:
                balance.square++;
                break;

            case TokenId::SymRightBracket:
                if (balance.square)
                    balance.square--;
                break;

            case TokenId::SymLeftCurly:
                balance.curly++;
                break;

            case TokenId::SymRightCurly:
                if (balance.curly)
                    balance.curly--;
                break;

            default:
                break;
        }
    }

    void extendModuleApiSnippetEndOffset(const SourceView& srcView, const TokenRef startTokRef, const TokenRef endTokRef, uint32_t& ioEndOffset)
    {
        ModuleApiDelimiterBalance balance;
        for (uint32_t tokIndex = startTokRef.get(); tokIndex <= endTokRef.get() && tokIndex < srcView.tokens().size(); ++tokIndex)
            updateModuleApiDelimiterBalance(balance, srcView.token(TokenRef(tokIndex)).id);

        if (balance.empty())
            return;

        for (uint32_t tokIndex = endTokRef.get() + 1; tokIndex < srcView.tokens().size(); ++tokIndex)
        {
            const Token& token  = srcView.token(TokenRef(tokIndex));
            bool         extend = false;

            switch (token.id)
            {
                case TokenId::SymRightParen:
                    extend = balance.paren != 0;
                    if (extend)
                        balance.paren--;
                    break;

                case TokenId::SymRightBracket:
                    extend = balance.square != 0;
                    if (extend)
                        balance.square--;
                    break;

                case TokenId::SymRightCurly:
                    extend = balance.curly != 0;
                    if (extend)
                        balance.curly--;
                    break;

                default:
                    return;
            }

            if (!extend)
                return;

            ioEndOffset = sourceTokenByteEnd(srcView, token);
            if (balance.empty())
                return;
        }
    }

    struct ModuleApiStripRange
    {
        uint32_t startOffset = 0;
        uint32_t endOffset   = 0;
    };

    bool moduleApiStripRangeStartsBefore(const ModuleApiStripRange& lhs, const ModuleApiStripRange& rhs)
    {
        return lhs.startOffset < rhs.startOffset;
    }

    void collectModuleApiPublicStripRanges(TaskContext& ctx, const Ast& ast, const AstNodeRef nodeRef, std::vector<ModuleApiStripRange>& outRanges)
    {
        if (nodeRef.isInvalid() || ast.isAdditionalNode(nodeRef) || !ast.hasSourceView())
            return;

        const AstNode& node = ast.node(nodeRef);
        if (const auto* accessNode = node.safeCast<AstAccessModifier>())
        {
            const SourceView& srcView = moduleApiNodeSourceView(ctx, ast, nodeRef);
            if (node.tokRef().isValid() && srcView.token(node.tokRef()).id == TokenId::KwdPublic && accessNode->nodeWhatRef.isValid() && ast.hasNode(accessNode->nodeWhatRef))
            {
                const AstNode& childNode        = ast.node(accessNode->nodeWhatRef);
                const TokenRef childStartTokRef = moduleApiSnippetStartTokRef(ast, childNode);
                if (childStartTokRef.isValid())
                {
                    const uint32_t startOffset = sourceTokenByteStart(srcView, srcView.token(node.tokRef()));
                    const uint32_t endOffset   = sourceTokenByteStart(srcView, srcView.token(childStartTokRef));
                    if (startOffset < endOffset)
                        outRanges.push_back({startOffset, endOffset});
                }
            }
        }

        SmallVector<AstNodeRef> childRefs;
        node.collectChildrenFromAst(childRefs, ast);
        for (const AstNodeRef childRef : childRefs)
            collectModuleApiPublicStripRanges(ctx, ast, childRef, outRanges);
    }

    void normalizeModuleApiStripRanges(std::vector<ModuleApiStripRange>& ioRanges)
    {
        if (ioRanges.empty())
            return;

        std::ranges::sort(ioRanges, moduleApiStripRangeStartsBefore);

        size_t writeIndex = 0;
        for (size_t readIndex = 1; readIndex < ioRanges.size(); ++readIndex)
        {
            ModuleApiStripRange&       current = ioRanges[writeIndex];
            const ModuleApiStripRange& next    = ioRanges[readIndex];
            if (next.startOffset <= current.endOffset)
            {
                current.endOffset = std::max(current.endOffset, next.endOffset);
                continue;
            }

            ioRanges[++writeIndex] = next;
        }

        ioRanges.resize(writeIndex + 1);
    }

    Utf8 stripModuleApiSourceRanges(const std::string_view snippetText, const uint32_t snippetStartOffset, std::span<const ModuleApiStripRange> stripRanges)
    {
        if (snippetText.empty() || stripRanges.empty())
            return Utf8{snippetText};

        Utf8     result;
        uint32_t cursor = 0;
        result.reserve(snippetText.size());

        for (const ModuleApiStripRange& range : stripRanges)
        {
            if (range.endOffset <= snippetStartOffset)
                continue;
            if (range.startOffset >= snippetStartOffset + snippetText.size())
                break;

            const uint32_t relativeStart = range.startOffset <= snippetStartOffset ? 0 : range.startOffset - snippetStartOffset;
            const uint32_t relativeEnd   = std::min<uint32_t>(static_cast<uint32_t>(snippetText.size()), range.endOffset - snippetStartOffset);
            if (relativeStart > cursor)
                result.append(snippetText.substr(cursor, relativeStart - cursor));
            cursor = std::max(cursor, relativeEnd);
        }

        if (cursor < snippetText.size())
            result.append(snippetText.substr(cursor));
        return result;
    }

    bool isModuleApiCommentToken(const TokenId tokenId)
    {
        return tokenId == TokenId::CommentLine || tokenId == TokenId::CommentBlock;
    }

    std::string_view moduleApiLeadingIndentPrefix(const SourceView& srcView, const uint32_t startOffset)
    {
        const std::string_view source = srcView.stringView();
        if (startOffset >= source.size())
            return {};

        uint32_t lineStart = startOffset;
        while (lineStart > 0 && source[lineStart - 1] != '\n' && source[lineStart - 1] != '\r')
            lineStart--;

        uint32_t indentEnd = lineStart;
        while (indentEnd < startOffset && (source[indentEnd] == ' ' || source[indentEnd] == '\t'))
            indentEnd++;

        indentEnd = std::min(indentEnd, startOffset);
        return source.substr(lineStart, indentEnd - lineStart);
    }

    void flushModuleApiLine(Utf8& output, Utf8& line, const std::string_view eol, bool& wroteLine, bool& lineHasContent, const bool forceWrite)
    {
        while (!line.empty() && (line.back() == ' ' || line.back() == '\t'))
            line.pop_back();

        if (forceWrite || lineHasContent)
        {
            if (wroteLine)
                output += eol;
            output += line;
            wroteLine = true;
        }

        line.clear();
        lineHasContent = false;
    }

    struct ModuleApiLexedPiece
    {
        TokenId          tokenId = TokenId::Invalid;
        std::string_view text;
    };

    ModuleApiLexedPiece nextModuleApiLexedPiece(const SourceView& srcView, uint32_t& ioTokenIndex, uint32_t& ioTriviaIndex)
    {
        const auto& tokens = srcView.tokens();
        while (ioTokenIndex < tokens.size())
        {
            const auto [triviaStart, triviaEnd] = srcView.triviaRangeForToken(TokenRef(ioTokenIndex));
            ioTriviaIndex                       = std::max(ioTriviaIndex, triviaStart);
            if (ioTriviaIndex < triviaEnd)
            {
                const SourceTrivia& trivia = srcView.trivia()[ioTriviaIndex++];
                return {
                    .tokenId = trivia.tok.id,
                    .text    = trivia.tok.string(srcView),
                };
            }

            const Token& token = tokens[ioTokenIndex++];
            if (token.is(TokenId::EndOfFile))
                continue;

            return {
                .tokenId = token.id,
                .text    = token.string(srcView),
            };
        }

        return {};
    }

    void appendModuleApiLexedText(Utf8& output, Utf8& line, const std::string_view text, const std::string_view indentPrefixToStrip, const std::string_view eol, const bool preserveEmptyLine, bool& wroteLine, bool& lineHasContent, bool& pendingSpace, size_t& ioIndentStripIndex)
    {
        size_t index = 0;
        while (index < text.size())
        {
            const char c = text[index];
            if (pendingSpace)
            {
                if (c == '\r' || c == '\n' || c == ' ' || c == '\t')
                {
                    pendingSpace = false;
                }
                else
                {
                    line += ' ';
                    pendingSpace = false;
                }
            }

            if (c == '\r' || c == '\n')
            {
                flushModuleApiLine(output, line, eol, wroteLine, lineHasContent, preserveEmptyLine);
                pendingSpace       = false;
                ioIndentStripIndex = 0;
                if (c == '\r' && index + 1 < text.size() && text[index + 1] == '\n')
                    index++;
                index++;
                continue;
            }

            if (!lineHasContent && ioIndentStripIndex < indentPrefixToStrip.size() && (c == ' ' || c == '\t'))
            {
                if (c == indentPrefixToStrip[ioIndentStripIndex])
                {
                    ioIndentStripIndex++;
                    index++;
                    continue;
                }

                ioIndentStripIndex = indentPrefixToStrip.size();
            }
            else if (!lineHasContent)
            {
                ioIndentStripIndex = indentPrefixToStrip.size();
            }

            line += c;
            if (c != ' ' && c != '\t')
                lineHasContent = true;
            index++;
        }
    }
}

namespace ModuleApi::Export
{
    TokenRef moduleApiSnippetStartTokRef(const Ast& ast, const AstNode& node)
    {
        if (node.is(AstNodeId::VarDeclList))
        {
            SmallVector<AstNodeRef> childRefs;
            ast.appendNodes(childRefs, node.cast<AstVarDeclList>().spanChildrenRef);
            if (!childRefs.empty() && childRefs.front().isValid() && ast.hasNode(childRefs.front()))
                return moduleApiSnippetStartTokRef(ast, ast.node(childRefs.front()));
        }

        if (node.is(AstNodeId::AttributeList))
        {
            if (node.tokRef().isValid())
                return node.tokRef();

            const auto& attrList = node.cast<AstAttributeList>();
            if (attrList.nodeBodyRef.isValid() && ast.hasNode(attrList.nodeBodyRef))
                return moduleApiSnippetStartTokRef(ast, ast.node(attrList.nodeBodyRef));
        }

        if (ast.hasSourceView() && node.tokRef().isValid() && node.tokRef().get() > 0)
        {
            const TokenRef prevTokRef(node.tokRef().get() - 1);
            const TokenId  prevId = ast.srcView().token(prevTokRef).id;
            switch (node.id())
            {
                case AstNodeId::FunctionDecl:
                    if (prevId == TokenId::KwdFunc || prevId == TokenId::KwdMtd)
                        return prevTokRef;
                    break;

                case AstNodeId::StructDecl:
                    if (prevId == TokenId::KwdStruct)
                        return prevTokRef;
                    break;

                case AstNodeId::EnumDecl:
                    if (prevId == TokenId::KwdEnum)
                        return prevTokRef;
                    break;

                case AstNodeId::UnionDecl:
                    if (prevId == TokenId::KwdUnion)
                        return prevTokRef;
                    break;

                case AstNodeId::InterfaceDecl:
                    if (prevId == TokenId::KwdInterface)
                        return prevTokRef;
                    break;

                case AstNodeId::AliasDecl:
                    if (prevId == TokenId::KwdAlias)
                        return prevTokRef;
                    break;

                case AstNodeId::Impl:
                    if (prevId == TokenId::KwdImpl)
                        return prevTokRef;
                    break;

                default:
                    break;
            }
        }

        return node.tokRef();
    }

    const SourceView& moduleApiNodeSourceView(TaskContext& ctx, const Ast& ast, const AstNodeRef nodeRef)
    {
        const AstNode& node = ast.node(nodeRef);
        if (node.srcViewRef().isValid())
            return ctx.compiler().srcView(node.srcViewRef());
        return ast.srcView();
    }

    bool tryGetModuleApiSnippetOffsets(TaskContext& ctx, const SourceFile& file, const AstNodeRef nodeRef, uint32_t& outStartOffset, uint32_t& outEndOffset)
    {
        outStartOffset = 0;
        outEndOffset   = 0;
        if (nodeRef.isInvalid())
            return false;

        const Ast& ast = file.ast();
        if (!ast.hasSourceView())
            return false;

        const AstNode& node        = ast.node(nodeRef);
        const TokenRef startTokRef = moduleApiSnippetStartTokRef(ast, node);
        if (!startTokRef.isValid())
            return false;
        const TokenRef endTokRef = moduleApiSnippetEndTokRef(ast, node);
        if (!endTokRef.isValid())
            return false;

        const SourceView& srcView = moduleApiNodeSourceView(ctx, ast, nodeRef);
        outStartOffset            = sourceTokenByteStart(srcView, srcView.token(startTokRef));
        outEndOffset              = sourceTokenByteEnd(srcView, srcView.token(endTokRef));
        extendModuleApiSnippetEndOffset(srcView, startTokRef, endTokRef, outEndOffset);
        return true;
    }

    bool tryGetModuleApiSnippetStartOffset(TaskContext& ctx, const SourceFile& file, const AstNodeRef nodeRef, uint32_t& outStartOffset)
    {
        uint32_t endOffset = 0;
        return tryGetModuleApiSnippetOffsets(ctx, file, nodeRef, outStartOffset, endOffset);
    }

    bool tryGetModuleApiSnippet(TaskContext& ctx, const SourceFile& file, const AstNodeRef nodeRef, std::string_view& outSnippet)
    {
        outSnippet           = {};
        uint32_t startOffset = 0;
        uint32_t endOffset   = 0;
        if (!tryGetModuleApiSnippetOffsets(ctx, file, nodeRef, startOffset, endOffset))
            return false;

        const SourceView&      srcView = moduleApiNodeSourceView(ctx, file.ast(), nodeRef);
        const std::string_view source  = srcView.stringView();
        endOffset                      = std::min(endOffset, static_cast<uint32_t>(source.size()));
        while (endOffset > startOffset && std::isspace(static_cast<unsigned char>(source[endOffset - 1])))
            endOffset--;

        if (startOffset >= endOffset || endOffset > source.size())
            return false;

        outSnippet = source.substr(startOffset, endOffset - startOffset);
        return true;
    }

    Utf8 buildSanitizedModuleApiSnippet(TaskContext& ctx, const SourceFile& file, const AstNodeRef nodeRef, const uint32_t startOffset, const std::string_view snippetText, const std::string_view eol)
    {
        if (snippetText.empty())
            return {};

        const SourceView&      snippetSrcView      = moduleApiNodeSourceView(ctx, file.ast(), nodeRef);
        const std::string_view indentPrefixToStrip = moduleApiLeadingIndentPrefix(snippetSrcView, startOffset);

        std::vector<ModuleApiStripRange> stripRanges;
        collectModuleApiPublicStripRanges(ctx, file.ast(), nodeRef, stripRanges);
        normalizeModuleApiStripRanges(stripRanges);
        const Utf8 filteredSnippet = stripModuleApiSourceRanges(snippetText, startOffset, stripRanges);

        SourceFile lexFile(FileRef::invalid(), file.path(), FileFlagsE::CustomSrc);
        lexFile.setContent(filteredSnippet.view());

        SourceView srcView(SourceViewRef::invalid(), &lexFile);
        Lexer      lexer;
        lexer.tokenize(ctx, srcView, LexerFlagsE::EmitTrivia);

        Utf8     result;
        Utf8     line;
        bool     wroteLine        = false;
        bool     lineHasContent   = false;
        bool     pendingSpace     = false;
        uint32_t tokenIndex       = 0;
        uint32_t triviaIndex      = 0;
        size_t   indentStripIndex = 0;

        result.reserve(filteredSnippet.size());
        line.reserve(filteredSnippet.size());

        while (true)
        {
            const ModuleApiLexedPiece piece = nextModuleApiLexedPiece(srcView, tokenIndex, triviaIndex);
            if (piece.tokenId == TokenId::Invalid)
                break;

            if (isModuleApiCommentToken(piece.tokenId))
            {
                if (!line.empty() && line.back() != ' ' && line.back() != '\t')
                    pendingSpace = true;
                continue;
            }

            if (piece.tokenId == TokenId::Whitespace)
            {
                appendModuleApiLexedText(result, line, piece.text, indentPrefixToStrip, eol, false, wroteLine, lineHasContent, pendingSpace, indentStripIndex);
                continue;
            }

            appendModuleApiLexedText(result, line, piece.text, indentPrefixToStrip, eol, true, wroteLine, lineHasContent, pendingSpace, indentStripIndex);
        }

        flushModuleApiLine(result, line, eol, wroteLine, lineHasContent, false);
        return result;
    }
}

SWC_END_NAMESPACE();
