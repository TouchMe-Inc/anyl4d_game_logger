const SQRT_2PI = Math.sqrt(2 * Math.PI);

function pdf(x) {
    return Math.exp(-0.5 * x * x) / SQRT_2PI;
}

function erf(x) {
    const sign = x >= 0 ? 1 : -1;
    x = Math.abs(x);

    const a1 = 0.254829592;
    const a2 = -0.284496736;
    const a3 = 1.421413741;
    const a4 = -1.453152027;
    const a5 = 1.061405429;
    const p = 0.3275911;

    const t = 1 / (1 + p * x);
    const y = 1 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * Math.exp(-x * x);

    return sign * y;
}

function cdf(x) {
    return 0.5 * (1 + erf(x / Math.sqrt(2)));
}

// ------------------------
// Гаусс в натуральных параметрах
// ------------------------
class Gaussian {
    constructor(mu = 0, sigma2 = 1) {
        this.pi = sigma2 > 0 ? 1 / sigma2 : 0;       // precision
        this.tau = this.pi * mu;                     // precision * mean
    }

    static fromPiTau(pi, tau) {
        const g = new Gaussian();
        g.pi = pi;
        g.tau = tau;
        return g;
    }

    get mean() {
        return this.pi > 0 ? this.tau / this.pi : 0;
    }

    get variance() {
        return this.pi > 0 ? 1 / this.pi : Infinity;
    }

    multiply(other) {
        return Gaussian.fromPiTau(this.pi + other.pi, this.tau + other.tau);
    }

    divide(other) {
        return Gaussian.fromPiTau(this.pi - other.pi, this.tau - other.tau);
    }
}

// ------------------------
// Параметры модели (масштаб 1000)
// ------------------------
const MU_START = 1000;
const SIGMA_START = MU_START / 3;
const BETA = MU_START / 5;
const RHO_START = MU_START / 600;
const DYNAMICS2 = (MU_START / 5000) ** 2;

// ------------------------
// Создание игрока
// ------------------------
function createPlayer(id, team, mu = MU_START, sigma = SIGMA_START, rho = RHO_START) {
    return {id, team, mu, sigma, rho};
}

class TrueSkillMatch {
    constructor(players, winnerTeam, iterations = 10) {
        if (!winnerTeam) {
            throw new Error("winnerTeam must be specified");
        }

        this.players = players;
        this.winnerTeam = winnerTeam;
        this.iterations = iterations;

        this.teamsMap = this.groupPlayers();
        if (this.teamsMap.size !== 2) {
            throw new Error("Exactly two teams are required");
        }

        this.sortedTeams = this.buildTeamOrder();
        this.skillMarginals = this.createMarginals();
    }

    // -----------------------------
    // 1. Группировка игроков
    // -----------------------------
    groupPlayers() {
        const map = new Map();
        for (const p of this.players) {
            if (!map.has(p.team)) map.set(p.team, []);
            map.get(p.team).push(p);
        }
        return map;
    }

    // -----------------------------
    // 2. Формируем порядок команд
    // -----------------------------
    buildTeamOrder() {
        const winnerPlayers = this.teamsMap.get(this.winnerTeam);
        const loserTeam = [...this.teamsMap.keys()].find(t => t !== this.winnerTeam);
        const loserPlayers = this.teamsMap.get(loserTeam);

        return [
            {id: this.winnerTeam, players: winnerPlayers},
            {id: loserTeam, players: loserPlayers}
        ];
    }

    // -----------------------------
    // 3. Применяем динамику
    // -----------------------------
    applyDynamics() {
        for (const team of this.sortedTeams) {
            for (const p of team.players) {
                const sigma2 = p.sigma * p.sigma + p.rho * p.rho + DYNAMICS2;
                p.sigma = Math.sqrt(sigma2);
            }
        }
    }

    // -----------------------------
    // 4. Создаём маргиналы
    // -----------------------------
    createMarginals() {
        const map = new Map();
        for (const p of this.players) {
            map.set(p.id, new Gaussian(p.mu, p.sigma * p.sigma));
        }
        return map;
    }

