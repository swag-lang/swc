const {TextDocument} = require('vscode-languageserver-textdocument');
const {pathKey, pathToFileURL} = require('./compiler');

const tokenTypes = ['namespace', 'type', 'struct', 'interface', 'enum', 'enumMember', 'function', 'variable', 'parameter', 'property'];
const tokenModifiers = ['declaration', 'readonly'];
const symbolKinds = {namespace: 3, type: 5, struct: 23, interface: 11, enum: 10, enumMember: 22, function: 12, variable: 13, parameter: 13, property: 7};
const implicitTryTooltip = 'Propagates its error: the function has #[Swag.Propagate]';

class Source
{
    constructor(file)
    {
        this.uri = pathToFileURL(file.path).href;
        this.document = TextDocument.create(this.uri, 'swag', 0, file.text);
        // Compiler offsets are UTF-8 bytes; LSP positions count UTF-16 code units.
        this.bytes = Buffer.from(file.text);
        this.lines = [0];
        for (let i = 0; i < this.bytes.length; ++i)
        {
            if (this.bytes[i] === 10) this.lines.push(i + 1);
            else if (this.bytes[i] === 13 && this.bytes[i + 1] !== 10) this.lines.push(i + 1);
        }
        this.occurrences = [];
        this.propagations = [];
    }

    offset(byte)
    {
        if (!Number.isInteger(byte) || byte < 0 || byte > this.bytes.length || (this.bytes[byte] & 0xc0) === 0x80)
            return undefined;
        let low = 0, high = this.lines.length;
        while (low + 1 < high)
        {
            const mid = (low + high) >>> 1;
            if (this.lines[mid] <= byte) low = mid;
            else high = mid;
        }
        return this.document.offsetAt({line: low, character: 0}) + this.bytes.toString('utf8', this.lines[low], byte).length;
    }

    range(start, length)
    {
        const first = this.offset(start), last = this.offset(start + length);
        if (first === undefined || last === undefined) return undefined;
        return {start: this.document.positionAt(first), end: this.document.positionAt(last)};
    }

    at(position)
    {
        const offset = this.document.offsetAt(position);
        let low = 0, high = this.occurrences.length;
        while (low < high)
        {
            const middle = (low + high) >>> 1;
            if (this.occurrences[middle].offset <= offset) low = middle + 1;
            else high = middle;
        }
        const item = this.occurrences[low - 1];
        return item && offset < item.end ? item : undefined;
    }
}

class SemanticSnapshot
{
    constructor(snapshot)
    {
        this.files = new Map(snapshot.files.map(file => [pathKey(file.path), new Source(file)]));
        for (const file of snapshot.files)
        {
            const source = this.files.get(pathKey(file.path));
            const candidates = new Map();
            for (const item of file.occurrences)
            {
                const range = source.range(item.start, item.length);
                const target = this.files.get(pathKey(item.definition.path));
                const targetRange = target?.range(item.definition.start, item.definition.length);
                if (!range || !targetRange || !tokenTypes.includes(item.kind)) continue;
                const identity = `${pathKey(item.definition.path)}:${item.definition.start}`;
                const previous = candidates.get(item.start);
                // Multiple instantiations at one written position have no unique answer.
                if (previous && (previous.identity !== identity || previous.type !== item.type))
                    candidates.set(item.start, {ambiguous: true});
                else if (!previous)
                    candidates.set(item.start, {...item, range, identity,
                        offset: source.offset(item.start), end: source.offset(item.start + item.length),
                        location: {uri: target.uri, range: targetRange}});
            }
            source.occurrences = [...candidates.values()].filter(item => !item.ambiguous).sort((a, b) => a.offset - b.offset);
            // Fallible expressions a '#[Swag.Propagate]' body reads as an unwritten 'try'.
            source.propagations = (file.propagations ?? []).map(byte => source.offset(byte))
                .filter(offset => offset !== undefined).sort((a, b) => a - b);
        }
    }

    source(uri)
    {
        const {fileURLToPath} = require('node:url');
        return this.files.get(pathKey(fileURLToPath(uri)));
    }

    hover(uri, position)
    {
        const item = this.source(uri)?.at(position);
        if (!item) return null;
        const signature = `${item.name}${item.type ? ': ' + item.type : ''}`;
        const fence = '`'.repeat(Math.max(3, ...[...signature.matchAll(/`+/g)].map(match => match[0].length + 1)));
        return {contents: {kind: 'markdown', value: `${fence}swag\n${signature}\n${fence}`}, range: item.range};
    }

    definition(uri, position)
    {
        return this.source(uri)?.at(position)?.location ?? null;
    }

    references(uri, position, includeDeclaration)
    {
        const symbol = this.source(uri)?.at(position);
        if (!symbol) return [];
        return [...this.files.values()].flatMap(file => file.occurrences
            .filter(item => item.identity === symbol.identity && (includeDeclaration || !item.declaration))
            .map(item => ({uri: file.uri, range: item.range})));
    }

    symbols(uri)
    {
        return (this.source(uri)?.occurrences ?? []).filter(item => item.declaration).map(item =>
            ({name: item.name, detail: item.type, kind: symbolKinds[item.kind], range: item.range, selectionRange: item.range}));
    }

    hints(uri, range)
    {
        const source = this.source(uri);
        if (!source) return [];
        const start = source.document.offsetAt(range.start), end = source.document.offsetAt(range.end);
        let low = 0, high = source.occurrences.length;
        while (low < high)
        {
            const middle = (low + high) >>> 1;
            if (source.occurrences[middle].end < start) low = middle + 1;
            else high = middle;
        }
        const hints = [];
        for (let i = low; i < source.occurrences.length && source.occurrences[i].end <= end; ++i)
        {
            const item = source.occurrences[i];
            if (item.inferred && item.type)
                hints.push({position: item.range.end, label: `: ${item.type}`, kind: 1, paddingLeft: true});
        }
        for (const offset of source.propagations)
        {
            if (offset >= start && offset <= end)
                hints.push({position: source.document.positionAt(offset), label: 'try', paddingRight: true, tooltip: implicitTryTooltip});
        }
        return hints;
    }

    tokens(uri)
    {
        const data = [];
        let previousLine = 0, previousCharacter = 0;
        for (const item of this.source(uri)?.occurrences ?? [])
        {
            const {start, end} = item.range;
            if (start.line !== end.line) continue;
            data.push(start.line - previousLine, start.line === previousLine ? start.character - previousCharacter : start.character,
                end.character - start.character, tokenTypes.indexOf(item.kind), (item.declaration ? 1 : 0) | (item.readonly ? 2 : 0));
            previousLine = start.line;
            previousCharacter = start.character;
        }
        return {data};
    }
}

module.exports = {SemanticSnapshot, Source, tokenTypes, tokenModifiers};
