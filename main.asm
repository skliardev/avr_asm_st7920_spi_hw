;
; controller.asm
;
; Created: 02.11.2021 15:35:21
; Author : Dmitry
;
.include "m328pdef.inc"

; переопределения
; accumulator data uint16_t
.def ACL = r16
.def ACH = r17
; counter data uint16_t, for m328p {24, 26, 28, 30}
.def CNL = r24
.def CNH = r25
; LCD PINS
.equ SS = PB2

; константы
.equ NULL = 0x0			; Определение константы
.equ FCPU = 16000000	; Частота кварца 16 MHz

; макросы
.macro uout
.if @0 < 0x40 
	out @0, @1 
.else
	sts @0, @1 
.endif 
.endm

.macro uin 
.if @1 < 0x40 
	in @0, @1 
.else
	lds @0, @1
.endif
.endm

#define getdelay(x) ((x * (FCPU/1000000) - 20) / 4)

; функция задержки
; -> CNH:CNL = N[tics] = (T[us] * 16[tics/us] - 12) / 4
.macro delay
.if @0 > 1 && @0 <= 16000
	#define number getdelay(@0)
	push CNL
	push CNH
	ldi CNL, LOW(number)
	ldi CNH, HIGH(number)
	call delay_us
	pop CNH
	pop CNL
	#undef number
.else
	.error "delay: 0 < param <= 16000!!!"
.endif
.endm

; функция отправки комманды или данных
; -> XH:HL - указатель на массив
; -> CNH:CNL - указатель количества байт (данных или команд)
; -> ACL - указывает команда или данные (ACL - 0 inst, 1 data)
; -> ACH - временный регистр
.macro lcd_tx
	push ACL
	push ACH
	push CNL
	push CNH
	push XL
	push XH
.if @0 >= 0 && @0 < 2
	ldi ACL, LOW(@0)
.else
	.error "lcd_tx: the first parameter must be set to '0'-code or '1'-data"
.endif
.if @1 < 1
	.error "lcd_tx: CNH:CNL must be above zero!"
.endif
	ldi CNL, LOW(@1)
	ldi CNH, HIGH(@1)
	ldi XL, LOW(@2)
	ldi XH, HIGH(@2)
	call spi_trx
	pop XH
	pop XL
	pop CNH
	pop CNL
	pop ACH
	pop ACL
.endm

; before use to write to X the address Sram 
.macro lxdata
	#define number getdelay(@0)
	ldi ACL, @1
	st X+, ACL
	ldi ACL, HIGH(number)
	st X+, ACL
	ldi ACL, LOW(number)
	st X+, ACL
	#undef number
.endm

; оперативная память SRAM
.dseg
buffer_index_cmd: .byte 1
buffer_spi_cmd: .byte 100
buffer_index_disp: .byte 1
buffer_spi_disp: .byte 1024

; код программы FLASH
.cseg
vec_reset:
	jmp vec_init	; ResetVector
	jmp vec_bad		; INT0addr
	jmp vec_bad		; INT1addr
	jmp vec_bad		; PCI0addr
	jmp vec_bad		; PCI1addr
	jmp vec_bad		; PCI2addr
	jmp vec_bad		; WDTaddr
	jmp vec_bad		; OC2Aaddr
	jmp vec_bad		; OC2Baddr
	jmp vec_bad		; OVF2addr
	jmp vec_bad		; ICP1addr
	jmp vec_bad		; OC1Aaddr
	jmp vec_bad		; OC1Baddr
	jmp vec_bad		; OVF1addr
	jmp vec_bad		; OC0Aaddr
	jmp vec_bad		; OC0Baddr
	jmp vec_bad		; OVF0addr
	jmp vec_bad		; SPIaddr
	jmp vec_bad		; URXCaddr
	jmp vec_bad		; UDREaddr
	jmp vec_bad		; UTXCaddr
	jmp vec_bad		; ADCCaddr
	jmp vec_bad		; ERDYaddr
	jmp vec_bad		; ACIaddr
	jmp vec_bad		; TWIaddr
	jmp vec_bad		; SPMRaddr

.org INT_VECTORS_SIZE
vec_bad:
	rjmp vec_bad

