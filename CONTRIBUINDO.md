# Contribuindo

Obrigado pelo interesse em contribuir com o Chat do Garoto. Este guia reúne o que é preciso para preparar o ambiente, seguir o fluxo de trabalho e entregar uma mudança que passe na revisão.

## Antes de começar

- [`README.md`](README.md): visão geral do projeto.
- [`app/DESENVOLVIMENTO.md`](app/DESENVOLVIMENTO.md) (Flutter) e [`core/DESENVOLVIMENTO.md`](core/DESENVOLVIMENTO.md) (Go): mapa do código e armadilhas conhecidas.

## Ambiente

| Peça | Versão | Onde |
| --- | --- | --- |
| Flutter / Dart | 3.47.5 / 3.13.4 | `app/` |
| Go + whatsmeow | 1.27.1 | `core/` (biblioteca `c-shared`) |
| Ponte | `dart:ffi` + bindings gerados por `ffigen` | `core/` exporta, `app/` consome |
| Banco local | SQLite + SQLCipher (Drift no Flutter) | `app.db` (Dart) e `wa.db` (Go) |
| Android | SDK 36, NDK r30 (30.0.16248370) | `~/Android/Sdk` |

No Linux, instale também `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `libsecret-1-dev` e `liblzma-dev`.

```bash
# Flutter (dentro de app/): flutter run, build e test também compilam o Go (build hook)
flutter pub get
flutter run -d linux          # computador
flutter run -d <aparelho>     # Android

# Go (dentro de core/)
gofmt -l .
go vet ./...
go test ./...
```

## Fluxo de trabalho

1. Abra uma issue descrevendo o problema ou a proposta, ou comente numa existente.
2. Crie uma branch a partir de `main`.
3. Faça mudanças pequenas e focadas, com testes.
4. Abra o pull request preenchendo o modelo.

### Commits

[Conventional Commits](https://www.conventionalcommits.org/pt-br/), com a descrição em português:

```
feat(app): filtro de conversas sem resposta
fix(core): não segurar a trava da sessão ao desconectar
docs: atualiza o guia de contribuição
```

## Qualidade

Antes de abrir o pull request:

```bash
cd core && gofmt -l . && go vet ./... && go test ./...
cd ../app && dart format . && flutter analyze && flutter test
```

- Todo comportamento novo tem teste. Nunca remova nem afrouxe um teste para fazê-lo passar.
- `flutter analyze` e `go vet` sem avisos.
- Código, identificadores e comentários no código em inglês. Documentação e mensagens de commit em português do Brasil.
- Uma tela nova segue os componentes e o espaçamento do tema (`app/lib/src/theme/`) e é conferida em celular, tablet e computador (`app/integration_test/layout_audit_test.dart` gera as imagens).

## Segurança e privacidade

Regras que nenhuma mudança pode quebrar:

- Nunca registrar em log, `print`, mensagem de erro ou relatório de falha: conteúdo de mensagens, números de telefone, nomes de contatos, chaves, PIN ou senhas.
- Nenhuma dependência de analytics, telemetria, relatório de falhas, anúncios ou nuvem.
- A única conexão de rede do aplicativo é com o WhatsApp, via whatsmeow. Qualquer outra exige discussão prévia numa issue.
- Criptografia apenas com bibliotecas reconhecidas (SQLCipher, age, Argon2id, protocolo Signal). Nenhum esquema próprio.
- Nunca versionar bancos (`*.db`), sessões do WhatsApp, chaves, backups, `.env` ou keystores.
- Em testes, nunca enviar mensagens a contatos reais: use um número de teste. Nenhum envio em massa (risco de banimento do número).

Vulnerabilidades devem ser relatadas de forma privada, conforme [`SECURITY.md`](SECURITY.md).

## Licença

Ao contribuir, você concorda que sua contribuição seja licenciada sob a [GPL-3.0](LICENSE), a mesma do projeto.
