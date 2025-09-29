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
	jp c,.n01 ; Jump size: 366
.n00:
	call get_next_bit
	jp c,.n001 ; Jump size: 269
.n000:
	call get_next_bit
	jr c,.n0001 ; Jump size: 91
.n0000:
	call get_next_bit
	jr c,.n00001 ; Jump size: 51
.n00000:
	call get_next_bit
	jr c,.n000001 ; Jump size: 3
.n000000:
	ld a,$fe
	ret
.n000001:
	call get_next_bit
	jr c,.n0000011 ; Jump size: 3
.n0000010:
	ld a,$0b
	ret
.n0000011:
	call get_next_bit
	jr c,.n00000111 ; Jump size: 27
.n00000110:
	call get_next_bit
	jr c,.n000001101 ; Jump size: 11
.n000001100:
	call get_next_bit
	jr c,.n0000011001 ; Jump size: 3
.n0000011000:
	ld a,$16
	ret
.n0000011001:
	ld a,$9a
	ret
.n000001101:
	call get_next_bit
	jr c,.n0000011011 ; Jump size: 3
.n0000011010:
	ld a,$22
	ret
.n0000011011:
	ld a,$ef
	ret
.n00000111:
	ld a,$ba
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
	ld a,$59
	ret
.n00001011:
	ld a,$e8
	ret
.n000011:
	ld a,$40
	ret
.n0001:
	call get_next_bit
	jp c,.n00011 ; Jump size: 164
.n00010:
	call get_next_bit
	jp c,.n000101 ; Jump size: 155
.n000100:
	call get_next_bit
	jr c,.n0001001 ; Jump size: 75
.n0001000:
	call get_next_bit
	jr c,.n00010001 ; Jump size: 3
.n00010000:
	ld a,$2f
	ret
.n00010001:
	call get_next_bit
	jr c,.n000100011 ; Jump size: 27
.n000100010:
	call get_next_bit
	jr c,.n0001000101 ; Jump size: 19
.n0001000100:
	call get_next_bit
	jr c,.n00010001001 ; Jump size: 11
.n00010001000:
	call get_next_bit
	jr c,.n000100010001 ; Jump size: 3
.n000100010000:
	ld a,$39
	ret
.n000100010001:
	ld a,$88
	ret
.n00010001001:
	ld a,$e1
	ret
.n0001000101:
	ld a,$66
	ret
.n000100011:
	call get_next_bit
	jr c,.n0001000111 ; Jump size: 3
.n0001000110:
	ld a,$f5
	ret
.n0001000111:
	call get_next_bit
	jr c,.n00010001111 ; Jump size: 11
.n00010001110:
	call get_next_bit
	jr c,.n000100011101 ; Jump size: 3
.n000100011100:
	ld a,$89
	ret
.n000100011101:
	ld a,$6b
	ret
.n00010001111:
	call get_next_bit
	jr c,.n000100011111 ; Jump size: 3
.n000100011110:
	ld a,$b8
	ret
.n000100011111:
	ld a,$e2
	ret
.n0001001:
	call get_next_bit
	jr c,.n00010011 ; Jump size: 11
.n00010010:
	call get_next_bit
	jr c,.n000100101 ; Jump size: 3
.n000100100:
	ld a,$5f
	ret
.n000100101:
	ld a,$a2
	ret
.n00010011:
	call get_next_bit
	jr c,.n000100111 ; Jump size: 3
.n000100110:
	ld a,$27
	ret
.n000100111:
	call get_next_bit
	jr c,.n0001001111 ; Jump size: 43
.n0001001110:
	call get_next_bit
	jr c,.n00010011101 ; Jump size: 11
.n00010011100:
	call get_next_bit
	jr c,.n000100111001 ; Jump size: 3
.n000100111000:
	ld a,$92
	ret
.n000100111001:
	ld a,$1d
	ret
.n00010011101:
	call get_next_bit
	jr c,.n000100111011 ; Jump size: 11
.n000100111010:
	call get_next_bit
	jr c,.n0001001110101 ; Jump size: 3
.n0001001110100:
	ld a,$94
	ret
.n0001001110101:
	ld a,$1f
	ret
