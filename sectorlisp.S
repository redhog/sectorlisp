/*-*- mode:unix-assembly; indent-tabs-mode:t; tab-width:8; coding:utf-8     -*-│
│vi: set et ft=asm ts=8 tw=8 fenc=utf-8                                     :vi│
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2020 Justine Alexandra Roberts Tunney                              │
│ Copyright 2021 Alain Greppin                                                 │
│                                                                              │
│ Permission to use, copy, modify, and/or distribute this software for         │
│ any purpose with or without fee is hereby granted, provided that the         │
│ above copyright notice and this permission notice appear in all copies.      │
│                                                                              │
│ THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL                │
│ WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED                │
│ WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE             │
│ AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL         │
│ DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR        │
│ PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER               │
│ TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR             │
│ PERFORMANCE OF THIS SOFTWARE.                                                │
╚─────────────────────────────────────────────────────────────────────────────*/

// LISP meta-circular evaluator in a MBR

.set NIL,		1
.set ATOM_T,		9
.set ATOM_QUOTE,	13
.set ATOM_COND,		25
.set ATOM_ATOM,		35
.set ATOM_CAR,		45
.set ATOM_CDR,		53
.set ATOM_CONS,		61
.set ATOM_EQ,		71

.set g_token,	0x4000
.set g_str,	0x4080
.set boot,	0x7c00

////////////////////////////////////////////////////////////////////////////////
.section .text,"ax",@progbits
.globl	_start
.code16

_start:	jmp	.init				# some bios scan for short jump
.type kSymbols,@object;
kSymbols:
	.ascii "NIL\0T\0QUOTE\0COND\0ATOM\0CAR\0CDR\0CONS\0EQ"

.type .init,@function
.init:	ljmp	$0x600>>4,$_begin		# end of bios data roundup page
_begin:	push	%cs				# memory model cs=ds=es = 0x600
	push	%cs
	push	%cs
	pop	%ds
	pop	%es
	pop	%ss
	mov	$0x7c00-0x600,%cx
	mov	%cx,%sp
	cld
	xor	%ax,%ax
	mov	%ax,%fs				# fs = &g_mem
	xor	%di,%di
	rep stosb				# clears our bss memory
main:	mov	$g_str,%di
	mov	$kSymbols,%si
	mov	$37,%cx
	rep movsb
0:	mov	$'\n',%dl
	call	GetToken
	call	GetObject
	mov	$NIL,%dx
	call	Eval
	call	PrintObject
	mov	$'\r',%al
	call	PutChar
	jmp	0b

GetToken:					# GetToken():al, dl is g_look
	mov	$g_token,%di
1:	mov	%dl,%al
	cmp	$' ',%al
	jbe	2f
	stosb
	xchg	%ax,%cx
2:	call	GetChar				# bh = 0 after PutChar
	xchg	%ax,%dx				# dl = g_look
	cmp	$' ',%al
	jbe	1b
	cmp	$')',%al
	jbe	3f
	cmp	$')',%dl
	ja	1b
3:	movb	%bh,(%di)
	xchg	%cx,%ax
	ret

GetObject:					# called just after GetToken
	cmpb	$'(',%al
	je	GetList
	mov	$g_token,%si
.Intern:
	mov	%si,%bx				# save s
	mov	$g_str,%di
	xor	%al,%al
0:	mov	$-1,%cl
	push	%di				# save 1
1:	cmpsb
	jne	2f
	cmp	-1(%di),%al
	jne	1b
	jmp	4f
2:	pop	%si				# drop 1
	mov	%bx,%si				# restore s
	repne scasb
	cmp	(%di),%al
	jne	0b
	push	%di				# StpCpy
3:	lodsb
	stosb
	test	%al,%al
	jnz	3b
4:	pop	%ax				# restore 1
	add	$-g_str,%ax			# stc
	adc	%ax,%ax				# ax = 2 * ax + carry
.ret:	ret

PrintObject:					# PrintObject(x:ax)
	test	$1,%al
	xchg	%ax,%di
	jz	.PrintList
.PrintAtom:
	shr	%di
	lea	g_str(%di),%si
.PrintString:					# nul-terminated in si
	lodsb
	test	%al,%al
	jz	.ret				# -> ret
	call	PutChar
	jmp	.PrintString
.PrintList:
	mov	$'(',%al
2:	push	2(%di)				# save 1 Cdr(x)
	mov	(%di),%di			# di = Car(x)
	call	.PutObject
	pop	%ax				# restore 1
	cmp	$NIL,%ax
	je	4f
	test	$1,%al
	xchg	%ax,%di
	mov	$' ',%al
	jz	2b
	mov	$249,%al			# bullet (A∙B)
	call	.PutObject
4:	mov	$')',%al
	jmp	PutChar
.PutObject:					# .PutObject(c:al,x:di)
	call	PutChar				# preserves di
	xchg	%di,%ax
	jmp	PrintObject

GetChar:
	xor	%ax,%ax				# get keystroke
	int	$0x16				# keyboard service
						# ah is bios scancode
						# al is ascii character
PutChar:
#	push	%bx				# don't clobber di,si,cx,dx
#	push	%bp				# original ibm pc scroll up bug
	mov	$7,%bx				# normal mda/cga style page zero
	mov	$0x0e,%ah			# teletype output al cp437
	int	$0x10				# vidya service
