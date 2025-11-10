Stage 4: Virtual Private Cloud (VPC) Implementation

Project Overview

A Linux-based Virtual Private Cloud (VPC) management tool that recreates cloud VPC fundamentals using network namespaces, bridges, veth pairs, and iptables. The `vpcctl` CLI enables creation, management, and isolation of virtual networks entirely on a single Linux host.


Features

- VPC Management: Create isolated virtual private clouds with custom CIDR ranges
- Subnet Support: Public and private subnets with automatic IP assignment
- Network Isolation: Each subnet runs in its own network namespace
- NAT Gateway: Public subnets have internet access via iptables MASQUERADE
- VPC Peering: Connect isolated VPCs for controlled cross-VPC communication
- Firewall Policies: JSON-based security rules enforced with iptables
- State Management: Persistent tracking of all resources
- Idempotent Operations: Safe to run commands multiple times
- Comprehensive Logging: All actions logged with timestamps

Architecture

High-Level Design



Component Breakdown

1. Network Namespaces: Each subnet is an isolated network namespace with its own network stack
2. Veth Pairs: Virtual ethernet pairs connect namespaces to the bridge (one end in namespace, one on bridge)
3. Linux Bridge: Acts as the VPC router, forwarding traffic between subnets
4. iptables NAT: MASQUERADE rules enable internet access for public subnets
5. iptables Firewall: Security group rules applied inside namespaces


Installation

1. Clone the Repository

```bash
git clone <your-repo-url>
cd vpc-project
```

2. Make vpcctl Executable

```bash
chmod +x bin/vpcctl
chmod +x demo-script.sh
```

3. Verify Installation

```bash
sudo ./bin/vpcctl help
```

Quick Start

Basic VPC Setup

```bash
1. Create a VPC
sudo ./bin/vpcctl create-vpc myvpc 10.0.0.0/16

2. Create public subnet (with internet access)
sudo ./bin/vpcctl create-subnet myvpc public 10.0.1.0/24 public

3. Create private subnet (no internet)
sudo ./bin/vpcctl create-subnet myvpc private 10.0.2.0/24 private

4. List your VPC
sudo ./bin/vpcctl list-vpcs
sudo ./bin/vpcctl list-subnets myvpc

5. Deploy a web server
sudo ./bin/vpcctl deploy-webserver myvpc public

6. Test it
curl http://10.0.1.10

7. Test connectivity
sudo ./bin/vpcctl test-connectivity myvpc

8. Clean up when done
sudo ./bin/vpcctl cleanup-all
```

CLI Usage

VPC Management

```bash
sudo ./bin/vpcctl create-vpc <vpc-name> <cidr>
sudo ./bin/vpcctl create-vpc production 10.0.0.0/16

sudo ./bin/vpcctl delete-vpc <vpc-name>
sudo ./bin/vpcctl delete-vpc production

sudo ./bin/vpcctl list-vpcs
```

Subnet Management

```bash
sudo ./bin/vpcctl create-subnet <vpc> <subnet-name> <cidr> <type>
sudo ./bin/vpcctl create-subnet production web 10.0.1.0/24 public
sudo ./bin/vpcctl create-subnet production db 10.0.2.0/24 private

sudo ./bin/vpcctl delete-subnet <vpc> <subnet-name>
sudo ./bin/vpcctl delete-subnet production web

sudo ./bin/vpcctl list-subnets <vpc-name>
sudo ./bin/vpcctl list-subnets production
```

Application Deployment

```bash
sudo ./bin/vpcctl deploy-webserver <vpc> <subnet>
sudo ./bin/vpcctl deploy-webserver production web

curl http://10.0.1.10
```

VPC Peering

```bash
sudo ./bin/vpcctl create-vpc staging 172.16.0.0/16
sudo ./bin/vpcctl create-subnet staging app 172.16.1.0/24 public

sudo ./bin/vpcctl peer-vpcs production staging

sudo ip netns exec production-web ping 172.16.1.10

sudo ./bin/vpcctl unpeer-vpcs production staging
```
Firewall Policies

```bash
sudo ./bin/vpcctl apply-policy <vpc> <subnet> <policy-file>
sudo ./bin/vpcctl apply-policy production web configs/example-policies/web-server-policy.json
```
Example Policy File

```json
{
  "subnet": "10.0.1.0/24",
  "description": "Web server policy - Allow HTTP/HTTPS, deny SSH",
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
```
Testing & Validation

```bash
sudo ./bin/vpcctl test-connectivity <vpc-name>
sudo ./bin/vpcctl test-connectivity production

sudo ./demo-script.sh
```

Cleanup

```bash
sudo ./bin/vpcctl delete-vpc production

sudo ./bin/vpcctl cleanup-all
```

Testing & Validation

Automated Testing

Run the comprehensive test suite:

```bash
sudo ./demo-script.sh
```

This script validates:
- VPC creation with bridges and namespaces
- Subnet creation and CIDR assignment
- Intra-VPC communication
- Public subnet internet access (NAT)
- Private subnet isolation
- Inter-VPC isolation (default)
- VPC peering functionality
- Firewall policy enforcement
- Clean resource teardown

Manual Testing

Test 1: Intra-VPC Communication

```bash
sudo ./bin/vpcctl create-vpc test 10.0.0.0/16
sudo ./bin/vpcctl create-subnet test sub1 10.0.1.0/24 public
sudo ./bin/vpcctl create-subnet test sub2 10.0.2.0/24 private

sudo ./bin/vpcctl deploy-webserver test sub1
sudo ./bin/vpcctl deploy-webserver test sub2

curl http://10.0.1.10
curl http://10.0.2.10
```

Test 2: NAT Gateway

```bash
sudo ip netns exec test-sub1 ping -c 3 8.8.8.8
sudo ip netns exec test-sub1 curl -I google.com

sudo ip netns exec test-sub2 ping -c 3 8.8.8.8
```

Test 3: VPC Isolation

```bash
sudo ./bin/vpcctl create-vpc isolated 172.16.0.0/16
sudo ./bin/vpcctl create-subnet isolated web 172.16.1.0/24 public

sudo ip netns exec test-sub1 ping 172.16.1.10  # Should fail

sudo ./bin/vpcctl peer-vpcs test isolated

sudo ip netns exec test-sub1 ping 172.16.1.10  # Should succeed
```

Test 4: Firewall Enforcement

```bash
sudo ./bin/vpcctl apply-policy test sub1 configs/example-policies/web-server-policy.json

curl http://10.0.1.10

```

Architecture Diagram

Packet Flow: Intra-VPC Communication

```
Namespace A (10.0.1.10)  →  veth-ns  →  veth-h  →  Bridge  →  veth-h  →  veth-ns  →  Namespace B (10.0.2.10)
```

Packet Flow: Internet Access (NAT)

```
Namespace (10.0.1.10)  →  veth  →  Bridge  →  iptables NAT  →  Host Interface  →  Internet
                                                  (MASQUERADE)
```

VPC Peering

```
VPC1 Bridge  ←→  veth pair  ←→  VPC2 Bridge
   ↓                               ↓
Subnets                        Subnets
```

Check Logs

```bash
tail -f logs/vpcctl.log

grep ERROR logs/vpcctl.log
```

Cleanup
```bash
sudo ./bin/vpcctl delete-subnet <vpc> <subnet>
sudo ./bin/vpcctl delete-vpc <vpc-name>
```

Clean Up Everything
```bash
sudo ./bin/vpcctl cleanup-all

sudo ip netns list              # Should be empty
sudo ip link show type bridge   # VPC bridges should be gone
cat configs/vpc_state.txt       # Should be empty
```