.n000100111011:
	call get_next_bit
	jr c,.n0001001110111 ; Jump size: 3
.n0001001110110:
	ld a,$6e
	ret
.n0001001110111:
	ld a,$44
	ret
.n0001001111:
	ld a,$17
	ret
.n000101:
	ld a,$14
	ret
.n00011:
	ld a,$05
	ret
.n001:
	call get_next_bit
	jr c,.n0011 ; Jump size: 3
.n0010:
	ld a,$55
	ret
.n0011:
	call get_next_bit
	jr c,.n00111 ; Jump size: 75
.n00110:
	call get_next_bit
	jr c,.n001101 ; Jump size: 3
.n001100:
	ld a,$06
	ret
.n001101:
	call get_next_bit
	jr c,.n0011011 ; Jump size: 35
.n0011010:
	call get_next_bit
	jr c,.n00110101 ; Jump size: 11
.n00110100:
	call get_next_bit
	jr c,.n001101001 ; Jump size: 3
.n001101000:
	ld a,$3f
	ret
.n001101001:
	ld a,$fc
	ret
.n00110101:
	call get_next_bit
	jr c,.n001101011 ; Jump size: 3
.n001101010:
	ld a,$fb
	ret
.n001101011:
	call get_next_bit
	jr c,.n0011010111 ; Jump size: 3
.n0011010110:
	ld a,$29
	ret
.n0011010111:
	ld a,$e5
	ret
.n0011011:
	call get_next_bit
	jr c,.n00110111 ; Jump size: 3
.n00110110:
	ld a,$69
	ret
.n00110111:
	call get_next_bit
	jr c,.n001101111 ; Jump size: 11
.n001101110:
	call get_next_bit
	jr c,.n0011011101 ; Jump size: 3
.n0011011100:
	ld a,$f9
	ret
.n0011011101:
	ld a,$d4
	ret
.n001101111:
	ld a,$65
	ret
.n00111:
	ld a,$08
	ret
.n01:
	call get_next_bit
	jr c,.n011 ; Jump size: 3
.n010:
	ld a,$01
	ret
.n011:
	call get_next_bit
	jr c,.n0111 ; Jump size: 51
.n0110:
	call get_next_bit
	jr c,.n01101 ; Jump size: 11
.n01100:
	call get_next_bit
	jr c,.n011001 ; Jump size: 3
.n011000:
	ld a,$15
	ret
.n011001:
	ld a,$bf
	ret
.n01101:
	call get_next_bit
	jr c,.n011011 ; Jump size: 3
.n011010:
	ld a,$20
	ret
.n011011:
	call get_next_bit
	jr c,.n0110111 ; Jump size: 19
.n0110110:
	call get_next_bit
	jr c,.n01101101 ; Jump size: 3
.n01101100:
	ld a,$0d
	ret
.n01101101:
	call get_next_bit
	jr c,.n011011011 ; Jump size: 3
.n011011010:
	ld a,$60
	ret
.n011011011:
	ld a,$35
	ret
.n0110111:
	ld a,$09
	ret
.n0111:
	ld a,$ff
	ret
.n1:
	call get_next_bit
	jp c,.n11 ; Jump size: 204
.n10:
	call get_next_bit
	jp c,.n101 ; Jump size: 196
.n100:
	call get_next_bit
	jp c,.n1001 ; Jump size: 139
.n1000:
	call get_next_bit
	jr c,.n10001 ; Jump size: 91
.n10000:
	call get_next_bit
	jr c,.n100001 ; Jump size: 19
.n100000:
	call get_next_bit
	jr c,.n1000001 ; Jump size: 3
.n1000000:
	ld a,$af
	ret
.n1000001:
	call get_next_bit
	jr c,.n10000011 ; Jump size: 3
.n10000010:
	ld a,$f8
	ret
.n10000011:
	ld a,$ab
	ret
.n100001:
	call get_next_bit
	jr c,.n1000011 ; Jump size: 59
.n1000010:
	call get_next_bit
	jr c,.n10000101 ; Jump size: 19
.n10000100:
	call get_next_bit
	jr c,.n100001001 ; Jump size: 3
.n100001000:
	ld a,$2b
	ret
.n100001001:
	call get_next_bit
	jr c,.n1000010011 ; Jump size: 3
