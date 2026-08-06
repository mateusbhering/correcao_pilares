;;; ===========================================================================
;;;  maqpilares.lsp
;;;  ---------------------------------------------------------------------------
;;;  Rotina de correcao dos desenhos de armacao de pilares exportados do
;;;  CYPECAD, para AutoCAD e ZWCAD.
;;;
;;;  Comando:  maqpilares
;;;
;;;  TUDO acontece somente dentro da area que o usuario selecionar.
;;;  A selecao e pedida UMA vez e todas as etapas rodam em cima dela.
;;;
;;;  Etapas:
;;;    1) Apaga as layers de rotina (nome do pavimento, nome das vistas,
;;;       niveis intermediarios, nome da secao e sombra).
;;;    2) Troca o estilo de todos os textos para ROMANS.
;;;    3) Troca alturas de texto conforme a tabela de regras.
;;;
;;;  Configuracao no topo do arquivo:
;;;    PL:LAYERS-ROTINA   - layers apagadas. Aceita curinga (* e ?), entao
;;;                         "CORTE_COTAS_*" pega todas que comecam assim.
;;;    PL:ESTILO-TEXTO    - estilo de texto de destino.
;;;    PL:ALTURAS-TROCAR  - pares (altura atual . altura nova).
;;; ===========================================================================

(vl-load-com)

;;; ---------------------------------------------------------------------------
;;; CONFIGURACAO
;;; ---------------------------------------------------------------------------

(defun PL:LAYERS-ROTINA ()
  (list
    "CORTE_NOMES_DAS_PLANTAS"                ; a - nome do pavimento
    "CORTE_TEXTO_DAS_ELEVACOES_DOS_PILARES"  ; b - nome das vistas
    "CORTE_COTAS_DAS_LAJES"                  ; c - niveis intermediarios
    "CORTE_SEGMENTOS_DE_CORTE_DE_SECOES"     ; d - nome da secao
    "CORTE_PISOS"                            ; e - sombra
  )
)

(defun PL:ESTILO-TEXTO () "ROMANS")

;; Fonte usada caso o estilo de destino ainda nao exista no desenho.
(defun PL:ESTILO-FONTE () "romans.shx")

;; Trocas de altura de texto: (altura atual . altura nova)
(defun PL:ALTURAS-TROCAR ()
  (list
    (cons 12.667 18.0)   ; titulo da tabela de detalhe
  )
)

;; Folga na comparacao de altura. O CYPE grava valores quebrados
;; (12.6666666..., 13.3333333...), entao comparar por igualdade exata
;; nao acha nada. A folga precisa ser menor que a distancia entre duas
;; alturas diferentes do desenho.
(defun PL:ALTURA-TOL () 0.01)

;;; ---------------------------------------------------------------------------
;;; FUNCOES AUXILIARES
;;; ---------------------------------------------------------------------------

