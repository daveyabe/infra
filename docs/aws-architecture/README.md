# Multi-Region AWS ECS Infrastructure Design

This document presents a production-grade, multi-region/multi-AZ infrastructure
design for deploying containerized services and asynchronous workloads on AWS,
fronted by Cloudflare for DNS, DDoS protection, and edge caching. The
infrastructure is managed entirely as code through Terraform and Terragrunt.

---

## Table of Contents

- [Part A — Architecture Diagram & Components](#part-a--architecture-diagram--components)
  - [High-Level Architecture](#high-level-architecture)
  - [Single-Region Detail View](#single-region-detail-view)
  - [Async / Event-Driven Processing](#async--event-driven-processing)
  - [Data Layer](#data-layer)
  - [Observability & Operations](#observability--operations)
  - [Security & Compliance](#security--compliance)
  - [Component Inventory](#component-inventory)
- [Part B — Code Structure, CI/CD & Apply Strategy](#part-b--code-structure-cicd--apply-strategy)
  - [Repository Layout](#repository-layout)
  - [Terragrunt Hierarchy](#terragrunt-hierarchy)
  - [Branching & Merging Strategy](#branching--merging-strategy)
  - [CI/CD Pipeline](#cicd-pipeline)
  - [Apply Methods & Promotion](#apply-methods--promotion)
  - [State Management](#state-management)

---

## Part A — Architecture Diagram & Components

### High-Level Architecture

The system spans two AWS regions (active/active or active/warm-standby) with
Cloudflare sitting at the edge. Each region contains a full, independently
operational stack.

```
                          ┌──────────────────────────────────────────────┐
                          │              CLOUDFLARE EDGE                 │
                          │                                              │
                          │  ┌─────────┐  ┌──────────┐  ┌───────────┐  │
                          │  │   DNS    │  │   WAF    │  │   CDN /   │  │
                          │  │ (Global  │  │ + DDoS   │  │  Caching  │  │
                          │  │ Anycast) │  │  Shield  │  │  (Pages   │  │
                          │  │         │  │          │  │   Rules)  │  │
                          │  └────┬────┘  └────┬─────┘  └─────┬─────┘  │
                          │       │            │              │         │
                          │       └──────┬─────┘──────────────┘         │
                          │              │ Geo-DNS / Weighted routing   │
                          │              │ Health checks per origin     │
                          └──────────────┼──────────────────────────────┘
                                         │
                          ┌──────────────┼──────────────┐
                          │              │              │
                 ┌────────▼───────┐            ┌───────▼────────┐
                 │  AWS REGION 1  │            │  AWS REGION 2  │
                 │  (us-east-1)   │            │  (us-west-2)   │
                 │                │            │                │
                 │  ┌──────────┐  │            │  ┌──────────┐  │
                 │  │   ALB    │  │            │  │   ALB    │  │
                 │  │ (public) │  │◄───────────►  │ (public) │  │
                 │  └────┬─────┘  │  Global    │  └────┬─────┘  │
                 │       │        │  Accelerator│       │        │
                 │  ┌────▼─────┐  │  (optional)│  ┌────▼─────┐  │
                 │  │   ECS    │  │            │  │   ECS    │  │
                 │  │ Fargate  │  │            │  │ Fargate  │  │
                 │  │ Cluster  │  │            │  │ Cluster  │  │
                 │  └────┬─────┘  │            │  └────┬─────┘  │
                 │       │        │            │       │        │
                 │  ┌────▼─────┐  │            │  ┌────▼─────┐  │
                 │  │  Data    │  │◄──Repl.───►│  │  Data    │  │
                 │  │  Layer   │  │            │  │  Layer   │  │
                 │  └──────────┘  │            │  └──────────┘  │
                 └────────────────┘            └────────────────┘
```

### Single-Region Detail View

Each region is deployed across three Availability Zones for full AZ-level
redundancy. Below is the networking and compute layout for one region.

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         AWS REGION (e.g. us-east-1)                             │
│                                                                                 │
│  ┌──── VPC (10.0.0.0/16) ─────────────────────────────────────────────────────┐ │
│  │                                                                             │ │
│  │  ┌─ AZ-a ────────────┐  ┌─ AZ-b ────────────┐  ┌─ AZ-c ────────────┐     │ │
│  │  │                    │  │                    │  │                    │     │ │
│  │  │  ┌──────────────┐  │  │  ┌──────────────┐  │  │  ┌──────────────┐  │     │ │
│  │  │  │Public Subnet │  │  │  │Public Subnet │  │  │  │Public Subnet │  │     │ │
│  │  │  │ 10.0.1.0/24  │  │  │  │ 10.0.2.0/24  │  │  │  │ 10.0.3.0/24  │  │     │ │
│  │  │  │  ┌────────┐  │  │  │  │  ┌────────┐  │  │  │  │  ┌────────┐  │  │     │ │
│  │  │  │  │  ALB   │  │  │  │  │  │  ALB   │  │  │  │  │  │  ALB   │  │  │     │ │
│  │  │  │  │ (node) │  │  │  │  │  │ (node) │  │  │  │  │  │ (node) │  │  │     │ │
│  │  │  │  └────────┘  │  │  │  │  └────────┘  │  │  │  │  └────────┘  │  │     │ │
│  │  │  │  NAT GW      │  │  │  │  NAT GW      │  │  │  │  NAT GW      │  │     │ │
│  │  │  └──────────────┘  │  │  └──────────────┘  │  │  └──────────────┘  │     │ │
│  │  │                    │  │                    │  │                    │     │ │
│  │  │  ┌──────────────┐  │  │  ┌──────────────┐  │  │  ┌──────────────┐  │     │ │
│  │  │  │Private Subnet│  │  │  │Private Subnet│  │  │  │Private Subnet│  │     │ │
│  │  │  │ 10.0.11.0/24 │  │  │  │ 10.0.12.0/24 │  │  │  │ 10.0.13.0/24 │  │     │ │
│  │  │  │              │  │  │  │              │  │  │  │              │  │     │ │
│  │  │  │ ┌──────────┐ │  │  │  │ ┌──────────┐ │  │  │  │ ┌──────────┐ │  │     │ │
│  │  │  │ │ECS Tasks │ │  │  │  │ │ECS Tasks │ │  │  │  │ │ECS Tasks │ │  │     │ │
│  │  │  │ │(Fargate) │ │  │  │  │ │(Fargate) │ │  │  │  │ │(Fargate) │ │  │     │ │
│  │  │  │ │          │ │  │  │  │ │          │ │  │  │  │ │          │ │  │     │ │
│  │  │  │ │ api-svc  │ │  │  │  │ │ api-svc  │ │  │  │  │ │ api-svc  │ │  │     │ │
│  │  │  │ │ web-svc  │ │  │  │  │ │ web-svc  │ │  │  │  │ │ web-svc  │ │  │     │ │
│  │  │  │ │ worker   │ │  │  │  │ │ worker   │ │  │  │  │ │ worker   │ │  │     │ │
│  │  │  │ └──────────┘ │  │  │  │ └──────────┘ │  │  │  │ └──────────┘ │  │     │ │
│  │  │  └──────────────┘  │  │  └──────────────┘  │  │  └──────────────┘  │     │ │
│  │  │                    │  │                    │  │                    │     │ │
│  │  │  ┌──────────────┐  │  │  ┌──────────────┐  │  │  ┌──────────────┐  │     │ │
│  │  │  │  Data Subnet │  │  │  │  Data Subnet │  │  │  │  Data Subnet │  │     │ │
│  │  │  │ 10.0.21.0/24 │  │  │  │ 10.0.22.0/24 │  │  │  │ 10.0.23.0/24 │  │     │ │
│  │  │  │              │  │  │  │              │  │  │  │              │  │     │ │
│  │  │  │  RDS (repl.) │  │  │  │  RDS (repl.) │  │  │  │  RDS (repl.) │  │     │ │
│  │  │  │  ElastiCache │  │  │  │  ElastiCache │  │  │  │  ElastiCache │  │     │ │
│  │  │  └──────────────┘  │  │  └──────────────┘  │  │  └──────────────┘  │     │ │
│  │  └────────────────────┘  └────────────────────┘  └────────────────────┘     │ │
│  │                                                                             │ │
│  │  ┌──── Shared Services ────────────────────────────────────────────────┐     │ │
│  │  │  VPC Endpoints: S3, ECR, CloudWatch Logs, SQS, Secrets Manager     │     │ │
│  │  │  Service Discovery: AWS Cloud Map (*.local namespace)               │     │ │
│  │  │  VPC Flow Logs → CloudWatch / S3                                    │     │ │
│  │  └────────────────────────────────────────────────────────────────────┘     │ │
│  └─────────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Async / Event-Driven Processing

Asynchronous workloads run on a combination of SQS queues, Lambda functions, and
ECS tasks triggered by EventBridge. This decouples long-running work from the
synchronous request path.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        EVENT-DRIVEN / ASYNC LAYER                           │
│                                                                              │
│                                                                              │
│    ┌──────────┐      ┌───────────┐      ┌──────────────────┐                │
│    │ API Svc  │─────►│    SQS    │─────►│   ECS Task       │                │
│    │ (ECS)    │      │  Queues   │      │   (worker svc)   │                │
│    └──────────┘      │           │      │   long-running   │                │
│         │            │ ┌───────┐ │      │   batch jobs     │                │
│         │            │ │ DLQ   │ │      └──────────────────┘                │
│         │            │ └───┬───┘ │                                          │
│         │            └─────┼─────┘                                          │
│         │                  │                                                 │
│         │                  ▼                                                 │
│         │            ┌───────────┐      ┌──────────────────┐                │
│         │            │CloudWatch │─────►│   SNS Alert      │                │
│         │            │  Alarm    │      │   (Ops Team)     │                │
│         │            └───────────┘      └──────────────────┘                │
│         │                                                                    │
│         │            ┌───────────┐      ┌──────────────────┐                │
│         ├───────────►│EventBridge│─────►│  Lambda Fn       │                │
│         │            │  Rules    │      │  (lightweight    │                │
│         │            │           │      │   transforms,    │                │
│         │            │ Scheduled │      │   notifications, │                │
│         │            │ + Event   │      │   webhooks)      │                │
│         │            └───────────┘      └──────┬───────────┘                │
│         │                                      │                            │
│         │            ┌───────────┐              │                            │
│         ├───────────►│    SNS    │◄─────────────┘                            │
│         │            │  Topics   │                                           │
│         │            │  (fan-out)│──────┬────────────────┐                   │
│         │            └───────────┘      │                │                   │
│         │                               ▼                ▼                   │
│         │                         ┌──────────┐    ┌──────────┐              │
│         │                         │  SQS Q1  │    │  SQS Q2  │              │
│         │                         │  (email) │    │  (audit) │              │
│         │                         └──────────┘    └──────────┘              │
│         │                                                                    │
│         │            ┌───────────┐      ┌──────────────────┐                │
│         └───────────►│  Kinesis  │─────►│  Lambda / Firehose│               │
│                      │  Data     │      │  → S3 Data Lake   │               │
│                      │  Streams  │      └──────────────────┘                │
│                      └───────────┘                                          │
│                                                                              │
│   ┌───────────────────────────────────────────────────────────────────┐      │
│   │  Step Functions — complex multi-step async workflows             │      │
│   │  (e.g. order processing, data pipeline orchestration)            │      │
│   │                                                                   │      │
│   │  Start ──► Validate ──► Process ──► Notify ──► Complete          │      │
│   │                │                                                  │      │
│   │                └──► Error ──► DLQ + SNS Alert                    │      │
│   └───────────────────────────────────────────────────────────────────┘      │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Data Layer

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              DATA LAYER                                      │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐    │
│   │  Amazon RDS (Aurora PostgreSQL) — Multi-AZ + Cross-Region Replica  │    │
│   │                                                                     │    │
│   │  Region 1 (Primary)              Region 2 (Read Replica / Standby) │    │
│   │  ┌────────────┐                  ┌────────────┐                    │    │
│   │  │  Writer    │───── async ─────►│  Reader    │                    │    │
│   │  │  Instance  │   replication    │  Instance  │                    │    │
│   │  └────────────┘                  └────────────┘                    │    │
│   │  ┌────────────┐                  ┌────────────┐                    │    │
│   │  │  Reader x2 │                  │  Reader x1 │                    │    │
│   │  └────────────┘                  └────────────┘                    │    │
│   │  Aurora Global Database (RPO < 1s, RTO < 1min failover)            │    │
│   └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐    │
│   │  Amazon ElastiCache (Redis) — Multi-AZ Cluster Mode               │    │
│   │                                                                     │    │
│   │  ┌────────┐  ┌────────┐  ┌────────┐                               │    │
│   │  │Primary │  │Replica │  │Replica │   Global Datastore for        │    │
│   │  │ AZ-a   │  │ AZ-b   │  │ AZ-c   │   cross-region replication   │    │
│   │  └────────┘  └────────┘  └────────┘                               │    │
│   └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐    │
│   │  Amazon S3 — Cross-Region Replication (CRR)                        │    │
│   │                                                                     │    │
│   │  ┌────────────────┐        CRR        ┌────────────────┐           │    │
│   │  │  app-assets    │──────────────────►│  app-assets    │           │    │
│   │  │  us-east-1     │                   │  us-west-2     │           │    │
│   │  └────────────────┘                   └────────────────┘           │    │
│   │  Versioning enabled · Lifecycle policies · S3 Intelligent-Tiering  │    │
│   └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐    │
│   │  Amazon DynamoDB Global Tables (optional, for session/config)      │    │
│   │  Multi-region active-active with <1s replication                    │    │
│   └─────────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Observability & Operations

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                       OBSERVABILITY & OPERATIONS                             │
│                                                                              │
│   ┌─── Monitoring ──────────────────────────────────────────────────────┐    │
│   │  CloudWatch Metrics, Logs, Dashboards (per-region)                  │    │
│   │  CloudWatch Container Insights (ECS task-level metrics)             │    │
│   │  CloudWatch Synthetics (canary health checks)                       │    │
│   │  X-Ray / OpenTelemetry (distributed tracing across services)        │    │
│   │  CloudWatch Cross-Account Observability (central pane of glass)     │    │
│   └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│   ┌─── Alerting ────────────────────────────────────────────────────────┐    │
│   │  CloudWatch Alarms → SNS → PagerDuty / Slack / OpsGenie            │    │
│   │  Composite Alarms for correlated failure detection                  │    │
│   │  Anomaly Detection on key metrics (latency, error rate, CPU)        │    │
│   └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│   ┌─── Logging ─────────────────────────────────────────────────────────┐    │
│   │  ECS → CloudWatch Logs (awslogs driver) → S3 archival              │    │
│   │  Lambda → CloudWatch Logs                                           │    │
│   │  ALB Access Logs → S3                                               │    │
│   │  VPC Flow Logs → CloudWatch / S3                                    │    │
│   │  CloudTrail → S3 + CloudWatch (API audit trail)                     │    │
│   │  Centralized log aggregation via Kinesis Firehose → S3 data lake    │    │
│   └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│   ┌─── Deployment & Ops ────────────────────────────────────────────────┐    │
│   │  ECR (Elastic Container Registry) — image storage per region        │    │
│   │    ECR Replication for cross-region image availability              │    │
│   │  ECS Service Auto Scaling (target tracking: CPU, request count)     │    │
│   │  Application Auto Scaling (step + scheduled)                        │    │
│   │  AWS CodeDeploy (blue/green ECS deployments)                        │    │
│   │  Systems Manager Parameter Store + Secrets Manager                  │    │
│   │  AWS Config (resource compliance tracking)                          │    │
│   │  AWS Backup (centralized backup policies for RDS, DynamoDB, EFS)    │    │
│   └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│   ┌─── Cost Management ────────────────────────────────────────────────┐    │
│   │  AWS Cost Explorer + Budgets + Anomaly Detection                    │    │
│   │  Resource tagging strategy (project, env, team, cost-center)        │    │
│   │  Fargate Spot for non-critical workloads                            │    │
│   │  Savings Plans / Reserved Instances for baseline capacity           │    │
│   │  S3 Intelligent-Tiering + Lifecycle policies                        │    │
│   └─────────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Security & Compliance

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        SECURITY & COMPLIANCE                                 │
│                                                                              │
│   ┌─── Identity & Access ───────────────────────────────────────────────┐    │
│   │  AWS Organizations (multi-account: prod, staging, dev, security)    │    │
│   │  IAM Roles (task execution role, task role — least privilege)        │    │
│   │  OIDC Federation for CI/CD (GitHub Actions → IAM, no long-lived     │    │
│   │    credentials)                                                      │    │
│   │  AWS SSO / IAM Identity Center for human access                     │    │
│   │  SCPs (Service Control Policies) at org level                       │    │
│   └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│   ┌─── Network Security ───────────────────────────────────────────────┐    │
│   │  Cloudflare WAF + Rate Limiting + Bot Management (edge)             │    │
│   │  AWS WAF on ALB (defense in depth)                                  │    │
│   │  Security Groups (per-service, least-privilege port access)         │    │
│   │  NACLs (subnet-level allow/deny)                                    │    │
│   │  VPC Endpoints (PrivateLink) — no internet traversal for AWS APIs   │    │
│   │  AWS Shield Advanced (DDoS protection — complements Cloudflare)     │    │
│   │  AWS Network Firewall (optional, for egress filtering)              │    │
│   └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│   ┌─── Data Protection ────────────────────────────────────────────────┐    │
│   │  KMS (customer-managed keys for encryption at rest)                 │    │
│   │  ACM (TLS certificates — ALB termination + Cloudflare origin certs) │    │
│   │  Secrets Manager (DB creds, API keys — auto-rotation)               │    │
│   │  S3 bucket policies + block public access                           │    │
│   │  RDS encryption at rest (KMS) + in transit (TLS)                    │    │
│   └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│   ┌─── Audit & Compliance ─────────────────────────────────────────────┐    │
│   │  CloudTrail (all API calls, multi-region, org trail)                │    │
│   │  AWS Config Rules (continuous compliance evaluation)                │    │
│   │  GuardDuty (threat detection — VPC flow, DNS, CloudTrail)           │    │
│   │  Security Hub (aggregated findings, CIS benchmarks)                 │    │
│   │  Inspector (container image vulnerability scanning in ECR)          │    │
│   │  Macie (S3 sensitive data discovery — if PII is stored)             │    │
│   └─────────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Component Inventory

A complete list of every component in the architecture, grouped by function.

#### Edge / DNS / CDN

| Component | Purpose |
|-----------|---------|
| Cloudflare DNS | Global anycast DNS with health-check-based failover between regions |
| Cloudflare WAF | Layer 7 firewall, bot management, rate limiting at the edge |
| Cloudflare CDN | Static asset caching, page rules, cache purge API |
| Cloudflare Argo (optional) | Smart routing to reduce latency to origin |
| AWS Global Accelerator (optional) | Anycast IPs with health-check failover (alternative to CF geo-routing) |

#### Networking

| Component | Purpose |
|-----------|---------|
| VPC (per region) | Isolated network, /16 CIDR, 3-AZ deployment |
| Public subnets (3x) | ALB nodes, NAT Gateways |
| Private subnets (3x) | ECS Fargate tasks (services, workers) |
| Data subnets (3x) | RDS, ElastiCache (isolated, no internet route) |
| NAT Gateway (per AZ) | Outbound internet for private subnets |
| Internet Gateway | Inbound internet for public subnets |
| VPC Endpoints | PrivateLink for S3, ECR, CloudWatch, SQS, Secrets Manager, KMS |
| VPC Peering / Transit Gateway | Cross-region or cross-account connectivity |
| VPC Flow Logs | Network traffic audit → CloudWatch / S3 |

#### Compute (ECS)

| Component | Purpose |
|-----------|---------|
| ECS Cluster (per region) | Fargate-backed container orchestration |
| ECS Services (long-running) | api, web frontend, internal-api, worker (SQS consumer) |
| ECS Tasks (one-off) | Migrations, batch jobs, scheduled tasks |
| Task Definitions | Container config: image, CPU, memory, env, secrets, logging |
| Service Discovery (Cloud Map) | Internal DNS for service-to-service communication |
| Application Auto Scaling | Scale ECS services on CPU, memory, or custom metrics |
| Capacity Providers | Fargate + Fargate Spot for cost optimization |

#### Async / Event-Driven

| Component | Purpose |
|-----------|---------|
| Amazon SQS | Message queues for async job dispatch |
| SQS Dead-Letter Queues | Failed message capture for retry / investigation |
| Amazon SNS | Fan-out pub/sub for notifications, event broadcast |
| Amazon EventBridge | Event bus for scheduled tasks, cross-service events |
| AWS Lambda | Lightweight event handlers (transforms, webhooks, glue) |
| AWS Step Functions | Complex multi-step workflow orchestration |
| Amazon Kinesis Data Streams | Real-time event streaming (high throughput) |
| Kinesis Firehose | Stream → S3 data lake delivery |

#### Data Stores

| Component | Purpose |
|-----------|---------|
| Aurora PostgreSQL (Global Database) | Primary relational DB with cross-region replication |
| ElastiCache Redis (Global Datastore) | Caching, session store, rate limiting |
| Amazon S3 | Object storage (assets, logs, backups) with CRR |
| DynamoDB Global Tables (optional) | Low-latency key-value for sessions or config |
| Amazon EFS (optional) | Shared filesystem for ECS tasks needing persistent volumes |

#### Container Registry

| Component | Purpose |
|-----------|---------|
| Amazon ECR | Docker image registry per region |
| ECR Replication | Cross-region image replication |
| ECR Image Scanning | Vulnerability scanning on push (Inspector integration) |
| ECR Lifecycle Policies | Automated cleanup of old/untagged images |

#### Security

| Component | Purpose |
|-----------|---------|
| AWS WAF (on ALB) | Layer 7 defense in depth behind Cloudflare |
| AWS Shield Advanced | DDoS mitigation at AWS edge |
| IAM Roles | Task execution role, task role (least privilege per service) |
| OIDC Federation | GitHub Actions → IAM (no static credentials in CI/CD) |
| KMS | Customer-managed encryption keys |
| ACM | TLS certificates for ALB |
| Secrets Manager | Database credentials, API keys (auto-rotation) |
| Security Groups | Per-service network access control |
| NACLs | Subnet-level network rules |
| AWS Network Firewall (optional) | Egress filtering, IDS/IPS |

#### Observability

| Component | Purpose |
|-----------|---------|
| CloudWatch Metrics & Dashboards | Infrastructure and application metrics |
| CloudWatch Container Insights | ECS task-level CPU, memory, network |
| CloudWatch Logs | Centralized application and infrastructure logs |
| CloudWatch Alarms | Threshold and anomaly-based alerting |
| CloudWatch Synthetics | Canary checks for endpoint health |
| X-Ray / OpenTelemetry | Distributed tracing across services |
| CloudTrail | API audit logging |

#### Compliance & Governance

| Component | Purpose |
|-----------|---------|
| AWS Organizations | Multi-account strategy (prod, staging, dev, security, logging) |
| Service Control Policies | Guardrails at org level |
| AWS Config | Resource compliance tracking |
| GuardDuty | Threat detection |
| Security Hub | Centralized security findings |
| Inspector | Container vulnerability scanning |
| Macie (optional) | S3 sensitive data discovery |

#### Cost & Backup

| Component | Purpose |
|-----------|---------|
| AWS Budgets | Spending alerts |
| Cost Explorer | Cost analysis and forecasting |
| Cost Anomaly Detection | Unexpected spend alerts |
| AWS Backup | Centralized backup policies |
| S3 Lifecycle Policies | Storage tiering and expiration |
| Fargate Spot | Cost-optimized capacity for non-critical workloads |

---

## Part B — Code Structure, CI/CD & Apply Strategy

### Repository Layout

The infrastructure is managed as a monorepo using **Terragrunt** to orchestrate
Terraform modules. Terragrunt provides DRY configuration, dependency management
between stacks, and consistent backend/provider configuration.

```
infrastructure/
├── terragrunt.hcl                          # Root Terragrunt config
│                                            #   - remote_state block (S3 native locking)
│                                            #   - generate "provider" block
│                                            #   - common inputs
│
├── _envcommon/                              # Shared partial configs (included by envs)
│   ├── ecs-cluster.hcl
│   ├── vpc.hcl
│   ├── alb.hcl
│   ├── rds.hcl
│   ├── redis.hcl
│   ├── sqs.hcl
│   ├── lambda.hcl
│   ├── ecr.hcl
│   ├── monitoring.hcl
│   ├── security.hcl
│   └── dns.hcl
│
├── modules/                                 # Terraform modules (reusable, versioned)
│   ├── networking/
│   │   ├── vpc/                            # VPC, subnets, NAT, IGW, flow logs
│   │   ├── vpc-endpoints/                  # PrivateLink endpoints
│   │   ├── security-groups/                # Per-service SG definitions
│   │   └── transit-gateway/                # Cross-region connectivity
│   ├── compute/
│   │   ├── ecs-cluster/                    # ECS cluster + capacity providers
│   │   ├── ecs-service/                    # ECS service + task def + auto scaling
│   │   ├── ecs-scheduled-task/             # EventBridge-triggered ECS tasks
│   │   └── lambda-function/                # Lambda with common config
│   ├── data/
│   │   ├── aurora/                         # Aurora PostgreSQL cluster
│   │   ├── elasticache-redis/              # Redis replication group
│   │   ├── s3-bucket/                      # S3 with encryption, versioning, CRR
│   │   └── dynamodb/                       # DynamoDB table + GSIs
│   ├── async/
│   │   ├── sqs-queue/                      # SQS + DLQ pair
│   │   ├── sns-topic/                      # SNS topic + subscriptions
│   │   ├── eventbridge-rule/               # EventBridge rule + targets
│   │   └── step-function/                  # Step Functions state machine
│   ├── loadbalancing/
│   │   ├── alb/                            # ALB + default rules
│   │   └── alb-listener-rule/              # Per-service routing rules
│   ├── security/
│   │   ├── iam-ecs-roles/                  # Task execution + task roles
│   │   ├── kms-key/                        # KMS key + alias + policy
│   │   ├── waf/                            # WAF web ACL + rules
│   │   └── acm-certificate/               # ACM cert + DNS validation
│   ├── observability/
│   │   ├── cloudwatch-dashboard/           # Dashboard definitions
│   │   ├── cloudwatch-alarms/              # Alarm sets per service
│   │   ├── log-group/                      # Log group with retention
│   │   └── sns-alerting/                   # Alert routing to PagerDuty/Slack
│   ├── container-registry/
│   │   └── ecr/                            # ECR repo + lifecycle + scanning
│   └── dns/
│       └── cloudflare-records/             # Cloudflare DNS records via CF provider
│
├── accounts/                                # AWS account definitions
│   ├── prod/
│   │   └── account.hcl                     # account_id, account_name
│   ├── staging/
│   │   └── account.hcl
│   ├── dev/
│   │   └── account.hcl
│   └── security/
│       └── account.hcl
│
├── regions/                                 # Per-region config
│   ├── us-east-1/
│   │   └── region.hcl                      # region, azs, ami_id
│   └── us-west-2/
│       └── region.hcl
│
├── live/                                    # LIVE INFRASTRUCTURE
│   ├── prod/
│   │   ├── env.hcl                         # environment = "prod"
│   │   ├── us-east-1/
│   │   │   ├── region.hcl                  # includes region config
│   │   │   ├── networking/
│   │   │   │   ├── vpc/
│   │   │   │   │   └── terragrunt.hcl      # include root + _envcommon/vpc.hcl
│   │   │   │   ├── vpc-endpoints/
│   │   │   │   │   └── terragrunt.hcl
│   │   │   │   └── security-groups/
│   │   │   │       └── terragrunt.hcl
│   │   │   ├── compute/
│   │   │   │   ├── ecs-cluster/
│   │   │   │   │   └── terragrunt.hcl
│   │   │   │   ├── api-service/
│   │   │   │   │   └── terragrunt.hcl
│   │   │   │   ├── web-service/
│   │   │   │   │   └── terragrunt.hcl
│   │   │   │   ├── worker-service/
│   │   │   │   │   └── terragrunt.hcl
│   │   │   │   └── scheduled-tasks/
│   │   │   │       └── terragrunt.hcl
│   │   │   ├── data/
│   │   │   │   ├── aurora/
│   │   │   │   │   └── terragrunt.hcl
│   │   │   │   ├── redis/
│   │   │   │   │   └── terragrunt.hcl
│   │   │   │   └── s3/
│   │   │   │       └── terragrunt.hcl
│   │   │   ├── async/
│   │   │   │   ├── order-queue/
│   │   │   │   │   └── terragrunt.hcl
│   │   │   │   ├── notification-topic/
│   │   │   │   │   └── terragrunt.hcl
│   │   │   │   └── data-pipeline/
│   │   │   │       └── terragrunt.hcl
│   │   │   ├── loadbalancing/
│   │   │   │   └── alb/
│   │   │   │       └── terragrunt.hcl
│   │   │   ├── security/
│   │   │   │   ├── iam/
│   │   │   │   │   └── terragrunt.hcl
│   │   │   │   ├── kms/
│   │   │   │   │   └── terragrunt.hcl
│   │   │   │   └── waf/
│   │   │   │       └── terragrunt.hcl
│   │   │   ├── observability/
│   │   │   │   ├── dashboards/
│   │   │   │   │   └── terragrunt.hcl
│   │   │   │   └── alarms/
│   │   │   │       └── terragrunt.hcl
│   │   │   ├── ecr/
│   │   │   │   └── terragrunt.hcl
│   │   │   └── dns/
│   │   │       └── terragrunt.hcl
│   │   └── us-west-2/
│   │       └── ...                          # Mirror of us-east-1 structure
│   │
│   ├── staging/
│   │   ├── env.hcl
│   │   └── us-east-1/                       # Single region for staging
│   │       └── ...
│   │
│   └── dev/
│       ├── env.hcl
│       └── us-east-1/                       # Single region for dev
│           └── ...
│
├── _ci/                                     # CI/CD pipeline definitions
│   ├── github-actions/
│   │   ├── terraform-plan.yml
│   │   ├── terraform-apply.yml
│   │   └── drift-detection.yml
│   └── scripts/
│       ├── plan-changed-stacks.sh           # Detect and plan changed stacks
│       ├── apply-stack.sh                   # Apply a single stack with locking
│       └── validate-all.sh                  # Format + validate all modules
│
├── tests/                                   # Infrastructure tests
│   ├── modules/                             # Unit tests per module (Terratest)
│   └── integration/                         # Cross-stack integration tests
│
└── docs/
    ├── architecture.md                      # This document
    ├── runbooks/                             # Operational runbooks
    │   ├── failover-procedure.md
    │   ├── scaling-guide.md
    │   └── incident-response.md
    └── adr/                                 # Architecture Decision Records
        ├── 001-ecs-fargate-over-eks.md
        └── 002-cloudflare-over-route53.md
```

### Terragrunt Hierarchy

Terragrunt's `include` and `read_terragrunt_config` mechanisms keep each
`terragrunt.hcl` leaf file minimal while inheriting configuration from multiple
levels.

```
terragrunt.hcl (root)                        ← S3 backend, provider, common tags
  └─ live/prod/env.hcl                       ← environment = "prod"
      └─ live/prod/us-east-1/region.hcl      ← region, AZs
          └─ live/prod/us-east-1/compute/
              └─ api-service/terragrunt.hcl  ← service-specific overrides
                  includes:
                    - root terragrunt.hcl
                    - _envcommon/ecs-service.hcl
                  dependency:
                    - ../ecs-cluster
                    - ../../networking/vpc
                    - ../../loadbalancing/alb
                    - ../../security/iam
```

**Key Terragrunt features used:**

| Feature | Purpose |
|---------|---------|
| `remote_state` | Auto-create S3 bucket per account/region (native S3 locking) |
| `generate` | Inject provider blocks with region and assume-role config |
| `dependency` | Express cross-stack dependencies (VPC before ECS, ALB before services) |
| `include` | Inherit config from root + `_envcommon` partials |
| `inputs` | Pass outputs from dependencies as inputs to modules |
| `run_all` | Plan/apply entire environment or region in dependency order |

### Branching & Merging Strategy

The repository follows **trunk-based development** with short-lived feature
branches and environment promotion.

```
                    main (protected)
                      │
    ┌─────────────────┼──────────────────┐
    │                 │                  │
    ▼                 ▼                  ▼
feat/add-api      fix/redis-config    feat/new-worker
    │                 │                  │
    │  PR + plan      │  PR + plan       │  PR + plan
    │  review         │  review          │  review
    │                 │                  │
    └────────────────►│◄─────────────────┘
                      │
                      ▼
                    main
                      │
                      ├──── auto-apply: dev
                      │
                      ├──── manual promote: staging
                      │         (workflow_dispatch)
                      │
                      └──── manual promote: prod
                                (workflow_dispatch + approval)
```

**Rules:**

1. `main` is protected — all changes go through pull requests
2. PRs trigger `terragrunt plan` for all affected stacks
3. Plans are posted as PR comments for review
4. Merge to `main` auto-applies to **dev** environment
5. **Staging** deploy is triggered manually via workflow_dispatch
6. **Prod** deploy requires manual trigger + GitHub Environment approval
7. Commits reference the change purpose (e.g. "feat(ecs): add worker service scaling")

**Branch naming:**

```
feat/<description>     # New infrastructure components
fix/<description>      # Bug fixes, config corrections
refactor/<description> # Module restructuring
docs/<description>     # Documentation only
```

### CI/CD Pipeline

The pipeline runs in **GitHub Actions** and uses OIDC federation (no long-lived
AWS credentials).

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           CI/CD PIPELINE                                     │
│                                                                              │
│  ┌─ On Pull Request ────────────────────────────────────────────────────┐    │
│  │                                                                       │    │
│  │  1. Checkout                                                          │    │
│  │  2. Detect changed stacks (git diff + terragrunt graph)              │    │
│  │  3. terraform fmt -check (all modules)                               │    │
│  │  4. terraform validate (all modules)                                 │    │
│  │  5. tflint (lint all modules)                                        │    │
│  │  6. tfsec / checkov (security scanning)                              │    │
│  │  7. OIDC auth → AWS (dev account, read-only role)                    │    │
│  │  8. terragrunt run-all plan (affected stacks only)                   │    │
│  │  9. Post plan output as PR comment                                   │    │
│  │ 10. Cost estimation (Infracost)                                      │    │
│  │ 11. OPA / Sentinel policy check (optional)                           │    │
│  │                                                                       │    │
│  └───────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─ On Merge to main (auto → dev) ──────────────────────────────────────┐    │
│  │                                                                       │    │
│  │  1. Checkout                                                          │    │
│  │  2. Detect changed stacks                                            │    │
│  │  3. OIDC auth → AWS (dev account, apply role)                        │    │
│  │  4. terragrunt run-all apply (affected stacks, dependency order)     │    │
│  │  5. Post-apply smoke tests (HTTP health checks, DB connectivity)     │    │
│  │  6. Notify Slack on success/failure                                  │    │
│  │                                                                       │    │
│  └───────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─ Promote to Staging (manual trigger) ────────────────────────────────┐    │
│  │                                                                       │    │
│  │  1. workflow_dispatch: select stacks or "all"                        │    │
│  │  2. OIDC auth → AWS (staging account)                                │    │
│  │  3. terragrunt run-all plan (preview changes)                        │    │
│  │  4. terragrunt run-all apply                                         │    │
│  │  5. Integration test suite                                           │    │
│  │  6. Notify Slack                                                     │    │
│  │                                                                       │    │
│  └───────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─ Promote to Prod (manual trigger + approval gate) ───────────────────┐    │
│  │                                                                       │    │
│  │  1. workflow_dispatch: select stacks or "all"                        │    │
│  │  2. GitHub Environment protection: require 1+ reviewer approval      │    │
│  │  3. OIDC auth → AWS (prod account)                                   │    │
│  │  4. terragrunt run-all plan                                          │    │
│  │  5. Plan artifact saved for audit                                    │    │
│  │  6. terragrunt run-all apply (from saved plan)                       │    │
│  │  7. Post-apply canary health checks                                  │    │
│  │  8. Notify Slack + audit log                                         │    │
│  │                                                                       │    │
│  └───────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─ Scheduled: Drift Detection (daily) ─────────────────────────────────┐    │
│  │                                                                       │    │
│  │  1. OIDC auth → AWS (each account)                                   │    │
│  │  2. terragrunt run-all plan (all stacks, all envs)                   │    │
│  │  3. If drift detected: open GitHub Issue + Slack alert               │    │
│  │                                                                       │    │
│  └───────────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Apply Methods & Promotion

#### Stack-Level Granularity

Terragrunt manages each infrastructure component as an independent "stack" with
its own state file. This allows targeted applies without risking unrelated
resources.

```bash
# Apply a single stack
cd live/prod/us-east-1/compute/api-service
terragrunt apply

# Apply all stacks in a region (respects dependency order)
cd live/prod/us-east-1
terragrunt run-all apply

# Apply only networking stacks
cd live/prod/us-east-1/networking
terragrunt run-all apply

# Plan everything in an environment
cd live/prod
terragrunt run-all plan
```

#### Environment Promotion Flow

```
┌─────────┐       ┌──────────┐       ┌─────────┐
│   dev   │──────►│ staging  │──────►│  prod   │
│         │ auto  │          │manual │         │
│ (merge  │       │(workflow │       │(workflow│
│  to     │       │ dispatch)│       │ dispatch│
│  main)  │       │          │       │ + gate) │
└─────────┘       └──────────┘       └─────────┘
```

| Stage | Trigger | Auth | Safeguards |
|-------|---------|------|------------|
| Dev | Auto on merge to `main` | OIDC → dev account | Plan output in PR |
| Staging | `workflow_dispatch` | OIDC → staging account | Plan preview before apply |
| Prod | `workflow_dispatch` + approval | OIDC → prod account | Environment protection rule, saved plan artifact, post-apply canary |

#### Multi-Region Apply Order

For production, the two regions are applied sequentially — Region 1 first,
validated, then Region 2. This prevents a bad change from breaking both regions
simultaneously.

```
  Region 1 (us-east-1)          Region 2 (us-west-2)
  ┌─────────────────┐           ┌─────────────────┐
  │  1. Plan        │           │                  │
  │  2. Apply       │           │   (waits)        │
  │  3. Validate    │──────────►│  4. Plan         │
  │     (canary +   │  success  │  5. Apply        │
  │      health     │           │  6. Validate     │
  │      checks)    │           │                  │
  └─────────────────┘           └─────────────────┘
         │                              │
         │         fail?                │
         └──────► Rollback R1 ──────────┘
                  Alert + halt R2
```

### State Management

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        TERRAFORM STATE                                       │
│                                                                              │
│  Backend: S3 with native locking (per account)                               │
│  Terraform ≥1.10 — uses S3 conditional writes (no DynamoDB needed)           │
│                                                                              │
│  Bucket structure:                                                           │
│  s3://company-terraform-state-{account-id}/                                  │
│    └── {region}/                                                             │
│        └── {component}/                                                      │
│            ├── terraform.tfstate                                             │
│            └── terraform.tfstate.tflock     ← S3 lock file                   │
│                                                                              │
│  Example paths:                                                              │
│    prod/us-east-1/networking/vpc/terraform.tfstate                           │
│    prod/us-east-1/compute/api-service/terraform.tfstate                      │
│    prod/us-west-2/data/aurora/terraform.tfstate                              │
│    staging/us-east-1/compute/api-service/terraform.tfstate                   │
│                                                                              │
│  Locking: S3 native (use_lockfile = true, conditional PutObject)             │
│  Encryption: S3 SSE-KMS with customer-managed key                            │
│  Versioning: Enabled (state history / rollback)                              │
│  Access: IAM role per environment (CI/CD OIDC, no static creds)              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Why Cloudflare + AWS (not just Route 53)?

| Concern | Cloudflare | Route 53 |
|---------|-----------|----------|
| Global DNS | Anycast, ~300 PoPs | Anycast, AWS edge |
| WAF / DDoS | Included (L3–L7), bot mgmt | AWS WAF + Shield (separate cost) |
| CDN | Integrated, free tier generous | CloudFront (separate service) |
| Edge logic | Workers, Page Rules | Lambda@Edge / CloudFront Functions |
| Cost | Free/Pro plan covers a lot | Pay per query + per service |
| Origin health checks | Built-in, geo-routing | Route 53 health checks (works fine) |

Cloudflare handles DNS resolution, edge caching, and L7 protection. AWS handles
everything from the ALB inward. This layered approach provides defense in depth
and vendor diversity for resilience.

---

## Design Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Container orchestration | ECS Fargate | No cluster management overhead, native AWS integration, simpler than EKS for service-oriented workloads |
| Launch type | Fargate (+ Fargate Spot) | Serverless compute, no EC2 patching, Spot for cost on non-critical workers |
| Async processing | SQS + ECS workers | Durable queues, ECS-based workers scale with queue depth, DLQ for failure handling |
| Lightweight events | Lambda | Sub-second cold start for transforms, webhooks, glue logic |
| Orchestration | Step Functions | Visual workflows for complex multi-step async processes |
| Database | Aurora PostgreSQL Global | Sub-second RPO, fast cross-region failover, read replicas |
| Cache | ElastiCache Redis Global Datastore | Cross-region replication, session/cache coherence |
| DNS & Edge | Cloudflare | Cost-effective WAF + CDN + DNS, vendor diversity |
| IaC tool | Terraform + Terragrunt | DRY configs, dependency management, multi-account/region orchestration |
| CI/CD auth | OIDC federation | No long-lived credentials, GitHub-native |
| State backend | S3 (native locking) | Terraform ≥1.10 S3 conditional writes, no DynamoDB lock table needed |
| Multi-region strategy | Active/active (read), active/standby (write) | Read traffic served from nearest region, writes go to primary |
