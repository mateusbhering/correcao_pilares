;;; ===========================================================================
;;;  maqpilares.lsp
;;;  ---------------------------------------------------------------------------
;;;  Apaga as layers de rotina do detalhamento de armacao de pilares
;;;  exportado do CYPECAD.
;;;
;;;  A limpeza acontece SOMENTE dentro da area que o usuario selecionar.
;;;  O registro da layer so e removido do desenho se, depois de apagar a
;;;  selecao, nao tiver sobrado nada dela em nenhum outro lugar.
;;;
;;;  Comando:  maqpilares
;;;
;;;  Compativel com AutoCAD e ZWCAD.
;;;
;;;  Para incluir ou tirar layers da rotina, edite SOMENTE a lista
;;;  PL:LAYERS-ROTINA logo abaixo. Aceita curinga (* e ?), entao
;;;  "CORTE_COTAS_*" pegaria todas as layers que comecam assim.
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

;; Monta o filtro de ssget com varias layers de uma vez: "A,B,C".
(defun pl:filtro (lst / s)
  (setq s "")
  (foreach n lst
    (setq s (if (= s "") (pl:esc n) (strcat s "," (pl:esc n)))))
  s
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

;; Soma 1 na contagem da layer dentro da lista associativa.
(defun pl:contar (nome lst / par)
  (if (setq par (assoc nome lst))
    (subst (cons nome (1+ (cdr par))) par lst)
    (cons (cons nome 1) lst))
)

;;; ---------------------------------------------------------------------------
;;; COMANDO PRINCIPAL
;;; ---------------------------------------------------------------------------

(defun c:maqpilares ( / *error* ce cl alvos padrao nomes nome ss i ed
                        contagem qtd sobra tot-obj tot-lay nao-achou)

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

  (princ "\n--- maqpilares: limpeza das layers de rotina ---\n")

  ;; ---- 1) descobre quais layers da rotina existem neste desenho ----
  (setq alvos nil nao-achou nil)
  (foreach padrao (PL:LAYERS-ROTINA)
    (if (setq nomes (pl:casar-layers padrao))
      (foreach nome nomes
        (if (not (member nome alvos)) (setq alvos (cons nome alvos))))
      (setq nao-achou (cons padrao nao-achou))))
  (setq alvos (reverse alvos))

  (if (null alvos)
    (progn
      (princ "\n  Nenhuma das layers de rotina existe neste desenho.\n")
      (setvar "CMDECHO" ce)
      (princ))

    (progn
      ;; ---- 2) libera as layers para que possam ser selecionadas ----
      ;; (objeto congelado, desligado ou travado nao entra na selecao)
      (foreach nome alvos (pl:liberar-layer nome))

      ;; ---- 3) pede a area ----
      (princ "\n  Selecione a area do desenho a limpar")
      (princ "\n  (janela, cerca ou clique; so entram as layers de rotina)\n")
      (setq ss (ssget (list (cons 8 (pl:filtro alvos)))))

      (if (null ss)
        (princ "\n  Nada das layers de rotina foi encontrado nessa area.\n")

        (progn
          ;; ---- 4) conta por layer antes de apagar ----
          (setq contagem nil i 0 tot-obj (sslength ss))
          (repeat tot-obj
            (setq ed       (entget (ssname ss i))
                  contagem (pl:contar (cdr (assoc 8 ed)) contagem)
                  i        (1+ i)))

          ;; ---- 5) apaga ----
          (command "_.ERASE" ss "")

          ;; ---- 6) relatorio + remove a layer se ficou vazia ----
          ;; Nao da para apagar a layer que esta corrente.
          (if (tblobjname "LAYER" "0") (setvar "CLAYER" "0"))
          (setq tot-lay 0)

          (foreach nome alvos
            (setq qtd   (cdr (assoc nome contagem))
                  sobra (pl:restantes nome))
            (cond
              ;; nao tinha nada dessa layer na area selecionada
              ((null qtd)
               (princ (strcat "  [-]        " nome
                              "  (nada nesta area, " (itoa sobra)
                              " objetos em outro lugar)\n")))
              ;; limpou a area e a layer ficou vazia -> remove o registro
              ((zerop sobra)
               (if (pl:deletar-layer nome)
                 (progn
                   (setq tot-lay (1+ tot-lay))
                   (princ (strcat "  [ok]       " nome
                                  "  (" (itoa qtd) " objetos, layer removida)\n")))
                 (princ (strcat "  [conteudo] " nome
                                "  (" (itoa qtd)
                                " objetos, layer vazia mas nao pode ser removida)\n"))))
              ;; limpou a area mas ainda ha conteudo fora dela
              (T
               (princ (strcat "  [parcial]  " nome
                              "  (" (itoa qtd) " objetos apagados, restam "
                              (itoa sobra) " fora da area)\n")))))

          (princ (strcat "\n  " (itoa tot-obj) " objetos apagados, "
                         (itoa tot-lay) " layers removidas.\n"))))

      (if nao-achou
        (progn
          (princ "\n  Nao existem neste desenho:\n")
          (foreach nome (reverse nao-achou)
            (princ (strcat "    - " nome "\n")))))

      (setvar "CLAYER" cl)
      (setvar "CMDECHO" ce)
      (princ)))
)

(princ "\nmaqpilares.lsp carregado.  Digite maqpilares para rodar.\n")
(princ)
