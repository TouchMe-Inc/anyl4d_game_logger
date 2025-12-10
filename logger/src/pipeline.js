class Pipeline {
    constructor() {
        this.middlewares = [];
        this.queue = Promise.resolve();
    }

    use(fn) {
        this.middlewares.push(fn);
        return this;
    }

    run(line, context = {}) {
        this.queue = this.queue.then(() => this._execute(line, context));
        return this.queue;
    }

    async _execute(line, context) {
        let index = 0;

        const next = async () => {
            const mw = this.middlewares[index++];
            if (!mw) return;
            await mw(line, next, context);
        };

        await next();
    }
}

export default Pipeline;