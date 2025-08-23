#!/bin/bash

# ==============================================================================
#   SCRIPT DE CONFIGURAÇÃO COMPLETA DE SERVIDOR v1.9
# ==============================================================================
#   v1.9:
#   - CORRIGIDO: A instalação do Docker agora usa o script oficial get.docker.com
#     para garantir que o docker-ce e o docker-compose-plugin sejam
#     instalados corretamente, resolvendo o erro "Unable to locate package".
# ==============================================================================

# --- Configurações Iniciais e Cores ---
set -e # Sai do script se um comando falhar

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Variáveis Globais ---
REAL_USER=""
PUID=""
PGID=""
USER_HOME=""
IP_ADDR=""
CAMINHO_BASE_DADOS="/dados" # Padrão Fixo
COMPOSE_CMD="" # Será definido dinamicamente

# --- Funções de Preparação ---
preparar_ambiente() {
    if [ "$(id -u)" -ne 0 ]; then
      echo -e "${RED}ERRO: Este script precisa ser executado com privilégios de root (sudo).${NC}" >&2
      exit 1
    fi
    REAL_USER=${SUDO_USER:-$(logname 2>/dev/null)}
    if [ -z "$REAL_USER" ]; then
        echo -e "${RED}ERRO: Não foi possível detectar o usuário que invocou o sudo.${NC}" >&2
        exit 1
    fi
    PUID=$(id -u "$REAL_USER")
    PGID=$(id -g "$REAL_USER")
    USER_HOME=$(eval echo "~$REAL_USER")
    IP_ADDR=$(hostname -I | awk '{print $1}')
}

preparar_docker() {
    echo -e "${YELLOW}--> Preparando ambiente Docker...${NC}"
    if ! command -v docker &> /dev/null; then
        echo "Docker não encontrado. Instalando via script oficial (get.docker.com)..."
        # =========================================================================
        # BLOCO CORRIGIDO (v1.9): Usa o método de instalação oficial do Docker
        # =========================================================================
        apt-get update
        apt-get install -y curl
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        # O script oficial já habilita e inicia o serviço Docker.
        echo -e "${GREEN}Docker instalado com sucesso.${NC}"
    fi

    if ! getent group docker | grep -qw "$REAL_USER"; then
        echo "Adicionando o usuário ${REAL_USER} ao grupo 'docker'..."
        usermod -aG docker "$REAL_USER"
        echo -e "${YELLOW}AVISO: Para usar 'docker' sem 'sudo', pode ser necessário SAIR e ENTRAR novamente.${NC}"
    fi

    if docker compose version &>/dev/null; then
        COMPOSE_CMD="docker compose"
        echo -e "${GREEN}Usando 'docker compose' (V2).${NC}"
    elif command -v docker-compose &>/dev/null; then
        COMPOSE_CMD="docker-compose"
        echo -e "${YELLOW}Usando 'docker-compose' (V1). Considere atualizar.${NC}"
    else
        echo -e "${RED}ERRO CRÍTICO: Não foi possível encontrar o Docker Compose mesmo após a instalação.${NC}"
        exit 1
    fi
    echo ""
}

# ==============================================================================
#   FUNÇÕES MODULARES
# ==============================================================================

