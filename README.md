# Linux Playground 🐧

Uma coleção de scripts Bash e projetos para automação e experimentação em ambientes Linux. Este repositório serve como meu "playground" para explorar soluções de linha de comando, automação de tarefas e administração de sistemas Linux.

---

## Scripts e Projetos

### 1. backup-docker-volumes.sh

* **Descrição:** Um script Bash robusto para automatizar o backup de volumes de containers Docker. O script foi projetado para parar os serviços de forma segura, compactar os dados de cada container individualmente e gerenciar a retenção de backups antigos para economizar espaço.

* **Funcionalidades Principais:**
    * **Gerenciamento de Serviços:** Detecta arquivos `docker-compose.yml` e para os containers antes do backup, reiniciando-os automaticamente após a conclusão.
    * **Backup Individual:** Compacta o diretório de cada container em um arquivo `.tar.gz` separado, facilitando a restauração granular.
    * **Organização Diária:** Armazena os backups em diretórios nomeados com a data atual no formato `YYYYMMDD`.
    * **Política de Retenção:** Mantém os últimos 12 backups e apaga automaticamente os mais antigos, otimizando o uso do disco.
    * **Logging Detalhado:** Cria um arquivo de log para cada execução, registrando todos os passos, sucessos e falhas.

* **Como Usar:**
    1.  Clone o repositório ou baixe o script `backup-docker-volumes.sh`.
    2.  Edite o script e ajuste as variáveis `SOURCE_DIR` e `DEST_DIR` para corresponder aos seus diretórios de volumes Docker e de destino do backup.
    3.  Torne o script executável:
        ```bash
        chmod +x backup-docker-volumes.sh
        ```
    4.  Execute o script. É recomendado usar `sudo` para garantir as permissões necessárias para parar containers e acessar os arquivos.
        ```bash
        sudo ./backup-docker-volumes.sh
        ```

---

### Contato

* **LinkedIn:** [Link para o seu perfil no LinkedIn]
* **Blog/Portfólio:** [Link para o seu site do GitHub Pages]
