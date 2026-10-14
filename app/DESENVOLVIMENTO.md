# app/ — app Flutter (telas, CRM, banco local)

Interface e CRM em Flutter/Dart. Conversa com o motor Go só pela ponte FFI. As regras gerais estão em `../CONTRIBUINDO.md`.

- Pacote Dart: `chat_do_garoto`.
- Identificador: `br.com.garotodoprograma.chatdogaroto` .
- Plataformas: Linux e Android (arm64, armv7 e x86_64; testado em aparelho só o arm64). NDK fixo: 30.0.16248370 (`android/app/build.gradle.kts`). Android mínimo: API 24.

## Organização

| Caminho | O que é |
| --- | --- |
| `hook/build.dart` | Build hook: compila `../core` com `go build -buildmode=c-shared` e embute a `libchatcore` no app (Linux e Android; no Android usa o wrapper `<triplo><api>-clang` do NDK). Grava o `SONAME`. Roda sozinho em `flutter run`, `build` e `test`. |
| `test/core_bridge_cases.dart`, `test/core_events_cases.dart` | Casos de teste da ponte e dos eventos, compartilhados pelo teste do Linux e pelo teste no aparelho (`integration_test/core_bridge_device_test.dart`, um arquivo só para instalar o app uma vez). |
| `tool/ffigen.dart` | Gera os bindings a partir de `../core/include/chatcore.h`. |
| `lib/src/core_bridge/chatcore.g.dart` | Bindings gerados. **Nunca editar à mão.** |
| `lib/src/core_bridge/core_bridge.dart` | `CoreBridge`: a única porta de entrada para o Go. `NativeCoreBridge` é a implementação real; os testes de tela usam uma falsa. |
| `lib/src/whatsapp/` | Conexão com o WhatsApp: `WhatsAppController` (`ChangeNotifier`) e `ConnectScreen` (código ou QR). |
| `lib/src/platform/connection_keeper.dart` + `android/.../ConnectionService.kt` | Serviço em primeiro plano (tipo `remoteMessaging`) que mantém a conexão quando o usuário troca de app; ligado por `MethodChannel` `chatdogaroto/connection`. |
| `lib/src/platform/wa_key.dart` + `android/.../WaKey.kt` | Chave do `wa.db`: no Android, o Kotlin a guarda envelopada pelo Keystore (`files/wa/wa.key`) e a entrega ao Dart (canal `waKey`) e ao serviço; no Linux, cofre do sistema. Testes usam `FakeWaKeyProvider`. |
| `lib/src/chats/` | Lista de conversas e conversa: `ChatsController`, `ChatController` (ao vivo, páginas de 50; envio e "tentar de novo", estado por `wa_message_status`), telas funcionais. Busca: `chat_search_screen.dart` (nomes e mensagens via `cc_messages_search`) e `ChatController(focus:)`, que abre a conversa na mensagem com "Ir para as mais recentes". Fotos: `photo_screen.dart` (tela cheia, download ao tocar, estados) e `previewOf` (a foto inteira depois de baixada, senão a miniatura; cache só na memória, 40 itens). Fotos de antes da 2.5 (`media` vazio) ficam como "[imagem]". Mídias em `chats/media/`: `media_platform.dart` (canal `chatdogaroto/media` do `MediaChannel.kt`: áudio e vídeo tocados da memória, gravação OGG/Opus, remux do vídeo sem localização, abrir com e salvar), balões e tela de vídeo (`media_tiles.dart`), anexo (`media_picker.dart`), prévia com legenda, botão de voz (segurar, soltar, arrastar para cancelar) e Encaminhar. `mediaPlatform` e `chatMediaPicker` são globais trocados nos testes. Exclusão: segurar a conversa na lista ou ⋮ na conversa → "Excluir conversa" (`confirmDeleteChat`, com a opção de apagar para todos as minhas mensagens recentes, `revocableCount`); segurar a mensagem → "Apagar" (para todos só quando `canRevoke`); `wa_deleted` atualiza lista e conversa (a tela fecha se a conversa for excluída) e a mensagem apagada vem com `kind` "revoked".

