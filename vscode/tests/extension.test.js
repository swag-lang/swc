const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

test('activation registers the build task provider and nothing else', () =>
{
    const registered = [], subscriptions = [];
    const disposable = {dispose() {}};
    const vscode = {
        tasks: {registerTaskProvider: (type, provider) => { registered.push({type, provider}); return disposable; }}
    };
    class TaskProvider {}
    const sandbox = {module: {exports: {}}, require: name =>
    {
        if (name === 'vscode') return vscode;
        if (name === './src/providers') return {TaskProvider};
        assert.fail(name);
    }};
    vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../extension.js'), 'utf8'), sandbox);

    sandbox.module.exports.activate({subscriptions});
    assert.equal(registered.length, 1);
    assert.equal(registered[0].type, 'swag-build');
    assert.ok(registered[0].provider instanceof TaskProvider);
    assert.deepEqual(subscriptions, [disposable]);
    sandbox.module.exports.deactivate();
});

test('the manifest ships no runtime dependency and no compiler-backed setting', () =>
{
    const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '../package.json'), 'utf8'));
    assert.equal(manifest.dependencies, undefined);
    assert.equal(manifest.contributes.configuration, undefined);
    assert.equal(manifest.contributes.commands, undefined);
    assert.deepEqual(manifest.activationEvents, ['onTaskType:swag-build']);
});
