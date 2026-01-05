# ============================================
# Teable on Azure AKS - Main Configuration
# ============================================
# Architecture:
# - Azure Database for PostgreSQL Flexible Server (managed, 2 vCPU / 8GB)
# - Azure Cache for Redis x2 (managed, 1GB each)
#   - Queue Redis: for job queues
#   - Cache Redis: for performance caching
# - AKS Cluster running MinIO + Teable
# ============================================

# --------------------------------------------
# Resource Group
# --------------------------------------------
resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

# --------------------------------------------
# Random passwords for services
# --------------------------------------------
resource "random_password" "postgresql" {
  length  = 32
  special = false # Azure PostgreSQL doesn't like some special chars
}

resource "random_password" "minio" {
  length  = 32
  special = false
}

resource "random_password" "secret_key" {
  length  = 32
  special = false
}

resource "random_password" "jwt_secret" {
  length  = 32
  special = false
}

resource "random_password" "session_secret" {
  length  = 32
  special = false
}

# --------------------------------------------
# Azure Database for PostgreSQL Flexible Server
# Default: 2 vCPU, 8GB RAM (B_Standard_B2ms)
# --------------------------------------------
resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "${local.name_prefix}-pg"
  resource_group_name    = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  version                = var.postgresql_version
  administrator_login    = "teableadmin"
  administrator_password = random_password.postgresql.result
  sku_name               = var.postgresql_sku
  storage_mb             = var.postgresql_storage_mb
  zone                   = "1"

  # Allow Azure services to access (including AKS)
  public_network_access_enabled = true

  tags = local.tags

  lifecycle {
    ignore_changes = [
      zone,
      high_availability
    ]
  }
}

# Firewall rule to allow Azure services
resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Allow all IPs for initial setup (restrict in production)
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_all" {
  count            = var.environment != "prod" ? 1 : 0
  name             = "AllowAll"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "255.255.255.255"
}

# Create teable database
resource "azurerm_postgresql_flexible_server_database" "teable" {
  name      = "teable"
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# --------------------------------------------
# Azure Cache for Redis - Queue
# For job queues and background tasks
# IMPORTANT: Queue data must NOT be lost
# - Uses "noeviction" policy (data never evicted)
# - Standard tier has replication (high availability)
# - Premium tier adds RDB persistence (disk backup)
# --------------------------------------------
resource "azurerm_redis_cache" "queue" {
  name                = "${local.name_prefix}-redis-queue"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  capacity            = var.redis_queue_capacity
  family              = var.redis_queue_family
  sku_name            = var.redis_queue_sku
  minimum_tls_version = "1.2"

  redis_configuration {
    # CRITICAL: Never evict queue data
    maxmemory_policy = "noeviction"

    # RDB persistence (Premium tier only)
    # Saves snapshots to disk for durability
    rdb_backup_enabled            = var.redis_queue_sku == "Premium" ? var.redis_queue_rdb_enabled : null
    rdb_backup_frequency          = var.redis_queue_sku == "Premium" && var.redis_queue_rdb_enabled ? var.redis_queue_rdb_frequency : null
    rdb_storage_connection_string = var.redis_queue_sku == "Premium" && var.redis_queue_rdb_enabled ? var.redis_queue_rdb_storage_connection_string : null

    # AOF persistence (Premium tier only, more durable than RDB)
    aof_backup_enabled = var.redis_queue_sku == "Premium" ? var.redis_queue_aof_enabled : null
  }

  tags = local.tags
}

# --------------------------------------------
# Azure Cache for Redis - Performance Cache
# For caching frequently accessed data
# Default: Standard C1 (1GB, 1 vCPU equivalent)
# --------------------------------------------
resource "azurerm_redis_cache" "cache" {
  name                = "${local.name_prefix}-redis-cache"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  capacity            = var.redis_cache_capacity
  family              = var.redis_cache_family
  sku_name            = var.redis_cache_sku
  minimum_tls_version = "1.2"

  redis_configuration {
    maxmemory_policy = "volatile-lru" # Cache can evict old data
  }

  tags = local.tags
}

# --------------------------------------------
# Azure Kubernetes Service (AKS)
# Default: 2 nodes x Standard_B2s (2 vCPU, 4GB each)
# --------------------------------------------
resource "azurerm_kubernetes_cluster" "main" {
  name                = "${local.name_prefix}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = local.name_prefix

  default_node_pool {
    name                = "default"
    node_count          = var.aks_enable_autoscaling ? null : var.aks_node_count
    vm_size             = var.aks_node_size
    enable_auto_scaling = var.aks_enable_autoscaling
    min_count           = var.aks_enable_autoscaling ? var.aks_min_nodes : null
    max_count           = var.aks_enable_autoscaling ? var.aks_max_nodes : null
    ultra_ssd_enabled   = false
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
  }

  tags = local.tags
}

# --------------------------------------------
# Kubernetes Provider Configuration
# --------------------------------------------
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.main.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate)
}

