# Relatório Técnico: Segurança e Confiabilidade do CourseSphere

**Autor:** Pedro Henrique Boa Hora da Silva
**Data:** 28/10/2026
**Repositório:** https://github.com/boahorapedro/coursesphere-appsec
**Base analisada:** tag `v0-original` (código recebido); ambiente executável em `v0-executavel`

---

## 1. Resumo executivo

O CourseSphere é uma aplicação web que ajuda estudantes a escolher disciplinas: frontend em React, backend em Flask e autenticação e banco no Firebase. Foi feita uma avaliação de segurança e confiabilidade do código recebido, seguida de correções, melhorias de proteção e uma camada de observabilidade.

**O que foi encontrado.** Foram triados 22 candidatos a achado (ferramentas automáticas e leitura do código). Onze foram **reproduzidos** em um ambiente isolado, com evidência; os demais são riscos latentes (existem no código, mas hoje não são exploráveis), falsos positivos ou informativos, cada um com justificativa. Nenhum achado atinge severidade **Alta**: a aplicação delega a autenticação ao Firebase e o código vulnerável mais grave (injeção de SQL) é inalcançável hoje. Os problemas mais relevantes para o negócio são:

| Prioridade | Problema | Por que importa |
|---|---|---|
| 1 | Credenciais da API do Reddit versionadas no repositório (C05) | qualquer pessoa que clone o repositório as lê, e continuam no histórico |
| 2 | Token de autenticação trafegando na URL e gravado em logs (C04) | quem lê o log se passa pelo usuário enquanto o token for válido |
| 3 | Cadastro revela quais e-mails têm conta, sem limite de tentativas (C19 e C06) | permite varrer contas em massa e facilita phishing |
| 4 | Dependências sem versão fixa (C07) | a mesma build pode quebrar ou mudar de comportamento com o tempo |

**O que foi feito.**
- **3 correções** de segurança (C05, C04, C19), cada uma com prova de antes e depois.
- **2 melhorias de proteção** que não faziam parte do código original (C12 containers sem root e C06 limite de taxa com cabeçalhos de segurança), além de outras decisões defensivas (backend sem porta pública, métricas internas, logs sem tokens).
- **Confiabilidade:** logs em JSON, endpoints `/health` e `/metrics`, 2 SLIs com SLOs, dashboard funcional (Prometheus e Grafana), e balanceamento com Nginx sobre 2 réplicas, com teste de queda de uma réplica.
- **Automação:** um pipeline de CI que impede a volta de segredos no código e executa 19 verificações de regressão das correções.

**O que fica para depois** (recomendações priorizadas na seção 9): revogar as credenciais do Reddit (só o dono pode), fixar as dependências com hashes, restringir o CORS e padronizar os erros da API.

---

## 2. Escopo e metodologia

### 2.1 Escopo
- **Dentro do escopo:** o código do repositório recebido (backend Flask, frontend React/Vite, Dockerfiles), na tag `v0-original`.
- **Fora do escopo:** o projeto Firebase de produção (pertence a terceiros, e o código tem a URL dele fixa), a API da OpenAI e qualquer infraestrutura implantada.
- **Regra de conduta:** todos os testes dinâmicos rodaram **apenas em ambiente local**, contra o emulador do Firebase. O backend se recusa a iniciar sem as variáveis do emulador (trava em `backend/entrypoint.sh`), então nenhum teste alcança o projeto real. Nenhum valor de segredo é reproduzido neste relatório.

### 2.2 Arquitetura

```
 navegador ──► Nginx (porta 5000) ──► backend-1 ┐
                (balanceador,                    ├──► Firebase Emulator (Auth + Realtime DB)
                 rate limit,        backend-2 ┘
                 cabeçalhos)             │  /metrics (rede interna)
                                          ▼
                                     Prometheus ──► Grafana
 navegador ──► frontend (porta 3000)
```

### 2.3 Método
1. **Varreduras automáticas:** Semgrep e Bandit (SAST), pip-audit e npm audit (SCA) e Gitleaks (segredos). As saídas brutas estão em `docs/evidencias/scans/`.
2. **Leitura manual do código**, em busca do que as ferramentas não cobrem (autenticação, erros, controle de acesso).
3. **Triagem:** cada candidato recebeu um ID (C01 a C20, com C17a, C17b e C17c), local, categoria, alcançabilidade, severidade preliminar, status e decisão (`docs/candidate-findings.md`).
4. **Validação dinâmica:** cada achado marcado como `confirmado` foi reproduzido em um ambiente isolado (Docker e emulador), com a evidência guardada em `docs/evidencias/<id>/`.
5. **Correção e hardening**, cada um em sua branch, com evidência de antes e depois.
6. **Confiabilidade:** observabilidade, SLIs e SLOs, e balanceamento.

