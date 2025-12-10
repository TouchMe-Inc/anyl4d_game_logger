import dgram from 'dgram';
import Pipeline from './pipeline.js'
import output from "./middlewares/output.js";
import parse from "./middlewares/parse.js";
import classify from "./middlewares/classify.js";

const pipeline = new Pipeline();

pipeline
    .use(parse())
    .use(classify())
    .use(output());

const server = dgram.createSocket('udp4');

server.on('listening', () => {
    const address = server.address();
    console.log(`Listening for logaddress messages on ${address.address}:${address.port}`);
});

server.on('message', (msg, rinfo) => {
    const log = msg.subarray(5).toString('utf8').trim();
    pipeline.run(log);
});

server.on('error', (err) => {
    console.error(`Server error: ${err.message}`);
});

server.bind(process.env.UDP_PORT || 27500, process.env.UDP_HOST || '0.0.0.0');