# --------------------------------------------
# Wait for cluster to be ready
# --------------------------------------------
resource "time_sleep" "wait_for_aks" {
  depends_on      = [azurerm_kubernetes_cluster.main]
  create_duration = "30s"
}

# --------------------------------------------
# Kubernetes Namespace
# --------------------------------------------
resource "kubernetes_namespace" "teable" {
  depends_on = [time_sleep.wait_for_aks]

  metadata {
    name = "teable"
    labels = {
      app = "teable"
    }
  }
}

# --------------------------------------------
# NGINX Ingress Controller Namespace
# --------------------------------------------
resource "kubernetes_namespace" "ingress_nginx" {
  depends_on = [time_sleep.wait_for_aks]

  metadata {
    name = "ingress-nginx"
  }
}

# --------------------------------------------
# MinIO Deployment
# --------------------------------------------
resource "kubernetes_secret" "minio" {
  depends_on = [kubernetes_namespace.teable]

  metadata {
    name      = "minio-secrets"
    namespace = "teable"
  }

  data = {
    root-user     = "minioadmin"
    root-password = random_password.minio.result
  }
}

resource "kubernetes_persistent_volume_claim" "minio" {
  depends_on = [kubernetes_namespace.teable]

  metadata {
    name      = "minio-pvc"
    namespace = "teable"
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "managed-csi"
    resources {
      requests = {
        storage = var.minio_storage_size
      }
    }
  }

  wait_until_bound = false  # WaitForFirstConsumer mode - PVC binds when Pod uses it
}