Conversas e clientes:
- `ChatClients`: liga conversa a cliente pela conversa salva, pelo telefone ou pelo telefone do LID (`cc_chat_phone`); também guarda o que cada cliente deve e os ignorados. `findChatClient` faz o mesmo para uma conversa só.
- Filtros (`chat_filters.dart`): Todas, Sem resposta (`waitingReply`: conversa individual, última mensagem do contato, até 7 dias, pelo `last_from_me` do motor), Clientes, Devendo e Novos contatos. O filtro escolhido fica no `ChatsController`.
- Tocar no nome de uma conversa individual abre o painel do cliente (`client_panel.dart`, devolve um `PanelAction`). Grupos, ou o app sem o `app.db`, abrem a `ContactScreen`.
- Faixa "Contato novo" (`new_contact_strip.dart`): Cadastrar, Vincular (`ClientPickerScreen` + `Client.linkedTo`) e Ignorar com Desfazer.
- Nota interna = anotação do cliente (`ClientNotes`). O modo nota da caixa nunca chama o `ChatController`. `mergeNotes` põe as notas entre as mensagens e só é recalculado quando as mensagens ou as notas mudam.
- Respostas rápidas: "/" no início da caixa (`quick_replies.dart`, `{nome}` = primeiro nome) e Configurações → Respostas rápidas.
- `ChatPrefs` (`chat_prefs.dart`) guarda respostas e ignorados em JSON na tabela `Preferences` do `app.db` e chega às telas pelo `CrmScope.chatPrefs`. |
| `lib/src/storage/` | Banco do app `app.db`: Drift sobre SQLCipher (`hooks.user_defines.sqlite3.source: sqlcipher` no `pubspec.yaml`), chave aleatória no cofre (`KeyVault`), `AppStorage` (recusa abrir sem SQLCipher; "ilegível" quando a chave não abre) e a tela de recuperação. Tabelas novas: editar `app_database.dart` e rodar `dart run build_runner build`. |
| `lib/src/home/` + `lib/src/settings/` | Seções do app: `HomeShell` com Conversas e Clientes (barra de baixo); menu ⋮ (e o ícone no alto do Início) → `SettingsScreen` (conexão, estabilidade, bateria, backup, aparência, privacidade e segurança, PIN, digital). Cinco abas (Início, Conversas, Clientes, Produtos, Vendas) com esmaecimento ao trocar. A seção Clientes funciona sem o WhatsApp. |
| `lib/src/clients/` | Clientes do CRM: `ClientsRepository` (Drift no `app.db` v2: `clients`, `client_tags`, `client_notes`), validações puras (`validation.dart`: telefone, e-mail, CPF/CNPJ, aniversário, etiquetas), controladores e telas; página do cliente com o bloco WhatsApp (últimas mensagens e "Abrir conversa"; a conversa vem de `chatJid` ou de `cc_chat_for_phone`). Telas recebem o repositório só com o `app.db` aberto. Busca, filtros (etiquetas, aniversariantes do mês) e ordenações no `ClientsController`, na memória, a partir do banco cifrado; textos comparados com `lib/src/search/text.dart` (`fold`, `textMatches`).

Ficha:
- resumo em `ClientSummary`/`ClientNumbers` (deve, vencido por parcela, comprado);
- botões Conversar, Nova venda, Receber e Cobrar;
- linha do tempo (`client_timeline.dart`) com compras, recebimentos não estornados, cancelamentos e anotações, 20 de cada vez.

Lista de clientes: filtro "Devendo". "Escolher da agenda" no cadastro novo usa `ContactPicker` (canal `chatdogaroto/contacts`, `ContactPickerChannel.kt`, `ACTION_PICK` em telefones, **sem** `READ_CONTACTS`); `normalizePhone` põe o 55. |
| `lib/src/products/` | Produtos: `app.db` v3 (`products`, `product_attributes`, `product_variants`, `product_wholesale`, `stock_moves`, `product_photos`). Dinheiro em centavos e quantidade em milésimos (`money.dart`); todo produto tem ao menos uma variação, e o estoque só muda por `move()` (movimento e saldo na mesma transação, custo médio). Lógica pura em `barcode.dart`, `variants.dart` e `pricing.dart`; busca, filtros e ordenações no `ProductsController`; fotos pelo `PhotoPicker` (`image_picker`), guardadas como BLOB e lidas sob demanda (`ProductThumb`). |
| `lib/src/sales/` + `lib/src/home/crm_scope.dart` | Vendas: `app.db` v4 (`sales`, `sale_items`, `sale_payments`, `sale_installments` e `stock_moves.sale_id`). A venda guarda uma fotografia dos itens (descrição, preço, custo da hora), nunca é apagada nem editada (cancelar devolve o estoque com `moveForSale` e estorna os pagamentos), e o abatimento das parcelas e a situação são calculados (`sale_math.dart`). Produto vendido só se inativa (`ProductHasSales`); cliente que deve não se apaga (`ClientHasOpenSales`). O `CrmScope` (no `MaterialApp.builder`, acima do navegador) entrega produtos e vendas a qualquer rota, como a página do cliente aberta pela conversa.

