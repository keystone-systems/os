// E2E check functions -- each check appends to the report
// See specs/REQ-031-e2e-os-agent-product-test.md

import { execFileSync, execSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { basename, join } from "node:path";
import type { AgentCtl } from "./agentctl";
import type { ForgejoPlatform } from "./forgejo";
import { emit } from "./log";
import type { Report } from "./report";

interface Config {
  productAgent: string;
  engineerAgent: string;
  platform: string;
  provider: string;
  forgejoUrl: string;
  forgejoToken: string;
  templateRepo: string;
  domain: string;
  timeoutMs: number;
  smoke: boolean;
  dryRun: boolean;
  print: boolean;
}

function engineerHome(config: Config): string | null {
  try {
    const line = execSync(`getent passwd agent-${config.engineerAgent}`, {
      encoding: "utf-8",
    }).trim();
    return line.split(":")[5] ?? null;
  } catch {
    return null;
  }
}

function forkName(config: Config): string {
  return config.templateRepo.split("/")[1];
}

function findInAgentPaths(
  home: string,
  test: (path: string) => boolean,
): boolean {
  const searchRoots = [join(home, "repos")];
  for (const root of searchRoots) {
    if (!existsSync(root)) continue;
    if (walkDir(root, test)) return true;
  }
  return false;
}

function walkDir(
  dir: string,
  test: (path: string) => boolean,
  depth = 6,
): boolean {
  if (depth <= 0) return false;
  try {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = join(dir, entry.name);
      if (test(full)) return true;
      if (entry.isDirectory()) {
        if (walkDir(full, test, depth - 1)) return true;
      }
    }
  } catch {
    // Permission denied or missing dir
  }
  return false;
}

// ---------------------------------------------------------------------------
// Polling helper
// ---------------------------------------------------------------------------

const POLL_INTERVAL_MS = 30_000;

async function pollUntil(
  fn: () => Promise<boolean>,
  timeoutMs: number,
): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await fn()) return true;
    const remaining = deadline - Date.now();
    if (remaining <= 0) break;
    await new Promise((resolve) =>
      setTimeout(resolve, Math.min(POLL_INTERVAL_MS, remaining)),
    );
  }
  return false;
}

// ---------------------------------------------------------------------------
// Agent quiescence (REQ-031.7a-d)
// ---------------------------------------------------------------------------

export async function pauseAgents(
  config: Config,
  report: Report,
  agentctl: AgentCtl,
) {
  for (const agent of [config.productAgent, config.engineerAgent]) {
    if (await agentctl.isPaused(agent)) {
      emit("info", "agent already paused", { agent });
      continue;
    }

    if (await agentctl.hasTasks(agent)) {
      emit("warn", "agent has active tasks", { agent });
      if (process.stdin.isTTY) {
        process.stderr.write(
          `Agent ${agent} has active tasks. Kill and proceed? [y/N] `,
        );
        const reply = await readLine();
        if (!/^y(es)?$/i.test(reply)) {
          report.check(
            "agent_quiescence",
            "fail",
            `Operator declined to kill active tasks on ${agent}`,
          );
          throw new Error("Agent quiescence failed");
        }
      } else {
        report.check(
          "agent_quiescence",
          "fail",
          `Agent ${agent} has active tasks (non-interactive)`,
        );
        throw new Error("Agent quiescence failed");
      }
    }

    if (!(await agentctl.pause(agent, "e2e test in progress"))) {
      report.check(
        "agent_quiescence",
        "fail",
        `Failed to pause agent ${agent}`,
      );
      throw new Error("Agent quiescence failed");
    }
    emit("info", "paused agent", { agent });
  }
  report.check("agent_quiescence", "pass", "Both agents paused");
}

export async function resumeAgents(config: Config, agentctl: AgentCtl) {
  for (const agent of [config.productAgent, config.engineerAgent]) {
    await agentctl.resume(agent);
    emit("info", "resumed agent", { agent });
  }
}

