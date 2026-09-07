    .section .text
    .globl _start

# ------------------------------------------------------------
# Shape IDs
#   0 = circle outline
#   1 = square outline
#   2 = line
#
# Memory map
#   Q1 base =   12
#   Q2 base =  464
#   Q3 base =  916
#   Q4 base = 1368
#
# Each shape:
#   60 x 60 = 3600 bits = 113 words
# ------------------------------------------------------------

_start:

    # ------------------------------------------------------------
    # Hardcoded 60x60 outline bitmaps written directly to dcache
    # Q1 circle @ 12, Q2 square @ 464, Q3 line @ 916, Q4 circle @ 1368
    # ------------------------------------------------------------
    # Q1 circle outline base = 12

    # ================== FOR DEBUGGING
    # addi x31, x0, 0 # signal done with pixel load, starting inference

    jal x0, load_pixels

    start_inference:
    # set base address for tensor controller
    lui x30, 0xE
    addi x30, x30, 1424 # make x30 base address for tensor controller (58780)

    # load shift value to tensor_controller
    addi x1, x0, 6
    sw x1, 12(x30) # store 6 to shift register
    sw x0, 4(x30) # init tensor

    addi x16, x0, 16 
    addi x9, x0, 0 # counter for sending pixels 16 times

    inference_loop:
    addi x9, x9, 1
    # setup 4 dcache memory pointers to start at quadrant base addr
    addi x15, x0, 113
    slli x15, x15, 2 # dcache addr gap between quadrants (3600 / 32 = 112.5 round up to 113 and each address is 4 apart)
    # x11 is q1, x12 is q2, x13 is q3, x14 is q4
    addi x11, x0, 12
    add x12, x11, x15
    add x13, x12, x15
    add x14, x13, x15

    # init tensor
    addi x10, x0, 0 
    addi x4, x0, 1
    addi x5, x0, 2
    addi x6, x0, 3
    addi x17, x0, 255
    slli x18, x17, 8
    slli x19, x17, 16
    slli x20, x17, 24

    # x30, x11-14, x15/x10 for tracking RESERVED, x1(sent to tc)
    # x17-20 are masks for which byte were on
    # x3 is status (1 means byte 1 loaded to x1, 2 means byte 2 loaded to x1, etc)
    # get 32b bus for each quadrant from dcache, load into x21-24, mask into x25-28
    get_tc_pixel:
    add x25, x10, x11
    add x26, x10, x12
    add x27, x10, x13
    add x28, x10, x14

    lw x21, 0(x25)
    lw x22, 0(x26)
    lw x23, 0(x27)
    lw x24, 0(x28)

    addi x10, x10, 4 # point to next pixel bus

    # prepare first bus using byte 1 mask
    and x25, x21, x17
    and x26, x22, x17
    and x27, x23, x17
    and x28, x24, x17 # x24 has 0x000...558 DEBUG

    # shift into correct position
    slli x26, x26, 8
    slli x27, x27, 16
    slli x28, x28, 24

    addi x1, x0, 0 # reset x1
    or x1, x1, x25
    or x1, x1, x26
    or x1, x1, x27
    or x1, x1, x28 # x28 has 58... DEBUG

    addi x3, x4, 0 # update status

    jal x0, send_tensor_pixel

    fill_second: # also check if x10 = x15 for full done 
    # mask
    and x25, x21, x18
    and x26, x22, x18
    and x27, x23, x18
    and x28, x24, x18

    # shift
    srli x25, x25, 8
    slli x27, x27, 8
    slli x28, x28, 16

    addi x1, x0, 0
    or x1, x1, x25
    or x1, x1, x26
    or x1, x1, x27
    or x1, x1, x28

    beq x10, x15, send_tensor_last
    addi x3, x5, 0
    jal x0, send_tensor_pixel

    fill_third:
    # mask
    and x25, x21, x19
    and x26, x22, x19
    and x27, x23, x19
    and x28, x24, x19

    # shift
    srli x25, x25, 16
    srli x26, x26, 8
    slli x28, x28, 8

    addi x1, x0, 0
    or x1, x1, x25
    or x1, x1, x26
    or x1, x1, x27
    or x1, x1, x28

    addi x3, x6, 0
    jal x0, send_tensor_pixel

    fill_fourth:
    # mask
    and x25, x21, x20
    and x26, x22, x20
    and x27, x23, x20
    and x28, x24, x20

    # shift
    srli x25, x25, 24
    srli x26, x26, 16
    srli x27, x27, 8

    addi x1, x0, 0
    or x1, x1, x25
    or x1, x1, x26
    or x1, x1, x27
    or x1, x1, x28

    addi x3, x0, 4
    jal x0, send_tensor_pixel

    send_tensor_pixel: # x1 is ready to be sent
    lw x2, 8(x30)
    beq x0, x2, send_tensor_pixel

    sw x1, 8(x30) # ===============================================
    beq x4, x3, fill_second
    beq x5, x3, fill_third
    beq x6, x3, fill_fourth
    jal x0, get_tc_pixel

    send_tensor_last:
    lw x2, 8(x30)
    beq x0, x2, send_tensor_last
    sw x1, 8(x30)
    bne x9, x16, inference_loop
    jal x0, get_tensor_shape


    # only x30 matters
    get_tensor_shape:
    lui x20, 0x80000 # only bit 31 high

    get_tensor_shape_loop:
    lw x1, 4(x30)
    and x2, x1, x20
    beq x2, x0, get_tensor_shape_loop

    # shape valid, need to ack to tensor
    sw x0, 4(x30)

    # prep x3 with shape data
    addi x3, x0, 15
    slli x3, x3, 12

    addi x4, x0, 2047
    slli x4, x4, 1
    addi x4, x4, 1 # x4 is lsb 12b mask

    and x1, x1, x4
    or x3, x3, x1

    # x3 has shape data, write to x31 for tb
    addi x31, x3, 0

