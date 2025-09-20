    section	code,text

    global decompress_rlh, decompress_rlh_advanced
	global rlh_param_offset_start, rlh_param_extract_length

FLAG_COMPRESSION_HUFFMAN equ 7
FLAG_COMPRESSION_RLE equ 6
FLAG_CLEAR_MASK equ %00111111
FLAG_CLEAR_COMPRESSION_RLE_MASK equ %10111111

rlh_param_offset_start:
	dc.w 0
rlh_param_extract_length:
	dc.w 0

; Compression is made in 2 optional layers:
; - Layer 1 is RLE or RAW
; - Layer 2 is Huffman or RAW

; Input registers:
;-----------------
; interrupts should be disabled
; registers assignment:
; hl => source buffer pointer
; de => target buffer pointer
decompress_rlh:
	; Indicate we want to extract the whole data
	push bc
	ld bc,0
	ld (rlh_param_extract_length),bc
	ld (rlh_param_offset_start),bc
	pop bc
	jr decompress_rlh_advanced
	

; Input registers:
;-----------------
; interrupts should be disabled
; registers assignment:
; hl => source buffer pointer
; de => target buffer pointer

; Work registers:
;----------------
; c => current byte
; b => bits left to process in current byte
; ix => output bytes left to be decoded
; iyh => Huffman compression flag (for mixed huffman / RLE compression)
; iyl => RLE compression key

decompress_rlh_advanced:
	push hl
	push bc
	push de
	push ix
	push iy
    ; initialization
	; see if we have a user defined size limit
	; rlh_param_extract_length should not be null
	ld bc,(rlh_param_extract_length)
	ld a,c
	or b
	jr z,.load_target_size_from_stream
	; we still need to load size and compression flags in ix
	ld ixl,c
	; point hl to upper byte
	inc hl
	ld a,(hl) ; load upper byte
	and %11000000 ; extract compression flags
	or b ; apply mask to our upper byte of stream length
	ld ixh,a
	jr .target_size_loaded
.load_target_size_from_stream:
    ; load target size and compress flag in ix
    ld a,(hl)
    ld ixl,a
    inc hl
    ld a,(hl)
    ld ixh,a
.target_size_loaded:
    inc hl
	; decode RLE compression flag
	bit FLAG_COMPRESSION_RLE,a
	jr z,.no_decomp_rle
	call decomp_rle
	jr .end
.no_decomp_rle:
	; decode compression flag
	bit FLAG_COMPRESSION_HUFFMAN,a
	jr z,.no_decomp_huffman
	call decomp_huffman
	jr .end
.no_decomp_huffman:
	; data is not compressed
	; compute starting address in hl
	ld bc,(rlh_param_offset_start)
	add hl,bc
	; load data size in bc
	push ix
	pop bc
	; copy uncompressed data
	ldir
.end
	pop iy
	pop ix
	pop de
	pop bc
	pop hl
	ret

decomp_rle:
	; data is RLE compressed
	ld b,a ; backup a
	and 1<<FLAG_COMPRESSION_HUFFMAN
	ld iyh,a ; iyh contains the Huffman compression flag
	ld a,b
	; clear compression flags
	and FLAG_CLEAR_MASK
	ld ixh,a

	; Init for potential Huffman decomp
    ; load current byte
    ld c,(hl)
    ; 8 bits to be processed
    ld b,8

    ; load current as the key => iyl
	call rle_read_one_byte
	ld iyl,a ; key in iyl

	; iterate on bytes
.loopDecomp
	; check if the decompression is complete
	ld a,ixl ; ix is 0?
	or ixh	; OR between high and low bytes and see if it is zero
	dc.b $c8 ; "ret z" not assembled correctly by VASM!

	call rle_read_one_byte
	cp iyl
	jr z,.byte_is_compressed
	; byte is not compressed
	call store_reg_a_to_output_stream_or_not
	jr .loopDecomp

