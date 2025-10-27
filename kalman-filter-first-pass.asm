kalman_filter:
    mov rA_ptr, rdi
    mov rX_ptr, rdx
    mov rP_ptr, rsi
    mov rC_ptr, r13
    mov rP_out, r14
    mov rZ_ptr, r12
    mov rH_ptr, r9
    mov rR_ptr, r10
    mov rY_ptr, r15
    mov rK_ptr, r11
    xor rN, rN
    
row_loop:
    cmp rN, N
    jae done
    vpxor ymm_acc, ymm_acc, ymm_acc
    mov rA_row, rA_ptr
    mov rX_block, rX_ptr

col_loop:
    cmp rN, N
    jae col_done
    vmovdqu ymmA, [rA_row]
    vmovdqu ymmX, [rX_block]
    vpmovzxwd ymmA, ymmA
    vpmovzxwd ymmX, ymmX
    vpmaddwd ymm_tmp, ymmA, ymmX
    vpaddd ymm_acc, ymm_acc, ymm_tmp
    add rA_row, BLOCK_STRIDE_A
    add rX_block, BLOCK_STRIDE_X
    sub rN, BLOCK_SIZE
    jg col_loop

col_done:
    vextracti128 xmm_hi, ymm_acc, 1
    vpaddd xmm_acc, xmm_acc, xmm_hi
    vmovdqu [rC_ptr], xmm_acc

    xor rM, rM
    mov rP_block, rP_ptr

cov_loop:
    cmp rM, N
    jae cov_done
    vpxor ymm_acc, ymm_acc, ymm_acc
    mov rA_row2, rA_ptr
    mov rP_block2, rP_block
    xor rK, rK

k_loop:
    cmp rK, N
    jae k_done
    vmovdqu ymmA, [rP_block2 + rN*STRIDE_P + rK*2]
    vpmovzxwd ymmA, ymmA
    vmovdqu ymmB, [rA_row2 + rM*STRIDE_A + rK*2]
    vpmovzxwd ymmB, ymmB
    vpmaddwd ymm_tmp, ymmA, ymmB
    vpaddd ymm_acc, ymm_acc, ymm_tmp
    add rK, BLOCK_SIZE
    jmp k_loop

k_done:
    vmovdqu ymmQ, [rR_ptr + rN*STRIDE_Q + rM*2]
    vpmovzxwd ymmQ, ymmQ
    vpaddd ymm_acc, ymm_acc, ymmQ
    vextracti128 xmm_hi, ymm_acc, 1
    vpaddd xmm_acc, xmm_acc, xmm_hi
    vmovdqu [rP_out + rN*STRIDE_P + rM*2], xmm_acc
    add rM, BLOCK_SIZE
    jmp cov_loop

cov_done:
    xor rM, rM

innov_loop:
    cmp rM, M
    jae innov_done
    vpxor ymm_acc, ymm_acc, ymm_acc
    mov rH_row, rH_ptr
    mov rX_block, rC_ptr

col_innov:
    cmp rN, N
    jae col_done_innov
    vmovdqu ymmH, [rH_row]
    vmovdqu ymmX, [rX_block]
    vpmovzxwd ymmH, ymmH
    vpmovzxwd ymmX, ymmX
    vpmaddwd ymm_tmp, ymmH, ymmX
    vpaddd ymm_acc, ymm_acc, ymm_tmp
    add rH_row, BLOCK_STRIDE_H
    add rX_block, BLOCK_STRIDE_X
    sub rN, BLOCK_SIZE
    jg col_innov

col_done_innov:
    vextracti128 xmm_hi, ymm_acc, 1
    vpaddd xmm_acc, xmm_acc, xmm_hi
    vmovdqu [rY_ptr + rM*2], xmm_acc
    add rM, BLOCK_SIZE
    jmp innov_loop

innov_done:
    xor rM, rM

gain_loop:
    cmp rM, M
    jae gain_done
    vpxor ymm_acc, ymm_acc, ymm_acc
    mov rP_block, rP_out
    mov rH_col, rH_ptr

col_gain:
    cmp rN, N
    jae col_done_gain
    vmovdqu ymmP, [rP_block + rN*STRIDE_P + rM*2]
    vmovdqu ymmH, [rH_col]
    vpmovzxwd ymmP, ymmP
    vpmovzxwd ymmH, ymmH
    vpmaddwd ymm_tmp, ymmP, ymmH
    vpaddd ymm_acc, ymm_acc, ymm_tmp
    add rP_block, BLOCK_STRIDE_P
    add rH_col, BLOCK_STRIDE_H
    sub rN, BLOCK_SIZE
    jg col_gain

col_done_gain:
    vmovdqu [rK_ptr + rM*STRIDE_K], ymm_acc
    add rM, BLOCK_SIZE
    jmp gain_loop

gain_done:
    xor rM, rM

state_update_loop:
    cmp rM, N
    jae state_done
    vmovdqu ymmK, [rK_ptr + rM*STRIDE_K]
    vmovdqu ymmY, [rY_ptr + rM*2]
    vpmaddwd ymm_tmp, ymmK, ymmY
    vpaddd ymm_tmp, ymm_tmp, [rC_ptr + rM*2]
    vmovdqu [rC_ptr + rM*2], ymm_tmp
    add rM, BLOCK_SIZE
    jmp state_update_loop

state_done:
    xor rM, rM

cov_update_loop:
    cmp rM, N
    jae done
    vpxor ymm_acc, ymm_acc, ymm_acc
    mov rK_row, rK_ptr
    mov rH_col, rH_ptr
    mov rP_block, rP_out

col_cov:
    cmp rN, N
    jae col_done_cov
    vmovdqu ymmK, [rK_row + rM*STRIDE_K]
    vmovdqu ymmH, [rH_col]
    vmovdqu ymmP, [rP_block + rN*STRIDE_P + rM*2]
    vpmovzxwd ymmK, ymmK
    vpmovzxwd ymmH, ymmH
    vpmaddwd ymm_tmp, ymmK, ymmH
    vpsubd ymm_tmp, rI, ymm_tmp
    vpmaddwd ymm_tmp2, ymm_tmp, ymmP
    vpaddd ymm_acc, ymm_acc, ymm_tmp2
    add rK_row, BLOCK_STRIDE_K
    add rH_col, BLOCK_STRIDE_H
    add rP_block, BLOCK_STRIDE_P
    sub rN, BLOCK_SIZE
    jg col_cov

col_done_cov:
    vmovdqu [rP_out + rM*STRIDE_P], ymm_acc
    add rM, BLOCK_SIZE
    jmp cov_update_loop

done:
    vzeroupper
    ret
