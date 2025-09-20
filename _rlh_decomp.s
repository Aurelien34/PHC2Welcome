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
;Decompression algorithm takes 987 bytes

.n:
	call get_next_bit
	jp c,.n1 ; Jump size: 439
.n0:
	call get_next_bit
	jp c,.n01 ; Jump size: 206
.n00:
	call get_next_bit
	jp c,.n001 ; Jump size: 197
.n000:
	call get_next_bit
	jr c,.n0001 ; Jump size: 43
.n0000:
	call get_next_bit
	jr c,.n00001 ; Jump size: 3
.n00000:
	ld a,$04
	ret
.n00001:
	call get_next_bit
	jr c,.n000011 ; Jump size: 27
.n000010:
	call get_next_bit
	jr c,.n0000101 ; Jump size: 11
.n0000100:
	call get_next_bit
	jr c,.n00001001 ; Jump size: 3
.n00001000:
	ld a,$a9
	ret
.n00001001:
	ld a,$6a
	ret
.n0000101:
	call get_next_bit
	jr c,.n00001011 ; Jump size: 3
.n00001010:
	ld a,$e8
	ret
.n00001011:
	ld a,$2f
	ret
.n000011:
	ld a,$14
	ret
.n0001:
	call get_next_bit
	jp c,.n00011 ; Jump size: 140
.n00010:
	call get_next_bit
	jp c,.n000101 ; Jump size: 131
.n000100:
	call get_next_bit
	jr c,.n0001001 ; Jump size: 59
.n0001000:
	call get_next_bit
	jr c,.n00010001 ; Jump size: 43
.n00010000:
	call get_next_bit
	jr c,.n000100001 ; Jump size: 11
.n000100000:
	call get_next_bit
	jr c,.n0001000001 ; Jump size: 3
.n0001000000:
	ld a,$ef
	ret
.n0001000001:
	ld a,$66
	ret
.n000100001:
	call get_next_bit
	jr c,.n0001000011 ; Jump size: 3
.n0001000010:
	ld a,$f5
	ret
.n0001000011:
	call get_next_bit
	jr c,.n00010000111 ; Jump size: 3
.n00010000110:
	ld a,$e1
	ret
.n00010000111:
	call get_next_bit
	jr c,.n000100001111 ; Jump size: 3
.n000100001110:
	ld a,$89
	ret
.n000100001111:
	ld a,$6b
	ret
.n00010001:
	call get_next_bit
	jr c,.n000100011 ; Jump size: 3
.n000100010:
	ld a,$5f
	ret
.n000100011:
	ld a,$a2
	ret
.n0001001:
	call get_next_bit
	jr c,.n00010011 ; Jump size: 51
.n00010010:
	call get_next_bit
	jr c,.n000100101 ; Jump size: 3
.n000100100:
	ld a,$27
	ret
.n000100101:
	call get_next_bit
	jr c,.n0001001011 ; Jump size: 35
.n0001001010:
	call get_next_bit
	jr c,.n00010010101 ; Jump size: 11
.n00010010100:
	call get_next_bit
	jr c,.n000100101001 ; Jump size: 3
.n000100101000:
	ld a,$b8
	ret
.n000100101001:
	ld a,$e2
	ret
.n00010010101:
	call get_next_bit
	jr c,.n000100101011 ; Jump size: 3
.n000100101010:
	ld a,$92
	ret
.n000100101011:
	call get_next_bit
	jr c,.n0001001010111 ; Jump size: 3
.n0001001010110:
	ld a,$94
	ret
.n0001001010111:
	ld a,$1f
	ret
.n0001001011:
	ld a,$17
	ret
.n00010011:
	call get_next_bit
	jr c,.n000100111 ; Jump size: 3
.n000100110:
	ld a,$3f
	ret
.n000100111:
	ld a,$fc
	ret
.n000101:
	ld a,$40
	ret
.n00011:
	ld a,$05
	ret
.n001:
	ld a,$01
	ret
.n01:
	call get_next_bit
	jr c,.n011 ; Jump size: 83
.n010:
	call get_next_bit
	jr c,.n0101 ; Jump size: 75
.n0100:
	call get_next_bit
	jr c,.n01001 ; Jump size: 67
.n01000:
	call get_next_bit
	jr c,.n010001 ; Jump size: 3
.n010000:
	ld a,$06
	ret
.n010001:
	call get_next_bit
	jr c,.n0100011 ; Jump size: 43
.n0100010:
	call get_next_bit
	jr c,.n01000101 ; Jump size: 11
.n01000100:
	call get_next_bit
	jr c,.n010001001 ; Jump size: 3
.n010001000:
	ld a,$fb
	ret
.n010001001:
	ld a,$1e
	ret
.n01000101:
	call get_next_bit
	jr c,.n010001011 ; Jump size: 11
.n010001010:
	call get_next_bit
	jr c,.n0100010101 ; Jump size: 3
.n0100010100:
	ld a,$29
	ret
.n0100010101:
	ld a,$e5
	ret