Conversas e clientes:
- `receive_dialog.dart`: `askReceipt`, o diálogo único de recebimento, e `receiveFromClient`, que escolhe a venda em aberto mais antiga primeiro;
- `charge_message.dart`: o texto do "Cobrar", que só vai para a caixa.

Vendas e formulários:
- nova venda em "Como vai pagar?": um toque (Pix, Dinheiro com troco, Débito, Crédito, Fiado com "Parcelar", "Outra forma"), "Dividir em mais de uma forma" com os pagamentos e parcelas de antes, e "Mais detalhes" (desconto, frete, data, observação); `SaleFormScreen(item:)` começa com um produto;
- painel de Vendas: só título e abas fixos, busca no ícone (`SalesSearch`), filtros numa linha (período em menu), totais num cartão que rola, A receber em "Vencidas" e "A vencer", botões lado a lado;
- `dueLabel` ("venceu há 3 dias") e `clientHint` (a linha útil da lista de Clientes); `formatPhone`; `plural`;
- o `CrmScope` também entrega `clients`, para a venda aberta pela ficha do produto.

Venda rápida e validade (`app.db` v5):
- `quick_sale_screen.dart`: a venda rápida é uma `Sale` com um item sem produto (`SaleItem.variantId` nulo), que não mexe no estoque;
- barra fixa `_TotalBar` na nova venda;
- "Ler código" na venda soma itens (`productByCode`);
- `Product.expiresOn`, `expiresIn`, `expiringSoon` (30 dias) e `expiryLabel`;
- `goneClients` (60 dias) para o filtro "Sumidos". |
| `lib/src/backup/` + `android/.../BackupChannel.kt` | Backup: `BackupController` (no `main`, vive com o app; fazer, restaurar, cancelar, lembrete com data e intervalo no cofre do sistema), `BackupScreen` (Configurações → Backup e tela de recuperação, só restaurar) e `BackupReminder` (no alto da `HomeShell`). O canal `chatdogaroto/backup` cria ou abre o arquivo no seletor do Android e devolve o descritor (`detachFd`) para o core. `exportCopy`/`AppStorage.importCopy` (em `storage/`) copiam o `app.db` cifrado com chave de uso único; a importação monta o banco ao lado e só então troca. Sobras em `cache/backup` são apagadas ao abrir. |
| `lib/src/scan/` | Leitor de código de barras:
- `BarcodeScanner` (`scanOne` e `scanMany` contínuo) e `ScanScreen`, com o `ReaderWidget` do `flutter_zxing`;
- formatos de produto e de etiqueta, sem galeria, com lanterna; a mesma etiqueta é ignorada por 1,5 s; câmera negada mostra a explicação;
- o global `barcodeScanner` só existe no Android (no `main`), e os testes usam `FakeBarcodeScanner`;
- `scanIntoButton` põe o botão no campo de código.

O manifesto remove as permissões que o plugin de câmera traz e o app não usa (`WRITE`/`READ_EXTERNAL_STORAGE` e `ACCESS_NETWORK_STATE`). |
| `lib/src/theme/form_parts.dart` + `lib/src/storage/form_drafts.dart` | Formulários:
- `Masks` (dinheiro "1290" → R$ 12,90, data, CEP, telefone, CPF/CNPJ), `MoneyField`, `moneyController`, `FormGap`;
- `DetailsGroup` ("Mais detalhes" recolhido, com resumo);
- `DraftKeeper` e `FormDrafts` (rascunho cifrado no `app.db`, chaves `draft_<form>`), mais `askContinueDraft` e `confirmDiscard`.