### 2.4 Critérios
**Severidade (Alta, Média, Baixa):** combina a probabilidade de exploração com o impacto no negócio, e considera se o código é alcançável hoje. Foi usada a escala qualitativa, e não o CVSS, porque vários achados dependem do contexto (por exemplo, o CORS aberto é pouco grave porque o token não vai em cookie).

**Status:** `confirmado` (reproduzido, com evidência), `risco-latente` (existe no código, hoje não explorável), `falso-positivo`, `informativo`, `confirmar` (identificado, ainda não reproduzido), `não-vulnerável`, `investigar`.

### 2.5 Ambiente de teste e limitações
O ambiente sobe com `docker compose up --build` (emulador do Firebase, 2 réplicas do backend, Nginx, Prometheus, Grafana e frontend). Limitações a considerar ao ler os resultados:
- O emulador emite tokens sem assinatura criptográfica real; a lógica de autorização do backend é a mesma da produção, mas a verificação de assinatura não foi exercitada.
- As regras do banco no emulador são abertas de propósito: os testes avaliam o código do backend, e não a configuração do Firebase real.
- Os testes de carga (C06) foram contra o emulador; no Firebase real há cotas próprias, mas o backend não impõe limite algum.

---

## 3. Resumo dos achados

| ID | Título | Categoria | Sev. | Status | Decisão |
|----|--------|-----------|------|--------|---------|
| C05 | Credenciais do Reddit versionadas | Exposição de dados sensíveis | Média | confirmado | **Corrigido** |
| C04 | Token de autenticação na query string | Autenticação / exposição de dados | Média | confirmado | **Corrigido** |
| C19 | Enumeração de usuários no cadastro | Autenticação | Média | confirmado | **Corrigido** |
| C06 | Sem limite de taxa (rate limiting) | Autenticação / configuração | Média | confirmado | **Hardening** |
| C12 | Containers executando como root | Configuração (container) | Baixa | confirmado | **Hardening** |
| C07 | Dependências Python sem versão fixa | Componentes vulneráveis / integridade | Baixa | confirmado | Recomendado |
| C17a | Dependências do frontend com CVEs | Componentes vulneráveis | Média  | confirmado | Recomendado |
| C01 | CORS aberto para qualquer origem | Configuração incorreta | Baixa | confirmado | Recomendado |
| C03 | Mensagens internas de erro devolvidas ao cliente | Configuração / exposição de dados | Baixa | confirmado | Recomendado |
| C15 | Erro 500 com corpo JSON `null` | Validação de entrada | Baixa | confirmado | Recomendado |
| C02 | Flask com `debug=True` | Configuração incorreta | Média | confirmar | Recomendado |
| C08 | SQL montado com f-string | Injeção | Média | risco latente | Recomendado |
| C09 | Entrada do usuário no prompt do LLM | Injeção (LLM) | Baixa | risco latente | Recomendado |
| C13 | URL do backend fixa em HTTP | Configuração / transporte | Baixa | risco latente | Recomendado |
| C20 | `/users/query` sem autenticação | Autenticação / design | Baixa | risco latente | Recomendado |
| C16 | Efeito colateral no import (`main.py`) | Confiabilidade | Baixa | informativo | Recomendado |
| C17b | Imagem do frontend leva o toolchain de build | Configuração (container) | Baixa | confirmado | Recomendado |
| C10 | Chave web do Firebase no frontend | Exposição de dados | n/a | falso positivo | Aceito |
| C11 | Uso de `random` em `hashFunction` | Criptografia | n/a | falso positivo | Aceito |
| C14 | `assert` para validar entrada | Qualidade de código | n/a | informativo | Aceito |
| C17c | pip-audit sem CVEs conhecidos | Componentes vulneráveis | n/a | informativo | n/a |
| C18 | Controle de acesso nas rotas de chat | Controle de acesso | n/a | não-vulnerável (testado) | Aceito |

**Categorias com achados reproduzidos:** exposição de dados sensíveis, autenticação falha, configuração incorreta de segurança e dependências vulneráveis.

---

## 4. Achados confirmados (descrição, reprodução e impacto)

   **Como reproduzir.** Os comandos de C04, C05, C06, C12 e C19 mostram o estado **anterior às correções**. Para vê-los falhar, use a tag vulnerável: `git checkout v0-executavel` e `docker compose up --build -d` (nela o backend fica direto na porta 5000). Na `main`, os mesmos comandos mostram o comportamento já corrigido (C04 `401`, C19 respostas idênticas, C06 `429`), e é isso que o `scripts/smoke-test.sh` verifica. Os demais (C01, C03, C07, C15, C17 e C18) valem nas duas versões. Todos os comandos supõem o backend em `http://localhost:5000`.

