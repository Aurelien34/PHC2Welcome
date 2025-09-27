    section	code,text

    global init_bar, handle_bar

COLOR_NORMAL equ %11010110
COLOR_BAR equ %10010110

BAR_TOP equ 16
BAR_BOTTOM equ 170
BAR_GRAVITY equ $12

init_bar:
    xor a
    ld (bar_y),a
    ld a,BAR_TOP
    ld (bar_y+1),a

    xor a
    ld (bar_speed),a
    ld (bar_speed+1),a
   
    ret

handle_bar:
    push hl
    push bc

    call compute_bar

    ; wait for end of VBL
.vbl_start
    in a,($40)
    bit 4,a
    jr nz,.vbl_start

.vbl_end
    in a,($40)
    bit 4,a
    jr z,.vbl_end


    ld b,40
.startrowloop
    call wait
    djnz .startrowloop

    ld a,(bar_y+1)
    ld b,a
.barstartloop
    call wait
    djnz .barstartloop

    call bar

    ld b,30
.barheightloop
    call wait
    djnz .barheightloop

    call no_bar

    pop bc
    pop hl

    ret

no_bar:
    ld a,COLOR_NORMAL
    out ($40),a
    ret

bar:
    ld a,COLOR_BAR
    out ($40),a
    ret

bar_speed:
    dc.w 256
bar_y:
    dc.w 0
compute_bar:

    ; Apply gravity
    ld hl,(bar_speed)
    ld bc,BAR_GRAVITY
    add hl,bc
    ld (bar_speed),hl

    ; Compute bar y
    ld hl,(bar_y)
    ld bc,(bar_speed)
    add hl,bc
    ld (bar_y),hl

    ; Check boundaries
    bit 7,b
    jr nz,.movedone
    ; going down
    ld a,h
    or a
    cp BAR_BOTTOM
    jr c,.movedone
    ld hl,(bar_speed)
    call neg_hl
    ld (bar_speed),hl
    jr .movedone
.movedone

    ret


wait:
    push bc
    ld b,11
.loop
    djnz .loop
    pop bc
    ret

neg_hl:
    xor a
    sub l
    ld l,a
    sbc a,a
    sub h
    ld h,a
    ret
