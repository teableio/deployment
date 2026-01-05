#!/bin/bash
# ============================================
# Teable Azure AKS - Cleanup Script
# ============================================
set -e

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${RED}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║           ⚠️  Teable Azure AKS - Cleanup                   ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}This will destroy ALL resources created by Terraform:${NC}"
echo "  • AKS Cluster"
echo "  • PostgreSQL Database"
echo "  • Redis Cache"
echo "  • All data stored in these services"
echo ""
echo -e "${RED}This action is IRREVERSIBLE!${NC}"
echo ""

read -p "Type 'destroy' to confirm: " -r
echo

if [[ $REPLY != "destroy" ]]; then
    echo "Aborted."
    exit 0
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "Destroying resources..."
terraform destroy -auto-approve

echo ""
echo -e "${GREEN}✓ All resources destroyed${NC}"