.byte_is_compressed
	; regular
	call rle_read_one_byte ; a <- move to count to replicate
	exx
	; shadow
	ld c,a ; backup a
	exx
	; regular
	call rle_read_one_byte ; counter in b
	push de
	exx
	; shadow
	ld b,a  
	pop de
	ld a,c
.loop_multi_instances
	call store_reg_a_to_output_stream_or_not
	ex af,af' ;'
	ld a,ixh
	or ixl
	jr nz,.not_over_yet
	ld b,1
.not_over_yet:
	ex af,af' ;'
	; shadow
	djnz .loop_multi_instances
	push de
	exx
	; Regular
	pop de
	jr .loopDecomp

rle_read_one_byte:
	; Check if data is Huffman compressed
	ld a,iyh
	or a
	jr nz,decompress_huffman_byte 	; ; Huffman data, decompress it warning here: optimization => jump instead of call to skip the expected RET
	; raw data, read it
	ld a,(hl)
	inc hl
	ret

decomp_huffman:
	; data is huffman compressed
	; clear compression flags
	and FLAG_CLEAR_MASK
	ld ixh,a

    ; load current byte
    ld c,(hl)
    ; 8 bits to be processed
    ld b,8

    ; now we can loop on decoding code
.loopDecomp
    call decompress_huffman_byte
    call store_reg_a_to_output_stream_or_not
	ld a,ixl ; ix is 0?
	or ixh
    jr nz,.loopDecomp
.endLoopDecomp
    ret

; result in C flag
get_next_bit:
    sll c; shift left and store bit of interest in carry flag
    ex af,af' ; '; backup status flags to shadow registers
    djnz .end ; still some bits to process

    ld b,8 ; back to first bit
    inc hl ; point to next byte
	; load next byte
    ld c,(hl)
.end
    ex af,af' ; '; restore carry flag
    ret

store_reg_a_to_output_stream_or_not:
	; determine if we have reached the offset
	push af
	push bc
	; load the offset
	ld bc,(rlh_param_offset_start)
	; check if it is 0
	ld a,b
	or c
	jr z,.store_value ; no offset or offset aleady reached
	; the offset is non zero
	; decrement it
	dec bc
	ld (rlh_param_offset_start),bc
	pop bc
	pop af
	ret
.store_value;
	pop bc
	pop af
	ld (de),a
	inc de
    dec ix
.end
	ret

decompress_huffman_byte:
;BEGIN_UNCOMPRESS_GENERATION
;Decompression algorithm takes 976 bytes

.n:
	call get_next_bit
	jp c,.n1 ; Jump size: 454
.n0:
	call get_next_bit
	jp c,.n01 ; Jump size: 204
.n00:
	call get_next_bit
	jp c,.n001 ; Jump size: 195
.n000:
	call get_next_bit
	jr c,.n0001 ; Jump size: 59
.n0000:
	call get_next_bit
	jr c,.n00001 ; Jump size: 3
.n00000:
	ld a,$04
	ret
.n00001:
	call get_next_bit
	jr c,.n000011 ; Jump size: 43
.n000010:
	call get_next_bit
	jr c,.n0000101 ; Jump size: 27
.n0000100:
	call get_next_bit
	jr c,.n00001001 ; Jump size: 3
.n00001000:
	ld a,$59
	ret
.n00001001:
	call get_next_bit
	jr c,.n000010011 ; Jump size: 11
.n000010010:
	call get_next_bit
	jr c,.n0000100101 ; Jump size: 3
.n0000100100:
	ld a,$22
	ret
.n0000100101:
	ld a,$ef
	ret
.n000010011:
	ld a,$99
	ret
.n0000101:
	call get_next_bit
	jr c,.n00001011 ; Jump size: 3
.n00001010:
	ld a,$ba
	ret
.n00001011:
	ld a,$e8
	ret
.n000011:
	ld a,$40
	ret
.n0001:
	call get_next_bit
	jr c,.n00011 ; Jump size: 3
