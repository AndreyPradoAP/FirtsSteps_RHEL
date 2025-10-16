#!/bin/bash

# Adicionar função para configurar o SNMP automáticamente

# Script de Configuração para Sistemas RHEL
# Autor: Gerado para gerenciamento de sistema RHEL
# Data: 2025

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para exibir mensagens coloridas
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCESSO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERRO]${NC} $1"
}

# Verificar se o script está sendo executado como root
check_root() {
    if [[ $EUID -ne 0 ]]; then # O valor do EUID do root é sempre 0
        print_error "Este script deve ser executado como root!"
        exit 1
    fi
}

# Função para atualizar o sistema
update_system() {
    print_info "Iniciando atualização do sistema..."
    
    if dnf update -y; then
        print_success "Sistema atualizado com sucesso!"
    else
        print_error "Falha ao atualizar o sistema!"
        return 1
    fi
}

# Função para criar usuários
create_users() {
    print_info "=== CRIAÇÃO DE USUÁRIOS ==="
    
    read -p "Quantos usuários deseja criar? " num_users
    
    if ! [[ "$num_users" =~ ^[0-9]+$ ]] || [ "$num_users" -lt 1 ]; then
        print_error "Número inválido de usuários!"
        return 1
    fi
    
    for ((i=1; i<=num_users; i++)); do
        echo ""
        print_info "Configurando usuário $i de $num_users"
        
        read -p "Nome do usuário: " username
        
        # Verificar se usuário já existe
        if id "$username" &>/dev/null; then
            print_warning "Usuário '$username' já existe! Pulando..."
            continue
        fi
        
        read -sp "Senha para $username: " password
        echo ""
        read -sp "Confirme a senha: " password_confirm
        echo ""
        
        if [ "$password" != "$password_confirm" ]; then
            print_error "As senhas não coincidem!"
            ((i--))
            continue
        fi
        
        read -p "Este usuário terá acesso root (sudo)? (s/n): " root_access
        
        # Criar usuário
        if useradd -m -s /bin/bash "$username"; then
            echo "$username:$password" | chpasswd
            
            # Adicionar ao grupo wheel se tiver acesso root
            if [[ "$root_access" =~ ^[sS]$ ]]; then
                usermod -aG wheel "$username"
                print_success "Usuário '$username' criado com acesso root!"
            else
                print_success "Usuário '$username' criado sem acesso root!"
            fi
        else
            print_error "Falha ao criar usuário '$username'!"
        fi
    done
}

# Função para listar interfaces de rede
list_interfaces() {
    print_info "Interfaces de rede disponíveis:"
    ip -o link show | awk -F': ' '{print "  - " $2}' | grep -v lo
}

