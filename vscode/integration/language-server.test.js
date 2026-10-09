const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const {spawn} = require('node:child_process');
const {pathToFileURL, fileURLToPath} = require('node:url');
const {createMessageConnection, StreamMessageReader, StreamMessageWriter} = require('vscode-jsonrpc/node');
const {analyze, projectFor, pathKey} = require('../src/compiler');
const {SemanticSnapshot} = require('../src/semantic');
const {TextDocument} = require('vscode-languageserver-textdocument');

test('LSP uses compiler semantics across files and unsaved document versions', {timeout: 39000}, async () =>
{
    assert.ok(process.env.SWAG_TEST_COMPILER, 'Set SWAG_TEST_COMPILER to the checkout-local compiler');
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'swag-lsp-test-'));
    let child, connection;
    try
    {
        await fs.mkdir(path.join(root, 'src'));
        await fs.writeFile(path.join(root, 'module.swg'), '// Language server integration module.\n');
        const library = path.join(root, 'src', 'library.swg');
        await fs.writeFile(library, 'func choose(value: s32)->s32 => value\nfunc choose(value: string)->string => value\n');
        const file = path.join(root, 'src', 'main.swg');
        const initial = 'func inspect()\n{\n    let result = choose(42)\n    discard result\n}\n';
        await fs.writeFile(file, initial);
        const uri = pathToFileURL(file).href.replace(/^file:\/\/\/([A-Z]):/, (_, drive) => `file:///${drive.toLowerCase()}%3A`);
        const indexed = await analyze(await projectFor(uri), [TextDocument.create(uri, 'swag', 1, initial)],
            {compilerPath: process.env.SWAG_TEST_COMPILER}, new AbortController().signal);
        const indexedPaths = indexed.snapshot.files.map(source => pathKey(source.path));
        assert.ok(indexedPaths.every(filePath => filePath === pathKey(root) || filePath.startsWith(`${pathKey(root)}/`)),
            `the editor index should contain the analyzed module only: ${indexedPaths.join(', ')}`);
        child = spawn(process.execPath, [path.join(__dirname, '../src/server.js'), '--stdio'], {windowsHide: true});
        let stderr = '';
        child.stderr.on('data', chunk => { stderr += chunk; });
        connection = createMessageConnection(new StreamMessageReader(child.stdout), new StreamMessageWriter(child.stdin));
        const messages = [], diagnostics = [];
        connection.onNotification('window/showMessage', value => messages.push(value.message));
        connection.onRequest('window/showMessageRequest', value => { messages.push(value.message); return null; });
        connection.onNotification('textDocument/publishDiagnostics', value => diagnostics.push(value));
        connection.listen();
        const initialized = await connection.sendRequest('initialize', {processId: process.pid, rootUri: pathToFileURL(root).href,
            capabilities: {}, initializationOptions: {compilerPath: process.env.SWAG_TEST_COMPILER, analysisDelay: 10000}});
        assert.equal(initialized.capabilities.definitionProvider, true);
        connection.sendNotification('initialized', {});
        connection.sendNotification('textDocument/didOpen', {textDocument: {uri, languageId: 'swag', version: 1, text: initial}});
        const request = (method, extras = {}) => connection.sendRequest(`textDocument/${method}`, {textDocument: {uri}, ...extras});
        const use = {line: 3, character: 13};
        const hover = await request('hover', {position: use});
        assert.match(hover?.contents.value ?? '', /result: s32/, messages.join('\n') + stderr);
        const definition = await request('definition', {position: use});
        assert.equal(pathKey(fileURLToPath(definition.uri)), pathKey(file));
        assert.deepEqual(definition.range, {start: {line: 2, character: 8}, end: {line: 2, character: 14}});
        const functionDefinition = await request('definition', {position: {line: 2, character: 19}});
        assert.ok(functionDefinition, messages.join('\n'));
        assert.equal(pathKey(fileURLToPath(functionDefinition.uri)), pathKey(library));
        assert.equal(functionDefinition.range.start.line, 0);
        const references = await request('references', {position: use, context: {includeDeclaration: true}});
        assert.equal(references.length, 2);
        const hints = await request('inlayHint', {range: {start: {line: 0, character: 0}, end: {line: 5, character: 0}}});
        assert.ok(hints.some(item => item.label === ': s32'));
        assert.ok((await request('semanticTokens/full')).data.length > 0);
        assert.ok((await request('documentSymbol')).some(item => item.name === 'inspect'));

        connection.sendNotification('textDocument/didChange', {textDocument: {uri, version: 2}, contentChanges: [
            {range: {start: {line: 2, character: 24}, end: {line: 2, character: 26}}, text: '"😀"'}]});
        assert.match((await request('hover', {position: use}))?.contents.value ?? '', /result: string/, messages.join('\n'));
        assert.equal((await request('definition', {position: {line: 2, character: 19}}))?.range.start.line, 1);
        assert.equal(await fs.readFile(file, 'utf8'), initial);

        connection.sendNotification('textDocument/didChange', {textDocument: {uri, version: 3}, contentChanges: [{text: initial.replace('42', 'true')}]});
        assert.equal(await request('hover', {position: use}), null);
        assert.ok(diagnostics.some(item => item.uri === uri && item.version === 3 && item.diagnostics.some(diagnostic => diagnostic.severity === 1)));
        connection.sendNotification('textDocument/didChange', {textDocument: {uri, version: 4}, contentChanges: [{text: initial}]});
        assert.ok(await request('hover', {position: use}));
        assert.equal(diagnostics.filter(item => item.uri === uri).at(-1).diagnostics.length, 0);
        connection.sendNotification('textDocument/didClose', {textDocument: {uri}});
        await connection.sendRequest('shutdown');
        connection.sendNotification('exit');
        await new Promise(resolve => child.once('close', resolve));
        assert.deepEqual(messages, []);
    }
    finally
    {
        connection?.dispose();
        if (child && child.exitCode === null)
        {
            const closed = new Promise(resolve => child.once('close', resolve));
            child.kill();
            await closed;
        }
        await fs.rm(root, {recursive: true, force: true});
    }
});

