#!/bin/bash

# Script v3 (Definitivo): Instala e configura o rclone de forma direta e robusta.
# Cria o arquivo de configuração manualmente para evitar qualquer modo interativo.

# --- Configuração ---
set -e # O script sai imediatamente se um comando falhar.

CURRENT_USER=$(whoami)
USER_GROUP=$(id -gn "$CURRENT_USER")
USER_HOME=$(eval echo "~$CURRENT_USER")
MOUNT_POINT="/mnt/gdrive"
REMOTE_NAME="gdrive"

# --- Início da Execução ---

echo "--- Iniciando a instalação automatizada (v3 - Definitiva) do Rclone ---"

# 1. Preparar o ambiente
echo "--> Passo 1: Criando e configurando o ponto de montagem..."
sudo mkdir -p "$MOUNT_POINT"
sudo chown "$CURRENT_USER":"$USER_GROUP" "$MOUNT_POINT"

# 2. Instalar dependências
echo "--> Passo 2: Instalando pacotes necessários (fuse3, curl)..."
sudo apt-get update && sudo apt-get install -y fuse3 curl

# 3. Instalar o Rclone
echo "--> Passo 3: Baixando e instalando a versão mais recente do rclone..."
curl https://rclone.org/install.sh | sudo bash

# 4. Obter o Token de Autorização (ÚNICA PARTE MANUAL)
echo ""
echo "--------------------------------------------------------------------------"
echo "✨ ATENÇÃO: ÚNICA AÇÃO MANUAL NECESSÁRIA ✨"
echo "--------------------------------------------------------------------------"
echo "1. Copie o comando abaixo:"
echo ""
echo -e "\033[1;32m    rclone authorize \"drive\"\033[0m"
echo ""
echo "2. Execute-o em um computador com navegador."
echo "3. Autorize na sua conta Google. O terminal irá gerar um token JSON."
echo "4. Copie o token COMPLETO (o bloco de texto que começa com '{') e cole abaixo."
echo "--------------------------------------------------------------------------"

read -p "Cole o token de autorização aqui e pressione [Enter]: " rclone_token

if [ -z "$rclone_token" ]; then
    echo "Erro: O token não pode estar vazio. Abortando."
    exit 1
fi

# 5. Criar o arquivo rclone.conf DIRETAMENTE (Método Robusto)
echo ""
echo "--> Passo 5: Criando o arquivo de configuração ~/.config/rclone/rclone.conf diretamente..."
mkdir -p "$USER_HOME/.config/rclone" # Garante que o diretório exista

tee "$USER_HOME/.config/rclone/rclone.conf" > /dev/null <<EOF
[$REMOTE_NAME]
type = drive
scope = drive
token = $rclone_token
EOF
echo "Arquivo de configuração do Rclone criado com sucesso!"

# 6. Criar o arquivo de serviço do Systemd
echo "--> Passo 6: Criando o arquivo de serviço rclone-gdrive.service..."
sudo tee "/etc/systemd/system/rclone-gdrive.service" > /dev/null <<EOF
[Unit]
Description=Montagem do Google Drive (rclone) para o usuário $CURRENT_USER
AssertPathIsDirectory=$MOUNT_POINT
After=network-online.target

[Service]
Type=simple
User=$CURRENT_USER
Group=$USER_GROUP
ExecStart=/usr/bin/rclone mount $REMOTE_NAME: $MOUNT_POINT \\
    --config "$USER_HOME/.config/rclone/rclone.conf" \\
    --allow-other \\
    --vfs-cache-mode writes \\
    --log-level INFO \\
    --log-file /var/log/rclone.log \\
    --allow-non-empty
ExecStop=/bin/fusermount -u $MOUNT_POINT
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF

# 7. Configurar o FUSE
echo "--> Passo 7: Configurando /etc/fuse.conf para permitir 'allow_other'..."
sudo tee "/etc/fuse.conf" > /dev/null <<EOF
user_allow_other
EOF

# 8. Criar e configurar o arquivo de log
echo "--> Passo 8: Criando e configurando o arquivo de log..."
sudo touch /var/log/rclone.log
sudo chown "$CURRENT_USER":"$USER_GROUP" /var/log/rclone.log

# 9. Habilitar e iniciar o serviço
echo "--> Passo 9: Habilitando e iniciando o serviço rclone..."
sudo systemctl daemon-reload
sudo systemctl enable rclone-gdrive.service
sudo systemctl start rclone-gdrive.service

echo ""
echo "--------------------------------------------------------------------------"
echo "✅ INSTALAÇÃO E CONFIGURAÇÃO (v3) CONCLUÍDAS! ✅"
echo "--------------------------------------------------------------------------"
echo "Verifique o status do serviço com o comando:"
echo "sudo systemctl status rclone-gdrive.service"
echo "--------------------------------------------------------------------------"
