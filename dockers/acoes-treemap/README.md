Treemap de Ações - Docker

Este projeto é um dashboard web que exibe sua carteira de ações brasileiras em formato de treemap. Ele busca dados em tempo real do Yahoo Finance, permitindo que você visualize variação no dia, na semana ou o total investido. A carteira é gerenciada diretamente pela interface web ou pela edição manual do arquivo acoes.csv. A atualização dos dados acontece automaticamente a cada cinco minutos. Tudo roda via Docker, sem depender de instalação do Python ou bibliotecas externas.

Para instalar e rodar, siga estes passos simples:

Tenha Docker e Docker Compose instalados.

Clone ou copie a pasta do projeto para sua máquina. Exemplo usando Git:
git clone https://github.com/cascodigital/linux-playground.git
cd linux-playground

(Opcional) Monte a imagem Docker usando:
docker compose build

Suba o container:
docker compose up -d

Acesse no navegador:
http://localhost:8050

Para adicionar, editar ou remover ações, use o painel web ou edite o arquivo acoes.csv manualmente. Após alterações diretas no CSV, reinicie o container:
docker compose restart

Para parar o serviço, use:
docker compose down

Licença MIT.