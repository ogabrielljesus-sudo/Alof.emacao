# Mentoria alof.emacao

Plataforma independente para GitHub + Netlify, com integração Supabase Auth, PostgreSQL e Storage.

## Estado desta entrega

- Página pública, feedbacks fornecidos, planos e WhatsApp implementados.
- Áreas administrativa e do aluno implementadas.
- Editor de ciclo por horas, quantidade de matérias e duração, com blocos editáveis e publicação manual.
- Dois editais importados dos verticalizados fornecidos: 178 tópicos de Soldado e 188 de CFO.
- Registros externos, desempenho ponderado, filtros, histórico, observações e alertas implementados.
- Questões com grifos e anotações; cadastro administrativo com gabarito privado.
- Materiais por upload privado de até 50 MB ou link; simulados com correção por função de banco.
- Supabase conectado ao projeto `MENTORIA ALOF.EMACAO`: tabelas, regras de acesso e bucket privado provisionados em 11/09/2026.
- Configuração pública incluída no site. O build Netlify a preserva quando não há variáveis de ambiente para substituí-la.
- Gerador com seleção por edital, marcação de matérias e períodos de 1 a 365 dias (30 por padrão).
- Testes de ciclos de 30, 60 e 365 dias e verificações de sintaxe executados. `tests/permissions.sql` passou no Supabase, com perfis temporários e rollback, verificando isolamento de alunos e acesso por plano.
- Cadastro por e-mail habilitado no projeto, com confirmação de e-mail ainda ligada. Conta do administrador e fluxo completo de cadastro/login precisam ser concluídos pelo proprietário com senha nova.
- O repositório pode ser conectado à Netlify para a publicação definitiva.
- Não há área de redação. Os tópicos de redação oficial presentes na disciplina Português do edital foram preservados.

## 1. Configuração Supabase

O projeto atual já foi conectado e o script já foi aplicado. NÃO execute novamente os passos 1–3 nele. Esses passos servem apenas para uma instalação nova.

1. Acesse https://supabase.com/dashboard e crie sua conta.
2. Crie um projeto chamado `mentoria-alof-emacao`. Escolha região próxima aos alunos e guarde a senha do banco em local seguro. Não envie a senha ao chat.
3. No SQL Editor, execute o conteúdo de `supabase/setup.sql` UMA VEZ, em um projeto novo. O script cria tabelas, permissões e o bucket privado `materials`.
4. Em Authentication, mantenha o provedor Email habilitado. Se quiser dispensar a confirmação por e-mail, desative `Confirm email`. Isso não dispensa o login por senha nem a liberação manual do mentor.
5. Em Authentication > URL Configuration, configure a URL da Netlify como Site URL e inclua `https://SEU-SITE.netlify.app/**` na lista de redirecionamento, substituindo pelo endereço exato do seu site. Não use liberação universal `**` para qualquer domínio.
6. Para recuperação de senha de alunos em produção, configure SMTP próprio. O serviço padrão de e-mail do Supabase é limitado e voltado a testes. Não considere recuperação operacional antes de testá-la.

## 2. Criar o administrador com segurança

Não existe senha embutida, padrão ou conta administrativa automática.

1. Dentro do painel autenticado do Supabase, em Authentication > Users, crie o usuário que será administrador e uma senha exclusiva de pelo menos 12 caracteres.
2. Confirme que é a conta criada por você. Copie o UUID dessa conta, não apenas o e-mail de um cadastro público.
3. No SQL Editor, substitua o UUID abaixo e execute:

```sql
update public.profiles
set role = 'admin', active = true, plan = 'Estratégico', name = 'Mentor alof.emacao'
where id = 'UUID-DA-CONTA-ADMINISTRATIVA'::uuid;
```

4. Entre no site usando o e-mail e a nova senha. A área administrativa aparece pelo papel salvo no banco, não pelo texto do e-mail.

Não promova automaticamente qualquer pessoa que se cadastre com esse endereço. Não há atribuição de administrador baseada em metadados do navegador.

## 3. Publicar no GitHub e Netlify

1. Use o repositório `ogabrielljesus-sudo/Alof.emacao`, preservando `dist`, `scripts`, `supabase`, `tests`, `netlify.toml` e `package.json`. Não envie senhas nem arquivos `.env`.
2. A pasta `.openai` identifica somente a prévia no Sites; não é necessária para a Netlify.
3. Na Netlify, importe esse repositório do GitHub.
4. A conexão pública já está incluída. Para usar outro projeto, substitua ambas as variáveis de ambiente de build:

