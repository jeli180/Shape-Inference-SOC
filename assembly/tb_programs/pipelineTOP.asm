test cases:
- every instruction, use x0 DONE
- register forwarding DONE
- consecutive branches, jals DONE
- all stall cases for mshr (mshr done DONE, mshr full DONE, dependency on ex DONE, jal/branch DONE)
- using values in register file DONE
- dcache behavior 

#itype x1-5 should contain their numbers, also tests reg forwarding
addi x1, x0, 1
xori x2, x1, 3
ori x1, x2, 0
addi x1, x1, -1
andi x3, x2, 3
addi x3, x3, 1
slli x4, x1, 2
srli x5, x4, 1
addi x5, x5, 3

#rtype x6-10 should contain their numbers
add x6, x2, x4
sub x7, x6, x3
addi x7, x7, 4
xor x8, x4, x0
sll x8, x8, x1
or x9, x8, x1
and x10, x7, 15
addi x10, x10, 3

#test srai, slti, sltiu for rtype and itype x11-x14 should have their numbers
addi x11, x0, -24
srai x11, x11, 2
sltiu x12, x11, 32
addi x12, x12, 12
slti x13, x11, 0
addi x13, x13, 12
addi x15, x0, -24
sra x15, x15, x2
slt x11, x15, x4
addi x11, x11, 10
sltu x14, x15, x4
addi x14, x14, 14

#test branching/jaling
addi x15, x5, -5
bne x15, x0, branch2
branch1:
addi x15, x15, 1
beq x15, x4, branch2
jal x29, branch1
branch2: #x15 should be 4
jal x29, branch3
beq x0, x0, branch4
branch4:
addi x15, x0, 100
branch3: x15 should still be 4
blt x4, x8, branch5
addi x15, x0, 100
branch5:
bge x4, x8, error1
addi x15, x15, 1
beq x0, x0, pass1

error1:
jal x29, error2
pass1: #x15 = 5
addi x15, x15, 10

#test lw, sw, dcache and mshr
addi x26, x0, 16
addi x27, x0, 17

addi x20, x0, 4
addi x21, x0, 68 
addi x22, x0, 132

#hit
sw x26, 4(x0)
lw x16, 4(x0)

#miss, basic mshr test case
sw x27, 4(x0)
sw x26, 262(x0)
sw x26, 516(x0)
lw x17, 4(x0)
jal x25, jal1

jal1:
# mshr full test case 
# use reg 18, 19, 20, 21, 22
# value in x24, x25, x26, x27, x28 bad val in x29

addi x24, x0, 18
addi x25, x0, 19
addi x26, x0, 20 
addi x27, x0, 21
addi x28, x0, 24 # wrong to test reg dep
addi x29, x0, 101

sw x24, 0(x0)
sw x25, 4(x0)
sw x26, 8(x0)
sw x27, 12(x0)
sw x28, 16(x0)

# change to second level 5 cons starting at 256
sw x29, 256(x0)
sw x29, 262(x0)
sw x29, 268(x0)
sw x29, 274(x0)
sw x29, 280(x0)
# change to third level 
sw x29, 512(x0)
sw x29, 518(x0)
sw x29, 524(x0)
sw x29, 530(x0)
sw x29, 536(x0)

#should be 5 load misses
lw x18, 0(x0)
lw x19, 4(x0)
lw x20, 8(x0)
lw x21, 12(x0)
lw x22, 16(x0)

addi x22, x22, -2 #correct wrong x22 val from cache

addi x29, x0, 23
sw x29, 262(x0)
lw x23, 262(x0)

beq x0, x0, pass2
error2:
addi x15, x0, 100
jalr x28, 0(x29)

pass2:
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0
addi x0, x0, 0

#testbench end case, check all reg up to x23
addi x31, x0, 0

#check by looking at regdata
addi x1, x1, 0
addi x2, x2, 0
addi x3, x3, 0
addi x4, x4, 0
addi x5, x5, 0
addi x6, x6, 0
addi x7, x7, 0
addi x8, x8, 0
addi x9, x9, 0
addi x10, x10, 0
addi x11, x11, 0
addi x12, x12, 0
addi x13, x13, 0
addi x14, x14, 0
addi x15, x15, 0
addi x16, x16, 0
addi x17, x17, 0
addi x18, x18, 0
addi x19, x19, 0
addi x20, x20, 0
addi x21, x21, 0
addi x22, x22, 0
addi x23, x23, 0