#include "pch.h"
#include "Format/FormatPasses.h"
#include "Format/FormatPassUtil.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using FormatPassUtil::INVALID_PIECE;

    // Ensures the gap before `pieceIndex` holds at least `newlines` line
    // breaks (or exactly, when `exact` is true), keeping the line indent.
    void forceGapNewlines(FormatModel& model, const uint32_t pieceIndex, const uint32_t newlines, const bool exact)
    {
        if (!FormatPassUtil::canEditGap(model, pieceIndex))
            return;

        const uint32_t current = model.gapNewlineCount(pieceIndex);
        if (current == 0)
            return; // same-line neighbors: not a line-structure gap
        if (exact ? current == newlines : current >= newlines)
            return;

        const Utf8 indent(model.lineIndentOf(pieceIndex));
        model.setGapBreak(pieceIndex, newlines, indent.view());
    }

    void applyBlankLineAfterUsingBlock(FormatModel& model)
    {
        const FormatOptions& options = model.options();
        if (!options.blankLineAfterUsingBlock)
            return;

        // Locate the initial run of top-level `using` statements; leading
        // `#global` directives count as part of the file header.
        bool sawUsing = false;

        std::vector<uint32_t> lineStarts;
        model.collectLineStarts(lineStarts);

        for (const uint32_t lineStart : lineStarts)
        {
            const FormatPiece& piece = model.piece(lineStart);
            if (piece.isComment)
            {
                if (sawUsing)
                    break;
                continue; // header comments before the using block
            }
            if (!sawUsing && piece.is(TokenId::CompilerGlobal))
                continue; // `#global` header lines before the using block

            if (piece.hasRole(FormatRoleE::UsingStart) && piece.depth == 0)
            {
                sawUsing = true;
                continue;
            }

            if (!sawUsing)
                return; // first code is not a using: nothing to do

            // First non-using code line after the block.
            const uint32_t wanted = *options.blankLineAfterUsingBlock ? 2u : 1u;
            forceGapNewlines(model, lineStart, wanted, !*options.blankLineAfterUsingBlock);
            return;
        }
    }

    void applyBlankLineAfterGlobalBlock(FormatModel& model)
    {
        const FormatOptions& options = model.options();
        if (!options.blankLineAfterGlobalBlock)
            return;

        // Locate the initial run of top-level `#global` directives.
        bool sawGlobal = false;

        std::vector<uint32_t> lineStarts;
        model.collectLineStarts(lineStarts);

        for (const uint32_t lineStart : lineStarts)
        {
            const FormatPiece& piece = model.piece(lineStart);
            if (piece.isComment)
            {
                if (sawGlobal)
                    break;
                continue; // header comments before the directives
            }

            if (piece.is(TokenId::CompilerGlobal) && piece.depth == 0)
            {
                sawGlobal = true;
                continue;
            }

            if (!sawGlobal)
                return; // first code is not a `#global`: nothing to do

            // First code line after the directives.
            const uint32_t wanted = *options.blankLineAfterGlobalBlock ? 2u : 1u;
            forceGapNewlines(model, lineStart, wanted, !*options.blankLineAfterGlobalBlock);
            return;
        }
    }

    // Walks up from a declaration line over the attribute lines and the
    // whole-line comments directly attached to it (no blank in between): the
    // forced blank line goes before that whole group.
    uint32_t declGroupStart(const FormatModel& model, const uint32_t declLineStart)
    {
        uint32_t target = declLineStart;
        for (;;)
        {
            if (model.gapNewlineCount(target) != 1)
                break; // already blank-separated (or same-line): group ends here
            const uint32_t prev = model.prevPiece(target);
            if (prev == INVALID_PIECE)
                break;
            const uint32_t     prevLineStart = model.lineStartOf(prev);
            const FormatPiece& prevPiece     = model.piece(prevLineStart);
            const bool         attrLine      = prevPiece.hasRole(FormatRoleE::AttrOpen);
            const bool         commentLine   = prevPiece.isComment && prevLineStart == prev;
            if (!attrLine && !commentLine)
                break; // real code (or a trailing comment on a code line)
            target = prevLineStart;
        }
        return target;
    }

    void applyBlankBeforeDeclGroup(FormatModel& model, const uint32_t declLineStart, const uint32_t minBlank)
    {
        const uint32_t target = declGroupStart(model, declLineStart);
        const uint32_t prev   = model.prevPiece(target);
        if (prev == INVALID_PIECE)
            return;
        // No forced blank line right after an opening brace or before the
        // very first statement of a block.
        if (model.piece(prev).is(TokenId::SymLeftCurly))
            return;

        forceGapNewlines(model, target, minBlank + 1, false);
    }

    bool blockSpansLines(const FormatModel& model, const FormatBlock& block)
    {
        return model.lineStartOf(block.openPiece) != model.lineStartOf(block.closePiece);
    }

    // Blank lines before multi-line function / type definitions. Prototypes,
    // `=>` short forms, and one-line bodies keep stacking as written.
    void applyBlankLinesBetweenDefinitions(FormatModel& model)
    {
        const FormatOptions& options   = model.options();
        const uint32_t       wantFuncs = options.minBlankLinesBetweenFunctions;
        const uint32_t       wantTypes = options.minBlankLinesBetweenTypes;
        if (wantFuncs == 0 && wantTypes == 0)
            return;

        for (const FormatBlock& block : model.blocks())
        {
            if (block.exprLevel || !blockSpansLines(model, block))
                continue;

            uint32_t want = 0;
            switch (block.kind)
            {
                case FormatBlockKind::Function:
                    want = wantFuncs;
                    break;
                case FormatBlockKind::Struct:
                case FormatBlockKind::Enum:
                case FormatBlockKind::Interface:
                case FormatBlockKind::Impl:
                case FormatBlockKind::Namespace:
                    want = wantTypes;
                    break;
                default:
                    break;
            }
            if (want == 0)
                continue;

            applyBlankBeforeDeclGroup(model, model.lineStartOf(block.headPiece), want);
        }
    }

    // Blank line before a whole-line comment block that directly follows code
    // at the same nesting: comments open a new "paragraph".
    void applyBlankLinesBeforeComments(FormatModel& model)
    {
        const FormatOptions& options = model.options();
        if (options.minBlankLinesBeforeComments == 0)
            return;

        std::vector<uint32_t> lineStarts;
        model.collectLineStarts(lineStarts);

        for (const uint32_t lineStart : lineStarts)
        {
            const FormatPiece& piece = model.piece(lineStart);
            if (piece.removed || !piece.isComment)
                continue;

            const uint32_t prev = model.prevPiece(lineStart);
            if (prev == INVALID_PIECE)
                continue;
            const FormatPiece& prevPiece = model.piece(prev);
            // Only the first line of a comment block, after real code.
            if (prevPiece.isComment || prevPiece.is(TokenId::SymLeftCurly))
                continue;
            if (model.piece(model.lineStartOf(prev)).hasRole(FormatRoleE::AttrOpen))
                continue; // between an attribute and its declaration

            // The comment must introduce a statement (or close a block), not
            // annotate the middle of a wrapped expression.
            uint32_t nextCode = model.nextPiece(lineStart);
            while (nextCode != INVALID_PIECE && model.piece(nextCode).isComment)
                nextCode = model.nextPiece(nextCode);
            if (nextCode == INVALID_PIECE)
                continue;
            const FormatPiece& nextPiece = model.piece(nextCode);
            if (!nextPiece.is(TokenId::SymRightCurly) &&
                !nextPiece.roles.hasAny({FormatRoleE::StmtStart, FormatRoleE::CaseLabel, FormatRoleE::FieldDeclStart,
                                         FormatRoleE::EnumValueStart, FormatRoleE::AttrOpen, FormatRoleE::UsingStart,
                                         FormatRoleE::FuncDeclStart, FormatRoleE::TypeDeclStart}))
                continue;

            forceGapNewlines(model, lineStart, options.minBlankLinesBeforeComments + 1, false);
        }
    }

    // Blank line after the `}` of a multi-line block when another statement
    // follows: separates the block from the next "paragraph". `else`, `case`,
    // and closing braces stay attached.
    void applyBlankLinesAfterBlocks(FormatModel& model)
    {
        const FormatOptions& options = model.options();
        if (options.minBlankLinesAfterBlocks == 0)
            return;

        for (const FormatBlock& block : model.blocks())
        {
            if (block.exprLevel || !blockSpansLines(model, block))
                continue;

            const uint32_t next = model.nextPiece(block.closePiece);
            if (next == INVALID_PIECE || !model.gapHasNewline(next))
                continue;

            const FormatPiece& nextPiece = model.piece(next);
            const bool         wholeLineComment = nextPiece.isComment && model.lineStartOf(next) == next;
            if (!wholeLineComment &&
                !nextPiece.roles.hasAny({FormatRoleE::StmtStart, FormatRoleE::FieldDeclStart, FormatRoleE::EnumValueStart,
                                         FormatRoleE::AttrOpen, FormatRoleE::UsingStart, FormatRoleE::FuncDeclStart,
                                         FormatRoleE::TypeDeclStart}))
                continue;

            forceGapNewlines(model, next, options.minBlankLinesAfterBlocks + 1, false);
        }
    }
}

namespace FormatPass
{
    void blanks(FormatModel& model)
    {
        applyBlankLineAfterGlobalBlock(model);
        applyBlankLineAfterUsingBlock(model);
        applyBlankLinesBetweenDefinitions(model);
        applyBlankLinesBeforeComments(model);
        applyBlankLinesAfterBlocks(model);
    }
}

SWC_END_NAMESPACE();
