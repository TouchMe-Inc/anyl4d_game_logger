const dgram = require('dgram');
const server = dgram.createSocket('udp4');

const PORT = 27500;
const HOST = '0.0.0.0';

class LogPipeline {
  constructor() {
    this.middlewares = [];
  }

  use(fn) {
    this.middlewares.push(fn);
  }

  run(line) {
    let index = 0;
    const next = () => {
      const mw = this.middlewares[index++];
      if (mw) mw(line, next, this);
    };
    next();
  }
}

const pipeline = new LogPipeline();

pipeline.use((() => {
  let ignore = false;

  return (line, next) => {
    if (line.includes("server cvars start")) {
      ignore = true;
      return;
    }
    if (line.includes("server cvars end")) {
      ignore = false;
      return;
    }
    if (ignore) {
      return;
    }
    next();
  };
})());

pipeline.use((line, next) => {
  if (line.includes("(DEATH)")) {
    console.log("[DEATH]", line);
    return;
  }
  if (line.includes("triggered")) {
    console.log("[TRIGGERED]", line);
    return;
  }
  if (line.includes("say")) {
    console.log("[CHAT]", line);
    return;
  }
  next();
});

pipeline.use((line) => {
  console.log("[OTHER]", line);
});

server.on('listening', () => {
  const address = server.address();
  console.log(`Listening for logaddress messages on ${address.address}:${address.port}`);
});

server.on('message', (msg, rinfo) => {
  const log = msg.subarray(5).toString('utf8').trim();
  pipeline.run(log);
});

server.bind(PORT, HOST);
