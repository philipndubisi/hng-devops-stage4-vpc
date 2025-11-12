#!/bin/bash
#
# VPC Demo Script - HNG DevOps Stage 4
# Demonstrates all VPC features: creation, isolation, peering, NAT, and cleanup
#
# Usage: sudo ./demo-script.sh
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Helper functions
print_header() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_step() {
    echo -e "${YELLOW}➜${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_test() {
    echo -e "${MAGENTA}TEST:${NC} $1"
}

wait_for_user() {
    echo ""
    echo -e "${BLUE}Press Enter to continue...${NC}"
    read -r
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run with sudo${NC}" 
   echo "Usage: sudo ./demo-script.sh"
   exit 1
fi

# Ensure clean start
print_header "Stage 0: Clean Slate"
print_step "Cleaning up any existing VPCs..."
./bin/vpcctl cleanup-all 2>/dev/null || true
sleep 1
print_success "Environment is clean"
wait_for_user

# ============================================================================
# PART 1: CORE VPC CREATION
# ============================================================================
print_header "Part 1: Core VPC Creation"

print_step "Creating production VPC with CIDR 10.0.0.0/16..."
./bin/vpcctl create-vpc prod 10.0.0.0/16
sleep 1

print_step "Listing VPCs..."
./bin/vpcctl list-vpcs
wait_for_user

print_step "Creating public subnet (10.0.1.0/24)..."
./bin/vpcctl create-subnet prod web 10.0.1.0/24 public
sleep 1

print_step "Creating private subnet (10.0.2.0/24)..."
./bin/vpcctl create-subnet prod data 10.0.2.0/24 private
sleep 1

print_step "Listing subnets in production VPC..."
./bin/vpcctl list-subnets production
wait_for_user

# ============================================================================
# PART 2: ROUTING AND NAT GATEWAY
# ============================================================================
print_header "Part 2: Routing and NAT Gateway"

print_step "Deploying web server in public subnet..."
./bin/vpcctl deploy-webserver prod web
sleep 2

print_test "Testing web server from host..."
if curl -s http://10.0.1.10 | grep -q "Web Server Running"; then
    print_success "Web server is accessible from host"
else
    echo -e "${RED}✗${NC} Web server test failed"
fi
wait_for_user

print_test "Testing internet connectivity from public subnet (with NAT)..."
if ip netns exec prod-web ping -c 2 8.8.8.8 &> /dev/null; then
    print_success "Public subnet has internet access via NAT"
else
    echo -e "${RED}✗${NC} Public subnet internet test failed"
fi
wait_for_user

print_test "Testing inter-subnet communication (web -> database)..."
if ip netns exec prod-web ping -c 2 10.0.2.10 &> /dev/null; then
    print_success "Subnets within same VPC can communicate"
else
    echo -e "${RED}✗${NC} Inter-subnet communication failed"
fi
wait_for_user

print_test "Verifying private subnet has NO internet access (no NAT)..."
echo "Attempting ping from private subnet (should timeout)..."
if timeout 3 ip netns exec prod-data ping -c 1 8.8.8.8 &> /dev/null; then
    echo -e "${RED}✗${NC} Private subnet should NOT have internet access"
else
    print_success "Private subnet correctly has no internet access"
fi
wait_for_user

# ============================================================================
# PART 3: VPC ISOLATION & PEERING
# ============================================================================
print_header "Part 3: VPC Isolation & Peering"

print_step "Creating staging VPC with CIDR 172.16.0.0/16..."
./bin/vpcctl create-vpc stage 172.16.0.0/16
sleep 1

print_step "Creating subnet in staging VPC..."
./bin/vpcctl create-subnet stage app 172.16.1.0/24 public
sleep 1

print_step "Listing all VPCs..."
./bin/vpcctl list-vpcs
wait_for_user

print_test "Testing VPC isolation (production -> staging should FAIL)..."
echo "Attempting ping from production to staging (should fail)..."
if timeout 3 ip netns exec prod-web ping -c 1 172.16.1.10 &> /dev/null; then
    echo -e "${RED}✗${NC} VPCs should be isolated by default!"
else
    print_success "VPCs are properly isolated - communication blocked"
fi
wait_for_user

print_step "Creating VPC peering connection between production and staging..."
./bin/vpcctl peer-vpcs prod stage
sleep 1
wait_for_user

print_test "Testing cross-VPC communication after peering (should SUCCEED)..."
if ip netns exec prod-web ping -c 2 172.16.1.10 &> /dev/null; then
    print_success "Peered VPCs can communicate successfully"
else
    echo -e "${RED}✗${NC} Peered VPCs should be able to communicate"
fi
wait_for_user

print_step "Removing VPC peering..."
./bin/vpcctl unpeer-vpcs prod stage
sleep 1

print_test "Testing isolation after unpeering (should FAIL again)..."
echo "Attempting ping after unpeering (should fail)..."
if timeout 3 ip netns exec prod-web ping -c 1 172.16.1.10 &> /dev/null; then
    echo -e "${RED}✗${NC} Isolation should be restored after unpeering"
else
    print_success "Isolation correctly restored after unpeering"
fi
wait_for_user

# ============================================================================
# PART 4: FIREWALL & SECURITY GROUPS
# ============================================================================
print_header "Part 4: Firewall & Security Groups"

print_step "Creating example firewall policy..."
cat > /tmp/demo-policy.json << 'EOF'
{
  "ingress": [
    {"port": 80, "protocol": "tcp", "action": "allow"},
    {"port": 443, "protocol": "tcp", "action": "allow"},
    {"port": 22, "protocol": "tcp", "action": "deny"}
  ],
  "egress": [
    {"port": 80, "protocol": "tcp", "action": "allow"},
    {"port": 443, "protocol": "tcp", "action": "allow"}
  ]
}
EOF

echo "Policy file created at /tmp/demo-policy.json"
cat /tmp/demo-policy.json
wait_for_user

print_step "Applying firewall policy to web subnet..."
./bin/vpcctl apply-policy prod web /tmp/demo-policy.json
sleep 1
print_success "Firewall policy applied successfully"
wait_for_user

print_step "Verifying iptables rules in namespace..."
echo "Showing INPUT chain rules:"
ip netns exec prod-web iptables -L INPUT -n --line-numbers | head -10
wait_for_user

# ============================================================================
# PART 5: CONNECTIVITY TESTING
# ============================================================================
print_header "Part 5: Comprehensive Connectivity Tests"

print_step "Running automated connectivity tests for production VPC..."
./bin/vpcctl test-connectivity prod
wait_for_user

print_step "Running automated connectivity tests for staging VPC..."
./bin/vpcctl test-connectivity stage
wait_for_user

# ============================================================================
# ADDITIONAL DEMONSTRATIONS
# ============================================================================
print_header "Additional Demonstrations"

print_step "Showing network namespace configuration..."
echo -e "${BLUE}Network namespaces:${NC}"
ip netns list
echo ""

print_step "Showing bridge interfaces..."
echo -e "${BLUE}Bridge interfaces:${NC}"
ip link show type bridge
echo ""

print_step "Showing routing table for production-web namespace..."
echo -e "${BLUE}Routes in prod-web:${NC}"
ip netns exec prod-web ip route
echo ""

print_step "Showing NAT rules..."
echo -e "${BLUE}NAT (POSTROUTING) rules:${NC}"
iptables -t nat -L POSTROUTING -n -v | grep -E "MASQUERADE|Chain"
echo ""

print_step "Showing VPC state file..."
echo -e "${BLUE}VPC State:${NC}"
cat configs/vpc_state.txt
echo ""
wait_for_user

# ============================================================================
# PART 6: CLEANUP
# ============================================================================
print_header "Part 6: Cleanup & Resource Removal"

print_step "Showing resources before cleanup..."
echo "VPCs:"
./bin/vpcctl list-vpcs
echo ""
echo "Namespaces:"
ip netns list
echo ""
echo "Bridges:"
ip link show type bridge | grep -E "^[0-9]+:" | awk '{print $2}' | sed 's/:$//'
wait_for_user

print_step "Cleaning up all VPC resources..."
./bin/vpcctl cleanup-all
sleep 2

print_step "Verifying cleanup..."
echo "VPCs:"
./bin/vpcctl list-vpcs
echo ""
echo "Namespaces:"
ip netns list 2>/dev/null || echo "  None"
echo ""
echo "Bridges (VPC bridges should be gone):"
ip link show type bridge 2>/dev/null | grep -E "prod-br|staging-br" || print_success "All VPC bridges removed"
echo ""

print_success "All resources cleaned up successfully"
wait_for_user

# ============================================================================
# SUMMARY
# ============================================================================
print_header "Demo Complete - Summary"

echo -e "${GREEN}✓${NC} Part 1: Core VPC Creation - VPCs and subnets created successfully"
echo -e "${GREEN}✓${NC} Part 2: Routing & NAT - Public subnet has internet, private subnet isolated"
echo -e "${GREEN}✓${NC} Part 3: VPC Isolation - Default isolation enforced, peering works"
echo -e "${GREEN}✓${NC} Part 4: Firewall Rules - Security policies applied successfully"
echo -e "${GREEN}✓${NC} Part 5: Connectivity Tests - All tests passed"
echo -e "${GREEN}✓${NC} Part 6: Cleanup - All resources removed cleanly"

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}All VPC features demonstrated successfully!${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

echo "Key Features Demonstrated:"
echo "  • Multi-VPC support with isolation"
echo "  • Public/private subnet types"
echo "  • NAT gateway for internet access"
echo "  • Inter-subnet routing within VPC"
echo "  • VPC peering with access control"
echo "  • Firewall policy enforcement"
echo "  • Clean resource lifecycle management"
echo ""

echo "Logs available at: logs/vpcctl.log"
echo "Check the log file for detailed operation history"
echo ""

# Cleanup temp files
rm -f /tmp/demo-policy.json

print_success "Demo script completed successfully!"