    // -----------------------------
    // 5. Суммируем параметры команды
    // -----------------------------
    sumTeamStats(team) {
        let mu = 0;
        let variance = 0;

        for (const p of team.players) {
            const g = this.skillMarginals.get(p.id);
            mu += g.mean;
            variance += g.variance;
        }

        return {mu, variance};
    }

    // -----------------------------
    // 6. Обновление команды
    // -----------------------------
    updateTeam(team, c, c2, v, w, direction) {
        for (const p of team.players) {
            const g = this.skillMarginals.get(p.id);
            const s2 = g.variance;

            const meanDelta = (s2 / c) * v * direction;
            const varMultiplier = 1 - (s2 / c2) * w;

            this.skillMarginals.set(p.id, new Gaussian(
                g.mean + meanDelta,
                s2 * varMultiplier
            ));
        }
    }

    // -----------------------------
    // 7. Одна EP‑итерация
    // -----------------------------
    runEpIteration() {
        const stronger = this.sortedTeams[0];
        const weaker = this.sortedTeams[1];

        const {mu: muStrong, variance: varStrong} = this.sumTeamStats(stronger);
        const {mu: muWeak, variance: varWeak} = this.sumTeamStats(weaker);

        const deltaMu = muStrong - muWeak;
        const c2 = varStrong + varWeak + 2 * BETA * BETA;
        const c = Math.sqrt(c2);

        const t = deltaMu / c;
        const v = pdf(t) / cdf(t);
        const w = v * (v + t);

        this.updateTeam(stronger, c, c2, v, w, +1);
        this.updateTeam(weaker, c, c2, v, w, -1);
    }

    // -----------------------------
    // 8. Собираем результат
    // -----------------------------
    buildResult() {
        return this.players.map(p => {
            const g = this.skillMarginals.get(p.id);
            return {
                id: p.id,
                team: p.team,
                mu: g.mean,
                sigma: Math.sqrt(g.variance),
                rho: p.rho
            };
        });
    }

    // -----------------------------
    // 9. Главный метод
    // -----------------------------
    run() {
        this.applyDynamics();

        for (let i = 0; i < this.iterations; i++) {
            this.runEpIteration();
        }

        return this.buildResult();
    }
}

// ------------------------
// Пример использования
// ------------------------
const TEAM_A = "A";
const TEAM_B = "B";

let players = [
    createPlayer("A1", TEAM_A, 1424.3256994997066,  160.6666666666666667),
    createPlayer("A2", TEAM_A),
    createPlayer("A3", TEAM_A),
    createPlayer("A4", TEAM_A, 901.9204861415672, 180.67148459386544),

    createPlayer("B1", TEAM_B),
    createPlayer("B2", TEAM_B),
    createPlayer("B3", TEAM_B),
    createPlayer("B4", TEAM_B,  604.7418545111414, 165.0459607978317)
];

let updated;
for (let i = 0; i < 100; i++) {
    let match = new TrueSkillMatch(players, TEAM_A, 20);
    updated = match.run();

    console.log(`=== Updated players #${i + 1} ===`);
    console.table(updated);
}

function shuffleTeams(players, teamA, teamB) {
    // 1. Копируем массив
    const arr = [...players];

    // 2. Перемешиваем Фишером–Йетсом
    for (let i = arr.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [arr[i], arr[j]] = [arr[j], arr[i]];
    }

    // 3. Делим пополам
    const half = arr.length / 2;

    const teamAPlayers = arr.slice(0, half).map(p => ({...p, team: teamA}));
    const teamBPlayers = arr.slice(half).map(p => ({...p, team: teamB}));

    return [...teamAPlayers, ...teamBPlayers];
}


let matchFinal = new TrueSkillMatch(shuffleTeams(updated, TEAM_A, TEAM_B), TEAM_A, 20);

console.log(`=== Last match ===`);
console.table(matchFinal.run());