Regra da pesquisa: cadastro curto, só o essencial no alto e o resto em grupos. |
| `lib/src/clients/cep_lookup.dart` | "Buscar CEP": ViaCEP e, se falhar, BrasilAPI, pelo `HttpClient`, só no toque e só com os 8 números. É a única conexão além do WhatsApp. O global `cepLookup` é trocado nos testes. Endereço em campos separados (`app.db` v6: `cep`, `address_number`, `complement`, `district`, `city`, `state`; `address` é a rua). |
| `lib/src/intro/` | Primeira configuração: `IntroScreen` (três páginas: o que protege, o que não protege, backup com caixa obrigatória; modos `newInstall`, `existing` e `read`) e `IntroController` (marca "vistas" no cofre do sistema, `intro_seen`, porque o `app.db` só abre depois do PIN). No `main`: antes do PIN numa instalação nova; uma vez depois do desbloqueio para quem já usa; "Tenho um backup" abre Restaurar logo após o PIN; Configurações → Privacidade e segurança. |
| `lib/src/theme/` | Identidade visual:
- `AppTheme`: cores do Garoto do Programa em esquemas feitos à mão (escuro por padrão, verde `#39FF88` principal, rosa `#FF2E88` nos terciários); Ubuntu Sans Mono nos títulos e Atkinson Hyperlegible Next no texto (variáveis; o `FontWeight` move o eixo de peso); formas; claro e escuro;
- `brand_mark.dart`: `BrandMark` (o rosto, imagem de `assets/brand/`), `SemicolonText` (título com o `;` rosa), `BrandLockup` (rosto + "Chat do Garoto;") e `DotGrid` (fundo de pontos); `brand_nav_bar.dart`: a barra de abas;
- `AppStatusColors` (`Situation` ok/open/overdue/off) e `StatusPill`;
- componentes: `MoneyText`, `AppListTile` (cresce com a fonte grande; o `ListTile` estoura o trecho da direita), `AppSearchField`, `EmptyState`, `SectionHeader`, `InitialsAvatar`, `ClientMark`;
- `Motion` (durações e "Remover animações"), `Haptics`, `Highlight`, `EnterOnce`, `OpenTile` e `GrowRoute`;
- `ThemeController` (Sistema/Claro/Escuro, no cofre).

Ícones: `Symbols.*_rounded` (`material_symbols_icons`), com o ativo `fill: 1`. |
| `lib/src/home/start_screen.dart` + `start_controller.dart` | Início: bloco "Hoje" (parcelas vencidas e de hoje, aniversários em 7 dias, conversas sem resposta, estoque baixo), atalhos e números do mês, calculados na memória dos repositórios. O app abre nele, e por isso **mostra nomes e prévias de conversas**: nos testes no celular, não capturar a tela do Início. "Ver todas" abre Conversas com o filtro. |
| `lib/src/lock/` + `android/.../BiometricKey.kt` | Bloqueio do app: `LockController` (PIN de 6 dígitos, digital, espera após erros, bloqueio após 1 min fora ou 5 min parado, trocar e esqueci o PIN) e as telas. A chave do `app.db` só sai com o PIN (envelope no Go) ou a digital (Keystore + `BiometricPrompt`, canal `chatdogaroto/security`). |
| `test/support/` | Ponte, serviço, cofre, biometria e chave falsos para os testes de tela e de controlador. |
| `lib/src/prototype/` | Tela de teste da Fase 1. Sai quando existirem as telas do WhatsApp. |

- Organização: uma pasta por funcionalidade em `lib/src/<funcionalidade>/`, com controlador `ChangeNotifier` (estado e ações) e telas que só leem o controlador (`ListenableBuilder`). Sem pacote externo de estado.
- As telas recebem um `CoreBridge` e nunca chamam FFI diretamente.

## Regras da ponte (FFI)

- Toda resposta do Go passa por `callNative`, que sempre chama `cc_free` (em `finally`) e converte o envelope de erro em `CoreException`.
- Strings enviadas ao Go são alocadas com `using((arena) { ... })`, que libera tudo ao sair. Texto com o caractere NUL não atravessa a ponte.
- Chamada FFI síncrona que faz I/O não roda no isolate da interface. As funções atuais (versão, eco) são instantâneas; as de rede chegam por eventos.
- **Eventos do Go**: `bridge.events` é um `Stream<CoreEvent>` broadcast. O ouvinte nativo (`NativeCallable.listener`) é criado na primeira leitura de `events`; cada evento é liberado com `cc_free` logo após ser lido.
- **Ordem ao descartar:** `dispose()` primeiro chama `cc_events_listen(nullptr)` (o Go espera as entregas em andamento) e só depois fecha o ouvinte. Inverter a ordem pode derrubar o app. Eventos ainda na fila no momento do `dispose` são descartados (não liberados) — aceitável no encerramento.
- Assine `events` **antes** de iniciar algo que emite eventos: sem ouvinte registrado, o Go descarta os eventos.

