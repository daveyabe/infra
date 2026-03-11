# Copy this file to terraform.tfvars and fill in your values
# Langgraph service - development

gcp_project_id = "n43-studio-sandbox-dev"
region         = "northamerica-northeast2"

common_labels = {
  managed_by = "terraform"
  team       = "platform"
}

# --- Langgraph image ---
langgraph_image_tag = "latest"

# --- Langgraph Cloud Run ---
langgraph_port                  = 8080
langgraph_min_instances         = 1   # always on
langgraph_max_instances         = 10
langgraph_cpu                   = "2"
langgraph_memory                = "2Gi"
langgraph_allow_unauthenticated = false
langgraph_request_timeout       = "3600s"   # 1h for long-running agent runs
# langgraph_service_account_email = null

# Optional: environment variables for the container
# See https://docs.langchain.com/langgraph-platform/env-var and deploy-standalone-server
# langgraph_env = {
#   ENV       = "dev"
#   LOG_LEVEL = "info"   # DEBUG, INFO, WARNING, ERROR
#   LOG_JSON  = "true"  # structured logs for Cloud Logging
#
#   # Postgres (required for standalone Agent Server: threads, runs, state, task queue)
#   # Build from Cloud SQL or set directly. Prefer Secret Manager for secrets.
#   # DATABASE_URI = "postgresql://user:password@/dbname?host=/cloudsql/PROJECT:REGION:INSTANCE"
#   # Or Cloud SQL placeholders to build URI:
#   # INSTANCE_CONNECTION_NAME = "project:region:instance"
#   # DB_NAME                   = "langgraph"
#   # DB_USER                   = "langgraph"
#   # DB_PASSWORD               = "..."  # prefer Secret Manager in production
#
#   # Redis (required for standalone: pub/sub and streaming)
#   # REDIS_URI = "redis://host:6379/0"
#
#   # LangSmith (tracing; set LANGSMITH_TRACING=false to disable)
#   # LANGSMITH_API_KEY  = "..."  # from LangSmith
#   # LANGSMITH_TRACING  = "true"
#   # LANGSMITH_ENDPOINT = "https://..."  # only for self-hosted LangSmith
#
#   # Langfuse (alternative observability; use with LangChain callback handler)
#   # LANGFUSE_PUBLIC_KEY  = "pk-lf-..."
#   # LANGFUSE_SECRET_KEY  = "sk-lf-..."  # prefer Secret Manager in production
#   # LANGFUSE_HOST        = "https://cloud.langfuse.com"  # or https://us.cloud.langfuse.com
#   # LANGFUSE_TRACING_ENVIRONMENT = "dev"  # e.g. dev, staging, production
#
#   # CORS (allowed origins; default *)
#   # CORS_ALLOW_ORIGINS = "https://your-frontend.example.com"
#
#   # Background jobs (helpful if health checks fail or sync code blocks API)
#   # BG_JOB_ISOLATED_LOOPS            = "true"   # use separate event loop for background runs
#   # BG_JOB_TIMEOUT_SECS              = "3600"   # max 1h client connection on Cloud Run
#   # BG_JOB_SHUTDOWN_GRACE_PERIOD_SECS = "180"   # graceful shutdown
#
#   # Optional tuning
#   # LANGGRAPH_POSTGRES_POOL_MAX_SIZE = "150"   # per-replica Postgres pool size
#   # N_JOBS_PER_WORKER                = "10"    # task queue jobs per worker
#   # REDIS_MAX_CONNECTIONS            = "2000"  # per-replica Redis pool
# }