# --- Função 1: Configuração de Disco e Samba ---
configurar_disco_e_samba() {
    echo -e "${YELLOW}--- MÓDULO 1: Configuração de Disco e Compartilhamento Samba ---${NC}"
    echo "--> Verificando discos conectados..."
    ROOT_DISK_NAME=$(lsblk -no pkname "$(findmnt -n -o SOURCE /)")
    mapfile -t ALL_DISKS < <(lsblk -dno name,type | awk '$2=="disk" {print $1}')
    TARGET_DISK_NAME=""
    for disk in "${ALL_DISKS[@]}"; do
        if [[ "$disk" != "$ROOT_DISK_NAME" ]]; then
            TARGET_DISK_NAME=$disk
            break
        fi
    done
    if [ -z "$TARGET_DISK_NAME" ]; then
        echo -e "${RED}ERRO: Apenas o disco do sistema ($ROOT_DISK_NAME) foi encontrado.${NC}"
        echo "Por favor, conecte o disco secundário/externo e execute o script novamente."
        return 1
    fi
    TARGET_DISK_DEV="/dev/${TARGET_DISK_NAME}"
    echo -e "${GREEN}Disco secundário detectado: ${TARGET_DISK_DEV}${NC}"
    read -p "Deseja FORMATAR o disco ${TARGET_DISK_DEV} (todos os dados serão perdidos)? (s/N): " formatar_disco
    if [[ "$formatar_disco" =~ ^[sS]$ ]]; then
        read -p "CONFIRMAÇÃO FINAL: TUDO em ${TARGET_DISK_DEV} será APAGADO. Digite '${TARGET_DISK_NAME}' para confirmar: " FINAL_CONFIRM
        if [[ "$FINAL_CONFIRM" != "$TARGET_DISK_NAME" ]]; then echo -e "${RED}A confirmação final falhou. Abortando.${NC}"; return 1; fi
        echo "--> Preparando o disco ${TARGET_DISK_DEV}..."
        umount ${TARGET_DISK_DEV}* &>/dev/null || true
        parted -s "$TARGET_DISK_DEV" mklabel gpt >/dev/null 2>&1
        parted -s -a optimal "$TARGET_DISK_DEV" mkpart primary ext4 0% 100% >/dev/null 2>&1
        partprobe "$TARGET_DISK_DEV"; sleep 3
        TARGET_PARTITION="${TARGET_DISK_DEV}1"
        if [ ! -b "$TARGET_PARTITION" ]; then TARGET_PARTITION="${TARGET_DISK_DEV}p1"; fi
        if [ ! -b "$TARGET_PARTITION" ]; then echo "${RED}Erro fatal: Partição não encontrada após formatação.${NC}"; return 1; fi
        echo "--> Formatando ${TARGET_PARTITION} como ext4..."
        mkfs.ext4 -F -L dados "$TARGET_PARTITION" >/dev/null 2>&1
        UUID=$(blkid -s UUID -o value "$TARGET_PARTITION")
    else
        echo "--> Identificando partição principal em ${TARGET_DISK_DEV}..."
        mapfile -t partitions < <(lsblk -plno NAME "${TARGET_DISK_DEV}" | grep -v "${TARGET_DISK_DEV}$")
        if [ ${#partitions[@]} -eq 0 ]; then echo -e "${RED}Erro: Nenhuma partição encontrada no disco ${TARGET_DISK_DEV}. Você precisa formatá-lo primeiro.${NC}"; return 1; fi
        TARGET_PARTITION=${partitions[0]}
        echo "--> Partição alvo para montagem: ${TARGET_PARTITION}"
        FSTYPE=$(blkid -s TYPE -o value "$TARGET_PARTITION")
        if [[ "$FSTYPE" == "ntfs" ]] && ! command -v ntfs-3g &> /dev/null; then
            echo "--> Detectado sistema de arquivos NTFS. Instalando driver 'ntfs-3g'..."
            apt-get install -y ntfs-3g
        fi
        UUID=$(blkid -s UUID -o value "$TARGET_PARTITION")
    fi
    if [ -z "$UUID" ]; then echo -e "${RED}Erro: Não foi possível obter o UUID de ${TARGET_PARTITION}. Abortando.${NC}"; return 1; fi
    echo "--> Configurando a partição ${TARGET_PARTITION} para ser montada em ${CAMINHO_BASE_DADOS}..."
    umount "$TARGET_PARTITION" &>/dev/null || true
    mkdir -p "$CAMINHO_BASE_DADOS"
    FSTYPE=$(blkid -s TYPE -o value "$TARGET_PARTITION")
    FSTAB_LINE="UUID=$UUID $CAMINHO_BASE_DADOS $FSTYPE defaults,nofail,errors=remount-ro 0 2"
    sed -i".bak" "\#${UUID}#d" /etc/fstab
    sed -i".bak" "\#${CAMINHO_BASE_DADOS}#d" /etc/fstab
    echo "--> Fazendo backup e atualizando /etc/fstab..."
    echo "" >> /etc/fstab; echo "# Entrada adicionada por script em $(date)" >> /etc/fstab; echo "$FSTAB_LINE" >> /etc/fstab
    echo "--> Montando todos os discos..."; mount -a
    if ! mountpoint -q "$CAMINHO_BASE_DADOS"; then echo -e "${RED}Erro fatal: A montagem da partição em ${CAMINHO_BASE_DADOS} falhou. Verifique o /etc/fstab. Abortando.${NC}"; return 1; fi
    echo -e "${GREEN}Partição montada com sucesso em ${CAMINHO_BASE_DADOS}.${NC}"
    echo -e "\n${YELLOW}--> Configurando o Samba...${NC}"
    apt-get install -y samba
    SAMBA_CONF="/etc/samba/smb.conf"; if [ -f "$SAMBA_CONF" ]; then cp "$SAMBA_CONF" "/etc/samba/smb.conf.bak.$(date +%Y%m%d_%H%M%S)"; fi
    cat > "$SAMBA_CONF" << EOF
[global]
workgroup = WORKGROUP
server string = %h server (Samba)
log file = /var/log/samba/log.%m
max log size = 1000
server role = standalone server
security = user
map to guest = bad user
obey pam restrictions = yes
unix password sync = yes
passwd program = /usr/bin/passwd %u
passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully* .
pam password change = yes
usershare allow guests = no

[dados]
path = ${CAMINHO_BASE_DADOS}
comment = Arquivos de Midia
browseable = yes
writable = yes
read only = no
valid users = ${REAL_USER}
create mask = 0664
directory mask = 0775
force user = ${REAL_USER}
force group = ${REAL_USER}
EOF
    echo "Defina uma senha de rede (Samba) para o usuário ${REAL_USER}:"; smbpasswd -a "$REAL_USER" || echo "Usuário ${REAL_USER} já existe no Samba."; smbpasswd -e "$REAL_USER"
    systemctl restart smbd nmbd && systemctl enable smbd nmbd
    echo -e "${GREEN}Módulo de Disco e Samba configurado com sucesso!${NC}\n"
}

# --- Função 2: Instalação do Rclone e Configuração de Backup Agendado ---
configurar_backup_agendado() {
    echo -e "\n${YELLOW}--> Configurando backup agendado (diário às 02:00)...${NC}"
    local SCRIPT_PATH="/usr/local/bin/backup_rclone.sh"
    local LOG_FILE="/var/log/rclone_backup.log"
    local REMOTE_NAME="gdrive" # Mesmo nome usado na configuração do rclone
    local CRON_FILE="/etc/cron.d/rclone_backup"

    # Cria o script de backup
    tee "$SCRIPT_PATH" > /dev/null <<EOF
#!/bin/bash
# Script de backup com Rclone e retenção de 15 dias. Gerado por script de instalação.

SOURCE="${CAMINHO_BASE_DADOS}/dockers"
DESTINATION="${REMOTE_NAME}:Backup"
LOGFILE="${LOG_FILE}"
RCLONE_CONFIG_FILE="${USER_HOME}/.config/rclone/rclone.conf"
DATE=\$(date +"%Y-%m-%d")

# Garante que o arquivo de log exista
touch \$LOGFILE

log_message() {
    echo "[\$(date)] - \$1" >> \$LOGFILE
}

log_message "--- INICIANDO PROCESSO DE BACKUP ---"

# 1. Copia os dados para uma pasta com a data atual
/usr/bin/rclone copy "\$SOURCE" "\${DESTINATION}/\${DATE}" --config "\$RCLONE_CONFIG_FILE" --log-file=\$LOGFILE -v
if [ \$? -ne 0 ]; then
    log_message "ERRO: A cópia dos dados falhou. Verifique o log."
    exit 1
fi
log_message "Cópia dos dados concluída com sucesso."

# 2. Remove backups com mais de 15 dias
log_message "Limpando backups com mais de 15 dias..."
/usr/bin/rclone delete --min-age 15d "\${DESTINATION}" --config "\$RCLONE_CONFIG_FILE" --log-file=\$LOGFILE -v
log_message "Limpeza de backups antigos finalizada."

log_message "--- PROCESSO DE BACKUP FINALIZADO ---"
echo "" >> \$LOGFILE
EOF

    # Define permissões e cria o arquivo de log
    chmod +x "$SCRIPT_PATH"
    touch "$LOG_FILE"
    chown "$REAL_USER":"$REAL_USER" "$LOG_FILE"

    # Cria o arquivo de agendamento do cron
    echo "# Executa o backup com rclone todos os dias às 02:00 da manhã" > "$CRON_FILE"
    echo "0 2 * * * root $SCRIPT_PATH" >> "$CRON_FILE"
    chmod 0644 "$CRON_FILE"

    echo -e "${GREEN}Script de backup criado em:${NC} ${SCRIPT_PATH}"
    echo -e "${GREEN}Agendamento do cron criado em:${NC} ${CRON_FILE}"
}

instalar_rclone() {
    echo -e "${YELLOW}--- MÓDULO 2: Instalação do Rclone para Google Drive (Backup) ---${NC}";
    MOUNT_POINT="/mnt/gdrive"; REMOTE_NAME="gdrive"
    echo "--> Instalando dependências e o rclone..."; apt-get install -y fuse3 curl; curl https://rclone.org/install.sh | sudo bash
    mkdir -p "$MOUNT_POINT" && chown "$REAL_USER":"$REAL_USER" "$MOUNT_POINT"
    echo -e "\n${YELLOW}================================================================================${NC}"
    echo -e "${YELLOW}   ✨ ATENÇÃO: PASSO MANUAL DE AUTORIZAÇÃO NECESSÁRIO ✨${NC}\n"
    echo "   Como este script roda num servidor, a autorização com o Google precisa ser feita em um computador que tenha navegador.\n"
    echo -e "${GREEN}   PASSO 1: Em OUTRO computador (seu notebook, etc.), instale o rclone (Instruções: https://rclone.org/install/).${NC}\n"
    echo -e "${GREEN}   PASSO 2: No terminal desse outro computador, execute o comando: ${NC}rclone authorize \"drive\"\n"
    echo -e "${GREEN}   PASSO 3: Seu navegador vai abrir. Faça login na conta Google e permita o acesso.${NC}\n"
    echo -e "${GREEN}   PASSO 4: Volte ao terminal do seu notebook. Um código longo (token) começando com '{\"access_token\":...}' será exibido.${NC}\n"
    echo -e "${GREEN}   PASSO 5: Copie TODO esse código e cole-o aqui neste terminal do servidor.${NC}"
    echo -e "${YELLOW}================================================================================${NC}"
    read -p "Cole o token de autorização completo aqui: " rclone_token

    if [ -z "$rclone_token" ]; then echo -e "${RED}Erro: O token não pode estar vazio. Abortando.${NC}"; return 1; fi
    echo "--> Criando arquivos de configuração e serviço..."; mkdir -p "$USER_HOME/.config/rclone";
    chown -R "$REAL_USER":"$REAL_USER" "$USER_HOME/.config"
    tee "$USER_HOME/.config/rclone/rclone.conf" > /dev/null <<EOF
[${REMOTE_NAME}]
type = drive
scope = drive
token = ${rclone_token}
EOF
    sudo tee "/etc/systemd/system/rclone-gdrive.service" > /dev/null <<EOF
[Unit]
Description=Montagem do Google Drive (rclone) para o usuário ${REAL_USER}
AssertPathIsDirectory=${MOUNT_POINT}
After=network-online.target
[Service]
Type=simple
User=${REAL_USER}
Group=$(id -gn "${REAL_USER}")
ExecStart=/usr/bin/rclone mount ${REMOTE_NAME}: ${MOUNT_POINT} --config "${USER_HOME}/.config/rclone/rclone.conf" --allow-other --vfs-cache-mode writes --log-level INFO --log-file /var/log/rclone.log
ExecStop=/bin/fusermount -u ${MOUNT_POINT}
Restart=always
RestartSec=10
[Install]
WantedBy=default.target
EOF
    if ! grep -q "^user_allow_other" /etc/fuse.conf; then echo "user_allow_other" | sudo tee -a /etc/fuse.conf; fi
    sudo touch /var/log/rclone.log && sudo chown "$REAL_USER":"$REAL_USER" /var/log/rclone.log
    echo "--> Habilitando e iniciando o serviço rclone...";
    sudo systemctl daemon-reload && sudo systemctl enable --now rclone-gdrive.service
    echo -e "${GREEN}Módulo Rclone configurado com sucesso!${NC}"

    # Chama a função para criar o script de backup e agendar no cron
    if configurar_backup_agendado; then
      echo -e "${GREEN}Configuração de backup agendado finalizada com sucesso!${NC}\n"
    else
      echo -e "${RED}Ocorreu um erro na configuração do backup agendado.${NC}\n"
    fi
}

# --- Função 3: Instalação dos Serviços Core (4dock) ---
instalar_servicos_core() {
    echo -e "${YELLOW}--- MÓDULO 3: Instalação dos Serviços Core (Cloudflare, Portainer, Vaultwarden, Marreta) ---${NC}";
    DOCKER_CONFIG_PATH="${CAMINHO_BASE_DADOS}/dockers"
    FOLDERS=("cloudflare" "portainer" "vaultwarden" "marreta"); for folder in "${FOLDERS[@]}"; do mkdir -p "${DOCKER_CONFIG_PATH}/${folder}"; chown -R "$PUID:$PGID" "${DOCKER_CONFIG_PATH}/${folder}"; done
    echo -e "${YELLOW}--- Configurando Cloudflared ---${NC}"; read -p "COLE AQUI SEU TOKEN DO CLOUDFLARE TUNNEL: " CLOUDFLARE_TOKEN
    echo "TUNNEL_TOKEN=${CLOUDFLARE_TOKEN}" > "${DOCKER_CONFIG_PATH}/cloudflare/.env"
    cat > "${DOCKER_CONFIG_PATH}/cloudflare/docker-compose.yml" << EOF
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared-tunnel
    restart: unless-stopped
    command: tunnel --no-autoupdate run --token \${TUNNEL_TOKEN}
EOF
    echo -e "${YELLOW}--- Configurando Portainer ---${NC}"
    cat > "${DOCKER_CONFIG_PATH}/portainer/docker-compose.yml" << EOF
services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    ports:
      - "8000:8000"
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
volumes:
  portainer_data: {}
EOF
    echo -e "${YELLOW}--- Configurando Vaultwarden ---${NC}"; read -p "CRIE UMA SENHA PARA O ADMIN_TOKEN (GUARDE-A BEM): " ADMIN_TOKEN
    cat > "${DOCKER_CONFIG_PATH}/vaultwarden/docker-compose.yml" << EOF
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    volumes:
      - "./:/data"
    ports:
      - "80:80"
    environment:
      - ADMIN_TOKEN=${ADMIN_TOKEN}
EOF
    echo -e "${YELLOW}--- Configurando Marreta ---${NC}"
    cat > "${DOCKER_CONFIG_PATH}/marreta/docker-compose.yml" << EOF
services:
  marreta:
    image: ghcr.io/manualdousuario/marreta:latest
    container_name: marreta
    restart: unless-stopped
    ports:
      - "18880:80"
    volumes:
      - "./app/cache:/app/cache"
      - "./app/logs:/app/logs"
    environment:
      SITE_URL: "http://${IP_ADDR}:18880"
      SELENIUM_HOST: "selenium-hub"
  selenium-hub:
    image: selenium/hub:latest
    container_name: selenium-hub
    restart: unless-stopped
    ports:
      - "4444:4444"
  selenium-chromium:
    image: selenium/node-chromium:latest
    container_name: selenium-chromium
    restart: unless-stopped
    shm_size: 2gb
    depends_on:
      - selenium-hub
    environment:
      SE_EVENT_BUS_HOST: "selenium-hub"
      SE_EVENT_BUS_PUBLISH_PORT: "4442"
      SE_EVENT_BUS_SUBSCRIBE_PORT: "4443"
EOF
    echo "Iniciando todos os contêineres de serviços core..."
    for service in "${FOLDERS[@]}"; do
        echo "--> Iniciando ${service}..."; (cd "${DOCKER_CONFIG_PATH}/${service}" && $COMPOSE_CMD up -d)
    done
    echo -e "${YELLOW}Removendo ADMIN_TOKEN do docker-compose.yml do Vaultwarden por segurança...${NC}"
    (cd "${DOCKER_CONFIG_PATH}/vaultwarden" && sed -i '/environment:/,$d' docker-compose.yml)
    echo -e "${GREEN}Módulo de Serviços Core configurado com sucesso!${NC}\n"
}
# --- Função 4: Instalação da Stack de Mídia (*arrs) ---
instalar_stack_midia() {
    echo -e "${YELLOW}--- MÓDULO 4: Instalação da Stack de Mídia (Plex, Sonarr, Radarr, SABnzbd) ---${NC}";
    DOCKER_CONFIG_PATH="${CAMINHO_BASE_DADOS}/dockers"
    TV_PATH="${CAMINHO_BASE_DADOS}/tv"; MOVIES_PATH="${CAMINHO_BASE_DADOS}/movies"; DOWNLOADS_PATH="${CAMINHO_BASE_DADOS}/downloads"
    echo "--> Criando e permissionando estrutura de diretórios para mídia..."
    for path in "$DOCKER_CONFIG_PATH" "$TV_PATH" "$MOVIES_PATH" "$DOWNLOADS_PATH"; do mkdir -p "$path"; chown -R "$PUID:$PGID" "$path"; done
    chmod -R u=rwX,g=rwX,o=rX "${CAMINHO_BASE_DADOS}"
    echo "--> Gerando arquivos docker-compose.yml para a stack de mídia..."
    SERVICES=("plex" "sabnzbd" "sonarr" "radarr"); for service in "${SERVICES[@]}"; do mkdir -p "${DOCKER_CONFIG_PATH}/${service}" && chown "$PUID:$PGID" "${DOCKER_CONFIG_PATH}/${service}"; done
    cat > "${DOCKER_CONFIG_PATH}/plex/docker-compose.yml" << EOF
version: '3.7'
services:
  plex:
    image: plexinc/pms-docker
    container_name: plex
    network_mode: host
    restart: always
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=America/Sao_Paulo
      - UMASK=002
    volumes:
      - './config:/config'
      - '${TV_PATH}:/tv'
      - '${MOVIES_PATH}:/movies'
EOF
    cat > "${DOCKER_CONFIG_PATH}/sabnzbd/docker-compose.yml" << EOF
version: "3.7"
services:
  sabnzbd:
    image: ghcr.io/linuxserver/sabnzbd
    container_name: sabnzbd
    restart: always
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=America/Sao_Paulo
      - UMASK=002
    volumes:
      - './config:/config'
      - '${DOWNLOADS_PATH}:/downloads'
      - '${DOWNLOADS_PATH}/incomplete:/incomplete-downloads'
    ports:
      - "58080:8080"
      - "59090:9090"
EOF
    cat > "${DOCKER_CONFIG_PATH}/sonarr/docker-compose.yml" << EOF
version: "3.7"
services:
  sonarr:
    image: ghcr.io/linuxserver/sonarr
    container_name: sonarr
    restart: always
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=America/Sao_Paulo
      - UMASK=002
    volumes:
      - './config:/config'
      - '${TV_PATH}:/tv'
      - '${DOWNLOADS_PATH}:/downloads'
    ports:
      - "58989:8989"
EOF
    cat > "${DOCKER_CONFIG_PATH}/radarr/docker-compose.yml" << EOF
version: "3.7"
services:
  radarr:
    image: lscr.io/linuxserver/radarr:latest
    container_name: radarr
    restart: always
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=America/Sao_Paulo
      - UMASK=002
    volumes:
      - './config:/config'
      - '${MOVIES_PATH}:/movies'
      - '${DOWNLOADS_PATH}:/downloads'
    ports:
      - "57878:7878"
EOF
    echo "--> Iniciando os contêineres da stack de mídia..."
    for service in "${SERVICES[@]}"; do echo "--> Iniciando contêiner: ${service}"; (cd "${DOCKER_CONFIG_PATH}/${service}" && $COMPOSE_CMD up -d); done
    echo -e "${GREEN}Módulo da Stack de Mídia configurado com sucesso!${NC}\n"
}
# ==============================================================================
#   EXECUÇÃO PRINCIPAL
# ==============================================================================
clear
preparar_ambiente
echo "======================================================================"
echo "       SCRIPT DE CONFIGURAÇÃO COMPLETA DE SERVIDOR v1.9"
echo "======================================================================"
echo "Usuário detectado: ${REAL_USER} (PUID=${PUID}, PGID=${PGID})"
echo ""
preparar_docker
while true; do
    echo "Escolha uma opção para instalar:"
    echo "  1) Configurar Disco Secundário (Automático) e Compartilhamento Samba"
    echo "  2) Instalar Rclone (Google Drive Backup)"
    echo "  3) Instalar Serviços Core (Cloudflare, Portainer, etc.)"
    echo "  4) Instalar Stack de Mídia (Plex, *arrs, etc.)"
    echo "  -------------------------------------------------"
    echo "  5) EXECUTAR TUDO (Recomendado para primeira instalação)"
    echo "  q) Sair"
    echo ""
    read -p "Opção: " choice
    case $choice in
        1) configurar_disco_e_samba ;;
        2) instalar_rclone ;;
        3) instalar_servicos_core ;;
        4) instalar_stack_midia ;;
        5)
            if configurar_disco_e_samba; then
                instalar_rclone && instalar_servicos_core && instalar_stack_midia && break
            fi ;;
        q) echo "Saindo."; exit 0 ;;
        *) echo -e "${RED}Opção inválida. Tente novamente.${NC}" ;;
    esac