### 4.1 C05: Credenciais do Reddit versionadas (Média)
- **Descrição:** o arquivo `backend/cornell-course-sphere-data/reddit-data/reddit_key.json` contém `client_id` e `client_secret` da API do Reddit e está versionado desde o commit `c979a1e` (2024-07-16).
- **Causa raiz:** o `.gitignore` cobre `*config.json` e `secrets/`, mas não esse nome; o código só lê o segredo de um arquivo dentro do repositório; não há varredura de segredos antes do commit.
- **Reprodução (sem imprimir o valor):**
  ```bash
  git log --all --format='%h %ad %s' --date=short -- backend/cornell-course-sphere-data/reddit-data/reddit_key.json
  git cat-file -e v0-original:backend/cornell-course-sphere-data/reddit-data/reddit_key.json; echo "exit=$?"
  ```
  O arquivo existe na tag `v0-original`, com os campos `client_id` (22 caracteres) e `client_secret` (30 caracteres). O Gitleaks também o sinalizou.
- **Impacto no negócio:** quem clonar o repositório lê as credenciais com `git show`. Elas dão acesso à API do Reddit em nome da aplicação de terceiros. Não se sabe se ainda são válidas, e não foram testadas. Apagar o arquivo não resolve, porque o valor permanece no histórico.
- **Evidência:** `docs/evidencias/c05/` e `docs/evidencias/scans/gitleaks.json`.

### 4.2 C04: Token de autenticação na query string (Média)
- **Descrição:** `GET /users/info` lê o token de `request.args.get("id_token")`, e o frontend (`api.ts`) também o envia na URL. O servidor registra a URL completa em seu log de acesso.
- **Causa raiz:** o token é verificado corretamente, mas trafega por um canal que é registrado por padrão (URLs aparecem em logs de servidor, proxies e histórico), ao contrário do cabeçalho `Authorization`.
- **Reprodução:**
  ```bash
  TOKEN=$(curl -s -X POST "http://localhost:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake" \
    -H "Content-Type: application/json" \
    -d '{"email":"c04@teste.com","password":"Senha123","returnSecureToken":true}' \
    | python -c "import sys,json; print(json.load(sys.stdin)['idToken'])")
  curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:5000/users/info?id_token=$TOKEN"
  docker compose logs backend | grep "users/info?id_token"
  ```
  A resposta é `200` e o log do backend contém a URL com o token (na evidência, truncado).
- **Impacto no negócio:** quem tiver acesso ao log obtém um bearer token e age como o usuário enquanto ele for válido (cerca de 1 hora para ID tokens do Firebase, o que limita a janela). Proxies, histórico do navegador e `Referer` seguem o mesmo padrão de risco, mas não foram testados.
- **Evidência:** `docs/evidencias/c04/`.

### 4.3 C19: Enumeração de usuários em `POST /users/create` (Média)
- **Descrição:** a primeira criação de um e-mail devolve `200` com `user_id`; a segunda, do mesmo e-mail, devolve `400` com `EMAIL_EXISTS`. Qualquer pessoa, sem login, descobre se uma conta existe.
- **Reprodução:**
  ```bash
  for i in 1 2; do
    curl -s -w "\nstatus: %{http_code}\n" -X POST http://localhost:5000/users/create \
      -H "Content-Type: application/json" -d '{"email":"c19@teste.com","password":"Senha123"}'
  done
  ```
- **Impacto no negócio:** combinada com a ausência de limite de taxa (C06), permite varrer listas de e-mails em massa, o que facilita phishing e ataques direcionados. Cada sondagem de e-mail novo ainda cria uma conta.
- **Evidência:** `docs/evidencias/c19/`.

### 4.4 C06: Sem limite de taxa (Média)
- **Descrição:** nenhuma rota limita a quantidade de requisições por origem.
- **Reprodução:** 50 cadastros seguidos em `/users/create` devolvem todos `200`.
  ```bash
  for i in $(seq 1 50); do curl -s -o /dev/null -w "%{http_code}\n" -X POST http://localhost:5000/users/create \
    -H "Content-Type: application/json" -d "{\"email\":\"t$i@teste.com\",\"password\":\"Senha123\"}"; done | sort | uniq -c
  ```
- **Impacto no negócio:** cadastro em massa, consumo de recursos e de cota do Firebase, e amplificação do C19.
- **Nota:** a política de senha é imposta pelo SDK do Firebase (uma senha de 1 caractere é recusada), então não é uma falha do backend.
- **Evidência:** `docs/evidencias/c06/`.

### 4.5 C12: Containers executando como root (Baixa)
- **Descrição:** os Dockerfiles do backend e do frontend não definem `USER`.
- **Reprodução:** `docker compose exec backend id` e `docker compose exec frontend id` mostravam `uid=0(root)`.
- **Impacto no negócio:** não é explorável sozinho, mas, se outra falha for explorada, o atacante ganha privilégios de root no container, o que facilita alterar a imagem, escrever em volumes montados e tentar escapar do container. Políticas de cluster (Pod Security `restricted`) recusam imagens que rodam como root.
- **Evidência:** `docs/evidencias/c12/`.

