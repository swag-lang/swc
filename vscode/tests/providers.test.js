const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

class ProcessExecution
{
    constructor(process, args)
    {
        this.process = process;
        this.args = Array.from(args);
    }
}

class Task
{
    constructor(definition, scope, name, source, execution, matcher)
    {
        Object.assign(this, {definition, scope, name, source, execution, matcher});
        this.presentationOptions = {};
    }
}

class ShellExecution
{
    constructor(commandLine)
    {
        this.commandLine = commandLine;
    }
}

const vscode = {ProcessExecution, ShellExecution, Task, TaskScope: {Workspace: 2}, TaskGroup: {Build: 'build'}};
const sandbox = {module: {exports: {}}, require: name =>
{
    assert.equal(name, 'vscode');
    return vscode;
}};
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../src/providers.js'), 'utf8'), sandbox);
const {TaskProvider} = sandbox.module.exports;
const diagnosticArgs = ['--diagnostic-one-line', '--path-display', 'absolute', '--no-log-color'];

test('discovery returns three fresh tasks with current compiler arguments', () =>
{
    const provider = new TaskProvider();
    const first = provider.provideTasks();
    const second = provider.provideTasks();
    assert.equal(first.length, 3);
    assert.equal(second.length, 3);
    assert.notEqual(first[0], second[0]);
    assert.deepEqual(Array.from(first, task => task.name), ['build', 'rebuild', 'format']);
    assert.deepEqual(first[0].execution.args, ['build', '--workspace', '${workspaceFolder}', ...diagnosticArgs]);
    assert.deepEqual(first[1].execution.args, ['build', '--workspace', '${workspaceFolder}', '--rebuild', ...diagnosticArgs]);
    assert.deepEqual(first[2].execution.args, ['format', '--file', '${file}', ...diagnosticArgs]);
    for (const task of first)
    {
        assert.ok(task.execution instanceof ProcessExecution);
        assert.equal(task.execution.process, 'swc');
        assert.equal(task.matcher, '$swag');
    }
    assert.equal(first[0].group, vscode.TaskGroup.Build);
    assert.equal(first[1].group, vscode.TaskGroup.Build);
    assert.equal(first[2].group, undefined);
});

test('paths with spaces and shell syntax remain one process argument', () =>
{
    const task = new TaskProvider().provideTasks()[2];
    const file = 'C:\\work with spaces\\a&b;$(echo injected).swg';
    const expanded = task.execution.args.map(arg => arg.replace('${file}', file));
    assert.deepEqual(expanded, ['format', '--file', file, ...diagnosticArgs]);
});

test('configured tasks resolve their command while preserving their identity and scope', () =>
{
    const definition = {type: 'swag-build', command: 'rebuild'};
    const scope = {uri: {fsPath: 'C:\\work with spaces'}};
    const task = new TaskProvider().resolveTask({definition, scope, name: 'Rebuild this workspace'});
    assert.equal(task.definition, definition);
    assert.equal(task.scope, scope);
    assert.equal(task.name, 'Rebuild this workspace');
    assert.deepEqual(task.execution.args, ['build', '--workspace', '${workspaceFolder}', '--rebuild', ...diagnosticArgs]);
    assert.equal(new TaskProvider().resolveTask({definition: {command: 'unknown'}}), undefined);
});

test('problem matchers read current compiler locations and optional diagnostic identifiers', () =>
{
    const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '../package.json'), 'utf8'));
    for (const matcher of manifest.contributes.problemMatchers)
    {
        const pattern = matcher.pattern;
        for (const severity of ['error', 'warning'])
        {
            for (const id of ['', '[sema_err_unknown_symbol]'])
            {
                const match = new RegExp(pattern.regexp).exec(`C:\\work with spaces\\main.swg:12:7-18: ${severity}${id}: unknown symbol 'MissingType'`);
                assert.ok(match);
                assert.equal(match[pattern.file], 'C:\\work with spaces\\main.swg');
                assert.equal(match[pattern.line], '12');
                assert.equal(match[pattern.column], '7');
                assert.equal(match[pattern.endColumn], '18');
                assert.equal(match[pattern.severity], severity);
                assert.equal(match[pattern.message], "unknown symbol 'MissingType'");
            }
        }
    }
});
