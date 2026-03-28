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
;Decompression algorithm takes 944 bytes

.n:
	call get_next_bit
	jp c,.n1 ; Jump size: 219
.n0:
	call get_next_bit
	jr c,.n01 ; Jump size: 67
.n00:
	call get_next_bit
	jr c,.n001 ; Jump size: 3
.n000:
	ld a,$01
	ret
.n001:
	call get_next_bit
	jr c,.n0011 ; Jump size: 3
.n0010:
	ld a,$55
	ret
.n0011:
	call get_next_bit
	jr c,.n00111 ; Jump size: 3
.n00110:
	ld a,$0a
	ret
.n00111:
	call get_next_bit
	jr c,.n001111 ; Jump size: 11
.n001110:
	call get_next_bit
	jr c,.n0011101 ; Jump size: 3
.n0011100:
	ld a,$56
	ret
.n0011101:
	ld a,$33
	ret
.n001111:
	call get_next_bit
	jr c,.n0011111 ; Jump size: 11
.n0011110:
	call get_next_bit
	jr c,.n00111101 ; Jump size: 3
.n00111100:
	ld a,$1b
	ret
.n00111101:
	ld a,$be
	ret
.n0011111:
	call get_next_bit
	jr c,.n00111111 ; Jump size: 3
.n00111110:
	ld a,$6a
	ret
.n00111111:
	ld a,$ae
	ret
.n01:
	call get_next_bit
	jr c,.n011 ; Jump size: 59
.n010:
	call get_next_bit
	jr c,.n0101 ; Jump size: 3
.n0100:
	ld a,$aa
	ret
.n0101:
	call get_next_bit
	jr c,.n01011 ; Jump size: 27
.n01010:
	call get_next_bit
	jr c,.n010101 ; Jump size: 19
.n010100:
	call get_next_bit
	jr c,.n0101001 ; Jump size: 3
.n0101000:
	ld a,$0f
	ret
.n0101001:
	call get_next_bit
	jr c,.n01010011 ; Jump size: 3
.n01010010:
	ld a,$2e
	ret
.n01010011:
	ld a,$30
	ret
.n010101:
	ld a,$2a
	ret
.n01011:
	call get_next_bit
	jr c,.n010111 ; Jump size: 11
.n010110:
	call get_next_bit
	jr c,.n0101101 ; Jump size: 3
.n0101100:
	ld a,$24
	ret
.n0101101:
	ld a,$0e
	ret
.n010111:
	ld a,$28
	ret
.n011:
	call get_next_bit
	jr c,.n0111 ; Jump size: 75
.n0110:
	call get_next_bit
	jr c,.n01101 ; Jump size: 3
.n01100:
	ld a,$04
	ret
.n01101:
	call get_next_bit
	jr c,.n011011 ; Jump size: 43
.n011010:
	call get_next_bit
	jr c,.n0110101 ; Jump size: 35
.n0110100:
	call get_next_bit
	jr c,.n01101001 ; Jump size: 3
.n01101000:
	ld a,$0d
	ret
.n01101001:
	call get_next_bit
	jr c,.n011010011 ; Jump size: 11
.n011010010:
	call get_next_bit
	jr c,.n0110100101 ; Jump size: 3
.n0110100100:
	ld a,$16
	ret
.n0110100101:
	ld a,$22
	ret
.n011010011:
	call get_next_bit
	jr c,.n0110100111 ; Jump size: 3
.n0110100110:
	ld a,$ef
	ret
.n0110100111:
	ld a,$5f
	ret
.n0110101:
	ld a,$0b
	ret
.n011011:
	call get_next_bit
	jr c,.n0110111 ; Jump size: 3
.n0110110:
	ld a,$af
	ret
.n0110111:
	call get_next_bit
	jr c,.n01101111 ; Jump size: 3
.n01101110:
	ld a,$a9
	ret
.n01101111:
	ld a,$ba
	ret
.n0111:
	ld a,$ff
	ret
.n1:
	call get_next_bit
	jp c,.n11 ; Jump size: 195
.n10:
	call get_next_bit
	jp c,.n101 ; Jump size: 187
.n100:
	call get_next_bit
	jr c,.n1001 ; Jump size: 99
