// swc-options lex-only

// ============================================================================
// COMMENTS AT END OF FILE
// ============================================================================


// ============================================================================
// MULTI-LINE COMMENTS
// ============================================================================
// --- Valid multi-line comments ---
/* comment */
/* single line */
/**/
/* */
/*    */

/* multi
   line
   comment */

/*
 * Block comment style
 * with asterisks
 */

/*
Multiple
Lines
Here
*/

// --- Multi-line comments with code ---
int a = 5; /* comment */ int b = 10;
int c /* mid-statement comment */ = 15;
/* comment before */ int d = 20;

// --- Nested multi-line comments ---
/* outer /* inner */ still in outer */
/* level 1 /* level 2 /* level 3 */ back to 2 */ back to 1 */
/* /* */ */
/* /* /* */ */ */

/* outer comment
   /* nested comment
      /* deeply nested */
      still nested */
   outer again */

// --- Multi-line comments with special content ---
/* comment with // single-line marker */
/* comment with "strings" and 'chars' */
/* comment with 123 numbers */
/* comment with operators: + - * / % */
/* comment with symbols: !@#$%^&*() */

/*
 * Documentation comment
 * @param x the input value
 * @return the result
 */

/*
 * Multi-line with escape sequences (not interpreted):
 * \n \t \r \\ \" \'
 */

// --- Multi-line comments spanning many lines ---
/*
This is a very long comment
that spans many lines
and contains lots of text
line 5
line 6
line 7
line 8
line 9
line 10
and keeps going
*/

// --- Empty and minimal multi-line comments ---
/**/
/* */
/*  */
/*

*/

// --- Multi-line comments with asterisks ---
/****/
/*** comment ***/
/* *** */
/* * * * */
/*********************/

// --- Multi-line comments with mixed content ---
/*
code: int x = 5;
string: "hello world"
number: 123.456
operator: +=
comment: // this is inside
nested: /* this */ is inside
*/

// ============================================================================
// NESTED COMMENTS - ADVANCED CASES
// ============================================================================
// --- Deep nesting ---
/* 1 /* 2 /* 3 /* 4 /* 5 */ 4 */ 3 */ 2 */ 1 */

/* level 1
   /* level 2
      /* level 3
      end 3 */
   end 2 */
end 1 */

// --- Complex nesting patterns ---
/* /* */ /* */ */
/* /* a */ b /* c */ d */
/* x /* y /* z */ y */ x */

// ============================================================================
// SINGLE-LINE COMMENTS
// ============================================================================
// --- Valid single-line comments ---
// This is a comment
// Another comment
//
// Comment without space
// Comment with leading spaces
// Comment with trailing spaces
// 123456789
// !@#$%^&*()
// With "quotes" and 'apostrophes'
// With /* multi-line markers */
// With // double slashes

// --- Single-line comments with code ---
int x = 5; // comment after code
int y = 10;//no space before comment
// Comment before code
int z = 15;

// --- Empty and whitespace single-line comments ---
//
//
//
//

// --- Single-line comments with special characters ---
// TODO: implement this feature
// FIXME: bug here
// NOTE: important information
// HACK: temporary solution
// XXX: warning
// BUG: known issue

// --- Single-line comments with escape sequences (not interpreted) ---
// This is \n not a newline
// This is \t not a tab
// This is \" not an escaped quote
// This is \\ not an escaped backslash

// --- Single-line comments with URLs ---
// Https://example.com
// Http://www.test.org/path/to/resource
// File:///C:/path/to/file

// --- Single-line comments at end of file (no newline after) ---
// This comment has no newline after it

// ============================================================================
// MIXED COMMENT STYLES
// ============================================================================
// --- Single-line followed by multi-line ---
// Single line comment
/* multi line comment */

// --- Multi-line followed by single-line ---
/* multi line comment */
// Single line comment

// --- Comments with code between ---
// Comment 1
int x = 5;
/* comment 2 */
int y = 10;
// Comment 3

// --- Multiple comments in sequence ---
// Comment 1
// Comment 2
// Comment 3

/**/
/**/
/**/

// A
/* b */
// C
/* d */

// ============================================================================
// EDGE CASES
// ============================================================================
// --- Comments with comment-like strings inside ---
/* This // is not a single-line comment */
// This /* is not a multi-line comment start
/* This "/*" is in a string concept */
/* This "*/" is in a string concept */

// --- Comments at boundaries ---
/*start*/
/* end*/
/*start */
/* end */

// --- Almost-comments (not actually comments) ---
/ / not a comment (spaces between slashes)
/ * not a comment (space between slash and asterisk)
* / not a comment end (no opening)

// --- Comments with unusual spacing ---
// No space after slashes
/*no space after open*/
/*no space before close*/
/*nospaces*/

// --- Very long single-line comment ---
// This is a very long single-line comment that goes on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on and on

// --- Multi-line with only asterisks on some lines ---
/*
 *
 *
 *
 */

// --- Comments with tabs ---
// Tab after slashes
/*	tab in comment	*/
	// tab before comment
/* 	multiple	tabs	here	 */

// swc-expected-error@+ {{lex_err_unclosed_comment}}
/* This comment is never closed
