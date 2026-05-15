# Presentation Guide — 30 + 30 Panel Format

3-person panel. **30 minutes for your walkthrough**, then **30 minutes of panel
Q&A**. You own the first half entirely — use the time to go deep where it
matters. The Q&A is where the panel probes your thinking, so the prep for that
section is just as important as the presentation itself.

---

## Pacing Overview

| Block | Minutes | Section | What you're doing |
|-------|---------|---------|-------------------|
| 1 | 0:00–3:00 | Opening | Set context, state design goals and key choices |
| 2 | 3:00–9:00 | High-level architecture | Walk the top-level diagram (Cloudflare → regions → ALB → ECS → data) |
| 3 | 9:00–15:00 | Single-region deep dive | Zoom into one region: VPC, 3-AZ layout, subnet tiers, VPC endpoints |
| 4 | 15:00–19:00 | Async + Data | SQS → Lambda pattern, Aurora Global Database, S3 CRR |
| 5 | 19:00–22:00 | Observability & Security | Talk in layers, not service lists |
| 6 | 22:00–26:00 | Part B: Code structure + CI/CD | Terragrunt layout, branching, pipeline stages |
| 7 | 26:00–29:00 | Apply strategy + State | Multi-region sequential apply, S3 native locking, drift detection |
| 8 | 29:00–30:00 | Close | Summarize design decisions, transition to Q&A |

---

## Block-by-Block Script

### Block 1 — Opening (3 min)

**Goal:** Frame the problem so the panel knows what they're evaluating.

> "The brief asked for a multi-region, multi-AZ infrastructure on AWS for
> services and async functions, managed as Infrastructure-as-Code. I'll walk
> you through my design in two parts: the architecture itself — networking,
> compute, data, async, observability, and security — then how I'd manage
> all of it with Terraform and Terragrunt in a CI/CD pipeline."

Hit these three choices and briefly say *why* — these are the threads you'll
pull on throughout:

- **ECS Fargate** for container orchestration — "I chose Fargate over EKS
  because for a service-oriented workload, it removes cluster management
  entirely. No node groups, no control plane upgrades, no kubelet patching.
  AWS handles the compute layer, and we focus on task definitions and service
  config."

- **Cloudflare** at the edge — "Rather than using Route 53 and CloudFront
  exclusively, I placed Cloudflare in front for DNS, WAF, and CDN. This gives
  us vendor diversity — our DNS and DDoS protection don't go down if AWS has
  a regional issue — and Cloudflare's integrated WAF and CDN are simpler
  and more cost-effective than assembling Shield, CloudFront, and WAF
  separately."

- **Terraform + Terragrunt** — "Terragrunt gives us DRY configuration across
  multiple accounts, regions, and environments. Each infrastructure component
  is an isolated state file with explicit dependency declarations, which
  limits blast radius and enables targeted applies."

Don't go deep on any of these yet — you're planting seeds that you'll come back
to. The panel now has a mental framework for everything that follows.

---

### Block 2 — High-Level Architecture (6 min)

**Goal:** Establish the multi-region topology. This is the "hero" diagram — make
it land.

Walk the diagram **top to bottom**, telling the story of a user request:

1. **Cloudflare edge (1.5 min)** — "A user's DNS query resolves via Cloudflare's
   anycast network — roughly 300 points of presence globally. Cloudflare runs
   active health checks against our ALB endpoints in both AWS regions. Based on
   geo-DNS or weighted routing rules, it directs the user to the nearest healthy
   region. Before the request even reaches AWS, Cloudflare has already applied
   WAF rules, rate limiting, and bot detection. Static assets can be served
   directly from Cloudflare's CDN cache without hitting origin at all."

2. **Two regions (2 min)** — "We deploy into us-east-1 and us-west-2. Each
   region is fully independently operational — its own ALB, its own ECS cluster,
   its own Aurora replica. The design is active/active for reads: both regions
   serve read traffic from their local Aurora readers. Writes go to the Aurora
   primary in Region 1. If Region 1 fails, Aurora Global Database promotes the
   Region 2 secondary to a writer — RPO under one second, RTO under one minute."

