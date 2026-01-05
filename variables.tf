# ============================================
# Required Variables
# ============================================

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastasia"
}

variable "teable_domain" {
  description = "Domain name for Teable application (e.g., teable.yourcompany.com)"
  type        = string
}

# ============================================
# Optional Variables - AKS
# ============================================

variable "aks_node_count" {
  description = "Number of nodes in AKS cluster"
  type        = number
  default     = 2
}

variable "aks_node_size" {
  description = "VM size for AKS nodes (default: 2 vCPU, 4GB)"
  type        = string
  default     = "Standard_B2s_v2" # Note: Standard_B2s may not be available in all regions
}

variable "aks_enable_autoscaling" {
  description = "Enable cluster autoscaling"
  type        = bool
  default     = false
}

variable "aks_min_nodes" {
  description = "Minimum nodes when autoscaling is enabled"
  type        = number
  default     = 2
}

variable "aks_max_nodes" {
  description = "Maximum nodes when autoscaling is enabled"
  type        = number
  default     = 5
}

# ============================================
# Optional Variables - PostgreSQL
# Default: 2 vCPU, 8GB RAM
# ============================================

variable "postgresql_sku" {
  description = "PostgreSQL SKU name (default: 2 vCPU, 8GB)"
  type        = string
  default     = "B_Standard_B2ms" # 2 vCPU, 8GB RAM
}

variable "postgresql_storage_mb" {
  description = "PostgreSQL storage size in MB"
  type        = number
  default     = 32768 # 32GB
}

variable "postgresql_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "16"
}

# ============================================
# Optional Variables - Redis Queue
# For job queues and background tasks
# Default: Standard C1 (1GB, ~1 vCPU equivalent)
# ============================================

variable "redis_queue_sku" {
  description = "Redis Queue SKU (Basic, Standard, Premium)"
  type        = string
  default     = "Standard"
}

variable "redis_queue_family" {
  description = "Redis Queue family (C for Basic/Standard, P for Premium)"
  type        = string
  default     = "C"
}

variable "redis_queue_capacity" {
  description = "Redis Queue capacity (0-6 for Basic/Standard, 1-4 for Premium)"
  type        = number
  default     = 1 # 1GB
}

# Premium tier persistence options for Queue Redis
variable "redis_queue_rdb_enabled" {
  description = "Enable RDB persistence for Queue Redis (Premium tier only)"
  type        = bool
  default     = true
}

variable "redis_queue_rdb_frequency" {
  description = "RDB backup frequency in minutes (15, 30, 60, 360, 720, 1440)"
  type        = number
  default     = 60 # Every hour
}

variable "redis_queue_rdb_storage_connection_string" {
  description = "Azure Storage connection string for RDB backups (Premium tier only)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "redis_queue_aof_enabled" {
  description = "Enable AOF persistence for Queue Redis (Premium tier only, more durable than RDB)"
  type        = bool
  default     = false
}

# ============================================
# Optional Variables - Redis Cache
# For performance caching
# Default: Standard C1 (1GB, ~1 vCPU equivalent)
# ============================================

variable "redis_cache_sku" {
  description = "Redis Cache SKU (Basic, Standard, Premium)"
  type        = string
  default     = "Standard"
}

variable "redis_cache_family" {
  description = "Redis Cache family (C for Basic/Standard, P for Premium)"
  type        = string
  default     = "C"
}

variable "redis_cache_capacity" {
  description = "Redis Cache capacity (0-6 for Basic/Standard, 1-4 for Premium)"
  type        = number
  default     = 1 # 1GB
}

# ============================================
# Optional Variables - MinIO
# ============================================

variable "minio_storage_size" {
  description = "MinIO persistent volume size"
  type        = string
  default     = "50Gi"
}

variable "minio_domain" {
  description = "Domain for MinIO (optional, for external access). Leave empty to use internal only."
  type        = string
  default     = ""
}

# ============================================
# Optional Variables - Teable Application
# ============================================

variable "teable_image_repository" {
  description = "Teable Docker image repository"
  type        = string
  default     = "ghcr.io/teableio/teable"
}

variable "teable_image_tag" {
  description = "Teable Docker image tag"
  type        = string
  default     = "latest"
}

variable "teable_replicas" {
  description = "Number of Teable replicas (ignored when HPA is enabled)"
  type        = number
  default     = 1
}

# Teable Pod Resources - Default: 2 CPU, 4GB RAM
variable "teable_cpu_request" {
  description = "CPU request for Teable pods"
  type        = string
  default     = "500m"
}

variable "teable_cpu_limit" {
  description = "CPU limit for Teable pods"
  type        = string
  default     = "2000m" # 2 CPU
}

variable "teable_memory_request" {
  description = "Memory request for Teable pods"
  type        = string
  default     = "1Gi"
}

variable "teable_memory_limit" {
  description = "Memory limit for Teable pods"
  type        = string
  default     = "4Gi" # 4GB RAM
}

# ============================================
# Optional Variables - Teable HPA
# ============================================

variable "teable_hpa_enabled" {
  description = "Enable Horizontal Pod Autoscaler for Teable"
  type        = bool
  default     = true
}

variable "teable_hpa_min_replicas" {
  description = "Minimum replicas for HPA"
  type        = number
  default     = 1
}

variable "teable_hpa_max_replicas" {
  description = "Maximum replicas for HPA"
  type        = number
  default     = 5
}

variable "teable_hpa_cpu_threshold" {
  description = "Target CPU utilization percentage for HPA"
  type        = number
  default     = 70
}

variable "teable_hpa_memory_threshold" {
  description = "Target memory utilization percentage for HPA (0 to disable)"
  type        = number
  default     = 80
}

# ============================================
# Computed Locals
# ============================================

locals {
  name_prefix = "teable-${var.environment}"

  tags = {
    Environment = var.environment
    Application = "Teable"
    ManagedBy   = "Terraform"
  }

  # MinIO domain (use internal if not specified)
  minio_external_enabled = var.minio_domain != ""
  minio_endpoint         = var.minio_domain != "" ? var.minio_domain : "minio.teable.svc.cluster.local"
  minio_port             = var.minio_domain != "" ? "443" : "9000"
  minio_use_ssl          = var.minio_domain != "" ? "true" : "false"
}