### 4.6 C07: Dependências Python sem versão fixa (Baixa)
- **Descrição:** `backend/requirements.txt` lista só nomes, sem versões nem arquivo de lock.
- **Reprodução:** a resolução de 16/07/2024 (`uv pip compile requirements.txt --exclude-newer 2024-07-16T00:00:00Z`) e a de hoje, a partir do mesmo requirements.txt original, diferem em 47 dos 59 pacotes originais (10 foram removidos e 9 são novos). 11 tiveram troca de versão maior, por exemplo openai 1.35.13 → 3.37.0, pandas 2.2.2 → 3.1.0. O pip freeze de uma imagem construída sem cache coincide com a resolução de hoje (`docs/evidencias/c07/`)
- **Impacto no negócio:** uma build gerada em outra data pode quebrar ou mudar de comportamento, e uma versão comprometida pode entrar sem ser notada.
- **Evidência:** `docs/evidencias/c07/`.

### 4.7 C17a: Dependências do frontend com vulnerabilidades conhecidas (Média)
- **Descrição:** o `npm audit` completo aponta 42 pacotes afetados (2 críticos, 23 altos, 16 moderados, 1 baixo). Restrito às dependências de runtime (`--omit=dev`), são 24 (2 críticos, 9 altos, 13 moderados); os outros 18 são só de ferramentas de build e desenvolvimento (`docs/evidencias/c17/npm-audit-runtime.txt`).
- **Análise de impacto:** O `npm audit` conta pacotes afetados, não falhas independentes. O app importa apenas `firebase/app`, `firebase/auth` e `firebase/database` (`docs/evidencias/c17/imports-firebase-e-router.txt`). O `protobufjs` (crítico) pertence ao Firestore, e uma busca por URLs de Firestore, Storage e Functions no bundle não encontrou nenhuma, com o Auth como controle positivo (`docs/evidencias/c17/imagem-e-bundle.txt`); logo, não deve estar no bundle. A presença de `websocket-driver` (crítico) e `undici` no bundle não foi verificada. O `react-router-dom` é importado e está no bundle (`BrowserRouter`, `Route`, `Routes`); o aviso de open redirect só se materializa se o app redirecionar com dado do usuário, e a busca por Navigate e redirect não encontrou usos (`docs/evidencias/c17/uso-de-redirect.txt`).
- **Impacto no negócio:** Há 24 vulnerabilidades em dependências de runtime. A evidência indica que os caminhos vulneráveis conhecidos não são exercitados pelo código do app, mas a superfície existe e cresce com o tempo.
- **Evidência:** `docs/evidencias/c17/`.

### 4.8 C01: CORS aberto (Baixa)
- **Descrição:** `CORS(app)` (em `backend/endpoints.py`) aceita qualquer origem.
- **Reprodução:** `curl -i -H "Origin: https://evil.example" http://localhost:5000/users/info`: a resposta ecoa a origem em `Access-Control-Allow-Origin`, e o preflight libera `authorization`, `content-type` e todos os métodos. Não há `Access-Control-Allow-Credentials`.
- **Impacto no negócio:** qualquer site pode chamar a API pelo navegador do visitante. A gravidade é baixa porque a autenticação é por cabeçalho e não por cookie, então um site malicioso não tem o token do usuário; mas libera abuso das rotas não autenticadas.
- **Evidência:** `docs/evidencias/c01/`.

### 4.9 C03: Mensagens internas de erro devolvidas ao cliente (Baixa)
- **Descrição:** várias rotas devolvem `str(e)`. Com um token inválido, a resposta traz o texto do SDK (`Error verifying ID token: Wrong number of segments in token: b'x'`).
- **Segunda ocorrência:** `DELETE /chats/<id>` sem o cabeçalho `Authorization` devolve 400 com `Error deleting message: 'NoneType' object has no attribute 'split'`. A falta de token vira um erro interno vazado, em vez de um 401.
- **Impacto no negócio:** revela a biblioteca e o formato interno dos erros, o que ajuda quem mapeia o sistema. A rota `/users/create` já foi ajustada junto com o C19; as demais seguem iguais.
- **Evidência:** `docs/evidencias/c03/` e `docs/evidencias/c18/`.

### 4.10 C15: Erro 500 com corpo JSON `null` (Baixa)
- **Descrição:** `request.get_json()` devolve `None` para o corpo `null`, e `data.get(...)` fica fora do `try`, gerando uma exceção não tratada.
- **Reprodução:** `curl -i -X POST http://localhost:5000/users/create -H "Content-Type: application/json" -d 'null'`: resposta `500` com HTML genérico.
- **Impacto no negócio:** erro de disponibilidade por entrada malformada, e, se o `debug=True` (C02) estiver ativo, exposição do depurador.
- **Evidência:** `docs/evidencias/c15/`.

