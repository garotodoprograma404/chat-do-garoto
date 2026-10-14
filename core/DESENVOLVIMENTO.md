# core/ — motor em Go (whatsmeow) exportado para o Flutter

Biblioteca Go compilada com `-buildmode=c-shared` (`libchatcore`) e carregada pelo app via `dart:ffi`. As regras gerais estão em `../CONTRIBUINDO.md`.

## Organização

| Caminho | O que é |
| --- | --- |
| `include/chatcore.h` | **Contrato da ponte**, escrito à mão. O cgo o inclui (divergência com o Go falha o build) e o `ffigen` gera os bindings Dart a partir dele. |
| `cmd/chatcore/` | A API C: `package main` (exigência do `c-shared`) com as funções `//export`. Fino: só converte tipos e delega. |
| `internal/bridge/` | Envelope JSON versionado, captura de `panic` (`bridge.Call`) e contador de strings pendentes. Go puro, testável. |
| `internal/events/` | `events.Hub`: entrega eventos ao app pelo ouvinte registrado. |
| `internal/wa/` | Sessão do WhatsApp (whatsmeow): `Start`, `Resume`, `PairCode`, `Logout`, `Stop`, `Reset`; tradução dos eventos (`translate.go`), diagnóstico mascarado (`diag.go`) e `wa.db` cifrado (`migrate.go`: chave, conversão do banco sem cifra, `unreadable`). |
| `internal/vault/` | Cofre de mídias: arquivos no formato age (`filippo.io/age`), nomes em SHA-256, gravação atômica, decifra só na memória, `Clear`. A identidade fica em `cc_settings` do `wa.db` (`wa/media.go: openVault`). |
| `internal/pinseal/` | Envelope do PIN: Argon2id (`golang.org/x/crypto`) + AES-256-GCM, parâmetros e sal no cabeçalho autenticado; recusa parâmetros absurdos. Lento de propósito: o Dart chama `cc_pin_seal`/`cc_pin_open` noutro isolate. |
| `internal/imgprep/` | Foto para enviar: aplica a orientação do EXIF, reduz a 1600 px, regrava JPEG sem metadados (GPS some) e faz a miniatura de 100 px. |
| `internal/wa/media_send.go`, `forward.go` | Envio de mídia: guarda no cofre, sobe uma vez só (o proto fica salvo para o "tentar de novo") e envia; `Forward` reenvia texto ou mídia com a marca de encaminhada (do cofre sobe de novo; senão reaproveita o proto). O envio passa pela interface `deliverer`, falsa nos testes. |
| `internal/msgstore/` | Conversas e mensagens nas tabelas `cc_*` do `wa.db`. Busca: `cc_messages_fts` (FTS4 com `remove_diacritics=2`, conteúdo externo por `rowid`, gatilhos BEFORE para apagar); `Search` monta a consulta com prefixos entre aspas. **Nunca dar VACUUM** no `wa.db` sem reconstruir o índice. O FTS5 exigiria a tag `sqlite_fts5` no driver; por isso FTS4. A conversão do banco sem cifra (`migrate.go`) derruba o índice antes do `sqlcipher_export` (que não copia tabelas virtuais) e ele é refeito ao abrir. Mídias: `cc_media` com `file_name`, `mime`, `size`, `seconds`, `ptt`, e `cc_messages.forwarded`; o índice de busca é refeito no `Open` sempre que falta. migração versionada, gravação em lote sem duplicar, listas paginadas, `Clear`. Estado de entrega das minhas mensagens (v2): `SetStatus` só avança e acha a mensagem pelo ID; `FailPending` na abertura. `ListChats` devolve `last_from_me`, calculado na leitura pela última mensagem (índice `(chat_jid, ts)`), sem coluna nova; uma conversa sem mensagens conta como minha. |
| `internal/wa/delete.go` + `internal/msgstore/delete.go` | Exclusão real: `DeleteChat` (opção de apagar para todos as minhas mensagens das últimas 60 h, até 50, espaçadas), `DeleteForMe`, `RevokeForEveryone` (minha, enviada, < 60 h, com conexão). Apaga no `wa.db` (v7) e no cofre (`Vault.Delete`), compacta o FTS (`optimize`) e esvazia o diário (`wal_checkpoint(TRUNCATE)`); o `wa.db` abre com `_secure_delete=on`. O WhatsApp recebe por app state (`deleteChat` até o momento da exclusão, `deleteMessageForMe`), pela fila `cc_pending_sync` (só identificadores), mandada a cada `Connected`. Aplica o que vem do celular (`events.DeleteChat`, `ClearChat`, `DeleteForMe`, REVOKE), com LID e telefone (`candidates`). |
| `internal/backup/` + `internal/wa/backup.go` + `internal/msgstore/backup.go` | Backup: `backup.Write`/`Extract` (age com senha, scrypt 2^18, + tar com `manifest.json`, `app.db`, `wa.db`, `media/`; nomes conferidos; lê até o fim, para o age autenticar o último bloco). `ExportTo` cria a cópia das conversas vazia, na versão atual, e copia só as linhas (`cc_chats`, `cc_messages`, `cc_media`, `cc_settings`); `ImportFrom` migra uma cópia antiga e troca tudo numa transação. O descritor do arquivo vem do Android e o Go o fecha. Na restauração, o cofre reabre com a identidade do backup (`Vault.Replace`); sem mídias, `ForgetMedia`. |
| `internal/demo/` | Contador de demonstração dos eventos da ponte. |
| `cmd/chatcore/trampoline.go` | Função C que chama o ponteiro do ouvinte (o preâmbulo de arquivo com `//export` não aceita definições). |
| `internal/...` | A lógica de verdade (WhatsApp etc.), em pacotes Go comuns, testáveis sem cgo. |

