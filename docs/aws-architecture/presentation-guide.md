# Presentation Guide — 30-Minute Panel

3-person panel, 30 minutes total. Budget **20 minutes for your walkthrough** and
**10 minutes for Q&A** (panels always have questions — protecting that time shows
confidence and respect for their expertise).

---

## Pacing Overview

| Block | Minutes | Section | What you're doing |
|-------|---------|---------|-------------------|
| 1 | 0:00–2:00 | Opening | Set context, state your design goals |
| 2 | 2:00–6:00 | High-level architecture | Walk the top-level diagram (Cloudflare → regions → ALB → ECS → data) |
| 3 | 6:00–10:00 | Single-region deep dive | Zoom into one region: VPC, 3-AZ layout, subnet tiers, VPC endpoints |
| 4 | 10:00–12:00 | Async + Data | SQS → Lambda pattern, Aurora Global Database, S3 CRR |
| 5 | 12:00–14:00 | Observability & Security | Hit the highlights, don't enumerate — show you thought about it |
| 6 | 14:00–17:00 | Part B: Code structure + CI/CD | Terragrunt layout, branching, pipeline stages |
| 7 | 17:00–19:00 | Apply strategy + State | Multi-region sequential apply, S3 native locking |
| 8 | 19:00–20:00 | Close | Summarize key design decisions, invite questions |
| 9 | 20:00–30:00 | Q&A | Panel questions |

---

## Block-by-Block Script

### Block 1 — Opening (2 min)

**Goal:** Frame the problem so the panel knows what they're evaluating.

> "The brief asked for a multi-region, multi-AZ infrastructure on AWS for
> services and async functions, managed as IaC. I'll walk you through my
> design in two parts: the architecture itself, then how I'd manage it
> with Terraform and Terragrunt in a CI/CD pipeline."

Hit these three points:
- **ECS Fargate** for container orchestration (and why — no cluster management, native AWS, simpler than EKS for service workloads)
- **Cloudflare** at the edge for DNS, WAF, and CDN (vendor diversity, cost-effective, defense in depth)
- **Terraform + Terragrunt** for IaC (DRY config, dependency management, multi-account)

Don't justify every choice yet — just plant the seeds. You'll come back to them.

---

### Block 2 — High-Level Architecture (4 min)

**Goal:** Establish the multi-region topology in the panel's mental model.

Walk the diagram **top to bottom, left to right**:

1. **Cloudflare edge** — "DNS resolves globally via anycast. Cloudflare runs health checks against both origins and routes traffic via geo-DNS or weighted routing. WAF and DDoS protection happen here before traffic ever hits AWS."

2. **Two regions** — "us-east-1 and us-west-2, each independently operational. The design supports active/active for reads and active/standby for writes, with Aurora Global Database handling cross-region replication."

3. **Per-region stack** — "Each region has its own ALB, ECS Fargate cluster, and data layer. If one region goes down, Cloudflare health checks detect it and shifts traffic."

**Tip:** Point at the diagram as you talk. If presenting on screen, zoom into the high-level diagram and leave it visible while you narrate. Don't read the diagram — tell the *story* of a request flowing through it.

---

### Block 3 — Single-Region Deep Dive (4 min)

**Goal:** Show you understand networking and AZ redundancy at depth.

Walk the single-region diagram:

1. **VPC structure** — "/16 CIDR, three availability zones, three subnet tiers"

2. **Subnet tiers** (spend a moment on each):
   - Public: ALB nodes, NAT Gateways — "one NAT per AZ so a single AZ failure doesn't take out outbound connectivity for the others"
   - Private: ECS Fargate tasks — "api and web services run here, no direct internet exposure"
   - Data: Aurora RDS — "fully isolated, no internet route"

3. **VPC Endpoints** — "PrivateLink for S3, ECR, CloudWatch, SQS, Secrets Manager. AWS API traffic stays on the AWS backbone, never traverses the internet or NAT."

4. **Service Discovery** — "Cloud Map provides internal DNS so services find each other without hardcoded IPs or load balancers for internal traffic."

**Tip:** This is where infrastructure depth shows. The NAT-per-AZ and VPC endpoint decisions are the kind of detail that separates someone who's done this from someone who's read about it.

---

### Block 4 — Async + Data (2 min)

**Goal:** Show the async pattern is intentionally simple, and the data layer supports the multi-region story.

**Async (1 min):**
> "For async work I chose the lightest-weight pattern available: SQS plus Lambda.
> ECS services enqueue messages, Lambda functions trigger automatically via event
> source mapping — no polling code, no dedicated worker fleet. Each queue has a
> dead-letter queue, and a CloudWatch alarm fires to SNS if anything lands there."

If asked why not Step Functions, EventBridge, Kinesis: *"Those are tools I'd
reach for when specific needs arise — ordering, replay, multi-step orchestration.
For the baseline, SQS + Lambda is the lowest operational overhead."*

**Data (1 min):**
- Aurora Global Database — "Sub-second RPO, under one minute RTO for cross-region failover. Primary writer in Region 1, read replicas in both regions."
- S3 with CRR — "Cross-region replication for assets and backups. Versioning enabled, lifecycle policies for cost management."

---

### Block 5 — Observability & Security (2 min)

**Goal:** Don't enumerate every service — show you think in layers.

**Observability (1 min):**
> "Four pillars: metrics via CloudWatch and Container Insights, logs via the
> awslogs driver to CloudWatch, tracing via X-Ray, and alerting via CloudWatch
> Alarms routed through SNS to PagerDuty or Slack. I'd also run CloudWatch
> Synthetics canaries for external health validation."