### 4.11 C17b: Imagem do frontend leva o toolchain de build (Baixa)
- **Descrição:** o Dockerfile do frontend tem um único estágio: a imagem final leva o `node_modules` completo (ferramentas de build e desenvolvimento incluídas) e o `serve` instalado globalmente.
- **Reprodução:**
  ```bash
  docker compose exec -T frontend du -sh node_modules
  ```
  O resultado é 463,4 MB dentro da imagem final.
- **Impacto no negócio:** a imagem carrega muito mais código do que precisa para servir arquivos estáticos. Isso aumenta a superfície de CVEs (18 das 42 entradas do `npm audit` são só de ferramentas de desenvolvimento) e deixa a imagem pesada, o que atrasa builds e downloads. Não há exploração direta, por isso a severidade é Baixa.
- **Evidência:** `docs/evidencias/c17/imagem-e-bundle.txt`.

---

## 5. Riscos latentes, falsos positivos e cobertura

### 5.1 Identificado, não reproduzido ou latente
- **C02, `debug=True`:** em `endpoints.py`, linha final (`app.run(debug=True)`). O container usa `flask run` (sem debug), então só se aplica a quem executar `python endpoints.py`. Identificado pelo Bandit (B201) e pelo Semgrep; **não foi reproduzido dinamicamente**. Se exposto fora do localhost, daria acesso ao console interativo do Werkzeug (protegido por PIN), o que o tornaria grave.
- **C08, SQL por f-string:** 6 consultas em `blueprints/courses.py`, mas o blueprint está comentado, nunca é importado, e o banco SQLite está ausente. Das 6, três recebem `<int:...>` (não injetáveis) e três recebem `<string:...>`. Serve de exemplo de correção por consulta parametrizada.
- **C09, injeção no prompt do LLM:** a consulta do usuário vai direto para o prompt, mas o `QueryManager` é um stub (as chamadas à OpenAI estão comentadas). Passa a valer quando o LLM for integrado. Verificado: o cliente da OpenAI está comentado e a função devolve o texto fixo Fake implementation (docs/evidencias/c09/stub-sem-llm.txt).
- **C13, URL em HTTP:** `http://127.0.0.1:5000` fixo no frontend; é URL de desenvolvimento e só é risco se for implantada assim.
- **C20, `/users/query` sem autenticação:** o erro de `try_get_user_info` é engolido e a rota segue. Hoje sem impacto (stub); com o LLM integrado vira abuso de custo.Reproduzido: sem Authorization, a rota responde 200 com o texto fixo (`docs/evidencias/c20/sem-token.txt`).
- **C16, efeito colateral no import:** `main.py` lia `config.json` e chamava a OpenAI ao ser importado. É um problema de confiabilidade, e não de segurança. Foi resolvido na branch de ambiente, com a guarda `if __name__ == "__main__"`.

### 5.2 Falsos positivos e informativos
- **C10:** a chave web do Firebase no frontend é pública por desenho; a proteção real está nas regras do banco, que estão fora do escopo.
- **C11:** `random` em `hashFunction`; o ID final inclui `secrets.token_hex(16)` e só identifica mensagens, não protege segredo.
- **C14:** `assert` em `query_manager.py`; baixo impacto, a falha cai no `try` da rota.
- **C17c:** o `pip-audit` não encontrou vulnerabilidades conhecidas nas versões resolvidas em 22 e 23/10/2026 (válido para essa data, já que as versões não são fixas).
- **Firebase apiKey no frontend** (alerta do GitHub Secret Scanning). O alerta aponta frontend/src/App.tsx e firebaseConfig.ts (commit do upstream, jul/2024). Trata-se da chave pública do SDK web do Firebase, que identifica o projeto e não concede acesso por si só; a proteção real está nas regras do banco e na autenticação. Classificado como falso positivo/informativo. Diferente das credenciais do Reddit (C05), que são segredos de servidor.

### 5.3 Cobertura das demais categorias
- **Controle de acesso quebrado (C18):** testado dinamicamente com duas contas no emulador. O usuário B tentou apagar e sobrescrever um chat do usuário A usando o mesmo `chat_id`; as duas operações atingiram apenas o ramo do próprio B, e os dados do A permaneceram intactos (`docs/evidencias/c18/isolamento-entre-usuarios.txt`). Isso ocorre porque o caminho no banco é montado com o uid extraído do token verificado, e não com um valor enviado pelo cliente. Limite do teste: cobre as rotas de chat do backend (`POST /chats/<id>/messages e DELETE /chats/<id>`); a leitura de dados diretamente pelo SDK do Firebase no frontend depende das regras do banco, que estão fora do escopo.
- **XSS:** Busca no código do frontend pelos padrões que contornam a proteção do React (dangerouslySetInnerHTML, innerHTML, document.write, eval) não encontrou ocorrências (docs/evidencias/xss/busca-padroes-xss.txt). O React escapa o conteúdo por padrão. Não foi feito teste dinâmico com payloads de XSS; esta conclusão se baseia na leitura do código.
- **Injeção:** só o C08 (latente).

