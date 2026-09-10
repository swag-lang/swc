const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { before, test } = require('node:test');
const { Registry, parseRawGrammar, INITIAL } = require('vscode-textmate');
const { loadWASM, OnigScanner, OnigString } = require('vscode-oniguruma');

let grammar;
before(async () => {
    await loadWASM(fs.readFileSync(require.resolve('vscode-oniguruma/release/onig.wasm')));
    const grammarPath = path.join(__dirname, '../syntaxes/swag.tmLanguage.json');
    const registry = new Registry({
        onigLib: Promise.resolve({
            createOnigScanner: patterns => new OnigScanner(patterns),
            createOnigString: text => new OnigString(text),
        }),
        loadGrammar: async () => parseRawGrammar(fs.readFileSync(grammarPath, 'utf8'), grammarPath),
    });
    grammar = await registry.loadGrammar('source');
});

function scopesAt(line, position) {
    return grammar.tokenizeLine(line, INITIAL).tokens.find(token =>
        token.startIndex <= position && token.endIndex > position).scopes;
}

test('not is a control keyword before identifiers and parentheses', () => {
    for (const line of ['if not ready', 'not(ready)', 'let value = not ready']) {
        assert.ok(scopesAt(line, line.indexOf('not')).includes('keyword.control'), line);
    }
});

test('keyword spellings inside identifiers, strings and comments keep their context', () => {
    for (const line of ['notReady', 'notnot', '"not"', '// not', '/* not */']) {
        const scopes = scopesAt(line, line.indexOf('not'));
        assert.ok(!scopes.includes('keyword.control'), line);
        assert.ok(!scopes.includes('invalid'), line);
    }
});

const tokenDefinitions = fs.readFileSync(path.join(__dirname, '../../src/Compiler/Lexer/Tokens.Def.inc'), 'utf8');
const tokens = [...tokenDefinitions.matchAll(/^SWC_TOKEN_DEF\(\w+, "([^"\n]+)", ([^)]+)\)/gm)]
    .map(([, spelling, flags]) => ({ spelling, flags }));

test('every compiler keyword, type, modifier and intrinsic has a complete syntax scope', () => {
    const failures = [];
    for (const { spelling, flags } of tokens) {
        if (!/TokenIdKindE::(?:Keyword|Type|Modifier|Compiler|Intrinsic)\b/.test(flags)) continue;
        const line = spelling + (spelling.startsWith('Swag.') ? '()' : ' ');
        const start = spelling.startsWith('Swag.') ? 5 : 0;
        for (let offset = start; offset < spelling.length; offset++) {
            const scopes = scopesAt(line, offset);
            const expected = spelling.startsWith('Swag.')
                ? /^(entity.name.function.intrinsic|entity.name.tag|constant.character.escape)$/
                : /^(keyword(?:\.|$)|storage\.|constant\.|meta.preprocessor|entity.name.function)/;
            if (scopes.includes('invalid') || !scopes.some(scope => expected.test(scope))) {
                failures.push(`${spelling}: ${scopes.join(', ')}`);
                break;
            }
        }
    }
    assert.deepEqual(failures, []);
});

test('compiler token prefixes do not color unknown directives as builtins', () => {
    for (const spelling of ['#typeofExtra', '#lineExtra', '#codeExtra', '#uniq0Extra', '#uniq10']) {
        for (let offset = 0; offset < spelling.length; offset++) {
            assert.ok(scopesAt(spelling, offset).includes('invalid'), spelling);
        }
    }
});

test('intrinsic member names require an accessor and a complete identifier', () => {
    for (const line of ['value.countExtra', 'value.bufferExtra', 'item0', 'myitem0']) {
        assert.ok(!scopesAt(line, line.length - 1).includes('constant.character.escape'), line);
    }
    for (const line of ['value.count', 'value.buffer', 'value.item0']) {
        assert.ok(scopesAt(line, line.length - 1).includes('constant.character.escape'), line);
    }
});

test('the language reference catalog covers all compiler keywords and intrinsics', () => {
    const reference = fs.readFileSync(path.join(__dirname,
        '../../bin/reference/modules/language/src/002_007_keywords.swg'), 'utf8');
    const catalog = new Set(reference.match(/(?:Swag\.|#|\.)?[A-Za-z_]\w*/g));
    const missing = tokens.filter(({ spelling, flags }) =>
        /TokenIdKindE::(?:Keyword|Type|Modifier|Compiler|Intrinsic)\b/.test(flags) && !catalog.has(spelling));
    assert.deepEqual(missing, []);
});
