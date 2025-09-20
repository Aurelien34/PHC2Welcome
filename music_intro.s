    include inc/ay8910.inc
    include inc/music.inc

    section	code,text

    global music_init_intro

music_instructions:
    dc.b 0,0,0,0

    dc.b 65,$9f,0,$9f
    dc.b 1,$77,0,0
    dc.b 9,$6a,0,0
    dc.b 9,$59,0,0

    dc.b 9,$50,0,0
    dc.b 9,$59,0,0
    dc.b 65,$6a,0,$be
    dc.b 1,$77,0,0

    dc.b 9,$6a,0,0
    dc.b 9,$9f,0,0
    dc.b 9,$77,0,0
    dc.b 9,$6a,0,0

    dc.b 65,$77,0,$7f
    dc.b 1,$9f,0,0
    dc.b 9,$77,0,0
    dc.b 9,$6a,0,0


    dc.b 65,$8e,0,$8e
    dc.b 1,$6a,0,0
    dc.b 9,$5f,0,0
    dc.b 9,$50,0,0

    dc.b 9,$47,0,0
    dc.b 9,$50,0,0
    dc.b 9,$5f,0,0
    dc.b 9,$6a,0,0

    dc.b 9,$5f,0,0
    dc.b 9,$8e,0,0
    dc.b 9,$6a,0,0
    dc.b 1,$5f,0,0

    dc.b 9,$5f,0,0
    dc.b 1,$8e,0,0
    dc.b 9,$6a,0,0
    dc.b 1,$5f,0,0


    dc.b 65,$77,0,$77
    dc.b 1,$5f,0,0
    dc.b 9,$50,0,0
    dc.b 9,$43,0,0

    dc.b 9,$3C,0,0
    dc.b 9,$43,0,0
    dc.b 65,$50,0,$7f
    dc.b 1,$5f,0,0

    dc.b 9,$43,0,0
    dc.b 9,$77,0,0
    dc.b 9,$5f,0,0
    dc.b 9,$50,0,0

    dc.b 65,$43,0,$9f
    dc.b 9,$77,0,0
    dc.b 9,$5f,0,0
    dc.b 9,$50,0,0

    dc.b 65,$8e,0,$8e
    dc.b 1,$6a,0,0
    dc.b 10,$5f,0,0
    dc.b 10,$47,0,0

    dc.b 10,$8e,0,0
    dc.b 10,$6a,0,0
    dc.b 10,$5f,0,0
    dc.b 10,$47,0,0

    dc.b 10,$8e,0,0
    dc.b 10,$6a,0,0
    dc.b 10,$5f,0,0
    dc.b 2,$47,0,0

    dc.b 10,$8e,0,0
    dc.b 2,$6a,0,0
    dc.b 10,$5f,0,0
    dc.b 2,$47,0,0

music_instructions_end:

init_sequence:
    dc.b AY8910_REGISTER_VOLUME_A, AY8910_FLAG_VOLUME_WITH_ENVELOPPE
    dc.b AY8910_REGISTER_VOLUME_B, 0
    dc.b AY8910_REGISTER_VOLUME_C, 15
    dc.b AY8910_REGISTER_ENVELOPPE_DURATION_UPPER, 15
    dc.b AY8910_REGISTER_ENVELOPPE_DURATION_LOWER, 0
end_init_sequence:

music_init_intro:
    ld hl,music_instructions
    ld (current_music_data_base_address),hl
    ld a,(music_instructions_end-music_instructions)/4
    ld (current_music_instructions_count),a
    ld a,44
    ld (music_animation_speed),a

    ld hl,init_sequence
    ld b,(end_init_sequence-init_sequence)/2
    call ay8910_read_command_sequence

    ret
