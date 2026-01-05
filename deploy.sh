#!/bin/bash
# ============================================
# Teable Azure AKS - One-Click Deployment
# ============================================
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Banner
echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║           🚀 Teable Azure AKS One-Click Deployment         ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check prerequisites
check_prerequisites() {
    echo -e "${BLUE}▶ Checking prerequisites...${NC}"
    echo ""
    
    local missing=0
    
    # Check Azure CLI
    if command -v az &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Azure CLI installed"
    else
        echo -e "  ${RED}✗${NC} Azure CLI not installed"
        echo -e "    Install: ${CYAN}brew install azure-cli${NC} (macOS)"
        echo -e "    Or visit: https://docs.microsoft.com/cli/azure/install-azure-cli"
        missing=1
    fi
    
    # Check Terraform
    if command -v terraform &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Terraform installed"
    else
        echo -e "  ${RED}✗${NC} Terraform not installed"
        echo -e "    Install: ${CYAN}brew install terraform${NC} (macOS)"
        echo -e "    Or visit: https://www.terraform.io/downloads"
        missing=1
    fi
    
    # Check kubectl
    if command -v kubectl &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} kubectl installed"
    else
        echo -e "  ${RED}✗${NC} kubectl not installed"
        echo -e "    Install: ${CYAN}brew install kubectl${NC} (macOS)"
        echo -e "    Or visit: https://kubernetes.io/docs/tasks/tools/"
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        echo ""
        echo -e "${RED}Please install the missing tools and run this script again${NC}"
        exit 1
    fi
    
    # Check Azure login
    echo ""
    echo -e "${BLUE}▶ Checking Azure login status...${NC}"
    if az account show &> /dev/null; then
        local account=$(az account show --query name -o tsv)
        echo -e "  ${GREEN}✓${NC} Logged in to Azure: ${CYAN}$account${NC}"
    else
        echo -e "  ${YELLOW}!${NC} Not logged in to Azure, opening login..."
        az login
    fi
    
    echo ""
    echo -e "${GREEN}✓ Prerequisites check passed${NC}"
}

# Check configuration
check_config() {
    echo ""
    echo -e "${BLUE}▶ Checking configuration file...${NC}"
    
    if [ ! -f "terraform.tfvars" ]; then
        echo -e "  ${YELLOW}!${NC} Configuration file not found, creating..."
        cp terraform.tfvars.example terraform.tfvars
        echo ""
        echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║  ⚠️  Please edit terraform.tfvars to set your domain       ║${NC}"
        echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  Open file: ${CYAN}$SCRIPT_DIR/terraform.tfvars${NC}"
        echo ""
        echo -e "  At minimum, change:"
        echo -e "    ${CYAN}teable_domain = \"your-domain.com\"${NC}"
        echo ""
        echo -e "  When done, run again: ${CYAN}./deploy.sh${NC}"
        exit 0
    fi
    
    # Check if domain is configured
    local domain=$(grep -E "^teable_domain" terraform.tfvars | grep -v "example.com" | head -1)
    if [ -z "$domain" ]; then
        echo -e "  ${YELLOW}!${NC} Domain may not be configured"
        echo ""
        read -p "  Have you updated teable_domain? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "  Please edit ${CYAN}terraform.tfvars${NC} to set your domain"
            exit 0
        fi
    fi
    
    echo -e "  ${GREEN}✓${NC} Configuration file ready"
}