;; Protege os caracteres que o AutoCAD trata como curinga, para que
;; nomes com "-", ".", "#" ou "@" sejam comparados ao pe da letra.
;; Nao protege "*" e "?" de proposito: sao os curingas uteis na config.
(defun pl:esc (s / c r)
  (setq r "")
  (foreach c (vl-string->list s)
    (if (member c '(35 64 46 126 91 93 45 44 96))   ; # @ . ~ [ ] - , `
      (setq r (strcat r "`" (chr c)))
      (setq r (strcat r (chr c)))))
  r
)

;; Numero para texto, com 4 casas, independente das unidades do desenho.
(defun pl:fmt (v) (rtos v 2 4))

;; Devolve os nomes reais de layer do desenho que casam com o padrao.
(defun pl:casar-layers (padrao / td nome achados)
  (setq achados nil
        td      (tblnext "LAYER" T))
  (while td
    (setq nome (cdr (assoc 2 td)))
    (if (wcmatch (strcase nome) (strcase padrao))
      (setq achados (cons nome achados)))
    (setq td (tblnext "LAYER")))
  (reverse achados)
)

;; Descongela, destrava e liga a layer. Precisa acontecer ANTES da
;; selecao: objeto em layer congelada, desligada ou travada nao pode
;; ser selecionado pelo usuario.
(defun pl:liberar-layer (nome / ed flag cor)
  (if (setq ed (tblobjname "LAYER" nome))
    (progn
      (setq ed (entget ed))
      ;; bit 1 = congelada, bit 4 = travada -> zera os dois
      (setq flag (logand (cdr (assoc 70 ed)) (~ 5)))
      (setq ed (subst (cons 70 flag) (assoc 70 ed) ed))
      ;; cor negativa = layer desligada -> liga
      (if (setq cor (assoc 62 ed))
        (setq ed (subst (cons 62 (abs (cdr cor))) cor ed)))
      (not (vl-catch-all-error-p (vl-catch-all-apply 'entmod (list ed)))))
    nil)
)

;; Quantos objetos ainda restam nessa layer, no desenho inteiro.
(defun pl:restantes (nome / ss)
  (if (setq ss (ssget "_X" (list (cons 8 (pl:esc nome)))))
    (sslength ss)
    0)
)

;; Remove o registro da layer. Tenta via ActiveX e, se falhar, via -PURGE.
;; Devolve T se a layer sumiu do desenho.
(defun pl:deletar-layer (nome)
  (vl-catch-all-apply
    '(lambda ()
       (vla-delete
         (vla-item
           (vla-get-layers
             (vla-get-activedocument (vlax-get-acad-object)))
           nome))))
  (if (tblobjname "LAYER" nome)
    (vl-catch-all-apply
      '(lambda () (command "_.-PURGE" "_LA" nome "_N"))))
  (not (tblobjname "LAYER" nome))
)

;; Soma 1 na contagem da chave dentro da lista associativa.
(defun pl:contar (chave lst / par)
  (if (setq par (assoc chave lst))
    (subst (cons chave (1+ (cdr par))) par lst)
    (cons (cons chave 1) lst))
)

;; Cria o estilo de texto se ele ainda nao existir no desenho.
(defun pl:garantir-estilo (nome)
  (if (not (tblobjname "STYLE" nome))
    (entmake
      (list '(0 . "STYLE")
            '(100 . "AcDbSymbolTableRecord")
            '(100 . "AcDbTextStyleTableRecord")
            (cons 2 nome)
            '(70 . 0)                       ; sem flags especiais
            '(40 . 0.0)                     ; altura variavel
            '(41 . 1.0)                     ; fator de largura
            '(50 . 0.0)                     ; angulo obliquo
            '(71 . 0)                       ; nao invertido
            '(42 . 2.5)                     ; ultima altura usada
            (cons 3 (PL:ESTILO-FONTE))
            '(4 . ""))))
  (if (tblobjname "STYLE" nome) T nil)
)

;; Sub-entidades ATTRIB de um INSERT com atributos.
(defun pl:atributos (e / ed sub prox)
  (setq sub nil ed (entget e))
  (if (and (= (cdr (assoc 0 ed)) "INSERT")
           (= 1 (cdr (assoc 66 ed))))
    (progn
      (setq prox (entnext e))
      (while (and prox
                  (setq ed (entget prox))
                  (/= (cdr (assoc 0 ed)) "SEQEND"))
        (if (= (cdr (assoc 0 ed)) "ATTRIB")
          (setq sub (cons prox sub)))
        (setq prox (entnext prox)))))
  sub
)

;; Todas as entidades de texto de dentro da selecao, ja incluindo os
;; ATTRIB de dentro dos blocos. Ignora o que ja foi apagado.
(defun pl:textos (ss / lst i e ed tipo)
  (setq lst nil i 0)
  (repeat (sslength ss)
    (setq e (ssname ss i))
    (if (setq ed (entget e))
      (progn
        (setq tipo (cdr (assoc 0 ed)))
        (cond
          ((member tipo '("TEXT" "MTEXT" "ATTDEF")) (setq lst (cons e lst)))
          ((= tipo "INSERT")
           (foreach a (pl:atributos e) (setq lst (cons a lst)))))))
    (setq i (1+ i)))
  (reverse lst)
)

;; Troca um codigo DXF de uma entidade. Devolve:
;;   'trocado   se mudou
;;   'erro      se a alteracao falhou (tipicamente layer travada)
;;   nil        se a entidade nao tem esse codigo (ou foi apagada)
(defun pl:trocar-dxf (e codigo valor / ed atual r)
  (if (and (setq ed (entget e)) (setq atual (assoc codigo ed)))
    (progn
      (setq r (vl-catch-all-apply
                'entmod (list (subst (cons codigo valor) atual ed))))
      (if (or (vl-catch-all-error-p r) (null r))
        'erro
        (progn (entupd e) 'trocado)))
    nil)
)

;;; ---------------------------------------------------------------------------
;;; ETAPA 1 - apagar as layers de rotina que estao dentro da selecao
;;; ---------------------------------------------------------------------------

(defun pl:etapa-layers (ss alvos / mortos i e ed lay contagem qtd sobra
                                   tot-obj tot-lay)
  (princ "\n  [1] Layers de rotina\n")

  ;; monta a sub-selecao so com o que esta nas layers alvo
  (setq mortos (ssadd) contagem nil i 0)
  (repeat (sslength ss)
    (setq e   (ssname ss i)
          ed  (entget e)
          lay (cdr (assoc 8 ed)))
    (if (member (strcase lay) alvos)
      (progn (ssadd e mortos)
             (setq contagem (pl:contar (strcase lay) contagem))))
    (setq i (1+ i)))

  (setq tot-obj (sslength mortos) tot-lay 0)

  (if (zerop tot-obj)
    (princ "      nada das layers de rotina nesta area\n")
    (progn
      (command "_.ERASE" mortos "")

      (foreach nome (PL:LAYERS-ROTINA)
        (foreach real (pl:casar-layers nome)
          (setq qtd   (cdr (assoc (strcase real) contagem))
                sobra (pl:restantes real))
          (cond
            ((null qtd)
             (princ (strcat "      [-]        " real
                            "  (nada nesta area, " (itoa sobra)
                            " objetos em outro lugar)\n")))
            ((zerop sobra)
             (if (pl:deletar-layer real)
               (progn
                 (setq tot-lay (1+ tot-lay))
                 (princ (strcat "      [ok]       " real
                                "  (" (itoa qtd) " objetos, layer removida)\n")))
               (princ (strcat "      [conteudo] " real
                              "  (" (itoa qtd)
                              " objetos, layer vazia mas nao pode ser removida)\n"))))
            (T
             (princ (strcat "      [parcial]  " real
                            "  (" (itoa qtd) " objetos apagados, restam "
                            (itoa sobra) " fora da area)\n"))))))

      (princ (strcat "      -> " (itoa tot-obj) " objetos apagados, "
                     (itoa tot-lay) " layers removidas\n"))))
  tot-obj
)

;;; ---------------------------------------------------------------------------
;;; ETAPA 2 - padronizar o estilo de todos os textos
;;; ---------------------------------------------------------------------------

(defun pl:etapa-estilo (ss / estilo lista e ed atual res trocados iguais
                             travados pulados origens i tipo)
  (setq estilo (PL:ESTILO-TEXTO))
  (princ (strcat "\n  [2] Estilo de texto -> " estilo "\n"))

  (if (not (pl:garantir-estilo estilo))
    (progn
      (princ (strcat "      nao foi possivel criar o estilo " estilo
                     ", etapa ignorada\n"))
      0)

    (progn
      ;; censo dos objetos cujo texto nao vem de um estilo de texto
      (setq pulados nil i 0)
      (repeat (sslength ss)
        (if (setq ed (entget (ssname ss i)))
          (progn
            (setq tipo (cdr (assoc 0 ed)))
            (if (wcmatch tipo "DIMENSION,*LEADER,ACAD_TABLE,TABLE")
              (setq pulados (pl:contar tipo pulados)))))
        (setq i (1+ i)))

      (setq trocados 0 iguais 0 travados 0 origens nil)

      (foreach e (pl:textos ss)
        (setq ed    (entget e)
              atual (cdr (assoc 7 ed)))
        (if (and atual (= (strcase atual) (strcase estilo)))
          (setq iguais (1+ iguais))
          (progn
            (setq res (pl:trocar-dxf e 7 estilo))
            (cond ((eq res 'trocado)
                   (setq trocados (1+ trocados)
                         origens  (pl:contar atual origens)))
                  ((eq res 'erro)
                   (setq travados (1+ travados)))))))

      (if (and (zerop trocados) (zerop iguais) (zerop travados))
        (princ "      nenhum texto nesta area\n")
        (progn
          (foreach par (reverse origens)
            (princ (strcat "      " (car par) " -> " estilo
                           "  (" (itoa (cdr par)) " textos)\n")))
          (princ (strcat "      -> " (itoa trocados) " textos trocados, "
                         (itoa iguais) " ja estavam em " estilo "\n"))))

      (if (> travados 0)
        (princ (strcat "      ATENCAO: " (itoa travados)
                       " textos nao puderam ser alterados"
                       " (layer travada?)\n")))

      (if pulados
        (progn
          (princ "      nao alterados (o texto vem do estilo do proprio\n")
          (princ "      objeto, nao de um estilo de texto):\n")
          (foreach par (reverse pulados)
            (princ (strcat "        " (car par) ": " (itoa (cdr par)) "\n")))))

      trocados))
)

;;; ---------------------------------------------------------------------------
;;; ETAPA 3 - trocar alturas de texto conforme a tabela de regras
;;; ---------------------------------------------------------------------------

;; Devolve a altura de destino para h, ou nil se nenhuma regra casa.
(defun pl:nova-altura (h / tol achou)
  (setq tol (PL:ALTURA-TOL) achou nil)
  (foreach par (PL:ALTURAS-TROCAR)
    (if (and (null achou) (<= (abs (- h (car par))) tol))
      (setq achou (cdr par))))
  achou
)

(defun pl:etapa-altura (ss / e ed h nova res trocados travados sobraram
                             feitas)
  (princ "\n  [3] Altura de texto\n")

  (if (null (PL:ALTURAS-TROCAR))
    (progn (princ "      nenhuma regra configurada\n") 0)

    (progn
      (setq trocados 0 travados 0 feitas nil sobraram nil)

      (foreach e (pl:textos ss)
        (setq ed (entget e)
              h  (cdr (assoc 40 ed)))
        (if h
          (if (setq nova (pl:nova-altura h))
            (progn
              (setq res (pl:trocar-dxf e 40 nova))
              (cond ((eq res 'trocado)
                     (setq trocados (1+ trocados)
                           feitas   (pl:contar (strcat (pl:fmt h) " -> "
                                                       (pl:fmt nova))
                                               feitas)))
                    ((eq res 'erro)
                     (setq travados (1+ travados)))))
            ;; sem regra: guarda para o censo
            (setq sobraram (pl:contar (pl:fmt h) sobraram)))))

      (if (zerop trocados)
        (princ "      nenhum texto com altura das regras nesta area\n")
        (foreach par (reverse feitas)
          (princ (strcat "      " (car par)
                         "  (" (itoa (cdr par)) " textos)\n"))))

      (if (> travados 0)
        (princ (strcat "      ATENCAO: " (itoa travados)
                       " textos nao puderam ser alterados"
                       " (layer travada?)\n")))

      ;; util para descobrir quais outras alturas existem na area
      (if sobraram
        (progn
          (princ "      outras alturas encontradas (sem regra):\n        ")
          (foreach par (reverse sobraram)
            (princ (strcat (car par) " (" (itoa (cdr par)) ")  ")))
          (princ "\n")))

      (princ (strcat "      -> " (itoa trocados) " alturas trocadas\n"))
      trocados))
)

;;; ---------------------------------------------------------------------------
;;; COMANDO PRINCIPAL
;;; ---------------------------------------------------------------------------

(defun c:maqpilares ( / *error* ce cl alvos padrao nome ss)

  (defun *error* (msg)
    (if ce (setvar "CMDECHO" ce))
    (if cl (vl-catch-all-apply 'setvar (list "CLAYER" cl)))
    (if (and msg (not (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*")))
      (princ (strcat "\nErro: " msg)))
    (princ)
  )

  (setq ce (getvar "CMDECHO")
        cl (getvar "CLAYER"))
  (setvar "CMDECHO" 0)

  (princ "\n--- maqpilares ---\n")

  ;; ---- quais layers de rotina existem neste desenho ----
  (setq alvos nil)
  (foreach padrao (PL:LAYERS-ROTINA)
    (foreach nome (pl:casar-layers padrao)
      (if (not (member (strcase nome) alvos))
        (setq alvos (cons (strcase nome) alvos)))))

  ;; ---- libera as layers para que possam ser selecionadas ----
  ;; (objeto congelado, desligado ou travado nao entra na selecao)
  (foreach nome alvos (pl:liberar-layer nome))

  ;; ---- pede a area, uma vez so, para todas as etapas ----
  (princ "\n  Selecione a area do desenho a corrigir")
  (princ "\n  (janela ou cerca; o script decide o que mexer dentro dela)\n")
  (setq ss (ssget))

  (if (null ss)
    (princ "\n  Nada selecionado.\n")
    (progn
      (princ (strcat "\n  " (itoa (sslength ss)) " objetos na area.\n"))
      ;; Nao da para apagar a layer que esta corrente.
      (if (tblobjname "LAYER" "0") (setvar "CLAYER" "0"))

      (pl:etapa-layers ss alvos)
      (pl:etapa-estilo ss)
      (pl:etapa-altura ss)

      (princ "\n  Concluido.\n")))

  (setvar "CLAYER" cl)
  (setvar "CMDECHO" ce)
  (princ)
)

(princ "\nmaqpilares.lsp carregado.  Digite maqpilares para rodar.\n")
(princ)
