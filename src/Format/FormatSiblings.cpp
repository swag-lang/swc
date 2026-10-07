#include "pch.h"
#include "Format/FormatSiblings.h"
#include "Format/FormatPassUtil.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using FormatPassUtil::INVALID_PIECE;

    bool rangeEditable(const FormatModel& model, const uint32_t first, const uint32_t last)
    {
        for (uint32_t i = first; i <= last && i < model.numPieces(); ++i)
        {
            if (model.piece(i).frozen || model.gapBefore(i).frozen)
                return false;
        }
        return true;
    }

    uint32_t nextCode(const FormatModel& model, const uint32_t pieceIndex)
    {
        uint32_t i = model.nextPiece(pieceIndex);
        while (i != INVALID_PIECE && model.piece(i).isComment)
            i = model.nextPiece(i);
        return i;
    }

    uint32_t prevCode(const FormatModel& model, const uint32_t pieceIndex)
    {
        uint32_t i = model.prevPiece(pieceIndex);
        while (i != INVALID_PIECE && model.piece(i).isComment)
            i = model.prevPiece(i);
        return i;
    }

    bool opensList(const FormatPiece& piece)
    {
        return piece.is(TokenId::SymLeftParen) || piece.is(TokenId::SymLeftBracket) || piece.hasRole(FormatRoleE::LiteralOpen);
    }

    bool closesList(const FormatPiece& piece)
    {
        return piece.is(TokenId::SymRightParen) || piece.is(TokenId::SymRightBracket) || piece.hasRole(FormatRoleE::LiteralClose);
    }

    // A declaration or a `defer` belongs to the scope its braces open: moving
    // it in or out of braces moves it to another scope.
    bool changesScope(const FormatPiece& piece)
    {
        switch (piece.id)
        {
            case TokenId::KwdLet:
            case TokenId::KwdVar:
            case TokenId::KwdConst:
            case TokenId::KwdDefer:
            case TokenId::KwdUsing:
            case TokenId::KwdWith:
            case TokenId::KwdFunc:
            case TokenId::KwdMtd:
            case TokenId::KwdStruct:
            case TokenId::KwdEnum:
            case TokenId::KwdUnion:
            case TokenId::KwdAlias:
            case TokenId::KwdImpl:
            case TokenId::KwdInterface:
            case TokenId::KwdNamespace:
            case TokenId::KwdAttr:
            case TokenId::KwdGlobal:
            case TokenId::KwdTls:
            case TokenId::KwdLate:
                return true;
            default:
                return false;
        }
    }

    // A nested control statement or a failure handler written after `do` can
    // capture the `else` that follows it: `catch expr else { ... }` is valid
    // grammar, so `if c do try a() else do b()` binds the `else` to the `try`.
    bool capturesElse(const FormatPiece& piece)
    {
        switch (piece.id)
        {
            case TokenId::KwdIf:
            case TokenId::KwdElse:
            case TokenId::KwdElseIf:
            case TokenId::KwdDo:
            case TokenId::KwdFor:
            case TokenId::KwdWhile:
            case TokenId::KwdSwitch:
            case TokenId::KwdParallel:
            case TokenId::KwdTry:
            case TokenId::KwdCatch:
            case TokenId::KwdExpect:
            case TokenId::KwdAssume:
            case TokenId::KwdCase:
            case TokenId::KwdDefault:
                return true;
            default:
                return false;
        }
    }

    struct ContentScan
    {
        bool compact         = true;  // one statement, no comment, no braced block, no line break outside a list
        bool scopeFree       = true;  // no token whose meaning depends on the enclosing scope
        bool elseFree        = true;  // no token that could capture a following `else`
        bool trailingComment = false; // a comment shares the last line
    };

    ContentScan scanContent(const FormatModel& model, const uint32_t first, const uint32_t last)
    {
        ContentScan    scan;
        const uint32_t depth      = model.piece(first).depth;
        uint32_t       statements = 0;
        uint32_t       listDepth  = 0;
        for (uint32_t p = first; p != INVALID_PIECE && p <= last; p = model.nextPiece(p))
        {
            const FormatPiece& piece = model.piece(p);
            if (piece.isComment)
                scan.compact = false;
            else
            {
                if (piece.hasRole(FormatRoleE::BlockOpen))
                    scan.compact = false;
                if (piece.depth == depth && piece.hasRole(FormatRoleE::StmtStart))
                    statements++;
                if (changesScope(piece))
                    scan.scopeFree = false;
                if (capturesElse(piece))
                    scan.elseFree = false;
            }

            if (p != first && !listDepth && model.gapHasNewline(p))
                scan.compact = false;
            if (opensList(piece))
                listDepth++;
            else if (listDepth && closesList(piece))
                listDepth--;
        }

        if (statements > 1)
            scan.compact = false;

        const uint32_t next = model.nextPiece(last);
        if (next != INVALID_PIECE && model.piece(next).isComment && !model.gapHasNewline(next))
        {
            scan.trailingComment = true;
            scan.compact         = false;
        }
        return scan;
    }

    bool noBreakBetween(const FormatModel& model, const uint32_t from, const uint32_t to)
    {
        for (uint32_t p = model.nextPiece(from); p != INVALID_PIECE && p <= to; p = model.nextPiece(p))
        {
            if (model.gapHasNewline(p))
                return false;
        }
        return true;
    }

    // Whether the gap before `piece` keeps two siblings in one group.
    bool gapKeepsGroup(const FormatModel& model, const uint32_t piece, const FormatAlignMode mode)
    {
        const uint32_t newlines = model.gapNewlineCount(piece);
        switch (mode)
        {
            case FormatAlignMode::Consecutive:
                return newlines <= 1;
            case FormatAlignMode::AcrossBlanks:
                return newlines <= 2;
            case FormatAlignMode::All:
                return true;
            default:
                return false;
        }
    }

    // Whether the statement starting at `nextStart` comes right after the one
    // ending at `prevLast`, with only comments, attributes, and access
    // modifiers between them, and no blank line `mode` treats as a boundary.
    bool follows(const FormatModel& model, const uint32_t prevLast, const uint32_t nextStart, const FormatAlignMode mode)
    {
        uint32_t p = model.nextPiece(prevLast);
        while (p != INVALID_PIECE)
        {
            if (!gapKeepsGroup(model, p, mode))
                return false;
            if (p == nextStart)
                return true;

            const FormatPiece& piece = model.piece(p);
            if (piece.hasRole(FormatRoleE::AttrOpen) && piece.match != INVALID_PIECE)
                p = piece.match;
            else if (!piece.isComment && !FormatPassUtil::isAccessModifier(piece))
                return false;
            p = model.nextPiece(p);
        }
        return false;
    }

    uint32_t enclosingOpen(const FormatModel& model, const uint32_t pieceIndex)
    {
        const uint32_t depth = model.piece(pieceIndex).depth;
        for (uint32_t p = model.prevPiece(pieceIndex); p != INVALID_PIECE; p = model.prevPiece(p))
        {
            if (model.piece(p).depth < depth)
                return p;
        }
        return INVALID_PIECE;
    }

    // The open bracket of the argument or literal list a closure is an item
    // of, or INVALID when the closure is not a whole item.
    uint32_t listOf(const FormatModel& model, const uint32_t head, const uint32_t last)
    {
        uint32_t before = prevCode(model, head);
        if (before != INVALID_PIECE && model.piece(before).hasRole(FormatRoleE::NamedArgumentColon))
        {
            const uint32_t name = prevCode(model, before);
            before              = name == INVALID_PIECE ? INVALID_PIECE : prevCode(model, name);
        }
        if (before == INVALID_PIECE)
            return INVALID_PIECE;

        uint32_t open = INVALID_PIECE;
        if (model.piece(before).is(TokenId::SymComma))
            open = enclosingOpen(model, before);
        else if (opensList(model.piece(before)))
            open = before;
        if (open == INVALID_PIECE || !opensList(model.piece(open)) || model.piece(open).match == INVALID_PIECE)
            return INVALID_PIECE;

        const uint32_t after = nextCode(model, last);
        if (after == model.piece(open).match)
            return open;
        if (after != INVALID_PIECE && model.piece(after).is(TokenId::SymComma) && model.piece(after).depth == model.piece(open).depth + 1)
            return open;
        return INVALID_PIECE;
    }

    // An attribute that turns a function into a macro or a mixin changes what
    // `return` means in its body.
    bool hasExpansionAttribute(const FormatModel& model, const uint32_t head)
    {
        uint32_t close = prevCode(model, head);
        while (close != INVALID_PIECE && model.piece(close).hasRole(FormatRoleE::AttrClose))
        {
            const uint32_t open = model.piece(close).match;
            if (open == INVALID_PIECE)
                return true;
            for (uint32_t p = open; p <= close; ++p)
            {
                const std::string_view text = model.piece(p).text;
                if (text == "Macro" || text == "Mixin")
                    return true;
            }
            close = prevCode(model, open);
        }
        return false;
    }

    bool hasWhereClause(const FormatModel& model, const uint32_t head, const uint32_t open)
    {
        for (uint32_t p = head; p < open; ++p)
        {
            if (model.piece(p).hasRole(FormatRoleE::WhereKeyword))
                return true;
        }
        return false;
    }

    void flushGroup(std::vector<std::vector<uint32_t>>& groups, std::vector<uint32_t>& current)
    {
        if (current.size() >= 2)
            groups.push_back(current);
        current.clear();
    }
}