---

## 6. Correções implementadas

Cada correção foi feita em sua própria branch, com um commit cujo corpo explica a causa raiz e por que a correção resolve. A verificação é sempre "antes e depois".

### 6.1 C05: credenciais do Reddit (commit `70b9307`)
- **Causa raiz:** ver 4.1.
- **Correção:** o arquivo foi removido do código atual; `reddit_key.json` e `.env` entraram no `.gitignore`; o `RedditCrawler` lê `REDDIT_CLIENT_ID` e `REDDIT_CLIENT_SECRET` do ambiente, com alternativa de um arquivo local não versionado; `reddit_key.example.json` documenta o formato.
- **Por que resolve:** impede novos vazamentos pela mesma via. **Limitação:** o valor continua no histórico, e a credencial precisa ser revogada pelo dono do projeto (não temos acesso para isso). O histórico não foi reescrito, porque pertence ao projeto original e a tag `v0-original` é a base das comparações.
- **Verificação:** depois da correção, o arquivo não está versionado e o Gitleaks não acusa o segredo; sem credenciais, o código falha com erro claro; com variáveis de ambiente, funciona (`docs/evidencias/c05/`).

### 6.2 C04: token no cabeçalho (commit `5da47ad`)
- **Causa raiz:** ver 4.2.
- **Correção:** `GET /users/info` lê o token do cabeçalho `Authorization: Bearer` e responde `401` se faltar; o token na query string é ignorado. O frontend envia o cabeçalho.
- **Por que resolve:** o caminho inseguro deixa de existir no servidor, e não apenas é desencorajado.
- **Verificação:** com o cabeçalho, `200` e a linha de log sem token; com o token na URL, `401` (`docs/evidencias/c04/`). Os `POST /users/info` e `POST /users/query` seguem recebendo o token no corpo, que não aparece nos logs de acesso; padronizar tudo no cabeçalho fica como recomendação.

### 6.3 C19: resposta uniforme no cadastro (commit `852bd37`)
- **Causa raiz:** ver 4.3.
- **Correção:** e-mail novo e e-mail já existente devolvem a mesma resposta (`200`, corpo genérico, sem `user_id`); entradas inválidas devolvem `400` genérico; o erro real vai para o log do servidor.
- **Por que resolve:** elimina a diferença observável que revelava a existência da conta.
- **Verificação:** os dois cadastros do mesmo e-mail devolvem respostas idênticas, a senha fraca devolve `400` genérico e a conta criada faz login (`docs/evidencias/c19/`).
- **Limitações:** o tempo de resposta pode diferir entre os casos (canal de tempo residual), e uniformidade total exigiria confirmação por e-mail, que não existe aqui. O limite de taxa (C06) reduz a escala.

---

## 7. Melhorias de proteção (hardening)

### 7.1 Containers sem root (C12; commit `56d4016`)
O backend roda como o usuário `app` (uid 10001), dono de `/app` para o entrypoint gerar as credenciais de teste; o frontend roda como `node`. Verificação: `uid=10001(app)` e `uid=1000(node)`, e os dois serviços continuam respondendo (`docs/evidencias/c12/`). Próximos passos recomendados: sistema de arquivos somente leitura, `cap_drop: [ALL]` e `no-new-privileges`.

### 7.2 Limite de taxa e cabeçalhos de segurança no Nginx (C06; commit `d342668`)
`limit_req` do Nginx: 5 requisições por minuto por IP em `/users/create` (com folga de 3) e 20 por segundo nas demais rotas, respondendo `429`. O limite fica no balanceador, e não no Flask, para o contador valer para as duas réplicas juntas. Foram adicionados `X-Content-Type-Options`, `X-Frame-Options` e `Referrer-Policy`, e a versão do Nginx foi ocultada. Verificação: 50 cadastros seguidos passaram de `50 × 200` para `4 × 200` e `46 × 429` (`docs/evidencias/c06/`). Limitação: o Nginx limita pelo IP que enxerga; atrás de outro proxy seria preciso configurar o IP real.

### 7.3 Outras decisões defensivas
- O backend **não publica porta**: só é acessível pelo Nginx, que não pode ser contornado.
- O `/metrics` fica na rede interna e é bloqueado (`404`) na porta pública.
- Os logs registram só o caminho da requisição, nunca a query string, para não gravar tokens.
- As portas do Prometheus e do Grafana ficam publicadas apenas em `127.0.0.1`.
- O ambiente se recusa a iniciar sem as variáveis dos emuladores e usa credenciais descartáveis.