.n010001011:
	call get_next_bit
	jr c,.n0100010111 ; Jump size: 3
.n0100010110:
	ld a,$f9
	ret
.n0100010111:
	ld a,$d4
	ret
.n0100011:
	call get_next_bit
	jr c,.n01000111 ; Jump size: 3
.n01000110:
	ld a,$69
	ret
.n01000111:
	ld a,$0d
	ret
.n01001:
	ld a,$08
	ret
.n0101:
	ld a,$ff
	ret
.n011:
	call get_next_bit
	jr c,.n0111 ; Jump size: 75
.n0110:
	call get_next_bit
	jr c,.n01101 ; Jump size: 11
.n01100:
	call get_next_bit
	jr c,.n011001 ; Jump size: 3
.n011000:
	ld a,$bf
	ret
.n011001:
	ld a,$20
	ret
.n01101:
	call get_next_bit
	jr c,.n011011 ; Jump size: 27
.n011010:
	call get_next_bit
	jr c,.n0110101 ; Jump size: 3
.n0110100:
	ld a,$09
	ret
.n0110101:
	call get_next_bit
	jr c,.n01101011 ; Jump size: 11
.n01101010:
	call get_next_bit
	jr c,.n011010101 ; Jump size: 3
.n011010100:
	ld a,$65
	ret
.n011010101:
	ld a,$60
	ret
.n01101011:
	ld a,$f8
	ret
.n011011:
	call get_next_bit
	jr c,.n0110111 ; Jump size: 3
.n0110110:
	ld a,$af
	ret
.n0110111:
	call get_next_bit
	jr c,.n01101111 ; Jump size: 11
.n01101110:
	call get_next_bit
	jr c,.n011011101 ; Jump size: 3
.n011011100:
	ld a,$35
	ret
.n011011101:
	ld a,$2b
	ret
.n01101111:
	ld a,$ab
	ret
.n0111:
	call get_next_bit
	jr c,.n01111 ; Jump size: 51
.n01110:
	call get_next_bit
	jr c,.n011101 ; Jump size: 3
.n011100:
	ld a,$15
	ret
.n011101:
	call get_next_bit
	jr c,.n0111011 ; Jump size: 35
.n0111010:
	call get_next_bit
	jr c,.n01110101 ; Jump size: 27
.n01110100:
	call get_next_bit
	jr c,.n011101001 ; Jump size: 11
.n011101000:
	call get_next_bit
	jr c,.n0111010001 ; Jump size: 3
.n0111010000:
	ld a,$f0
	ret
.n0111010001:
	ld a,$68
	ret
.n011101001:
	call get_next_bit
	jr c,.n0111010011 ; Jump size: 3
.n0111010010:
	ld a,$13
	ret
.n0111010011:
	ld a,$11
	ret
.n01110101:
	ld a,$ea
	ret
.n0111011:
	ld a,$2c
	ret
.n01111:
	ld a,$54
	ret
.n1:
	call get_next_bit
	jp c,.n11 ; Jump size: 259
.n10:
	call get_next_bit
	jr c,.n101 ; Jump size: 2
.n100:
	xor a
	ret
.n101:
	call get_next_bit
	jp c,.n1011 ; Jump size: 163
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
	jr c,.n101011 ; Jump size: 11
.n101010:
	call get_next_bit
	jr c,.n1010101 ; Jump size: 3
.n1010100:
	ld a,$95
	ret
.n1010101:
	ld a,$fa
	ret
.n101011:
	call get_next_bit
	jr c,.n1010111 ; Jump size: 75
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
	call get_next_bit
	jr c,.n101011011 ; Jump size: 43
.n101011010:
	call get_next_bit
	jr c,.n1010110101 ; Jump size: 3
.n1010110100:
	ld a,$6f
	ret
.n1010110101:
	call get_next_bit
	jr c,.n10101101011 ; Jump size: 19
.n10101101010:
	call get_next_bit
	jr c,.n101011010101 ; Jump size: 11
.n101011010100:
	call get_next_bit
	jr c,.n1010110101001 ; Jump size: 3
.n1010110101000:
	ld a,$6e
	ret
.n1010110101001:
	ld a,$8f
	ret
.n101011010101:
	ld a,$98
	ret
.n10101101011:
	call get_next_bit
	jr c,.n101011010111 ; Jump size: 3
.n101011010110:
	ld a,$e9
	ret
.n101011010111:
	ld a,$8b
	ret
.n101011011:
	ld a,$57
	ret
.n1010111:
	ld a,$07
	ret
.n1011:
	call get_next_bit
	jr c,.n10111 ; Jump size: 11
.n10110:
	call get_next_bit
	jr c,.n101101 ; Jump size: 3
.n101100:
	ld a,$50
	ret
.n101101:
	ld a,$02
	ret
.n10111:
	call get_next_bit
	jr c,.n101111 ; Jump size: 27
.n101110:
	call get_next_bit
	jr c,.n1011101 ; Jump size: 3
.n1011100:
	ld a,$a5
	ret