.n00010:
	ld a,$05
	ret
.n00011:
	call get_next_bit
	jr c,.n000111 ; Jump size: 115
.n000110:
	call get_next_bit
	jr c,.n0001101 ; Jump size: 83
.n0001100:
	call get_next_bit
	jr c,.n00011001 ; Jump size: 3
.n00011000:
	ld a,$2f
	ret
.n00011001:
	call get_next_bit
	jr c,.n000110011 ; Jump size: 11
.n000110010:
	call get_next_bit
	jr c,.n0001100101 ; Jump size: 3
.n0001100100:
	ld a,$66
	ret
.n0001100101:
	ld a,$f5
	ret
.n000110011:
	call get_next_bit
	jr c,.n0001100111 ; Jump size: 19
.n0001100110:
	call get_next_bit
	jr c,.n00011001101 ; Jump size: 3
.n00011001100:
	ld a,$e1
	ret
.n00011001101:
	call get_next_bit
	jr c,.n000110011011 ; Jump size: 3
.n000110011010:
	ld a,$89
	ret
.n000110011011:
	ld a,$6b
	ret
.n0001100111:
	call get_next_bit
	jr c,.n00011001111 ; Jump size: 11
.n00011001110:
	call get_next_bit
	jr c,.n000110011101 ; Jump size: 3
.n000110011100:
	ld a,$b8
	ret
.n000110011101:
	ld a,$e2
	ret
.n00011001111:
	call get_next_bit
	jr c,.n000110011111 ; Jump size: 3
.n000110011110:
	ld a,$92
	ret
.n000110011111:
	call get_next_bit
	jr c,.n0001100111111 ; Jump size: 3
.n0001100111110:
	ld a,$94
	ret
.n0001100111111:
	ld a,$1f
	ret
.n0001101:
	call get_next_bit
	jr c,.n00011011 ; Jump size: 11
.n00011010:
	call get_next_bit
	jr c,.n000110101 ; Jump size: 3
.n000110100:
	ld a,$5f
	ret
.n000110101:
	ld a,$a2
	ret
.n00011011:
	call get_next_bit
	jr c,.n000110111 ; Jump size: 3
.n000110110:
	ld a,$27
	ret
.n000110111:
	ld a,$3f
	ret
.n000111:
	ld a,$14
	ret
.n001:
	ld a,$01
	ret
.n01:
	call get_next_bit
	jp c,.n011 ; Jump size: 147
.n010:
	call get_next_bit
	jr c,.n0101 ; Jump size: 19
.n0100:
	call get_next_bit
	jr c,.n01001 ; Jump size: 11
.n01000:
	call get_next_bit
	jr c,.n010001 ; Jump size: 3
.n010000:
	ld a,$06
	ret
.n010001:
	ld a,$15
	ret
.n01001:
	ld a,$08
	ret
.n0101:
	call get_next_bit
	jr c,.n01011 ; Jump size: 75
.n01010:
	call get_next_bit
	jr c,.n010101 ; Jump size: 67
.n010100:
	call get_next_bit
	jr c,.n0101001 ; Jump size: 43
.n0101000:
	call get_next_bit
	jr c,.n01010001 ; Jump size: 11
.n01010000:
	call get_next_bit
	jr c,.n010100001 ; Jump size: 3
.n010100000:
	ld a,$fc
	ret
.n010100001:
	ld a,$fb
	ret
.n01010001:
	call get_next_bit
	jr c,.n010100011 ; Jump size: 11
.n010100010:
	call get_next_bit
	jr c,.n0101000101 ; Jump size: 3
.n0101000100:
	ld a,$17
	ret
.n0101000101:
	ld a,$29
	ret
.n010100011:
	call get_next_bit
	jr c,.n0101000111 ; Jump size: 3
.n0101000110:
	ld a,$e5
	ret
.n0101000111:
	ld a,$f9
	ret
.n0101001:
	call get_next_bit
	jr c,.n01010011 ; Jump size: 3
