# rules.md — Diretrizes de trabalho

Diretrizes pra reduzir erros comuns de LLM em código. Combinar com as
instruções específicas do projeto em `CLAUDE.md`.

**Tradeoff:** estas diretrizes priorizam cautela sobre velocidade. Pra
tarefas triviais, use bom senso.

## 1. Pensar antes de codar

**Não suponha. Não esconda confusão. Exponha tradeoffs.**

Antes de implementar:
- Declare suas suposições explicitamente. Se incerto, pergunte.
- Se há múltiplas interpretações, apresente-as — não escolha em silêncio.
- Se existe um caminho mais simples, diga. Discorde quando fizer sentido.
- Se algo está confuso, pare. Nomeie o que confunde. Pergunte.

## 2. Simplicidade primeiro

**Código mínimo que resolve o problema. Nada especulativo.**

- Nenhuma feature além do que foi pedido.
- Nenhuma abstração pra código de uso único.
- Nenhuma "flexibilidade"/"configurabilidade" que não foi pedida.
- Nenhum tratamento de erro pra cenário impossível.
- Se escreveu 200 linhas e dava pra fazer em 50, reescreva.

Pergunte: "um engenheiro sênior diria que isso está complicado demais?"
Se sim, simplifique.

## 3. Mudanças cirúrgicas

**Toque só no necessário. Limpe só a sua própria bagunça.**

Ao editar código existente:
- Não "melhore" código, comentário ou formatação adjacente.
- Não refatore o que não está quebrado.
- Siga o estilo existente, mesmo que você fizesse diferente.
- Código morto não-relacionado: mencione, não apague.

Quando suas mudanças criam órfãos:
- Remova imports/variáveis/funções que AS SUAS mudanças deixaram sem uso.
- Não remova código morto pré-existente sem pedir.

Teste: cada linha alterada deve rastrear direto ao pedido do usuário.

## 4. Execução guiada por objetivo

**Defina critério de sucesso. Repita até verificar.**

- "Adicionar validação" → "escrever testes pra inputs inválidos, depois
  fazer passar".
- "Corrigir o bug" → "escrever um teste que reproduz, depois fazer passar".
- "Refatorar X" → "garantir que os testes passam antes e depois".

Pra tarefas multi-passo, declare um plano breve:
```
1. [passo] → verifica: [checagem]
2. [passo] → verifica: [checagem]
```
Critério forte deixa você iterar sozinho; critério fraco ("faz funcionar")
exige clarificação o tempo todo.

## 5. Verificar antes de afirmar — separar o que você VIU do que DEDUZIU

O erro mais perigoso não é não saber algo; é **afirmar como fato algo que
você só deduziu**.

> Aconteceu nesta sessão: afirmei "o token do agy está em arquivo, o
> keychain é só auxiliar e não é necessário". Eu tinha **visto** um arquivo
> de token e o login funcionar — mas **deduzi** a relação causal sem testar.
> Uma investigação depois mostrou que a credencial real é o keychain (slot
> global único) e o arquivo só funciona por fallback. A afirmação foi pra
> documentação como fato, e estava errada.

Regras pra não cair nisso:
- **Distinga observação de conclusão.** "Vi um arquivo de token + o login
  funcionou" (observação) ≠ "o arquivo é a credencial" (conclusão). A
  conclusão foi além da evidência.
- **Afirmação que sustenta uma recomendação ou que vai pra doc precisa ser
  testada ANTES**, não depois. Se não dá pra testar barato, escreva como
  hipótese: "observei X; infiro Y — **não verificado**".
- **Para afirmar "Z não é necessário", o teste é remover Z e ver se ainda
  funciona.** Não conclua de ausência de evidência ("não vi o keychain ser
  usado" ≠ "o keychain não é usado").
- **A documentação herda o nível de confiança.** Se é inferência, escreva
  como inferência. Não promova hipótese a fato no papel.
- Gatilho mental: ao escrever uma frase causal confiante ("X porque Y", "Z
  não importa"), pergunte-se: **"isso eu vi ou deduzi? dá pra testar em 1
  comando?"** Se deduziu e dá pra testar barato, teste antes de afirmar.

## 6. Evidência antes de "pronto"

Não diga "funciona / corrigido / passa" sem ter rodado o comando e visto a
saída. Se não rodou, diga que não rodou. Se um teste falhou, mostre a saída.
Afirmações de sucesso vêm depois da evidência, nunca antes.

---

**Estas diretrizes estão funcionando se:** menos mudanças desnecessárias nos
diffs, menos reescritas por excesso de complexidade, e as perguntas de
clarificação vêm antes da implementação — não depois do erro.
