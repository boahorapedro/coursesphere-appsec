# Candidatos a achado — CourseSphere

Triagem inicial a partir de Semgrep, Bandit, Gitleaks e leitura manual do código (tag `v0-original`).

**Status:** `confirmar` (validar na prática) · `confirmado` (reproduzido, com evidência) · `risco-latente` (existe no código, hoje não explorável) · `falso-positivo` · `informativo` · `investigar` (ainda falta ler/testar) · `não-vulnerável` (testado, sem falha)

**Decisão:** `Corrigir` (correção implementada no repositório) · `Hardening` (melhoria extra implementada) · `Recomendar` (descrito no relatório, não implementado) · `Aceitar risco` (justificado no relatório) · `A definir`

**Severidade preliminar:** Alta · Média · Baixa (pode mudar após a validação). Categorias seguem os nomes do OWASP Top 10.

**Pré-requisito dos comandos de validação:** backend rodando **localmente** em `http://localhost:5000` (com Firebase Emulator). Nunca testar contra o projeto Firebase real.

| ID | Título | Fonte | Local | Categoria | Alcançável? | Como validar | Sev. prelim. | Status | Decisão |
|----|--------|-------|-------|-----------|-------------|--------------|--------------|--------|---------|
| C01 | CORS aberto para qualquer origem | Leitura manual (nenhum scanner apontou) | backend/endpoints.py:8 (`CORS(app)`) | Security Misconfiguration | Sim, todas as rotas | `curl -i -H "Origin: https://evil.example" http://localhost:5000/users/info` e conferir que `Access-Control-Allow-Origin` ecoa a origem enviada | Baixa (a autenticação é por Bearer token, não por cookie, o que reduz o impacto) | confirmado | Recomendar |
| C02 | Flask com `debug=True` (debugger do Werkzeug) | Bandit B201, Semgrep debug-enabled | backend/endpoints.py:108 | Security Misconfiguration | Só se o app for executado com `python endpoints.py`; o Docker atual usa `flask run` (sem debug); escuta só em 127.0.0.1 por padrão e exige PIN | Rodar com `python endpoints.py`, provocar erro não tratado (ver C15) e verificar a página de traceback interativa | Média (Alta se exposto fora do localhost) | confirmar | Recomendar |
| C03 | Detalhes internos de exceção devolvidos ao cliente (`str(e)`) | Leitura manual | backend/endpoints.py (várias rotas, ex.: `/users/info`, `/users/query`) | Security Misconfiguration / Sensitive Data Exposure | Sim | `curl -i -X POST http://localhost:5000/users/info -H "Content-Type: application/json" -d '{"id_token":"x"}'` e observar a mensagem de erro interna na resposta | Baixa | confirmado | Recomendar |
| C04 | Token de autenticação aceito na query string | Leitura manual | backend/endpoints.py (`GET /users/info`, `request.args.get("id_token")`); o frontend também envia o token na URL (frontend/src/api.ts) | Authentication Failures / Sensitive Data Exposure | Sim | Chamar `GET /users/info?id_token=TOKEN` com token de teste e conferir em `docker logs` que a URL com o token foi registrada | Média | confirmado | Corrigir |
| C05 | Credenciais do Reddit versionadas (`client_id` e `client_secret`) | Gitleaks (generic-api-key) | backend/cornell-course-sphere-data/reddit-data/reddit_key.json | Sensitive Data Exposure / Secrets | Sim, está no repositório e no histórico (introduzido no commit c979a1e, 2024-07-16); o Gitleaks sinalizou o `client_secret` e o `client_id` está no mesmo arquivo | `git log --oneline --all -- backend/cornell-course-sphere-data/reddit-data/reddit_key.json` e `git cat-file -e v0-original:backend/cornell-course-sphere-data/reddit-data/reddit_key.json` (confirmam a presença sem imprimir o valor) | Média (credenciais de API de terceiros; recomendar revogar e gerar novas) | confirmado (Gitleaks); evidência em `docs/evidencias/scans/gitleaks.json` | Corrigir |
| C06 | Sem rate limiting em `/users/create` e demais rotas | Leitura manual | backend/endpoints.py (`/users/create`) | Security Misconfiguration / Authentication Failures | Sim | Com o emulador: `for i in $(seq 1 50); do curl -s -o /dev/null -w "%{http_code}\n" -X POST http://localhost:5000/users/create -H "Content-Type: application/json" -d "{\"email\":\"t$i@teste.com\",\"password\":\"Senha123\"}"; done` e verificar que todas retornam 200 | Média | confirmado | Hardening |
| C07 | Dependências Python sem versão fixa | Leitura manual, pip-audit | backend/requirements.txt | Vulnerable and Outdated Components / Integrity | Sim (a cada build podem entrar versões diferentes) | `uv pip compile requirements.txt --exclude-newer 2024-07-16T00:00:00Z` (resolução de 2024) contra `uv pip compile requirements.txt` (resolução de hoje) e `pip freeze` na imagem construída; detalhes em `docs/evidencias/c07/` | Baixa | confirmado | Recomendar |
| C08 | SQL montado com f-string (injeção SQL latente) | Bandit B608 (×6), Semgrep tainted-sql-string | backend/blueprints/courses.py:30, 47, 64, 80, 96, 112 | Injection | Não hoje: blueprint comentado em endpoints.py, nunca importado, SQLite ausente (caminho com typo) e conexão fechada antes do fetch. Das 6 consultas, 3 usam `<int:...>` e não seriam injetáveis; 3 usam `<string:...>` (semester, department, instructor) | Demonstrar só em ambiente controlado (registrar o blueprint e criar o banco) ou documentar como risco latente | Média | risco-latente | Recomendar |
| C09 | Entrada do usuário concatenada no prompt do LLM (prompt injection) | Leitura manual | backend/main.py (`make_prompt`), backend/query_manager.py; rota `POST /users/query` | Injection (LLM) / Insecure Design | Não hoje: `QueryManager` é um stub (as chamadas à OpenAI estão comentadas e ele devolve um texto fixo). Passa a valer quando o LLM for integrado | `grep -n "openai\|Fake" backend/query_manager.py` para conferir que o stub não chama o modelo | Baixa | risco-latente | Recomendar |
| C10 | Chave de API do Firebase no frontend | Gitleaks (gcp-api-key, 2 ocorrências) | frontend/src/firebaseConfig.ts:2 (código atual); frontend/src/App.tsx:13 (só no histórico, commit 27bc032) | Sensitive Data Exposure (provável falso positivo) | Sim, mas chaves web do Firebase são públicas por desenho; o risco real depende das regras de segurança do banco do projeto, que não são testáveis (fora do escopo) | Documentar a justificativa; não testar contra o projeto real | Baixa (informativo) | falso-positivo | Aceitar risco |
| C11 | Uso de `random` em `hashFunction` | Bandit B311 (×3) | backend/main.py:15-16 | Cryptographic Failures (aviso genérico) | O ID final inclui `secrets.token_hex(16)` e serve só para identificar mensagens; não é segredo | Justificar no relatório | n/a | falso-positivo | Aceitar risco |
| C12 | Containers rodando como root (Dockerfiles sem `USER`) | Semgrep missing-user (×2) | backend/Dockerfile:7 (criado por nós); frontend/Dockerfile:24 | Security Misconfiguration (container) | Sim | `docker compose exec backend id` (e `frontend`) deve mostrar `uid=0(root)` antes da correção | Baixa | confirmado | Hardening |
| C13 | URL do backend fixa em HTTP no frontend | Semgrep react-insecure-request (×5) | frontend/src/api.ts:14, 160, 186, 304; frontend/src/components/UserChats/UserChats.tsx:25 | Security Misconfiguration / Cryptographic Failures (transporte) | Só se implantado como está (hoje é URL de desenvolvimento) | `grep -n "http://" frontend/src/api.ts` | Baixa | risco-latente | Recomendar |
| C14 | `assert` usado para validar entrada | Bandit B101 | backend/query_manager.py:44 | Qualidade de código | Baixo impacto: a falha cai no `try` da rota | Justificar no relatório | n/a | informativo | Aceitar risco |
| C15 | Erro 500 com corpo JSON `null` em `/users/create` (falta de validação de entrada) | Leitura manual | backend/endpoints.py (`data.get(...)` fora do `try` em `create_user` e `set_user_info`) | Insecure Design / Security Misconfiguration | Sim | `curl -i -X POST http://localhost:5000/users/create -H "Content-Type: application/json" -d 'null'` e esperar resposta 500 | Baixa | confirmado | Recomendar |
| C16 | Efeito colateral no import: `main.py` lê `config.json` e chama a OpenAI ao ser importado, derrubando o backend | Leitura manual | backend/main.py (final do arquivo), importado por backend/endpoints.py | Confiabilidade (SRE, fora do OWASP) | Sim, na inicialização | Subir o backend sem `config.json` e observar o erro na inicialização (`docker logs`); evidência em `docs/evidencias/c16/` | Baixa | informativo | Recomendar |
| C17a | Dependências do frontend com vulnerabilidades conhecidas (42 pacotes afetados: 2 críticos, 23 altos, 16 moderados, 1 baixo) | npm audit | frontend/package-lock.json | Vulnerable and Outdated Components | Parcial. A maior parte é toolchain de build/dev (vite, esbuild, rollup, postcss, sass, eslint). A cadeia do firebase (undici, protobufjs, grpc, websocket-driver) vem de módulos que o app não importa (só `firebase/app`, `auth` e `database`). O react-router-dom (open redirect/XSS) entra no bundle, mas o app só usa rotas fixas, sem `redirect` nem `Navigate` com dado do usuário | `npm audit --omit=dev` (só dependências de runtime); `npm ls protobufjs`; após o build, `grep -c "protobuf" dist/assets/*.js`; `grep -rn "Navigate\|redirect" frontend/src` | Média (as "críticas" do scanner não são críticas neste contexto) | confirmado (as falhas existem); impacto real a documentar | Recomendar |
| C17b | Imagem do frontend leva o toolchain de build para produção (Dockerfile de estágio único, `node_modules` completo e `serve` instalado globalmente na imagem final) | Leitura manual (Dockerfile) + npm audit | frontend/Dockerfile | Security Misconfiguration / Vulnerable Components | Sim: tudo que está em `node_modules` vai para a imagem final, mesmo sem ser executado | `docker run --rm cs-frontend du -sh /app/node_modules` e `docker images cs-frontend` (tamanho da imagem) | Baixa | confirmar | Recomendar |
| C17c | Dependências Python: nenhum CVE conhecido nas versões resolvidas em 22-23/10/2026, mas sem versões fixas (ver C07) | pip-audit | backend/requirements.txt | Vulnerable and Outdated Components | n/a | `cat docs/evidencias/scans/pip-audit.txt` (resultado: "No known vulnerabilities found") | n/a | informativo (resultado negativo registrado) | Recomendar |
| C18 | Controle de acesso nas rotas de chat e nos helpers genéricos do Firebase | Leitura manual (nenhum scanner cobre) | backend/endpoints.py (`/chats/<chat_id>/messages`, `/chats/<chat_id>`), backend/firebase.py (`create_document`, `get_document`) | Broken Access Control | A verificar (ler como `chat_id` e `document_id` são usados e se sempre ficam sob o `uid` do token) | Com dois usuários no emulador, tentar acessar ou apagar o chat de um usuário usando o token do outro | A definir | investigar | A definir |
| C19 | Enumeração de usuários em `POST /users/create` | Leitura manual | backend/endpoints.py (`create_user`), backend/firebase.py | Identification and Authentication Failures | Sim, sem autenticação: a 1ª criação devolve 200 com `user_id` e a 2ª, do mesmo e-mail, 400 `EMAIL_EXISTS`, o que revela se uma conta existe. Combinado com C06 (sem rate limit), permite enumerar contas em massa | Com o emulador, rodar duas vezes `curl -s -w "\n%{http_code}\n" -X POST http://localhost:5000/users/create -H "Content-Type: application/json" -d '{"email":"c19@teste.com","password":"Senha123"}'` e comparar o código e o corpo das duas respostas | Média | confirmado | Corrigir |
| C20 | `POST /users/query` não exige autenticação | Leitura manual | backend/endpoints.py (`get_user_query`, onde o erro de `try_get_user_info` é engolido e a rota segue) | Insecure Design / Authentication Failures | Sim, sem token, mas hoje sem impacto porque o `QueryManager` é um stub. Quando o LLM for integrado, vira abuso de custo | Chamar a rota sem o cabeçalho `Authorization` (corpo conforme `get_user_query`) e confirmar que ela responde mesmo assim | Baixa | risco-latente | Recomendar |