3. **Per-region stack (1.5 min)** — "Inside each region, the stack follows a
   standard three-tier pattern: public subnets for the ALB and NAT gateways,
   private subnets for ECS Fargate tasks, and isolated data subnets for Aurora.
   The ALB terminates TLS — certificates managed by ACM — and routes to ECS
   services based on path or host rules."

4. **Failover scenario (1 min)** — Walk through a concrete failure: "If
   us-east-1 goes down — let's say an AZ outage cascades — Cloudflare's health
   checks fail for that origin within seconds. It stops routing traffic there.
   All requests now go to us-west-2, which was already serving read traffic and
   has a warm ECS cluster. The Aurora secondary promotes to writer. From the
   user's perspective, they might see a brief increase in latency as they're
   now hitting the farther region, but availability is maintained."

**Tip:** Telling the failover story here is powerful. It's not a separate topic —
it's a proof that the diagram actually works under pressure.

---

### Block 3 — Single-Region Deep Dive (6 min)

**Goal:** Show you understand networking fundamentals and AZ redundancy at depth.
This is where you demonstrate that you've actually built this, not just drawn
boxes.

Walk the single-region diagram layer by layer:

1. **VPC structure (1 min)** — "/16 CIDR gives us 65,000 addresses. Three
   availability zones — AZ-a, AZ-b, AZ-c. We divide the VPC into three subnet
   tiers, each deployed across all three AZs."

2. **Public subnets (1.5 min)** — "These hold the ALB nodes and NAT Gateways.
   Key design decision: **one NAT Gateway per AZ**. This costs more than a
   single NAT, but it means an AZ failure doesn't take out outbound internet
   connectivity for private subnets in the surviving AZs. The ALB is
   automatically distributed across all three AZs by AWS."

3. **Private subnets (1.5 min)** — "ECS Fargate tasks run here — our api and
   web services. No direct internet exposure. Outbound traffic (for pulling
   images, calling third-party APIs) goes through the NAT Gateway in the
   same AZ. ECS services are configured to spread tasks across all three AZs
   for redundancy."

4. **Data subnets (1 min)** — "Fully isolated — no route to an internet gateway
   or NAT. Aurora's multi-AZ replicas sit here. The only way in or out is
   through security groups that allow traffic from the private subnets on the
   database port."

5. **VPC Endpoints + Service Discovery (1 min)** — "We use PrivateLink endpoints
   for S3, ECR, CloudWatch Logs, SQS, and Secrets Manager. This means AWS API
   traffic never traverses the internet or burns NAT Gateway bandwidth — it
   stays on the AWS backbone. For service-to-service communication, Cloud Map
   provides internal DNS under a `.local` namespace so services discover each
   other without hardcoded IPs."

**Tip:** The NAT-per-AZ decision and VPC endpoints are the kind of detail that
separates someone who has run production infrastructure from someone who
followed a tutorial. Linger on these.

---

### Block 4 — Async + Data (4 min)

**Goal:** Show the async pattern is intentionally simple, and the data layer
directly supports the multi-region story.

**Async (2 min):**

> "For asynchronous work, I chose the lightest-weight pattern available on AWS:
> SQS plus Lambda."

Walk the diagram:
- "ECS services enqueue messages to SQS using standard `SendMessage` calls.
  Lambda functions are attached to each queue via an event source mapping —
  AWS manages the polling, batching, and invocation automatically. There's no
  polling code to write, no dedicated worker fleet to manage, no auto-scaling
  rules to tune for workers."
- "Each queue has a paired dead-letter queue. After a configurable number of
  receive attempts — say three — failed messages land in the DLQ. A CloudWatch
  Alarm monitors DLQ depth and fires to SNS, which routes to our alerting
  channel."
