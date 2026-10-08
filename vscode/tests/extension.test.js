const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function extension(trusted, enabled = true)
{
    const clients = [], events = {}, subscriptions = [];
    let tasks = 0;
    const disposable = {dispose() {}};
    const vscode = {
        tasks: {registerTaskProvider: () => { ++tasks; return disposable; }},
        workspace: {
            isTrusted: trusted,
            getConfiguration: () => ({get: (key, fallback) => key === 'languageServer.enabled' ? enabled : fallback}),
            createFileSystemWatcher: () => disposable,
            onDidGrantWorkspaceTrust: fn => { events.trust = fn; return disposable; },
            onDidChangeConfiguration: fn => { events.configure = fn; return disposable; }
        },
        commands: {registerCommand: (name, fn) => { events.restart = fn; return disposable; }},
        window: {showErrorMessage: message => assert.fail(message)}
    };
    class LanguageClient
    {
        constructor(id, name, serverOptions, clientOptions)
        {
            Object.assign(this, {serverOptions, clientOptions});
            clients.push(this);
        }
        async start() { this.started = true; }
        async dispose() { this.disposed = true; }
    }
    const sandbox = {module: {exports: {}}, require: name =>
    {
        if (name === 'vscode') return vscode;
        if (name === './src/providers') return {TaskProvider: class {}};
        if (name === 'vscode-languageclient/node') return {LanguageClient, TransportKind: {ipc: 1}};
        assert.fail(name);
    }};
    vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../extension.js'), 'utf8'), sandbox);
    return {api: sandbox.module.exports, clients, events, vscode,
        context: {subscriptions, asAbsolutePath: value => path.resolve(__dirname, '..', value)}, tasks: () => tasks};
}

test('untrusted workspaces keep tasks but start no compiler-backed client', async () =>
{
    const harness = extension(false);
    await harness.api.activate(harness.context);
    assert.equal(harness.tasks(), 1);
    assert.equal(harness.clients.length, 0);
    harness.vscode.workspace.isTrusted = true;
    await harness.events.trust();
    assert.equal(harness.clients.length, 1);
    assert.ok(harness.clients[0].started);
    await harness.api.deactivate();
    assert.ok(harness.clients[0].disposed);
});

test('disabled language features do not start a client; restart disposes the previous client', async () =>
{
    const disabled = extension(true, false);
    await disabled.api.activate(disabled.context);
    assert.equal(disabled.clients.length, 0);
    const enabled = extension(true);
    await enabled.api.activate(enabled.context);
    await enabled.events.restart();
    assert.equal(enabled.clients.length, 2);
    assert.ok(enabled.clients[0].disposed);
    assert.ok(enabled.clients[1].started);
    assert.equal(enabled.clients[1].clientOptions.initializationOptions.compilerPath, 'swc');
    await enabled.api.deactivate();
});