## Resumo das decisões

| Tipo | ID | Branch | Commit |
|------|----|--------|--------|
| Correção | C05 — credenciais do Reddit | `fix/security-c05-segredo-reddit` | `3574c3cb88150a89ca0245934c52fc06aae50d91` |
| Correção | C04 — token na query string | `fix/security-c04-token-no-header` | `9e67ca05059bfb2a7e5e3dd21505f00961f020e3` |
| Correção | C19 — enumeração de usuários | `fix/security-c19-enumeracao-usuarios` | `9fa3367df2ad7efc62ce65110b7ea76e20ed0956` |
| Hardening | C12 — containers sem root | `hardening/containers-sem-root` | `56d4016237d5ed11c4a117b949302ecc2dbd0a0a` |
| Hardening | C06 — rate limit e cabeçalhos no Nginx | `feat/nginx-balanceador-rate-limit` | `c959293377a3e7ac9048b8c51978315e4e7ee111` |
| Infra | Nginx com 2 réplicas do backend | `feat/nginx-balanceador-rate-limit` | `d0cedc661ef3603166d92775edca187daf10f73a` |

Achados confirmados com evidência própria: C01, C03, C04, C05, C06, C07, C12, C15, C17a, C19. Categorias cobertas: exposição de dados sensíveis, autenticação falha, configuração incorreta de segurança e dependências vulneráveis.

