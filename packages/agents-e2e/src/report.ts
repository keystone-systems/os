// Progressive YAML report (REQ-031.1-031.5, NFR-004)

export type CheckStatus = "pass" | "fail" | "skip" | "running";

export interface CheckResult {
  name: string;
  status: CheckStatus;
  started_at: string;
  completed_at: string | null;
  details: string;
}

interface ReportData {
  harness: {
    product_agent: string;
    engineer_agent: string;
    platform: string;
    provider: string;
    template_repo: string;
    started_at: string;
    completed_at: string | null;
  };
  checks: CheckResult[];
}

export class Report {
  private data: ReportData;
  failed = false;

  constructor(config: {
    productAgent: string;
    engineerAgent: string;
    platform: string;
    provider: string;
    templateRepo: string;
  }) {
    this.data = {
      harness: {
        product_agent: config.productAgent,
        engineer_agent: config.engineerAgent,
        platform: config.platform,
        provider: config.provider,
        template_repo: config.templateRepo,
        started_at: new Date().toISOString(),
        completed_at: null,
      },
      checks: [],
    };
  }

  check(name: string, status: CheckStatus, details = "") {
    const now = new Date().toISOString();
    this.data.checks.push({
      name,
      status,
      started_at: now,
      completed_at: status === "running" ? null : now,
      details,
    });
    if (status === "fail") this.failed = true;
  }

  finalize() {
    this.data.harness.completed_at = new Date().toISOString();
  }

  toYaml(): string {
    const h = this.data.harness;
    const lines = [
      `# ks agents e2e report -- ${h.started_at}`,
      `harness:`,
      `  product_agent: "${h.product_agent}"`,
      `  engineer_agent: "${h.engineer_agent}"`,
      `  platform: "${h.platform}"`,
      `  provider: "${h.provider}"`,
      `  template_repo: "${h.template_repo}"`,
      `  started_at: "${h.started_at}"`,
      `  completed_at: ${h.completed_at ? `"${h.completed_at}"` : "null"}`,
      `checks:`,
    ];

    for (const c of this.data.checks) {
      lines.push(`  - name: "${c.name}"`);
      lines.push(`    status: "${c.status}"`);
      lines.push(`    started_at: "${c.started_at}"`);
      lines.push(
        `    completed_at: ${c.completed_at ? `"${c.completed_at}"` : "null"}`,
      );
      lines.push(`    details: "${c.details.replace(/"/g, '\\"')}"`);
    }

    return `${lines.join("\n")}\n`;
  }

  print(formatted: boolean) {
    if (formatted) {
      this.printFormatted();
    } else {
      process.stdout.write(this.toYaml());
    }
  }

  private printFormatted() {
    const icons: Record<CheckStatus, string> = {
      pass: "\x1b[32m+\x1b[0m",
      fail: "\x1b[31mx\x1b[0m",
      skip: "\x1b[33m-\x1b[0m",
      running: "\x1b[36m~\x1b[0m",
    };

    for (const c of this.data.checks) {
      const detail = c.details ? ` (${c.details})` : "";
      console.log(`  ${icons[c.status]} ${c.name}${detail}`);
    }

    console.log();
    const counts = this.data.checks.reduce(
      (acc, c) => {
        acc[c.status] = (acc[c.status] ?? 0) + 1;
        return acc;
      },
      {} as Record<string, number>,
    );
    console.log(
      `  ${counts.pass ?? 0} passed, ${counts.fail ?? 0} failed, ${counts.skip ?? 0} skipped`,
    );
  }
}
