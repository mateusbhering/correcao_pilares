;;; ===========================================================================
;;;  maqpilares.lsp
;;;  ---------------------------------------------------------------------------
;;;  Apaga as layers de rotina do detalhamento de armacao de pilares
;;;  exportado do CYPECAD: remove o conteudo e depois o proprio registro
;;;  da layer.
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

;; Descongela, destrava e liga a layer, para que o ERASE alcance tudo.
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

;; Apaga tudo que estiver na layer, em qualquer aba (modelo e layouts).
;; Devolve a quantidade de objetos apagados.
(defun pl:apagar-conteudo (nome / ss n)
  (setq n 0)
  (if (setq ss (ssget "_X" (list (cons 8 (pl:esc nome)))))
    (progn
      (setq n (sslength ss))
      (command "_.ERASE" ss "")))
  n
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

;;; ---------------------------------------------------------------------------
;;; COMANDO PRINCIPAL
;;; ---------------------------------------------------------------------------

(defun c:maqpilares ( / *error* ce cl nomes nome n
                    tot-obj tot-lay nao-achou presas)

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

  ;; Nao da para apagar a layer que esta corrente.
  (if (tblobjname "LAYER" "0") (setvar "CLAYER" "0"))

  (setq tot-obj   0
        tot-lay   0
        nao-achou nil
        presas    nil)

  (princ "\n--- maqpilares: limpeza das layers de rotina ---\n")

  (foreach padrao (PL:LAYERS-ROTINA)
    (setq nomes (pl:casar-layers padrao))
    (if (null nomes)
      (setq nao-achou (cons padrao nao-achou))
      (foreach nome nomes
        (pl:liberar-layer nome)
        (setq n (pl:apagar-conteudo nome))
        (setq tot-obj (+ tot-obj n))
        (if (pl:deletar-layer nome)
          (progn
            (setq tot-lay (1+ tot-lay))
            (princ (strcat "  [ok]      " nome
                           "  (" (itoa n) " objetos)\n")))
          (progn
            (setq presas (cons nome presas))
            (princ (strcat "  [conteudo] " nome
                           "  (" (itoa n) " objetos apagados, layer nao pode ser removida)\n")))))))

  ;; ---- relatorio ----
  (princ (strcat "\n  " (itoa tot-obj) " objetos apagados, "
                 (itoa tot-lay) " layers removidas.\n"))

  (if nao-achou
    (progn
      (princ "\n  Nao encontradas neste desenho:\n")
      (foreach nome (reverse nao-achou)
        (princ (strcat "    - " nome "\n")))))

  (if presas
    (progn
      (princ "\n  Layers esvaziadas mas ainda presentes (algo as referencia,\n")
      (princ "  normalmente uma definicao de bloco ou um estilo):\n")
      (foreach nome (reverse presas)
        (princ (strcat "    - " nome "\n")))))

  (setvar "CLAYER" cl)
  (setvar "CMDECHO" ce)
  (princ)
)

(princ "\nmaqpilares.lsp carregado.  Digite maqpilares para rodar.\n")
(princ)