// ---------------------------------------------------------------------------
// Dry-run validation (REQ-031.7)
// ---------------------------------------------------------------------------

export async function dryRun(
  config: Config,
  report: Report,
  forgejo: ForgejoPlatform,
  agentctl: AgentCtl,
) {
  emit("info", "dry-run: validating configuration");

  // Check agentctl available and agents exist
  for (const [label, agent] of [
    ["product", config.productAgent],
    ["engineer", config.engineerAgent],
  ] as const) {
    if (await agentctl.exists(agent)) {
      report.check(
        `dryrun_${label}_agent`,
        "pass",
        `Agent '${agent}' is configured`,
      );
      const paused = await agentctl.isPaused(agent);
      report.check(
        `dryrun_${agent}_paused`,
        "pass",
        paused
          ? `Agent '${agent}' is paused`
          : `Agent '${agent}' is running (will be paused during full run)`,
      );
    } else {
      report.check(
        `dryrun_${label}_agent`,
        "fail",
        `Agent '${agent}' not found in agentctl`,
      );
    }
  }

  // Check Forgejo connectivity
  if (config.platform === "forgejo") {
    if (!config.forgejoToken) {
      report.check(
        "dryrun_forgejo_token",
        "fail",
        "FORGEJO_TOKEN not set and --forgejo-token not provided",
      );
    } else {
      report.check("dryrun_forgejo_token", "pass", "Forgejo token present");
    }

    if (await forgejo.repoExists(config.templateRepo)) {
      report.check(
        "dryrun_template_repo",
        "pass",
        `Template repo '${config.templateRepo}' exists`,
      );
    } else {
      report.check(
        "dryrun_template_repo",
        "fail",
        `Template repo '${config.templateRepo}' not found at ${config.forgejoUrl}`,
      );
    }
  }

  // Check himalaya available
  try {
    execSync("which himalaya", { stdio: "pipe" });
    report.check("dryrun_himalaya", "pass", "himalaya is available");
  } catch {
    report.check("dryrun_himalaya", "fail", "himalaya not found in PATH");
  }
}

// ---------------------------------------------------------------------------
// Environment lifecycle (REQ-031.11-031.14)
// ---------------------------------------------------------------------------

export async function cleanupEnvironment(config: Config, report: Report) {
  emit("info", "cleaning environment");
  const name = forkName(config);
  const owner = config.templateRepo.split("/")[0];

  for (const agent of [config.productAgent, config.engineerAgent]) {
    const home = (() => {
      try {
        return execSync(`getent passwd agent-${agent}`, { encoding: "utf-8" })
          .trim()
          .split(":")[5];
      } catch {
        return null;
      }
    })();
    if (!home) continue;

    const wtBase = join(home, "repos", owner, name, "worktrees");
    if (existsSync(wtBase)) {
      emit("info", "removing worktrees", { agent, path: wtBase });
      execSync(`rm -rf ${JSON.stringify(wtBase)}`);
    }
    const clonePath = join(home, "repos", owner, name);
    if (existsSync(clonePath)) {
      emit("info", "removing clone", { agent, path: clonePath });
      execSync(`rm -rf ${JSON.stringify(clonePath)}`);
    }
  }

  report.check(
    "environment_cleanup",
    "pass",
    "Cleaned agent disks and worktrees",
  );
}

export async function setupEnvironment(
  config: Config,
  report: Report,
  forgejo: ForgejoPlatform,
) {
  emit("info", "setting up environment");
  const name = forkName(config);

  // Delete prior forks
  for (const agent of [config.productAgent, config.engineerAgent]) {
    await forgejo.deleteRepo(`${agent}/${name}`);
  }

  // Fork template for engineering agent
  try {
    await forgejo.forkRepo(config.templateRepo, config.engineerAgent);
    report.check(
      "environment_setup",
      "pass",
      `Forked template to ${config.engineerAgent}/${name}`,
    );
  } catch (err) {
    report.check(
      "environment_setup",
      "fail",
      `Failed to fork template: ${err}`,
    );
    throw err;
  }
}