**Security (1 min):**
> "Defense in depth: Cloudflare WAF at the edge, AWS WAF on the ALB behind it.
> No long-lived credentials anywhere — CI/CD authenticates via OIDC federation.
> ECS tasks get least-privilege IAM roles. Secrets Manager handles database
> credentials with auto-rotation. And on the audit side: CloudTrail, Config,
> GuardDuty, Security Hub, and Inspector for container image scanning in ECR."

**Tip:** Resist the urge to explain what GuardDuty *does*. The panel knows.
Mentioning it shows you'd include it. If they want details, they'll ask in Q&A.

---

### Block 6 — Code Structure + CI/CD (3 min)

**Goal:** This is Part B — show you've thought about how real teams manage this.

**Terragrunt layout (1.5 min):**
- "Monorepo. Reusable Terraform modules in `modules/`, environment-specific
  config in `live/{env}/{region}/{component}/`."
- "Terragrunt's `include` and `dependency` blocks keep each leaf config minimal
  while expressing the dependency graph — VPC before ECS, ALB before services."
- "The `_envcommon/` partials hold shared defaults so dev, staging, and prod
  stay consistent."
- Show or reference the root `terragrunt.hcl` with `use_lockfile = true`.

**Branching + Pipeline (1.5 min):**
- "Trunk-based development. Short-lived feature branches, PRs trigger
  `terragrunt plan` with the output posted as a PR comment."
- "Pipeline runs fmt, validate, tflint, and tfsec on every PR — security
  scanning is not an afterthought."
- "Merge to main auto-applies to dev. Staging and prod are manual
  workflow_dispatch with a GitHub Environment approval gate on prod."

---

### Block 7 — Apply Strategy + State (2 min)

**Goal:** Show you've thought about blast radius and safe rollout.

**Multi-region apply (1 min):**
> "For prod, regions are applied sequentially. Region 1 applies and runs canary
> health checks. Only if those pass does Region 2 proceed. If Region 1 fails,
> we halt and don't touch Region 2 — this prevents a bad change from breaking
> both regions simultaneously."

**State management (30 sec):**
> "S3 backend with native locking — Terraform 1.10+ and Terragrunt 1.0+ support
> S3 conditional writes via `use_lockfile`, so no DynamoDB lock table needed.
> One state file per component stack. Versioning enabled for rollback."

**Drift detection (30 sec):**
> "A scheduled daily pipeline runs `terragrunt plan` across all environments.
> If drift is detected, it opens a GitHub Issue and fires a Slack alert."

---

### Block 8 — Close (1 min)

**Goal:** Land the plane. Summarize the *decisions*, not the components.

> "To summarize the key decisions: ECS Fargate for services because it removes
> cluster management overhead. SQS plus Lambda for async because it's the
> lightest-weight pattern. Cloudflare at the edge for vendor diversity and
> cost-effective WAF. Aurora Global Database for the cross-region data story.
> And Terragrunt to keep the IaC DRY across accounts, regions, and environments
> with a CI/CD pipeline that has safety gates at every promotion stage."

Then: *"I'm happy to take questions."*

---

### Block 9 — Q&A (10 min)

**Likely questions and how to handle them:**

| Question | Key point to make |
|----------|-------------------|
| "Why ECS over EKS?" | Simpler for service-oriented workloads, no control plane management, native AWS integration. EKS is better when you need the Kubernetes ecosystem (custom operators, service mesh, multi-cloud portability). |
| "Why Cloudflare instead of just Route 53 + CloudFront?" | Vendor diversity (DNS + DDoS outside AWS), integrated WAF at no extra cost on Pro plan, simpler than managing CloudFront distributions + Shield + Route 53 health checks separately. |
| "How do you handle failover?" | Cloudflare health checks detect origin failure and stop routing to that region. Aurora Global Database promotes the secondary to writer. RTO under 1 minute for the database, DNS failover depends on TTL (Cloudflare can be very fast). |
| "What about cost?" | Fargate Spot for non-critical tasks, S3 Intelligent-Tiering, right-sizing ECS tasks via Container Insights metrics, Infracost in the CI pipeline to catch cost changes at PR time. |
| "Why not a multi-account setup?" | The design assumes it — `accounts/` directory with prod, staging, dev, security. Each env applies via OIDC to its own account. I'd elaborate if the panel wants details on the org structure. |
| "How do you rollback?" | Revert the commit in git, merge to main, pipeline re-applies the previous state. S3 state versioning provides a safety net. For ECS, blue/green deploys via CodeDeploy allow instant rollback at the service level. |
| "What if you need to scale this to more services?" | Add a new `ecs-service` module instance under `compute/`. Terragrunt's structure means a new service is a new `terragrunt.hcl` leaf that includes `_envcommon/ecs-service.hcl` — a few lines of config. |

**General Q&A tips:**
- If you don't know, say *"I haven't implemented that specifically, but my approach would be..."* — never bluff.
- If a question is about something you intentionally excluded (Step Functions, Kinesis, ElastiCache), say *"I considered it but excluded it to keep the design focused on [X]. I'd add it when [specific trigger]."*
- Keep answers to 60–90 seconds. A concise answer is always better than a rambling one.

---

## Presentation Tips

- **Don't read the diagrams.** Tell the story of a request, a deployment, or a failure — and point to the diagram as you go.
- **Use "we" not "I"** when talking about operations ("we'd deploy...", "we'd monitor..."). It signals you think about team workflows, not solo heroics.
- **Name your tradeoffs.** Saying "I chose X over Y because Z" is more impressive than just presenting X. The panel wants to see your decision-making, not just your knowledge of AWS services.
- **Watch the clock.** If you're at 10 minutes and still on the single-region diagram, skip ahead to Part B. The CI/CD and apply strategy section is where you differentiate from someone who just drew boxes.
