computer and fpga communicate over built in uart

tx/rx from fpga perspective

uart_tower: 
    contains ingress fifo 
    grants credits, init signals, and shape classes through tx

    acts as peripheral to MMIO

computer:
    send pixel data according to credit scheme
    wait for shape classes, then process when it recieves
    should have a button to replace tapping screen > 480

packet scheme
 tx types: 
    - start signal (CPU writes to addr4)
        - can just be 1 (software will also track states), 2 msb 00
    - credits (can just be the num of credits to grant in lower) 2msb 01
    - shape classification header (msb of byte is high) 2msb 10
    - shape classification (CPU writes to addr 8)
        - msb bits can be bottom right quadrant
        - 01 circle, 10 square, 11 line

 rx types:
    - pixel data, need 4 uart frames, first frame is lsb of 32 bit word 