done:
    jal  x0, done

load_pixels: 
    # Q1 circle-ish ring base = 12
    addi x29, x0, 12
    sw   x0, 0(x29)
    sw   x0, 4(x29)
    sw   x0, 8(x29)
    sw   x0, 12(x29)
    sw   x0, 16(x29)
    sw   x0, 20(x29)
    sw   x0, 24(x29)
    sw   x0, 28(x29)
    sw   x0, 32(x29)
    sw   x0, 36(x29)
    sw   x0, 40(x29)
    sw   x0, 44(x29)
    sw   x0, 48(x29)
    sw   x0, 52(x29)
    sw   x0, 56(x29)
    sw   x0, 60(x29)
    sw   x0, 64(x29)
    sw   x0, 68(x29)
    sw   x0, 72(x29)
    li   x1, 0x00400000
    sw   x1, 76(x29)
    sw   x0, 80(x29)
    li   x1, 0x01FFF000
    sw   x1, 84(x29)
    sw   x0, 88(x29)
    li   x1, 0x007FFFC0
    sw   x1, 92(x29)
    sw   x0, 96(x29)
    li   x1, 0x001FFFFF
    sw   x1, 100(x29)
    li   x1, 0xFC000000
    sw   x1, 104(x29)
    li   x1, 0x0007FFFF
    sw   x1, 108(x29)
    li   x1, 0x1FE00000
    sw   x1, 112(x29)
    li   x1, 0x0000FF00
    sw   x1, 116(x29)
    li   x1, 0x007F0000
    sw   x1, 120(x29)
    li   x1, 0x00001FC0
    sw   x1, 124(x29)
    li   x1, 0x0001F800
    sw   x1, 128(x29)
    li   x1, 0x000003F0
    sw   x1, 132(x29)
    li   x1, 0x00000FC0
    sw   x1, 136(x29)
    li   x1, 0x0000007E
    sw   x1, 140(x29)
    li   x1, 0xC000007C
    sw   x1, 144(x29)
    li   x1, 0xE0000007
    sw   x1, 148(x29)
    li   x1, 0xF8000003
    sw   x1, 152(x29)
    li   x1, 0x1E000000
    sw   x1, 156(x29)
    li   x1, 0x0F000000
    sw   x1, 160(x29)
    li   x1, 0x01F00000
    sw   x1, 164(x29)
    li   x1, 0x01F00000
    sw   x1, 168(x29)
    li   x1, 0x000F0000
    sw   x1, 172(x29)
    li   x1, 0x001E0000
    sw   x1, 176(x29)
    li   x1, 0x0000F800
    sw   x1, 180(x29)
    li   x1, 0x0003E000
    sw   x1, 184(x29)
    li   x1, 0x00000780
    sw   x1, 188(x29)
    li   x1, 0x00003C00
    sw   x1, 192(x29)
    li   x1, 0x00000078
    sw   x1, 196(x29)
    li   x1, 0x800003C0
    sw   x1, 200(x29)
    li   x1, 0x00000007
    sw   x1, 204(x29)
    li   x1, 0x7800003C
    sw   x1, 208(x29)
    li   x1, 0xC0000000
    sw   x1, 212(x29)
    li   x1, 0x07800003
    sw   x1, 216(x29)
    li   x1, 0x3C000000
    sw   x1, 220(x29)
    li   x1, 0x007C0000
    sw   x1, 224(x29)
    li   x1, 0x07C00000
    sw   x1, 228(x29)
    li   x1, 0x00078000
    sw   x1, 232(x29)
    li   x1, 0x003C0000
    sw   x1, 236(x29)
    li   x1, 0x00007800
    sw   x1, 240(x29)
    li   x1, 0x0003C000
    sw   x1, 244(x29)
    li   x1, 0x00000780
    sw   x1, 248(x29)
    li   x1, 0x00003C00
    sw   x1, 252(x29)
    li   x1, 0x00000078
    sw   x1, 256(x29)
    li   x1, 0x800003C0
    sw   x1, 260(x29)
    li   x1, 0x00000007
    sw   x1, 264(x29)
    li   x1, 0xF800003C
    sw   x1, 268(x29)
    li   x1, 0xE0000000
    sw   x1, 272(x29)
    li   x1, 0x0F000003
    sw   x1, 276(x29)
    li   x1, 0x1E000000
    sw   x1, 280(x29)
    li   x1, 0x01F00000
    sw   x1, 284(x29)
    li   x1, 0x01F00000
    sw   x1, 288(x29)
    li   x1, 0x001E0000
    sw   x1, 292(x29)
    li   x1, 0x000F0000
    sw   x1, 296(x29)
    li   x1, 0x0003E000
    sw   x1, 300(x29)
    li   x1, 0x0000F800
    sw   x1, 304(x29)
    li   x1, 0x00007C00
    sw   x1, 308(x29)
    li   x1, 0x000007C0
    sw   x1, 312(x29)
    li   x1, 0x00000FC0
    sw   x1, 316(x29)
    li   x1, 0x0000007E
    sw   x1, 320(x29)
    li   x1, 0xF00001F8
    sw   x1, 324(x29)
    li   x1, 0x00000003
    sw   x1, 328(x29)
    li   x1, 0x1FC0007F
    sw   x1, 332(x29)
    li   x1, 0xE0000000
    sw   x1, 336(x29)
    li   x1, 0x00FF001F
    sw   x1, 340(x29)
    li   x1, 0xFC000000
    sw   x1, 344(x29)
    li   x1, 0x0007FFFF
    sw   x1, 348(x29)
    li   x1, 0xFF000000
    sw   x1, 352(x29)
    li   x1, 0x00001FFF
    sw   x1, 356(x29)
    li   x1, 0xFFC00000
    sw   x1, 360(x29)
    li   x1, 0x0000007F
    sw   x1, 364(x29)
    li   x1, 0xFFF00000
    sw   x1, 368(x29)
    li   x1, 0x00000001
    sw   x1, 372(x29)
    li   x1, 0x00400000
    sw   x1, 376(x29)
    sw   x0, 380(x29)
    sw   x0, 384(x29)
    sw   x0, 388(x29)
    sw   x0, 392(x29)
    sw   x0, 396(x29)
    sw   x0, 400(x29)
    sw   x0, 404(x29)
    sw   x0, 408(x29)
    sw   x0, 412(x29)
    sw   x0, 416(x29)
    sw   x0, 420(x29)
    sw   x0, 424(x29)
    sw   x0, 428(x29)
    sw   x0, 432(x29)
    sw   x0, 436(x29)
    sw   x0, 440(x29)
    sw   x0, 444(x29)
    sw   x0, 448(x29)

    # Q2 thick square base = 464
    addi x29, x0, 464
    sw   x0, 0(x29)
    sw   x0, 4(x29)
    sw   x0, 8(x29)
    sw   x0, 12(x29)
    sw   x0, 16(x29)
    sw   x0, 20(x29)
    sw   x0, 24(x29)
    sw   x0, 28(x29)
    sw   x0, 32(x29)
    sw   x0, 36(x29)
    sw   x0, 40(x29)
    sw   x0, 44(x29)
    sw   x0, 48(x29)
    sw   x0, 52(x29)
    sw   x0, 56(x29)
    sw   x0, 60(x29)
    sw   x0, 64(x29)
    sw   x0, 68(x29)
    sw   x0, 72(x29)
    sw   x0, 76(x29)
    sw   x0, 80(x29)
    sw   x0, 84(x29)
    sw   x0, 88(x29)
    sw   x0, 92(x29)
    li   x1, 0xF8000000
    sw   x1, 96(x29)
    li   x1, 0x03FFFFFF
    sw   x1, 100(x29)
    li   x1, 0xFF800000
    sw   x1, 104(x29)
    li   x1, 0x003FFFFF
    sw   x1, 108(x29)
    li   x1, 0xFFFE0000
    sw   x1, 112(x29)
    li   x1, 0x000FFFFF
    sw   x1, 116(x29)
    li   x1, 0xFFFFE000
    sw   x1, 120(x29)
    li   x1, 0x0000FFFF
    sw   x1, 124(x29)
    li   x1, 0xFFFFFE00
    sw   x1, 128(x29)
    li   x1, 0x00000FFF
    sw   x1, 132(x29)
    li   x1, 0x000003E0
    sw   x1, 136(x29)
    li   x1, 0x000000F8
    sw   x1, 140(x29)
    li   x1, 0x8000003E
    sw   x1, 144(x29)
    li   x1, 0xE000000F
    sw   x1, 148(x29)
    li   x1, 0xF8000003
    sw   x1, 152(x29)
    li   x1, 0x3E000000
    sw   x1, 156(x29)
    li   x1, 0x0F800000
    sw   x1, 160(x29)
    li   x1, 0x03E00000
    sw   x1, 164(x29)
    li   x1, 0x00F80000
    sw   x1, 168(x29)
    li   x1, 0x003E0000
    sw   x1, 172(x29)
    li   x1, 0x000F8000
    sw   x1, 176(x29)
    li   x1, 0x2003E000
    sw   x1, 180(x29)
    li   x1, 0x0000F800
    sw   x1, 184(x29)
    li   x1, 0x00003E00
    sw   x1, 188(x29)
    li   x1, 0x00000F80
    sw   x1, 192(x29)
    li   x1, 0x000003E0
    sw   x1, 196(x29)
    li   x1, 0x000000F8
    sw   x1, 200(x29)
    li   x1, 0x8000003E
    sw   x1, 204(x29)
    li   x1, 0xE000000F
    sw   x1, 208(x29)
    li   x1, 0xF8000043
    sw   x1, 212(x29)
    li   x1, 0x3E000000
    sw   x1, 216(x29)
    li   x1, 0x0F800000
    sw   x1, 220(x29)
    li   x1, 0x03E00000
    sw   x1, 224(x29)
    li   x1, 0x00F80400
    sw   x1, 228(x29)
    li   x1, 0x003E0000
    sw   x1, 232(x29)
    li   x1, 0x000F8000
    sw   x1, 236(x29)
    li   x1, 0x0003E000
    sw   x1, 240(x29)
    li   x1, 0x0000F800
    sw   x1, 244(x29)
    li   x1, 0x00003E00
    sw   x1, 248(x29)
    li   x1, 0x00000F80
    sw   x1, 252(x29)
    li   x1, 0x000003E0
    sw   x1, 256(x29)
    li   x1, 0x000000F8
    sw   x1, 260(x29)
    li   x1, 0x8000403E
    sw   x1, 264(x29)
    li   x1, 0xE000000F
    sw   x1, 268(x29)
    li   x1, 0xF8000003
    sw   x1, 272(x29)
    li   x1, 0x3E000000
    sw   x1, 276(x29)
    li   x1, 0x0F800000
    sw   x1, 280(x29)
    li   x1, 0x03E00000
    sw   x1, 284(x29)
    li   x1, 0x00F80000
    sw   x1, 288(x29)
    li   x1, 0x003E0000
    sw   x1, 292(x29)
    li   x1, 0x000F8000
    sw   x1, 296(x29)
    li   x1, 0x0003E000
    sw   x1, 300(x29)
    li   x1, 0x0000F800
    sw   x1, 304(x29)
    li   x1, 0x00003E00
    sw   x1, 308(x29)
    li   x1, 0x00000F80
    sw   x1, 312(x29)
    li   x1, 0x000003E0
    sw   x1, 316(x29)
    li   x1, 0x000000F8
    sw   x1, 320(x29)
    li   x1, 0xFFFFFFFE
    sw   x1, 324(x29)
    li   x1, 0xE000000F
    sw   x1, 328(x29)
    li   x1, 0xFFFFFFFF
    sw   x1, 332(x29)
    li   x1, 0xFE000000
    sw   x1, 336(x29)
    li   x1, 0x0FFFFFFF
    sw   x1, 340(x29)
    li   x1, 0xFF800000
    sw   x1, 344(x29)
    li   x1, 0x003FFFFF
    sw   x1, 348(x29)
    li   x1, 0xFFF80000
    sw   x1, 352(x29)
    li   x1, 0x0003FFFF
    sw   x1, 356(x29)
    sw   x0, 360(x29)
    sw   x0, 364(x29)
    sw   x0, 368(x29)
    sw   x0, 372(x29)
    sw   x0, 376(x29)
    sw   x0, 380(x29)
    sw   x0, 384(x29)
    sw   x0, 388(x29)
    sw   x0, 392(x29)
    sw   x0, 396(x29)
    sw   x0, 400(x29)
    sw   x0, 404(x29)
    sw   x0, 408(x29)
    sw   x0, 412(x29)
    sw   x0, 416(x29)
    sw   x0, 420(x29)
    sw   x0, 424(x29)
    sw   x0, 428(x29)
    sw   x0, 432(x29)
    sw   x0, 436(x29)
    sw   x0, 440(x29)
    sw   x0, 444(x29)
    sw   x0, 448(x29)

    # Q3 45deg line base = 916
    addi x29, x0, 916
    sw   x0, 0(x29)
    sw   x0, 4(x29)
    sw   x0, 8(x29)
    sw   x0, 12(x29)
    sw   x0, 16(x29)
    sw   x0, 20(x29)
    sw   x0, 24(x29)
    sw   x0, 28(x29)
    sw   x0, 32(x29)
    sw   x0, 36(x29)
    sw   x0, 40(x29)
    sw   x0, 44(x29)
    sw   x0, 48(x29)
    sw   x0, 52(x29)
    sw   x0, 56(x29)
    sw   x0, 60(x29)
    sw   x0, 64(x29)
    sw   x0, 68(x29)
    sw   x0, 72(x29)
    sw   x0, 76(x29)
    sw   x0, 80(x29)
    sw   x0, 84(x29)
    li   x1, 0xF0000000
    sw   x1, 88(x29)
    li   x1, 0x00000001
    sw   x1, 92(x29)
    li   x1, 0x3F000000
    sw   x1, 96(x29)
    sw   x0, 100(x29)
    li   x1, 0x07F00000
    sw   x1, 104(x29)
    sw   x0, 108(x29)
    li   x1, 0x00FF0000
    sw   x1, 112(x29)
    sw   x0, 116(x29)
    li   x1, 0x001FF000
    sw   x1, 120(x29)
    sw   x0, 124(x29)
    li   x1, 0x0003FE00
    sw   x1, 128(x29)
    sw   x0, 132(x29)
    li   x1, 0x00007FC0
    sw   x1, 136(x29)
    sw   x0, 140(x29)
    li   x1, 0x00000FF8
    sw   x1, 144(x29)
    sw   x0, 148(x29)
    li   x1, 0x000001FF
    sw   x1, 152(x29)
    li   x1, 0xE0000000
    sw   x1, 156(x29)
    li   x1, 0x0000003F
    sw   x1, 160(x29)
    li   x1, 0xFC000000
    sw   x1, 164(x29)
    li   x1, 0x00000007
    sw   x1, 168(x29)
    li   x1, 0xFF800000
    sw   x1, 172(x29)
    sw   x0, 176(x29)
    li   x1, 0x1FF00000
    sw   x1, 180(x29)
    sw   x0, 184(x29)
    li   x1, 0x03FE0000
    sw   x1, 188(x29)
    sw   x0, 192(x29)
    li   x1, 0x007FC000
    sw   x1, 196(x29)
    sw   x0, 200(x29)
    li   x1, 0x000FF800
    sw   x1, 204(x29)
    sw   x0, 208(x29)
    li   x1, 0x0001FF00
    sw   x1, 212(x29)
    sw   x0, 216(x29)
    li   x1, 0x00003FE0
    sw   x1, 220(x29)
    sw   x0, 224(x29)
    li   x1, 0x000007FC
    sw   x1, 228(x29)
    li   x1, 0x80000000
    sw   x1, 232(x29)
    li   x1, 0x000000FF
    sw   x1, 236(x29)
    li   x1, 0xF0000000
    sw   x1, 240(x29)
    li   x1, 0x0000001F
    sw   x1, 244(x29)
    li   x1, 0xFE000000
    sw   x1, 248(x29)
    li   x1, 0x00000003
    sw   x1, 252(x29)
    li   x1, 0x7FC00000
    sw   x1, 256(x29)
    sw   x0, 260(x29)
    li   x1, 0x0FF80000
    sw   x1, 264(x29)
    sw   x0, 268(x29)
    li   x1, 0x01FF0000
    sw   x1, 272(x29)
    sw   x0, 276(x29)
    li   x1, 0x003FE000
    sw   x1, 280(x29)
    sw   x0, 284(x29)
    li   x1, 0x0007FC00
    sw   x1, 288(x29)
    sw   x0, 292(x29)
    li   x1, 0x0000FF80
    sw   x1, 296(x29)
    sw   x0, 300(x29)
    li   x1, 0x00001FF0
    sw   x1, 304(x29)
    sw   x0, 308(x29)
    li   x1, 0x000003FE
    sw   x1, 312(x29)
    li   x1, 0xC0000000
    sw   x1, 316(x29)
    li   x1, 0x0000007F
    sw   x1, 320(x29)
    li   x1, 0xF8000000
    sw   x1, 324(x29)
    li   x1, 0x0000000F
    sw   x1, 328(x29)
    li   x1, 0xFF000000
    sw   x1, 332(x29)
    li   x1, 0x00000001
    sw   x1, 336(x29)
    li   x1, 0x1FE00000
    sw   x1, 340(x29)
    sw   x0, 344(x29)
    li   x1, 0x01FC0000
    sw   x1, 348(x29)
    sw   x0, 352(x29)
    li   x1, 0x001F8000
    sw   x1, 356(x29)
    sw   x0, 360(x29)
    li   x1, 0x0001F000
    sw   x1, 364(x29)
    sw   x0, 368(x29)
    sw   x0, 372(x29)
    sw   x0, 376(x29)
    sw   x0, 380(x29)
    sw   x0, 384(x29)
    sw   x0, 388(x29)
    sw   x0, 392(x29)
    sw   x0, 396(x29)
    sw   x0, 400(x29)
    sw   x0, 404(x29)
    sw   x0, 408(x29)
    sw   x0, 412(x29)
    sw   x0, 416(x29)
    sw   x0, 420(x29)
    sw   x0, 424(x29)
    sw   x0, 428(x29)
    sw   x0, 432(x29)
    sw   x0, 436(x29)
    sw   x0, 440(x29)
    sw   x0, 444(x29)
    sw   x0, 448(x29)

    # Q4 = exact copy of Q1 (113 words) instead of shifted ring
    addi x29, x0, 12        # src = Q1 base
    addi x28, x0, 1368      # dst = Q4 base
    addi x27, x0, 113       # word count

copy_q1_to_q4:
    lw   x26, 0(x29)
    sw   x26, 0(x28)
    addi x29, x29, 4
    addi x28, x28, 4
    addi x27, x27, -1
    bne  x27, x0, copy_q1_to_q4

    jal x0, start_inference