.n01010010:
	ld a,$0d
	ret
.n01010011:
	call get_next_bit
	jr c,.n010100111 ; Jump size: 3
.n010100110:
	ld a,$60
	ret
.n010100111:
	ld a,$1c
	ret
.n010101:
	ld a,$bf
	ret
.n01011:
	call get_next_bit
	jr c,.n010111 ; Jump size: 3
.n010110:
	ld a,$20
	ret
.n010111:
	call get_next_bit
	jr c,.n0101111 ; Jump size: 3
.n0101110:
	ld a,$09
	ret
.n0101111:
	call get_next_bit
	jr c,.n01011111 ; Jump size: 19
.n01011110:
	call get_next_bit
	jr c,.n010111101 ; Jump size: 3
.n010111100:
	ld a,$35
	ret
.n010111101:
	call get_next_bit
	jr c,.n0101111011 ; Jump size: 3
.n0101111010:
	ld a,$d4
	ret
.n0101111011:
	ld a,$f0
	ret
.n01011111:
	ld a,$f8
	ret
.n011:
	call get_next_bit
	jr c,.n0111 ; Jump size: 3
.n0110:
	ld a,$ff
	ret
.n0111:
	call get_next_bit
	jr c,.n01111 ; Jump size: 3
.n01110:
	ld a,$54
	ret
.n01111:
	call get_next_bit
	jr c,.n011111 ; Jump size: 27
.n011110:
	call get_next_bit
	jr c,.n0111101 ; Jump size: 3
.n0111100:
	ld a,$af
	ret
.n0111101:
	call get_next_bit
	jr c,.n01111011 ; Jump size: 3
.n01111010:
	ld a,$ab
	ret
.n01111011:
	call get_next_bit
	jr c,.n011110111 ; Jump size: 3
.n011110110:
	ld a,$65
	ret
.n011110111:
	ld a,$2b
	ret
.n011111:
	call get_next_bit
	jr c,.n0111111 ; Jump size: 35
.n0111110:
	call get_next_bit
	jr c,.n01111101 ; Jump size: 27
.n01111100:
	call get_next_bit
	jr c,.n011111001 ; Jump size: 11
.n011111000:
	call get_next_bit
	jr c,.n0111110001 ; Jump size: 3
.n0111110000:
	ld a,$68
	ret
.n0111110001:
	ld a,$13
	ret
.n011111001:
	call get_next_bit
	jr c,.n0111110011 ; Jump size: 3
.n0111110010:
	ld a,$6f
	ret
.n0111110011:
	ld a,$11
	ret
.n01111101:
	ld a,$ea
	ret
.n0111111:
	ld a,$2c
	ret
.n1:
	call get_next_bit
	jp c,.n11 ; Jump size: 250
.n10:
	call get_next_bit
	jr c,.n101 ; Jump size: 2
.n100:
	xor a
	ret
.n101:
	call get_next_bit
	jr c,.n1011 ; Jump size: 107
.n1010:
	call get_next_bit
	jr c,.n10101 ; Jump size: 59
.n10100:
	call get_next_bit
	jr c,.n101001 ; Jump size: 51
.n101000:
	call get_next_bit
	jr c,.n1010001 ; Jump size: 11
.n1010000:
	call get_next_bit
	jr c,.n10100001 ; Jump size: 3
.n10100000:
	ld a,$e0
	ret
.n10100001:
	ld a,$32
	ret
.n1010001:
	call get_next_bit
	jr c,.n10100011 ; Jump size: 27
.n10100010:
	call get_next_bit
	jr c,.n101000101 ; Jump size: 3
.n101000100:
	ld a,$eb
	ret
.n101000101:
	call get_next_bit
	jr c,.n1010001011 ; Jump size: 11
.n1010001010:
	call get_next_bit
	jr c,.n10100010101 ; Jump size: 3
.n10100010100:
	ld a,$62
	ret
.n10100010101:
	ld a,$12
	ret