namespace FormatSiblings
{
    bool isActive(const FormatAlignMode mode)
    {
        return mode != FormatAlignMode::Preserve && mode != FormatAlignMode::None;
    }

    BodyShape branchShape(const FormatModel& model, const FormatBranch& branch)
    {
        BodyShape shape;
        if (branch.keyword == INVALID_PIECE || branch.lastPiece == INVALID_PIECE)
            return shape;

        uint32_t intro = branch.doPiece;
        if (branch.openPiece != INVALID_PIECE)
        {
            shape.braced = true;
            intro        = branch.openPiece;
            shape.first  = model.nextPiece(branch.openPiece);
            shape.last   = model.prevPiece(branch.lastPiece);
        }
        else
        {
            if (branch.doPiece == INVALID_PIECE)
                return shape;
            shape.first = model.nextPiece(branch.doPiece);
            shape.last  = branch.lastPiece;
        }

        shape.valid   = rangeEditable(model, branch.keyword, branch.lastPiece);
        shape.oneLine = noBreakBetween(model, intro, branch.lastPiece);
        if (shape.first == INVALID_PIECE || shape.last == INVALID_PIECE || shape.first > shape.last || model.piece(shape.first).is(TokenId::SymRightCurly))
            return shape; // an empty body has nothing to put after `do`

        const ContentScan scan = scanContent(model, shape.first, shape.last);
        shape.compact          = scan.compact;
        shape.unbraceable      = scan.compact && scan.scopeFree && scan.elseFree;
        shape.braceable        = scan.scopeFree && !scan.trailingComment;
        return shape;
    }