.n1000:
	call get_next_bit
	jr c,.n10001 ; Jump size: 83
.n10000:
	call get_next_bit
	jr c,.n100001 ; Jump size: 27
.n100000:
	call get_next_bit
	jr c,.n1000001 ; Jump size: 11
.n1000000:
	call get_next_bit
	jr c,.n10000001 ; Jump size: 3
.n10000000:
	ld a,$e8
	ret
.n10000001:
	ld a,$2f
	ret
.n1000001:
	call get_next_bit
	jr c,.n10000011 ; Jump size: 3
.n10000010:
	ld a,$40
	ret
.n10000011:
	ld a,$69
	ret
.n100001:
	call get_next_bit
	jr c,.n1000011 ; Jump size: 3
.n1000010:
	ld a,$54
	ret
.n1000011:
	call get_next_bit
	jr c,.n10000111 ; Jump size: 35
.n10000110:
	call get_next_bit
	jr c,.n100001101 ; Jump size: 3
.n100001100:
	ld a,$a6
	ret
.n100001101:
	call get_next_bit
	jr c,.n1000011011 ; Jump size: 3
.n1000011010:
	ld a,$f5
	ret
.n1000011011:
	call get_next_bit
	jr c,.n10000110111 ; Jump size: 3
.n10000110110:
	ld a,$e1
	ret
.n10000110111:
	call get_next_bit
	jr c,.n100001101111 ; Jump size: 3
.n100001101110:
	ld a,$fd
	ret
.n100001101111:
	ld a,$88
	ret
.n10000111:
	ld a,$ea
	ret
.n10001:
	call get_next_bit
	jr c,.n100011 ; Jump size: 3
.n100010:
	ld a,$06
	ret
.n100011:
	ld a,$bf
	ret
.n1001:
	call get_next_bit
	jr c,.n10011 ; Jump size: 75
.n10010:
	call get_next_bit
	jr c,.n100101 ; Jump size: 67
.n100100:
	call get_next_bit
	jr c,.n1001001 ; Jump size: 3
.n1001000:
	ld a,$fa
	ret
.n1001001:
	call get_next_bit
	jr c,.n10010011 ; Jump size: 11
.n10010010:
	call get_next_bit
	jr c,.n100100101 ; Jump size: 3
.n100100100:
	ld a,$a2
	ret
.n100100101:
	ld a,$27
	ret
.n10010011:
	call get_next_bit
	jr c,.n100100111 ; Jump size: 35
.n100100110:
	call get_next_bit
	jr c,.n1001001101 ; Jump size: 27
.n1001001100:
	call get_next_bit
	jr c,.n10010011001 ; Jump size: 11
.n10010011000:
	call get_next_bit
	jr c,.n100100110001 ; Jump size: 3
.n100100110000:
	ld a,$89
	ret
.n100100110001:
	ld a,$6b
	ret
.n10010011001:
	call get_next_bit
	jr c,.n100100110011 ; Jump size: 3
.n100100110010:
	ld a,$b8
	ret
.n100100110011:
	ld a,$e2
	ret
.n1001001101:
	ld a,$17
	ret
.n100100111:
	ld a,$3f
	ret
.n100101:
	ld a,$05
	ret
.n10011:
	ld a,$08
	ret
.n101:
	xor a
	ret
.n11:
	call get_next_bit
	jp c,.n111 ; Jump size: 244
.n110:
	call get_next_bit
	jp c,.n1101 ; Jump size: 211
.n1100:
	call get_next_bit
	jr c,.n11001 ; Jump size: 107
.n11000:
	call get_next_bit
	jr c,.n110001 ; Jump size: 99
.n110000:
	call get_next_bit
	jr c,.n1100001 ; Jump size: 67
.n1100000:
	call get_next_bit
	jr c,.n11000001 ; Jump size: 11
.n11000000:
	call get_next_bit
	jr c,.n110000001 ; Jump size: 3
.n110000000:
	ld a,$fc
	ret
.n110000001:
	ld a,$fb
	ret
.n11000001:
	call get_next_bit
	jr c,.n110000011 ; Jump size: 11
.n110000010:
	call get_next_bit
	jr c,.n1100000101 ; Jump size: 3
