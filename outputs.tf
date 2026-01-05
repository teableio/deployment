# ============================================
# Terraform Outputs
# ============================================

output "resource_group_name" {
  description = "Azure Resource Group name"
  value       = azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  description = "AKS Cluster name"
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_get_credentials_command" {
  description = "Command to get AKS credentials"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}"
}

output "postgresql_fqdn" {
  description = "PostgreSQL Flexible Server FQDN"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "redis_queue_hostname" {
  description = "Azure Cache for Redis (Queue) hostname"
  value       = azurerm_redis_cache.queue.hostname
}

output "redis_cache_hostname" {
  description = "Azure Cache for Redis (Cache) hostname"
  value       = azurerm_redis_cache.cache.hostname
}

output "teable_url" {
  description = "Teable application URL"
  value       = "https://${var.teable_domain}"
}

output "next_steps" {
  description = "Next steps after deployment"
  value       = <<-EOT
    
    =========================================
    🎉 Deployment Complete!
    =========================================
    
    1. Get AKS credentials:
       az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}
    
    2. Install NGINX Ingress Controller:
       kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/cloud/deploy.yaml
    
    3. Get Ingress External IP:
       kubectl get svc -n ingress-nginx ingress-nginx-controller -w
    
    4. Configure DNS:
       Point ${var.teable_domain} to the Ingress External IP
    
    5. Apply Ingress configuration:
       kubectl apply -f ingress.yaml
    
    6. Access Teable:
       https://${var.teable_domain}
    
    Check pod status:
       kubectl get pods -n teable
    
    View logs:
       kubectl logs -n teable -l app=teable -f
  EOT
}

# Sensitive outputs (use -json flag to see)
output "postgresql_password" {
  description = "PostgreSQL admin password"
  value       = random_password.postgresql.result
  sensitive   = true
}

output "minio_password" {
  description = "MinIO root password"
  value       = random_password.minio.result
  sensitive   = true
}

output "teable_secret_key" {
  description = "Teable secret key"
  value       = random_password.secret_key.result
  sensitive   = true
}

# Resource summary
output "resource_summary" {
  description = "Summary of deployed resources"
  value       = <<-EOT
    
    📊 Resource Summary:
    ────────────────────────────────────────
    PostgreSQL:     ${var.postgresql_sku} (2 vCPU, 8GB RAM)
    Redis Queue:    ${var.redis_queue_sku} C${var.redis_queue_capacity} (~1GB)
    Redis Cache:    ${var.redis_cache_sku} C${var.redis_cache_capacity} (~1GB)
    AKS Nodes:      ${var.aks_node_count} x ${var.aks_node_size}
    Teable Pods:    ${var.teable_hpa_min_replicas}-${var.teable_hpa_max_replicas} (HPA enabled)
    Pod Resources:  ${var.teable_cpu_limit} CPU, ${var.teable_memory_limit} RAM
    ────────────────────────────────────────
  EOT
}