## Notas de triagem
- **C01 (resultado):** com `Origin: https://evil.example` a resposta ecoa a mesma origem em `Access-Control-Allow-Origin` e o preflight libera `authorization, content-type` e todos os métodos; não há `Access-Control-Allow-Credentials`. Qualquer site pode chamar a API pelo navegador, mas o token não vai em cookie, por isso Baixa. Evidência: `docs/evidencias/c01/`.
- **C03 (resultado):** `POST /users/info` com token inválido devolve o texto interno do SDK (`Wrong number of segments in token: b'x'`), o que expõe a biblioteca e o formato do erro. Evidência: `docs/evidencias/c03/`.
- **C15 (resultado):** corpo JSON `null` em `/users/create` devolve `500` com HTML genérico, porque `request.get_json()` retorna `None` e o `data.get(...)` está fora do `try`. Evidência: `docs/evidencias/c15/`.
- **C08 (SQL injection):** a ferramenta acerta o padrão, mas o código é inalcançável. Para o relatório, tratar como risco latente e usar como exemplo de correção por query parametrizada, sem contá-lo entre os achados principais.
- **C10 (Firebase apiKey):** chaves web do Firebase identificam o projeto e não são segredos; a proteção está nas regras de segurança do banco. O projeto é de terceiros e fora do escopo, então só se registra a justificativa.
- **C11 (random):** o aviso é válido em princípio, mas o identificador é composto também por `secrets.token_hex(16)` e não funciona como segredo.
- **C13:** a URL `127.0.0.1` é de desenvolvimento. O risco só existe se o frontend for implantado sem mudar a configuração, e o ponto de melhoria é parametrizar a URL base.
- `UserChats.tsx` chama `/theactualbackendlink`, uma rota inexistente: código inacabado, não vulnerabilidade.
- **C10:** o Gitleaks achou a mesma chave (mesma entropia) em dois lugares. No código atual ela só existe em `firebaseConfig.ts`; a ocorrência de `App.tsx` está apenas em commit antigo.
- **C16:** rebaixado para informativo. Ao subir o container sem `credentials.json`, a falha acontece em `firebase.py`, e isso é esperado em qualquer app que exige credenciais (ver `docs/evidencias/c16/cenario-A.txt`). O defeito próprio do `main.py` (ler `config.json` e chamar a OpenAI no import) é de confiabilidade e será tratado na branch de ambiente com a guarda `if __name__ == "__main__"`, sem contar como correção de segurança.
- **C17a:** o `npm audit` conta pacotes afetados, não falhas independentes. Cerca de 11 das 42 entradas vêm de um único pacote raiz (`firebase`), e a severidade que ele mostra é a da biblioteca em geral, não a deste uso. O pacote `uuid` aparece no `package.json`, mas não é usado no código.
- **C17c:** como o `requirements.txt` não fixa versões, o `pip-audit` verificou as versões mais recentes de hoje, não as que os autores usavam em 2024. O resultado é válido para esta data. O `main.py` também importa `numpy` sem declará-lo (ele chega via `pandas`).
- **C03 (situação após as correções):** a rota `/users/create` deixou de repassar o texto interno do SDK (correção do C19); as demais rotas ainda devolvem `str(e)`.
- **Política de senha (C06/C19):** uma senha de 1 caractere é recusada com `400` (ver `docs/evidencias/c19/depois-resposta-uniforme.txt`), então a política de tamanho é imposta pelo SDK do Firebase e não é uma falha do backend.
- **C02:** ainda não reproduzido; exige subir o backend com `python endpoints.py` (o container usa `flask run`, sem debug).
- **Status x Decisão:** "confirmado" só é marcado depois de eu reproduzir o achado e guardar a evidência em `docs/evidencias/<id>/`. A decisão (corrigir, hardening, recomendar) é independente do status.