.n1000010010:
	ld a,$f0
	ret
.n1000010011:
	ld a,$68
	ret
.n10000101:
	call get_next_bit
	jr c,.n100001011 ; Jump size: 11
.n100001010:
	call get_next_bit
	jr c,.n1000010101 ; Jump size: 3
.n1000010100:
	ld a,$13
	ret
.n1000010101:
	ld a,$6f
	ret
.n100001011:
	call get_next_bit
	jr c,.n1000010111 ; Jump size: 3
.n1000010110:
	ld a,$11
	ret
.n1000010111:
	call get_next_bit
	jr c,.n10000101111 ; Jump size: 3
.n10000101110:
	ld a,$62
	ret
.n10000101111:
	ld a,$12
	ret
.n1000011:
	ld a,$2c
	ret
.n10001:
	call get_next_bit
	jr c,.n100011 ; Jump size: 35
.n100010:
	call get_next_bit
	jr c,.n1000101 ; Jump size: 11
.n1000100:
	call get_next_bit
	jr c,.n10001001 ; Jump size: 3
.n10001000:
	ld a,$ea
	ret
.n10001001:
	ld a,$e0
	ret
.n1000101:
	call get_next_bit
	jr c,.n10001011 ; Jump size: 3
.n10001010:
	ld a,$32
	ret
.n10001011:
	call get_next_bit
	jr c,.n100010111 ; Jump size: 3
.n100010110:
	ld a,$eb
	ret
.n100010111:
	ld a,$1c
	ret
.n100011:
	ld a,$80
	ret
.n1001:
	call get_next_bit
	jr c,.n10011 ; Jump size: 43
.n10010:
	call get_next_bit
	jr c,.n100101 ; Jump size: 3
.n100100:
	ld a,$50
	ret
.n100101:
	call get_next_bit
	jr c,.n1001011 ; Jump size: 3
.n1001010:
	ld a,$95
	ret
.n1001011:
	call get_next_bit
	jr c,.n10010111 ; Jump size: 3
.n10010110:
	ld a,$a8
	ret
.n10010111:
	call get_next_bit
	jr c,.n100101111 ; Jump size: 3
.n100101110:
	ld a,$82
	ret
.n100101111:
	call get_next_bit
	jr c,.n1001011111 ; Jump size: 3
.n1001011110:
	ld a,$7f
	ret
.n1001011111:
	ld a,$fd
	ret
.n10011:
	ld a,$04
	ret
.n101:
	xor a
	ret
.n11:
	call get_next_bit
	jp c,.n111 ; Jump size: 195
.n110:
	call get_next_bit
	jr c,.n1101 ; Jump size: 91
.n1100:
	call get_next_bit
	jr c,.n11001 ; Jump size: 19
.n11000:
	call get_next_bit
	jr c,.n110001 ; Jump size: 11
.n110000:
	call get_next_bit
	jr c,.n1100001 ; Jump size: 3
.n1100000:
	ld a,$07
	ret
.n1100001:
	ld a,$fa
	ret
.n110001:
	ld a,$02
	ret
.n11001:
	call get_next_bit
	jr c,.n110011 ; Jump size: 35
.n110010:
	call get_next_bit
	jr c,.n1100101 ; Jump size: 3
.n1100100:
	ld a,$a5
	ret
.n1100101:
	call get_next_bit
	jr c,.n11001011 ; Jump size: 3
.n11001010:
	ld a,$5a
	ret
.n11001011:
	call get_next_bit
	jr c,.n110010111 ; Jump size: 11
.n110010110:
	call get_next_bit
	jr c,.n1100101101 ; Jump size: 3
.n1100101100:
	ld a,$5b
	ret
.n1100101101:
	ld a,$c0
	ret
.n110010111:
	ld a,$57
	ret
.n110011:
	call get_next_bit
	jr c,.n1100111 ; Jump size: 19
.n1100110:
	call get_next_bit
	jr c,.n11001101 ; Jump size: 11
.n11001100:
	call get_next_bit
	jr c,.n110011001 ; Jump size: 3
.n110011000:
	ld a,$a6
	ret
.n110011001:
	ld a,$d5
	ret