- O módulo é `chatdogaroto/core`. O `go.work` na raiz do repositório existe para o `gopls` (o servidor de linguagem do editor) enxergar o módulo.
- Não é preciso compilar à mão: o `app/hook/build.dart` compila a biblioteca a cada `flutter run`, `build` ou `test`.

## Como adicionar uma função à ponte

1. Declare a função em `include/chatcore.h`, com o prefixo `cc_` (obrigatório: a biblioteca só exporta `cc_*` e `Java_*`, pelo `cmd/chatcore/exports.map`) e o comentário de dono da memória. Parâmetros de texto são `char *` (o cgo não exporta `const`).
2. Implemente em `cmd/chatcore/` com `//export`, envolvendo o corpo em `bridge.Call`, e devolva a resposta com `toC`.
3. Em `app/`, rode `dart run tool/ffigen.dart` e exponha a função pelo `CoreBridge` (nunca direto nas telas).
4. Teste o lado Go em `internal/` e o lado Dart nos casos compartilhados (`app/test/core_bridge_cases.dart` ou `core_events_cases.dart`), que rodam no Linux e no celular.

## Como emitir um evento para o app

- Use o `hub` de `cmd/chatcore` (repasse um `*events.Hub` aos pacotes internos): `hub.Emit("tipo", dados)`. Pode ser chamado de qualquer goroutine e não bloqueia.
- O evento sai como `{"v":1,"type":...,"data":...}` e só é entregue se houver ouvinte; sem ouvinte, é descartado.
- Eventos de uma mesma goroutine chegam na ordem em que foram emitidos.
- Funções que param tarefas (como `ticker.Stop`) só retornam quando nenhum evento delas pode mais sair.
- Nunca emitir conteúdo sensível para log; o evento vai só para o app.

## Regras da ponte (FFI)

- Toda função exportada passa por `bridge.Call`, que converte `panic` em erro `internal`. Nenhum `panic` atravessa a ponte.
- **Mensagens de erro:** só erros do tipo `*bridge.Error` levam a mensagem até o app. Qualquer outro erro vira `internal` com mensagem genérica, porque erros comuns podem conter dados do usuário.
- **Memória:** toda string devolvida é alocada em C (`toC`) e liberada pelo app com `cc_free`. O `cc_live_allocs` conta as pendentes e os testes exigem que volte a zero.
- Nunca guardar ponteiro Go do lado C/Dart, nem guardar ponteiro recebido do Dart depois que a chamada retorna (regras de ponteiros do cgo).
- Chamadas vindas do Dart não bloqueiam: rede e disco rodam em goroutines, e o resultado volta como evento.
- Mídia atravessa a ponte como bytes por ponteiro e tamanho: `cc_media_read` entrega o binário decifrado e o Dart o libera com `cc_bytes_free`; `cc_media_send(chat, meta, data, len)` recebe a mídia. Nunca em JSON/base64 (só a miniatura vai assim).
- Goroutines e conexões recebem um `context` e param na função de desligamento exportada.
- Todo o Go fica nesta única biblioteca: só um runtime Go funciona bem por processo.