---

## 8. Confiabilidade (SRE)

### 8.1 Observabilidade
- **Logs estruturados em JSON:** uma linha por requisição com `timestamp`, `level`, `request_id`, método, caminho, rota, status, `duration_ms` e a réplica que atendeu (`instance`). O `request_id` é gerado pelo Nginx e permite seguir uma requisição de ponta a ponta.
- **`GET /health`:** devolve `200` quando o processo está de pé (para balanceadores e probes). Não indica degradação: com 30 % de erros ele continua `ok`.
- **`GET /metrics`:** formato Prometheus, com `http_requests_total` (por método, rota e status) e `http_request_duration_seconds` (histograma por rota). É interno: o Prometheus raspa cada réplica pela rede do Docker.
- **Dashboard (Prometheus e Grafana):** provisionado por arquivos, sobe com o `docker compose up`. Tem 8 painéis: disponibilidade, latência, orçamento de erro, réplicas no ar, requisições por rota e por status, distribuição entre as réplicas e latência p50, p95 e p99. Capturas em `docs/evidencias/observabilidade/`.

### 8.2 SLIs e SLOs
Detalhados em `docs/sre/slis-slos.md`.

| SLI | Definição | SLO proposto |
|---|---|---|
| Disponibilidade | requisições sem erro 5xx / total | 99,5 % em 30 dias (orçamento de erro de 0,5 %, cerca de 3 h 36 min) |
| Latência | requisições atendidas em até 500 ms / total | 95 % em 30 dias |

Os SLOs são propostas justificadas e devem ser revistos com tráfego real. Um ponto de atenção: o código converte várias exceções em `400`, então uma falha de servidor pode se disfarçar de erro de cliente e não consumir o orçamento de disponibilidade.

### 8.3 Balanceamento e tolerância a falha
O Nginx distribui as requisições em round-robin entre 2 réplicas do backend e tenta a outra réplica quando uma falha.
- **Distribuição:** 40 requisições resultaram em 20 e 20 (`docs/evidencias/nginx/balanceamento.txt`).
- **Queda de uma réplica:** com uma réplica parada, 6 requisições devolveram `401` (a resposta esperada sem token), sem nenhum erro 5xx (`docs/evidencias/nginx/tolerancia-a-falha.txt`).
- **Observação:** a primeira medição de distribuição deu 16 e 4, e uma medição isolada posterior deu 20 e 20. Também se viu uma réplica sem tráfego no começo de uma rajada no dashboard. A causa não foi confirmada; a hipótese é que o Nginx resolve os endereços das réplicas **ao iniciar**, então, depois de recriar réplicas (com mudança de IP), é preciso reiniciar o balanceador. O `smoke-test.sh` reinicia o Nginx antes de testar. *(Hipótese não verificada.)*

### 8.4 Outros pontos de confiabilidade
- **C16:** o `main.py` executava lógica no import (lia `config.json` e chamava a OpenAI), derrubando o backend na inicialização. Resolvido com a guarda `if __name__ == "__main__"`.
- **C07:** versões não fixas tornam as builds não reproduzíveis.
- **Persistência:** o histórico de métricas e os logs não usam volumes; um `docker compose down` os apaga. Em produção, o Prometheus teria disco persistente e os logs iriam para um sistema central.


---

## 9. Recomendações priorizadas

| Prioridade | Recomendação | Achado | Esforço |
|---|---|---|---|
| **P0 (imediato)** | Revogar e gerar novas credenciais do Reddit; notificar o mantenedor | C05 | baixo |
| **P1 (curto prazo)** | Gerar lock com hashes (`uv pip compile --generate-hashes`) e instalar com `--require-hashes` | C07 | baixo |
| P1 | Restringir o CORS à origem do frontend, configurada por variável de ambiente | C01 | baixo |
| P1 | Padronizar erros: mensagens genéricas ao cliente, detalhe no log, status 5xx para falha de servidor, validação de entrada (`get_json(silent=True)`). 401 quando faltar token | C03, C15 | médio |
| P1 | Executar com um servidor WSGI de produção (por exemplo gunicorn) e remover `debug=True` | C02 | baixo |
| P2 | Padronizar o token no cabeçalho `Authorization` também nos `POST` | C04 | baixo |
| P2 | Exigir autenticação em `/users/query` antes de integrar o LLM, e tratar a entrada do prompt | C20, C09 | médio |
| P2 | Confirmação por e-mail no cadastro; limitar também o login | C19 | médio |
| P2 | Frontend em múltiplos estágios (servidor sem o toolchain de build), URL da API parametrizada e HTTPS | C17b, C13 | médio |
| P2 | Atualizar as dependências do frontend e acompanhar o `npm audit` | C17a | médio |
| P3 | `read_only`, `cap_drop` e `no-new-privileges` nos containers; volumes persistentes para o Prometheus; logs centralizados | C12 e observabilidade | médio |

