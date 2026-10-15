<p align="center">
  <img src="app/assets/brand/garoto.png" alt="Garoto do Programa;" width="96">
</p>

<h1 align="center">Chat do Garoto</h1>

<p align="center">
  Conversas do WhatsApp, clientes, produtos e vendas num só aplicativo.<br>
  Tudo cifrado no próprio aparelho, sem servidor, sem nuvem e sem telemetria.
</p>

<p align="center">
  <a href="../../actions/workflows/testes.yml"><img src="../../actions/workflows/testes.yml/badge.svg" alt="testes"></a>
  <img src="https://img.shields.io/badge/licença-GPL--3.0-39FF88?labelColor=0D1117" alt="GPL-3.0">
  <img src="https://img.shields.io/badge/Flutter-3.47-FF2E88?labelColor=0D1117" alt="Flutter 3.47">
  <img src="https://img.shields.io/badge/Go-1.27-39FF88?labelColor=0D1117" alt="Go 1.27">
  <img src="https://img.shields.io/badge/plataformas-Android%20%7C%20Linux-FF2E88?labelColor=0D1117" alt="Android e Linux">
</p>

| Início | Conversas | Clientes |
| --- | --- | --- |
| ![Início](docs/imagens/1-inicio.png) | ![Conversas](docs/imagens/2-conversas.png) | ![Clientes](docs/imagens/3-clientes.png) |
| **Produtos** | **Vendas** | **No celular** |
| ![Produtos](docs/imagens/4-produtos.png) | ![Vendas](docs/imagens/5-vendas.png) | ![No celular](docs/imagens/6-celular.png) |

<sub>Capturas do modo de demonstração, em execução real. Todos os nomes e números são fictícios.</sub>

## Visão geral

O Chat do Garoto conecta-se ao WhatsApp como aparelho vinculado (como o WhatsApp Web) e reúne, na mesma interface, o atendimento e a gestão do negócio. Os dados nunca saem do aparelho: não existe servidor do projeto.

A interface se adapta ao tamanho da janela: barra de abas no celular; barra lateral com lista e detalhe lado a lado no tablet e no computador; e, em monitores grandes, a ficha do cliente fixa ao lado da conversa.

## Funcionalidades

- **Conversas:** pareamento por código ou QR Code; texto, foto, áudio, vídeo e documento; encaminhar e apagar (para mim ou para todos); busca nas conversas.
- **Clientes:** a conversa vira ficha, com anotações internas, etiquetas, aniversário, histórico de compras e saldo devedor.
- **Produtos:** variações (tamanho, cor), estoque com histórico e custo médio, preço promocional e de atacado, validade, foto e leitor de código de barras.
- **Vendas:** Pix, dinheiro, cartão e fiado em parcelas, com recebimentos, vencidas e a receber. A cobrança apenas prepara a mensagem na caixa da conversa; o envio é sempre manual.
- **Início:** painel do dia, com parcelas vencidas, aniversários, conversas sem resposta, estoque baixo e números do mês.
- **Segurança:** bloqueio por PIN e biometria, bancos cifrados, backup cifrado com senha do usuário e exclusão definitiva.

## Privacidade e segurança

- Dois bancos SQLCipher: o do aplicativo (`app.db`, Drift) e o da sessão do WhatsApp (`wa.db`, Go).
- Chaves guardadas no cofre do sistema (Android Keystore; libsecret no Linux). O PIN protege a chave por Argon2id e AES-256-GCM.
- Mídias cifradas em repouso e abertas apenas em memória.
- Backup cifrado com senha (age + scrypt), que só o usuário consegue abrir.
- `secure_delete` nos bancos e bloqueio de captura de tela no Android.
- A única conexão de rede do aplicativo é com o WhatsApp (e, opcionalmente, uma consulta de CEP disparada pelo usuário). Não há analytics, crash reporting nem anúncios.

Apenas bibliotecas de criptografia reconhecidas são usadas; nenhum esquema próprio. Para relatar uma vulnerabilidade, consulte [`SECURITY.md`](SECURITY.md).

