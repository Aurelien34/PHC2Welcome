    include inc/ay8910.inc

    global play_sample_ready,play_sample_ready_half

    section	code,text

    if DEBUG=0
REAL_HARDWARE_TIMINT_OFFSET equ 9
    else
REAL_HARDWARE_TIMINT_OFFSET equ 0
    endif

sample_ready:
    incbin res_raw/ready.raw
sample_ready_end:

play_sample_ready_half:
    ld bc,(sample_ready_end-sample_ready)*4/3/2
    jr play_sample_ready_address_and_play

play_sample_ready:
    ld bc,(sample_ready_end-sample_ready)*4/3
play_sample_ready_address_and_play:
    ld hl,sample_ready
    call play_sample
    ret

init_sound:
    ld b,14
    ld c,0
.clear_loop:
    ld a,c
    AY_PUSH_REG
    xor a
    AY_PUSH_VAL
    inc c
    djnz .clear_loop

    AYOUT AY8910_REGISTER_MIXER,AY8910_MASK_MIXER_TONE_A&AY8910_MASK_MIXER_TONE_B&AY8910_MASK_MIXER_TONE_C
    
    ret

; Sample address in HL,length in BC
play_sample:
    ; Check if length is 0
    ld a,b
    or c
	dc.b $c8 ; "ret z" not assembled correctly by VASM!

    ; Divide BC by 4 because we output 4 samples per loop
    srl b
    rr c
    srl b
    rr c

.frame_loop:
    ; === SAMPLE 0 ===
    ld a,(hl)       ; 7
    and $3F         ; 7
    call ay_output  ; 249 (call 17 + ret 10 + internal)
    
    ; Delay 0 (Target 287 T-states)
    ld d,17-REAL_HARDWARE_TIMINT_OFFSET         ; 7 + 16*16 + 11 = 274
    ; 287 - 274 = 13 (Target 550 total)
.del0: dec d        ; 4
    jr nz,.del0     ; 12/7
    nop             ; 4
    nop             ; 4
    nop             ; 4

    ; === SAMPLE 1 ===
    ld a,(hl)       ; 7
    rlca            ; 4
    rlca            ; 4
    and $03         ; 7
    ld e,a          ; 4
    inc hl          ; 6
    ld a,(hl)       ; 7
    and $0F         ; 7
    add a,a         ; 4
    add a,a         ; 4
    or e            ; 4
    call ay_output  ; 249
    
    ; Delay 1 (Target 243 T-states)
    ld d,15-REAL_HARDWARE_TIMINT_OFFSET         ; 7 + 14*16 + 11 = 242
    ; 243 - 242 = 1
.del1: dec d        ; 4
    jr nz,.del1     ; 12/7

    ; === SAMPLE 2 ===
    ld a,(hl)       ; 7
    rrca            ; 4
    rrca            ; 4
    rrca            ; 4
    rrca            ; 4
    and $0F         ; 7
    ld e,a          ; 4
    inc hl          ; 6
    ld a,(hl)       ; 7
    and $03         ; 7
    add a,a         ; 4
    add a,a         ; 4
    add a,a         ; 4
    add a,a         ; 4
    or e            ; 4
    call ay_output  ; 249
    
    ; Delay 2 (Target 227 T-states)
    ld d,14-REAL_HARDWARE_TIMINT_OFFSET         ; 7 + 13*16 + 11 = 226
    ; 227 - 226 = 1
.del2: dec d        ; 4
    jr nz,.del2     ; 12/7

    ; === SAMPLE 3 ===
    ld a,(hl)       ; 7
    rrca            ; 4
    rrca            ; 4
    and $3F         ; 7
    inc hl          ; 6
    call ay_output  ; 249
    
    ; Delay 3 (Target 249 T-states)
    ld d,15-REAL_HARDWARE_TIMINT_OFFSET         ; 7 + 14*16 + 11 = 242
    add a,0         ; 7
    ; 242 + 7 = 249
.del3: dec d        ; 4
    jr nz,.del3     ; 12/7
    
    ; === LOOP OVERHEAD ===
    dec bc          ; 6
    ld a,b          ; 4
    or c            ; 4
    jp nz,.frame_loop ; 10
    
    ret

ay_output:
    ld e,a
    ld d,0
    push hl
    ld hl,volume_table
    add hl,de
    ld e,(hl)
    ld a,e
    and $0f
    ld h,a
    AYOUT AY8910_REGISTER_VOLUME_C,h
    ld l,h
    bit 5,e
    jr z,.skip_b
    inc l
.skip_b:
    AYOUT AY8910_REGISTER_VOLUME_B,l
    ld l,h
    bit 4,e
    jr z,.skip_a
    inc l
.skip_a:
    AYOUT AY8910_REGISTER_VOLUME_A,l
    pop hl
    ret

volume_table:
    ; Table de conversion compactee 46 octets (Bits 0-3 = Base C,Bit 4 = Flag A+1,Bit 5 = Flag B+1)
    dc.b $00,$10,$30,$01,$11,$31,$02,$12,$32,$03,$13,$33,$04,$14,$34,$05,$15,$35
    dc.b $06,$16,$36,$07,$17,$37,$08,$18,$38,$09,$19,$39,$0a,$1a,$3a,$0b,$1b,$3b
    dc.b $0c,$1c,$3c,$0d,$1d,$3d,$0e,$1e,$3e,$0f