# Main deployment
deploy() {
    echo ""
    echo -e "${BLUE}▶ Step 1/5: Initializing Terraform...${NC}"
    terraform init -upgrade > /dev/null 2>&1
    echo -e "  ${GREEN}✓${NC} Initialization complete"
    
    echo ""
    echo -e "${BLUE}▶ Step 2/5: Validating configuration...${NC}"
    if terraform validate > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Configuration valid"
    else
        echo -e "  ${RED}✗${NC} Configuration validation failed"
        terraform validate
        exit 1
    fi
    
    echo ""
    echo -e "${BLUE}▶ Step 3/5: Planning deployment...${NC}"
    echo ""
    terraform plan -out=tfplan
    
    echo ""
    echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  ⚠️  About to create Azure resources (this will incur costs)${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
    echo ""
    read -p "Confirm deployment? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Deployment cancelled${NC}"
        rm -f tfplan
        exit 0
    fi
    
    echo ""
    echo -e "${BLUE}▶ Step 4/5: Deploying resources (takes ~15-20 minutes)...${NC}"
    echo ""
    echo -e "  ${CYAN}☕ This takes a while, grab a coffee...${NC}"
    echo ""
    
    terraform apply tfplan
    
    echo -e "  ${GREEN}✓${NC} Resource deployment complete"
    
    # Get cluster credentials and setup ingress
    echo ""
    echo -e "${BLUE}▶ Step 5/5: Configuring Kubernetes and Ingress...${NC}"
    
    local RG_NAME=$(terraform output -raw resource_group_name 2>/dev/null)
    local AKS_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null)
    local TEABLE_DOMAIN=$(terraform output -raw teable_url 2>/dev/null | sed 's|https://||')
    
    # Get AKS credentials
    echo -e "  Getting cluster credentials..."
    az aks get-credentials --resource-group "$RG_NAME" --name "$AKS_NAME" --overwrite-existing > /dev/null 2>&1
    
    # Install NGINX Ingress Controller
    echo -e "  Installing Ingress Controller..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/cloud/deploy.yaml > /dev/null 2>&1
    
    # Wait for ingress controller
    echo -e "  Waiting for Ingress Controller to be ready..."
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=120s > /dev/null 2>&1 || true
    
    # Generate and apply ingress
    echo -e "  Configuring Ingress rules..."
    sed "s/\${teable_domain}/$TEABLE_DOMAIN/g" ingress.yaml.tpl > ingress.yaml
    kubectl apply -f ingress.yaml > /dev/null 2>&1
    
    echo -e "  ${GREEN}✓${NC} Ingress configuration complete"
    
    # Get Ingress IP
    echo ""
    echo -e "  ${CYAN}Waiting for external IP...${NC}"
    sleep 30
    local INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    # Clean up
    rm -f tfplan
    
    # Final output
    echo ""
    echo -e "${GREEN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                                                            ║"
    echo "║           🎉 Deployment Complete!                          ║"
    echo "║                                                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "${BLUE}📍 Resources Created:${NC}"
    echo -e "   • Resource Group: ${CYAN}$RG_NAME${NC}"
    echo -e "   • AKS Cluster: ${CYAN}$AKS_NAME${NC}"
    echo -e "   • PostgreSQL: ${CYAN}$(terraform output -raw postgresql_fqdn 2>/dev/null)${NC}"
    echo -e "   • Redis: ${CYAN}$(terraform output -raw redis_hostname 2>/dev/null)${NC}"
    echo ""
    
    if [ -n "$INGRESS_IP" ]; then
        echo -e "${BLUE}🌐 External IP Address:${NC}"
        echo -e "   ${GREEN}$INGRESS_IP${NC}"
        echo ""
        echo -e "${YELLOW}📋 Next Step - Configure DNS:${NC}"
        echo -e "   Add an A record in your domain's DNS settings:"
        echo ""
        echo -e "   ${CYAN}$TEABLE_DOMAIN${NC}  →  ${GREEN}$INGRESS_IP${NC}"
        echo ""
    else
        echo -e "${YELLOW}📋 Get External IP:${NC}"
        echo -e "   IP is still being provisioned. Run this command to check:"
        echo -e "   ${CYAN}kubectl get svc -n ingress-nginx ingress-nginx-controller${NC}"
        echo ""
    fi
    
    echo -e "${BLUE}🔗 Access Teable:${NC}"
    echo -e "   https://$TEABLE_DOMAIN"
    echo ""
    echo -e "${BLUE}📊 Useful Commands:${NC}"
    echo -e "   Check pod status:    ${CYAN}kubectl get pods -n teable${NC}"
    echo -e "   View logs:           ${CYAN}kubectl logs -n teable -l app=teable -f${NC}"
    echo -e "   Check auto-scaling:  ${CYAN}kubectl get hpa -n teable${NC}"
    echo ""
    echo -e "${YELLOW}💡 Tip: View passwords and other sensitive info${NC}"
    echo -e "   ${CYAN}terraform output -json${NC}"
    echo ""
}

# Run
check_prerequisites
check_config
deploy
