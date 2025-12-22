#!/bin/bash

# Multi-Chain Deployment Script
# Usage: ./deploy.sh <network>
# Example: ./deploy.sh sepolia

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
KEYSTORE="${KEYSTORE:-$HOME/.foundry/keystores/default}"
SCRIPT="script/MultiChainDeploy.s.sol:MultiChainDeployScript"

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ ${NC}$1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    if ! command -v forge &> /dev/null; then
        print_error "forge not found. Please install Foundry."
        exit 1
    fi
    
    if [ ! -f "$KEYSTORE" ]; then
        print_error "Keystore not found at $KEYSTORE"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to display help
show_help() {
    cat << EOF
${BLUE}Polymarket Multi-Chain Deployment Script${NC}

${YELLOW}Usage:${NC}
  ./deploy.sh <network> [options]

${YELLOW}Supported Networks:${NC}

  ${GREEN}Testnets:${NC}
    sepolia              Ethereum Sepolia
    arbitrum-sepolia     Arbitrum Sepolia
    optimism-sepolia     Optimism Sepolia
    base-sepolia         Base Sepolia
    polygon-amoy         Polygon Amoy (testnet)

  ${RED}Mainnets:${NC}
    mainnet              Ethereum Mainnet
    arbitrum             Arbitrum One
    optimism             Optimism
    base                 Base
    polygon              Polygon

  ${BLUE}Local:${NC}
    local                Local Anvil instance

${YELLOW}Options:${NC}
  --no-verify          Skip contract verification
  --help               Show this help message

${YELLOW}Environment Variables:${NC}
  KEYSTORE             Path to keystore file (default: ~/.foundry/keystores/default)
  KEYSTORE_PASSWORD    Password for keystore (will prompt if not set)
  ETHERSCAN_API_KEY    Etherscan API key for verification

${YELLOW}Examples:${NC}
  ./deploy.sh sepolia
  ./deploy.sh arbitrum-sepolia --no-verify
  ./deploy.sh mainnet

EOF
}

# Function to get RPC URL for network
get_rpc_url() {
    case $1 in
        sepolia)
            echo "sepolia"
            ;;
        arbitrum-sepolia)
            echo "arbitrum_sepolia"
            ;;
        optimism-sepolia)
            echo "optimism_sepolia"
            ;;
        base-sepolia)
            echo "base_sepolia"
            ;;
        polygon-amoy)
            echo "polygon_amoy"
            ;;
        mainnet)
            echo "mainnet"
            ;;
        arbitrum)
            echo "arbitrum"
            ;;
        optimism)
            echo "optimism"
            ;;
        base)
            echo "base"
            ;;
        polygon)
            echo "polygon"
            ;;
        local)
            echo "localhost"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Function to check if network is mainnet
is_mainnet() {
    case $1 in
        mainnet|arbitrum|optimism|base|polygon)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Main deployment function
deploy() {
    local network=$1
    local verify=$2
    
    local rpc_url=$(get_rpc_url "$network")
    
    if [ -z "$rpc_url" ]; then
        print_error "Unknown network: $network"
        echo ""
        show_help
        exit 1
    fi
    
    # Warn for mainnet deployments
    if is_mainnet "$network"; then
        print_warning "⚠️  WARNING: You are about to deploy to ${RED}${network}${NC} mainnet!"
        print_warning "This will cost real money and is irreversible."
        echo ""
        read -p "Type 'YES' to continue: " confirm
        if [ "$confirm" != "YES" ]; then
            print_info "Deployment cancelled."
            exit 0
        fi
    fi
    
    print_info "Deploying to $network..."
    echo ""
    
    # Set Etherscan API key for Sepolia
    if [ "$network" = "sepolia" ]; then
        export ETHERSCAN_API_KEY="PJFEDANUFHK7RWQXU52P67QXJTVM4HB9IU"
    fi
    
    # Build command
    local cmd="forge script $SCRIPT --rpc-url $rpc_url --keystore $KEYSTORE --broadcast -vvvv"
    
    if [ "$verify" = "true" ]; then
        cmd="$cmd --verify"
    fi
    
    # Ask for password if not set
    if [ -z "$KEYSTORE_PASSWORD" ]; then
        read -s -p "Enter keystore password: " KEYSTORE_PASSWORD
        echo ""
    fi
    
    # Execute deployment
    export KEYSTORE_PASSWORD
    if eval "$cmd --password \"$KEYSTORE_PASSWORD\""; then
        echo ""
        print_success "Deployment to $network completed successfully!"
        
        # Show deployment info
        if [ -d "deployments" ]; then
            print_info "Deployment info saved to deployments/ directory"
        fi
        
        if [ -d "broadcast/MultiChainDeploy.s.sol" ]; then
            print_info "Broadcast data saved to broadcast/ directory"
        fi
    else
        echo ""
        print_error "Deployment failed!"
        exit 1
    fi
}

# Main script
main() {
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi
    
    local network=""
    local verify="true"
    
    # Parse arguments
    while [ $# -gt 0 ]; do
        case $1 in
            --help)
                show_help
                exit 0
                ;;
            --no-verify)
                verify="false"
                shift
                ;;
            *)
                network=$1
                shift
                ;;
        esac
    done
    
    if [ -z "$network" ]; then
        print_error "No network specified"
        echo ""
        show_help
        exit 1
    fi
    
    check_prerequisites
    deploy "$network" "$verify"
}

# Run main function
main "$@"
