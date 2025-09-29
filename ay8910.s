    include inc/ay8910.inc

    section	code,text

    global ay8910_mute, ay8910_init,  ay8910_init_music, ay8910_read_command_sequence

ANIM_COUNTER_INCREMENT equ 32

init_sequence:
    dc.b AY8910_REGISTER_VOLUME_A, 0
    dc.b AY8910_REGISTER_VOLUME_B, 0
    dc.b AY8910_REGISTER_VOLUME_C, 0
    dc.b AY8910_REGISTER_MIXER, AY8910_MASK_MIXER_TONE_A&AY8910_MASK_MIXER_TONE_B&AY8910_MASK_MIXER_TONE_C&AY8910_MASK_MIXER_PORT_A_IN&AY8910_MASK_MIXER_PORT_B_IN
    dc.b AY8910_REGISTER_FREQUENCY_A_LOWER, 0
    dc.b AY8910_REGISTER_FREQUENCY_A_UPPER, 0
    dc.b AY8910_REGISTER_FREQUENCY_B_LOWER, 0
    dc.b AY8910_REGISTER_FREQUENCY_B_UPPER, 0
    dc.b AY8910_REGISTER_FREQUENCY_C_LOWER, 0
    dc.b AY8910_REGISTER_FREQUENCY_C_UPPER, 0
end_init_sequence:

music_sequence:
    dc.b AY8910_REGISTER_VOLUME_A, AY8910_FLAG_VOLUME_WITH_ENVELOPPE
    dc.b AY8910_REGISTER_VOLUME_B, AY8910_FLAG_VOLUME_WITH_ENVELOPPE
    dc.b AY8910_REGISTER_VOLUME_C, AY8910_FLAG_VOLUME_WITH_ENVELOPPE
    dc.b AY8910_REGISTER_ENVELOPPE_DURATION_UPPER, 1
    dc.b AY8910_REGISTER_ENVELOPPE_DURATION_LOWER, 0
    dc.b AY8910_REGISTER_ENVELOPPE_SHAPE, AY_ENVELOPPE_TYPE_REPEATED_ATTACK_DECAY
    dc.b AY8910_REGISTER_NOISE_PERIOD, 0
end_music_sequence:

audio_animation_counter:
    dc.w 0

ay8910_read_command_sequence:
.command_loop:
    ld a,(hl)
    inc hl
    AY_PUSH_REG
    ld a,(hl)
    inc hl
    AY_PUSH_VAL
    djnz .command_loop
    ret

ay8910_init:
ay8910_mute:
    ld hl,init_sequence
    ld b,(end_init_sequence-init_sequence)/2
    call ay8910_read_command_sequence
    xor a
    ret

ay8910_init_music:
    call ay8910_init
    ld hl,music_sequence
    ld b,(end_music_sequence-music_sequence)/2
    call ay8910_read_command_sequence
    ret