    BodyShape functionShape(const FormatModel& model, const FormatFunctionBody& body)
    {
        BodyShape shape;
        if (body.lastPiece == INVALID_PIECE)
            return shape;

        const uint32_t intro = body.openPiece != INVALID_PIECE ? body.openPiece : body.arrowPiece;
        if (body.openPiece != INVALID_PIECE)
        {
            shape.braced = true;
            shape.first  = model.nextPiece(body.openPiece);
            shape.last   = model.prevPiece(body.lastPiece);
        }
        else
        {
            shape.first = model.nextPiece(body.arrowPiece);
            shape.last  = body.lastPiece;
        }

        shape.valid   = rangeEditable(model, body.headPiece, body.lastPiece);
        shape.oneLine = noBreakBetween(model, intro, body.lastPiece);
        if (shape.first == INVALID_PIECE || shape.last == INVALID_PIECE || shape.first > shape.last || model.piece(shape.first).is(TokenId::SymRightCurly))
            return shape;

        // A declaration whose single statement spans lines, even inside a
        // literal, does not read as a one-line function.
        const ContentScan scan = scanContent(model, shape.first, shape.last);
        shape.compact          = scan.compact && noBreakBetween(model, shape.first, shape.last);
        if (shape.braced)
        {
            // `{ return e }` becomes `=> e` only when the signature spells
            // the type `e` gives back.
            const uint32_t value = model.nextPiece(shape.first);
            shape.unbraceable    = scan.compact && body.hasReturnType && model.piece(shape.first).is(TokenId::KwdReturn) &&
                                value != INVALID_PIECE && value <= shape.last && !hasWhereClause(model, body.headPiece, body.openPiece) &&
                                !hasExpansionAttribute(model, body.headPiece);
        }
        else
        {
            shape.braceable = body.hasReturnType && !scan.trailingComment;
        }
        return shape;
    }

    uint32_t assignedStatementStart(const FormatModel& model, const uint32_t valuePiece, const uint32_t valueLast)
    {
        const uint32_t op = prevCode(model, valuePiece);
        if (op == INVALID_PIECE || !model.piece(op).roles.hasAny({FormatRoleE::AssignOp, FormatRoleE::InitAssign}))
            return INVALID_PIECE;

        const uint32_t depth = model.piece(op).depth;
        uint32_t       start = INVALID_PIECE;
        for (uint32_t p = model.prevPiece(op); p != INVALID_PIECE; p = model.prevPiece(p))
        {
            const FormatPiece& piece = model.piece(p);
            if (piece.depth < depth)
                return INVALID_PIECE;
            if (piece.depth == depth && piece.hasRole(FormatRoleE::StmtStart))
            {
                start = p;
                break;
            }
        }

        // The value has to end the statement.
        const uint32_t next = nextCode(model, valueLast);
        if (next != INVALID_PIECE)
        {
            const FormatPiece& piece = model.piece(next);
            if (piece.depth >= depth && !(piece.depth == depth && piece.hasRole(FormatRoleE::StmtStart) && model.gapHasNewline(next)))
                return INVALID_PIECE;
        }
        return start;
    }

