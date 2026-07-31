// Forgejo platform abstraction (REQ-031.42-031.44)

export class ForgejoPlatform {
  constructor(
    private baseUrl: string,
    private token: string,
  ) {}

  private async api<T>(
    method: string,
    endpoint: string,
    body?: unknown,
  ): Promise<T> {
    const url = `${this.baseUrl}/api/v1${endpoint}`;
    const resp = await fetch(url, {
      method,
      headers: {
        Authorization: `token ${this.token}`,
        "Content-Type": "application/json",
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (!resp.ok) {
      throw new Error(
        `Forgejo API ${method} ${endpoint}: ${resp.status} ${resp.statusText}`,
      );
    }
    if (resp.status === 204) return undefined as T;
    return resp.json() as Promise<T>;
  }

  async repoExists(repo: string): Promise<boolean> {
    try {
      await this.api("GET", `/repos/${repo}`);
      return true;
    } catch {
      return false;
    }
  }

  async deleteRepo(repo: string): Promise<void> {
    try {
      await this.api("DELETE", `/repos/${repo}`);
    } catch {
      // Ignore 404
    }
  }

  async forkRepo(sourceRepo: string, targetOrg: string): Promise<unknown> {
    return this.api("POST", `/repos/${sourceRepo}/forks`, {
      organization: targetOrg,
    });
  }

  async listMilestones(repo: string, state = "open"): Promise<Milestone[]> {
    return this.api("GET", `/repos/${repo}/milestones?state=${state}&limit=50`);
  }

  async createMilestone(repo: string, title: string): Promise<Milestone> {
    return this.api("POST", `/repos/${repo}/milestones`, { title });
  }

  async listIssues(
    repo: string,
    state = "open",
    milestone?: string,
  ): Promise<Issue[]> {
    let qs = `state=${state}&limit=50`;
    if (milestone) qs += `&milestone=${milestone}`;
    return this.api("GET", `/repos/${repo}/issues?${qs}`);
  }

  async createIssue(
    repo: string,
    opts: {
      title: string;
      body?: string;
      milestone?: number;
      assignees?: string[];
    },
  ): Promise<Issue> {
    return this.api("POST", `/repos/${repo}/issues`, opts);
  }

  async closeIssue(repo: string, issueNumber: number): Promise<void> {
    await this.api("PATCH", `/repos/${repo}/issues/${issueNumber}`, {
      state: "closed",
    });
  }

  async listPrs(repo: string, state = "open"): Promise<PullRequest[]> {
    return this.api("GET", `/repos/${repo}/pulls?state=${state}&limit=50`);
  }

  async listBranches(repo: string): Promise<Branch[]> {
    return this.api("GET", `/repos/${repo}/branches?limit=50`);
  }

  async commentIssue(
    repo: string,
    issueNumber: number,
    body: string,
  ): Promise<void> {
    await this.api("POST", `/repos/${repo}/issues/${issueNumber}/comments`, {
      body,
    });
  }
}

export interface Milestone {
  id: number;
  title: string;
  state: string;
}

export interface Issue {
  id: number;
  number: number;
  title: string;
  state: string;
  assignees?: { login: string }[];
}

export interface PullRequest {
  id: number;
  number: number;
  title: string;
  state: string;
}

export interface Branch {
  name: string;
}
