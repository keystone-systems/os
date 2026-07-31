// Agent control wrapper -- calls agentctl subprocess

export class AgentCtl {
  async isPaused(agent: string): Promise<boolean> {
    const proc = Bun.spawn(["agentctl", agent, "paused"], {
      stdout: "pipe",
      stderr: "pipe",
    });
    const code = await proc.exited;
    return code === 0;
  }

  async hasTasks(agent: string): Promise<boolean> {
    const proc = Bun.spawn(["agentctl", agent, "tasks"], {
      stdout: "pipe",
      stderr: "pipe",
    });
    const output = await new Response(proc.stdout).text();
    await proc.exited;
    return /in.progress|running|active/i.test(output);
  }

  async pause(agent: string, reason: string): Promise<boolean> {
    const proc = Bun.spawn(["agentctl", agent, "pause", reason], {
      stdout: "pipe",
      stderr: "pipe",
    });
    return (await proc.exited) === 0;
  }

  async resume(agent: string): Promise<boolean> {
    const proc = Bun.spawn(["agentctl", agent, "resume"], {
      stdout: "pipe",
      stderr: "pipe",
    });
    return (await proc.exited) === 0;
  }

  async exists(agent: string): Promise<boolean> {
    const proc = Bun.spawn(["agentctl"], {
      stdout: "pipe",
      stderr: "pipe",
    });
    const output = await new Response(proc.stdout).text();
    const stderr = await new Response(proc.stderr).text();
    await proc.exited;
    const all = output + stderr;
    const match = all.match(/Known agents:\s*(.+)/);
    if (!match) return false;
    const agents = match[1].split(",").map((s) => s.trim());
    return agents.includes(agent);
  }
}