- "Lambda concurrency is controlled per-function via reserved concurrency,
  which also acts as a natural throttle to protect downstream resources."

Preempt the "why not X" question:
> "I intentionally kept this simple. If we later need message ordering, we'd
> reach for SQS FIFO or Kinesis. If we need multi-step orchestration, Step
> Functions. If we need fan-out, SNS in front of SQS. But for the baseline
> architecture, SQS plus Lambda is the lowest operational overhead and cost."

**Data (2 min):**

- **Aurora Global Database (1.5 min):** "Aurora PostgreSQL with a Global
  Database configuration. The primary cluster in us-east-1 has a writer
  instance and two read replicas. The secondary cluster in us-west-2 has
  its own read replica. Replication is asynchronous with sub-second RPO.
  In a failover, the secondary promotes to a full read-write cluster in
  under a minute. Both regions use Aurora's reader endpoint for read
  traffic, so we get active/active reads with a single write endpoint."

- **S3 (30 sec):** "S3 with cross-region replication for assets and backups.
  Versioning is enabled, and lifecycle policies handle cost management via
  Intelligent-Tiering."

---

### Block 5 — Observability & Security (3 min)

**Goal:** Talk in layers and categories, not service lists. Show you think about
*why* these exist, not just *which* ones to turn on.

**Observability (1.5 min):**

> "I think about observability in four pillars."

- **Metrics:** "CloudWatch metrics and Container Insights for ECS task-level
  CPU, memory, and network. We'd build dashboards per service and per region."
- **Logs:** "Application logs go to CloudWatch Logs via the `awslogs` driver
  on the ECS task definition. ALB access logs go to S3. VPC Flow Logs and
  CloudTrail provide the network and API audit trail."
- **Tracing:** "X-Ray or OpenTelemetry for distributed tracing across services.
  This is critical when you have multiple ECS services calling each other — you
  need to trace a request across service boundaries."
- **Alerting:** "CloudWatch Alarms with anomaly detection on key metrics —
  latency P99, error rate, CPU. Alarms route through SNS to PagerDuty or Slack.
  And CloudWatch Synthetics canaries run external health checks so we detect
  issues the way a user would."

**Security (1.5 min):**

> "Security is layered — edge to core."

- **Edge:** "Cloudflare WAF handles L7 filtering, bot management, and rate
  limiting before traffic hits AWS."
- **AWS perimeter:** "AWS WAF on the ALB as defense in depth. Security groups
  on ECS tasks enforce least-privilege port access — each service only accepts
  traffic from the ALB on its specific port."
- **Identity:** "No long-lived credentials anywhere. CI/CD authenticates via
  OIDC federation — GitHub Actions gets short-lived AWS tokens. ECS tasks have
  separate execution roles and task roles, each with least-privilege policies.
  Secrets Manager handles database credentials with auto-rotation."
- **Audit:** "CloudTrail for API audit, Config for resource compliance,
  GuardDuty for threat detection, Security Hub for aggregated findings,
  Inspector for container image vulnerability scanning in ECR."

**Tip:** Saying "defense in depth" and then showing two WAF layers demonstrates
the concept concretely. Saying "no long-lived credentials anywhere" is a strong
statement that sticks.

---

### Block 6 — Code Structure + CI/CD (4 min)

**Goal:** This is Part B. Show you've thought about how a team actually manages
this infrastructure day-to-day. This section differentiates you from someone
who just drew boxes.

**Terragrunt layout (2 min):**

> "The infrastructure is a monorepo managed with Terragrunt."

- "Reusable Terraform modules live in `modules/` — networking, compute, data,
  async, security, observability. Each module is a self-contained unit with
  its own variables, outputs, and versioning."
- "The `live/` directory mirrors reality: `live/{env}/{region}/{component}/`.
  So `live/prod/us-east-1/compute/api-service/terragrunt.hcl` is the ECS
  service definition for the API in prod us-east-1."
