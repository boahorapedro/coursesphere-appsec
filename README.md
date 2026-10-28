# CourseSphere: Avaliação de AppSec e SRE

Desafio técnico AppSec & SRE (Bolsista DevOps / SRE / Segurança). Este repositório contém o código do CourseSphere (backend Flask, frontend React e autenticação e banco no Firebase), a análise de segurança, as correções, as melhorias de proteção e uma camada de confiabilidade (logs, métricas, dashboard e balanceamento).

**Autor:** Pedro Henrique Boa Hora da Silva

> **Origem:** este repositório é um fork de [LambdaAK/CourseSphere](https://github.com/LambdaAK/CourseSphere). O código da aplicação é dos autores originais; o trabalho deste repositório é a análise, as correções, o ambiente isolado, a observabilidade, o CI e a documentação.

| Documento | O que é |
|---|---|
| [`docs/relatorio-tecnico.md`](docs/relatorio-tecnico.md) | Relatório técnico: escopo, metodologia, achados, correções, confiabilidade e recomendações priorizadas |
| [`docs/candidate-findings.md`](docs/candidate-findings.md) | Triagem completa dos 22 candidatos a achado, com status e decisão |
| [`docs/sre/slis-slos.md`](docs/sre/slis-slos.md) | SLIs, SLOs e descrição do dashboard |
| [`docs/evidencias/`](docs/evidencias/) | Saídas dos testes (antes e depois) e das varreduras, uma pasta por achado |

> **Aviso:** todo o ambiente roda **localmente** contra o **emulador** do Firebase. O backend se recusa a iniciar sem as variáveis do emulador, então nenhum teste alcança o projeto real. Não execute os testes contra o Firebase de produção.

## Resumo

- **22 candidatos triados**; **11 reproduzidos** com evidência (exposição de dados sensíveis, autenticação, configuração incorreta e dependências vulneráveis).
- **3 correções:** C05 (credenciais do Reddit versionadas), C04 (token na URL) e C19 (enumeração de usuários).
- **2 melhorias de proteção:** C12 (containers sem root) e C06 (limite de taxa e cabeçalhos de segurança no Nginx).
- **SRE:** logs em JSON, `/health`, `/metrics` (Prometheus), 2 SLIs com SLOs, dashboard no Grafana e balanceamento com Nginx sobre 2 réplicas.
- **CI:** varredura de segredos, SAST, SCA e teste de regressão das correções.

## Estrutura do repositório

```
backend/          API Flask (endpoints.py, firebase.py, observability.py), Dockerfile e entrypoint
frontend/         React + Vite + TypeScript
emulator/         Dockerfile do Firebase Emulator (Auth e Realtime Database)
nginx/            Configuração do balanceador (rate limit, cabeçalhos, 2 réplicas)
observability/    Prometheus e Grafana (datasource e dashboard provisionados)
scripts/          smoke-test.sh (regressão) e generate-traffic.sh (popula o dashboard)
docs/             Relatório, triagem, SLIs/SLOs e evidências
.github/workflows/security.yml   Pipeline de CI
docker-compose.yml
```

## Como executar

### Pré-requisitos
- Docker com Docker Compose v2 (no Windows, o Docker Desktop precisa estar **em execução**).
- `git`, `curl` e `python3` (os scripts usam o Python para ler JSON).

### Subir o ambiente
```bash
git clone https://github.com/boahorapedro/coursesphere-appsec.git
cd coursesphere-appsec
docker compose up --build -d
```
O primeiro build baixa imagens e leva alguns minutos. Depois, **espere cerca de 20 segundos** (o emulador do Firebase demora a ficar pronto) e confira:
```bash
docker compose ps
curl -s http://localhost:5000/health        # {"status":"ok"}
```

### Endereços
| Serviço | URL | Observação |
|---|---|---|
| API (via Nginx) | http://localhost:5000 | ponto de entrada único; o backend não publica porta |
| Frontend | http://localhost:3000 | |
| Grafana | http://localhost:3001 | usuário `admin`, senha `admin` (**só para uso local**, publicado apenas em `127.0.0.1`; troque a senha em qualquer outro uso) |
| Prometheus | http://localhost:9090 | publicado apenas em `127.0.0.1`; veja `/targets` |
| Emulador Auth / Database | http://localhost:9099 / http://localhost:9000 | usados pelos testes |

`/metrics` é interno: pela porta 5000 ele responde `404` de propósito.

### Estado do emulador
O emulador guarda os dados **em memória**. Ao reiniciá-lo (`docker compose restart firebase-emulator` ou `down`/`up`), as contas e os chats desaparecem e precisam ser recriados.

### Derrubar
```bash
docker compose down
```

## Verificar que tudo funciona (teste de fumaça)

Com o ambiente no ar, na raiz do repositório:
```bash
bash scripts/smoke-test.sh
```
O script reinicia o Nginx, aguarda os serviços e verifica as correções e os hardenings (C04, C05, C19, C06, C12), os cabeçalhos de segurança, o balanceamento entre as 2 réplicas, os logs em JSON e as métricas. Termina com `Resultado: N verificações OK, 0 falhas` e código de saída `0` quando tudo passa.

## Como reproduzir os achados

Os comandos de reprodução de cada achado estão na **seção 4 do relatório** (`docs/relatorio-tecnico.md`), e as saídas que obtive estão em `docs/evidencias/<id>/`.

Atenção: os achados **C04, C05, C06, C12 e C19 foram corrigidos na `main`**, então os mesmos comandos mostram o comportamento já corrigido (por exemplo `401` no C04 e `429` no C06). Para ver o estado **vulnerável**, use a tag `v0-executavel` (código original, adaptado só para rodar em Docker, com o backend publicado direto na porta 5000):

```bash
docker compose down                       # libera as portas
git worktree add ../coursesphere-v0 v0-executavel
cd ../coursesphere-v0
docker compose up --build -d              # espere ~20 s
# ... rode os comandos do relatório (seção 4) ...
docker compose down
cd - && git worktree remove ../coursesphere-v0
```

| Tag | Conteúdo |
|---|---|
| `v0-original` | código recebido, sem nenhuma alteração (base das comparações) |
| `v0-executavel` | original + Docker e emulador, **ainda vulnerável** |

| Achado | Onde reproduzir | Evidência |
|---|---|---|
| C05 credenciais do Reddit | `v0-original` (`git log` e `git cat-file`, sem imprimir o valor) | `docs/evidencias/c05/` |
| C04 token na URL, C19 enumeração, C06 sem rate limit, C12 root | `v0-executavel` | `c04/`, `c19/`, `c06/`, `c12/` |
| C01 CORS, C03 erros internos, C15 corpo `null`, C18 isolamento de chats | `main` ou `v0-executavel` | `c01/`, `c03/`, `c15/`, `c18/` |
| C07 versões não fixas, C17 dependências do frontend | qualquer versão | `c07/`, `c17/`, `scans/` |

## Correções e melhorias de proteção

| Tipo | Achado | O que foi feito |
|---|---|---|
| Correção | C05 | segredo removido do código atual, leitura por variáveis de ambiente, `.gitignore` e exemplo documentado |
| Correção | C04 | token lido do cabeçalho `Authorization: Bearer`; na URL é recusado |
| Correção | C19 | resposta idêntica para e-mail novo e já existente |
| Hardening | C12 | backend e frontend executam sem root |
| Hardening | C06 | `limit_req` e cabeçalhos de segurança no Nginx, versão oculta |

Causa raiz, antes e depois de cada uma estão nas seções 6 e 7 do relatório. Os commits explicam o motivo no corpo da mensagem (`git log --oneline`).

## Confiabilidade (SRE)

- **Logs em JSON:** `docker compose logs backend` (uma linha por requisição, com `request_id`, rota, status, duração e réplica).
- **`/health`:** `curl -s http://localhost:5000/health`.
- **`/metrics`:** `docker compose exec -T backend python -c "import urllib.request as u; print(u.urlopen('http://localhost:5000/metrics').read().decode())"`.
- **SLIs e SLOs:** disponibilidade 99,5 % e latência (95 % das requisições em até 500 ms), ambos em 30 dias. Detalhes em `docs/sre/slis-slos.md`.
- **Dashboard:** abra o Grafana (http://localhost:3001), pasta **CourseSphere**, dashboard "CourseSphere: SLOs e tráfego". Ele fica vazio até haver tráfego; gere com
  ```bash
  bash scripts/generate-traffic.sh 120                # 2 minutos de requisições normais
  bash scripts/generate-traffic.sh 120 --with-errors  # inclui alguns erros 500 (C15)
  ```
  Capturas de tela em `docs/evidencias/observabilidade/`.

### Balanceamento e tolerância a falha

```bash
# distribuição entre as 2 réplicas
T=$(date -u +%Y-%m-%dT%H:%M:%SZ)
for i in $(seq 1 20); do curl -s -o /dev/null http://localhost:5000/users/info; sleep 0.1; done
docker compose logs backend --since "$T" | grep '"path": "/users/info"' | cut -d'|' -f1 | sort | uniq -c

# queda de uma réplica: o Nginx tenta a outra, sem erro 5xx
ID=$(docker compose ps -q backend | head -1)
docker stop "$ID"
for i in $(seq 1 6); do curl -s -o /dev/null -w "%{http_code}\n" http://localhost:5000/users/info; done   # 401, nunca 5xx
docker start "$ID"
```
Se, depois de recriar as réplicas, a distribuição ficar desigual, reinicie o balanceador: `docker compose restart nginx` (o Nginx resolve os endereços das réplicas ao iniciar).

## Ferramentas de análise

As mesmas que o CI usa (as saídas completas desta análise estão em `docs/evidencias/scans/`):

| Tipo | Ferramenta | Comando | Saída |
|---|---|---|---|
| SAST | Semgrep | `semgrep scan --config p/python --config p/flask --config p/typescript --config p/react --config p/dockerfile --config p/secrets --exclude backend/cornell-course-sphere-data .` | `scans/semgrep.txt` |
| SAST | Bandit | `bandit -r backend -x backend/cornell-course-sphere-data` | `scans/bandit.txt` |
| SCA | pip-audit | `pip-audit -r backend/requirements.txt` | `scans/pip-audit.txt` |
| SCA | npm audit | `cd frontend && npm audit` (no CI, `--omit=dev` para só runtime) | `scans/npm-audit.txt` |
| Segredos | Gitleaks | `docker run --rm -v "$PWD:/repo" zricethezav/gitleaks:v8.21.2 detect --redact --source /repo` (histórico completo; no CI usa-se `--no-git` para o código atual) | `scans/gitleaks.json` |

## CI (GitHub Actions)

O workflow [`.github/workflows/security.yml`](.github/workflows/security.yml) roda a cada push na `main` e em todo pull request:

| Job | O que faz | Bloqueia? |
|---|---|---|
| `secrets` | Gitleaks no código atual | sim |
| `sast` | Semgrep (relatório completo; nos PRs, só falha em achados **novos** em relação à base) e Bandit | só achados novos |
| `sca` | pip-audit e npm audit | não (informativo: um CVE novo não deve quebrar o build por causa externa) |
| `smoke` | `docker compose up`, `scripts/smoke-test.sh` e logs em caso de falha | sim |

## Comandos Docker úteis

```bash
docker compose up --build -d                  # sobe tudo (reconstrói as imagens)
docker compose ps                             # estado dos serviços
docker compose logs -f backend                # logs das 2 réplicas
docker compose restart nginx                  # relê a configuração e os IPs das réplicas
docker compose up -d --force-recreate nginx   # após editar nginx/default.conf
docker compose exec backend id                # confere que não é root
docker compose down                           # derruba tudo
```

### Windows (Git Bash)
- O Docker Desktop precisa estar aberto antes de qualquer comando `docker`.
- Comandos com caminho absoluto dentro do container (por exemplo `/app/...`) são reescritos pelo Git Bash; use `MSYS_NO_PATHCONV=1` antes do comando ou caminhos relativos.

## Limitações conhecidas
- Os testes usam o emulador: os tokens dele não têm assinatura criptográfica real e as regras do banco são abertas. Os testes avaliam o código do backend, e não a configuração do Firebase de produção.
- O C02 (`debug=True`) foi identificado por scanners e por leitura de código, mas não foi reproduzido.
- O histórico do Git não foi reescrito: a credencial do Reddit (C05) continua nele até ser revogada pelo dono.
- Os SLOs são propostas, ainda não calibradas com tráfego real; métricas e logs não têm armazenamento persistente.

A lista completa de limitações e as recomendações priorizadas estão nas seções 9 e 12 do relatório.