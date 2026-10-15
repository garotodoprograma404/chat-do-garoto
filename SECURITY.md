# Política de segurança

O Chat do Garoto guarda conversas e dados de clientes, então segurança é requisito central. Agradecemos o relato responsável de vulnerabilidades.

## Como relatar

**Não abra uma issue pública** para um problema de segurança. Use o relato privado do GitHub:

[Relatar uma vulnerabilidade](https://github.com/garotodoprograma404/chat-do-garoto/security/advisories/new)

Inclua, se possível: a versão ou o commit, os passos para reproduzir, o impacto esperado e, se tiver, uma sugestão de correção. Não inclua dados reais de clientes ou conversas.

## O que consideramos relevante

- Vazamento de mensagens, números, nomes, chaves, PIN ou senhas (em disco, log, memória persistida ou rede).
- Falhas na cifra dos bancos (`app.db`, `wa.db`), das mídias ou do backup.
- Contorno do bloqueio por PIN ou biometria.
- Qualquer conexão de rede além da prevista (WhatsApp e consulta de CEP disparada pelo usuário).

Fora do escopo: limitações do próprio protocolo do WhatsApp e a política da empresa sobre clientes não oficiais (veja o aviso no [`README.md`](README.md)).

## Versões com suporte

O projeto está em desenvolvimento ativo; correções de segurança são feitas na branch `main`.

## Prazos

Confirmamos o recebimento em até 7 dias e mantemos o relator informado até a correção. Pedimos que a divulgação pública aguarde a correção estar disponível.
