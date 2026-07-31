#!/usr/bin/env bun
// agents-e2e -- End-to-end OS agent product lifecycle test (REQ-031)
// See specs/REQ-031-e2e-os-agent-product-test.md

import { parseArgs } from "node:util";
import { AgentCtl } from "./agentctl";
import * as checks from "./checks";
import { ForgejoPlatform } from "./forgejo";
import { emit } from "./log";
import { Report } from "./report";

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

function extractAgentDomain(forgejoUrl: string): string {
  try {
    const hostname = new URL(forgejoUrl).hostname;
    const parts = hostname.split(".");
    // Strip leading subdomain (e.g., "git.ncrmro.com" -> "ncrmro.com")
    return parts.length > 2 ? parts.slice(1).join(".") : hostname;
  } catch {
    return "localhost";
  }
}

function parseConfig(): Config | null {
  const { values } = parseArgs({
    args: Bun.argv.slice(2),
    options: {
      product: { type: "string" },
      engineer: { type: "string" },
      platform: { type: "string", default: "forgejo" },
      provider: { type: "string", default: "claude" },
      "forgejo-url": {
        type: "string",
        default: Bun.env.FORGEJO_URL ?? "https://git.ncrmro.com",
      },
      "forgejo-token": { type: "string", default: Bun.env.FORGEJO_TOKEN ?? "" },
      "template-repo": {
        type: "string",
        default: "ks-testing/agent-e2e-bun-template",
      },
      domain: { type: "string", default: Bun.env.AGENT_DOMAIN ?? "" },
      timeout: { type: "string", default: "30" },
      smoke: { type: "boolean", default: false },
      "dry-run": { type: "boolean", default: false },
      print: { type: "boolean", default: false },
      help: { type: "boolean", default: false },
    },
    strict: true,
  });

  if (values.help) {
    printHelp();
    return null;
  }

  const isSmoke = values.smoke ?? false;
  if (!values.product) {
    console.error("Error: --product is required.");
    printHelp();
    process.exit(1);
  }
  if (!isSmoke && !values.engineer) {
    console.error("Error: --engineer is required (unless --smoke).");
    printHelp();
    process.exit(1);
  }

  const forgejoUrl = values["forgejo-url"] ?? "https://git.ncrmro.com";
  const rawDomain = values.domain || "";
  const domain = rawDomain || extractAgentDomain(forgejoUrl);
  const timeoutMinutes = Number.parseInt(values.timeout ?? "30", 10);
  const resolvedTimeoutMinutes = Number.isNaN(timeoutMinutes) ? 30 : timeoutMinutes;

  return {
    productAgent: values.product,
    engineerAgent: values.engineer ?? "",
    platform: values.platform ?? "forgejo",
    provider: values.provider ?? "claude",
    forgejoUrl,
    forgejoToken: values["forgejo-token"] ?? "",
    templateRepo:
      values["template-repo"] ?? "ks-testing/agent-e2e-bun-template",
    domain,
    timeoutMs: resolvedTimeoutMinutes * 60 * 1000,
    smoke: values.smoke ?? false,
    dryRun: values["dry-run"] ?? false,
    print: values.print ?? false,
  };
}

function printHelp() {
  console.log(`Usage: agents-e2e [options]

Run the end-to-end agent product lifecycle test (REQ-031).

Orchestrates a palindrome feature request through the full product-to-engineering
workflow: email intake -> press release -> milestone -> specification ->
implementation -> Playwright testing -> release PR -> product verification.

Options:
  --product NAME        Product agent name (required)
  --engineer NAME       Engineering agent name (required)
  --platform NAME       Platform for repos/issues (default: forgejo)
  --provider MODEL      AI model provider (default: claude)
  --forgejo-url URL     Forgejo instance URL (default: $FORGEJO_URL or https://git.ncrmro.com)
  --forgejo-token TOK   Forgejo API token (default: $FORGEJO_TOKEN)
  --template-repo REPO  Template repo owner/name (default: ks-testing/agent-e2e-bun-template)
  --domain DOMAIN       Agent email domain (default: $AGENT_DOMAIN or derived from --forgejo-url)
  --timeout MINUTES     Polling timeout in minutes (default: 30)
  --smoke               Send ping email and wait for pong reply (pipeline smoke test)
  --dry-run             Validate configuration without executing the workflow
  --print               Render final report with formatting when complete
  --help                Show this help`);
}

async function main() {
  const config = parseConfig();
  if (!config) return;

  const report = new Report(config);
  const forgejo = new ForgejoPlatform(config.forgejoUrl, config.forgejoToken);
  const agentctl = new AgentCtl();
  const engineerRepo = `${config.engineerAgent}/${config.templateRepo.split("/")[1]}`;

  emit("info", "starting e2e agent lifecycle test", {
    product: config.productAgent,
    engineer: config.engineerAgent,
    platform: config.platform,
  });

  if (config.dryRun) {
    emit("info", "dry-run mode -- validating configuration only");
    await checks.dryRun(config, report, forgejo, agentctl);
    report.finalize();
    report.print(config.print);
    process.exit(report.failed ? 1 : 0);
  }

  if (config.smoke) {
    emit("info", "smoke mode -- ping-pong email pipeline test");
    await checks.pingPong(config, report);
    report.finalize();
    report.print(config.print);
    process.exit(report.failed ? 1 : 0);
  }

  // Full E2E run
  try {
    // Phase: Agent quiescence
    await checks.pauseAgents(config, report, agentctl);

    // Phase: Environment lifecycle
    await checks.cleanupEnvironment(config, report);
    await checks.setupEnvironment(config, report, forgejo);

    // Phase: Product agent workflow
    await checks.productEmail(config, report);
    await checks.productPressRelease(config, report, forgejo, engineerRepo);
    await checks.productMilestone(config, report, forgejo, engineerRepo);

    // Phase: Engineering agent workflow
    await checks.engineeringIssue(config, report, forgejo, engineerRepo);
    await checks.trunkBranch(config, report, forgejo, engineerRepo);
    await checks.worktree(config, report);
    await checks.specFile(config, report);
    await checks.palindromeBackend(config, report);
    await checks.modelMatrix(config, report);
    await checks.playwrightTests(config, report);
    await checks.screenshots(config, report);
    await checks.lfsTracking(config, report);
    await checks.releasePr(config, report, forgejo, engineerRepo);
    await checks.issueClosed(config, report, forgejo, engineerRepo);

    // Phase: Product verification
    await checks.milestoneClosed(config, report, forgejo, engineerRepo);
  } finally {
    // Always resume agents
    await checks.resumeAgents(config, agentctl);
  }

  report.finalize();
  report.print(config.print);
  process.exit(report.failed ? 1 : 0);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(2);
});