## WhatsApp (whatsmeow)

- **Nunca chamar métodos de rede do whatsmeow (`Disconnect`, `Logout`, `Connect`…) segurando a trava da `Session`.** Eventos como `LoggedOut` chegam de dentro das goroutines do whatsmeow, e `Disconnect` espera essas goroutines: segurar a trava causa deadlock (aconteceu na 1.4). Padrão: `detachLocked()` sob a trava e `shutdown()` fora dela.
- Eventos de um cliente já descartado são ignorados (`handle` compara com `s.client`).
- Mensagens: `extract` decide o que guardar (texto, legenda, marcadores; ignora status, reações, edições e mensagens técnicas). As ao vivo viram `wa_message`; o histórico vira lotes e `wa_history`. Desconectar apaga as mensagens (`msgstore.Clear`).
- Conversas sob LID (identificador privado) são nomeadas pelo telefone por trás delas (`Store.LIDs.GetPNForLID`). `AutomaticMessageRerequestFromPhone` pede ao celular as mensagens que chegam "indisponíveis".
- Fotos: ao receber uma `ImageMessage` (ao vivo e do histórico), a miniatura vai para o cofre e os dados de download (sem a miniatura) para `cc_media`. `DownloadMedia` só roda quando o app pede (toque do usuário), emite `wa_media`; 404/410 viram `expired` e não são tentados de novo. Desconectar limpa o cofre e a identidade.
- Envio: `SendText` grava como `sending` e devolve na hora; o `SendMessage` roda numa goroutine, **fora do lock**, e termina em `wa_message_status`. O reenvio (`Retry`) usa o **mesmo ID**, para não duplicar no destinatário. **Nunca reenviar sozinho** (sem fila, sem repetição automática): o que estava `sending` quando o app parou vira `failed`. As confirmações (`events.Receipt`) de contatos atualizam o estado; as dos meus aparelhos são ignoradas.
- **REVOKE é o valor zero** do enum `ProtocolMessage_Type`: `GetType()` de uma mensagem sem tipo devolve REVOKE. Confira `pm.Type != nil` antes.
- **Excluir conversa no WhatsApp:** o horário guardado das mensagens enviadas pelo app é o do celular, um instante antes do do servidor; por isso o `deleteChat` vai "até agora" (o celular mantinha a conversa com o horário da última mensagem).
- **`sqlcipher_export` leva o índice FTS e os gatilhos**, e `DROP TRIGGER bk.x` num banco anexado não teve efeito. Para copiar só parte do `wa.db`, crie a cópia vazia com `msgstore.Open` e copie as linhas.
- O app **não envia** confirmação de leitura nem presença. Não chamar `MarkRead`/`SendPresence` sem um requisito que peça isso.
- `PairPhone` só depois do primeiro QR (`qrReady`); o nome exibido é `DisplayName` ("Chrome (Linux)"), e o WhatsApp mostra "Google Chrome (Linux)".
- O log do whatsmeow fica desligado. O diagnóstico (`cc_wa_diagnostics`, só em build de desenvolvimento) troca toda sequência de 6+ dígitos por `<num>`.
- Licença: o whatsmeow traz o `go.mau.fi/libsignal` (GPL-3.0): quem distribuir o app deve cumprir a licença.

## Segurança

- O logger do whatsmeow é configurado para não registrar conteúdo de mensagens, números nem chaves. Em release, o nível mínimo é `WARN`.
- A sessão do whatsmeow e as mensagens ficam em `wa.db`, cifrado com SQLCipher pelo driver `github.com/WissCore/go-sqlcipher/v4`. A chave chega pela ponte (64 hex) e vai na DSN (`_pragma_key`): **nunca logar a DSN nem ecoar a chave em erros.** Testes que abrem banco sem chave continuam funcionando (o driver abre arquivo sem cifra). Nunca em arquivo versionado.
- Não modificar arquivos do whatsmeow (licença MPL-2.0).
- O build usa `-trimpath`, para que nenhum caminho da máquina de quem compilou vá dentro do binário.

## Antes do commit (dentro de core/)

```bash
gofmt -l .        # não pode listar nada
go vet ./...
go test ./...
```

Para inspecionar a biblioteca à mão (Linux):

```bash
go build -buildmode=c-shared -o /tmp/libchatcore.so ./cmd/chatcore
nm -D --defined-only /tmp/libchatcore.so | grep " cc_"
```
