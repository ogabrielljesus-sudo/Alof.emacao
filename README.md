# Mentoria alof.emacao

Plataforma estática para GitHub, Netlify e Sites, com dados e autenticação no Supabase.

## Recursos

- Ciclos de 1 a 365 dias, exibidos como Dia 01 em diante. Cada dia permite quantidade, matérias, minutos e observações próprios.
- Assuntos vinculados ao edital do aluno ou opção “Seguir edital verticalizado”. Renovação e continuação criam ciclos separados e preservam o histórico.
- Panorama por aluno com estudo, resumo, questões, revisão e lista dos assuntos estudados.
- Registro de questões externas com observações, desempenho e filtros.
- Caderno de erros com edição, negrito, itálico, sublinhado, destaque e listas. A formatação é renderizada com HTML escapado.
- Simulados numerados, questões novas ou do banco, gabarito comentado, resultados e comentários compartilhados. O mentor pode moderar comentários e excluir simulados; as questões ficam no banco.
- Materiais e vídeos, histórico e alertas de acompanhamento.
- Básico: ciclos, edital, panorama, registros e desempenho. Estratégico: todos os recursos. Sem redação na plataforma.

## Contas

O cadastro usa a Edge Function `mentor-accounts`, que cria contas de aluno sem envio de e-mail, com senha entre 8 e 128 caracteres. Toda conta começa bloqueada e no Básico. A liberação continua sendo feita pelo mentor.

“Esqueci a senha” registra um pedido no painel **Alunos e acessos**. O mentor verifica o aluno pelo contato conhecido e define uma nova senha, sem envio automático de mensagens. A função valida a sessão e o perfil administrativo no servidor.

O administrador também pode excluir alunos. Há confirmação na interface; a exclusão remove a conta e os registros relacionados. Nenhuma conta administrativa pode ser excluída por essa função.

Cadastro e pedidos de recuperação têm limite de cinco tentativas por IP e e-mail em 15 minutos, armazenado no banco. As chaves de limitação são hashes. A chave privilegiada existe apenas no ambiente da função.

## Implantação

O projeto atual já está provisionado. Não reaplique o script inicial nele.

Para uma instalação nova:

1. Execute `supabase/setup.sql` uma única vez.
2. Aplique as migrações em `supabase/migrations/`, em ordem.
3. Publique `supabase/functions/mentor-accounts/index.ts` com `verify_jwt=false`. Os fluxos públicos são cadastro e solicitação de recuperação; operações administrativas validam o token e o papel internamente. As variáveis `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` são fornecidas pelo Supabase.
4. Configure a URL e a chave pública em `dist/config.js`, ou pelas variáveis de build descritas em `.env.example`. Nunca coloque a chave privilegiada no frontend.
5. Crie e confirme o usuário administrador no Supabase e atribua `role='admin'`, `active=true` e `plan='Estratégico'` ao UUID verificado dessa conta em `public.profiles`.
6. Na Netlify, o build é `node scripts/configure-netlify.mjs` e a pasta publicada é `dist`.

## Verificação

`npm test` verifica ciclos, dias numerados, continuação, formatação segura, panorama e a regressão do login. `tests/mentor-controls.sql` verifica permissões, correção de simulados, comentários, observações e exclusões com rollback.

`tests/accounts.integration.mjs` é executado explicitamente com a variável `MENTORIA_ADMIN_PASSWORD`. Cria e remove uma conta temporária para verificar cadastro sem e-mail, senha de oito caracteres, recuperação pelo mentor e exclusão. Não contém senhas reais.

## Limites atuais

- O gerador sugere uma distribuição determinística; o mentor define prioridades pedagógicas antes de publicar.
- As datas continuam armazenadas internamente para a tarefa do dia e o calendário; a edição dos ciclos é apresentada por número do dia.
- A sessão fica em memória. Atualizar a página exige novo login. Os dados confirmados permanecem no Supabase.
- O simulado exige a aba aberta e conectada até o envio. Não há retomada de tentativa nesta versão.
- Contratação e entrega da nova senha são combinadas pelo WhatsApp. Não há cobrança automática nem importação automática de questões de terceiros.
- Os editais são os arquivos fornecidos pelo mentor, sem atualização normativa automática.
