# maqpilares

Rotina em AutoLISP para automatizar a correção dos desenhos de **armação de
pilares** exportados do CYPECAD, dentro do AutoCAD e do ZWCAD.

O comando único `maqpilares` roda todas as etapas de correção em cima de uma
área que você seleciona no desenho.

---

## Índice

- [Instalação](#instalação)
- [Como usar](#como-usar)
- [O que a rotina faz](#o-que-a-rotina-faz)
- [Configuração](#configuração)
- [Contexto: o desenho que ela corrige](#contexto-o-desenho-que-ela-corrige)
- [Decisões técnicas](#decisões-técnicas)
- [Limitações](#limitações)
- [O que ainda não está automatizado](#o-que-ainda-não-está-automatizado)
- [Compatibilidade](#compatibilidade)
- [Estrutura do código](#estrutura-do-código)

---

## Instalação

### Carregar uma vez

1. No AutoCAD ou ZWCAD, digite `APPLOAD`
2. Selecione `maqpilares.lsp`
3. Clique em **Carregar**

### Carregar sempre que abrir o CAD

Na mesma janela do `APPLOAD`, arraste o arquivo para a caixa
**Inicialização / Startup Suite**. Assim ele fica disponível em todo desenho
que você abrir.

---

## Como usar

```
Command: maqpilares
```

O comando pede **uma** seleção e roda todas as etapas nela:

```
--- maqpilares ---

  Selecione a area do desenho a corrigir
  (janela ou cerca; o script decide o que mexer dentro dela)
Select objects: [faça a janela]

  1240 objetos na area.

  [1] Layers de rotina
      [ok]       CORTE_NOMES_DAS_PLANTAS  (28 objetos, layer removida)
      [parcial]  CORTE_PISOS  (98 objetos apagados, restam 98 fora da area)
      -> 126 objetos apagados, 1 layers removidas

  [2] Textos a apagar pelo conteudo
      24N[1]-%%c20
      8N[1]-%%c20
      Escala vertical   1:50
      Escala horizontal 1:25
      ... e mais 22
      -> 26 textos apagados

  [3] Estilo de texto -> ROMANS
      CYPETXT_romans -> ROMANS  (23 textos)
      -> 23 textos trocados, 267 ja estavam em ROMANS

  [4] Altura de texto
      12.6667 -> 18.0000  (7 textos)
      13.3333 -> 12.5000  (159 textos)
      outras alturas encontradas (sem regra):
        10.0000 (226)  12.3333 (14)  18.0000 (7)  12.5000 (10)
      -> 166 alturas trocadas

  [5] Espacamento nas anotacoes
      N2-%%c5c/18c=444   ->   N2-%%c5 c/18 c=444
      N1-24%%c20c=380   ->   N1-24%%c20 c=380
      ...
      -> 31 textos ajustados

  [6] Fator de largura -> 0.9000
      larguras originais entre 0.7213 e 1.1565
      -> 614 textos ajustados, 539 ja estavam em 0.9000
      37 MTEXT nao alterados (fator de largura de MTEXT vem do estilo)

  Concluido.
```

**Não precisa de pontaria na seleção.** Pode passar uma janela larga por cima
de tudo: cada etapa filtra internamente o que lhe interessa e ignora o resto
do desenho.

---

## O que a rotina faz

### Etapa 1 — Apaga as layers de rotina

Layers que sempre saem do CYPE e nunca são aproveitadas:

| Layer | O que é |
|---|---|
| `CORTE_NOMES_DAS_PLANTAS` | nome do pavimento |
| `CORTE_TEXTO_DAS_ELEVACOES_DOS_PILARES` | nome das vistas |
| `CORTE_COTAS_DAS_LAJES` | níveis intermediários |
| `CORTE_SEGMENTOS_DE_CORTE_DE_SECOES` | nome da seção |
| `CORTE_PISOS` | sombra |

Apaga o conteúdo que estiver **dentro da área selecionada**. O registro da
layer só é removido do desenho se, depois disso, não sobrar nada dela em
nenhum outro lugar.

O relatório distingue três situações por layer:

| Marca | Significado |
|---|---|
| `[ok]` | limpou e a layer ficou vazia — registro removido |
| `[parcial]` | limpou a área, mas ainda há conteúdo fora dela |
| `[-]` | não havia nada dessa layer na área selecionada |

### Etapa 2 — Apaga textos pelo conteúdo

Apaga **o texto inteiro** de toda entidade cujo conteúdo contenha um dos
trechos de `PL:APAGAR-SE-CONTEM`.

| Trecho | Alvo | No desenho modelo |
|---|---|---|
| `[` e `]` | numeração local do CYPE: `50N[1]-%%c25`, `10N[2]-%%c20` | 24 textos, em `PILCPSECC_ARM_LONG_REFERENCIA` |
| `Escala vertical` | `Escala vertical   1:50` | 14 textos, em `CORTE_TITULO_DA_TABELA_DE_DETALHE` |
| `Escala horizontal` | `Escala horizontal 1:25` | 14 textos, na mesma layer |

A comparação é **literal**, não curinga — basta o trecho aparecer em qualquer
posição do texto para a entidade ser apagada.

**Os trechos são curtos de propósito.** O texto da escala está gravado como
`Escala vertical` seguido de **três espaços** e depois `1:50`; e o valor da
escala muda de desenho para desenho. Casando só por `Escala vertical`, a regra
funciona sem depender de espaçamento nem do número.

> Cuidado ao encurtar demais: `Escala` sozinho apagaria também o `Escala:` do
> carimbo.

A layer `CORTE_TITULO_DA_TABELA_DE_DETALHE` **não** pode ser apagada inteira —
ela guarda os títulos dos pilares (`P1`, `P2=P5=P16=P19`, `P12A`…), que ficam.
Por isso a exclusão aqui é por conteúdo, e não por layer como na etapa 1.

Atributos de bloco (`ATTRIB`) não são apagados: são sub-entidades e só somem
mexendo na inserção ou na definição do bloco. Se algum casar com a regra, ele
é contado e informado.

### Etapa 3 — Padroniza o estilo dos textos

Troca o estilo de todos os textos para **`ROMANS`**.

Alcança `TEXT`, `MTEXT`, `ATTDEF` e entra nos blocos para trocar também os
`ATTRIB` — o carimbo é um bloco com atributos, sem isso passaria batido.

Se o estilo `ROMANS` não existir no desenho, ele é criado com a fonte
`romans.shx`.

O relatório mostra **de onde veio** cada troca (`CYPETXT_romans -> ROMANS
(23 textos)`), para você conferir se pegou o que devia.

### Etapa 4 — Padroniza as alturas de texto

Aplica uma tabela de regras `(altura atual . altura nova)`:

| De | Para | Onde aparece |
|---|---|---|
| 12,667 | 18 | título da tabela de detalhe |
| 13,333 | 12,5 | referências de posição, cotas dos estribos |

O relatório também lista **as alturas encontradas na área que não tinham
regra**. É assim que você descobre o que ainda falta padronizar, sem sair
medindo texto na mão.

### Etapa 5 — Espaçamento nas anotações de ferro

Garante um espaço antes de `c/` e `c=`:

```
N2-%%c5c/18c=444    ->    N2-%%c5 c/18 c=444
N1-24%%c20c=380     ->    N1-24%%c20 c=380
N2-+9N3- c/18       ->    N2-+9N3- c/18       (já estava certo, não mexe)
```

### Etapa 6 — Uniformiza o fator de largura

Coloca o fator de largura de todos os textos em **0,9**.

O CYPE grava um fator diferente para cada texto, calculado para encaixar o
conteúdo na caixa. No desenho modelo há **68 valores distintos**, de 0,7213 a
1,1565 — e 539 textos já em 0,9. A etapa uniformiza os outros 614.

Vale para `TEXT`, `ATTDEF` e `ATTRIB`. **`MTEXT` fica de fora de propósito**:
nele o código DXF 41 é a largura da caixa de texto, não o fator de largura, e
escrever 0,9 ali espremeria o parágrafo inteiro para 0,9 unidade de largura.

---

## Configuração

Tudo fica no **topo do arquivo**. Não é preciso mexer no resto do código.

```lisp
;; Layers apagadas na etapa 1. Aceita curinga (* e ?):
;; "CORTE_COTAS_*" pegaria todas as layers que começam assim.
(defun PL:LAYERS-ROTINA ()
  (list
    "CORTE_NOMES_DAS_PLANTAS"
    "CORTE_TEXTO_DAS_ELEVACOES_DOS_PILARES"
    "CORTE_COTAS_DAS_LAJES"
    "CORTE_SEGMENTOS_DE_CORTE_DE_SECOES"
    "CORTE_PISOS"
  )
)

;; Textos com estes trechos são apagados inteiros, na etapa 2.
(defun PL:APAGAR-SE-CONTEM ()
  (list
    "["                    ; numeração local do CYPE: 50N[1]-%%c25
    "]"
    "Escala vertical"      ; "Escala vertical   1:50"
    "Escala horizontal"    ; "Escala horizontal 1:25"
  )
)

;; Estilo de texto de destino da etapa 3.
(defun PL:ESTILO-TEXTO () "ROMANS")

;; Fonte usada se o estilo acima ainda não existir no desenho.
(defun PL:ESTILO-FONTE () "romans.shx")

;; Trocas de altura da etapa 4: (altura atual . altura nova)
(defun PL:ALTURAS-TROCAR ()
  (list
    (cons 12.667 18.0)
    (cons 13.333 12.5)
  )
)

;; Folga na comparação de altura.
(defun PL:ALTURA-TOL () 0.01)

;; Fator de largura de destino da etapa 6. nil desliga a etapa.
(defun PL:LARGURA-TEXTO () 0.9)

;; Trechos que devem ter espaço na frente, na etapa 5.
(defun PL:ESPACO-ANTES ()
  (list "c/" "c=")
)
```

### Acrescentar uma regra

**Nova layer para apagar** — uma linha em `PL:LAYERS-ROTINA`.

**Nova troca de altura** — uma linha em `PL:ALTURAS-TROCAR`:

```lisp
(cons 13.667 12.5)   ; tabela de quantitativos
```

**Novo texto para apagar** — uma linha em `PL:APAGAR-SE-CONTEM`. Use o menor
trecho que identifique o texto sem pegar outros.

**Novo trecho para espaçar** — uma linha em `PL:ESPACO-ANTES`.

---

## Contexto: o desenho que ela corrige

O arquivo modelo (`PILAR MODELO ANTES.dwg`, formato AutoCAD 2013, 3,5 MB,
150.446 objetos) é um detalhamento de armação de pilares do 6º pavimento
**exportado do CYPECAD** e colado num template de escritório — carimbo,
formato A1 e tabela de penas `BeltraoEng.ctb`.

Os números abaixo saíram da leitura direta do DWG, feita com o
[libredwg](https://www.gnu.org/software/libredwg/) (`dwgread -O JSON`).

### O desenho tem duas cópias de si mesmo

|  | Perto da origem (X ≈ 0) | Na prancha (X ≈ 248.000) |
|---|---|---|
| Textos | 539 | 590 |
| Geometria | 809 | 1.033 |
| Estilo de texto | `CYPETXT_romans` | `ROMANS` |
| Altura de texto | 0,2 / 0,2667 | 10 / 13,333 (**×50**) |

O export cru do CYPE fica largado perto da origem e a versão escalada 50×
é montada na prancha. Como a rotina age só na área selecionada, ela mexe
apenas na cópia que estiver dentro da janela.

### Composição do arquivo

- **59 layers**, sendo 19 vazias
- **9 estilos de texto**: `ROMANS`, `CYPETXT_romans`, `CYPETXT_0.08_romans`,
  `AR120`, `GrAcad`, `Verdana`, `Lista_Ferros`, `Annotative`, `STANDARD`
- **7 estilos de cota**: `cype_oblique`, `GRACAD`, `Gr-Conc`, `ISO-25`,
  `Ef_Quant_MRV_A`, `Annotative`, `STANDARD`
- Layers do CYPE (`ARM_*`, `CORTE_*`, `SECAO_*`, `PILCP_*`) convivendo com
  layers do template de escritório (`GrAcad01-06`, `Lista_Ferros_*`,
  `Usuario01-03`, `CARIMBO`, `QUAD_*`, `T120`, `FORM02/04`)

### Entidades

| Tipo | Quantidade |
|---|---|
| `VERTEX_2D` | 135.118 |
| `POLYLINE_2D` | 5.568 |
| `TEXT` | 1.153 |
| `LINE` | 1.072 |
| `CIRCLE` | 770 |
| `HATCH` | 444 |
| `POINT` | 111 |
| `INSERT` | 75 |
| `MTEXT` | 37 |
| `DIMENSION_ALIGNED` | 34 |
| `LWPOLYLINE` | 6 |
| `OLE2FRAME` | 3 |

---

## Decisões técnicas

Cada uma destas resolve um problema concreto que apareceu no desenho real.

### A seleção é pedida uma vez só

Todas as etapas rodam em cima da mesma seleção. Etapas novas entram sem
obrigar você a selecionar de novo.

A seleção é **sem filtro** — quem decide o que mexer é cada etapa. Por isso
você pode dar uma janela larga sem se preocupar.

### As layers são liberadas antes da seleção

Objeto em layer congelada, desligada ou travada **não pode ser selecionado**.
Sem descongelar, ligar e destravar antes, você faria a janela e o script não
acharia nada.

Efeito colateral: se alguma das layers de rotina estava desligada, ela
reaparece na tela no momento da seleção.

### A layer só é removida se ficar vazia

Como a limpeza é por área, pode sobrar conteúdo da layer fora da seleção.
Apagar o registro nesse caso deixaria órfãos, então a etapa 1 confere o
desenho inteiro antes de remover.

### Alturas são comparadas com folga, não por igualdade

O CYPE grava alturas quebradas. O que aparece como **12,667** está gravado
como **12,66666666…**, porque é 0,2533… multiplicado por 50. Um `=` exato
não acharia nenhum texto.

A comparação usa folga de **0,01** (`PL:ALTURA-TOL`). É seguro neste desenho:
as alturas usadas nessa faixa são 12,3333 / 12,5 / 12,6667 / 13,3333 /
13,6667, e a menor distância entre duas delas é 0,1667 — dezesseis vezes a
folga.

> Se você cadastrar regras com alturas separadas por menos que a folga,
> precisa apertar `PL:ALTURA-TOL`.

**As regras de altura não encadeiam.** Cada texto é avaliado uma vez, pela
altura que tinha antes da etapa começar. Se existirem regras `A→B` e `B→C`,
os textos em A param em B.

### O espaçamento é idempotente

A etapa 5 **não é uma substituição de texto**. Parte das anotações já vem
com o espaço (`N2-+9N3- c/18`, em `CORTE_TEXTO_DAS_COTAS`). Trocar `c/` por
` c/` nesses geraria espaço dobrado, e o estrago aumentaria a cada execução.

Por isso `PL:ESPACO-ANTES` lista trechos que devem **ter** espaço na frente.
Se já houver, nada muda. Rodar duas vezes dá o mesmo resultado que rodar uma.

Casos verificados contra os 38 textos do desenho que contêm `c/` ou `c=`
(31 são ajustados, 7 já estavam corretos):

| Caso | Resultado |
|---|---|
| `%%c` (código do Ø) é confundido com o `c` de `c/`? | Não — `%%c5c/18` → `%%c5 c/18` |
| Trecho no início da string | `c/18` fica `c/18`, sem espaço à esquerda |
| Espaço já existente | `  c/15` não vira `   c/15` |
| Dois trechos no mesmo texto | `N1-%%c20c=380c/10` → `N1-%%c20 c=380 c/10` |
| Aplicar três vezes | igual a aplicar uma |

### O código DXF 41 significa coisas diferentes em TEXT e MTEXT

Em `TEXT`, `ATTDEF` e `ATTRIB` o código 41 é o **fator de largura**. Em
`MTEXT` o mesmo código é a **largura da caixa de texto**. Aplicar 0,9 num
MTEXT não deixaria a fonte mais estreita — espremeria o parágrafo inteiro
para 0,9 unidade de largura.

Por isso a etapa 6 exclui MTEXT e informa quantos encontrou.

### Falhas aparecem no relatório

Se o `entmod` falhar — tipicamente porque o texto está em layer travada — o
objeto é contado e aparece um aviso, em vez de sumir da contagem.

---

## Limitações

**Cotas, leaders e tabelas não têm o texto alterado.** Nesses objetos o texto
vem do estilo do próprio objeto (dimstyle, mleaderstyle), não de um estilo de
texto. Mudar exige mexer no estilo ou criar override. A rotina conta quantos
encontrou e informa no relatório. O desenho modelo tem 34 `DIMENSION_ALIGNED`
nessa situação, usando o dimstyle `cype_oblique`.

**MTEXT longo não é alterado na etapa 5.** Nele o texto é repartido entre
vários códigos DXF 3 mais o código 1; mexer só no 1 quebraria o conteúdo.
Esses são contados e informados. No desenho modelo não há nenhum nessa
situação.

**A rotina não entra em definições de bloco.** Ela alcança os atributos de
blocos inseridos, mas não a geometria e os textos dentro da definição.

**A rotina não foi testada dentro do CAD.** A lógica de espaçamento da etapa 4
foi verificada contra os textos reais do DWG, mas o comportamento no AutoCAD
e no ZWCAD ainda depende de você rodar. **Rode sempre numa cópia primeiro.**

---

## O que ainda não está automatizado

Problemas identificados no desenho modelo que a rotina ainda não trata:

1. **Cópia crua do CYPE na origem** — 539 textos e 809 entidades largados
   fora da prancha. Boa parte dos 3,5 MB do arquivo.
2. **Erro de digitação `6º AVTO`** (falta o "P") em `CORTE_NOMES_DAS_PLANTAS`
   e em `Planta: 6º AVTO`. No mesmo desenho existem `5º Pavimento` e, no
   carimbo, `6o. PAVIMENTO` — três grafias diferentes.
3. **19 layers vazias** (`GrAcad01-06`, `Usuario01-03`, `Lista_Ferros_*`,
   `Telas de Aço*`, `PILAR_BETAO`, `Cotas`…).
4. **5.568 `POLYLINE_2D` no formato antigo**, com 135 mil vértices soltos —
   contra apenas 6 `LWPOLYLINE`. Converter reduz muito o arquivo.
5. **3 objetos OLE** na layer 0, que costumam dar problema no ZWCAD.
6. **Espessuras muito finas** nas layers do CYPE (0,00 / 0,09 / 0,15 /
   0,20 mm).
7. **Layers com `Ø` e acentos** (`ARM_LONGITUDINAL_Ø20`, `Telas de Aço em
   Elevação`) — risco de encoding entre AutoCAD e ZWCAD.

---

## Compatibilidade

Escrita para funcionar igual em **AutoCAD** e **ZWCAD**:

- Usa AutoLISP puro e `entmod` / `entmake` / `ssget`, sem depender de
  comandos que mudam de nome entre os dois.
- Onde usa ActiveX (remoção de layer), há queda para `-PURGE` se falhar.
- Todas as chamadas de comando levam o prefixo `_.` (`_.ERASE`, `_.-PURGE`),
  que força o nome em inglês independente do idioma da instalação.
- Nomes de layer com caractere especial são protegidos antes de virarem
  filtro de `ssget`.

---

## Estrutura do código

Arquivo único: `maqpilares.lsp`.

```
CONFIGURACAO          PL:LAYERS-ROTINA, PL:ESTILO-TEXTO, PL:ESTILO-FONTE,
                      PL:APAGAR-SE-CONTEM, PL:ALTURAS-TROCAR, PL:ALTURA-TOL,
                      PL:LARGURA-TEXTO,
                      PL:ESPACO-ANTES

AUXILIARES            pl:esc              protege curingas em nome de layer
                      pl:fmt              número -> texto, 4 casas
                      pl:espacar          garante espaço antes de um trecho
                      pl:casar-layers     resolve curinga -> nomes reais
                      pl:liberar-layer    descongela, destrava e liga
                      pl:restantes        quantos objetos sobraram na layer
                      pl:deletar-layer    ActiveX, com queda para -PURGE
                      pl:contar           contagem em lista associativa
                      pl:garantir-estilo  cria o estilo de texto se faltar
                      pl:atributos        ATTRIB de dentro de um INSERT
                      pl:textos           textos da seleção, já com ATTRIB
                      pl:trocar-dxf       troca um código DXF com tratamento
                                          de erro
                      pl:definir-dxf      idem, criando o par se faltar

ETAPAS                pl:etapa-layers        [1]
                      pl:etapa-apagar-texto  [2]
                      pl:etapa-estilo        [3]
                      pl:nova-altura         regra da [4]
                      pl:etapa-altura        [4]
                      pl:etapa-texto         [5]
                      pl:etapa-largura       [6]

COMANDO               c:maqpilares
```

Cada etapa é uma função que recebe a seleção pronta. Para acrescentar uma
etapa nova, escreva a função e chame em `c:maqpilares`, na sequência.

---

## Repositório

Os arquivos `.dwg` e `.dxf` ficam fora do repositório, junto com os
temporários do CAD (`.bak`, `.dwl`, `.dwl2`, `.sv$`, `.ac$`). Veja o
`.gitignore`.
