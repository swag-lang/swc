#include "pch.h"
#include "Format/FormatClassifier.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Format/FormatModel.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t INVALID_PIECE = FormatPiece::INVALID_INDEX;

    struct NodeSpan
    {
        uint32_t minPiece = INVALID_PIECE;
        uint32_t maxPiece = INVALID_PIECE;

        bool valid() const { return minPiece != INVALID_PIECE; }
    };

    bool isAssignTokenId(const TokenId id)
    {
        switch (id)
        {
            case TokenId::SymEqual:
            case TokenId::SymPlusEqual:
            case TokenId::SymMinusEqual:
            case TokenId::SymAsteriskEqual:
            case TokenId::SymSlashEqual:
            case TokenId::SymPercentEqual:
            case TokenId::SymAmpersandEqual:
            case TokenId::SymPipeEqual:
            case TokenId::SymCircumflexEqual:
            case TokenId::SymLowerLowerEqual:
            case TokenId::SymGreaterGreaterEqual:
                return true;
            default:
                return false;
        }
    }

    class Classifier
    {
    public:
        Classifier(FormatModel& model, const Ast& ast) :
            model_(&model),
            ast_(&ast)
        {
        }

        void run()
        {
            const AstNodeRef root = ast_->root();
            if (root.isInvalid())
                return;
            computeSpan(root);
            classifyNode(root, AstNodeId::Invalid);
            registerRemainingBraces();
        }

        // Brace constructs the classifier has no dedicated handling for
        // (trailing code-block arguments, compiler blocks, ...) still behave
        // as plain blocks for indentation and brace placement.
        void registerRemainingBraces() const
        {
            std::unordered_set<uint32_t> registered;
            for (const FormatBlock& block : model_->blocks())
                registered.insert(block.openPiece);

            for (uint32_t i = 0; i < model_->numPieces(); ++i)
            {
                const FormatPiece& piece = model_->piece(i);
                if (piece.isNot(TokenId::SymLeftCurly) || piece.match == INVALID_PIECE)
                    continue;
                if (piece.hasRole(FormatRoleE::LiteralOpen) || registered.contains(i))
                    continue;

                FormatBlock block;
                block.openPiece  = i;
                block.closePiece = piece.match;
                block.headPiece  = model_->lineStartOf(i);
                block.kind       = FormatBlockKind::Plain;
                model_->blocks().push_back(block);
                model_->piece(i).roles.add(FormatRoleE::BlockOpen);
                model_->piece(piece.match).roles.add(FormatRoleE::BlockClose);
            }
        }

    private:
        bool shouldVisit(const AstNodeRef nodeRef) const
        {
            return nodeRef.isValid() && !ast_->isAdditionalNode(nodeRef);
        }

        uint32_t pieceOfNodeToken(const AstNode& node) const
        {
            const TokenRef tokRef = node.tokRef();
            if (tokRef.isInvalid())
                return INVALID_PIECE;
            if (model_->srcView().token(tokRef).is(TokenId::EndOfFile))
                return INVALID_PIECE;
            return model_->pieceOfToken(tokRef.get());
        }

        const NodeSpan& computeSpan(const AstNodeRef nodeRef)
        {
            const auto it = spans_.find(nodeRef.get());
            if (it != spans_.end())
                return it->second;

            NodeSpan       span;
            const AstNode& node        = ast_->node(nodeRef);
            const uint32_t anchorPiece = pieceOfNodeToken(node);
            if (anchorPiece != INVALID_PIECE)
            {
                span.minPiece = anchorPiece;
                span.maxPiece = anchorPiece;
            }

            SmallVector<AstNodeRef> children;
            Ast::nodeIdInfos(node.id()).collectChildren(children, *ast_, node);
            for (const AstNodeRef childRef : children)
            {
                if (!shouldVisit(childRef))
                    continue;
                const NodeSpan childSpan = computeSpan(childRef);
                if (!childSpan.valid())
                    continue;
                if (!span.valid())
                {
                    span = childSpan;
                }
                else
                {
                    span.minPiece = std::min(span.minPiece, childSpan.minPiece);
                    span.maxPiece = std::max(span.maxPiece, childSpan.maxPiece);
                }
            }

            // Nodes are anchored on the token the parser was at when it created
            // them, which for some declarations is past the introducing
            // keyword. Pull the span back so it starts on the keyword.
            if (span.valid())
            {
                if (node.is(AstNodeId::FunctionDecl))
                {
                    const uint32_t prev = prevCode(span.minPiece);
                    if (prev != INVALID_PIECE && (model_->piece(prev).is(TokenId::KwdFunc) || model_->piece(prev).is(TokenId::KwdMtd)))
                        span.minPiece = prev;
                }
                else if (node.is(AstNodeId::AttrDecl))
                {
                    const uint32_t prev = prevCodeIf(span.minPiece, TokenId::KwdAttr);
                    if (prev != INVALID_PIECE)
                        span.minPiece = prev;
                }
            }

            return spans_.emplace(nodeRef.get(), span).first->second;
        }

        NodeSpan spanOf(const AstNodeRef nodeRef)
        {
            if (!shouldVisit(nodeRef))
                return {};
            return computeSpan(nodeRef);
        }

        void addRole(const uint32_t pieceIndex, const FormatRoleE role) const
        {
            if (pieceIndex != INVALID_PIECE)
                model_->piece(pieceIndex).roles.add(role);
        }

        uint32_t nextCode(const uint32_t pieceIndex) const
        {
            uint32_t i = pieceIndex;
            for (;;)
            {
                i = model_->nextPiece(i);
                if (i == INVALID_PIECE || !model_->piece(i).isComment)
                    return i;
            }
        }

        uint32_t prevCode(const uint32_t pieceIndex) const
        {
            uint32_t i = pieceIndex;
            for (;;)
            {
                i = model_->prevPiece(i);
                if (i == INVALID_PIECE || !model_->piece(i).isComment)
                    return i;
            }
        }

        uint32_t nextCodeIf(const uint32_t after, const TokenId id) const
        {
            const uint32_t i = nextCode(after);
            if (i == INVALID_PIECE || model_->piece(i).isNot(id))
                return INVALID_PIECE;
            return i;
        }

        uint32_t prevCodeIf(const uint32_t before, const TokenId id) const
        {
            const uint32_t i = prevCode(before);
            if (i == INVALID_PIECE || model_->piece(i).isNot(id))
                return INVALID_PIECE;
            return i;
        }

        // Node spans do not include the closing brackets of their expression,
        // so the token after an operand may be a `)` / `]` / `}` that still
        // belongs to it. Skips those to reach the actual operator.
        uint32_t nextCodeAfterOperand(const uint32_t operandEnd) const
        {
            uint32_t i = nextCode(operandEnd);
            while (i != INVALID_PIECE)
            {
                const FormatPiece& piece = model_->piece(i);
                if (piece.isNot(TokenId::SymRightParen) && piece.isNot(TokenId::SymRightBracket) && piece.isNot(TokenId::SymRightCurly))
                    break;
                i = nextCode(i);
            }
            return i;
        }

        uint32_t nextCodeAfterOperandIf(const uint32_t operandEnd, const TokenId id) const
        {
            const uint32_t i = nextCodeAfterOperand(operandEnd);
            if (i == INVALID_PIECE || model_->piece(i).isNot(id))
                return INVALID_PIECE;
            return i;
        }

        // Symmetric of nextCodeAfterOperand: a span may start INSIDE its own
        // brackets (`[2] u32` anchors on the dimension), so the token that
        // introduces it sits before the opening brackets.
        uint32_t prevCodeBeforeOperandIf(const uint32_t operandStart, const TokenId id) const
        {
            uint32_t i = prevCode(operandStart);
            while (i != INVALID_PIECE)
            {
                const FormatPiece& piece = model_->piece(i);
                if (piece.isNot(TokenId::SymLeftParen) && piece.isNot(TokenId::SymLeftBracket) && piece.isNot(TokenId::SymLeftCurly))
                    break;
                i = prevCode(i);
            }
            if (i == INVALID_PIECE || model_->piece(i).isNot(id))
                return INVALID_PIECE;
            return i;
        }

        void registerBlock(const uint32_t openPiece, const FormatBlockKind kind, const uint32_t headPiece, const bool exprLevel = false) const
        {
            if (openPiece == INVALID_PIECE)
                return;
            const FormatPiece& open = model_->piece(openPiece);
            if (open.isNot(TokenId::SymLeftCurly) || open.match == INVALID_PIECE)
                return;

            // Constructs register their body before recursing, so a generic
            // EmbeddedBlock never overrides a more precise owner registration.
            for (const FormatBlock& block : model_->blocks())
            {
                if (block.openPiece == openPiece)
                    return;
            }

            FormatBlock block;
            block.openPiece  = openPiece;
            block.closePiece = open.match;
            block.headPiece  = headPiece == INVALID_PIECE ? openPiece : headPiece;
            block.kind       = kind;
            block.exprLevel  = exprLevel;
            model_->blocks().push_back(block);

            addRole(openPiece, FormatRoleE::BlockOpen);
            addRole(open.match, FormatRoleE::BlockClose);
        }

        // Locates the `{` that opens a body node: either the body's first
        // piece, or the code piece right before it.
        uint32_t bodyOpenBrace(const NodeSpan& bodySpan) const
        {
            if (!bodySpan.valid())
                return INVALID_PIECE;
            if (model_->piece(bodySpan.minPiece).is(TokenId::SymLeftCurly))
                return bodySpan.minPiece;

            const uint32_t prev = prevCode(bodySpan.minPiece);
            if (prev != INVALID_PIECE && model_->piece(prev).is(TokenId::SymLeftCurly))
                return prev;
            return INVALID_PIECE;
        }

        // Scans forward from a declaration anchor for the `{` that opens its
        // body, skipping the header (name, generic parameters, base type, ...).
        uint32_t findHeaderOpenBrace(const uint32_t anchorPiece) const
        {
            if (anchorPiece == INVALID_PIECE)
                return INVALID_PIECE;

            uint32_t guard = 0;
            uint32_t i     = anchorPiece;
            for (;;)
            {
                i = model_->nextPiece(i);
                if (i == INVALID_PIECE || ++guard > 256)
                    return INVALID_PIECE;

                const FormatPiece& piece = model_->piece(i);
                if (piece.isComment)
                    continue;
                if (piece.is(TokenId::SymLeftCurly))
                    return i;

                if ((piece.is(TokenId::SymLeftParen) || piece.is(TokenId::SymLeftBracket) || piece.is(TokenId::SymAttrStart)) && piece.match != INVALID_PIECE)
                {
                    i = piece.match;
                    continue;
                }

                if (piece.is(TokenId::SymRightCurly) || piece.is(TokenId::SymRightParen) || piece.is(TokenId::SymRightBracket) || piece.is(TokenId::SymSemiColon))
                    return INVALID_PIECE;
            }
        }

        void markTrailingDo(const NodeSpan& bodySpan) const
        {
            if (!bodySpan.valid())
                return;
            addRole(prevCodeIf(bodySpan.minPiece, TokenId::KwdDo), FormatRoleE::TrailingDo);
        }

        void markControlBody(const AstNodeRef bodyRef, const uint32_t headPiece)
        {
            const NodeSpan bodySpan = spanOf(bodyRef);
            if (!bodySpan.valid())
                return;
            const uint32_t open = bodyOpenBrace(bodySpan);
            if (open != INVALID_PIECE)
                registerBlock(open, FormatBlockKind::Control, headPiece);
            else
                markTrailingDo(bodySpan);
        }

        // Marks the `else` keyword (and optional trailing `do`) that introduces
        // an else body which is not an `elif` chain.
        void classifyElseBody(const AstNodeRef elseRef, const uint32_t headPiece)
        {
            if (!shouldVisit(elseRef))
                return;

            const AstNode& elseNode = ast_->node(elseRef);
            if (elseNode.is(AstNodeId::IfStmt) || elseNode.is(AstNodeId::IfVarDecl) || elseNode.is(AstNodeId::CompilerIf))
                return; // `elif` / `#elif` chain: the nested if carries the keyword

            const NodeSpan elseSpan = spanOf(elseRef);
            if (!elseSpan.valid())
                return;

            uint32_t before = prevCode(elseSpan.minPiece);
            if (before != INVALID_PIECE && model_->piece(before).is(TokenId::KwdDo))
            {
                addRole(before, FormatRoleE::TrailingDo);
                before = prevCode(before);
            }
            if (before != INVALID_PIECE && (model_->piece(before).is(TokenId::KwdElse) || model_->piece(before).is(TokenId::CompilerElse)))
                addRole(before, FormatRoleE::ElseKeyword);

            const uint32_t open = bodyOpenBrace(elseSpan);
            if (open != INVALID_PIECE)
                registerBlock(open, FormatBlockKind::Control, headPiece);
        }

        void markStatementStarts(const AstNode& node)
        {
            SmallVector<AstNodeRef> children;
            Ast::nodeIdInfos(node.id()).collectChildren(children, *ast_, node);
            for (const AstNodeRef childRef : children)
            {
                if (!shouldVisit(childRef))
                    continue;
                const NodeSpan span = spanOf(childRef);
                if (span.valid())
                    addRole(span.minPiece, FormatRoleE::StmtStart);
            }
        }

        // First piece of the first compound child (statements span only).
        uint32_t firstCompoundChildPiece(const SpanRef spanChildrenRef)
        {
            SmallVector<AstNodeRef> children;
            AstNode::collectChildren(children, *ast_, spanChildrenRef);
            uint32_t result = INVALID_PIECE;
            for (const AstNodeRef childRef : children)
            {
                const NodeSpan span = spanOf(childRef);
                if (span.valid())
                    result = std::min(result, span.minPiece);
            }
            return result;
        }

        void classifyVarDecl(const AstNode& node, const NodeSpan& span, const AstNodeRef typeRef, const AstNodeRef initRef, const AstNodeId parentCompound)
        {
            const auto flags       = node.parserFlags();
            const bool isConst     = (flags & static_cast<AstNode::ParserFlags>(AstVarDeclFlagsE::Const)) != 0;
            const bool inAggregate = parentCompound == AstNodeId::AggregateBody;

            const FormatRoleE startRole = inAggregate ? FormatRoleE::FieldDeclStart
                                        : isConst     ? FormatRoleE::ConstDeclStart
                                                      : FormatRoleE::VarDeclStart;
            addRole(span.minPiece, startRole);

            // `using wnd: Wnd` fields start their line on the `using` keyword.
            if (span.valid())
            {
                const uint32_t prev = prevCode(span.minPiece);
                if (prev != INVALID_PIECE && model_->piece(prev).is(TokenId::KwdUsing))
                    addRole(prev, startRole);
            }

            // The type may start with qualifiers (`#late`, `#null`, `*`, ...)
            // that its span skips over: find the `:` forward from the
            // declaration start instead of walking back from the type.
            const NodeSpan typeSpan = spanOf(typeRef);
            if (typeSpan.valid() && span.valid())
            {
                const uint32_t declDepth = model_->piece(span.minPiece).depth;
                for (uint32_t p = nextCode(span.minPiece); p != INVALID_PIECE && p <= typeSpan.minPiece; p = nextCode(p))
                {
                    const FormatPiece& piece = model_->piece(p);
                    if (piece.is(TokenId::SymColon) && piece.depth == declDepth)
                    {
                        addRole(p, FormatRoleE::DeclColon);
                        break;
                    }
                }
            }

            markInitAssign(initRef, FormatRoleE::InitAssign);
        }

        void markInitAssign(const AstNodeRef initRef, const FormatRoleE role)
        {
            const NodeSpan initSpan = spanOf(initRef);
            if (!initSpan.valid())
                return;
            if (model_->piece(initSpan.minPiece).is(TokenId::SymEqual))
                addRole(initSpan.minPiece, role);
            else
                addRole(prevCodeBeforeOperandIf(initSpan.minPiece, TokenId::SymEqual), role);
        }

        void classifyAttributeList(const AstNode& node, const NodeSpan& span) const
        {
            if (!span.valid())
                return;
            const FormatPiece& open = model_->piece(span.minPiece);
            if (open.isNot(TokenId::SymAttrStart) || open.match == INVALID_PIECE)
                return;

            addRole(span.minPiece, FormatRoleE::AttrOpen);
            addRole(open.match, FormatRoleE::AttrClose);

            const uint32_t innerDepth = open.depth + 1;
            for (uint32_t i = span.minPiece + 1; i < open.match; ++i)
            {
                const FormatPiece& piece = model_->piece(i);
                if (piece.is(TokenId::SymComma) && piece.depth == innerDepth)
                    addRole(i, FormatRoleE::AttrComma);
            }
            SWC_UNUSED(node);
        }

        void classifyNode(const AstNodeRef nodeRef, const AstNodeId parentCompound)
        {
            if (!shouldVisit(nodeRef))
                return;

            const AstNode& node       = ast_->node(nodeRef);
            const NodeSpan span       = spanOf(nodeRef);
            AstNodeId      nextParent = parentCompound;

            switch (node.id())
            {
                case AstNodeId::File:
                case AstNodeId::DependenciesBlock:
                case AstNodeId::FunctionBody:
                case AstNodeId::AggregateBody:
                case AstNodeId::EnumBody:
                case AstNodeId::InterfaceBody:
                case AstNodeId::SwitchCaseBody:
                    markStatementStarts(node);
                    nextParent = node.id();
                    break;

                case AstNodeId::TopLevelBlock:
                case AstNodeId::EmbeddedBlock:
                {
                    // Braced groups (bare blocks, `#[attr] { ... }` bodies)
                    // are anchored on their `{`.
                    markStatementStarts(node);
                    nextParent = node.id();
                    if (span.valid() && model_->piece(span.minPiece).is(TokenId::SymLeftCurly))
                        registerBlock(span.minPiece, FormatBlockKind::Plain, span.minPiece);
                    break;
                }

                case AstNodeId::NamespaceDecl:
                {
                    markStatementStarts(node);
                    nextParent = node.id();
                    addRole(span.minPiece, FormatRoleE::TypeDeclStart);
                    if (span.valid())
                        registerBlock(findHeaderOpenBrace(span.minPiece), FormatBlockKind::Namespace, span.minPiece);
                    break;
                }

                case AstNodeId::Impl:
                {
                    markStatementStarts(node);
                    nextParent = node.id();
                    addRole(span.minPiece, FormatRoleE::TypeDeclStart);
                    if (span.valid())
                        registerBlock(findHeaderOpenBrace(span.minPiece), FormatBlockKind::Impl, span.minPiece);
                    break;
                }

                case AstNodeId::SwitchStmt:
                {
                    const auto& sw = node.cast<AstSwitchStmt>();
                    addRole(span.minPiece, FormatRoleE::ControlKeyword);
                    markStatementStarts(node);
                    nextParent = node.id();

                    const uint32_t firstCase = firstCompoundChildPiece(sw.spanChildrenRef);
                    uint32_t       open      = INVALID_PIECE;
                    if (firstCase != INVALID_PIECE)
                        open = prevCodeIf(firstCase, TokenId::SymLeftCurly);
                    if (open == INVALID_PIECE)
                    {
                        const NodeSpan exprSpan = spanOf(sw.nodeExprRef);
                        open = findHeaderOpenBrace(exprSpan.valid() ? exprSpan.maxPiece : span.minPiece);
                    }
                    registerBlock(open, FormatBlockKind::Switch, span.minPiece);
                    break;
                }

                case AstNodeId::SwitchCaseStmt:
                {
                    addRole(span.minPiece, FormatRoleE::CaseLabel);
                    addRole(span.minPiece, FormatRoleE::ControlKeyword);

                    // The label colon: first `:` at the label's depth.
                    if (span.valid())
                    {
                        const uint32_t depth = model_->piece(span.minPiece).depth;
                        uint32_t       colon = INVALID_PIECE;
                        for (uint32_t i = model_->nextPiece(span.minPiece); i != INVALID_PIECE && i <= span.maxPiece; i = model_->nextPiece(i))
                        {
                            const FormatPiece& piece = model_->piece(i);
                            if (piece.is(TokenId::SymColon) && piece.depth == depth)
                            {
                                colon = i;
                                break;
                            }
                        }
                        if (colon == INVALID_PIECE)
                            colon = nextCodeIf(span.maxPiece, TokenId::SymColon);
                        addRole(colon, FormatRoleE::CaseColon);
                    }
                    break;
                }

                case AstNodeId::FunctionDecl:
                {
                    const auto& fn = node.cast<AstFunctionDecl>();
                    addRole(span.minPiece, FormatRoleE::FuncDeclStart);

                    const NodeSpan paramsSpan = spanOf(fn.nodeParamsRef);
                    if (paramsSpan.valid())
                    {
                        if (model_->piece(paramsSpan.minPiece).is(TokenId::SymLeftParen))
                            addRole(paramsSpan.minPiece, FormatRoleE::DeclOpenParen);
                        else
                            addRole(prevCodeIf(paramsSpan.minPiece, TokenId::SymLeftParen), FormatRoleE::DeclOpenParen);
                    }

                    const NodeSpan returnSpan = spanOf(fn.nodeReturnTypeRef);
                    if (returnSpan.valid())
                        addRole(prevCodeBeforeOperandIf(returnSpan.minPiece, TokenId::SymMinusGreater), FormatRoleE::Arrow);

                    const NodeSpan bodySpan = spanOf(fn.nodeBodyRef);
                    if (bodySpan.valid())
                    {
                        const uint32_t open = bodyOpenBrace(bodySpan);
                        if (open != INVALID_PIECE)
                        {
                            registerBlock(open, FormatBlockKind::Function, span.minPiece);
                        }
                        else if (model_->piece(bodySpan.minPiece).is(TokenId::SymEqualGreater))
                        {
                            addRole(bodySpan.minPiece, FormatRoleE::FatArrow);
                        }
                        else
                        {
                            addRole(prevCodeBeforeOperandIf(bodySpan.minPiece, TokenId::SymEqualGreater), FormatRoleE::FatArrow);
                        }
                    }
                    else if (span.valid())
                    {
                        // Prototype (interface method, foreign function): the
                        // terminating `;` is required by the grammar. It may
                        // sit after closing brackets and suffix keywords such
                        // as `throw`.
                        for (uint32_t p = nextCode(span.maxPiece); p != INVALID_PIECE; p = nextCode(p))
                        {
                            if (model_->gapHasNewline(p))
                                break; // next line: past the declaration
                            if (model_->piece(p).is(TokenId::SymSemiColon))
                            {
                                addRole(p, FormatRoleE::KeepSemi);
                                break;
                            }
                        }
                    }
                    break;
                }

                case AstNodeId::FunctionExpr:
                {
                    const auto&    fn       = node.cast<AstFunctionExpr>();
                    const NodeSpan bodySpan = spanOf(fn.nodeBodyRef);
                    registerBlock(bodyOpenBrace(bodySpan), FormatBlockKind::Function, span.minPiece, true);

                    const NodeSpan returnSpan = spanOf(fn.nodeReturnTypeRef);
                    if (returnSpan.valid())
                        addRole(prevCodeBeforeOperandIf(returnSpan.minPiece, TokenId::SymMinusGreater), FormatRoleE::Arrow);
                    break;
                }

                case AstNodeId::ClosureExpr:
                {
                    const auto&    fn       = node.cast<AstClosureExpr>();
                    const NodeSpan bodySpan = spanOf(fn.nodeBodyRef);
                    registerBlock(bodyOpenBrace(bodySpan), FormatBlockKind::Function, span.minPiece, true);
                    break;
                }

                case AstNodeId::LambdaType:
                {
                    const auto&    lambda     = node.cast<AstLambdaType>();
                    const NodeSpan returnSpan = spanOf(lambda.nodeReturnTypeRef);
                    if (returnSpan.valid())
                        addRole(prevCodeBeforeOperandIf(returnSpan.minPiece, TokenId::SymMinusGreater), FormatRoleE::Arrow);
                    break;
                }

                case AstNodeId::StructDecl:
                case AstNodeId::UnionDecl:
                case AstNodeId::InterfaceDecl:
                {
                    AstNodeRef bodyRef;
                    if (node.is(AstNodeId::StructDecl))
                        bodyRef = node.cast<AstStructDecl>().nodeBodyRef;
                    else if (node.is(AstNodeId::UnionDecl))
                        bodyRef = node.cast<AstUnionDecl>().nodeBodyRef;
                    else
                        bodyRef = node.cast<AstInterfaceDecl>().nodeBodyRef;

                    const FormatBlockKind kind = node.is(AstNodeId::InterfaceDecl) ? FormatBlockKind::Interface : FormatBlockKind::Struct;
                    addRole(span.minPiece, FormatRoleE::TypeDeclStart);
                    const NodeSpan bodySpan    = spanOf(bodyRef);
                    uint32_t       open        = bodyOpenBrace(bodySpan);
                    if (open == INVALID_PIECE && span.valid())
                        open = findHeaderOpenBrace(span.minPiece);
                    registerBlock(open, kind, span.minPiece);
                    break;
                }

                case AstNodeId::AnonymousStructDecl:
                case AstNodeId::AnonymousUnionDecl:
                {
                    const AstNodeRef bodyRef = node.is(AstNodeId::AnonymousStructDecl)
                                                   ? node.cast<AstAnonymousStructDecl>().nodeBodyRef
                                                   : node.cast<AstAnonymousUnionDecl>().nodeBodyRef;
                    const NodeSpan bodySpan = spanOf(bodyRef);
                    uint32_t       open     = bodyOpenBrace(bodySpan);
                    if (open == INVALID_PIECE && span.valid())
                        open = findHeaderOpenBrace(span.minPiece);
                    registerBlock(open, FormatBlockKind::Struct, span.minPiece, true);
                    break;
                }

                case AstNodeId::EnumDecl:
                {
                    const auto& en = node.cast<AstEnumDecl>();
                    addRole(span.minPiece, FormatRoleE::TypeDeclStart);

                    const NodeSpan typeSpan = spanOf(en.nodeTypeRef);
                    if (typeSpan.valid())
                        addRole(prevCodeBeforeOperandIf(typeSpan.minPiece, TokenId::SymColon), FormatRoleE::BaseClauseColon);

                    const NodeSpan bodySpan = spanOf(en.nodeBodyRef);
                    uint32_t       open     = bodyOpenBrace(bodySpan);
                    if (open == INVALID_PIECE && span.valid())
                        open = findHeaderOpenBrace(span.minPiece);
                    registerBlock(open, FormatBlockKind::Enum, span.minPiece);
                    break;
                }

                case AstNodeId::EnumValue:
                {
                    const auto& value = node.cast<AstEnumValue>();
                    addRole(span.minPiece, FormatRoleE::EnumValueStart);
                    markInitAssign(value.nodeInitRef, FormatRoleE::EnumAssign);
                    break;
                }

                case AstNodeId::SingleVarDecl:
                {
                    const auto& var = node.cast<AstSingleVarDecl>();
                    classifyVarDecl(node, span, var.nodeTypeRef, var.nodeInitRef, parentCompound);
                    break;
                }

                case AstNodeId::MultiVarDecl:
                {
                    const auto& var = node.cast<AstMultiVarDecl>();
                    classifyVarDecl(node, span, var.nodeTypeRef, var.nodeInitRef, parentCompound);
                    break;
                }

                case AstNodeId::AliasDecl:
                {
                    const auto& alias = node.cast<AstAliasDecl>();
                    markInitAssign(alias.nodeExprRef, FormatRoleE::InitAssign);
                    break;
                }

                case AstNodeId::IfStmt:
                {
                    const auto& stmt = node.cast<AstIfStmt>();
                    addRole(span.minPiece, FormatRoleE::ControlKeyword);
                    if (span.valid() && model_->piece(span.minPiece).is(TokenId::KwdElseIf))
                        addRole(span.minPiece, FormatRoleE::ElseKeyword);

                    markControlBody(stmt.nodeIfBlockRef, span.minPiece);
                    classifyElseBody(stmt.nodeElseBlockRef, span.minPiece);
                    break;
                }

                case AstNodeId::IfVarDecl:
                {
                    const auto& stmt = node.cast<AstIfVarDecl>();
                    addRole(span.minPiece, FormatRoleE::ControlKeyword);
                    if (span.valid() && model_->piece(span.minPiece).is(TokenId::KwdElseIf))
                        addRole(span.minPiece, FormatRoleE::ElseKeyword);

                    markControlBody(stmt.nodeIfBlockRef, span.minPiece);
                    classifyElseBody(stmt.nodeElseBlockRef, span.minPiece);
                    break;
                }

                case AstNodeId::CompilerIf:
                {
                    const auto& stmt = node.cast<AstCompilerIf>();
                    addRole(span.minPiece, FormatRoleE::ControlKeyword);
                    if (span.valid() && model_->piece(span.minPiece).is(TokenId::CompilerElseIf))
                        addRole(span.minPiece, FormatRoleE::ElseKeyword);

                    markControlBody(stmt.nodeIfBlockRef, span.minPiece);
                    classifyElseBody(stmt.nodeElseBlockRef, span.minPiece);
                    break;
                }

                case AstNodeId::ConstraintBlock:
                case AstNodeId::ConstraintExpr:
                {
                    // `where` / `verify` clauses anchor on their keyword.
                    addRole(span.minPiece, FormatRoleE::WhereKeyword);
                    if (node.is(AstNodeId::ConstraintBlock))
                    {
                        markStatementStarts(node);
                        nextParent = node.id();
                        if (span.valid())
                            registerBlock(findHeaderOpenBrace(span.minPiece), FormatBlockKind::Control, span.minPiece, true);
                    }
                    break;
                }

                case AstNodeId::WhileStmt:
                {
                    const auto& stmt = node.cast<AstWhileStmt>();
                    addRole(span.minPiece, FormatRoleE::ControlKeyword);
                    markControlBody(stmt.nodeBodyRef, span.minPiece);
                    break;
                }

                case AstNodeId::ForeachStmt:
                {
                    const auto& stmt = node.cast<AstForeachStmt>();
                    addRole(span.minPiece, FormatRoleE::ControlKeyword);
                    markControlBody(stmt.nodeBodyRef, span.minPiece);
                    break;
                }

                case AstNodeId::ForStmt:
                {
                    const auto& stmt = node.cast<AstForStmt>();
                    addRole(span.minPiece, FormatRoleE::ControlKeyword);
                    markControlBody(stmt.nodeBodyRef, span.minPiece);
                    break;
                }

                case AstNodeId::ForCStyleStmt:
                {
                    const auto& stmt = node.cast<AstForCStyleStmt>();
                    addRole(span.minPiece, FormatRoleE::ControlKeyword);
                    markControlBody(stmt.nodeBodyRef, span.minPiece);
                    break;
                }

                case AstNodeId::InfiniteLoopStmt:
                {
                    const auto& stmt = node.cast<AstInfiniteLoopStmt>();
                    addRole(span.minPiece, FormatRoleE::ControlKeyword);
                    markControlBody(stmt.nodeBodyRef, span.minPiece);
                    break;
                }

                case AstNodeId::WithStmt:
                {
                    const auto& stmt = node.cast<AstWithStmt>();
                    addRole(span.minPiece, FormatRoleE::ControlKeyword);
                    markControlBody(stmt.nodeBodyRef, span.minPiece);
                    break;
                }

                case AstNodeId::DeferStmt:
                {
                    const auto& stmt = node.cast<AstDeferStmt>();
                    addRole(span.minPiece, FormatRoleE::ControlKeyword);
                    markControlBody(stmt.nodeBodyRef, span.minPiece);
                    break;
                }

                case AstNodeId::ReturnStmt:
                case AstNodeId::BreakStmt:
                case AstNodeId::ScopedBreakStmt:
                case AstNodeId::ContinueStmt:
                case AstNodeId::FallThroughStmt:
                case AstNodeId::UnreachableStmt:
                case AstNodeId::TryCatchStmt:
                case AstNodeId::TryCatchExpr:
                case AstNodeId::ThrowExpr:
                case AstNodeId::DiscardExpr:
                    addRole(span.minPiece, FormatRoleE::ControlKeyword);
                    break;

                case AstNodeId::UsingDecl:
                case AstNodeId::UsingNamespaceStmt:
                case AstNodeId::UsingEnumDecl:
                    addRole(span.minPiece, FormatRoleE::UsingStart);
                    break;

                case AstNodeId::AssignStmt:
                {
                    const auto& stmt = node.cast<AstAssignStmt>();
                    addRole(span.minPiece, FormatRoleE::AssignStart);

                    const NodeSpan leftSpan = spanOf(stmt.nodeLeftRef);
                    if (leftSpan.valid())
                    {
                        const uint32_t op = nextCodeAfterOperand(leftSpan.maxPiece);
                        if (op != INVALID_PIECE && isAssignTokenId(model_->piece(op).id))
                            addRole(op, FormatRoleE::AssignOp);
                    }
                    break;
                }

                case AstNodeId::BinaryExpr:
                case AstNodeId::RelationalExpr:
                case AstNodeId::LogicalExpr:
                {
                    const AstNodeRef leftRef = node.is(AstNodeId::BinaryExpr)
                                                   ? node.cast<AstBinaryExpr>().nodeLeftRef
                                               : node.is(AstNodeId::RelationalExpr)
                                                   ? node.cast<AstRelationalExpr>().nodeLeftRef
                                                   : node.cast<AstLogicalExpr>().nodeLeftRef;
                    const NodeSpan leftSpan = spanOf(leftRef);
                    if (leftSpan.valid())
                        addRole(nextCodeAfterOperand(leftSpan.maxPiece), FormatRoleE::BinaryOp);
                    break;
                }

                case AstNodeId::NullCoalescingExpr:
                {
                    const auto&    expr     = node.cast<AstNullCoalescingExpr>();
                    const NodeSpan leftSpan = spanOf(expr.nodeLeftRef);
                    if (leftSpan.valid())
                        addRole(nextCodeAfterOperand(leftSpan.maxPiece), FormatRoleE::BinaryOp);
                    break;
                }

                case AstNodeId::UnaryExpr:
                    addRole(span.minPiece, FormatRoleE::UnaryOp);
                    break;

                case AstNodeId::RangeExpr:
                {
                    const auto&    expr     = node.cast<AstRangeExpr>();
                    const NodeSpan downSpan = spanOf(expr.nodeExprDownRef);
                    if (downSpan.valid())
                        addRole(nextCodeAfterOperand(downSpan.maxPiece), FormatRoleE::RangeOp);
                    break;
                }

                case AstNodeId::ConditionalExpr:
                {
                    const auto&    expr     = node.cast<AstConditionalExpr>();
                    const NodeSpan condSpan = spanOf(expr.nodeCondRef);
                    if (condSpan.valid())
                        addRole(nextCodeAfterOperandIf(condSpan.maxPiece, TokenId::SymQuestion), FormatRoleE::TernaryOp);
                    const NodeSpan trueSpan = spanOf(expr.nodeTrueRef);
                    if (trueSpan.valid())
                        addRole(nextCodeAfterOperandIf(trueSpan.maxPiece, TokenId::SymColon), FormatRoleE::TernaryOp);
                    break;
                }

                case AstNodeId::CastExpr:
                {
                    addRole(span.minPiece, FormatRoleE::CastKeyword);
                    if (span.valid())
                    {
                        uint32_t open = nextCodeIf(span.minPiece, TokenId::SymLeftParen);
                        if (open == INVALID_PIECE)
                        {
                            // Modifiers may sit between `cast` and the type list.
                            const uint32_t after = nextCode(span.minPiece);
                            if (after != INVALID_PIECE)
                                open = nextCodeIf(after, TokenId::SymLeftParen);
                        }
                        if (open != INVALID_PIECE && model_->piece(open).match != INVALID_PIECE)
                            addRole(model_->piece(open).match, FormatRoleE::CastCloseParen);
                    }
                    break;
                }

                case AstNodeId::AutoCastExpr:
                    addRole(span.minPiece, FormatRoleE::CastKeyword);
                    break;

                case AstNodeId::CallExpr:
                case AstNodeId::IntrinsicCallExpr:
                {
                    const AstNodeRef calleeRef = node.is(AstNodeId::CallExpr)
                                                     ? node.cast<AstCallExpr>().nodeExprRef
                                                     : node.cast<AstIntrinsicCallExpr>().nodeExprRef;
                    const NodeSpan calleeSpan = spanOf(calleeRef);
                    const uint32_t from       = calleeSpan.valid() ? calleeSpan.maxPiece : span.minPiece;
                    addRole(nextCodeIf(from, TokenId::SymLeftParen), FormatRoleE::CallOpenParen);
                    break;
                }

                case AstNodeId::IntrinsicCall:
                case AstNodeId::IntrinsicCallVariadic:
                {
                    if (span.valid())
                        addRole(nextCodeIf(span.minPiece, TokenId::SymLeftParen), FormatRoleE::CallOpenParen);
                    break;
                }

                case AstNodeId::StructInitializerList:
                {
                    // The `{` may sit after the closing `)` / `}` of the type
                    // expression (`Type'(args){...}`, `struct { ... }{...}`),
                    // which the span excludes.
                    const auto&    init     = node.cast<AstStructInitializerList>();
                    const NodeSpan whatSpan = spanOf(init.nodeWhatRef);
                    if (whatSpan.valid())
                    {
                        const uint32_t open = nextCodeAfterOperandIf(whatSpan.maxPiece, TokenId::SymLeftCurly);
                        if (open != INVALID_PIECE && model_->piece(open).match != INVALID_PIECE)
                        {
                            addRole(open, FormatRoleE::LiteralOpen);
                            addRole(model_->piece(open).match, FormatRoleE::LiteralClose);
                        }
                    }
                    break;
                }

                case AstNodeId::ArrayLiteral:
                case AstNodeId::StructLiteral:
                {
                    if (span.valid())
                    {
                        const FormatPiece& open = model_->piece(span.minPiece);
                        if (open.is(TokenId::SymLeftCurly) && open.match != INVALID_PIECE)
                        {
                            addRole(span.minPiece, FormatRoleE::LiteralOpen);
                            addRole(open.match, FormatRoleE::LiteralClose);
                        }
                    }
                    break;
                }

                case AstNodeId::AttributeList:
                {
                    classifyAttributeList(node, span);

                    // The annotated declaration starts its own statement.
                    const NodeSpan bodySpan = spanOf(node.cast<AstAttributeList>().nodeBodyRef);
                    if (bodySpan.valid())
                        addRole(bodySpan.minPiece, FormatRoleE::StmtStart);
                    break;
                }

                default:
                    break;
            }

            classifyChildren(node, nextParent);
        }

        void classifyChildren(const AstNode& node, const AstNodeId parentCompound)
        {
            SmallVector<AstNodeRef> children;
            Ast::nodeIdInfos(node.id()).collectChildren(children, *ast_, node);
            for (const AstNodeRef childRef : children)
                classifyNode(childRef, parentCompound);
        }

        FormatModel*                           model_;
        const Ast*                             ast_;
        std::unordered_map<uint32_t, NodeSpan> spans_;
    };
}

void FormatClassifier::classify(FormatModel& model, const Ast& ast)
{
    Classifier classifier(model, ast);
    classifier.run();
}

SWC_END_NAMESPACE();
