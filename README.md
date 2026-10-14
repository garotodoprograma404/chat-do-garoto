# Chat do Garoto

Sistema grátis do canal **Garoto do Programa** para a comunidade: um app que junta, no mesmo lugar, as conversas do WhatsApp, os clientes, os produtos e as vendas de quem atende pelo celular. Tudo roda e fica cifrado no seu aparelho, **sem servidor** e sem enviar nada para ninguém.

Android e Linux primeiro; iPhone, Windows e Mac ficam para depois.

## O que já faz

- Conecta o seu WhatsApp como "aparelho vinculado" (por código ou QR Code) e mostra as conversas, com texto, foto, áudio, vídeo e documento.
- Cadastro de clientes ligado à conversa, com anotações, etiquetas e histórico.
- Produtos com variações, estoque e custo médio; leitor de código de barras.
- Vendas, pagamentos, parcelas e "a receber", com resumo para mandar na conversa.
- Bloqueio por PIN ou digital, banco e mídias cifrados (SQLCipher) e backup cifrado que só você abre.

## Aviso importante

O app usa a biblioteca [whatsmeow](https://github.com/tulir/whatsmeow), que **não é oficial**. O WhatsApp pode banir números que usam clientes não oficiais. Teste com um número descartável, nunca envie mensagem em massa e use por sua conta e risco. O app só funciona enquanto o WhatsApp oficial do seu celular for aberto pelo menos a cada 14 dias.

## Como rodar

Você precisa de Go 1.27.1 e Flutter 3.47.5. Para Android, também o Android SDK e o NDK 30.0.16248370.

```bash
cd app
flutter pub get
flutter run -d linux      # no computador
flutter run -d <celular>  # no Android (use `flutter devices` para ver o nome)
```

O Flutter compila o motor em Go sozinho. Para rodar os testes:

```bash
cd core && go test ./...
cd ../app && flutter test
```

Um teste de tela (`screens_review_test.dart`, "the text of my bubble uses its own color") já falhava antes e continua falhando; os outros passam.

## Como o código está organizado

| Pasta | O que é |
| --- | --- |
| `app/` | App Flutter: telas, clientes, produtos, vendas e banco local |
| `core/` | Motor em Go (whatsmeow), exportado como biblioteca via FFI |
| `docs/` | Capturas de tela usadas neste README |

## Privacidade

O app não tem analytics, telemetria nem nuvem. A única conexão de rede é com o WhatsApp. As regras estão em [`CONTRIBUINDO.md`](CONTRIBUINDO.md).

## Licença

GPL-3.0, veja o arquivo [`LICENSE`](LICENSE). Ela vem do `libsignal`, usado pelo whatsmeow, que também é GPL-3.0: quem distribuir o app precisa abrir o código sob a mesma licença.
