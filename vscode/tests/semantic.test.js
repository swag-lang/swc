const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const {pathToFileURL} = require('node:url');
const {TextDocument} = require('vscode-languageserver-textdocument');
const {SemanticSnapshot, Source} = require('../src/semantic');
const {displayColumn} = require('../src/server');
const {overlayBuffer} = require('../src/compiler');

const filename = path.resolve('example with spaces.swg');
const uri = pathToFileURL(filename).href;

test('compiler byte ranges become UTF-16 positions across CRLF and non-BMP text', () =>
{
    const source = new Source({path: filename, text: '// café 😀\r\nlet value = "😀"; value\n'});
    const bytes = source.bytes.indexOf('value', source.bytes.indexOf(';'));
    assert.deepEqual(source.range(bytes, 5), {start: {line: 1, character: 18}, end: {line: 1, character: 23}});
    assert.equal(source.offset(source.bytes.indexOf(Buffer.from('😀')) + 1), undefined);
    assert.equal(source.offset(-1), undefined);
    assert.equal(displayColumn(source.document, 1, 17), 18);
    const tabs = TextDocument.create(uri, 'swag', 1, '\t😀\tvalue');
    assert.equal(displayColumn(tabs, 0, 8), 4);
});

test('definitions and references use semantic identity, preserving shadowed names', () =>
{
    const text = 'value value value value';
    const occurrence = (start, declaration, target) => ({start, length: 5, name: 'value', kind: 'variable', type: 's32',
        declaration, readonly: true, inferred: declaration, definition: {path: filename, start: target, length: 5}});
    const snapshot = new SemanticSnapshot({files: [{path: filename, text, occurrences: [
        occurrence(0, true, 0), occurrence(6, false, 0), occurrence(12, true, 12), occurrence(18, false, 12)
    ]}]});
    assert.equal(snapshot.definition(uri, {line: 0, character: 19}).range.start.character, 12);
    assert.deepEqual(snapshot.references(uri, {line: 0, character: 1}, false).map(item => item.range.start.character), [6]);
    assert.equal(snapshot.hints(uri, {start: {line: 0, character: 0}, end: {line: 0, character: 23}}).length, 2);
    assert.equal(snapshot.symbols(uri).length, 2);
    assert.match(snapshot.hover(uri, {line: 0, character: 7}).contents.value, /value: s32/);
    assert.deepEqual(snapshot.tokens(uri).data, [0, 0, 5, 7, 3, 0, 6, 5, 7, 2, 0, 6, 5, 7, 3, 0, 6, 5, 7, 2]);
    assert.equal(snapshot.definition(uri, {line: 0, character: 5}), null);
});

test('ambiguous instantiated types do not choose an arbitrary definition or hint', () =>
{
    const occurrence = type => ({start: 0, length: 5, name: 'value', kind: 'variable', type,
        definition: {path: filename, start: 0, length: 5}});
    const snapshot = new SemanticSnapshot({files: [{path: filename, text: 'value',
        occurrences: [occurrence('s32'), occurrence('string'), occurrence('string')]}]});
    assert.equal(snapshot.hover(uri, {line: 0, character: 0}), null);
    assert.deepEqual(snapshot.tokens(uri), {data: []});
});

test('overlay lengths count UTF-8 bytes and preserve empty buffers', () =>
{
    const documents = [TextDocument.create(uri, 'swag', 2, 'é😀\n'), TextDocument.create(pathToFileURL(path.resolve('empty.swg')).href, 'swag', 3, '')];
    const buffer = overlayBuffer(documents);
    let offset = buffer.indexOf('\n') + 1;
    const read = () =>
    {
        const end = buffer.indexOf('\n', offset);
        const size = Number(buffer.toString('utf8', offset, end));
        offset = end + 1;
        const value = buffer.toString('utf8', offset, offset + size);
        offset += size;
        return value;
    };
    read();
    assert.equal(read(), 'é😀\n');
    read();
    assert.equal(read(), '');
    assert.equal(offset, buffer.length);
});
