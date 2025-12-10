function parse() {
    function parseMeta(meta) {
        if (!meta) return null;

        const result = {};
        const parts = meta.split(";");

        for (const part of parts) {
            const [key, value] = part.split("=");
            if (key && value) {
                result[key.trim()] = value.trim();
            }
        }

        return result;
    }

    return (line, next, context) => {
        const match = line.match(/^L\s+(\d{2})\/(\d{2})\/(\d{4})\s+-\s+(\d{2}):(\d{2}):(\d{2}):\s*(?:\[([^\]]+)])?\s*(?:\(([^)]+)\))?\s*(.*)/);

        if (!match) {
            return false;
        }

        const [
            _,
            mm, dd, yyyy,
            hh, mi, ss,
            meta,
            tag,
            message
        ] = match;

        context.meta = parseMeta(meta);
        context.iso = `${yyyy}-${mm}-${dd}T${hh}:${mi}:${ss}`;
        context.message = message;

        next();
    };
}

export default parse;