## Armadilhas conhecidas

- **Hook novo não roda:** se um `hook/build.dart` for criado *depois* de um build, o Flutter usa o cache e não o executa. Rode `flutter clean` uma vez. Mudanças no Go já são detectadas sozinhas.
- **O Go precisa estar no `PATH`** de quem roda o Flutter. O hook só recebe `PATH`, `HOME` e poucas outras variáveis de ambiente.
- **Xiaomi recusa instalar pelo cabo** (`INSTALL_FAILED_USER_RESTRICTED`): ativar "Instalar via USB" nas Opções do desenvolvedor e tocar em **Instalar** na janela com contagem regressiva que aparece a cada instalação. `flutter test integration_test` instala um app de teste separado, então a janela aparece de novo.
- **O Go não grava `SONAME` sozinho**: o hook passa `-extldflags=-Wl,-soname,libchatcore.so`. Não remover.
- O primeiro build Android baixa o Gradle (uma vez, alguns minutos).
- **Android corta a internet do app em segundo plano** (Xiaomi principalmente: `software caused connection abort`). Tudo que precisa ficar conectado com o app fora da tela depende do `ConnectionService`.
- **Nunca imprimir QR nem código de pareamento** (são senhas de uso único). O log de diagnóstico (`[wa]`, só `kDebugMode`) mostra só tipos de evento e códigos de erro.
- **`adb` perde o celular** (sobretudo depois de reconectar o cabo): `adb kill-server` e `ADB_LIBUSB=0 adb start-server`; se o celular pedir, aceitar "Permitir depuração USB".
- **`flutter run` em segundo plano** pode rodar fora de `app/` ("No pubspec.yaml"): usar `bash -c 'cd .../app && exec flutter run ...'`.
- **Hot restart com eventos ativos:** o Go pode chamar o ouvinte antigo antes de o novo ser registrado. Pare o que emite eventos (ex.: contador) antes de um hot restart.
- **Testes de tela com banco de verdade travam** (o tempo é simulado e o Drift roda noutro isolate): teste o banco em `test()` comum e a tela com callbacks.
- **Formulário em `ListView` com campos que aparecem e somem** (ex.: a linha de lucro): a lista preguiçosa casa os filhos pela posição, e o texto digitado vai parar em outro campo. Formulários dinâmicos usam `SingleChildScrollView` + `Column`.
- **Barra de navegação do Android por cima do fim da tela** (edge to edge; com 3 botões, 94 px no aparelho de referência): telas que rolam somam `MediaQuery.paddingOf(context).bottom` ao padding de baixo, ou os últimos botões não recebem o toque.
- **`image_picker` deixa arquivos no cache** (`<uuid>…jpg` da câmera, pasta `<uuid>/` da galeria e `scaled_…`): `cleanPhotoLeftovers()` apaga depois de cada foto e ao abrir o app. No Linux o arquivo escolhido é do usuário e não é apagado.
- **Janela (`showDialog`) com campo de texto:** o controlador tem de morar num `StatefulWidget` da própria janela. Descartá-lo logo depois do `await showDialog` quebra, porque a janela ainda se desenha enquanto fecha.
- **Formulário longo que o botão de voltar apaga:** use `PopScope` com confirmação quando houver algo preenchido (nova venda).
- **Teste com `| tail` antes do commit:** sem `set -o pipefail`, o `&&` segue mesmo com teste falhando.
- **Avisos na conversa:** use `aboveComposer` (flutuante, acima da caixa); o `SnackBar` comum cobre o microfone e o anexo.
- **Telas cheias com controles embaixo** (vídeo): `SafeArea`, ou os botões ficam atrás da barra de navegação.
- **Barra de progresso indeterminada em teste de tela:** ela anima sem parar e o `pumpAndSettle` estoura o tempo; use `pump()` com uma duração.
- **Digitar em janela pelo `adb`:** o teclado empurra os campos; liste de novo antes de cada toque, ou o toque cai noutro campo ou numa caixa de marcar (aconteceu no teste da 3.8).
- **Um `OpenContainer` (pacote `animations`) por linha pesa na rolagem** (medido no aparelho de referência). Para a linha que vira a ficha, use `OpenTile`/`GrowRoute`, que só leem a posição no toque.
- **Não crie animação em todo item de lista:** a conversa só anima as mensagens novas (`ChatController.fresh`).
- **`flutter drive` desinstala o app quando a instalação falha** (e a janela da Xiaomi às vezes cancela): isso apagaria a sessão e os dados. Para medir no aparelho:
  1. `flutter build apk --profile -t integration_test/scroll_perf_test.dart`;
  2. `adb install -r` e abrir o app;
  3. `flutter drive --driver=test_driver/perf_driver.dart --use-existing-app=<URL do serviço>` (o resultado vai para `build/integration_response_data.json`);
  4. no fim, reinstalar o app normal.