# Função para validar IP
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [ "$i" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Função para configurar IP de uma interface
configure_interface_ip() {
    local interface=$1
    
    print_info "Configurando IP para interface: $interface"
    
    read -p "Endereço IP: " ip_addr
    if ! validate_ip "$ip_addr"; then
        print_error "IP inválido!"
        return 1
    fi
    
    read -p "Máscara de rede (ex: 24): " netmask
    if ! [[ "$netmask" =~ ^[0-9]+$ ]] || [ "$netmask" -lt 1 ] || [ "$netmask" -gt 32 ]; then
        print_error "Máscara inválida!"
        return 1
    fi
    
    read -p "Gateway (deixe em branco se não houver): " gateway
    if [ -n "$gateway" ] && ! validate_ip "$gateway"; then
        print_error "Gateway inválido!"
        return 1
    fi
    
    # Configurar usando nmcli
    nmcli con mod "$interface" ipv4.addresses "$ip_addr/$netmask"
    nmcli con mod "$interface" ipv4.method manual
    
    if [ -n "$gateway" ]; then
        nmcli con mod "$interface" ipv4.gateway "$gateway"
    fi
    
    nmcli con up "$interface"
    
    print_success "IP configurado para $interface: $ip_addr/$netmask"
}

# Função para configurar IPs
configure_ips() {
    print_info "=== CONFIGURAÇÃO DE IPs ==="
    
    list_interfaces
    
    read -p "Deseja configurar IPs para as interfaces? (s/n): " config_ips
    
    if [[ ! "$config_ips" =~ ^[sS]$ ]]; then
        return 0
    fi
    
    while true; do
        read -p "Nome da interface (ou 'sair' para terminar): " interface
        
        if [ "$interface" = "sair" ]; then
            break
        fi
        
        if ! ip link show "$interface" &>/dev/null; then
            print_error "Interface '$interface' não encontrada!"
            continue
        fi
        
        configure_interface_ip "$interface"
        
        echo ""
        read -p "Configurar outra interface? (s/n): " another
        if [[ ! "$another" =~ ^[sS]$ ]]; then
            break
        fi
    done
}

# Função para configurar firewall
configure_firewall() {
    print_info "=== CONFIGURAÇÃO DO FIREWALL ==="
    
    # Verificar se firewalld está instalado e ativo
    if ! systemctl is-active --quiet firewalld; then
        print_info "Iniciando firewalld..."
        systemctl start firewalld
        systemctl enable firewalld
    fi
    
    list_interfaces
    
    # Configurar interface pública
    echo ""
    read -p "Nome da interface PÚBLICA (apenas ping permitido): " public_iface
    
    # Verificação da existência da interface
    if ! ip link show "$public_iface" &>/dev/null; then
        print_error "Interface pública '$public_iface' não encontrada!"
        return 1
    fi
    
    # Configurar interface interna
    read -p "Nome da interface INTERNA (ping e SSH permitidos): " internal_iface
    
    # Verificação da existência da interface
    if ! ip link show "$internal_iface" &>/dev/null; then
        print_error "Interface interna '$internal_iface' não encontrada!"
        return 1
    fi
    
    if [ "$public_iface" = "$internal_iface" ]; then
        print_error "As interfaces devem ser diferentes!"
        return 1
    fi
    
    print_info "Configurando zona pública para $public_iface..."
    
    # Criar e configurar zona pública
    firewall-cmd --permanent --zone=public --remove-interface="$public_iface" 2>/dev/null
    firewall-cmd --permanent --zone=public --add-interface="$public_iface"
    firewall-cmd --permanent --zone=public --remove-service=ssh 2>/dev/null
    firewall-cmd --permanent --zone=public --remove-service=dhcpv6-client 2>/dev/null
    firewall-cmd --permanent --zone=public --add-icmp-block-inversion
    firewall-cmd --permanent --zone=public --add-icmp-block=echo-request
    firewall-cmd --permanent --zone=public --remove-icmp-block=echo-request
    
    print_success "Interface pública configurada: $public_iface (apenas PING)"
    
    print_info "Configurando zona interna para $internal_iface..."
    
    # Criar e configurar zona interna
    firewall-cmd --permanent --zone=internal --remove-interface="$internal_iface" 2>/dev/null
    firewall-cmd --permanent --zone=internal --add-interface="$internal_iface"
    firewall-cmd --permanent --zone=internal --add-service=ssh
    
    print_success "Interface interna configurada: $internal_iface (PING e SSH)"
    
    # Recarregar firewall
    firewall-cmd --reload
    
    print_success "Firewall configurado com sucesso!"
    
    # Exibir configuração
    echo ""
    print_info "Configuração atual do firewall:"
    echo "----------------------------------------"
    firewall-cmd --list-all-zones | grep -A 10 "^public\|^internal"
}

# Menu principal
main_menu() {
    while true; do
        clear
        echo ""
        echo "========================================"
        echo "  SCRIPT DE CONFIGURAÇÃO RHEL"
        echo "========================================"
        echo "1. Atualizar sistema"
        echo "2. Criar usuários"
        echo "3. Configurar IPs das interfaces"
        echo "4. Configurar Firewall"
        echo "5. Executar todas as opções"
        echo "6. Sair"
        echo "========================================"
        read -p "Escolha uma opção: " choice
        
        case $choice in
            1)
                update_system
                ;;
            2)
                create_users
                ;;
            3)
                configure_ips
                ;;
            4)
                configure_firewall
                ;;
            5)
                update_system
                echo ""
                create_users
                echo ""
                configure_ips
                echo ""
                configure_firewall
                print_success "Todas as configurações foram concluídas!"
                ;;
            6)
                print_info "Encerrando script..."
                exit 0
                ;;
            *)
                print_error "Opção inválida!"
                ;;
        esac
    done
}

# Início do script
check_root
main_menu