    std::vector<std::vector<BranchRef>> branchGroups(const FormatModel& model, const bool chains, const FormatAlignMode guards)
    {
        std::vector<std::vector<BranchRef>> groups;
        const auto&                         all = model.branchChains();

        std::vector<uint32_t> singles;
        for (uint32_t c = 0; c < all.size(); ++c)
        {
            const FormatBranchChain& chain = all[c];
            if (chain.branches.size() == 1)
            {
                singles.push_back(c);
                continue;
            }
            if (!chains)
                continue;

            std::vector<BranchRef> group;
            for (uint32_t b = 0; b < chain.branches.size(); ++b)
                group.push_back({c, b});
            groups.push_back(std::move(group));
        }

        if (!isActive(guards))
            return groups;

        std::ranges::sort(singles, [&](const uint32_t a, const uint32_t b) { return all[a].stmtPiece < all[b].stmtPiece; });
        std::vector<BranchRef> current;
        for (const uint32_t c : singles)
        {
            const FormatBranch& branch = all[c].branches.front();
            if (branch.lastPiece == INVALID_PIECE)
            {
                if (current.size() >= 2)
                    groups.push_back(current);
                current.clear();
                continue;
            }

            if (!current.empty())
            {
                const FormatBranch& prev = all[current.back().first].branches.front();
                if (!follows(model, prev.lastPiece, all[c].stmtPiece, guards))
                {
                    if (current.size() >= 2)
                        groups.push_back(current);
                    current.clear();
                }
            }
            current.push_back({c, 0});
        }
        if (current.size() >= 2)
            groups.push_back(current);
        return groups;
    }

    std::vector<std::vector<uint32_t>> closureGroups(const FormatModel& model, const FormatAlignMode mode)
    {
        std::vector<std::vector<uint32_t>> groups;
        if (!isActive(mode))
            return groups;

        struct Statement
        {
            uint32_t start = 0;
            uint32_t last  = 0;
            uint32_t body  = 0;
        };

        const auto&                               bodies = model.functionBodies();
        std::vector<Statement>                    statements;
        std::map<uint32_t, std::vector<uint32_t>> lists;
        for (uint32_t i = 0; i < bodies.size(); ++i)
        {
            const FormatFunctionBody& body = bodies[i];
            if (!body.closure || body.lastPiece == INVALID_PIECE)
                continue;

            const uint32_t start = assignedStatementStart(model, body.headPiece, body.lastPiece);
            if (start != INVALID_PIECE)
            {
                statements.push_back({start, body.lastPiece, i});
                continue;
            }

            const uint32_t open = listOf(model, body.headPiece, body.lastPiece);
            if (open != INVALID_PIECE)
                lists[open].push_back(i);
        }

        std::ranges::sort(statements, {}, &Statement::start);
        std::vector<uint32_t> current;
        for (size_t i = 0; i < statements.size(); ++i)
        {
            if (!current.empty() && !follows(model, statements[i - 1].last, statements[i].start, mode))
                flushGroup(groups, current);
            current.push_back(statements[i].body);
        }
        flushGroup(groups, current);

        for (auto& [open, members] : lists)
        {
            if (members.size() >= 2)
                groups.push_back(members);
        }
        return groups;
    }

    std::vector<std::vector<uint32_t>> functionGroups(const FormatModel& model, const FormatAlignMode mode)
    {
        std::vector<std::vector<uint32_t>> groups;
        if (!isActive(mode))
            return groups;

        const auto&           bodies = model.functionBodies();
        std::vector<uint32_t> declarations;
        for (uint32_t i = 0; i < bodies.size(); ++i)
        {
            if (!bodies[i].closure && bodies[i].lastPiece != INVALID_PIECE)
                declarations.push_back(i);
        }
        std::ranges::sort(declarations, [&](const uint32_t a, const uint32_t b) { return bodies[a].headPiece < bodies[b].headPiece; });

        std::vector<uint32_t> current;
        for (const uint32_t i : declarations)
        {
            if (!current.empty() && !follows(model, bodies[current.back()].lastPiece, bodies[i].headPiece, mode))
                flushGroup(groups, current);
            current.push_back(i);
        }
        flushGroup(groups, current);
        return groups;
    }
}

SWC_END_NAMESPACE();