- **Medir desempenho:**
  - `PERF_ONLY=<clients|chat|chats>` mede um cenário só: numa execução longa, o aparelho esquenta e piora o que vem depois (a mesma lista variou de 3% a 10%);
  - `PERF_SEMANTICS=false` mede sem a árvore de acessibilidade, que o `testWidgets` liga por padrão e o aparelho de referência não usa;
  - o tempo de medir é limitado: medir uma ou duas vezes, corrigir o óbvio e registrar os números.
- **`ListTile` é pesado em listas longas:** ele refaz os textos para alinhar as linhas de base (de 2 a 3 ms por linha nova no aparelho de referência). Use `AppListTile`.
- **Nome + marca "cliente" numa linha:** use `Wrap`, não `Row`. Com a fonte em 200% a marca não cabe ao lado e estoura.
- **`scrollCacheExtent`** (que substitui o `cacheExtent`, descontinuado) precisa de `import 'package:flutter/rendering.dart' show ScrollCacheExtent;`.
- **Conferir uma tela antes do celular**: um teste temporário desenha a tela com as fontes reais e salva um PNG no scratchpad, que se olha como imagem:
  - fontes carregadas com `FontLoader`: as do app, `packages/material_symbols_icons/MaterialSymbolsRounded` e `MaterialIcons` do cache do Flutter;
  - a captura vem de um `RepaintBoundary` com `toImage` dentro de `runAsync`;
  - nunca commitar esse teste nem as imagens;
  - toda tela mexida é conferida inteira contra a pesquisa de layout.
- **Fonte grande:** `largeText(context)` (150% ou mais) decide os arranjos: o `AppListTile` põe o trecho da direita embaixo dos textos, pares de campos ficam um embaixo do outro e totais vão para duas colunas. O `MoneyText` nunca quebra (encolhe numa linha). Teste sem exceção não basta: palavra quebrando letra por letra não gera erro; olhe a imagem com a fonte em 200%.
- **Posição e largura em teste de tela:** a fonte de teste é mais larga que a do app (cada letra é um quadrado). Para conferir se algo cabe lado a lado, carregue as fontes do app com `FontLoader` no próprio teste (`test/sales_panel_test.dart`), num arquivo separado, para não mudar os outros testes.
- **Texto igual em dois lugares:** a aba "A receber" e o total "A receber" do cartão. Em teste, toque na aba com `find.widgetWithText(Tab, ...)`.
- **Cor "on" do contêiner no limite:** no esquema `fidelity`, o `onSecondaryContainer` fica perto de 4,5:1 e parece apagado em botão. Para rótulo de botão tonal, use `onSurface`.
- **Campo com máscara de dinheiro em teste:** `enterText` com "50" vira R$ 0,50. Digite "50,00" ou "5000".
- **Migração que recria tabela** (`TableMigration`): teste com um banco antigo montado pelo próprio teste. O `test/fixtures/app_db_v4.sql` tem o esquema v4. Para gerar o de uma versão, use `sqlite_master` de um banco novo.
- **`adb shell input text` em campo numérico ou de data:** o teclado pode engolir a vírgula e a barra. Use "9.90" e "13102026", que o app aceita.
- **`uiautomator dump` no Início mostra nomes e números de conversas:** filtre só os campos e botões que interessam (um script que imprime só `EditText` e os rótulos pedidos), nunca a árvore inteira.
- **120 Hz no aparelho de referência (Redmi):** a tela aceita, mas o sistema está em 60 Hz (configuração do aparelho). As metas valem a 60 Hz.
- **Cache corrompido depois de travamento:** erro `output.json contained a format error` → apague `.dart_tool/hooks_runner` (é só cache).

## Segurança

