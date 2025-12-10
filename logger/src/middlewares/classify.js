export const ENTITY_RE = `"([^"]+)"`;

const MATCHERS = [
    ['KILL', new RegExp(`^${ENTITY_RE} killed ${ENTITY_RE} with "([^"]+)"(?: \\((headshot)\\))?$`)],
    ['INCAP', new RegExp(`^${ENTITY_RE} was incapped by ${ENTITY_RE} with "([^"]+)"$`)],
    ['PLAYER_CONNECT', new RegExp(`^${ENTITY_RE} connected(?:, address "([^"]*)")$`)], // "Nick<34><BOT><>" connected, address "none"
    ['PLAYER_ENTER', new RegExp(`^${ENTITY_RE} entered the game$`)], // "Nick<34><BOT><>" entered the game
    ['PLAYER_DISCONNECT', new RegExp(`^${ENTITY_RE} disconnected(?: \\(reason "([^"]*)"\\))$`)], // "Nick<34><BOT><Survivor>" disconnected (reason "...")
    ['PLAYER_TEAM', new RegExp(`^${ENTITY_RE} joined team "([^"]+)"$`)], // "Nick<34><BOT><Unassigned>" joined team "Survivor"
    ['PLAYER_TRIGGER', new RegExp(`^${ENTITY_RE} triggered "([^"]+)`)], // "Nick<34><BOT><Survivor>" triggered "first_survivor_left"
    ['SPAWN', new RegExp(`^${ENTITY_RE} spawned$`)], // "Charger<10><BOT><Infected><CHARGER><ALIVE><600+0><setpos_exact 37.50 425.00 -305.97; setang 0.00 0.00 0.00><Area 37556>" spawned
    ['MAP_LOADING', /^Loading map "([^"]+)"/], // Loading map "c5m2_park"
    ['MAP_TRIGGER', /^World triggered "([^"]+)"/], // World triggered "Round_Start"
];

function output() {
    return (line, next, context) => {

        if (context.message === undefined) {
            return next();
        }

        for (const [type, re] of MATCHERS) {
            if (re.test(context.message)) {
                context.type = type;
                return next();
            }
        }

        context.type = 'NOISE';

        next();
    };
}

export default output;