#	pop	%bp				# preserves al
#	pop	%bx
	cmp	$'\r',%al			# don't clobber stuff
	jne	.ret
	mov	$'\n',%al
	jmp	PutChar				# bx volatile, bp never used

GetList:call	GetToken
	cmpb	$')',%al
	je	.retF
	call	GetObject
	push	%ax				# save 1
	call	GetList
	xchg	%ax,%si
	pop	%di				# restore 1
	jmp	Cons

////////////////////////////////////////////////////////////////////////////////

Evlis:	cmp	$NIL,%di			# Evlis(m:di,a:dx):ax
	je	1f
	push	2(%di)				# save 1 Cdr(m)
	mov	(%di),%ax
	push	%dx				# save a
	call	Eval
	pop	%dx				# restore a
	pop	%di				# restore 1
	push	%ax				# save 2
	call	Evlis
	xchg	%ax,%si
	pop	%di				# restore 2
#	jmp	Cons
Cons:	xchg	%di,%ax
	mov	%fs,%di
	push	%di
	stosw
	xchg	%si,%ax
	stosw
	mov	%di,%fs
	pop	%ax
	ret
1:	xchg	%di,%ax
	ret

Pairlis:cmp	$NIL,%di			# Pairlis(x:di,y:si,a:dx):ax
	je	1f
	push	2(%di)				# save 1 Cdr(x)
	push	2(%si)				# save 2 Cdr(y)
	mov	(%di),%di
	mov	(%si),%si
	call	Cons				# preserves dx
	pop	%si				# restore 2
	pop	%di				# restore 1
	push	%ax				# save 3
	call	Pairlis
	xchg	%ax,%si
	pop	%di				# restore 3
	jmp	Cons				# can be inlined here
1:	xchg	%dx,%ax
	ret

Apply:	test	$1,%al				# Apply(fn:ax,x:si:a:dx):ax
	jnz	.switch
	xchg	%ax,%di				# di = fn
.lambda:mov	2(%di),%di			# di = Cdr(fn)
	push	%di				# save 1
	mov	(%di),%di			# di = Cadr(fn)
	call	Pairlis
	xchg	%ax,%dx
	pop	%di				# restore 1
	jmp	.EvCadr
.switch:cmp	$ATOM_EQ,%ax
	ja	.dflt1
	mov	(%si),%di			# di = Car(x)
.ifCar:	cmp	$ATOM_CAR,%al
	jne	.ifCdr
	mov	(%di),%ax
	ret
.ifCdr:	cmp	$ATOM_CDR,%al
	jne	.ifAtom
	mov	2(%di),%ax
	ret
.ifAtom:cmp	$ATOM_ATOM,%al
	jne	.ifCons
	test	$1,%di
	jnz	.retT
.retF:	mov	$NIL,%ax			# ax = NIL
	ret
.ifCons:mov	2(%si),%si			# si = Cdr(x)
	mov	(%si),%si			# si = Cadr(x)
	cmp	$ATOM_CONS,%al
	je	Cons
.isEq:	cmp	%di,%si
	jne	.retF
.retT:	mov	$ATOM_T,%al			# ax = ATOM_T
	ret
.dflt1:	push	%si				# save x
	push	%dx				# save a
	call	Eval
	pop	%dx				# restore a
	pop	%si				# restore x
	jmp	Apply

Eval:	test	$1,%al				# Eval(e:ax,a:dx):ax
	jnz	Assoc
	xchg	%ax,%di				# di = e
	mov	(%di),%ax			# ax = Car(e)
	cmp	$ATOM_QUOTE,%ax			# maybe CONS
	je	Cadr
	mov	2(%di),%di			# di = Cdr(e)
	cmp	$ATOM_COND,%ax
	je	Evcon
.Ldflt2:push	%ax				# save 2
	call	Evlis				# preserves dx
	xchg	%ax,%si
	pop	%ax				# restore 2
	jmp	Apply

Cadr:	mov	2(%di),%di			# contents of decrement register
	mov	(%di),%ax			# contents of address register
	ret

Evcon:	push	%di				# save c
	mov	(%di),%di			# di = Car(c)
	mov	(%di),%ax			# ax = Caar(c)
	push	%dx				# save a
	call	Eval
	pop	%dx				# restore a
	pop	%di				# restore c
	cmp	$NIL,%ax
	jne	2f
	mov	2(%di),%di			# di = Cdr(c)
	jmp	Evcon
2:	mov	(%di),%di			# di = Car(c)
.EvCadr:call	Cadr				# ax = Cadar(c)
	jmp	Eval

Assoc:	cmp	$NIL,%dx			# Assoc(x:ax,y:dx):ax
	mov	%dx,%si
	je	.retF
	mov	(%si),%bx			# bx = Car(y)
	mov	(%bx),%cx			# cx = Caar(y)
	cmp	%cx,%ax
	jne	1f
	mov	2(%bx),%ax			# ax = Cdar(y)
	ret
1:	mov	2(%si),%dx			# dx = Cdr(y)
	jmp	Assoc

.type .sig,@object;
.sig:
.fill 510 - (. - _start), 1, 0xce
.word 0xAA55