## Blocos de notas por achado

### C04 — Token de autenticação na query string
- **Causa raiz:** o token é verificado corretamente pelo SDK do Firebase, mas a rota `GET /users/info` o recebe pela query string (`request.args.get("id_token")`), e o `POST` pelo corpo, em vez do cabeçalho `Authorization`. O frontend (`api.ts`) também envia o token na URL. URLs são registradas em logs de acesso, proxies e histórico, e cabeçalhos de autorização normalmente não são.
- **Impacto:** Média. Quem tiver acesso a esses registros obtém um bearer token e age como o usuário enquanto ele for válido (cerca de 1 h para ID tokens do Firebase, o que limita a janela). Reproduzido: o log de acesso do backend guarda a URL completa com o token. Proxies, histórico do navegador e `Referer` são riscos do mesmo padrão, mas não foram testados aqui.
- **Evidência:**
  - Antes: `docs/evidencias/c04/token-no-log.txt` (requisição `GET /users/info?id_token=...` com status 200 e a linha correspondente no log, com o token truncado)
  - Depois: `docs/evidencias/c04/depois-header.txt` (cabeçalho: 200 e log sem token; query string: 401)
- **Correção implementada:** o backend lê o token do cabeçalho `Authorization: Bearer` em `GET /users/info` e recusa com 401 se ele faltar; o token na query string é ignorado. O frontend (`api.ts`) envia o cabeçalho em vez de montar a URL. `POST /users/info` e `POST /users/query` continuam recebendo o token no corpo, que não aparece em logs de acesso; padronizar tudo no cabeçalho fica como recomendação.
- **Implementada:** sim, commit `9e67ca05059bfb2a7e5e3dd21505f00961f020e3`

