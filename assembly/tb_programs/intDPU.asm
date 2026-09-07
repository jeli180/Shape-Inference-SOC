sw x0, 4(x0) # init command

# now poll h4 for pixel data
# need 480 valid 30b buses
# 32nd bit high means last bus (all pixels sent)
# 31st bit high means bus is valid, all 30 bits filled with data

addi x10, x0, 1 # AND mask for 30th bit
slli x11, x10, 30 # 31st bit high
slli x12, x10, 31 # 32nd bit high

addi x20, x0, 12 # holds the address pixel bus is stored to

addi x13, x0, -1
srli x13, x13, 2 # lsb 30 bits high bit mask

pixel_poll:
lw x2, 4(x0)
and x3, x2, x11
beq x3, x11, valid_bus
jal x0, pixel_poll

valid_bus:
# store data to memory
and x5, x2, x13 # mask msb 2 bits low
sw x5, 0(x20) # store
addi x20, x20, 4 # advance memory address 
sw x0, 4(x0) # tell dpu data recieved

# determine if current data is last data
and x4, x2, x12
beq x4, x12, shape_send
jal x0, pixel_poll

shape_send: # all pixels sent, now sending shapes to h8
# convention is bit [6:3] is what quadrant (0001 is 1st)
# [2:0] is what shape in that quadrant
# 100 is circle, 010 is square, 001 is line
# testbench expects quadrant 1, 4 circle, 2 is line, 3 is square
addi x25, x0, 4 # circle
addi x26, x0, 2 # square
addi x27, x0, 1 # line

# send quadrant 1 circle
addi x28, x0, 1
slli x28, x28, 3
or x29, x28, x25
sw x29, 8(x0)

# send quadrant 2 line
slli x28, x28, 1
or x29, x28, x27
sw x29, 8(x0)

# send quadrant 3 square
slli x28, x28, 1
or x29, x28, x26
sw x29, 8(x0)

# send quadrant 4 circle
slli x28, x28, 1
or x29, x28, x25
sw x29, 8(x0)

addi x1, x0, 1
# poll h8 to know when dpu done
poll_full_done:
lw x9, 8(x0)
beq x9, x1, check
jal x0, poll_full_done

# check that data is right 
# tb_integratedDPU expects a write to register 31
# then the buses stored to memory to be written to register 30
check:
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0

addi x7, x0, 8 # should be 480 but lowered for sim
addi x8, x0, 0
addi x20, x0, 12
addi x31, x0, 0

send_loop:
lw x6, 0(x20)
addi x30, x6, 0 # tb monitors

addi x8, x8, 1
addi x20, x20, 4

beq x7, x8, done
jal x0, send_loop

done:
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0