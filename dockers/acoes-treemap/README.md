# Treemap de Acoes - Docker

Dashboard interativo para visualizar suas acoes em formato treemap, similar ao InfoMoney.

## Estrutura de Arquivos

/dados/dockers/acoes/treemap/
├── docker-compose.yml
├── Dockerfile
├── requirements.txt
├── app/
│   └── main.py
└── acoes.csv

## Instalacao

1. Crie a estrutura de diretorios:
```bash
mkdir -p /dados/dockers/acoes/treemap/app
cd /dados/dockers/acoes/treemap
```

2. Crie os arquivos conforme os conteudos fornecidos

3. Inicie o container:
```bash
docker-compose up -d
```

## Uso

- Acesse: http://localhost:8050
- Atualizacao automatica a cada 5 minutos
- Para adicionar/remover acoes: edite acoes.csv e reinicie o container

## Gerenciamento de Acoes

Para adicionar novas acoes, edite o arquivo acoes.csv:

ticker,shares
CAML3.SA,100
KLBN4.SA,150
PNVL3.SA,200
VALE3.SA,50
PETR4.SA,75

**IMPORTANTE**: Use o sufixo .SA para acoes brasileiras

Apos editar, reinicie o container:
```bash
docker-compose restart
```

## Comandos Uteis

# Parar o container
docker-compose down

# Ver logs
docker-compose logs -f

# Reiniciar
docker-compose restart

# Rebuild (apos mudancas no codigo)
docker-compose up -d --build

## Funcionalidades

- Visualizacao em treemap hierarquico
- Cores baseadas em variacao percentual (verde = alta, vermelho = queda)
- Tamanho proporcional ao valor investido
- Atualizacao automatica a cada 5 minutos
- Interface responsiva
- Dados em tempo real via Yahoo Finance