; инициализация
vec_init:
	; Инициализация стека в конец SRAM
	ldi ACL, low(ramend) 
	uout spl, ACL
	ldi ACL, high(ramend)
	uout sph, ACL
	; выбор минимального предделителя (максимальная скорость системы) CLKPR = 0x80, CLKPR = 0x00
	ldi ACL, 0x80
	uout clkpr, ACL
	ldi ACL, 0x00
	uout clkpr, ACL
	; инициализация работы SPI Master FCPU/32 setup falling
	; - /SS,MOSI,SCK установка выводов на выход
	ldi ACL, (1<<SS | 1<<PB3 | 1<<PB5)
	uout DDRB, ACL
	ldi ACL, (1<<SPE | 1<<MSTR | 1<<CPHA | 1<<SPR1) ; (1<<DORD)
	uout SPCR, ACL
	ldi ACL, (1<<SPI2X)
	uout SPSR, ACL
	; инициализация данных
	ldi XL, LOW(buffer_spi_cmd)
	ldi XH, HIGH(buffer_spi_cmd)	; 4 count
	lxdata 75,	 0b00000110	; Entry mode set, increased cursor		0b0000_01{I/D}{S}
	lxdata 2000, 0b00000001	; Display clear
	lxdata 75,	 0b00000010	; Displat home
	lxdata 75,   0b00001100	; Display on, cursor on and blink off	0b0000_1{d}{c}{b}

	ldi XL, LOW(buffer_spi_disp)
	ldi XH, HIGH(buffer_spi_disp)	; 16 count
	lxdata 2, 'D'
	lxdata 2, 'I'
	lxdata 2, 'M'
	lxdata 2, 'A'
	lxdata 2, ' '
	lxdata 2, 'A'
	lxdata 2, 'N'
	lxdata 2, 'D'
	lxdata 2, ' '
	lxdata 2, 'K'
	lxdata 2, 'S'
	lxdata 2, 'U'
	lxdata 2, 'S'
	lxdata 2, 'H'
	lxdata 2, 'A'
	lxdata 2, '!'

	lcd_tx 0, 4, buffer_spi_cmd
	lcd_tx 1, 17, buffer_spi_disp
; главный цикл
vec_start:
	
    rjmp vec_start

; функция задержки
; -> CNH:CNL = N[tics] = (T[us] * 16[tics/us] - 12) / 4
delay_us:			; 4
	sbiw CNL, 1		; 2
	brne delay_us	; 2 if z!=0 (1 if z==0)
	nop				; 1 - компенсация brne при выходе из цикла
	nop				; 1 - два следующих 'nop' компенсируют кратность 4
	nop				; 1  ,что бы числа получались ровные! без дробных частей
	ret				; 4

; функция отправки комманды или данных
; -> XH:HL - указатель на массив
; -> CNH:CNL - указатель количества байт (данных или команд)
; -> ACL - указывает команда или данные (ACL - 0 inst, 1 data)
; -> ACH - временный регистр
spi_trx:
	; посылка из 3-х байт 0b11111{RW}{RS}0 0b{4bit HIGH DATA}0000 0b{4bit LOW DATA}0000 {RW = 0 write, 1 read} {RS = 0 inst, 1 data}
	; отправка первого байта
	; разрешить передачу
	uin ACH, PORTB
	sbr ACH, 1<<SS			; установка /SS -> HIGH
	uout PORTB, ACH
loop0:
	ldi ACH, 0b11111000		; write instr
	sbrc ACL, 0
	ldi ACH, 0b11111010		; write data
	uout SPDR, ACH
wait1:
	uin ACH, SPSR
	sbrs ACH, SPIF
	rjmp wait1
	; отправка второго байта
	ld ACH, X
	andi ACH, 0b11110000
	uout SPDR, ACH
wait2:
	uin ACH, SPSR
	sbrs ACH, SPIF
	rjmp wait2
	; отправка третьего байта
	ld ACH, X+
	swap ACH
	andi ACH, 0b11110000
	uout SPDR, ACH
wait3:
	uin ACH, SPSR
	sbrs ACH, SPIF
	rjmp wait3
	;задержка после отправки команды
	push CNH
	push CNL
	ld CNH, X+
	ld CNL, X+
	call delay_us
	pop CNL
	pop CNH
	; отсчет команд/данных в буфере
	sbiw CNL, 1
	brne loop0
	; завершить передачу
	uin ACH, PORTB
	cbr ACH, 1<<SS			; установка /SS -> LOW
	uout PORTB, ACH
	ret
