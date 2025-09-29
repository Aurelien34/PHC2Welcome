    include inc/music.inc
    include inc/screen.inc

    section	code,text

    global start

IMAGES_BASE equ phc_file_footer
IMAGES_PHC25 equ IMAGES_BASE
IMAGES_SPEC1 equ IMAGES_PHC25+924
IMAGES_SPEC2 equ IMAGES_SPEC1+800

VRAM_LOGO_START equ $6000+32*4+8
VRAM_SPEC1 equ $6000+32*8+7
VRAM_SPEC2 equ $6000+32*10+1

start:
    di ; Disable interrupts
    ld sp,$ffff

    call install_im2

.loop:
    ; show eye catcher
    call show_eye_catcher

    ld a,MUSIC_NUMBER_SLIDESHOW
    call music_init

    ei ; enable music playing using interrupts
    call transition_to_white

    call show_rpufos

    call show_kids

    call show_ordi
    di ; disable music playing using interrupts

    call ay8910_init

    jr .loop


show_eye_catcher:
    ld hl,rlh_phc25
    ld de,IMAGES_PHC25
    call decompress_rlh
    ld hl,rlh_spec1
    ld de,IMAGES_SPEC1
    call decompress_rlh
    ld hl,rlh_spec2
    ld de,IMAGES_SPEC2
    call decompress_rlh

    call switch_to_mode_graphics_vsd_green

    ld a,$ff
    call clear_screen

    call fill_with_white

    ld c,60
    call wait_for_vbl_count

    ld a,MUSIC_NUMBER_INTRO
    call music_init

    ld hl,IMAGES_PHC25
    ld de,VRAM_LOGO_START

    ld a,1
    call pause

    ld ixl,14
    call anim

    ld a,20
    call pause

    ld ixl,4
    call anim
    push hl
    push de

    ld a,2
    call pause

    ld a,%100110
    ld (filling_pattern),a
    ld a,%011001
    ld (filling_pattern+1),a
    call fill_with_black_and_white

    ld a,2
    call pause

    ld a,%100100
    ld (filling_pattern),a
    ld a,%011000
    ld (filling_pattern+1),a
    call fill_with_black_and_white

    ld a,2
    call pause

    ld a,%000100
    ld (filling_pattern),a
    ld a,%001000
    ld (filling_pattern+1),a
    call fill_with_black_and_white

    ld a,2
    call pause

    ld a,%000000
    ld (filling_pattern),a
    ld a,%000000
    ld (filling_pattern+1),a
    call fill_with_black_and_white

    ld a,2
    call pause

    pop de
    pop hl
    ld ixl,4
    call anim

    ld a,1
    call pause

    ld hl,IMAGES_SPEC1
    ld de,VRAM_SPEC1

    ld ixl,25
    call anim_1

    ld hl,IMAGES_SPEC2
    ld de,VRAM_SPEC2

    ld ixl,42
    call anim_2

.loop
    ld a,(music_pointer)
    or a
	jr z,.music_is_over
    call pause
    jr .loop
.music_is_over:
    
    ; stop the music
    call ay8910_init

    ; show "b" and wait

    ld hl,VRAM_SPEC1+16
    ld a,%01010101
    ld (hl),a
    inc hl
    ld a,%01000011
    ld (hl),a
    
    ld hl,VRAM_SPEC1+16+32
    ld a,%01010100
    ld (hl),a
    inc hl
    ld a,%01011100
    ld (hl),a


    ld c,120
    call wait_for_vbl_count

    ret


transition_to_white:
    ld a,%000000
    ld (filling_pattern),a
    ld a,%000000
    ld (filling_pattern+1),a
    call fill_with_black_and_white

    ld c,2
    call wait_for_vbl_count

    ld a,%000100
    ld (filling_pattern),a
    ld a,%001000
    ld (filling_pattern+1),a
    call fill_with_black_and_white

    ld c,2
    call wait_for_vbl_count

    ld a,%100100
    ld (filling_pattern),a
    ld a,%011000
    ld (filling_pattern+1),a
    call fill_with_black_and_white

    ld c,2
    call wait_for_vbl_count

    ld a,%100110
    ld (filling_pattern),a
    ld a,%011001
    ld (filling_pattern+1),a
    call fill_with_black_and_white

    ld c,2
    call wait_for_vbl_count

    ld a,%111111
    ld (filling_pattern),a
    ld a,%111111
    ld (filling_pattern+1),a
    call fill_with_black_and_white

    ld c,2
    call wait_for_vbl_count

    ret

