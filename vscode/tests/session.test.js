const test = require('node:test');
const assert = require('node:assert/strict');
const {TextDocument} = require('vscode-languageserver-textdocument');
const {Session} = require('../src/session');

const uri = 'file:///example.swg';
const tick = () => new Promise(resolve => setImmediate(resolve));

test('requests share analysis; edits cancel it and reject stale publication', async () =>
{
    let document = TextDocument.create(uri, 'swag', 1, 'old');
    const jobs = [], published = [], errors = [];
    const backend = {
        projectFor: async () => ({key: 'project'}),
        analyze: (project, documents, options, signal) => new Promise(resolve => jobs.push({documents, signal, resolve}))
    };
    const session = new Session({all: () => [document]}, {analysisDelay: 10000},
        {analyzed: snapshot => published.push(snapshot), error: error => errors.push(error)}, backend);
    try
    {
        const first = session.snapshot(uri), shared = session.snapshot(uri);
        await tick();
        assert.equal(jobs.length, 1);
        document = TextDocument.update(document, [{text: 'new'}], 2);
        session.invalidate();
        const next = session.snapshot(uri);
        assert.equal(jobs[0].signal.aborted, true);
        assert.equal(jobs[0].documents[0].getText(), 'old');
        jobs[0].resolve({snapshot: {files: []}, output: ''});
        assert.equal(await first, undefined);
        assert.equal(await shared, undefined);
        await tick();
        assert.equal(jobs.length, 2);
        assert.equal(jobs[1].documents[0].getText(), 'new');
        jobs[1].resolve({snapshot: {files: []}, output: ''});
        assert.ok(await next);
        assert.equal(published.length, 1);
        assert.deepEqual(errors, []);
    }
    finally { await session.dispose(); }
});

test('different modules are serialized and shutdown cancels running analysis', async () =>
{
    const jobs = [];
    const backend = {
        projectFor: async value => ({key: value}),
        analyze: (project, docs, options, signal) => new Promise(resolve =>
        {
            jobs.push(project.key);
            signal.addEventListener('abort', () => resolve(undefined));
        })
    };
    const session = new Session({all: () => []}, {}, {analyzed: () => assert.fail(), error: () => assert.fail()}, backend);
    const first = session.snapshot('a'), second = session.snapshot('b');
    await tick();
    assert.deepEqual(jobs, ['a']);
    await session.dispose();
    assert.equal(await first, undefined);
    assert.equal(await second, undefined);
    assert.deepEqual(jobs, ['a']);
});