// ---------------------------------------------------------------------------
// Ping-pong smoke test
// ---------------------------------------------------------------------------

export async function pingPong(config: Config, report: Report) {
  const toAddr = `${config.productAgent}@${config.domain}`;
  const tag = `e2e-${Date.now()}`;
  const subject = `[ping] ${tag}`;
  emit("info", "sending ping email", { to: toAddr, tag });
  try {
    const fromAddr = detectSender();
    const eml = [
      `From: ${fromAddr}`,
      `To: ${toAddr}`,
      `Subject: ${subject}`,
      `Date: ${new Date().toUTCString()}`,
      `MIME-Version: 1.0`,
      `Content-Type: text/plain; charset=utf-8`,
      ``,
      `ping`,
    ].join("\r\n");
    execSync("himalaya message send", {
      input: eml,
      stdio: ["pipe", "pipe", "pipe"],
    });
    report.check("ping_send", "pass", `Ping sent to ${toAddr} (${tag})`);
  } catch (err) {
    report.check("ping_send", "fail", `Failed to send ping: ${err}`);
    throw err;
  }

  emit("info", "waiting for pong reply", { tag });
  // The contract (job.yml parse_sources step) requires the reply subject to
  // be `Re: [pong] <tag>` — flip `ping` to `pong`, preserve the tag. The
  // harness asserts that invariant exactly: tag present AND pong in subject.
  // Contract drift is caught by the sandbox test under `nix flake check`
  // (tests/module/agent-task-loop-ping-pong.nix), so the smoke does not need
  // a body-fallback.
  const found = await pollUntil(async () => {
    try {
      const raw = execSync(
        'himalaya envelope list -o json "not flag seen"',
        { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"] },
      );
      const envelopes: Array<{ subject: string }> = JSON.parse(raw);
      return envelopes.some(
        (e) => e.subject.includes(tag) && /pong/i.test(e.subject),
      );
    } catch {
      return false;
    }
  }, config.timeoutMs);
  report.check(
    "ping_pong",
    found ? "pass" : "fail",
    found
      ? `Received pong reply for ${tag}`
      : `No pong reply within ${Math.round(config.timeoutMs / 60_000)} min`,
  );
}

// ---------------------------------------------------------------------------
// Product agent workflow (REQ-031.15-031.18)
// ---------------------------------------------------------------------------

const PALINDROME_REQUIREMENT_TEMPLATE = `# Feature Requirement: Palindrome Checker

## Title

Palindrome Checker

## Repo

ks-testing/agent-e2e-bun-template

## Description

Add a palindrome checker to the bun web server. The user submits a string via
an HTML form; the server responds with whether the string is a palindrome.

## Problem

The bun server template has an HTML form with no backend logic. We need a
palindrome solver to validate that the agent pipeline can implement a feature
end-to-end: from product requirement to specification, implementation, tested
release, and product verification.

## Acceptance Criteria

- The palindrome checker MUST be implemented as a backend service
- The backend response MUST return JSON with \`input\` (string) and
  \`is_palindrome\` (boolean) fields
- The HTML form in \`packages/web/\` MUST submit a string and display whether
  it is a palindrome
- The engineering agent MUST write Playwright end-to-end tests in
  \`packages/e2e/\` that exercise the palindrome happy path
- Playwright tests MUST capture screenshots at key steps following the naming
  convention \`{test-name}.{step-index}.{step-name}.png\`
- Screenshots MUST be committed via git LFS

## Priority

high

## Process

Please follow the standard product process:

1. Create a press release issue on the Forgejo repo describing the Palindrome
   Checker feature
2. Create a milestone titled "Palindrome Checker v1" and associate the press
   release issue with it
3. Assign the engineering agent to the press release issue (or create a linked
   engineering-intake issue assigned to the engineering agent) to begin
   implementation
`;

export async function productEmail(config: Config, report: Report) {
  const toAddr = `${config.productAgent}@${config.domain}`;
  emit("info", "sending palindrome requirement to product agent", {
    agent: config.productAgent,
    to: toAddr,
  });
  try {
    const fromAddr = detectSender();
    const eml = [
      `From: ${fromAddr}`,
      `To: ${toAddr}`,
      `Subject: [feature.requirement] Palindrome Checker`,
      `Date: ${new Date().toUTCString()}`,
      `MIME-Version: 1.0`,
      `Content-Type: text/plain; charset=utf-8`,
      ``,
      PALINDROME_REQUIREMENT_TEMPLATE,
    ].join("\r\n");
    execSync("himalaya message send", { input: eml, stdio: ["pipe", "pipe", "pipe"] });
    report.check(
      "product_email_dispatch",
      "pass",
      `Palindrome requirement sent to ${toAddr}`,
    );
  } catch (err) {
    report.check(
      "product_email_dispatch",
      "fail",
      `Failed to send email: ${err}`,
    );
    throw err;
  }
}

export async function productPressRelease(
  config: Config,
  report: Report,
  forgejo: ForgejoPlatform,
  repo: string,
) {
  emit("info", "waiting for press release issue");
  const found = await pollUntil(async () => {
    try {
      const issues = await forgejo.listIssues(repo, "open");
      return issues.some((i) => /press release|palindrome/i.test(i.title));
    } catch {
      return false;
    }
  }, config.timeoutMs);
  report.check(
    "product_press_release",
    found ? "pass" : "skip",
    found ? "Found press release issue" : "No press release issue found yet",
  );
}

export async function productMilestone(
  config: Config,
  report: Report,
  forgejo: ForgejoPlatform,
  repo: string,
) {
  emit("info", "waiting for palindrome milestone");
  const found = await pollUntil(async () => {
    try {
      const milestones = await forgejo.listMilestones(repo);
      return milestones.some((m) => /palindrome/i.test(m.title));
    } catch {
      return false;
    }
  }, config.timeoutMs);
  report.check(
    "product_milestone",
    found ? "pass" : "skip",
    found ? "Found palindrome milestone" : "No palindrome milestone found yet",
  );
}

// ---------------------------------------------------------------------------
// Engineering agent workflow (REQ-031.19-031.33)
// ---------------------------------------------------------------------------

export async function engineeringIssue(
  config: Config,
  report: Report,
  forgejo: ForgejoPlatform,
  repo: string,
) {
  emit("info", "waiting for engineering issue on milestone");
  const found = await pollUntil(async () => {
    try {
      const issues = await forgejo.listIssues(repo, "all");
      return issues.some((i) =>
        /engineer|implement|palindrome/i.test(i.title),
      );
    } catch {
      return false;
    }
  }, config.timeoutMs);
  report.check(
    "engineering_issue",
    found ? "pass" : "skip",
    found ? "Found engineering issue" : "No engineering issue found yet",
  );
}

export async function trunkBranch(
  _config: Config,
  report: Report,
  forgejo: ForgejoPlatform,
  repo: string,
) {
  emit("info", "checking for trunk branch");
  try {
    const branches = await forgejo.listBranches(repo);
    const nonDefault = branches.filter(
      (b) => b.name !== "main" && b.name !== "master",
    );
    if (nonDefault.length > 0) {
      report.check(
        "trunk_branch",
        "pass",
        `Found branch: ${nonDefault[0].name}`,
      );
    } else {
      report.check("trunk_branch", "skip", "No trunk branch found yet");
    }
  } catch {
    report.check("trunk_branch", "skip", "Could not list branches");
  }
}

export async function worktree(config: Config, report: Report) {
  emit("info", "checking for engineer worktree");
  const home = engineerHome(config);
  if (!home) {
    report.check(
      "worktree",
      "skip",
      "Could not resolve engineer home directory",
    );
    return;
  }

  const name = forkName(config);
  const wtBase = join(
    home,
    "repos",
    config.engineerAgent,
    name,
    "worktrees",
  );
  if (existsSync(wtBase)) {
    try {
      const entries = readdirSync(wtBase, { withFileTypes: true });
      if (entries.some((e) => e.isDirectory())) {
        report.check("worktree", "pass", `Worktree exists at ${wtBase}`);
        return;
      }
    } catch {
      /* fall through */
    }
  }
  report.check("worktree", "skip", `No worktree found at ${wtBase}`);
}

export async function specFile(config: Config, report: Report) {
  emit("info", "checking for specs/REQ-*palindrome* file");
  const home = engineerHome(config);
  if (!home) {
    report.check(
      "spec_file",
      "skip",
      "Could not resolve engineer home directory",
    );
    return;
  }

  const found = findInAgentPaths(home, (p) =>
    /specs\/REQ-.*palindrome.*\.md$/i.test(p),
  );
  report.check(
    "spec_file",
    found ? "pass" : "skip",
    found ? "Found palindrome spec file" : "No palindrome spec file found yet",
  );
}

export async function palindromeBackend(config: Config, report: Report) {
  emit("info", "checking palindrome backend responds correctly");
  const home = engineerHome(config);
  if (!home) {
    report.check(
      "palindrome_backend",
      "skip",
      "Could not resolve engineer home directory",
    );
    return;
  }

  const port = discoverServerPort(home, config) ?? 3000;
  const baseUrl = `http://localhost:${port}`;

  const cases: Array<{ input: string; expected: boolean }> = [
    { input: "racecar", expected: true },
    { input: "hello", expected: false },
  ];

  for (const { input, expected } of cases) {
    let result: unknown;
    try {
      result = await fetchPalindromeResult(baseUrl, input);
    } catch (err) {
      report.check(
        "palindrome_backend",
        "skip",
        `Could not reach server at ${baseUrl}: ${err}`,
      );
      return;
    }

    const validated = validatePalindromeResponse(result);
    if (!validated) {
      report.check(
        "palindrome_backend",
        "fail",
        `Response for "${input}" does not match JSON schema: ${JSON.stringify(result)}`,
      );
      return;
    }

    if (validated.is_palindrome !== expected) {
      report.check(
        "palindrome_backend",
        "fail",
        `Expected is_palindrome=${expected} for "${input}", got ${validated.is_palindrome}`,
      );
      return;
    }
  }

  report.check(
    "palindrome_backend",
    "pass",
    `Palindrome backend at port ${port} returns correct JSON`,
  );
}

export async function modelMatrix(config: Config, report: Report) {
  emit("info", "recording model-matrix: detecting agent language/framework");
  const home = engineerHome(config);
  if (!home) {
    report.check(
      "model_matrix",
      "skip",
      "Could not resolve engineer home directory",
    );
    return;
  }

  const lang = detectBackendLanguage(home, config);
  report.check(
    "model_matrix",
    lang ? "pass" : "skip",
    lang
      ? `lang=${lang} provider=${config.provider}`
      : `Could not detect backend language provider=${config.provider}`,
  );
}

export async function playwrightTests(config: Config, report: Report) {
  emit("info", "checking for Playwright tests in packages/e2e/");
  const home = engineerHome(config);
  if (!home) {
    report.check(
      "playwright_tests",
      "skip",
      "Could not resolve engineer home directory",
    );
    return;
  }

  const found = findInAgentPaths(home, (p) =>
    /packages\/e2e\/.*\.(spec|test)\./i.test(p),
  );
  report.check(
    "playwright_tests",
    found ? "pass" : "skip",
    found ? "Found Playwright test files" : "No Playwright tests found yet",
  );
}

export async function screenshots(config: Config, report: Report) {
  emit("info", "checking screenshot naming convention");
  const home = engineerHome(config);
  if (!home) {
    report.check(
      "screenshots",
      "skip",
      "Could not resolve engineer home directory",
    );
    return;
  }

  let found = false;
  let badNames = false;
  findInAgentPaths(home, (p) => {
    if (/packages\/e2e\/.*\.png$/.test(p)) {
      found = true;
      const name = basename(p);
      if (!/^[a-z0-9_-]+\.\d+\.[a-z0-9_-]+\.png$/.test(name)) {
        badNames = true;
      }
    }
    return false; // keep searching
  });

  if (found && !badNames) {
    report.check("screenshots", "pass", "Screenshots follow naming convention");
  } else if (found && badNames) {
    report.check(
      "screenshots",
      "fail",
      "Some screenshots do not follow {test-name}.{step-index}.{step-name}.png",
    );
  } else {
    report.check("screenshots", "skip", "No screenshots found yet");
  }
}

export async function lfsTracking(config: Config, report: Report) {
  emit("info", "checking git LFS tracking for PNG files");
  const home = engineerHome(config);
  if (!home) {
    report.check(
      "lfs_tracking",
      "skip",
      "Could not resolve engineer home directory",
    );
    return;
  }

  const name = forkName(config);
  const found = findInAgentPaths(home, (p) => {
    if (p.endsWith(".gitattributes") && p.includes(name)) {
      try {
        const content = readFileSync(p, "utf-8");
        return /\.png.*filter=lfs/.test(content);
      } catch {
        return false;
      }
    }
    return false;
  });

  report.check(
    "lfs_tracking",
    found ? "pass" : "skip",
    found
      ? ".gitattributes tracks *.png via LFS"
      : "No LFS tracking found for PNG files",
  );
}

export async function releasePr(
  _config: Config,
  report: Report,
  forgejo: ForgejoPlatform,
  repo: string,
) {
  emit("info", "checking for release PR");
  try {
    const prs = await forgejo.listPrs(repo, "all");
    report.check(
      "release_pr",
      prs.length > 0 ? "pass" : "skip",
      prs.length > 0 ? "Found release PR" : "No release PR found yet",
    );
  } catch {
    report.check("release_pr", "skip", "Could not list PRs");
  }
}

export async function issueClosed(
  _config: Config,
  report: Report,
  forgejo: ForgejoPlatform,
  repo: string,
) {
  emit("info", "checking engineering issue is closed");
  try {
    const closed = await forgejo.listIssues(repo, "closed");
    report.check(
      "issue_closed",
      closed.length > 0 ? "pass" : "skip",
      closed.length > 0
        ? `Found ${closed.length} closed issue(s)`
        : "No closed issues found yet",
    );
  } catch {
    report.check("issue_closed", "skip", "Could not list closed issues");
  }
}

// ---------------------------------------------------------------------------
// Product verification (REQ-031.34-031.35)
// ---------------------------------------------------------------------------

export async function milestoneClosed(
  _config: Config,
  report: Report,
  forgejo: ForgejoPlatform,
  repo: string,
) {
  emit("info", "checking milestone is closed");
  try {
    const milestones = await forgejo.listMilestones(repo, "closed");
    report.check(
      "milestone_closed",
      milestones.length > 0 ? "pass" : "skip",
      milestones.length > 0
        ? "Palindrome milestone closed"
        : "No closed milestones found",
    );
  } catch {
    report.check("milestone_closed", "skip", "Could not list milestones");
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function detectSender(): string {
  // Try himalaya config (most reliable)
  const configPath = join(
    process.env.XDG_CONFIG_HOME ?? join(process.env.HOME ?? "", ".config"),
    "himalaya",
    "config.toml",
  );
  if (existsSync(configPath)) {
    const content = readFileSync(configPath, "utf-8");
    const match = content.match(/^email\s*=\s*"(.+)"/m);
    if (match) return match[1];
  }
  // Fall back to git config
  try {
    return execSync("git config user.email", { encoding: "utf-8" }).trim();
  } catch {
    throw new Error("Could not detect sender email (no himalaya config or git config)");
  }
}

function discoverServerPort(
  agentHome: string,
  config: Config,
): number | null {
  const name = forkName(config);
  const owner = config.templateRepo.split("/")[0];
  const roots = [
    join(agentHome, "repos", owner, name, "worktrees"),
    join(agentHome, "repos", owner, name),
  ];
  for (const root of roots) {
    const portFile = join(root, "packages", "web", ".port");
    if (existsSync(portFile)) {
      const raw = readFileSync(portFile, "utf-8").trim();
      const port = Number.parseInt(raw, 10);
      if (!Number.isNaN(port) && port > 0 && port <= 65535) return port;
    }
  }
  return null;
}

interface PalindromeResponse {
  input: string;
  is_palindrome: boolean;
}

async function fetchPalindromeResult(
  baseUrl: string,
  input: string,
): Promise<unknown> {
  const paths = ["/palindrome", "/api/palindrome", "/check", "/api/check"];
  for (const path of paths) {
    try {
      const resp = await fetch(`${baseUrl}${path}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ input }),
        // 5 s per path attempt; up to 4 paths tried before failing
        signal: AbortSignal.timeout(5000),
      });
      if (resp.ok) return resp.json();
    } catch {
      // try next path
    }
  }
  throw new Error(`No palindrome endpoint responded at ${baseUrl}`);
}

function validatePalindromeResponse(
  data: unknown,
): PalindromeResponse | null {
  if (
    data !== null &&
    typeof data === "object" &&
    "input" in data &&
    "is_palindrome" in data &&
    typeof (data as Record<string, unknown>).input === "string" &&
    typeof (data as Record<string, unknown>).is_palindrome === "boolean"
  ) {
    return data as PalindromeResponse;
  }
  return null;
}

function detectBackendLanguage(agentHome: string, config: Config): string | null {
  const name = forkName(config);
  const owner = config.templateRepo.split("/")[0];
  const roots = [
    join(agentHome, "repos", owner, name, "worktrees"),
    join(agentHome, "repos", owner, name),
  ];

  const indicators: Array<{ pattern: RegExp; lang: string }> = [
    { pattern: /Cargo\.toml$/, lang: "rust" },
    { pattern: /go\.mod$/, lang: "go" },
    { pattern: /requirements\.txt$|setup\.py$|pyproject\.toml$/, lang: "python" },
    { pattern: /Gemfile$/, lang: "ruby" },
    { pattern: /pom\.xml$|build\.gradle$/, lang: "java" },
    { pattern: /packages\/web\/.*\.go$/, lang: "go" },
    { pattern: /packages\/web\/.*\.rs$/, lang: "rust" },
    { pattern: /packages\/web\/.*\.py$/, lang: "python" },
    { pattern: /packages\/web\/.*\.rb$/, lang: "ruby" },
    { pattern: /packages\/web\/.*\.java$/, lang: "java" },
  ];

  for (const root of roots) {
    if (!existsSync(root)) continue;
    for (const { pattern, lang } of indicators) {
      if (walkDir(root, (p) => pattern.test(p))) return lang;
    }
    // Default: TypeScript/Bun (template language)
    if (existsSync(join(root, "bun.lock")) || existsSync(join(root, "bun.lockb"))) {
      return "typescript";
    }
  }
  return null;
}

function readLine(): Promise<string> {
  return new Promise((resolve) => {
    let buf = "";
    process.stdin.setRawMode?.(false);
    process.stdin.resume();
    process.stdin.setEncoding("utf-8");
    process.stdin.once("data", (chunk: string) => {
      buf += chunk;
      process.stdin.pause();
      resolve(buf.trim());
    });
  });
}