show_rpufos
    call switch_to_mode_graphics_sd_white
    ld a,%00000000
    call clear_screen
    ld hl,rlh_RPUFOS
    ld de,VRAM_ADDRESS
    call decompress_rlh

    ld b,20
.loop_rpufos:
    ld c,8
    call wait_for_vbl_count

    ld a,%01010101 ; green
    call show_rpufos_square

    ld c,8
    call wait_for_vbl_count

    ld a,%10101010 ; purple
    call show_rpufos_square
    djnz .loop_rpufos

    ret

show_kids:
    call switch_to_mode_graphics_sd_white
    ld hl,rlh_kids
    ld de,VRAM_ADDRESS
    call decompress_rlh
    call init_bar

    ld b,240
.loop_kids_bars
    call handle_bar
    call handle_bar
    call handle_bar
    djnz .loop_kids_bars

    ret

show_ordi:
    call switch_to_mode_graphics_sd_white
    ld hl,rlh_ordi
    ld de,VRAM_ADDRESS
    call decompress_rlh

    ld c,240
    call wait_for_vbl_count
    ld c,240
    call wait_for_vbl_count

    ret


show_rpufos_square:
    push hl
    push bc
    push de

    ld d,16
    ld bc,31
    ld hl,VRAM_ADDRESS+11+101*32
.loopy:
    ld (hl),a
    inc hl
    ld (hl),a
    add hl,bc
    dec d
    jr nz,.loopy

    pop de
    pop bc
    pop hl
    ret


; show 28x9 image => 14*3 = 42 bytes
show_image:
    ld iyl,3
.loopy
    ld bc,14
    ldir
    ex de,hl
    ld bc,18
    add hl,bc
    ex de,hl

    dec iyl
    jr nz,.loopy
    ret

; show 32x6 image => 16*2 = 32 bytes
show_text_1:
    ld iyl,2
.loopy
    ld bc,16
    ldir
    ex de,hl
    ld bc,16
    add hl,bc
    ex de,hl

    dec iyl
    jr nz,.loopy
    ret

; show 56x6 image => 28*2 = 32 bytes
show_text_2:
    ld iyl,2
.loopy
    ld bc,28
    ldir
    ex de,hl
    ld bc,4
    add hl,bc
    ex de,hl

    dec iyl
    jr nz,.loopy
    ret

fill_with_white:
    ld hl,VRAM_ADDRESS
    ld de,VRAM_ADDRESS+1
    ld a,%111111
    ld (hl),a
    ld bc,16*32-1
    ldir
    ret

; ixl <= image_count
anim:
    call wait_for_vbl
.loopanim
    ld a,3
    call pause
    push de
    call show_image
    pop de
    dec ixl
    jr nz,.loopanim
    ret

; ixl <= image_count
anim_1:
    call wait_for_vbl
.loopanim
    ld a,2
    call pause
    push de
    call show_text_1
    pop de
    dec ixl
    jr nz,.loopanim
    ret

; ixl <= image_count
anim_2:
    call wait_for_vbl
.loopanim
    ld a,2
    call pause
    push de
    call show_text_2
    pop de
    dec ixl
    jr nz,.loopanim
    ret

; [a] <= cycles to wait for
pause:
    push bc
    ld b,a
.loopwait
    push hl
    push de
    push bc
    call music_loop
    pop bc
    pop de
    pop hl
    push af
    call wait_for_vbl
    pop af
    djnz .loopwait
    pop bc
    ret

;    dc.b "                  BREAKPOINT                   "
filling_pattern:
    dc.b %100110
    dc.b %011001
fill_with_black_and_white:
    ld iyl,8
    ld hl,VRAM_ADDRESS
    ld de,VRAM_ADDRESS+1
.loopy
    ld a,(filling_pattern)
    ld (hl),a
    ld bc,32
    ldir
    ld a,(filling_pattern+1)
    ld (hl),a
    ld bc,32
    ldir
    
    ld a,iyl
    cp 5
    jr nz,.go_loop
    ld a,1
    call pause
.go_loop:
    dec iyl
    jr nz,.loopy
    ret