- "Each `terragrunt.hcl` leaf is minimal — it includes the root config for
  backend and provider setup, includes a shared partial from `_envcommon/` for
  defaults, and declares its dependencies. For example, the api-service depends
  on the ECS cluster, VPC, ALB, and IAM roles. Terragrunt resolves the
  dependency graph and applies in order."
- "The root `terragrunt.hcl` configures the S3 backend with `use_lockfile = true`
  for native S3 state locking — no DynamoDB table needed."

**Branching + Pipeline (2 min):**

- "Trunk-based development. `main` is protected. All changes go through
  short-lived feature branches and pull requests."
- "On PR, the pipeline runs `terraform fmt`, `validate`, `tflint` for linting,
  and `tfsec` for security scanning. Then it detects which stacks changed
  and runs `terragrunt plan` only for those — the plan output is posted as
  a PR comment so reviewers see exactly what will change."
- "We also run Infracost on PRs to surface cost impact before merge."
- "Merge to main auto-applies to the **dev** environment. Staging is a manual
  `workflow_dispatch` trigger. Prod requires manual trigger **plus** a GitHub
  Environment approval gate — someone on the team has to explicitly approve
  the production apply."
- "CI/CD authenticates to AWS via OIDC federation. No static access keys, no
  secrets stored in GitHub. Each environment assumes a different IAM role in
  its respective AWS account."

---

### Block 7 — Apply Strategy + State (3 min)

**Goal:** Show you've thought about blast radius, safe rollout, and operational
recovery.

**Multi-region apply (1.5 min):**

> "For production, the two regions are applied sequentially — never in parallel."

- "Region 1 applies first. After apply, we run canary health checks — HTTP
  endpoint validation, database connectivity, key functional checks."
- "Only if Region 1's health checks pass does Region 2 proceed."
- "If Region 1 fails, we halt immediately. Region 2 is untouched, so it's still
  running the known-good configuration and serving traffic via Cloudflare
  failover."
- "This means a bad Terraform change can never break both regions simultaneously.
  The blast radius of any single apply is one region."

**State management (1 min):**

> "State is stored in S3 with native locking."

- "Terraform 1.10 and Terragrunt 1.0 support S3 conditional writes via
  `use_lockfile`. This places a `.tflock` file next to the state object in S3.
  No DynamoDB lock table to provision or manage."
- "One state file per component stack — so a change to the api-service doesn't
  risk the VPC state or the database state."
- "S3 versioning is enabled, so every state change is a version. If something
  goes wrong, the previous state version is recoverable."

**Drift detection (30 sec):**

> "A scheduled daily pipeline runs `terragrunt plan` across all environments and
> all stacks. If any plan shows a non-empty diff — meaning something changed
> outside of Terraform — it opens a GitHub Issue and fires a Slack alert. This
> catches manual console changes, unmanaged resources, and configuration drift."

---

### Block 8 — Close (1 min)

**Goal:** Land the plane. Summarize the *decisions*, not the components. Leave
them with your design philosophy, not a parts list.

> "To wrap up — the design philosophy here is simple: use the right tool at each
> layer, keep operational overhead low, and build safety into the deployment
> process.
>
> ECS Fargate for services because it removes cluster management entirely.
> SQS plus Lambda for async because it's the lightest-weight pattern with zero
> infrastructure to manage. Cloudflare at the edge for vendor diversity and
> cost-effective protection. Aurora Global Database for the cross-region data
> story with sub-second RPO. And Terragrunt to keep the IaC DRY across
> accounts, regions, and environments, with a CI/CD pipeline that has safety
> gates at every promotion stage and a sequential multi-region apply that
> limits blast radius.
>
> I'm looking forward to your questions."

---

## Q&A Prep (30 minutes)

With 30 minutes of Q&A from three panelists, expect 8–12 questions. Some will be
clarifying ("tell me more about X"), some will be probing ("what if Y happens"),
and some will be challenging ("why not Z"). Below are the likely categories with
prepared answers.

### Architecture Choices

