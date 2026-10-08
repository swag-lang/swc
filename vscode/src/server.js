const {createConnection, ProposedFeatures, TextDocuments, TextDocumentSyncKind} = require('vscode-languageserver/node');
const {TextDocument} = require('vscode-languageserver-textdocument');
const {pathToFileURL, fileURLToPath} = require('node:url');
const {pathKey} = require('./compiler');
const {Session} = require('./session');
const {tokenTypes, tokenModifiers} = require('./semantic');

function startServer()
{
    const connection = createConnection(ProposedFeatures.all);
    const documents = new TextDocuments(TextDocument);
    const published = new Set();
    let session;
    let lastError;
    let refreshTokens = false, refreshHints = false;

    connection.onInitialize(params =>
    {
        refreshTokens = !!params.capabilities.workspace?.semanticTokens?.refreshSupport;
        refreshHints = !!params.capabilities.workspace?.inlayHint?.refreshSupport;
        session = new Session(documents, params.initializationOptions ?? {}, {
            error: message =>
            {
                connection.console.error(message);
                const summary = message.split('\n')[0];
                if (lastError !== summary) connection.window.showErrorMessage(summary);
                lastError = summary;
            },
            analyzed: (snapshot, output, versions) =>
            {
                lastError = undefined;
                const open = new Map(versions.map(document => [pathKey(fileURLToPath(document.uri)), document]));
                const diagnostics = new Map();
                for (const source of snapshot.files.values()) diagnostics.set(source.uri, []);
                for (const line of output.split(/\r?\n/))
                {
                    const match = /^(.*):(\d+):(\d+)(?:-(\d+))?: (warning|error)(?:\[([^\]]+)\])?: (.*)$/.exec(line);
                    if (!match) continue;
                    const uri = pathToFileURL(match[1]).href;
                    if (!diagnostics.has(uri)) diagnostics.set(uri, []);
                    // The compiler's one-line format uses display columns, including expanded tabs.
                    // Convert against the analyzed buffer, never against a newer editor document.
                    const source = snapshot.source(uri);
                    const original = open.get(pathKey(fileURLToPath(uri)));
                    const lineNumber = Number(match[2]) - 1;
                    const column = value => displayColumn(source?.document ?? original, lineNumber, Number(value) - 1);
                    const start = column(match[3]);
                    diagnostics.get(uri).push({range: {start: {line: lineNumber, character: start},
                        end: {line: lineNumber, character: Math.max(start + 1, column(match[4] || match[3]))}},
                        severity: match[5] === 'error' ? 1 : 2, code: match[6], source: 'swag', message: match[7]});
                }
                for (const [uri, items] of diagnostics)
                {
                    const document = open.get(pathKey(fileURLToPath(uri)));
                    // Keep unopened dependency diagnostics out of the Problems panel.
                    if (document && documents.get(document.uri))
                    {
                        connection.sendDiagnostics({uri: document.uri, version: document.version, diagnostics: items});
                        published.add(document.uri);
                    }
                }
                if (refreshTokens) connection.languages.semanticTokens.refresh().catch(() => {});
                if (refreshHints) connection.languages.inlayHint.refresh().catch(() => {});
            }
        });
        return {serverInfo: {name: 'Swag Language Server', version: '1'}, capabilities: {
            textDocumentSync: TextDocumentSyncKind.Incremental,
            hoverProvider: true, definitionProvider: true, referencesProvider: true,
            documentSymbolProvider: true, inlayHintProvider: true,
            semanticTokensProvider: {legend: {tokenTypes, tokenModifiers}, full: true}
        }};
    });

    function invalidate()
    {
        session?.invalidate();
        for (const uri of published)
            connection.sendDiagnostics({uri, version: documents.get(uri)?.version, diagnostics: []});
        published.clear();
    }

    async function query(params, cancellation, fn, empty)
    {
        if (!documents.get(params.textDocument.uri) || cancellation.isCancellationRequested) return empty;
        return new Promise((resolve, reject) =>
        {
            const subscription = cancellation.onCancellationRequested(() => resolve(empty));
            session.snapshot(params.textDocument.uri)
                .then(snapshot => snapshot && !cancellation.isCancellationRequested ? fn(snapshot) : empty)
                .then(resolve, reject).finally(() => subscription.dispose());
        });
    }

    documents.onDidChangeContent(invalidate);
    documents.onDidClose(invalidate);
    connection.onDidChangeWatchedFiles(params =>
    {
        // Dependency API publication is an analysis output, not a new source edit.
        if (params.changes.some(change => !/(?:^|[\\/])(?:\.output|\.tmp|\.dep|\.git|node_modules)(?:[\\/]|$)/.test(fileURLToPath(change.uri))))
            invalidate();
    });
    connection.onHover((p, t) => query(p, t, s => s.hover(p.textDocument.uri, p.position), null));
    connection.onDefinition((p, t) => query(p, t, s => s.definition(p.textDocument.uri, p.position), null));
    connection.onReferences((p, t) => query(p, t, s => s.references(p.textDocument.uri, p.position, p.context.includeDeclaration), []));
    connection.onDocumentSymbol((p, t) => query(p, t, s => s.symbols(p.textDocument.uri), []));
    connection.languages.inlayHint.on((p, t) => query(p, t, s => s.hints(p.textDocument.uri, p.range), []));
    connection.languages.semanticTokens.on((p, t) => query(p, t, s => s.tokens(p.textDocument.uri), {data: []}));
    connection.onShutdown(() => session?.dispose());
    connection.onExit(() => session?.dispose());
    connection.onDidChangeConfiguration(invalidate);
    for (const signal of ['SIGINT', 'SIGTERM'])
        process.once(signal, async () => { await session?.dispose(); process.exit(0); });
    process.once('disconnect', () => session?.dispose());
    documents.listen(connection);
    connection.listen();
}

function displayColumn(document, line, column)
{
    if (!document) return Math.max(0, column);
    const text = document.getText({start: {line, character: 0}, end: {line: line + 1, character: 0}});
    let display = 0, offset = 0;
    for (const character of text)
    {
        if (display >= column || character === '\r' || character === '\n') break;
        display += character === '\t' ? 4 - display % 4 : 1;
        offset += character.length;
    }
    return offset;
}

if (require.main === module) startServer();
module.exports = {displayColumn};