- Nunca usar `print`, `debugPrint` ou log com conteúdo de mensagens, números, nomes de contatos, chaves ou PIN.
- Nenhum pacote de analytics, crash reporting, anúncios ou nuvem (`firebase_*`, `sentry` e similares). Antes de adicionar qualquer pacote, alinhe com o responsável pelo projeto e confira se ele acessa a rede.
- O `app.db` liga `secure_delete` e `foreign_keys` em toda conexão (`applyKey`): apagar zera o espaço e leva junto as anotações e etiquetas.
- Dados só em `app.db` (SQLCipher + Drift) ou no cofre do sistema (`flutter_secure_storage`). Nunca em `SharedPreferences` ou em arquivo sem cifra. Nunca imprimir a chave do banco.
- Mídias só passam pela memória (`Image.memory`, `MediaDataSource`): nunca gravar mídia aberta em arquivo, cache de disco ou galeria. Exceções: a cópia do "abrir com" em `cache/open` (apagada no `onResume`/`onCreate`) e o "salvar no aparelho" pedido pelo usuário.
- O backup do Android fica desligado (`allowBackup="false"` e `res/xml/*_rules.xml`). Não religar.
- O app bloqueia captura de tela e a miniatura nos apps recentes (`FLAG_SECURE` no `MainActivity`). Não tirar.
- Nunca registrar PIN, chave nem o número de tentativas; o log `[lock]` (só `kDebugMode`) mostra só o estado.

## Comandos (dentro de app/)

```bash
flutter run -d linux                  # compila o Go e abre o app
flutter devices                       # id do celular conectado
flutter run -d <celular>              # instala e abre no celular
flutter test integration_test -d <celular>   # testes da ponte no aparelho
dart run tool/ffigen.dart             # regenera os bindings depois de mudar o chatcore.h
```

Conferir um APK de release (`flutter build apk --release`):

```bash
APK=build/app/outputs/flutter-apk/app-release.apk
unzip -l $APK | grep libchatcore                        # uma por arquitetura
~/Android/Sdk/ndk/*/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf -d <lib.so> | grep -i soname
~/Android/Sdk/build-tools/<versão>/zipalign -c -P 16 -v 4 $APK   # 16 KB
~/Android/Sdk/build-tools/<versão>/aapt2 dump permissions $APK   # hoje: nenhuma de sistema
```

**Inspeção no aparelho (Android).** Com o `FLAG_SECURE` ligado, o `screencap` sai preto. Para diagnosticar, use o log de depuração (`adb logcat -d | grep -E "\[lock\]|\[keys\]|\[wa\]|\[storage\]"`), que mostra só estados, nunca conteúdo. Para ver a tela sem desligar o `FLAG_SECURE`, use o inspetor do Flutter no APK de debug:
- **captura:** pegue a URL do serviço no log (`The Dart VM service is listening on …`), faça `adb forward` da porta e chame `ext.flutter.inspector.screenshot` (largura e altura grandes, `maxPixelRatio` 1); o `_flutter.screenshot` não funciona com o Impeller;
- **posições:** `uiautomator dump` lista os campos e botões do app com as posições (sem o conteúdo das fotos);
- **entrada:** `adb shell input text` (só ASCII; espaço é `%s`); para apagar, `keyevent 123` (fim) e vários `keyevent 67`. O teclado empurra os campos: liste de novo antes de cada toque;
- o PIN nunca é digitado por automação, e a galeria só recebe imagens de teste, apagadas depois.

Capturas de tela do aparelho nunca entram no repositório. Antes de capturar, confira que o app está na frente:

```bash
adb shell dumpsys activity activities | grep -m1 topResumedActivity   # br.com.garotodoprograma.chatdogaroto
adb shell cmd statusbar collapse    # a cortina de notificações pode estar por cima
adb exec-out screencap -p > /tmp/tela.png
```

Para atualizar o app no aparelho **sem perder sessão e conversas**: `adb install -r build/app/outputs/flutter-apk/app-debug.apk` (o `flutter run` desinstala quando a instalação falha). **Depois, abra o app** (`adb shell am start -n br.com.garotodoprograma.chatdogaroto/.MainActivity`): a instalação encerra o processo, e o Android não religa o serviço nesse caso. A janela "Instalar" da Xiaomi às vezes fecha sozinha (até em 0,3 s) e a instalação volta "canceled by user"; tente de novo.

Antes do commit:

```bash
dart format .
flutter analyze   # zero avisos
flutter test      # inclui testes contra a biblioteca Go real
```
