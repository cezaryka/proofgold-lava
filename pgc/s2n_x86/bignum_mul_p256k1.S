/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 * You may not use this file except in compliance with the License.
 * A copy of the License is located at
 *
 *  http://aws.amazon.com/apache2.0
 *
 * or in the "LICENSE" file accompanying this file. This file is distributed
 * on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
 * express or implied. See the License for the specific language governing
 * permissions and limitations under the License.
 */

// ----------------------------------------------------------------------------
// Multiply modulo p_256k1, z := (x * y) mod p_256k1
// Inputs x[4], y[4]; output z[4]
//
//    extern void bignum_mul_p256k1
//     (uint64_t z[static 4], uint64_t x[static 4], uint64_t y[static 4]);
//
// Standard x86-64 ABI: RDI = z, RSI = x, RDX = y
// ----------------------------------------------------------------------------

        .intel_syntax noprefix
        .globl  bignum_mul_p256k1
        .text

// These are actually right

#define z rdi
#define x rsi

// Copied in or set up

#define y rcx

// A zero register

#define zero rbp
#define zeroe ebp

// mulpadd(high,low,m) adds rdx * m to a register-pair (high,low)
// maintaining consistent double-carrying with adcx and adox,
// using rax and rbx as temporaries.

#define mulpadd(high,low,m)             \
        mulx    rbx, rax, m;            \
        adcx    low, rax;               \
        adox    high, rbx

// mulpade(high,low,m) adds rdx * m to a register-pair (high,low)
// maintaining consistent double-carrying with adcx and adox,
// using rax as a temporary, assuming high created from scratch
// and that zero has value zero.

#define mulpade(high,low,m)             \
        mulx    high, rax, m;           \
        adcx    low, rax;               \
        adox    high, zero

bignum_mul_p256k1:

// Save more registers to play with

        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15

// Copy y into a safe register to start with

        mov     y, rdx

// Zero a register, which also makes sure we don't get a fake carry-in

        xor     zeroe, zeroe

// Do the zeroth row, which is a bit different

        mov     rdx, [y]

        mulx    r9, r8, [x]
        mulx    r10, rax, [x+8]
        add     r9, rax
        mulx    r11, rax, [x+16]
        adc     r10, rax
        mulx    r12, rax, [x+24]
        adc     r11, rax
        adc     r12, zero

// Add row 1

        xor     zeroe, zeroe
        mov     rdx, [y+8]
        mulpadd(r10,r9,[x])
        mulpadd(r11,r10,[x+8])
        mulpadd(r12,r11,[x+16])
        mulpade(r13,r12,[x+24])
        adcx    r13, zero

// Add row 2

        xor     zeroe, zeroe
        mov     rdx, [y+16]
        mulpadd(r11,r10,[x])
        mulpadd(r12,r11,[x+8])
        mulpadd(r13,r12,[x+16])
        mulpade(r14,r13,[x+24]);
        adcx    r14, zero

// Add row 3

        xor     zeroe, zeroe
        mov     rdx, [y+24]
        mulpadd(r12,r11,[x])
        mulpadd(r13,r12,[x+8])
        mulpadd(r14,r13,[x+16]);
        mulpade(r15,r14,[x+24]);
        adcx    r15, zero

// Now we have the full 8-digit product 2^256 * h + l where
// h = [r15,r14,r13,r12] and l = [r11,r10,r9,r8]
// and this is == 4294968273 * h + l (mod p_256k1)

        mov     rdx, 4294968273

        xor     zeroe, zeroe

        mulpadd(r9,r8,r12)
        mulpadd(r10,r9,r13)
        mulpadd(r11,r10,r14)
        mulpade(r12,r11,r15)
        adcx    r12, zero

// Now we have reduced to 5 digits, 2^256 * h + l = [r12,r11,r10,r9,r8]
// Use q = h + 1 as the initial quotient estimate, either right or 1 too big.

        lea     rax, [r12+1]
        mulx    rbx, rax, rax
        add     r8, rax
        adc     r9, rbx
        adc     r10, zero
        adc     r11, zero

// Now the effective answer is 2^256 * (CF - 1) + [r11,r10,r9,r8]
// So we correct if CF = 0 by subtracting 4294968273, i.e. by
// adding p_256k1 to the "full" answer

        sbb     rax, rax
        not     rax
        and     rax, rdx
        sub     r8, rax
        sbb     r9, zero
        sbb     r10, zero
        sbb     r11, zero

// Write everything back

        mov     [z], r8
        mov     [z+8], r9
        mov     [z+16], r10
        mov     [z+24], r11

// Restore registers and return

        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx

        ret

#if defined(__linux__) && defined(__ELF__)
.section .note.GNU-stack,"",%progbits
#endif
