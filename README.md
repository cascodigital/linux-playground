# Linux Playground 🐧

Uma coleção de scripts Bash e projetos para automação e experimentação em ambientes Linux. Este repositório serve como meu "playground" para explorar soluções de linha de comando, automação de tarefas e administração de sistemas Linux.

---

## Índice

* [1. setup-rclone-gdrive.sh](#1-setup-rclone-grivesh)
* [2. backup-docker-volumes.sh](#2-backup-docker-volumessh)
* [3. setup-full-server.sh](#3-setup-full-serversh)

---

## Scripts e Projetos

Aqui está a lista de scripts e projetos disponíveis neste repositório.

### 1. setup-rclone-gdrive.sh

* **Descrição:** Um script de setup completo que instala e configura o `rclone` para montar um Google Drive como um diretório local em sistemas Debian/Ubuntu. O script cria um serviço `systemd` para garantir que a montagem seja persistente e automática.
* **Funcionalidades Principais:**
    * **Instalação Automatizada:** Baixa a versão mais recente do `rclone` e instala suas dependências (`fuse3`, `curl`).
    * **Configuração Não-Interativa:** Cria o arquivo de configuração do `rclone` diretamente, exigindo apenas o token JSON de autorização.
    * **Serviço Systemd:** Gera e habilita um serviço `systemd` (`rclone-gdrive.service`) para montar o drive na inicialização do sistema e reiniciá-lo em caso de falha.
    * **Gerenciamento de Permissões:** Configura corretamente as permissões do ponto de montagem, do FUSE (`user_allow_other`), e do arquivo de log.
    * **Logging Centralizado:** Direciona todos os logs de atividade do `rclone` para `/var/log/rclone.log`.
* **Como Usar:**
    1.  **Passo Prévio (em um PC com navegador):** Execute o comando `rclone authorize "drive"` e siga os passos para autorizar o acesso à sua conta Google. Copie o token JSON gerado no final.
    2.  **No Servidor:** Baixe e torne o script executável: `chmod +x setup-rclone-gdrive.sh`.
    3.  **Execução:** Execute o script com `sudo`: `sudo ./setup-rclone-gdrive.sh`.
    4.  O script irá solicitar que você cole o token JSON obtido no passo prévio.

### 2. backup-docker-volumes.sh

* **Descrição:** Um script Bash robusto para automatizar o backup de volumes de containers Docker. O script foi projetado para parar os serviços de forma segura, compactar os dados de cada container individualmente e gerenciar a retenção de backups antigos para economizar espaço.
* **Funcionalidades Principais:**
    * **Gerenciamento de Serviços:** Detecta arquivos `docker-compose.yml` e para os containers antes do backup, reiniciando-os automaticamente após a conclusão.
    * **Backup Individual:** Compacta o diretório de cada container em um arquivo `.tar.gz` separado, facilitando a restauração granular.
    * **Organização Diária:** Armazena os backups em diretórios nomeados com a data atual no formato `YYYYMMDD`.
    * **Política de Retenção:** Mantém os últimos 12 backups e apaga automaticamente os mais antigos, otimizando o uso do disco.
    * **Logging Detalhado:** Cria um arquivo de log para cada execução, registrando todos os passos, sucessos e falhas.
* **Como Usar:**
    1.  Edite o script e ajuste as variáveis `SOURCE_DIR` e `DEST_DIR`.
    2.  Torne o script executável: `chmod +x backup-docker-volumes.sh`.
    3.  Execute com `sudo` para garantir as permissões necessárias: `sudo ./backup-docker-volumes.sh`.

### 3. setup-full-server.sh

* **Descrição:** Um script modular e interativo para a configuração completa e inicial de um servidor Linux (Debian/Ubuntu). Automatiza a preparação de discos, compartilhamento de rede, backups em nuvem e a implantação de serviços essenciais e de mídia via Docker.
* **Funcionalidades Principais:**
    * **Interface Modular:** Permite ao usuário escolher quais partes da configuração executar através de um menu interativo, ou rodar tudo de uma vez.
    * **Gestão de Disco e Samba:** Detecta um disco secundário, oferece a opção de formatá-lo (ext4), configura a montagem automática em `/dados` via `/etc/fstab` e cria um compartilhamento de rede Samba para acesso facilitado.
    * **Backup com Rclone e Cron:** Instala o Rclone, guia o usuário na configuração do Google Drive, cria um serviço `systemd` para a montagem e agenda um backup diário (com retenção de 15 dias) da pasta `/dados/dockers` usando `cron`.
    * **Deploy de Serviços Core:** Implanta um conjunto de serviços essenciais via Docker Compose, incluindo Cloudflare Tunnel (requer token), Portainer, Vaultwarden (gerenciador de senhas) e Marreta.
    * **Deploy de Stack de Mídia:** Automatiza a instalação de uma stack de mídia completa com Plex, Sonarr, Radarr e SABnzbd, criando a estrutura de diretórios e arquivos de configuração necessários.
    * **Preparação de Ambiente:** Garante que o Docker e o Docker Compose estejam instalados usando o método oficial e adiciona o usuário ao grupo `docker` para execução de comandos sem `sudo`.
* **Como Usar:**
    1.  Torne o script executável: `chmod +x setup-full-server.sh`.
    2.  Execute com privilégios `sudo`: `sudo ./setup-full-server.sh`.
    3.  Siga o menu interativo, escolhendo as opções desejadas.
    4.  Tenha em mãos os tokens necessários (Cloudflare, token de autorização do Rclone) para colar quando solicitado.

---

## 📊 Projetos Docker

### Ações Treemap
Dashboard interativo de ações da B3 com rotação automática entre visualizações.
- Localização: `dockers/acoes-treemap/`
- Tecnologias: Python, Plotly Dash, Docker
