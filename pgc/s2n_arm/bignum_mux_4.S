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
// 256-bit multiplex/select z := x (if p nonzero) or z := y (if p zero)
// Inputs p, x[4], y[4]; output z[4]
//
//    extern void bignum_mux_4
//     (uint64_t p, uint64_t z[static 4],
//      uint64_t x[static 4], uint64_t y[static 4]);
//
// It is assumed that all numbers x, y and z have the same size 4 digits.
//
// Standard ARM ABI: X0 = p, X1 = z, X2 = x, X3 = y
// ----------------------------------------------------------------------------

        .globl  bignum_mux_4
        .text
        .balign 4

#define p x0
#define z x1
#define x x2
#define y x3
#define a x4


bignum_mux_4:

                cmp     p, #0                    // Set condition codes p = 0

                ldr     a, [x]
                ldr     p, [y]
                csel    a, a, p, ne
                str     a, [z]

                ldr     a, [x, #8]
                ldr     p, [y, #8]
                csel    a, a, p, ne
                str     a, [z, #8]

                ldr     a, [x, #16]
                ldr     p, [y, #16]
                csel    a, a, p, ne
                str     a, [z, #16]

                ldr     a, [x, #24]
                ldr     p, [y, #24]
                csel    a, a, p, ne
                str     a, [z, #24]

                ret

#if defined(__linux__) && defined(__ELF__)
.section .note.GNU-stack,"",%progbits
#endif