resource "kubernetes_deployment" "minio" {
  depends_on = [kubernetes_persistent_volume_claim.minio]

  metadata {
    name      = "minio"
    namespace = "teable"
    labels = {
      app = "minio"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "minio"
      }
    }

    template {
      metadata {
        labels = {
          app = "minio"
        }
      }

      spec {
        container {
          name  = "minio"
          image = "minio/minio:RELEASE.2025-04-22T22-12-26Z"
          args  = ["server", "/data", "--console-address", ":9001"]

          port {
            container_port = 9000
            name           = "api"
          }

          port {
            container_port = 9001
            name           = "console"
          }

          env {
            name = "MINIO_ROOT_USER"
            value_from {
              secret_key_ref {
                name = "minio-secrets"
                key  = "root-user"
              }
            }
          }

          env {
            name = "MINIO_ROOT_PASSWORD"
            value_from {
              secret_key_ref {
                name = "minio-secrets"
                key  = "root-password"
              }
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/minio/health/live"
              port = 9000
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }

          readiness_probe {
            http_get {
              path = "/minio/health/ready"
              port = 9000
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = "minio-pvc"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "minio" {
  depends_on = [kubernetes_deployment.minio]

  metadata {
    name      = "minio"
    namespace = "teable"
  }

  spec {
    selector = {
      app = "minio"
    }

    port {
      name        = "api"
      port        = 9000
      target_port = 9000
    }

    port {
      name        = "console"
      port        = 9001
      target_port = 9001
    }

    type = "ClusterIP"
  }
}

# MinIO bucket initialization job
resource "kubernetes_job" "minio_init" {
  depends_on = [kubernetes_service.minio]

  metadata {
    name      = "minio-init-buckets"
    namespace = "teable"
  }

  spec {
    backoff_limit = 5

    template {
      metadata {
        labels = {
          app = "minio-init"
        }
      }

      spec {
        restart_policy = "OnFailure"

        container {
          name  = "mc"
          image = "minio/mc:latest"

          command = ["/bin/sh", "-c"]
          args = [<<-EOT
            sleep 10
            mc alias set teable http://minio.teable.svc.cluster.local:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD
            mc mb --ignore-existing teable/teable-pub
            mc mb --ignore-existing teable/teable-pvt
            mc anonymous set public teable/teable-pub
            echo "Buckets created successfully"
          EOT
          ]

          env {
            name = "MINIO_ROOT_USER"
            value_from {
              secret_key_ref {
                name = "minio-secrets"
                key  = "root-user"
              }
            }
          }

          env {
            name = "MINIO_ROOT_PASSWORD"
            value_from {
              secret_key_ref {
                name = "minio-secrets"
                key  = "root-password"
              }
            }
          }
        }
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = "5m"
  }
}

# --------------------------------------------
# Teable Configuration
# --------------------------------------------
resource "kubernetes_config_map" "teable" {
  depends_on = [kubernetes_namespace.teable]

  metadata {
    name      = "teable-config"
    namespace = "teable"
  }

  data = {
    # Application
    PUBLIC_ORIGIN = "https://${var.teable_domain}"

    # Storage - MinIO
    BACKEND_STORAGE_PROVIDER                = "minio"
    BACKEND_STORAGE_PUBLIC_BUCKET           = "teable-pub"
    BACKEND_STORAGE_PRIVATE_BUCKET          = "teable-pvt"
    BACKEND_STORAGE_MINIO_ENDPOINT          = local.minio_endpoint
    STORAGE_PREFIX                          = local.minio_external_enabled ? "https://${var.minio_domain}" : "http://minio.teable.svc.cluster.local:9000"
    BACKEND_STORAGE_MINIO_INTERNAL_ENDPOINT = "minio.teable.svc.cluster.local"
    BACKEND_STORAGE_MINIO_PORT              = local.minio_port
    BACKEND_STORAGE_MINIO_INTERNAL_PORT     = "9000"
    BACKEND_STORAGE_MINIO_USE_SSL           = local.minio_use_ssl

    # Cache provider
    BACKEND_CACHE_PROVIDER = "redis"

    # Other
    NEXT_ENV_IMAGES_ALL_REMOTE             = "true"
    PRISMA_ENGINES_CHECKSUM_IGNORE_MISSING = "1"
    NODE_TLS_REJECT_UNAUTHORIZED           = "0"
  }
}

resource "kubernetes_secret" "teable" {
  depends_on = [kubernetes_namespace.teable]

  metadata {
    name      = "teable-secrets"
    namespace = "teable"
  }

  data = {
    # Database
    PRISMA_DATABASE_URL = "postgresql://teableadmin:${random_password.postgresql.result}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/teable?sslmode=require"

    # Application secrets
    SECRET_KEY             = random_password.secret_key.result
    BACKEND_JWT_SECRET     = random_password.jwt_secret.result
    BACKEND_SESSION_SECRET = random_password.session_secret.result

    # MinIO credentials
    BACKEND_STORAGE_MINIO_ACCESS_KEY = "minioadmin"
    BACKEND_STORAGE_MINIO_SECRET_KEY = random_password.minio.result

    # Redis - Queue (Azure Cache for Redis uses SSL on port 6380)
    BACKEND_CACHE_REDIS_URI = "rediss://:${azurerm_redis_cache.queue.primary_access_key}@${azurerm_redis_cache.queue.hostname}:6380/0"

    # Redis - Performance Cache
    BACKEND_PERFORMANCE_CACHE = "rediss://:${azurerm_redis_cache.cache.primary_access_key}@${azurerm_redis_cache.cache.hostname}:6380/0"
  }
}

# --------------------------------------------
# Teable Deployment
# Default: 2 CPU, 4GB RAM per pod
# --------------------------------------------
resource "kubernetes_deployment" "teable" {
  depends_on = [
    kubernetes_job.minio_init,
    kubernetes_config_map.teable,
    kubernetes_secret.teable,
    azurerm_postgresql_flexible_server_database.teable
  ]

  metadata {
    name      = "teable"
    namespace = "teable"
    labels = {
      app = "teable"
    }
  }

  spec {
    replicas = var.teable_hpa_enabled ? 1 : var.teable_replicas

    selector {
      match_labels = {
        app = "teable"
      }
    }

    template {
      metadata {
        labels = {
          app = "teable"
        }
      }

      spec {
        # Init container for database migration
        init_container {
          name  = "db-migrate"
          image = "${var.teable_image_repository}:${var.teable_image_tag}"
          args  = ["migrate-only"]

          env_from {
            config_map_ref {
              name = "teable-config"
            }
          }

          env_from {
            secret_ref {
              name = "teable-secrets"
            }
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }
        }

        # Main Teable container
        container {
          name  = "teable"
          image = "${var.teable_image_repository}:${var.teable_image_tag}"
          args  = ["skip-migrate"]

          port {
            container_port = 3000
          }

          env_from {
            config_map_ref {
              name = "teable-config"
            }
          }

          env_from {
            secret_ref {
              name = "teable-secrets"
            }
          }

          # Resource limits: 2 CPU, 4GB RAM per pod
          resources {
            requests = {
              cpu    = var.teable_cpu_request
              memory = var.teable_memory_request
            }
            limits = {
              cpu    = var.teable_cpu_limit
              memory = var.teable_memory_limit
            }
          }

          startup_probe {
            http_get {
              path = "/health"
              port = 3000
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 30
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 3000
            }
            initial_delay_seconds = 30
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 3000
            }
            initial_delay_seconds = 15
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "teable" {
  depends_on = [kubernetes_deployment.teable]

  metadata {
    name      = "teable"
    namespace = "teable"
  }

  spec {
    selector = {
      app = "teable"
    }

    port {
      port        = 3000
      target_port = 3000
    }

    type = "ClusterIP"
  }
}

# --------------------------------------------
# Horizontal Pod Autoscaler (HPA)
# --------------------------------------------
resource "kubernetes_horizontal_pod_autoscaler_v2" "teable" {
  count = var.teable_hpa_enabled ? 1 : 0

  depends_on = [kubernetes_deployment.teable]

  metadata {
    name      = "teable-hpa"
    namespace = "teable"
    labels = {
      app = "teable"
    }
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = "teable"
    }

    min_replicas = var.teable_hpa_min_replicas
    max_replicas = var.teable_hpa_max_replicas

    # CPU-based scaling
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.teable_hpa_cpu_threshold
        }
      }
    }

    # Memory-based scaling (optional)
    dynamic "metric" {
      for_each = var.teable_hpa_memory_threshold > 0 ? [1] : []
      content {
        type = "Resource"
        resource {
          name = "memory"
          target {
            type                = "Utilization"
            average_utilization = var.teable_hpa_memory_threshold
          }
        }
      }
    }

    behavior {
      # Scale up quickly
      scale_up {
        stabilization_window_seconds = 60
        select_policy                = "Max"
        policy {
          type           = "Percent"
          value          = 100
          period_seconds = 60
        }
        policy {
          type           = "Pods"
          value          = 4
          period_seconds = 60
        }
      }

      # Scale down slowly to avoid flapping
      scale_down {
        stabilization_window_seconds = 300
        select_policy                = "Min"
        policy {
          type           = "Percent"
          value          = 10
          period_seconds = 60
        }
      }
    }
  }
}

# --------------------------------------------
# Ingress (using kubectl apply in deploy.sh)
# --------------------------------------------
# The ingress is created via kubectl in deploy.sh
# because the NGINX ingress controller needs to be installed first
