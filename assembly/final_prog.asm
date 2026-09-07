# in the actual hex file, add machine code to load weight/biases to tensor mem
# the asm is in weight_load folder

# the rest of this code assumes weights have already been loaded

# need to store 32bit buses to dcache when DPU sends them 30 at a time (top 2 are status bits)
# 2 registers that hold pixel data: data_store (x1) where i lw into and data_send (x4) which will be sw to mem
# also an intermediary register x5 for bit ops 
# last_valid tracks the last valid bit in data_send, initialized to 0 | 1-32

# when there is a new valid data in x1, shift x1 left by last_valid into x5
# or x5 with data_send

# if last valid is greater or equal to 2, store data_send to memory since it is full
# shift x1 right by (32-last_valid) and store that into data_send (preserve bits that weren't used)
# subtract 2 from last valid

# else don't store data_send to memory
# add 30 to last valid
# don't need to preserve anything in x1 

# NOTE: the status bits don't affect anything since they aren't tracked with last status
# and are overwritten

# check if bit 32 is high, if so all pixel data has been sent and we can mask the first 16 bits of half full data_send 
# (get rid of status bits) and send to mem | this is because 3600 / 32 = 12.5

# init DPU
.section .text
.globl _start

_start:
sw x0, 4(x0)

repeat:
addi x29, x0, 12 # dcache sw address (changes)
addi x28, x0, 0 # tracks last valid bit in data_send (x4)
addi x27, x0, 0 # tracks how many data buses sent per quadrant
addi x26, x0, 120
addi x2, x0, 2
addi x13, x0, 3
addi x12, x0, 32
addi x4, x0, 0
lui  x7, 0x10         # x7 = 0x00010000
addi x7, x7, -1       # x7 = 0x0000FFFF

poll_dpu_pixel:
lw x1, 4(x0) 
srli x3, x1, 30 # x3 has x1's bit 31, 32 in lsbs
slli x1, x1, 2
srli x1, x1, 2
blt x0, x3, valid_dpu_pixel
jal x0, poll_dpu_pixel

# process the pixel data in x1 to make 32b bus to send to dcache
valid_dpu_pixel:
sw x0, 4(x0) # ack dpu
addi x27, x27, 1 # increment data count 
sll x5, x1, x28
or x4, x4, x5

bge x28, x2, send_pixel_bus # if last valid >= 2
addi x28, x28, 30
jal x0, poll_dpu_pixel

send_pixel_bus:
sw x4, 0(x29) # store completed 32b bus to dcache
addi x29, x29, 4 # advance dcache mem pointer
sub x6, x12, x28 # x6 = 32 - last_valid
srl x4, x1, x6 # shift x1 right and store to x4 to preserve unsent bits
addi x28, x28, -2

# check if its the last data in the quadrant
bge x27, x26, quadrant_done
jal x0, poll_dpu_pixel

# if it is the last data in the quadrant, there should be 16 unsent bits in x4
quadrant_done:
and x4, x4, x7
sw x4, 0(x29)
addi x29, x29, 4
addi x27, x0, 0 # reset x27 for next quadrant
# check last pixel (bits 32, 31 still in x3)
addi x28, x0, 0 # reset packed-bit count
addi x4, x0, 0  # reset packing accumulator
beq x3, x13, start_inference
jal x0, poll_dpu_pixel

# ALL PIXELS LOADED FROM DPU

# all reg vals discarded
start_inference:
# set base address for tensor controller
lui x30, 0xE
addi x30, x30, 1424 # make x30 base address for tensor controller (58780)

# load shift value to tensor_controller
addi x1, x0, 6
sw x1, 12(x30) # store 6 to shift register

# setup 4 dcache memory pointers to start at quadrant base addr
addi x15, x0, 113
slli x15, x15, 2 # dcache addr gap between quadrants (3600 / 32 = 112.5 round up to 113 and each address is 4 apart)
# x11 is q1, x12 is q2, x13 is q3, x14 is q4
addi x11, x0, 12
add x12, x11, x15
add x13, x12, x15
add x14, x13, x15

# init tensor
sw x0, 4(x30)

addi x16, x0, 16 # number of 4-neuron groups in the 64-neuron first layer
addi x9, x0, 0 # tracks completed passes over the 3600 input pixels

inference_loop:
addi x9, x9, 1
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
and x28, x24, x17

# shift into correct position
slli x26, x26, 8
slli x27, x27, 16
slli x28, x28, 24

addi x1, x0, 0 # reset x1
or x1, x1, x25
or x1, x1, x26
or x1, x1, x27
or x1, x1, x28

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

sw x1, 8(x30)
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

sw x3, 8(x0)

# all done, go back to polling dpu pixels for next inference process
jal x0, repeat


