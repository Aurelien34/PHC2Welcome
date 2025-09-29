    include inc/ay8910.inc
    include inc/music.inc

    section	code,text

    global music_init, music_loop, music_interrupt_handler
    global current_music_data_base_address, current_music_instructions_count
    global music_animation_counter, music_animation_speed, music_pointer

music_animation_speed
    dc.b 0

music_animation_counter:
    dc.b 0

music_pointer:
    dc.b 0

current_music_data_base_address:
    dc.w $ffff

current_music_instructions_count:
    dc.b $ff

; Music number in register [a]
    dc.b "                  BREAKPOINT                   "
music_init:
    push af
    call ay8910_init_music
    pop af
    cp MUSIC_NUMBER_INTRO
    jp nz,.not_music_intro
    call music_init_intro
    jp .common
.not_music_intro:
    cp MUSIC_NUMBER_SLIDESHOW
    jp nz,.not_music_slideshow
    call music_init_slideshow
.not_music_slideshow:
.common:
    ld a,$ff ; ensure we trigger the carry flag on next round
    ld (music_animation_counter),a
    ld a,1 ; skip 1st row
    ld (music_pointer),a
    ret

music_loop:
    ; increment counter
    ld a,(music_animation_speed)
    ld b,a
    ld a,(music_animation_counter)
    add b
    jr nc,.update_counter
    ; overflow here, reset counter
    ld a,0 ; don't optimize this, as we don't want to loose the carry flag
.update_counter:
    ld (music_animation_counter),a
    ; return if nothing to be done
    dc.b $d0 ; "ret nc" not assembled correctly by VASM!
    ; Play current pointer position
    ld a,(music_pointer)
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    ld bc,(current_music_data_base_address)
    add hl,bc
    ; Now read notes
    ; First byte is flags
    ld b,(hl)
    inc hl
    bit MUSIC_BIT_ATTACK,b
    jr z,.no_reset_enveloppe
    AYOUT AY8910_REGISTER_ENVELOPPE_SHAPE, AY_ENVELOPPE_TYPE_SINGLE_DECAY_THEN_OFF
.no_reset_enveloppe:
    bit MUSIC_BIT_VOL_DOWN_A,b
    jr z,.no_vol_down_a
    ld a,AY8910_REGISTER_VOLUME_A
    AY_PUSH_REG
    AY_READ_VAL
    dec a
    jp m,.no_vol_down_a
    AY_PUSH_VAL
.no_vol_down_a:
    bit MUSIC_BIT_VOL_DOWN_B,b
    jr z,.no_vol_down_b
    ld a,AY8910_REGISTER_VOLUME_B
    AY_PUSH_REG
    AY_READ_VAL
    dec a
    jp m,.no_vol_down_b
    AY_PUSH_VAL
.no_vol_down_b:
    bit MUSIC_BIT_VOL_DOWN_C,b
    jr z,.no_vol_down_c
    ld a,AY8910_REGISTER_VOLUME_C
    AY_PUSH_REG
    AY_READ_VAL
    dec a
    jp m,.no_vol_down_c
    AY_PUSH_VAL
.no_vol_down_c:
    bit MUSIC_BIT_VOL_MAX_A,b
    jr z,.no_vol_max_a
    AYOUT AY8910_REGISTER_VOLUME_A,15
.no_vol_max_a:
    bit MUSIC_BIT_VOL_MAX_B,b
    jr z,.no_vol_max_b
    AYOUT AY8910_REGISTER_VOLUME_B,15
.no_vol_max_b:
    bit MUSIC_BIT_VOL_MAX_C,b
    jr z,.no_vol_max_c
    AYOUT AY8910_REGISTER_VOLUME_C,16
.no_vol_max_c:
    bit MUSIC_BIT_UPPER_BYTE_1_CHAN_B,b
    jr z,.no_upper_byte_1_chan_b
    AYOUT AY8910_REGISTER_FREQUENCY_B_UPPER,1
    jr .continue
.no_upper_byte_1_chan_b:
    AYOUT AY8910_REGISTER_FREQUENCY_B_UPPER,0
.continue:

    ; Channel A
    ld a,(hl)
    inc hl
    or a
    jr z,.skip_channel_a
    call play_tone_frequency_channel_a
.skip_channel_a:
    ; Channel B
    ld a,(hl)
    inc hl
    or a
    jr z,.skip_channel_b
    call play_tone_frequency_channel_b
.skip_channel_b:
    ; Channel C
    ld a,(hl)
    inc hl
    or a
    jr z,.skip_channel_c
    call play_tone_frequency_channel_c
.skip_channel_c:

    ; Update pointer position
    ld a,(current_music_instructions_count)
    ld b,a
    ld a,(music_pointer)
    inc a
    cp b
    jr nz,.update_pointer
    ld a,0 ; preserve zero flag
.update_pointer    
    ld (music_pointer),a
    ret

; frequency in [a]
play_tone_frequency_channel_a:
    ex af,af' ;'
    ld a,AY8910_REGISTER_FREQUENCY_A_LOWER
    AY_PUSH_REG
    ex af,af' ;'
    AY_PUSH_VAL
    ret

; frequency in [a]
play_tone_frequency_channel_b:
    ex af,af' ;'
    ld a,AY8910_REGISTER_FREQUENCY_B_LOWER
    AY_PUSH_REG
    ex af,af' ;'
    AY_PUSH_VAL
    ret

; frequency in [a]
play_tone_frequency_channel_c:
    ex af,af' ;'
    ld a,AY8910_REGISTER_FREQUENCY_C_LOWER
    AY_PUSH_REG
    ex af,af' ;'
    AY_PUSH_VAL
    ret

vbl_counter:
    dc.b 0
music_interrupt_handler:
    push af
    ex af,af'
    push af
    push hl
    push de
    push bc

    ld a,(vbl_counter)
    inc a
    ld (vbl_counter),a

    call music_loop

    pop bc
    pop de
    pop hl
    pop af
    ex af,af'
    pop af
    ei
    reti