| Nome | Valor |
|---|---|
| `SUPABASE_URL` | URL HTTPS do projeto Supabase |
| `SUPABASE_PUBLISHABLE_KEY` | Chave publicável (`sb_publishable_...`) ou chave `anon` legada |

5. Nunca use `service_role`, `sb_secret_...` ou senha do banco no site. A chave publicável não é um segredo: a proteção dos dados é feita pelo login e pelas políticas RLS.
6. A Netlify usa automaticamente o comando `node scripts/configure-netlify.mjs` e publica a pasta `dist`.
7. Volte à configuração de URLs no Supabase e confira os endereços de login e recuperação após a publicação.

O código do site fica no GitHub; os dados dos alunos e os arquivos privados ficam no Supabase. Nada é salvo no repositório quando um aluno registra questões.

## 4. Usar a plataforma

1. Aluno cria a conta pelo próprio site.
2. A conta nasce BLOQUEADA no plano Básico.
3. Mentor abre **Alunos e acessos**, confirma a contratação e libera o plano e concurso corretos.
4. Mentor abre **Ciclos de estudos**, escolhe aluno, data, dias, horas e matérias; gera a sugestão e preenche os assuntos. Pode salvar rascunho ou publicar.
5. Ambos os planos registram estudo e resultados de questões externas. Acertos nunca podem ultrapassar o total.
6. Apenas Estratégico acessa questões, caderno de erros, vídeos, materiais e simulados. A restrição é aplicada também no banco.
7. O mentor vê os registros e pode adicionar históricos anteriores. Notas desmarcadas como visíveis ficam restritas ao mentor.
8. Alertas: três ou mais dias sem registros; queda de pelo menos dez pontos percentuais comparando últimos sete dias com sete anteriores, com mínimo de vinte questões em cada período.
9. Questões: de duas a cinco alternativas; comentário/gabarito ficam em schema privado. Grifos e anotações só são salvos quando o aluno confirma. Anotações privadas não são exibidas a outros alunos nem ao mentor.
10. Cada envio de resposta avulsa representa uma nova resolução e entra no desempenho. Simulado é corrigido uma única vez por tentativa.

## Limitações e validação antes de receber alunos

- O gerador é determinístico por horas e rodízio de matérias, não uma inteligência artificial pedagógica. O mentor deve ajustar dificuldades, frequência e assuntos antes de publicar.
- A duração diária inicial é uniforme. Depois de gerar, cada bloco pode ter data e duração próprias para ajustar a disponibilidade por dia.
- O conteúdo dos editais foi transcrito dos arquivos de preparação enviados, sem atualização normativa automática.
- Materiais por link externo continuam sujeitos às permissões do provedor externo. Use upload no bucket privado para exigir o plano no acesso. Links assinados de arquivos expiram após cinco minutos, mas um aluno pode guardar o arquivo baixado.
- Vídeos são abertos pelo link/arquivo; não há streaming com transcodificação.
- A sessão é mantida em memória; atualizar a página exige novo login. Dados confirmados no Supabase permanecem salvos. Não feche a página durante um simulado.
- Simulados têm prazo no servidor. O envio automático no prazo depende da aba estar aberta e conectada; uma tentativa expirada sem envio não gera nota. Não há retomada de simulado nesta versão.
- Não há checkout, cobrança automática ou integração com QConcursos/TecConcursos. Contratação pelo WhatsApp e registros externos manuais.
- Enunciados e comentários de terceiros só devem ser publicados com autorização para reutilização.
- Não houve teste visual em navegador nem validação WebMCP em contexto suportado; não solicitados nesta etapa.

Antes de uso real, crie dois alunos de teste (Básico e Estratégico) e valide:

- Básico não lê questões, recursos, simulados ou erros, inclusive pela API.
- Aluno A não lê nem altera registros de B.
- Cadastro público não altera role, plano ou active.
- Rascunhos não aparecem ao aluno.
- Gabaritos não são lidos diretamente pela API.
- Novo cadastro, login, recuperação, upload e download funcionam no domínio definitivo.
- Envio repetido da mesma tentativa de simulado não duplica a nota nem os registros.

## Verificações locais sem dependências

```sh
node --test tests/domain.test.mjs
node --check dist/app.js
node --check dist/api.js
```

## Referências oficiais

- https://supabase.com/docs/guides/auth/passwords
- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/docs/guides/storage/security/access-control
- https://docs.netlify.com/build/configure-builds/environment-variables/
