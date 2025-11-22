#include "pch.h"

#include "Lexer/SourceView.h"
#include "Main/TaskContext.h"
#include "Parser/Ast.h"
#include "Parser/AstNodes.h"
#include "Sema/ConstantManager.h"

SWC_BEGIN_NAMESPACE()

void AstNode::collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast, SpanRef spanRef)
{
    ast.nodes(out, spanRef);
}

void AstNode::collectChildren(SmallVector<AstNodeRef>& out, std::initializer_list<AstNodeRef> nodes)
{
    for (auto n : nodes)
        out.push_back(n);
}

void AstNode::setConstant(ConstantRef ref)
{
    semaFlags_.clearMask(SemaFlagE::RefMask);
    addSemaFlag(SemaFlagE::IsConst);
    sema_ = ref;
}

const ConstantValue& AstNode::getConstant(const TaskContext& ctx) const
{
    SWC_ASSERT(isConstant());
    return ctx.compiler().constMgr().get(std::get<ConstantRef>(sema_));
}

TokenRef AstNode::tokRefEnd(const Ast& ast) const
{
    const auto& info = Ast::nodeIdInfos(id_);

    SmallVector<AstNodeRef> children;
    info.collectChildren(children, ast, *this);

    if (children.empty())
        return tokRef_;

    const auto& nodePtr = ast.node(children.back());
    return nodePtr->tokRefEnd(ast);
}

namespace
{
    // Return the actual starting byte offset of a token, accounting for identifiers table
    uint32_t tokenStartOffset(const SourceView& view, const Token& tok)
    {
        if (tok.id == TokenId::Identifier)
            return view.identifiers()[tok.byteStart].byteStart;
        return tok.byteStart;
    }

    // Return length clamped to the first EOL within the token text (remain on the same line)
    uint32_t tokenLenClampedSameLine(const SourceView& view, const Token& tok)
    {
        const auto sv  = tok.string(view);
        const auto pos = sv.find_first_of("\n\r");
        if (pos == std::string_view::npos)
            return tok.byteLength;
        return static_cast<uint32_t>(pos);
    }

    // Compute a 0-based line index for a given byte offset using SourceView::lines()
    size_t lineIndexForOffset(const std::vector<uint32_t>& lines, uint32_t offset)
    {
        auto it = std::ranges::upper_bound(lines, offset);
        if (it == lines.begin())
            return 0;
        --it;
        return static_cast<size_t>(std::distance(lines.begin(), it));
    }
}

SourceCodeLocation AstNode::location(const TaskContext& ctx, const Ast& ast) const
{
    SourceCodeLocation loc{};

    // Always use the SourceView of the node itself
    const auto  baseViewRef = srcViewRef_;
    auto&       view        = ctx.compiler().srcView(baseViewRef);
    const auto& lines       = view.lines();
    if (tokRef_.isInvalid() || view.tokens().empty() || lines.empty())
        return loc;

    // baseline comes from this node token
    const auto&    baseTok     = view.token(tokRef_);
    const uint32_t baseStart   = tokenStartOffset(view, baseTok);
    const auto     baseLineIdx = lineIndexForOffset(lines, baseStart);

    // Descend left-most while staying on the same line and same SourceView
    auto     leftMost = this;
    uint32_t startOff = baseStart;
    while (true)
    {
        SmallVector<AstNodeRef> children;
        Ast::nodeIdInfos(leftMost->id()).collectChildren(children, ast, *leftMost);
        if (children.empty() || children.front().isInvalid())
            break;
        const auto* childPtr = ast.node(children.front());
        if (childPtr->srcViewRef() != baseViewRef)
            break; // Different file/view -> stop
        const auto& childTok = view.token(childPtr->tokRef());
        const auto  cStart   = tokenStartOffset(view, childTok);
        if (lineIndexForOffset(lines, cStart) != baseLineIdx)
            break;
        leftMost = childPtr;
        startOff = cStart;
    }

    // Descend right-most while staying on the same line and same SourceView
    auto     rightMost = this;
    uint32_t endStart  = baseStart;
    uint32_t endLen    = tokenLenClampedSameLine(view, baseTok);
    while (true)
    {
        SmallVector<AstNodeRef> children;
        Ast::nodeIdInfos(rightMost->id()).collectChildren(children, ast, *rightMost);
        if (children.empty() || children.back().isInvalid())
            break;
        const auto* childPtr = ast.node(children.back());
        if (childPtr->srcViewRef() != baseViewRef)
            break; // Different file/view -> stop
        const auto& childTok = view.token(childPtr->tokRef());
        const auto  cStart   = tokenStartOffset(view, childTok);
        if (lineIndexForOffset(lines, cStart) != baseLineIdx)
            break;
        rightMost           = childPtr;
        const auto& lastTok = view.token(rightMost->tokRefEnd(ast));
        endStart            = tokenStartOffset(view, lastTok);
        endLen              = tokenLenClampedSameLine(view, lastTok);
    }

    // Compute span and fill location
    const uint32_t endByte = endStart + endLen;
    const uint32_t spanLen = endByte > startOff ? (endByte - startOff) : 1u;
    loc.fromOffset(ctx, view, startOff, spanLen);
    return loc;
}

SWC_END_NAMESPACE()