.n1011101:
	call get_next_bit
	jr c,.n10111011 ; Jump size: 3
.n10111010:
	ld a,$5a
	ret
.n10111011:
	call get_next_bit
	jr c,.n101110111 ; Jump size: 3
.n101110110:
	ld a,$a6
	ret
.n101110111:
	ld a,$d5
	ret
.n101111:
	call get_next_bit
	jr c,.n1011111 ; Jump size: 27
.n1011110:
	call get_next_bit
	jr c,.n10111101 ; Jump size: 3
.n10111100:
	ld a,$3b
	ret
.n10111101:
	call get_next_bit
	jr c,.n101111011 ; Jump size: 11
.n101111010:
	call get_next_bit
	jr c,.n1011110101 ; Jump size: 3
.n1011110100:
	ld a,$c0
	ret
.n1011110101:
	ld a,$99
	ret
.n101111011:
	ld a,$96
	ret
.n1011111:
	ld a,$18
	ret
.n11:
	call get_next_bit
	jr c,.n111 ; Jump size: 67
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
	ld a,$1a
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
	ld a,$25
	ret
.n1101101:
	call get_next_bit
	jr c,.n11011011 ; Jump size: 3
.n11011010:
	ld a,$19
	ret
.n11011011:
	ld a,$33
	ret
.n110111:
	ld a,$0a
	ret
.n111:
	call get_next_bit
	jp c,.n1111 ; Jump size: 140
.n1110:
	call get_next_bit
	jp c,.n11101 ; Jump size: 131
.n11100:
	call get_next_bit
	jr c,.n111001 ; Jump size: 99
.n111000:
	call get_next_bit
	jr c,.n1110001 ; Jump size: 35
.n1110000:
	call get_next_bit
	jr c,.n11100001 ; Jump size: 19
.n11100000:
	call get_next_bit
	jr c,.n111000001 ; Jump size: 11
.n111000000:
	call get_next_bit
	jr c,.n1110000001 ; Jump size: 3
.n1110000000:
	ld a,$8a
	ret
.n1110000001:
	ld a,$58
	ret
.n111000001:
	ld a,$1b
	ret
.n11100001:
	call get_next_bit
	jr c,.n111000011 ; Jump size: 3
.n111000010:
	ld a,$be
	ret
.n111000011:
	ld a,$ae
	ret
.n1110001:
	call get_next_bit
	jr c,.n11100011 ; Jump size: 51
.n11100010:
	call get_next_bit
	jr c,.n111000101 ; Jump size: 3
.n111000100:
	ld a,$2e
	ret
.n111000101:
	call get_next_bit
	jr c,.n1110001011 ; Jump size: 27
.n1110001010:
	call get_next_bit
	jr c,.n11100010101 ; Jump size: 19
.n11100010100:
	call get_next_bit
	jr c,.n111000101001 ; Jump size: 3
.n111000101000:
	ld a,$4b
	ret
.n111000101001:
	call get_next_bit
	jr c,.n1110001010011 ; Jump size: 3
.n1110001010010:
	ld a,$44
	ret
.n1110001010011:
	ld a,$88
	ret
.n11100010101:
	ld a,$16
	ret
.n1110001011:
	call get_next_bit
	jr c,.n11100010111 ; Jump size: 3
.n11100010110:
	ld a,$9a
	ret
.n11100010111:
	ld a,$22
	ret
.n11100011:
	ld a,$0f
	ret
.n111001:
	call get_next_bit
	jr c,.n1110011 ; Jump size: 3
.n1110010:
	ld a,$2a
	ret
.n1110011:
	call get_next_bit
	jr c,.n11100111 ; Jump size: 3
.n11100110:
	ld a,$24
	ret
.n11100111:
	call get_next_bit
	jr c,.n111001111 ; Jump size: 3
.n111001110:
	ld a,$30
	ret
.n111001111:
	ld a,$1c
	ret
.n11101:
	ld a,$aa
	ret
.n1111:
	call get_next_bit
	jr c,.n11111 ; Jump size: 3
.n11110:
	ld a,$03
	ret
.n11111:
	call get_next_bit
	jr c,.n111111 ; Jump size: 19
.n111110:
	call get_next_bit
	jr c,.n1111101 ; Jump size: 3
.n1111100:
	ld a,$28
	ret
.n1111101:
	call get_next_bit
	jr c,.n11111011 ; Jump size: 3
.n11111010:
	ld a,$0e
	ret
.n11111011:
	ld a,$56
	ret
.n111111:
	call get_next_bit
	jr c,.n1111111 ; Jump size: 3
.n1111110:
	ld a,$fe
	ret
.n1111111:
	call get_next_bit
	jr c,.n11111111 ; Jump size: 3
.n11111110:
	ld a,$0b
	ret
.n11111111:
	call get_next_bit
	jr c,.n111111111 ; Jump size: 3
.n111111110:
	ld a,$59
	ret
.n111111111:
	ld a,$ba
	ret

;END_UNCOMPRESS_GENERATION
