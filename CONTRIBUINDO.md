# Contribuindo — Chat do Garoto

App que junta, no mesmo lugar, conversas do WhatsApp, clientes, produtos e vendas, com privacidade total: tudo roda e fica cifrado no aparelho, sem servidor. Android e Linux primeiro.

- Regras de cada parte do código: `core/DESENVOLVIMENTO.md` (Go) e `app/DESENVOLVIMENTO.md` (Flutter)

## Como trabalhar

- Teste antes de dar por pronto. Nunca apague nem afrouxe teste para "passar".
- Documentos e commits em português do Brasil; código, identificadores e comentários no código em inglês.
- Commits no estilo Conventional Commits, com a descrição em português (`feat(app): ...`, `fix(core): ...`, `docs: ...`).

## Stack

| Peça | Versão | Onde |
| --- | --- | --- |
| Flutter / Dart | 3.47.5 / 3.13.4 | `app/` |
| Go + whatsmeow | 1.27.1 + última do repositório | `core/` (biblioteca `c-shared`) |
| Ponte | `dart:ffi` + bindings gerados por `ffigen` | `core/` exporta, `app/` consome |
| Banco local | SQLite + SQLCipher (Drift no Flutter) | `app.db` (Dart) e `wa.db` (Go) |
| Android | SDK 36, NDK r30 (30.0.16248370) | `~/Android/Sdk` |

## Comandos

```bash
# Flutter (dentro de app/) — flutter run/build/test também compila o Go (hook)
flutter pub get
dart format .
flutter analyze
flutter test
flutter run -d linux          # desktop
flutter run -d <celular>      # instala e abre no celular

# Go (dentro de core/)
gofmt -l .
go vet ./...
go test ./...
```

## Segurança e privacidade (inegociável)

- Nunca registrar em log, `print`, mensagem de erro ou crash report: conteúdo de mensagens, números de telefone, nomes de contatos, chaves, PIN ou senhas.
- Nenhuma dependência de analytics, telemetria, crash reporting, anúncios ou nuvem.
- Criptografia só com bibliotecas reconhecidas (SQLCipher, libsodium, Argon2id, protocolo Signal). Nunca inventar esquema próprio.
- Nunca commitar bancos (`*.db`), sessões do WhatsApp, chaves, backups, `.env` ou keystores.
- **Nunca enviar mensagem a contatos reais em teste.** Use um número de teste seu. Nada de envio em massa (risco de banimento do número).