## Arquitetura

O motor do WhatsApp é escrito em Go ([whatsmeow](https://github.com/tulir/whatsmeow)), compilado como biblioteca C (`c-shared`) e chamado pelo Flutter por `dart:ffi`, com bindings gerados pelo `ffigen`. Os eventos voltam do Go para o Dart por callback nativo. O Flutter compila o Go automaticamente, no Linux e no Android, por um build hook.

```
app/   Flutter (telas, CRM, banco local)   ←  dart:ffi  →   core/   Go (WhatsApp, cofre, backup)
```

- **Telas e CRM (`app/`):** controladores `ChangeNotifier`, repositórios sobre Drift/SQLCipher e telas que só leem o estado; nenhuma tela chama o FFI diretamente.
- **Motor (`core/`):** sessão do WhatsApp, cofre de mídias, envelope do PIN e backup, em pacotes Go testáveis sem cgo; toda função exportada passa por um único ponto que converte `panic` em erro.
- **Ponte:** contrato em `core/include/chatcore.h`; respostas em envelope JSON versionado; mídia como bytes por ponteiro e tamanho.

## Como executar

Requisitos: **Go 1.27** e **Flutter 3.47**. Para Android, também o Android SDK e o NDK 30.0.16248370.

```bash
cd app
flutter pub get
flutter run -d linux        # computador
flutter run -d <aparelho>   # Android (flutter devices lista os disponíveis)
```

### Modo de demonstração

Na primeira tela, escolha **"Explorar sem conectar"**. Abre uma loja fictícia, com clientes, produtos, vendas e conversas. Nada é gravado em disco, nada vai para a rede e o WhatsApp não é conectado.

## Testes

```bash
cd core && go test ./...
cd ../app && flutter test
```

São 408 testes no aplicativo e 131 no motor em Go, executados a cada envio pelo GitHub Actions (formatação, análise estática e testes). Os testes de interface em tamanhos de tela diferentes ficam em `app/integration_test/`.

## Estrutura do repositório

| Pasta | Conteúdo |
| --- | --- |
| `app/` | Aplicativo Flutter: telas, CRM, banco local e modo de demonstração |
| `core/` | Motor em Go (whatsmeow), exportado como biblioteca via FFI |
| `docs/` | Capturas de tela usadas neste README |

## Documentação

- [`CONTRIBUINDO.md`](CONTRIBUINDO.md): ambiente, fluxo de trabalho e padrões
- [`app/DESENVOLVIMENTO.md`](app/DESENVOLVIMENTO.md) e [`core/DESENVOLVIMENTO.md`](core/DESENVOLVIMENTO.md): mapa do código e armadilhas conhecidas
- [`SECURITY.md`](SECURITY.md): como relatar vulnerabilidades
- [`CHANGELOG.md`](CHANGELOG.md): histórico de mudanças

## Aviso sobre o WhatsApp

O aplicativo usa o protocolo do WhatsApp pela biblioteca [whatsmeow](https://github.com/tulir/whatsmeow), que **não é oficial**. O WhatsApp pode restringir contas que usam clientes não oficiais. Use um número de teste, não envie mensagens em massa e assuma o risco do uso. O vínculo permanece ativo enquanto o WhatsApp oficial do celular principal for aberto ao menos a cada 14 dias.

## Licença

[GPL-3.0](LICENSE). A licença vem do `libsignal`, usado pelo whatsmeow, que também é GPL-3.0: quem distribuir o aplicativo deve disponibilizar o código sob a mesma licença. As fontes (Ubuntu Sans e Ubuntu Sans Mono) acompanham as próprias licenças (Ubuntu Font Licence).

## Autoria

Mantido por **Garoto do Programa;**, canal de programação e sistemas gratuitos para a comunidade.

[Instagram](https://instagram.com/garotodoprograma) · [TikTok](https://tiktok.com/@garotodoprograma) · [GitHub](https://github.com/garotodoprograma404)