.n11001101:
	ld a,$3b
	ret
.n1100111:
	ld a,$1a
	ret
.n1101:
	call get_next_bit
	jr c,.n11011 ; Jump size: 67
.n11010:
	call get_next_bit
	jr c,.n110101 ; Jump size: 3
.n110100:
	ld a,$54
	ret
.n110101:
	call get_next_bit
	jr c,.n1101011 ; Jump size: 3
.n1101010:
	ld a,$18
	ret
.n1101011:
	call get_next_bit
	jr c,.n11010111 ; Jump size: 43
.n11010110:
	call get_next_bit
	jr c,.n110101101 ; Jump size: 35
.n110101100:
	call get_next_bit
	jr c,.n1101011001 ; Jump size: 3
.n1101011000:
	ld a,$99
	ret
.n1101011001:
	call get_next_bit
	jr c,.n11010110011 ; Jump size: 11
.n11010110010:
	call get_next_bit
	jr c,.n110101100101 ; Jump size: 3
.n110101100100:
	ld a,$98
	ret
.n110101100101:
	ld a,$e9
	ret
.n11010110011:
	call get_next_bit
	jr c,.n110101100111 ; Jump size: 3
.n110101100110:
	ld a,$8b
	ret
.n110101100111:
	ld a,$4b
	ret
.n110101101:
	ld a,$96
	ret
.n11010111:
	ld a,$10
	ret
.n11011:
	call get_next_bit
	jr c,.n110111 ; Jump size: 3
.n110110:
	ld a,$0c
	ret
.n110111:
	call get_next_bit
	jr c,.n1101111 ; Jump size: 3
.n1101110:
	ld a,$a0
	ret
.n1101111:
	call get_next_bit
	jr c,.n11011111 ; Jump size: 3
.n11011110:
	ld a,$25
	ret
.n11011111:
	ld a,$19
	ret
.n111:
	call get_next_bit
	jr c,.n1111 ; Jump size: 67
.n1110:
	call get_next_bit
	jr c,.n11101 ; Jump size: 59
.n11100:
	call get_next_bit
	jr c,.n111001 ; Jump size: 51
.n111000:
	call get_next_bit
	jr c,.n1110001 ; Jump size: 27
.n1110000:
	call get_next_bit
	jr c,.n11100001 ; Jump size: 3
.n11100000:
	ld a,$33
	ret
.n11100001:
	call get_next_bit
	jr c,.n111000011 ; Jump size: 11
.n111000010:
	call get_next_bit
	jr c,.n1110000101 ; Jump size: 3
.n1110000100:
	ld a,$8a
	ret
.n1110000101:
	ld a,$58
	ret
.n111000011:
	ld a,$1b
	ret
.n1110001:
	call get_next_bit
	jr c,.n11100011 ; Jump size: 11
.n11100010:
	call get_next_bit
	jr c,.n111000101 ; Jump size: 3
.n111000100:
	ld a,$be
	ret
.n111000101:
	ld a,$ae
	ret
.n11100011:
	ld a,$0f
	ret
.n111001:
	ld a,$0a
	ret
.n11101:
	ld a,$03
	ret
.n1111:
	call get_next_bit
	jr c,.n11111 ; Jump size: 51
.n11110:
	call get_next_bit
	jr c,.n111101 ; Jump size: 27
.n111100:
	call get_next_bit
	jr c,.n1111001 ; Jump size: 19
.n1111000:
	call get_next_bit
	jr c,.n11110001 ; Jump size: 11
.n11110000:
	call get_next_bit
	jr c,.n111100001 ; Jump size: 3
.n111100000:
	ld a,$2e
	ret
.n111100001:
	ld a,$30
	ret
.n11110001:
	ld a,$24
	ret
.n1111001:
	ld a,$2a
	ret
.n111101:
	call get_next_bit
	jr c,.n1111011 ; Jump size: 3
.n1111010:
	ld a,$28
	ret
.n1111011:
	call get_next_bit
	jr c,.n11110111 ; Jump size: 3
.n11110110:
	ld a,$0e
	ret
.n11110111:
	ld a,$56
	ret
.n11111:
	ld a,$aa
	ret

;END_UNCOMPRESS_GENERATION
