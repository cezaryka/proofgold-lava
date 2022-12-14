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
// Reduce modulo group order, z := x mod n_256k1
// Input x[4]; output z[4]
//
//    extern void bignum_mod_n256k1_4
//     (uint64_t z[static 4], uint64_t x[static 4]);
//
// Reduction is modulo the group order of the secp256k1 curve.
//
// Standard ARM ABI: X0 = z, X1 = x
// ----------------------------------------------------------------------------

        .globl  bignum_mod_n256k1_4
        .text
        .balign 4

#define z x0
#define x x1

#define n0 x2
#define n1 x3
#define n2 x4
#define n3 x5

#define d0 x6
#define d1 x7
#define d2 x8
#define d3 x9

// Loading large constants

#define movbig(nn,n3,n2,n1,n0)                                              \
                movz    nn, n0;                                             \
                movk    nn, n1, lsl #16;                                    \
                movk    nn, n2, lsl #32;                                    \
                movk    nn, n3, lsl #48

bignum_mod_n256k1_4:

// Load the complicated three words of n_256k1, the other being all 1s

                movbig( n0, #0xbfd2, #0x5e8c, #0xd036, #0x4141)
                movbig( n1, #0xbaae, #0xdce6, #0xaf48, #0xa03b)
                mov     n2, 0xFFFFFFFFFFFFFFFE

// Load the input number

                ldp     d0, d1, [x]
                ldp     d2, d3, [x, #16]

// Do the subtraction. Since word 3 of n_256k1 is all 1s, that can be
// done by adding zero with carry, thanks to the inverted carry.

                subs    n0, d0, n0
                sbcs    n1, d1, n1
                sbcs    n2, d2, n2
                adcs    n3, d3, xzr

// Now if the carry is *clear* (inversion at work) the subtraction carried
// and hence we should have done nothing, so we reset each n_i = d_i

                csel    n0, d0, n0, cc
                csel    n1, d1, n1, cc
                csel    n2, d2, n2, cc
                csel    n3, d3, n3, cc

// Store the end result

                stp     n0, n1, [z]
                stp     n2, n3, [z, #16]

                ret

#if defined(__linux__) && defined(__ELF__)
.section .note.GNU-stack,"",%progbits
#endif
