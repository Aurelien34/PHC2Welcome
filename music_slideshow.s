    include inc/ay8910.inc
    include inc/music.inc

    section	code,text

    global music_init_slideshow

music_instructions:
    dc.b 0,0,0,0

    ; 1
    dc.b $80,0,$de,0
    dc.b $00,0,$ef,0
    dc.b $80,0,$de,0
    dc.b $00,0,$ef,0
    dc.b $80,0,$de,0
    dc.b $00,0,$ef,0
    dc.b $80,0,$de,0
    dc.b $00,0,$ef,0

    ; 2
    dc.b $80,0,$de,0
    dc.b $00,0,$ef,0
    dc.b $80,0,$de,0
    dc.b $00,0,$ef,0
    dc.b $80,0,$de,0
    dc.b $00,0,$ef,0
    dc.b $80,0,$de,0
    dc.b $00,0,$ef,0

    ; 3
    dc.b $81,$77,$de,0
    dc.b $01,$77,$ef,0
    dc.b $81,$86,$de,0  
    dc.b $01,$77,$ef,0  
    dc.b $80,0,$de,0  
    dc.b $01,$9f,$ef,0  
    dc.b $80,0,$de,0  
    dc.b $01,$9f,$ef,0  

    ;4
    dc.b $81,$77,$de,0
    dc.b $01,$59,$ef,0
    dc.b $81,$5f,$de,0
    dc.b $01,$77,$ef,0
    dc.b $80,0,$de,0
    dc.b $00,0,$ef,0
    dc.b $80,0,$de,0
    dc.b $00,0,$ef,0

    ; 5
    dc.b $81,$77,$de,0
    dc.b $01,$77,$ef,0
    dc.b $81,$86,$de,0  
    dc.b $01,$77,$ef,0  
    dc.b $80,0,$de,0  
    dc.b $01,$9f,$ef,0  
    dc.b $80,0,$de,0  
    dc.b $01,$9f,$ef,0  

    ; 6
    dc.b $81,$77,$de,0
    dc.b $01,$59,$ef,0
    dc.b $81,$5f,$de,0
    dc.b $01,$77,$ef,0
    dc.b $80,0,$de,0
    dc.b $00,0,$ef,0
    dc.b $80,0,$de,0
    dc.b $00,0,$ef,0

    ; 7
    dc.b $81,$ef,$de,0
    dc.b $01,$ef,$ef,0
    dc.b $81,$ef,$de,0
    dc.b $01,$ef,$ef,0
    dc.b $81,$be,$de,0
    dc.b $00,0,$ef,0
    dc.b $81,$be,$de,0
    dc.b $01,$be,$ef,0

    ; 8
    dc.b $81,$9f,$de,0
    dc.b $01,$9f,$ef,0
    dc.b $80,0,$de,0
    dc.b $01,$5f,$ef,0
    dc.b $80,0,$de,0
    dc.b $01,$6a,$ef,0
    dc.b $81,$77,$de,0
    dc.b $00,0,$ef,0

    ; 9
    dc.b $81,$77,$de,0
    dc.b $01,$77,$ef,0
    dc.b $81,$86,$de,0  
    dc.b $01,$77,$ef,0  
    dc.b $80,0,$de,0  
    dc.b $01,$9f,$ef,0  
    dc.b $80,0,$de,0  
    dc.b $01,$9f,$ef,0  

    ; 10
    dc.b $81,$77,$de,0
    dc.b $01,$59,$ef,0
    dc.b $81,$5f,$de,0
    dc.b $01,$77,$ef,0
    dc.b $80,0,$de,0
    dc.b $00,0,$ef,0
    dc.b $80,0,$de,0
    dc.b $00,0,$ef,0
;
    ; 11
    dc.b $81,$ef,$de,0
    dc.b $01,$ef,$ef,0
    dc.b $81,$ef,$de,0
    dc.b $01,$ef,$ef,0
    dc.b $81,$be,$de,0
    dc.b $01,$be,$ef,0
    dc.b $81,$be,$de,0
    dc.b $01,$be,$ef,0
;
    ; 12
    dc.b $81,$9f,$de,0
    dc.b $01,$9f,$ef,0
    dc.b $81,$9f,$de,0
    dc.b $01,$9f,$ef,0
    dc.b $81,$5f,$de,0
    dc.b $01,$6a,$ef,0
    dc.b $81,$77,$de,0
    dc.b $00,0,$ef,0

    ; 13
    dc.b $81+14,$77,$de,0
    dc.b $01+14,$77,$ef,0
    dc.b $81+14,$86,$de,0  
    dc.b $01+14,$77,$ef,0  
    dc.b $80+14,0,$de,0  
    dc.b $01+14,$9f,$ef,0  
    dc.b $80+14,0,$de,0  
    dc.b $01+14,$9f,$ef,0  

    ; 14
    dc.b $81+14,$77,$de,0
    dc.b $01+14,$59,$ef,0
    dc.b $81+14,$5f,$de,0
    dc.b $01+14,$77,$ef,0
    dc.b $80+14,0,$de,0
    dc.b $00+14,0,$ef,0
    dc.b $80+14,0,$de,0
    dc.b $00+14,0,$ef,0

music_instructions_end:

init_sequence:
    dc.b AY8910_REGISTER_VOLUME_A, AY8910_FLAG_VOLUME_WITH_ENVELOPPE
    dc.b AY8910_REGISTER_VOLUME_B, 10
    dc.b AY8910_REGISTER_VOLUME_C, AY8910_FLAG_VOLUME_WITH_ENVELOPPE
    dc.b AY8910_REGISTER_ENVELOPPE_DURATION_UPPER, 12
    dc.b AY8910_REGISTER_ENVELOPPE_DURATION_LOWER, 0
    dc.b AY8910_REGISTER_FREQUENCY_A_UPPER,0
    dc.b AY8910_REGISTER_FREQUENCY_B_UPPER,0
    dc.b AY8910_REGISTER_FREQUENCY_C_UPPER,0
end_init_sequence:

music_init_slideshow:
    ld hl,music_instructions
    ld (current_music_data_base_address),hl
    ld a,(music_instructions_end-music_instructions)/4
    ld (current_music_instructions_count),a
    ld a,9
    ld (music_animation_speed),a

    ld hl,init_sequence
    ld b,(end_init_sequence-init_sequence)/2
    call ay8910_read_command_sequence

    ret