| Question | How to answer |
|----------|---------------|
| **"Why ECS over EKS?"** | "For service-oriented workloads — a set of containerized services behind a load balancer — ECS Fargate is simpler. No control plane management, no node group AMI upgrades, no kubelet version skew. AWS manages the compute layer entirely. I'd choose EKS when the team needs the Kubernetes ecosystem — custom operators, service mesh, Helm charts, or multi-cloud portability via the K8s API. For this use case, ECS gets us there with less operational surface area." |
| **"Why Cloudflare instead of Route 53 + CloudFront?"** | "Three reasons. First, vendor diversity — if AWS has a control-plane issue, our DNS and DDoS protection are on a completely separate provider. Second, simplicity — Cloudflare integrates DNS, WAF, CDN, and health-check-based failover in one place, versus assembling Route 53 health checks, CloudFront distributions, AWS WAF, and Shield separately. Third, cost — Cloudflare's Pro plan includes WAF and DDoS at a flat rate, whereas AWS WAF and Shield Advanced are per-rule and per-resource charges." |
| **"Why Fargate over EC2 launch type?"** | "Fargate eliminates instance management — no AMI patching, no capacity planning, no cluster bin-packing optimization. The tradeoff is cost at scale: Fargate has a premium over equivalent EC2 on-demand pricing. For predictable baseline workloads, I'd use Fargate Spot for non-critical tasks and evaluate EC2 capacity providers if cost became a concern at scale. But for this design, the operational simplicity is the priority." |
| **"Would you consider a service mesh?"** | "Not for this scale. Service meshes like App Mesh or Istio add value when you have dozens of services with complex traffic routing, mTLS requirements, or fine-grained observability needs. With a handful of services, Cloud Map for discovery and ALB for routing covers what we need. X-Ray handles distributed tracing. I'd introduce a mesh when service-to-service communication patterns become complex enough to justify the overhead." |

### Async & Data

| Question | How to answer |
|----------|---------------|
| **"What if Lambda's 15-minute timeout isn't enough?"** | "If we have jobs that run longer than 15 minutes, I'd move those specific workloads to ECS tasks — either as a long-running ECS service that polls SQS, or as one-off ECS tasks triggered by EventBridge. The SQS + Lambda pattern stays for everything under 15 minutes. It's not all-or-nothing — you use the right compute for the job duration." |
| **"Why not EventBridge instead of SQS?"** | "EventBridge is an event bus — it's great for event routing, filtering, and fan-out to multiple targets. SQS is a queue — it's great for decoupling a producer from a consumer with durable, at-least-once delivery. For async job processing where one service says 'do this work,' SQS is the simpler primitive. I'd add EventBridge when we need scheduled triggers, cross-service event routing, or pattern-based filtering." |
| **"How do you handle poison messages?"** | "The dead-letter queue handles this. After a configurable `maxReceiveCount` — say three attempts — the message moves to the DLQ. A CloudWatch Alarm on the DLQ fires immediately. From there, we can inspect the message, fix the bug, and either replay the messages from the DLQ or discard them. The key is that a poison message doesn't block the main queue." |
| **"Why Aurora over standard RDS PostgreSQL?"** | "Aurora gives us two things that standard RDS doesn't: the Global Database feature for cross-region replication with sub-second RPO, and Aurora's storage layer which auto-scales and replicates six copies across three AZs. For a single-region design, standard RDS Multi-AZ would be fine. The multi-region requirement is what makes Aurora the right choice here." |
| **"How do you handle database migrations?"** | "ECS run-task. We run a one-off ECS task using the same container image as the api service, with the entrypoint overridden to run the migration tool — Flyway, Alembic, whatever the app uses. This task runs in the private subnet with access to the database. It's triggered as a pre-deploy step in the CI/CD pipeline before the new service version is rolled out." |

### Networking & Security

