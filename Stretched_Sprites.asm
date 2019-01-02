#import "helpers.asm"

.label border = $d020
.label background = $d021

.label cia1_interrupt_control_register = $dc0d
.label cia2_interrupt_control_register = $dd0d

.const VIC2 = $d000
.namespace sprites {
  .label positions = VIC2
  .label position_x_high_bits = VIC2 + 16
  .label enable_bits = VIC2 + 21
  .label vertical_stretch_bits = VIC2 + 23
  .label horizontal_stretch_bits = VIC2 + 29
  .label colors = VIC2 + 39
  .label pointers = screen + 1024 - 8
}

.const RASTER_LINE = 48
.const SPRITE_BITMAPS = 255-8

* = SPRITE_BITMAPS*64 "Sprites"
.import binary "numbers.bin"

:BasicUpstart2(main)
main:

  sei

  clear_screen(96)

	// Enable and prepare sprites
  lda #$ff
  sta sprites.enable_bits
  sta sprites.vertical_stretch_bits
  .for (var sprite_id = 0; sprite_id < 8; sprite_id++) {
    lda #SPRITE_BITMAPS + sprite_id
    sta sprites.pointers + sprite_id
    lda #WHITE
    sta sprites.colors + sprite_id
    lda #24+32*sprite_id
    sta sprites.positions + 0 + sprite_id * 2
    lda #51//+21*sprite_id
    sta sprites.positions + 1 + sprite_id * 2
  }

  lda $01
  and #%11111101
  sta $01

  lda #%01111111
  sta cia1_interrupt_control_register
  sta cia2_interrupt_control_register
  lda cia1_interrupt_control_register
  lda cia2_interrupt_control_register

  lda #%00000001
  sta vic2_interrupt_control_register
  sta vic2_interrupt_status_register
  :set_raster(RASTER_LINE)
  :mov16 #irq1 : $fffe

  cli

loop:
  jmp loop

// Notice that sprite0's y coordinate is BL51, so the first
// 24 pixels are loaded during it (consuming 5 cycles)
// that means it will first appear at GL52.
// The plan is to crunch GL52 and GL53.
irq1:
  sta atemp
  stx xtemp
  sty ytemp
  :stabilize_irq() // After 3rd cycle of GL50
  //:cycles(-3 + 63) // End of GL50 / Very start of BL51

  :cycles(60 + 63 -3 -40 -3-2*8) // End of BL51 / Very start of GL52

  // GL52
  :cycles(9)
  lda #0  // MC from 0 to 1
  sta sprites.vertical_stretch_bits // End of cycle 15 of GL52
  lda #$ff
  sta sprites.vertical_stretch_bits // End of cycle 21 of GL52
  :cycles(63 -21 -3-2*8) // End of GL52 / Very start of GL53

  // GL53
  :cycles(9)
  lda #0  // MC from 1 to 5
  sta sprites.vertical_stretch_bits // End of cycle 15 of GL53
  lda #$ff
  sta sprites.vertical_stretch_bits // End of cycle 21 of GL53
  :cycles(63 -21 -3-2*8) // End of GL53 / Very start of GL54

  jmp exiting_irq


exiting_irq:
  asl vic2_interrupt_status_register
  :set_raster(RASTER_LINE)
  :mov16 #irq1 : $fffe
  lda atemp: #$00
  ldx xtemp: #$00
  ldy ytemp: #$00
  rti

/*
 * Wait functions.
*/

// Waits 23 cycles minus 12 cycles for the caller's jsr and this function's rts.
wait_one_bad_line: //+6
  :cycles(-6+23-6) // 23-12
  rts //+6
wait_one_bad_line_minus_3: //+6
  :cycles(-6+23-3-6) //20-12
  rts //+6

// Waits 63 cycles minus 12 cycles for the caller's jsr and this function's rts.
wait_one_good_line: //+6
  :cycles(-6+63-6) // 63-12
  rts //+6

// Waits 63 cycles minus 12 cycles for the caller's jsr and this function's rts, and
// further minus 12 cycles for the caller's caller's jsr and corresponding rts.
// Basically this wait function is meant to be called from another wait function.
wait_one_good_line_minus_jsr_and_rts: //+6
  :cycles(-6-6+63-6-6) // 63-24
  rts //+6

// Waits 63 cycles minus 12 cycles for the caller's jsr and this function's rts, and
// further minus 12 cycles for the caller's caller's jsr and corresponding rts.
// Basically this wait function is meant to be called from another wait function.
wait_6_good_lines_minus_jsr_and_rts: //+6
  jsr wait_one_good_line // 1: 63-12+6+6 = 63
  jsr wait_one_good_line // 2: 63-12+6+6 = 63
  jsr wait_one_good_line // 3: 63-12+6+6 = 63
  jsr wait_one_good_line // 4: 63-12+6+6 = 63
  jsr wait_one_good_line // 5: 63-12+6+6 = 63
  // 6: Wait_one_good_line minus 24 cycles for 2 jsrs and 2 rtses.
  jsr wait_one_good_line_minus_jsr_and_rts // 6: 63-12
  rts //+6

// wait one entire row worth of cycles minus the 12 cycles to call this function.
wait_1_row_with_20_cycles_bad_line: //+6
  jsr wait_one_bad_line_minus_3 // 23-3 = 20
  jsr wait_6_good_lines_minus_jsr_and_rts // 63*5 + 63-12+6+6 = 63*6
  // Wait_one_good_line minus 24 cycles for 2 jsrs and 2 rtses.
  jsr wait_one_good_line_minus_jsr_and_rts // 63-12
  rts //+6

// wait two full rows worth of cycles minus the 12 cycles to call this function.
wait_2_rows_with_20_cycles_bad_lines: //+6
  jsr wait_1_row_with_20_cycles_bad_line
  jsr wait_one_bad_line_minus_3 // 23-3 = 20
  jsr wait_6_good_lines_minus_jsr_and_rts // 63*5 + 63-12+6+6 = 63*6
  // Wait_one_good_line minus 24 cycles for 2 jsrs and 2 rtses.
  jsr wait_one_good_line_minus_jsr_and_rts // 63-12
  rts //+6

wait_4_rows_with_20_cycles_bad_lines: //+6
  jsr wait_2_rows_with_20_cycles_bad_lines
  jsr wait_1_row_with_20_cycles_bad_line
  jsr wait_one_bad_line_minus_3 // 23-3 = 20
  jsr wait_6_good_lines_minus_jsr_and_rts // 63*5 + 63-12+6+6 = 63*6
  // Wait_one_good_line minus 24 cycles for 2 jsrs and 2 rtses.
  jsr wait_one_good_line_minus_jsr_and_rts // 63-12
  rts //+6

wait_8_rows_with_20_cycles_bad_lines: //+6
  jsr wait_4_rows_with_20_cycles_bad_lines
  jsr wait_2_rows_with_20_cycles_bad_lines
  jsr wait_1_row_with_20_cycles_bad_line
  jsr wait_one_bad_line_minus_3 // 23-3 = 20
  jsr wait_6_good_lines_minus_jsr_and_rts // 63*5 + 63-12+6+6 = 63*6
  // Wait_one_good_line minus 24 cycles for 2 jsrs and 2 rtses.
  jsr wait_one_good_line_minus_jsr_and_rts // 63-12
  rts //+6