.n1100000100:
	ld a,$29
	ret
.n1100000101:
	ld a,$e5
	ret
.n110000011:
	call get_next_bit
	jr c,.n1100000111 ; Jump size: 3
.n1100000110:
	ld a,$f9
	ret
.n1100000111:
	call get_next_bit
	jr c,.n11000001111 ; Jump size: 19
.n11000001110:
	call get_next_bit
	jr c,.n110000011101 ; Jump size: 3
.n110000011100:
	ld a,$92
	ret
.n110000011101:
	call get_next_bit
	jr c,.n1100000111011 ; Jump size: 3
.n1100000111010:
	ld a,$94
	ret
.n1100000111011:
	ld a,$1f
	ret
.n11000001111:
	ld a,$66
	ret
.n1100001:
	call get_next_bit
	jr c,.n11000011 ; Jump size: 11
.n11000010:
	call get_next_bit
	jr c,.n110000101 ; Jump size: 3
.n110000100:
	ld a,$a8
	ret
.n110000101:
	ld a,$65
	ret
.n11000011:
	call get_next_bit
	jr c,.n110000111 ; Jump size: 3
.n110000110:
	ld a,$60
	ret
.n110000111:
	ld a,$35
	ret
.n110001:
	ld a,$20
	ret
.n11001:
	call get_next_bit
	jr c,.n110011 ; Jump size: 27
.n110010:
	call get_next_bit
	jr c,.n1100101 ; Jump size: 3
.n1100100:
	ld a,$09
	ret
.n1100101:
	call get_next_bit
	jr c,.n11001011 ; Jump size: 3
.n11001010:
	ld a,$f8
	ret
.n11001011:
	call get_next_bit
	jr c,.n110010111 ; Jump size: 3
.n110010110:
	ld a,$96
	ret
.n110010111:
	ld a,$2b
	ret
.n110011:
	call get_next_bit
	jr c,.n1100111 ; Jump size: 3
.n1100110:
	ld a,$95
	ret
.n1100111:
	call get_next_bit
	jr c,.n11001111 ; Jump size: 27
.n11001110:
	call get_next_bit
	jr c,.n110011101 ; Jump size: 11
.n110011100:
	call get_next_bit
	jr c,.n1100111001 ; Jump size: 3
.n1100111000:
	ld a,$f0
	ret
.n1100111001:
	ld a,$68
	ret
.n110011101:
	call get_next_bit
	jr c,.n1100111011 ; Jump size: 3
.n1100111010:
	ld a,$13
	ret
.n1100111011:
	ld a,$6f
	ret
.n11001111:
	call get_next_bit
	jr c,.n110011111 ; Jump size: 19
.n110011110:
	call get_next_bit
	jr c,.n1100111101 ; Jump size: 3
.n1100111100:
	ld a,$11
	ret
.n1100111101:
	call get_next_bit
	jr c,.n11001111011 ; Jump size: 3
.n11001111010:
	ld a,$62
	ret
.n11001111011:
	ld a,$12
	ret
.n110011111:
	ld a,$59
	ret
.n1101:
	call get_next_bit
	jr c,.n11011 ; Jump size: 19
.n11010:
	call get_next_bit
	jr c,.n110101 ; Jump size: 3
.n110100:
	ld a,$02
	ret
.n110101:
	call get_next_bit
	jr c,.n1101011 ; Jump size: 3
.n1101010:
	ld a,$07
	ret
.n1101011:
	ld a,$2c
	ret
.n11011:
	ld a,$03
	ret
.n111:
	call get_next_bit
	jr c,.n1111 ; Jump size: 75
.n1110:
	call get_next_bit
	jr c,.n11101 ; Jump size: 27
.n11100:
	call get_next_bit
	jr c,.n111001 ; Jump size: 3
.n111000:
	ld a,$80
	ret
.n111001:
	call get_next_bit
	jr c,.n1110011 ; Jump size: 11
.n1110010:
	call get_next_bit
	jr c,.n11100101 ; Jump size: 3
.n11100100:
	ld a,$e0
	ret
.n11100101:
	ld a,$32
	ret
.n1110011:
	ld a,$14
	ret