.n1010001011:
	ld a,$7f
	ret
.n10100011:
	ld a,$a8
	ret
.n101001:
	ld a,$80
	ret
.n10101:
	call get_next_bit
	jr c,.n101011 ; Jump size: 3
.n101010:
	ld a,$50
	ret
.n101011:
	call get_next_bit
	jr c,.n1010111 ; Jump size: 27
.n1010110:
	call get_next_bit
	jr c,.n10101101 ; Jump size: 19
.n10101100:
	call get_next_bit
	jr c,.n101011001 ; Jump size: 3
.n101011000:
	ld a,$82
	ret
.n101011001:
	call get_next_bit
	jr c,.n1010110011 ; Jump size: 3
.n1010110010:
	ld a,$fd
	ret
.n1010110011:
	ld a,$5b
	ret
.n10101101:
	ld a,$96
	ret
.n1010111:
	ld a,$07
	ret
.n1011:
	call get_next_bit
	jr c,.n10111 ; Jump size: 75
.n10110:
	call get_next_bit
	jr c,.n101101 ; Jump size: 3
.n101100:
	ld a,$02
	ret
.n101101:
	call get_next_bit
	jr c,.n1011011 ; Jump size: 3
.n1011010:
	ld a,$fa
	ret
.n1011011:
	call get_next_bit
	jr c,.n10110111 ; Jump size: 51
.n10110110:
	call get_next_bit
	jr c,.n101101101 ; Jump size: 43
.n101101100:
	call get_next_bit
	jr c,.n1011011001 ; Jump size: 35
.n1011011000:
	call get_next_bit
	jr c,.n10110110001 ; Jump size: 19
.n10110110000:
	call get_next_bit
	jr c,.n101101100001 ; Jump size: 11
.n101101100000:
	call get_next_bit
	jr c,.n1011011000001 ; Jump size: 3
.n1011011000000:
	ld a,$6e
	ret
.n1011011000001:
	ld a,$44
	ret
.n101101100001:
	ld a,$98
	ret
.n10110110001:
	call get_next_bit
	jr c,.n101101100011 ; Jump size: 3
.n101101100010:
	ld a,$e9
	ret
.n101101100011:
	ld a,$8b
	ret
.n1011011001:
	ld a,$c0
	ret
.n101101101:
	ld a,$57
	ret
.n10110111:
	ld a,$5a
	ret
.n10111:
	call get_next_bit
	jr c,.n101111 ; Jump size: 11
.n101110:
	call get_next_bit
	jr c,.n1011101 ; Jump size: 3
.n1011100:
	ld a,$1a
	ret
.n1011101:
	ld a,$95
	ret
.n101111:
	call get_next_bit
	jr c,.n1011111 ; Jump size: 3
.n1011110:
	ld a,$18
	ret
.n1011111:
	call get_next_bit
	jr c,.n10111111 ; Jump size: 3
.n10111110:
	ld a,$3b
	ret
.n10111111:
	call get_next_bit
	jr c,.n101111111 ; Jump size: 3
.n101111110:
	ld a,$d5
	ret
.n101111111:
	call get_next_bit
	jr c,.n1011111111 ; Jump size: 3
.n1011111110:
	ld a,$8a
	ret
.n1011111111:
	ld a,$9a
	ret
.n11:
	call get_next_bit
	jp c,.n111 ; Jump size: 147
.n110:
	call get_next_bit
	jr c,.n1101 ; Jump size: 3
.n1100:
	ld a,$55
	ret
.n1101:
	call get_next_bit
	jr c,.n11011 ; Jump size: 19
.n11010:
	call get_next_bit
	jr c,.n110101 ; Jump size: 11
.n110100:
	call get_next_bit
	jr c,.n1101001 ; Jump size: 3
.n1101000:
	ld a,$a0
	ret
.n1101001:
	ld a,$56
	ret
.n110101:
	ld a,$0c
	ret
