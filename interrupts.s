   section	code,text

    global install_im2

; See: https://www.triceraprog.fr/phc-25-et-z80-en-im-2.html

install_im2:

    ; Remplit la table des vecteurs d'interruption
    ld      hl,$fe00        ; La table démarre en $FE00
    ld      e,l
    ld      d,h
    inc     de              ; Idiome de remplissage de mémoire
    ld      bc,257          ; De longueur 257 octets
    ld      a,$fd           ; Contenant l'adresse $fdfd
    ld      (hl),a
    ldir                    ; Remplissage de mémoire

    ; On place un saut vers l'ISR dans le vecteur d'interruption
    ld      hl,$fdfd        ; L'adresse du vecteur
    ld      a,$c3           ; Instruction de saut (JP) vers xxxx
    ld      (hl),a
    inc     hl
    ld      de,music_interrupt_handler ; L'adresse de l'ISR
    ld      (hl),e
    inc     hl
    ld      (hl),d          ; Met l'adresse de l'ISR après l'instruction JP

    ; Place la table des vecteurs d'interruption ($FExx)
    ld      a,$fe
    ld      i,a             ; Met l'adresse haute à $FE
    im      2               ; Commute en Mode d'Interruption 2

    ret