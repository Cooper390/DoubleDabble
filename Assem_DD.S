; PROJECT  :ADCAssemblyTimer1OVFTriggerSource + DoubleDabble2025 Integration
; PURPOSE  :ADC in Assembly triggered by Timer1 Overflow and output via Serial
; COURSE   :ICS4U-E
; AUTHOR   :C. D'Arcy and Nate Cooper (modifications combined)
; DATE     :2025 05 04
; MCU      :328P
; STATUS   :Working
; REFERENCE:http://darcy.rsgc.on.ca/ACES/TEI4M/Assembly/images/InterruptVectorTable.png
;          :http://www.rjhcoding.com/avr-asm-tutorials.php

#include <avr/io.h>
#include "Timerprescalers.h"
#include "ADCprescalers.h"

.global main
.global TIMER1_OVF_vect
.global ADC_vect

.section .text
.equ plHI,  0x00
.equ plLO,  0x00
.equ BAUD_PRESCALER, 103
.equ ASYNCHRONOUS, 0<<UMSEL01 | 0<<UMSEL00
.equ PARITY_NONE,  0<<UPM01 | 0<<UPM00
.equ CHAR_SIZE8,   0<<UCSZ02 | 1<<UCSZ01 | 1<<UCSZ00
.equ STOP_BITS1,   0<<USBS0
.equ cTHREEZERO,0x30

util    = 16
bin0    = 18
bin1    = 19
BCD01   = 20
BCD23   = 21
BCD4    = 22
offset  = 23

.org 0x00
  jmp main
.org 0x1A
  jmp TIMER1_OVF_vect
.org 0x2A
  jmp ADC_vect

.org _VECTORS_SIZE

.org 0x100
main:
  rcall IOSetup
  rcall TIMER1Setup
  rcall ADCSetup
  rcall USARTSetup
  sei
hold:
  rjmp hold
  ret

USARTSetup:
  ldi util, hi8(BAUD_PRESCALER)
  sts UBRR0H, util
  ldi util, lo8(BAUD_PRESCALER)
  sts UBRR0L, util
  ldi util, (1<<RXEN0) | (1<<TXEN0)
  sts UCSR0B, util
  ldi util, ASYNCHRONOUS | CHAR_SIZE8 | PARITY_NONE | STOP_BITS1
  sts UCSR0C, util
  ret

IOSetup:
  sbi DDRB-0x20, DDB5
  ret

ADCSetup:
  ser util
  sts DIDR0, util
  ldi util, ADCAVCC
  ori util, ADC5
  sts ADMUX, util
  ldi util, 1<<ADEN
  ori util, 1<<ADSC
  ori util, ADCps128
  sts ADCSRA, util
dummy:
  lds util, ADCSRA
  sbrs util, ADIF
  rjmp dummy
  lds util, ADCSRA
  ori util, 1<<ADIF
  ori util, 1<<ADATE
  sts ADCSRA, util
  ldi util, ADCtsT1OVF
  sts ADCSRB, util
  lds util, ADCSRA
  ori util, 1<<ADIE
  sts ADCSRA, util
  ret

TIMER1Setup:
  clr util
  sts TCCR1A, util
  ldi util, T1ps64
  sts TCCR1B, util
  ldi util, plHI
  sts TCNT1H, util
  ldi util, plLO
  sts TCNT1L, util
  ldi util, 1<<TOIE1
  sts TIMSK1, util
  ret

TIMER1_OVF_vect:
  ldi util, plHI
  sts TCNT1H, util
  ldi util, plLO
  sts TCNT1L, util
  reti

ADC_vect:
  lds bin0, ADCL
  lds bin1, ADCH
  rcall doubleDabble
  rcall display
  sbi PINB-0x20, DDB5
  ldi r24, 0x0A     ; newline
  rcall TXCHAR
  ldi r24, 0x0D     ; return
  rcall TXCHAR
  reti

doubleDabble:
    ; clear BCD
    clr   BCD4
    clr   BCD23
    clr   BCD01

    ; load & pre-align 10-bit ADC into r24:r25
    mov   r24, bin1
    mov   r25, bin0
    ldi   r17, 6
.align_input:
    lsl   r25
    rol   r24
    dec   r17
    brne  .align_input

    ldi   r17, 10    ; # of bits to process
.loop:
    ; —— add-3 per digit ——
    cpi   BCD4, 5
    brlo  .skip4
    subi  BCD4, -3
.skip4:
    mov   r16, BCD23
    swap  r16
    andi  r16, 0x0F
    cpi   r16, 5
    brlo  .skip3
    subi  BCD23, -0x30
.skip3:
    mov   r16, BCD23
    andi  r16, 0x0F
    cpi   r16, 5
    brlo  .skip2
    subi  BCD23, -3
.skip2:
    mov   r16, BCD01
    swap  r16
    andi  r16, 0x0F
    cpi   r16, 5
    brlo  .skip1
    subi  BCD01, -0x30
.skip1:
    mov   r16, BCD01
    andi  r16, 0x0F
    cpi   r16, 5
    brlo  .no_add1
    subi  BCD01, -3
.no_add1:

    ; —— shift BCD chain ——
    lsl   BCD4
    rol   BCD23
    rol   BCD01

    ; —— shift binary & insert ——
    lsl   r25
    rol   r24
    brcc  .no_insert
    ori   BCD01, 0x01
.no_insert:

    dec   r17
    brne  .loop
    ret
display:
  ldi   offset,'0'
  mov   r24,BCD4
  andi  r24,0x0F
  add   r24,offset
  rcall TXCHAR
  mov   r24,BCD23
  swap  r24
  andi  r24,0x0F
  add   r24,offset
  rcall TXCHAR
  mov   r24,BCD23
  andi  r24,0x0F
  add   r24,offset
  rcall TXCHAR
  mov   r24,BCD01
  swap  r24
  andi  r24,0x0F
  add   r24,offset
  rcall TXCHAR
  mov   r24,BCD01
  andi  r24,0x0F
  add   r24,offset
  rcall TXCHAR
  ret

; PreCondition:  Character data (1 byte) to be transmitted is in R24
; PostCondition: Contents of R24 are transmitted via the USART (should appear on the Serial Monitor)

TXCHAR:
  lds   util,UCSR0A
  sbrs  util,UDRE0
  rjmp  .-8
  sts   UDR0, r24
  ret