### C05 — Credenciais do Reddit versionadas
- **Causa raiz:** o arquivo `reddit_key.json`, com `client_id` e `client_secret` da API do Reddit, foi commitado no repositório (histórico a partir do `c979a1e`, 2024-07-16) e nada o impediu: o `.gitignore` cobre `*config.json` e `secrets/`, mas não esse nome de arquivo; o código só sabia ler o segredo de um arquivo dentro do repositório; e não há varredura de segredos antes do commit.
- **Impacto:** Média. Quem clonar o repositório lê as credenciais com `git show` em qualquer commit (o `git log` só lista os commits, quem mostra o conteúdo é o `git show`). Elas dão acesso à API do Reddit em nome da aplicação de terceiros, e não foi possível saber se ainda são válidas (não testamos credenciais de terceiros). Apagar o arquivo não resolve, porque o valor continua em todos os commits antigos.
- **Evidência:**
  - Antes: `docs/evidencias/c05/historico-e-presenca.txt` (commit de origem, presença na tag e na `main`, campos de 22 e 30 caracteres, sem expor valores) e `docs/evidencias/scans/gitleaks.json`
  - Depois: `docs/evidencias/c05/depois.txt` (arquivo fora do código atual, Gitleaks sem achado no diretório) e `docs/evidencias/c05/depois-carregamento.txt` (erro claro sem credenciais; funciona com variáveis de ambiente)
