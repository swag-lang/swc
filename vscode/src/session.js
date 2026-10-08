const {TextDocument} = require('vscode-languageserver-textdocument');
const compiler = require('./compiler');
const {SemanticSnapshot} = require('./semantic');

// One compilation at a time per server. Requests share the same versioned analysis;
// editing cancels obsolete work, while cancelling one hover does not cancel other readers.
class Session
{
    constructor(documents, options, events, backend = compiler)
    {
        Object.assign(this, {documents, options, events, backend});
        this.revision = 0;
        this.pending = new Map();
        this.queue = Promise.resolve();
        this.disposed = false;
    }

    invalidate()
    {
        ++this.revision;
        this.active?.abort();
        this.pending.clear();
        clearTimeout(this.timer);
        if (!this.disposed)
            this.timer = setTimeout(() => this.refresh(), this.options.analysisDelay ?? 500);
    }

    async refresh()
    {
        const revision = this.revision;
        for (const document of this.documents.all())
        {
            if (revision !== this.revision || this.disposed) return;
            await this.snapshot(document.uri);
        }
    }

    async snapshot(uri)
    {
        const revision = this.revision;
        if (this.disposed) return undefined;
        try
        {
            const project = await this.backend.projectFor(uri);
            if (revision !== this.revision || this.disposed) return undefined;
            if (!this.pending.has(project.key))
            {
                const documents = this.documents.all().map(document =>
                    TextDocument.create(document.uri, 'swag', document.version, document.getText()));
                const job = this.queue.then(async () =>
                {
                    if (revision !== this.revision || this.disposed) return undefined;
                    const controller = new AbortController();
                    this.active = controller;
                    const timeout = setTimeout(() => controller.abort(), this.options.analysisTimeout ?? 60000);
                    try
                    {
                        const result = await this.backend.analyze(project, documents, this.options, controller.signal);
                        if (revision !== this.revision || this.disposed || !result) return undefined;
                        const semantic = new SemanticSnapshot(result.snapshot);
                        this.events.analyzed(semantic, result.output, documents);
                        return semantic;
                    }
                    catch (error)
                    {
                        if (revision === this.revision && !this.disposed)
                            this.events.error(controller.signal.aborted ? 'Swag analysis exceeded its time limit' : error.message);
                        return undefined;
                    }
                    finally
                    {
                        clearTimeout(timeout);
                        if (this.active === controller) this.active = undefined;
                    }
                });
                this.pending.set(project.key, job);
                this.queue = job.then(() => undefined, () => undefined);
            }
            const result = await this.pending.get(project.key);
            return revision === this.revision && !this.disposed ? result : undefined;
        }
        catch (error)
        {
            if (revision === this.revision && !this.disposed) this.events.error(error.message);
            return undefined;
        }
    }

    async dispose()
    {
        this.disposed = true;
        this.invalidate();
        await this.queue;
    }
}

module.exports = {Session};