| Question | How to answer |
|----------|---------------|
| **"Why NAT Gateway per AZ instead of one shared NAT?"** | "Availability. If AZ-a goes down and all three private subnets route through AZ-a's NAT, the other two AZs lose outbound connectivity even though their compute is fine. One NAT per AZ means each AZ is self-contained. The cost is roughly $32/month per additional NAT Gateway — a small price for AZ-independent availability." |
| **"How do you handle TLS?"** | "Two layers. Cloudflare terminates the client-facing TLS connection at the edge. Between Cloudflare and the ALB, we use Cloudflare origin certificates or Full (Strict) mode with ACM certificates on the ALB. The ALB terminates TLS for ECS tasks — traffic between ALB and Fargate tasks is internal VPC traffic. If we need end-to-end encryption to the container, ECS supports TLS termination at the task level." |
| **"What about cross-region connectivity?"** | "For this design, the regions don't need to talk to each other directly — Aurora Global Database handles data replication at the storage layer, and S3 CRR handles object replication. If we later needed direct VPC-to-VPC communication across regions, we'd use a Transit Gateway with cross-region peering." |
| **"How do you prevent unauthorized access to the ALB directly, bypassing Cloudflare?"** | "Cloudflare origin pull certificates combined with an AWS WAF rule on the ALB that validates the Cloudflare client certificate. You can also restrict ALB security group ingress to Cloudflare's published IP ranges, though the WAF approach is more robust since IP ranges can change." |

### CI/CD & IaC

| Question | How to answer |
|----------|---------------|
| **"Why Terragrunt over plain Terraform workspaces?"** | "Terraform workspaces share the same backend configuration and state partition — they're designed for light environment variation, not multi-region, multi-account infrastructure. Terragrunt gives us isolated state files per component, explicit dependency graphs between stacks, DRY configuration via includes and partials, and automatic backend provisioning. It scales to hundreds of stacks in a way workspaces don't." |
| **"What if someone `terraform apply`s from their laptop?"** | "Two safeguards. First, IAM policies — the OIDC role used by CI/CD has apply permissions, but human users authenticate through IAM Identity Center with read-only roles. They can `terraform plan` locally but not apply. Second, state locking — `use_lockfile = true` means if CI/CD is running an apply, a local apply would fail to acquire the lock." |
| **"How do you handle secrets in Terraform?"** | "Secrets never live in Terraform code, tfvars files, or git. Database passwords and API keys are stored in AWS Secrets Manager. Terraform references them by ARN and passes them to ECS task definitions as secrets — the container runtime injects them as environment variables. Rotation is handled by Secrets Manager natively." |
| **"What does your rollback process look like?"** | "For infrastructure: revert the commit in git, merge to main, and the pipeline re-applies the previous configuration. S3 state versioning provides a safety net if the state itself gets corrupted. For application deployments: ECS supports blue/green via CodeDeploy — if the new task definition fails health checks, CodeDeploy automatically rolls back to the previous version." |
| **"How do you test Terraform modules?"** | "Three levels. First, `terraform validate` and `tflint` on every PR for syntax and best-practice checks. Second, `tfsec` or `checkov` for security policy scanning. Third, for critical modules, Terratest integration tests that spin up real resources in a sandbox account, validate behavior, and tear down. The sandbox account is isolated — tests can't affect real environments." |
| **"How do you handle breaking changes to a shared module?"** | "Module versioning. Terragrunt `source` references can pin to a git tag or a specific commit. When we make a breaking change to a module, we bump the version. Environments upgrade on their own schedule — dev first, then staging, then prod. The `_envcommon/` partials make this easy to coordinate." |

### Operational Scenarios