- **Correção implementada:** o arquivo foi removido do código atual e `reddit_key.json` e `.env` entraram no `.gitignore`; `RedditCrawler` lê `REDDIT_CLIENT_ID` e `REDDIT_CLIENT_SECRET` do ambiente, com fallback para um arquivo local não versionado; `reddit_key.example.json` documenta o formato. Isso impede novos vazamentos pela mesma via, mas o valor continua no histórico e a credencial precisa ser revogada pelo dono do projeto (não temos como fazê-lo). A reescrita do histórico não foi feita: o histórico é do projeto original e a tag `v0-original` é a base das comparações.
- **Recomendação adicional:** notificar o mantenedor para revogar e gerar novas credenciais; adicionar varredura de segredos (Gitleaks) no CI.
- **Implementada:** sim, commit `3574c3cb88150a89ca0245934c52fc06aae50d91`

### C19 — Enumeração de usuários em `POST /users/create`
- **Causa raiz:** a rota devolve respostas distintas para "conta criada" (200 com `user_id`) e "e-mail já existe" (400 com `EMAIL_EXISTS`), e repassa ao cliente a mensagem de erro do SDK do Firebase. Não há autenticação, nem limite de taxa, nem resposta uniforme.
- **Impacto:** Média. Qualquer pessoa descobre se um e-mail tem conta, sem login. Combinado com a ausência de rate limit (C06), permite varrer listas de e-mails em massa, o que facilita phishing e ataques de credenciais direcionados. Cada sondagem de e-mail novo ainda cria uma conta.
- **Evidência:**
  - Antes: `docs/evidencias/c19/duas-criacoes-mesmo-email.txt` (mesmo e-mail enviado duas vezes: 200 com `user_id`, depois 400 `EMAIL_EXISTS`)
  - Depois: `docs/evidencias/c19/depois-resposta-uniforme.txt` (as duas criações devolvem 200 com o mesmo corpo; senha fraca devolve 400 genérico; a conta criada faz login)
- **Correção implementada:** e-mail novo e e-mail já existente passam a devolver a mesma resposta (200, corpo genérico, sem `user_id`); erros de dados inválidos devolvem 400 genérico, e o erro real vai para o log do servidor. O frontend não usa os campos removidos.
- **Limitações:** o tempo de resposta pode diferir entre os dois casos (canal de tempo residual); uniformidade total de cadastro exigiria confirmação por e-mail, que não existe aqui; o rate limit do C06 reduz a escala da sondagem.
- **Implementada:** sim, commit `9fa3367df2ad7efc62ce65110b7ea76e20ed0956`

