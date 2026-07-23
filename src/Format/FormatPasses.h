#pragma once

SWC_BEGIN_NAMESPACE();

class FormatModel;

// The formatting passes, in the order run() applies them. Every pass only
// acts when its options ask for a rewrite, so a fully "preserve" configuration
// renders the source byte-for-byte.
namespace FormatPass
{
    void sortUsing(FormatModel& model);      // sort-using-statements, merge-using-statements
    void attributes(FormatModel& model);     // attribute-placement, break-after-attribute, sort-attribute-arguments
    void braces(FormatModel& model);         // brace-style, compact-empty-braces, break-before-else
    void shortBlocks(FormatModel& model);    // allow-short-*-on-single-line
    void blanks(FormatModel& model);         // blank-line-after-using-block
    void spacing(FormatModel& model);        // all space-* options
    void indent(FormatModel& model);         // indent-* structural options
    void wrap(FormatModel& model);           // column-limit and break-* wrapping options
    void comments(FormatModel& model);       // comment rewriting options
    void align(FormatModel& model);          // align-* options

    void runAll(FormatModel& model);
}

SWC_END_NAMESPACE();
