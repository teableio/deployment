# Teable Azure AKS Deployment

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

One-click deployment of [Teable](https://github.com/teableio/teable) to Azure Kubernetes Service (AKS).

> 💡 **No Terraform experience required!** Just run one script - all configurations are pre-set.

## 🚀 Quick Start (5 minutes)

### Prerequisites

Before you begin, make sure you have these tools installed:

<details>
<summary><b>📦 Install Azure CLI</b> (click to expand)</summary>

**macOS:**
```bash
brew install azure-cli
```

**Windows:**
```powershell
winget install Microsoft.AzureCLI
```

**Linux (Ubuntu/Debian):**
```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

Verify installation:
```bash
az --version
```
</details>

<details>
<summary><b>📦 Install Terraform</b> (click to expand)</summary>

**macOS:**
```bash
brew install terraform
```

**Windows:**
```powershell
winget install Hashicorp.Terraform
```

**Linux:**
```bash
wget https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip
unzip terraform_1.6.6_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

Verify installation:
```bash
terraform --version
```

> ℹ️ **What is Terraform?**  
> Terraform is an automation tool that creates cloud resources for you. You don't need to learn it - just run our script!
</details>

<details>
<summary><b>📦 Install kubectl</b> (click to expand)</summary>

**macOS:**
```bash
brew install kubectl
```

**Windows:**
```powershell
winget install Kubernetes.kubectl
```

**Linux:**
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

Verify installation:
```bash
kubectl version --client
```
</details>

### Deployment Steps

```bash
# 1️⃣ Clone the repository
git clone https://github.com/teableio/deployment.git
cd deployment

# 2️⃣ Login to Azure
az login

# 3️⃣ Create configuration file
cp terraform.tfvars.example terraform.tfvars

# 4️⃣ Edit configuration (just change the domain)
#    Open terraform.tfvars and set: teable_domain = "your-domain.com"

# 5️⃣ Deploy!
./deploy.sh
```

After deployment, point your domain's DNS to the output IP address, then visit `https://your-domain.com`!

---

## 📐 Architecture

After deployment, you'll have:

```
┌───────────────────────────────────────────────────────────────┐
│                        Azure Cloud                             │
│                                                                │
│   ┌──────────────────────────────────────────────────────┐    │
│   │              Kubernetes Cluster (AKS)                 │    │
│   │                                                       │    │
│   │   ┌───────────┐          ┌───────────┐               │    │
│   │   │  Teable   │          │  MinIO    │               │    │
│   │   │  (App)    │◄────────►│ (Storage) │               │    │
│   │   └─────┬─────┘          └───────────┘               │    │
│   │         │                                             │    │
│   └─────────┼─────────────────────────────────────────────┘    │
│             │                                                   │
│   ┌─────────▼─────────┐    ┌───────────────────┐               │
│   │    PostgreSQL     │    │      Redis        │               │
│   │  (Azure Managed)  │    │  (Azure Managed)  │               │
│   └───────────────────┘    └───────────────────┘               │
└─────────────────────────────────────────────────────────────────┘
```

**Why this architecture?**
- ✅ **High reliability**: Database and cache use Azure managed services with automatic backups
- ✅ **Auto-scaling**: Teable automatically scales based on load
- ✅ **Secure**: Passwords auto-generated, secrets encrypted
- ✅ **Easy maintenance**: Upgrade by changing version and redeploying

---

## ⚙️ Configuration Options

### Required Settings

Edit the `terraform.tfvars` file:

```hcl
# Environment type: dev (development), staging, prod (production)
environment = "prod"

# Azure region (choose one close to your users)
location = "eastasia"      # East Asia (Hong Kong)
# location = "southeastasia" # Southeast Asia (Singapore)
# location = "eastus"        # East US

# Your domain name
teable_domain = "teable.yourcompany.com"
```

### Optional Settings (usually no changes needed)

<details>
<summary>View all optional settings</summary>

```hcl
# AKS node configuration
aks_node_count = 2                    # Number of nodes
aks_node_size  = "Standard_D4s_v3"    # Node size

# Auto-scaling (enabled by default)
teable_hpa_enabled       = true       # Enable Pod auto-scaling
teable_hpa_min_replicas  = 2          # Minimum 2 pods
teable_hpa_max_replicas  = 10         # Maximum 10 pods
teable_hpa_cpu_threshold = 70         # Scale up when CPU > 70%

# Storage
minio_storage_size = "100Gi"          # File storage size

# Teable version
teable_image_tag = "latest"           # Or specific version like "v1.5.0"
```
</details>

### Environment Presets

Different environments automatically use appropriate resource sizes:

| Environment | PostgreSQL | Redis | Use Case |
|-------------|-----------|-------|----------|
| `dev` | Basic (cheap) | Basic | Development/testing |
| `staging` | Basic | Basic | Staging |
| `prod` | High-performance | Standard | Production |

---

## 📖 Common Operations

### Check Status

```bash
# View all pod status
kubectl get pods -n teable

# View Teable logs
kubectl logs -n teable -l app=teable -f

# View auto-scaling status
kubectl get hpa -n teable
```

### Upgrade Teable

```bash
# 1. Update version
echo 'teable_image_tag = "v1.6.0"' >> terraform.tfvars

# 2. Redeploy
terraform apply
```

### Restart Teable

```bash
kubectl rollout restart deployment/teable -n teable
```

### Destroy All Resources

```bash
./destroy.sh
```

⚠️ **Warning**: This will delete all data including the database!

---

## ❓ FAQ

<details>
<summary><b>Q: How long does deployment take?</b></summary>

First deployment takes about 15-20 minutes:
- PostgreSQL creation: ~10 minutes
- AKS cluster creation: ~5-8 minutes
- Teable startup: ~3-5 minutes
</details>

<details>
<summary><b>Q: How much does it cost?</b></summary>

Estimated monthly cost (USD):

| Environment | Est. Cost/Month |
|-------------|-----------------|
| dev | ~$150-200 |
| prod | ~$400-600 |

Main costs: AKS nodes + PostgreSQL + Redis

💡 Tip: Set up cost alerts in Azure Portal
</details>

<details>
<summary><b>Q: I don't know Terraform. What if I have problems?</b></summary>

1. Check the error message - it usually tells you what's wrong
2. Common issues:
   - Not logged in → Run `az login`
   - Permission denied → Ensure your Azure account has resource creation permissions
   - Quota exceeded → Contact Azure to increase quota
3. If still stuck, ask on [GitHub Issues](https://github.com/teableio/deployment/issues)
</details>

<details>
<summary><b>Q: How do I use my own domain?</b></summary>

1. After deployment, get the Ingress IP
2. Add an A record in your domain's DNS settings:
   ```
   teable.yourcompany.com → <ingress-ip>
   ```
3. Wait for DNS propagation (usually 5-30 minutes)
4. Visit `https://teable.yourcompany.com`
</details>

<details>
<summary><b>Q: How do I configure HTTPS certificates?</b></summary>

After deployment, install cert-manager for automatic Let's Encrypt certificates:

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# Create Let's Encrypt issuer (edit email)
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

Then edit `ingress.yaml` and uncomment the TLS configuration.
</details>

<details>
<summary><b>Q: How do I backup data?</b></summary>

Azure PostgreSQL has automatic backups enabled by default (7-day retention).

For manual backup:
```bash
# Get database connection info
terraform output -json | jq -r '.postgresql_fqdn.value'

# Use pg_dump to backup
pg_dump -h <fqdn> -U teableadmin -d teable > backup.sql
```
</details>

---

## 🔧 Troubleshooting

### Pod fails to start

```bash
# View pod details
kubectl describe pod -n teable -l app=teable

# View init container logs (database migration)
kubectl logs -n teable -l app=teable -c db-migrate
```

### Cannot connect to database

```bash
# Check PostgreSQL firewall rules
az postgres flexible-server firewall-rule list \
  --resource-group teable-prod-rg \
  --name teable-prod-pg
```

### Ingress has no IP

```bash
# Check Ingress Controller status
kubectl get svc -n ingress-nginx

# View Ingress Controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller
```

---

## 📚 Related Links

- [Teable Documentation](https://help.teable.io)
- [Teable GitHub](https://github.com/teableio/teable)
- [Azure AKS Documentation](https://docs.microsoft.com/azure/aks/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

---

## 📄 License

Apache License 2.0. See [LICENSE](LICENSE) for details.