### C06 — Sem rate limiting em `/users/create`
- **Causa raiz:** nenhuma rota do backend limita a quantidade de requisições por origem; a aplicação não usa nenhum mecanismo de limite (nem no app nem em um proxy).
- **Impacto:** Média. Permite automatizar cadastros em massa e, combinado com o C19, enumerar contas sem restrição. Também permite consumo abusivo de recursos e cota do Firebase.
- **Evidência:**
  - Antes: `docs/evidencias/c06/50-criacoes-sem-limite.txt` (50 cadastros seguidos, todos com status 200). Teste feito contra o emulador; no Firebase real há cotas próprias, mas o backend não impõe limite algum.
  - Depois: `docs/evidencias/c06/depois-rate-limit.txt` (50 cadastros seguidos pelo Nginx: 4 com 200 e 46 com 429; cabeçalhos de segurança presentes e versão do Nginx oculta)
- **Melhoria implementada (hardening):** `limit_req` no Nginx, 5 requisições por minuto por IP em `/users/create` (com folga de 3) e 20 por segundo nas demais rotas, respondendo `429`. O limite fica no balanceador, e não no Flask, para o contador valer para as 2 réplicas juntas. Foram acrescentados os cabeçalhos `X-Content-Type-Options`, `X-Frame-Options` e `Referrer-Policy`, e `server_tokens off`.
- **Limitação:** o Nginx limita pelo IP que enxerga; atrás de outro proxy seria preciso configurar o IP real via `X-Forwarded-For`.
- **Implementada:** sim, commit `c959293377a3e7ac9048b8c51978315e4e7ee111`

### C12 — Containers rodando como root
- **Causa raiz:** os Dockerfiles do backend e do frontend não definem `USER`, então os processos rodam como `root` (uid 0) dentro do container.
- **Impacto:** Baixa. Não é uma vulnerabilidade explorável por si só, mas, se a aplicação for comprometida por outra falha, o atacante ganha privilégios de root no container, o que facilita alterar arquivos da imagem, escrever em volumes montados e tentar escapar do container. Pod Security Standards "restricted" do Kubernetes recusam imagens que rodam como root.
- **Evidência:**
  - Antes: `docs/evidencias/c12/antes-root.txt` (`uid=0(root)` nos dois serviços)
  - Depois: `docs/evidencias/c12/depois-sem-root.txt` (`uid=10001(app)` no backend e `uid=1000(node)` no frontend; os dois continuam respondendo)
- **Melhoria implementada (hardening):** o backend cria o usuário `app` (uid 10001), dono de `/app` para o entrypoint poder gerar as credenciais de teste, e executa com `USER app`; o frontend executa com `USER node`.
- **Próximos passos recomendados:** sistema de arquivos somente leitura (`read_only: true`), `cap_drop: [ALL]` e `no-new-privileges`.
- **Implementada:** sim, commit `80ad3e8a41294e27475021ff51ba8e2989b59eb2`

### C07 — Dependências sem versão fixa
- **Causa raiz:** requirements.txt só com nomes, sem arquivo de lock.
- **Impacto:** uma build gerada em uma data antiga pode quebrar quando for gerada novamente depois, porque as versões resolvidas mudam com o tempo.
- **Evidência:** `docs/evidencias/c07/`
  - `resolvido-2024-07-16.txt`: versões que o pip resolveria em 16/07/2024 (`uv pip compile --exclude-newer`)
  - `resolvido-hoje.txt`: versões resolvidas hoje, a partir do mesmo `requirements.txt`
  - `instalado-sem-cache.txt`: `pip freeze` da imagem construída sem cache
- **Correção recomendada:** gerar um arquivo de lock com as versões exatas (e hashes) de todas as dependências, diretas e transitivas, a partir do requirements.txt (uv pip compile --generate-hashes), versioná-lo no repositório e fazer o Dockerfile do backend instalar a partir dele (pip install --require-hashes -r requirements.lock)
- **Implementada:** não (recomendação no relatório)