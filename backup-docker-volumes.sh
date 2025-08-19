#!/bin/bash

SOURCE_DIR="/media/aristofeles/3t/dockers"
DEST_DIR="/mnt/gdrive/dockers"
DATE=$(date +%Y%m%d)
BACKUP_DIR="$DEST_DIR/$DATE"
LOG_FILE="/tmp/backup_completo_$(date +%Y%m%d_%H%M%S).log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

backup_container() {
    local container="$1"
    log "=== Processando: $container ==="

    cd "$SOURCE_DIR/$container" || { log "ERRO: Não conseguiu entrar em $container"; return 1; }

    # Parar docker se tiver
    if [ -f "docker-compose.yml" ] || [ -f "compose.yml" ]; then
        log "Parando docker: $container"
        docker compose down 2>/dev/null
        sleep 5
    fi

    # Fazer backup
    log "Compactando: $container"

    if sudo tar -czf "$BACKUP_DIR/${container}.tar.gz" -C "$SOURCE_DIR" "$container" 2>/dev/null; then
        sudo chown aristofeles:aristofeles "$BACKUP_DIR/${container}.tar.gz"
        size=$(ls -lh "$BACKUP_DIR/${container}.tar.gz" | awk '{print $5}')
        log "✓ SUCCESS: $container - $size"
    else
        log "✗ FAILED: $container"
    fi

    # Religar docker se tiver
    if [ -f "docker-compose.yml" ] || [ -f "compose.yml" ]; then
        log "Religando docker: $container"
        docker compose up -d 2>/dev/null
        sleep 8
    fi
}

cleanup_old_backups() {
    log "=== INICIANDO LIMPEZA DE BACKUPS ANTIGOS ==="
    
    # Listar todas as pastas no diretório de destino (apenas nomes de pastas que são datas)
    local backup_dirs=()
    for dir in "$DEST_DIR"/*/; do
        if [ -d "$dir" ]; then
            folder_name=$(basename "$dir")
            # Verificar se o nome da pasta é uma data válida (8 dígitos)
            if [[ $folder_name =~ ^[0-9]{8}$ ]]; then
                backup_dirs+=("$folder_name")
            fi
        fi
    done
    
    # Ordenar as pastas (mais antigas primeiro)
    IFS=$'\n' backup_dirs_sorted=($(sort <<< "${backup_dirs[*]}"))
    unset IFS
    
    local total_backups=${#backup_dirs_sorted[@]}
    log "Total de backups encontrados: $total_backups"
    
    if [ $total_backups -gt 12 ]; then
        local to_delete=$((total_backups - 12))
        log "Preciso deletar $to_delete backup(s) antigo(s)"
        
        # Deletar os mais antigos
        for ((i=0; i<to_delete; i++)); do
            local old_backup="${backup_dirs_sorted[$i]}"
            local old_path="$DEST_DIR/$old_backup"
            
            log "Deletando backup antigo: $old_backup"
            if rm -rf "$old_path"; then
                log "✓ Deletado com sucesso: $old_backup"
            else
                log "✗ ERRO ao deletar: $old_backup"
            fi
        done
        
        log "Limpeza concluída. Mantidos os últimos 12 backups."
    else
        log "Apenas $total_backups backups encontrados. Nenhuma limpeza necessária."
    fi
    
    # Mostrar backups restantes
    log "Backups mantidos:"
    for ((i=$((total_backups > 12 ? total_backups - 12 : 0)); i<total_backups; i++)); do
        if [ $i -ge 0 ] && [ $i -lt ${#backup_dirs_sorted[@]} ]; then
            backup_date="${backup_dirs_sorted[$i]}"
            if [ -d "$DEST_DIR/$backup_date" ]; then
                backup_size=$(du -sh "$DEST_DIR/$backup_date" 2>/dev/null | awk '{print $1}' || echo "N/A")
                log "  → $backup_date ($backup_size)"
            fi
        fi
    done
}

# Criar diretório
mkdir -p "$BACKUP_DIR"
log "=== BACKUP COMPLETO INICIADO ==="
log "Destino: $BACKUP_DIR"

# Pegar TODAS as pastas (exceto non.docker e arquivos)
all_containers=()
for item in "$SOURCE_DIR"/*; do
    if [ -d "$item" ]; then
        folder=$(basename "$item")
        if [ "$folder" != "non.docker" ] && [ "$folder" != "lost+found" ]; then
            all_containers+=("$folder")
        fi
    fi
done

log "TOTAL DE CONTAINERS ENCONTRADOS: ${#all_containers[@]}"
log "Lista completa: ${all_containers[*]}"

# Contar quantos já foram feitos
already_done=0
for container in "${all_containers[@]}"; do
    if [ -f "$BACKUP_DIR/${container}.tar.gz" ]; then
        ((already_done++))
    fi
done

log "Já processados: $already_done"
log "Restantes: $((${#all_containers[@]} - already_done))"

# Processar apenas os que ainda não foram feitos
count=0
for container in "${all_containers[@]}"; do
    if [ ! -f "$BACKUP_DIR/${container}.tar.gz" ]; then
        ((count++))
        log "[$count/${#all_containers[@]}] Processando: $container"
        backup_container "$container"
        sleep 3
    else
        log "PULANDO: $container (já existe)"
    fi
done

log "=== BACKUP COMPLETO FINALIZADO ==="
log "Verificando todos os arquivos:"
ls -lh "$BACKUP_DIR/"*.tar.gz | tee -a "$LOG_FILE"

total_files=$(ls -1 "$BACKUP_DIR/"*.tar.gz 2>/dev/null | wc -l)
total_size=$(du -sh "$BACKUP_DIR" | awk '{print $1}')
log "Total de arquivos: $total_files"
log "Tamanho total: $total_size"

# NOVA FUNCIONALIDADE: Limpeza dos backups antigos
cleanup_old_backups

log "=== PROCESSO COMPLETO FINALIZADO ==="
