function output() {
    return (line, next, context) => {

        // if (context.type === 'NOISE') {
        //     return next();
        // }

        console.log(`L ${context.iso}: [${context.type}] ${context.message}`);
        next();
    };
}

export default output;