| Question | How to answer |
|----------|---------------|
| **"Walk me through a full region failure."** | "Cloudflare detects the origin health check failure in Region 1 — typically within 30 seconds depending on check interval. It removes Region 1 from the DNS pool. All traffic routes to Region 2, which is already running and serving reads. Aurora Global Database promotes the Region 2 secondary to a writer — under one minute. SQS queues in Region 2 start receiving new messages. Our RTO is under two minutes end-to-end. RPO is sub-second for the database, potentially a few minutes for S3 objects depending on CRR lag." |
| **"How do you handle a bad deploy that passes health checks?"** | "This is the subtle failure — the deploy looks healthy but introduces a logic bug. We catch this through CloudWatch anomaly detection on error rates and latency P99. If those metrics spike after a deploy, the alarm fires and the team investigates. For automated rollback, ECS CodeDeploy supports configurable alarm-based rollback — if a specific CloudWatch Alarm triggers during the deployment window, CodeDeploy auto-reverts. Additionally, the sequential region apply means Region 2 hasn't been updated yet, so it's still serving correct responses." |
| **"How do you scale this to 10+ services?"** | "The Terragrunt structure handles this well. Each new service is a new `terragrunt.hcl` leaf under `compute/` that includes `_envcommon/ecs-service.hcl`. The module handles task definition, service, auto-scaling, security group, and log group. Adding a service is a PR with one small config file. The ALB gets a new listener rule via the `alb-listener-rule` module. CI/CD automatically detects the new stack and includes it in plan/apply." |
| **"What about cost — isn't multi-region expensive?"** | "It roughly doubles infrastructure cost for the compute and networking layers. The key levers are: Fargate Spot for non-critical tasks in the secondary region, right-sizing via Container Insights metrics, S3 Intelligent-Tiering for storage, and Infracost in the CI pipeline so every PR shows its cost impact before merge. The business decision is whether the availability and RPO guarantees justify the cost. For many production systems, they do." |
| **"How do you onboard a new team member?"** | "The repo structure is self-documenting — `live/prod/us-east-1/compute/api-service/` tells you exactly what it manages. The `_envcommon/` partials mean a new team member only needs to understand the leaf config, not the full module internals. For day-to-day work, they branch, edit a `terragrunt.hcl`, push a PR, and the pipeline shows them the plan. They never need to run apply locally. Runbooks in `docs/runbooks/` cover operational procedures — failover, scaling, incident response." |

### General Q&A Tips

- **Keep answers to 60–90 seconds.** A concise answer shows mastery. A rambling
  answer shows uncertainty. If they want more depth, they'll follow up.
- **If you don't know, say so honestly.** "I haven't implemented that
  specifically, but my approach would be..." is always better than bluffing.
  Panels respect intellectual honesty.
- **If a question is about something you intentionally excluded** (Step
  Functions, Kinesis, ElastiCache, EKS), frame it as a deliberate choice: "I
  considered it and decided against it for this design because [reason]. I'd
  add it when [specific trigger]."
- **If a panelist is testing your depth**, they'll ask follow-up questions on
  your answer. This is a good sign — it means you said something interesting.
  Go one level deeper, then stop.
- **Watch for the "what would you do differently" question.** This usually comes
  near the end. Have an honest answer ready: "If I were doing this for a real
  production system with [specific constraint], I'd probably add [X] and
  reconsider [Y]." Self-awareness about tradeoffs is what they're looking for.

---

## Presentation Tips

- **Don't read the diagrams.** Tell the story of a request, a deployment, or a
  failure — and point to the diagram as you go. The diagram is a visual anchor,
  not a script.
- **Use "we" not "I"** when talking about operations ("we'd deploy...", "we'd
  monitor..."). It signals you think about team workflows, not solo heroics.
- **Name your tradeoffs.** Saying "I chose X over Y because Z" is more
  impressive than just presenting X. The panel wants to see your
  decision-making process, not just your knowledge of AWS services.
- **Pace yourself.** You have 30 full minutes. There's no need to rush. Pausing
  after making a key point gives the panel time to absorb it and signals
  confidence.
- **If you finish early, that's fine.** Ending at 25 minutes with a strong close
  is better than padding to 30 with filler. It gives the panel more Q&A time,
  which they'll appreciate.
- **Bring water.** 30 minutes of talking is a lot. Take a sip during natural
  transitions between sections.