done
# --- Finalização ---
echo -e "${GREEN}========================================================"
echo "       🚀 CONFIGURAÇÃO CONCLUÍDA! 🚀"
echo "========================================================${NC}"
echo -e "\nResumo dos acessos configurados:\n"
echo "  Compartilhamento de Rede (Samba):"
echo "    Endereço: \\\\${IP_ADDR}\\dados"
echo "    Usuário: ${REAL_USER}\n"
echo "  Serviços via Navegador:"
echo "    Portainer:   https://${IP_ADDR}:9443"
echo "    Vaultwarden: http://${IP_ADDR}"
echo "    Marreta:     http://${IP_ADDR}:18880"
echo "    Plex:        http://${IP_ADDR}:32400/web"
echo "    SABnzbd:     http://${IP_ADDR}:58080"
echo "    Sonarr:      http://${IP_ADDR}:58989"
echo "    Radarr:      http://${IP_ADDR}:57878\n"
echo "  Montagem Google Drive:"
echo "    Ponto de Montagem: /mnt/gdrive"
echo "    Status: sudo systemctl status rclone-gdrive.service\n"
echo -e "${YELLOW}Lembrete: Se o grupo docker foi adicionado agora, saia e entre novamente para usar 'docker' sem 'sudo'.${NC}"