.n11101:
	call get_next_bit
	jr c,.n111011 ; Jump size: 27
.n111010:
	call get_next_bit
	jr c,.n1110101 ; Jump size: 3
.n1110100:
	ld a,$a5
	ret
.n1110101:
	call get_next_bit
	jr c,.n11101011 ; Jump size: 11
.n11101010:
	call get_next_bit
	jr c,.n111010101 ; Jump size: 3
.n111010100:
	ld a,$82
	ret
.n111010101:
	ld a,$ab
	ret
.n11101011:
	ld a,$5a
	ret
.n111011:
	call get_next_bit
	jr c,.n1110111 ; Jump size: 3
.n1110110:
	ld a,$fe
	ret
.n1110111:
	ld a,$15
	ret
.n1111:
	call get_next_bit
	jp c,.n11111 ; Jump size: 147
.n11110:
	call get_next_bit
	jr c,.n111101 ; Jump size: 51
.n111100:
	call get_next_bit
	jr c,.n1111001 ; Jump size: 43
.n1111000:
	call get_next_bit
	jr c,.n11110001 ; Jump size: 3
.n11110000:
	ld a,$50
	ret
.n11110001:
	call get_next_bit
	jr c,.n111100011 ; Jump size: 11
.n111100010:
	call get_next_bit
	jr c,.n1111000101 ; Jump size: 3
.n1111000100:
	ld a,$5b
	ret
.n1111000101:
	ld a,$c0
	ret
.n111100011:
	call get_next_bit
	jr c,.n1111000111 ; Jump size: 3
.n1111000110:
	ld a,$eb
	ret
.n1111000111:
	call get_next_bit
	jr c,.n11110001111 ; Jump size: 3
.n11110001110:
	ld a,$57
	ret
.n11110001111:
	ld a,$d5
	ret
.n1111001:
	ld a,$18
	ret
.n111101:
	call get_next_bit
	jr c,.n1111011 ; Jump size: 83
.n1111010:
	call get_next_bit
	jr c,.n11110101 ; Jump size: 3
.n11110100:
	ld a,$3b
	ret
.n11110101:
	call get_next_bit
	jr c,.n111101011 ; Jump size: 59
.n111101010:
	call get_next_bit
	jr c,.n1111010101 ; Jump size: 19
.n1111010100:
	call get_next_bit
	jr c,.n11110101001 ; Jump size: 3
.n11110101000:
	ld a,$99
	ret
.n11110101001:
	call get_next_bit
	jr c,.n111101010011 ; Jump size: 3
.n111101010010:
	ld a,$9a
	ret
.n111101010011:
	ld a,$98
	ret
.n1111010101:
	call get_next_bit
	jr c,.n11110101011 ; Jump size: 11
.n11110101010:
	call get_next_bit
	jr c,.n111101010101 ; Jump size: 3
.n111101010100:
	ld a,$e9
	ret
.n111101010101:
	ld a,$8b
	ret
.n11110101011:
	call get_next_bit
	jr c,.n111101010111 ; Jump size: 3
.n111101010110:
	ld a,$4b
	ret
.n111101010111:
	call get_next_bit
	jr c,.n1111010101111 ; Jump size: 3
.n1111010101110:
	ld a,$6e
	ret
.n1111010101111:
	ld a,$7f
	ret
.n111101011:
	call get_next_bit
	jr c,.n1111010111 ; Jump size: 3
.n1111010110:
	ld a,$8a
	ret
.n1111010111:
	ld a,$58
	ret
.n1111011:
	ld a,$a0
	ret
.n11111:
	call get_next_bit
	jr c,.n111111 ; Jump size: 3
.n111110:
	ld a,$0c
	ret
.n111111:
	call get_next_bit
	jr c,.n1111111 ; Jump size: 11
.n1111110:
	call get_next_bit
	jr c,.n11111101 ; Jump size: 3
.n11111100:
	ld a,$10
	ret
.n11111101:
	ld a,$1a
	ret
.n1111111:
	call get_next_bit
	jr c,.n11111111 ; Jump size: 3
.n11111110:
	ld a,$19
	ret
.n11111111:
	ld a,$25
	ret

;END_UNCOMPRESS_GENERATION