test('implicit propagation in a Swag.Propagate body becomes a try hint', {timeout: 39000}, async () =>
{
    assert.ok(process.env.SWAG_TEST_COMPILER);
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'swag-propagate-editor-'));
    try
    {
        const file = path.join(root, 'example.swgs');
        const uri = pathToFileURL(file).href;
        const text = 'func load()->s32 fail => 1\n#[Swag.Propagate]\nfunc sum()->s32 fail\n{\n    let a = load()\n    return a + (catch load())\n}\n#main { discard catch sum() }\n';
        await fs.writeFile(file, text);
        const result = await analyze(await projectFor(uri), [TextDocument.create(uri, 'swag', 1, text)],
            {compilerPath: process.env.SWAG_TEST_COMPILER}, new AbortController().signal);
        assert.equal(result.snapshot.complete, true, result.output);
        const source = result.snapshot.files.find(item => item.path.replaceAll('\\', '/') === file.replaceAll('\\', '/'));
        assert.deepEqual(source?.propagations, [text.indexOf('load()', text.indexOf('let a'))], result.output);
        const hints = new SemanticSnapshot(result.snapshot).hints(uri, {start: {line: 0, character: 0}, end: {line: 8, character: 0}});
        assert.deepEqual(hints.filter(hint => hint.label === 'try').map(hint => hint.position), [{line: 4, character: 12}]);
    }
    finally { await fs.rm(root, {recursive: true, force: true}); }
});

test('standalone scripts use compiler script setup and unsaved buffers', {timeout: 39000}, async () =>
{
    assert.ok(process.env.SWAG_TEST_COMPILER);
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'swag-script-editor-'));
    try
    {
        const file = path.join(root, 'example.swgs');
        const uri = pathToFileURL(file).href;
        const text = 'func answer()->s32 => 42\n#main { let value = answer(); discard value }\n';
        await fs.writeFile(file, text);
        const edited = text.replace('s32 => 42', 'string => "hello"');
        const result = await analyze(await projectFor(uri), [TextDocument.create(uri, 'swag', 1, edited)],
            {compilerPath: process.env.SWAG_TEST_COMPILER}, new AbortController().signal);
        assert.equal(result.snapshot.complete, true, result.output);
        const source = result.snapshot.files.find(item => item.path.replaceAll('\\', '/') === file.replaceAll('\\', '/'));
        assert.equal(source?.text, edited);
        assert.ok(source.occurrences.some(item => item.name === 'value' && item.type === 'string'), result.output);
        assert.equal(await fs.readFile(file, 'utf8'), text);
    }
    finally { await fs.rm(root, {recursive: true, force: true}); }
});