---

## 10. Modelo de ameaças (STRIDE, resumo)

| Ameaça | Onde aparece | Achados |
|---|---|---|
| **S**poofing (falsificação de identidade) | roubo de token em logs; enumeração de contas | C04, C19 |
| **T**ampering (adulteração) | acesso entre usuários nos chats (verificado dinamicamente, sem falha); SQL por f-string (latente) | C18, C08 |
| **R**epudiation (repúdio) | logs sem identificador, antes da correção; agora com `request_id` por requisição | observabilidade |
| **I**nformation disclosure (vazamento) | segredo no repositório; token na URL; erros internos; CORS aberto | C05, C04, C03, C01 |
| **D**enial of service (negação de serviço) | sem limite de taxa; erro 500 por entrada malformada; efeito colateral no import | C06, C15, C16 |
| **E**levation of privilege (elevação) | containers como root; rota sem autenticação | C12, C20 |

---

## 11. Ferramentas de análise recomendadas e saídas

| Tipo | Ferramenta | Uso | Saída |
|---|---|---|---|
| SAST | Semgrep (regras `p/python`, `p/flask`, `p/typescript`, `p/react`, `p/dockerfile`, `p/secrets`) | padrões inseguros no código e nos Dockerfiles | `docs/evidencias/scans/semgrep.txt` |
| SAST | Bandit | problemas específicos de Python | `docs/evidencias/scans/bandit.txt` |
| SCA | pip-audit | CVEs em dependências Python | `docs/evidencias/scans/pip-audit.txt` |
| SCA | npm audit | CVEs em dependências do frontend | `docs/evidencias/scans/npm-audit.txt` |
| Segredos | Gitleaks (com `--redact`) | segredos no código e no histórico | `docs/evidencias/scans/gitleaks.json` |

**CI (GitHub Actions, `.github/workflows/security.yml`):**
- **Bloqueiam:** Gitleaks no código atual (impede a volta de segredos) e o teste de fumaça (`scripts/smoke-test.sh`), que verifica as correções C04, C05 e C19, os hardenings C06 e C12, o balanceamento e a observabilidade.
- **Bloqueiam só achados novos:** Semgrep nos pull requests, comparando com a branch base (os achados antigos são conhecidos e documentados).
- **Informativos:** relatório completo do Semgrep, Bandit, pip-audit e npm audit (guardados como artefatos). Um CVE novo publicado não deve quebrar o build por uma causa externa.

---

## 12. Limitações deste trabalho
- Os testes dinâmicos foram feitos contra o emulador do Firebase, e não contra o serviço real (que está fora do escopo e é de terceiros).
- O C02 foi identificado por análise e por scanners, e não foi reproduzido.
- Os SLOs são propostas, e não foram calibrados com tráfego real.
- O histórico do Git não foi reescrito; a credencial do Reddit continua nele até ser revogada.
- O teste de fumaça e o CI cobrem as correções implementadas, mas não substituem um teste de intrusão completo.
- A presença de código vulnerável no bundle foi avaliada pelos imports do código-fonte e por busca de URLs de serviços no dist; uma busca por nomes de pacote em código minificado não é conclusiva e não foi usada como prova.

---

## Anexo A: Índice de evidências

| Pasta ou arquivo | Conteúdo |
|---|---|
| `docs/candidate-findings.md` | triagem completa, notas por achado e resumo das decisões |
| `docs/evidencias/scans/` | saídas brutas das varreduras automáticas |
| `docs/evidencias/c01/`, `c03/`, `c15/` | reproduções dos achados de configuração e validação |
| `docs/evidencias/c04/`, `c05/`, `c19/` | antes e depois das três correções |
| `docs/evidencias/c06/`, `c12/` | antes e depois dos hardenings |
| `docs/evidencias/c07/` | comparação das versões de dependências |
| `docs/evidencias/c16/` | cenário de falha na inicialização |
| `docs/evidencias/nginx/` | balanceamento e tolerância a falha |
| `docs/evidencias/observabilidade/` | `/health`, logs JSON, métricas e capturas do Grafana |
| `docs/sre/slis-slos.md` | SLIs, SLOs e descrição do dashboard |
| `scripts/smoke-test.sh` | testes automatizados de regressão |
| `docs/evidencias/c09/`, `c20/` | verificação do stub do LLM e da rota semautenticação |
| `docs/evidencias/c17/` | npm audit de runtime, imports do frontend, busca no bundle etamanho da imagem |
| `docs/evidencias/c18/` | teste de isolamento de chats entre dois usuários |
| `docs/evidencias/xss/` | busca por padrões de XSS no frontend |

Como executar o ambiente e reproduzir os achados: ver o `README.md`.