.n11011:
	call get_next_bit
	jr c,.n110111 ; Jump size: 27
.n110110:
	call get_next_bit
	jr c,.n1101101 ; Jump size: 11
.n1101100:
	call get_next_bit
	jr c,.n11011001 ; Jump size: 3
.n11011000:
	ld a,$10
	ret
.n11011001:
	ld a,$a5
	ret
.n1101101:
	call get_next_bit
	jr c,.n11011011 ; Jump size: 3
.n11011010:
	ld a,$25
	ret
.n11011011:
	ld a,$19
	ret
.n110111:
	call get_next_bit
	jr c,.n1101111 ; Jump size: 51
.n1101110:
	call get_next_bit
	jr c,.n11011101 ; Jump size: 3
.n11011100:
	ld a,$33
	ret
.n11011101:
	call get_next_bit
	jr c,.n110111011 ; Jump size: 35
.n110111010:
	call get_next_bit
	jr c,.n1101110101 ; Jump size: 3
.n1101110100:
	ld a,$58
	ret
.n1101110101:
	call get_next_bit
	jr c,.n11011101011 ; Jump size: 19
.n11011101010:
	call get_next_bit
	jr c,.n110111010101 ; Jump size: 3
.n110111010100:
	ld a,$4b
	ret
.n110111010101:
	call get_next_bit
	jr c,.n1101110101011 ; Jump size: 3
.n1101110101010:
	ld a,$79
	ret
.n1101110101011:
	ld a,$88
	ret
.n11011101011:
	ld a,$16
	ret
.n110111011:
	ld a,$1b
	ret
.n1101111:
	call get_next_bit
	jr c,.n11011111 ; Jump size: 11
.n11011110:
	call get_next_bit
	jr c,.n110111101 ; Jump size: 3
.n110111100:
	ld a,$be
	ret
.n110111101:
	ld a,$69
	ret
.n11011111:
	call get_next_bit
	jr c,.n110111111 ; Jump size: 3
.n110111110:
	ld a,$ae
	ret
.n110111111:
	ld a,$2e
	ret
.n111:
	call get_next_bit
	jr c,.n1111 ; Jump size: 35
.n1110:
	call get_next_bit
	jr c,.n11101 ; Jump size: 3
.n11100:
	ld a,$03
	ret
.n11101:
	call get_next_bit
	jr c,.n111011 ; Jump size: 3
.n111010:
	ld a,$0a
	ret
.n111011:
	call get_next_bit
	jr c,.n1110111 ; Jump size: 11
.n1110110:
	call get_next_bit
	jr c,.n11101101 ; Jump size: 3
.n11101100:
	ld a,$0f
	ret
.n11101101:
	ld a,$24
	ret
.n1110111:
	ld a,$2a
	ret
.n1111:
	call get_next_bit
	jr c,.n11111 ; Jump size: 3
.n11110:
	ld a,$aa
	ret
.n11111:
	call get_next_bit
	jr c,.n111111 ; Jump size: 35
.n111110:
	call get_next_bit
	jr c,.n1111101 ; Jump size: 27
.n1111100:
	call get_next_bit
	jr c,.n11111001 ; Jump size: 11
.n11111000:
	call get_next_bit
	jr c,.n111110001 ; Jump size: 3
.n111110000:
	ld a,$a6
	ret
.n111110001:
	ld a,$6a
	ret
.n11111001:
	call get_next_bit
	jr c,.n111110011 ; Jump size: 3
.n111110010:
	ld a,$30
	ret
.n111110011:
	ld a,$a9
	ret
.n1111101:
	ld a,$28
	ret
.n111111:
	call get_next_bit
	jr c,.n1111111 ; Jump size: 11
.n1111110:
	call get_next_bit
	jr c,.n11111101 ; Jump size: 3
.n11111100:
	ld a,$0e
	ret
.n11111101:
	ld a,$0b
	ret
.n1111111:
	ld a,$fe
	ret

;END_UNCOMPRESS_GENERATION
