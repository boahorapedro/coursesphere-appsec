# SLIs, SLOs e dashboard

Este documento define os indicadores de nível de serviço (SLIs) e os objetivos (SLOs) da API do CourseSphere, e descreve o dashboard que os mede.

## Escopo e fonte dos dados
- **Escopo:** as requisições da API que passam pelo Nginx. `/health` e `/metrics` ficam fora, para a checagem de saúde não inflar os números.
- **Fonte:** as métricas `http_requests_total` (contador por método, rota e status) e `http_request_duration_seconds` (histograma de latência por rota), expostas por cada réplica do backend em `/metrics` e coletadas pelo Prometheus a cada 5 segundos.
- **Onde é medido:** na aplicação (backend). Não inclui o tempo de rede nem o do navegador do usuário.

## Por que estes dois SLIs
Os dois descrevem o que o usuário sente na API: se ela **responde sem erro** e se responde **rápido**.

Exemplos comuns (latência de login, taxa de erro do CRUD de cursos) não se aplicam a este projeto:
- O **login** é feito direto no Firebase pelo SDK do frontend, e não passa pelo nosso backend; não temos como medi-lo aqui.
- O **CRUD de cursos** não existe na API ativa: o blueprint `courses.py` não está registrado no `endpoints.py`.

As rotas de negócio que existem e passam pelo backend são o cadastro (`/users/create`), o perfil (`/users/info`), a consulta (`/users/query`) e os chats (`/chats/...`). Os SLIs abaixo cobrem todas elas e podem ser filtrados por rota no Prometheus (por exemplo, `route="/users/create"`) para acompanhar um fluxo específico.

## SLI 1: Disponibilidade (taxa de sucesso)
- **Definição:** proporção de requisições que **não** terminam em erro de servidor (status 5xx).
- **Consulta (Prometheus, janela de 5 min):**
  `sum(rate(http_requests_total{status!~"5.."}[5m])) / sum(rate(http_requests_total[5m]))`
- **SLO proposto:** 99,5 % das requisições sem erro 5xx, em 30 dias.
- **Orçamento de erro:** 0,5 %, ou seja, até 5 falhas a cada 1000 requisições (em tempo corrido, cerca de 3 h 36 min de indisponibilidade total em 30 dias).
- **Por que 99,5 %:** é um serviço sem redundância de região e que depende do Firebase; 99,9 % exigiria uma infraestrutura que não existe aqui. Com 2 réplicas atrás do Nginx, a queda de uma delas não derruba o serviço (ver `docs/evidencias/nginx/tolerancia-a-falha.txt`).
- **Limitação:** respostas 4xx contam como "boas". O código converte várias exceções internas em `400` (`str(e)` nas rotas), então uma falha de servidor pode se disfarçar de 4xx e não consumir orçamento. Melhoria: devolver `5xx` para exceções inesperadas. Respostas `429` do rate limit são geradas pelo Nginx e não passam pelo backend, portanto não entram neste SLI.

## SLI 2: Latência
- **Definição:** proporção de requisições atendidas em até 500 ms.
- **Consulta (Prometheus, janela de 5 min):**
  `sum(rate(http_request_duration_seconds_bucket{le="0.5"}[5m])) / sum(rate(http_request_duration_seconds_count[5m]))`
- **SLO proposto:** 95 % das requisições em até 500 ms, em 30 dias.
- **Por que uma proporção e não a média:** a média esconde a cauda lenta. Uma única requisição de 10 s entre 99 de 10 ms mantém a média baixa, mas o usuário afetado teve uma experiência ruim.
- **Base do limite:** nas medições locais, a primeira requisição autenticada levou cerca de 370 ms (verificação do token no primeiro uso) e as seguintes ficaram em torno de 10 ms. O limite de 500 ms deixa margem para esse caso e deve ser revisto com tráfego real.
- **Limitação:** as medições foram feitas contra o emulador do Firebase; em produção, a latência do Firebase soma ao tempo.

## Alertas (proposta, não implementada)
- **Rápido:** taxa de erro 5xx acima de 5 % por 5 minutos (consumo acelerado do orçamento).
- **Lento:** taxa de erro acima de 1 % por 1 hora.
- **Latência:** menos de 90 % das requisições em até 500 ms por 15 minutos.

## Dashboard (Grafana)
Acesso local: `http://localhost:3001` (pasta **CourseSphere**, dashboard "CourseSphere: SLOs e tráfego"). Ele é provisionado por arquivos e sobe já configurado com o `docker compose up`.

**Linha 1, "SLOs"**
1. **Disponibilidade (SLO 99,5 %)**, valor único, vermelho abaixo da meta:
   `sum(increase(http_requests_total{status!~"5.."}[30d])) / sum(increase(http_requests_total[30d]))`
2. **Latência ≤ 500 ms (SLO 95 %)**, valor único, vermelho abaixo da meta:
   `sum(increase(http_request_duration_seconds_bucket{le="0.5"}[30d])) / sum(increase(http_request_duration_seconds_count[30d]))`
3. **Orçamento de erro restante**, valor único: `1 - ((1 - disponibilidade) / 0.005)`. 100 % significa que nenhum erro consumiu o orçamento; 0 %, que o orçamento esgotou.
4. **Réplicas do backend no ar**, valor único: `count(up{job="backend"} == 1)` (esperado: 2).

**Linha 2, "Tráfego"**
5. **Requisições por rota**, série temporal: `sum by (route) (rate(http_requests_total[1m]))`
6. **Requisições por status HTTP**, série empilhada: `sum by (status) (rate(http_requests_total[1m]))`

**Linha 3, "Réplicas e latência"**
7. **Distribuição entre réplicas**, série temporal: `sum by (instance) (rate(http_requests_total[1m]))` (mostra o balanceamento do Nginx)
8. **Latência p50, p95 e p99**, série temporal:
   `histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))` (e o mesmo com 0.5 e 0.99)

## Implementação e evidências
- Métricas e logs: `backend/observability.py` (contador e histograma; logs JSON com `request_id`, rota, status, duração e réplica).
- Coleta: `observability/prometheus.yml` (descoberta das réplicas por DNS, coleta a cada 5 s).
- Dashboard: `observability/grafana/dashboards/coursesphere-slo.json`, com o datasource provisionado em `observability/grafana/provisioning/`.
- Evidências: `docs/evidencias/observabilidade/` (`/health`, logs JSON, métricas, capturas do dashboard e dos alvos do Prometheus).

## Limitações gerais
- O histórico de métricas e os logs não têm armazenamento persistente (sem volumes): um `docker compose down` os apaga. Em produção, o Prometheus teria disco persistente e os logs iriam para um sistema central com retenção.
- Os SLOs são propostas justificadas, e devem ser revistos com dados de tráfego real.
- Há logs e métricas, mas não há rastreamento distribuído (traces).