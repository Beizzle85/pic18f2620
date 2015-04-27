        LIST
;*******************************************************************************
; tinyRTX Filename: ssio.asm (System Serial I/O communication services)
;             Assumes USART module is available on chip.
;
; Copyright 2015 Sycamore Software, Inc.  ** www.tinyRTX.com **
; Distributed under the terms of the GNU Lesser General Purpose License v3
;
; This file is part of tinyRTX. tinyRTX is free software: you can redistribute
; it and/or modify it under the terms of the GNU Lesser General Public License
; version 3 as published by the Free Software Foundation.
;
; tinyRTX is distributed in the hope that it will be useful, but WITHOUT ANY
; WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
; A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for more
; details.
;
; You should have received a copy of the GNU Lesser General Public License
; (filename copying.lesser.txt) and the GNU General Public License (filename
; copying.txt) along with tinyRTX.  If not, see <http://www.gnu.org/licenses/>.
;
; AS THIS SOFTWARE WAS DERIVED FROM SOFTWARE WRITTEN BY MICROCHIP, THIS LICENSE IS
; SUBORDINATE TO THE RESTRICTIONS IMPOSED BY THE ORIGINAL MICROCHIP TECHNOLOGIES
; LICENSE INCLUDED BELOW IN ITS ENTIRETY.
;
; Revision history:
;   16Apr15  Stephen_Higgins@KairosAutonomi.com Modified from p18_tiri.asm from
;               Mike Garbutt at Microchip Technology Inc. All the interrupt discovery
;               was ripped out as tinyRTX already does that in SISD.  All the
;               "application loop" code was ripped out as that is handled by SRTX,
;               and the copy RX to TX action upon detecting <CR> became a tinyRTX user task.
;               The old GetData was rewritten to schedule that user task.
;               Also the high/low interrupt priorities replaced by non-prioritized ints.
;               Lots of banksel directives added, as now interfacing with code and variables 
;               that are not necessarily local. 
;
;*******************************************************************************
;
        errorlevel +302 
        #include    <p18f2620.inc>
        #include    <srtx.inc>
;       #include    <si2cuser.inc>
        #include    <susr.inc>
;
;=============================================================================
; Software License Agreement
;
; The software supplied herewith by Microchip Technology Incorporated 
; (the "Company") for its PICmicro® Microcontroller is intended and 
; supplied to you, the Company’s customer, for use solely and 
; exclusively on Microchip PICmicro Microcontroller products. The 
; software is owned by the Company and/or its supplier, and is 
; protected under applicable copyright laws. All rights are reserved. 
; Any use in violation of the foregoing restrictions may subject the 
; user to criminal sanctions under applicable laws, as well as to 
; civil liability for the breach of the terms and conditions of this 
; license.
;
; THIS SOFTWARE IS PROVIDED IN AN "AS IS" CONDITION. NO WARRANTIES, 
; WHETHER EXPRESS, IMPLIED OR STATUTORY, INCLUDING, BUT NOT LIMITED 
; TO, IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A 
; PARTICULAR PURPOSE APPLY TO THIS SOFTWARE. THE COMPANY SHALL NOT, 
; IN ANY CIRCUMSTANCES, BE LIABLE FOR SPECIAL, INCIDENTAL OR 
; CONSEQUENTIAL DAMAGES, FOR ANY REASON WHATSOEVER.
;
;=============================================================================
;   Filename:   p18_tiri.asm
;=============================================================================
;   Author:     Mike Garbutt
;   Company:    Microchip Technology Inc.
;   Revision:   1.00
;   Date:       August 6, 2002
;   Assembled using MPASMWIN V3.20
;=============================================================================
;   Include Files:  p18f452.inc V1.3
;=============================================================================
;   PIC18XXX USART example code for with transmit and receive interrupts.
;   Received data is put into a buffer, called RxBuffer. When a carriage
;   return <CR> is received, the received data in RxBuffer is copied into
;   another buffer, TxBuffer. The data in TxBuffer is then transmitted.
;   Receive uses high priority interrupts, transmit uses low priority.
;=============================================================================
;
        radix   dec             ; Default radix for constants is decimal.
;
;Bit Definitions
;
#define SSIO_TxBufFull  0       ;bit indicates Tx buffer is full
#define SSIO_TxBufEmpty 1       ;bit indicates Tx buffer is empty
#define SSIO_RxBufFull  2       ;bit indicates Rx buffer is full
#define SSIO_RxBufEmpty 3       ;bit indicates Rx buffer is empty
#define SSIO_ReceivedCR 4       ;bit indicates <CR> character received
;
;*******************************************************************************
;
; SSIO service variables, receive and transmit buffers.
;
SSIO_UdataSec   UDATA       ; Currently this whole data section crammed into 
                            ; one 256 RAM bank.  Code ASSUMES this is so, as it
                            ; only changes bank first time any of these vars used.
;
#define SSIO_TX_BUF_LEN 0x70    ; Define transmit buffer size.
#define SSIO_RX_BUF_LEN 0x70    ; Define receive buffer size.
;
SSIO_Flags          res     1       ;byte for indicator flag bits
SSIO_TempRxData     res     1       ;temporary data in Rx buffer routines 
SSIO_TempTxData     res     1       ;temporary data in Tx buffer routines 
SSIO_TxStartPtrH    res     1       ;pointer to start of data in Tx buffer
SSIO_TxStartPtrL    res     1       ;pointer to start of data in Tx buffer
SSIO_TxEndPtrH      res     1       ;pointer to end of data in Tx buffer
SSIO_TxEndPtrL      res     1       ;pointer to end of data in Tx buffer
SSIO_RxStartPtrH    res     1       ;pointer to start of data in Rx buffer
SSIO_RxStartPtrL    res     1       ;pointer to start of data in Rx buffer
SSIO_RxEndPtrH      res     1       ;pointer to end of data in Rx buffer
SSIO_RxEndPtrL      res     1       ;pointer to end of data in Rx buffer
SSIO_VarsSpace1     res     5       ;Reserve space so buffer aligns on boundary
SSIO_TxBuffer       res     SSIO_TX_BUF_LEN     ;Tx buffer for data to transmit
SSIO_VarsSpace2     res     0x10    ;Reserve space so buffer aligns on boundary
SSIO_RxBuffer       res     SSIO_RX_BUF_LEN     ;Rx buffer for data to receive
;
;*******************************************************************************
;
; SSIO interrupt handling code.
;
SSIO_CodeSec    CODE
;
;*******************************************************************************
;
;   Initialize SSIO internal flags.  Call this before SSIO_InitTxBuffer and SSIO_InitRxBuffer.
;
        GLOBAL  SSIO_InitFlags
SSIO_InitFlags
;
        banksel SSIO_Flags      
        clrf    SSIO_Flags      ;clear all flags
        return
;
;*******************************************************************************
;
;   Initialize transmit buffer.
;
        GLOBAL  SSIO_InitTxBuffer
SSIO_InitTxBuffer
;
        banksel SSIO_TxBuffer      
        movlw   HIGH SSIO_TxBuffer          ;take high address of transmit buffer
        movwf   SSIO_TxStartPtrH            ;and place in transmit start pointer
        movwf   SSIO_TxEndPtrH              ;and place in transmit end pointer
;
        movlw   LOW SSIO_TxBuffer           ;take low address of transmit buffer
        movwf   SSIO_TxStartPtrL            ;and place in transmit start pointer
        movwf   SSIO_TxEndPtrL              ;and place in transmit end pointer
;
        bcf     SSIO_Flags, SSIO_TxBufFull  ;indicate Tx buffer is not full
        bsf     SSIO_Flags, SSIO_TxBufEmpty ;indicate Tx buffer is empty
        return
;
;*******************************************************************************
;
;   Initialize receive buffer.
;
        GLOBAL  SSIO_InitRxBuffer
SSIO_InitRxBuffer
;
        banksel SSIO_RxBuffer      
        movlw   HIGH SSIO_RxBuffer          ;take high address of receive buffer
        movwf   SSIO_RxStartPtrH            ;and place in receive start pointer
        movwf   SSIO_RxEndPtrH              ;and place in receive end pointer
;
        movlw   LOW SSIO_RxBuffer           ;take low address of receive buffer
        movwf   SSIO_RxStartPtrL            ;and place in receive start pointer
        movwf   SSIO_RxEndPtrL              ;and place in receive end pointer
;
        bcf     SSIO_Flags, SSIO_RxBufFull  ;indicate Rx buffer is not full
        bsf     SSIO_Flags, SSIO_RxBufEmpty ;indicate Rx buffer is empty
        return
;
;------------------------------------
;Read data from the transmit buffer and put into transmit register.
;
        GLOBAL  SSIO_PutByteIntoTxHW
SSIO_PutByteIntoTxHW
;
        banksel SSIO_Flags
        btfss   SSIO_Flags, SSIO_TxBufEmpty ;check if transmit buffer is empty
        bra     SSIO_PutByteIntoTxHW1       ;if not then go transmit
;
        bcf     PIE1,TXIE                   ;else disable Tx interrupt...
        bra     SSIO_PutByteIntoTxHW_Exit   ; and leave this routine.
;
SSIO_PutByteIntoTxHW1
        rcall   SSIO_GetByteTxBuffer        ;get data from transmit buffer
        movwf   TXREG                       ;and transmit
;
SSIO_PutByteIntoTxHW_Exit
        return
;
;*******************************************************************************
;
;   Get received data from USART data register and write it into receive buffer.
;
        GLOBAL  SSIO_GetByteFromRxHW
SSIO_GetByteFromRxHW
;
;   Check for serial errors and handle them if found.
;
        banksel SSIO_Flags
        btfsc   RCSTA, OERR                     ;if overrun error
        bra     SSIO_GetByteFromRxHW_ErrOERR    ;then go handle error
;
        btfsc   RCSTA, FERR                     ;if framing error
        bra     SSIO_GetByteFromRxHW_ErrFERR    ;then go handle error
;
        btfsc   SSIO_Flags, SSIO_RxBufFull      ;if buffer full
        bra     SSIO_GetByteFromRxHW_ErrRxOver  ;then go handle error
;
        bra     SSIO_GetByteFromRxHW_DataGood   ; Otherwise no errors so get good data.
;
;   Error handling.
;
;error because OERR overrun error bit is set
;can do special error handling here - this code simply clears and continues
;
SSIO_GetByteFromRxHW_ErrOERR
        bcf     RCSTA, CREN                     ;reset the receiver logic
        bsf     RCSTA, CREN                     ;enable reception again
        bra     SSIO_GetByteFromRxHW_Exit
;
;error because FERR framing error bit is set
;can do special error handling here - this code simply clears and continues
;
SSIO_GetByteFromRxHW_ErrFERR
        movf    RCREG, W                        ;discard received data that has error
        bra     SSIO_GetByteFromRxHW_Exit
;
;error because receive buffer is full
;can do special error handling here - this code checks and discards the data
;
SSIO_GetByteFromRxHW_ErrRxOver
        movf    RCREG, W                        ;discard received data
        xorlw   0x0d                            ;but compare with <CR>      
        btfsc   STATUS,Z                        ;check if the same
        bsf     SSIO_Flags, SSIO_ReceivedCR     ;indicate <CR> character received
;
        bra     SSIO_GetByteFromRxHW_CheckCR    ; We could just bra SSIO_GetByteFromRxHW_SchedTask
                                                ; but maybe ReceivedCR will come in handy.
;
;   Put good data into receive buffer, schedule task if <CR> found.
;   THIS WILL HAVE TO BE RE-EXAMINED FOR MORE GENERIC WAY OF TRIGGERING USER TASK
;   BECAUSE <CR> IS NOT A UNIVERSAL DEMARCATION OF COMPLETED MESSAGE.
;
SSIO_GetByteFromRxHW_DataGood
        movf    RCREG, W                        ;get received data
        xorlw   0x0d                            ;compare with <CR>      
        btfsc   STATUS, Z                       ;check if the same
        bsf     SSIO_Flags, SSIO_ReceivedCR     ;indicate <CR> character received
;
        xorlw   0x0d                            ;change back to valid data
        rcall   SSIO_PutByteRxBuffer            ;and put in buffer
        banksel SSIO_Flags                      ; In case bank bits changed in subroutine.
;
;    If we find <CR> then schedule user task to process data.  Then interrupt can exit.
;    SRTX Dispatcher will find task scheduled and invoke SUSR_TaskSIO.
;
SSIO_GetByteFromRxHW_CheckCR
        btfss   SSIO_Flags, SSIO_ReceivedCR     ;indicates <CR> character received
        bra     SSIO_GetByteFromRxHW_Exit
        bcf     SSIO_Flags, SSIO_ReceivedCR     ;clear <CR> received indicator
;
;    Schedule user task SUSR_TaskSIO.
;
SSIO_GetByteFromRxHW_SchedTask
        banksel SRTX_Sched_Cnt_TaskSIO
        incfsz  SRTX_Sched_Cnt_TaskSIO, F       ; Increment task schedule count.
        goto    SSIO_GetByteFromRxHW_Exit       ; Task schedule count did not rollover.
        decf    SRTX_Sched_Cnt_TaskSIO, F       ; Max task schedule count.
;
SSIO_GetByteFromRxHW_Exit
        return
;
;*******************************************************************************
;
;   Add a byte (in WREG) to the end of the transmit buffer.
;
        GLOBAL  SSIO_PutByteTxBuffer
SSIO_PutByteTxBuffer
;
        bcf     PIE1, TXIE                          ;disable Tx interrupt to avoid conflict
;
        banksel SSIO_Flags      
        btfsc   SSIO_Flags, SSIO_TxBufFull          ;check if transmit buffer full
        bra     SSIO_PutByteTxBuffer_BufFull        ;go handle error if full
;
        movff   SSIO_TxEndPtrH, FSR0H               ;put EndPointer into FSR0
        movff   SSIO_TxEndPtrL, FSR0L               ;put EndPointer into FSR0
        movwf   POSTINC0                            ;copy data to buffer
;
;test if buffer pointer needs to wrap around to beginning of buffer memory
;
        movlw   HIGH (SSIO_TxBuffer+SSIO_TX_BUF_LEN)    ;get last address of buffer
        cpfseq  FSR0H                                   ;and compare with end pointer
        bra     SSIO_PutByteTxBuffer1                   ;skip low bytes if high bytes not equal
;
        movlw   LOW (SSIO_TxBuffer+SSIO_TX_BUF_LEN)     ;get last address of buffer
        cpfseq  FSR0L                                   ;and compare with end pointer
        bra     SSIO_PutByteTxBuffer1                   ;go save new pointer if at end
;
        lfsr    0, SSIO_TxBuffer                        ;point to beginning of buffer if at end
;
SSIO_PutByteTxBuffer1
        movff   FSR0H, SSIO_TxEndPtrH        ;save new EndPointer high byte
        movff   FSR0L, SSIO_TxEndPtrL        ;save new EndPointer low byte
;
;test if buffer is full
;
        movf    SSIO_TxStartPtrH, W         ;get start pointer
        cpfseq  SSIO_TxEndPtrH              ;and compare with end pointer
        bra     SSIO_PutByteTxBuffer2       ;skip low bytes if high bytes not equal
;
        movf    SSIO_TxStartPtrL, W         ;get start pointer
        cpfseq  SSIO_TxEndPtrL              ;and compare with end pointer
;
        bra     SSIO_PutByteTxBuffer2
        bsf     SSIO_Flags, SSIO_TxBufFull  ;if same then indicate buffer full
;
SSIO_PutByteTxBuffer2
        bcf     SSIO_Flags, SSIO_TxBufEmpty ;Tx buffer cannot be empty
        bsf     PIE1, TXIE                  ;enable transmit interrupt
        return
;
;error because attempting to store new data and the buffer is full
;can do special error handling here - this code simply ignores the byte
;
SSIO_PutByteTxBuffer_BufFull
        bsf     PIE1, TXIE                  ;enable transmit interrupt
        return                              ;no save of data because buffer is full
;
;*******************************************************************************
;
;Add a byte (in WREG) to the end of the receive buffer.
;
        GLOBAL  SSIO_PutByteRxBuffer
SSIO_PutByteRxBuffer
;
; NOTE: no disabling of RX interrupt because this likely called from RX ISR.
;
        banksel SSIO_Flags
        btfsc   SSIO_Flags, SSIO_RxBufFull      ;check if receive buffer full
        bra     SSIO_PutByteRxBuffer_BufFull    ;go handle error if full
;
        movff   SSIO_RxEndPtrH, FSR0H           ;put EndPointer into FSR0
        movff   SSIO_RxEndPtrL, FSR0L           ;put EndPointer into FSR0
        movwf   POSTINC0                        ;copy data to buffer
;
;test if buffer pointer needs to wrap around to beginning of buffer memory

        movlw   HIGH (SSIO_RxBuffer+SSIO_RX_BUF_LEN)    ;get last address of buffer
        cpfseq  FSR0H                                   ;and compare with end pointer
        bra     SSIO_PutByteRxBuffer1                   ;skip low bytes if high bytes not equal
;
        movlw   LOW (SSIO_RxBuffer+SSIO_RX_BUF_LEN)     ;get last address of buffer
        cpfseq  FSR0L                                   ;and compare with end pointer
        bra     SSIO_PutByteRxBuffer1                   ;go save new pointer if not at end
;
        lfsr    0, SSIO_RxBuffer                        ;point to beginning of buffer if at end
;
SSIO_PutByteRxBuffer1
        movff   FSR0H, SSIO_RxEndPtrH       ;save new EndPointer high byte
        movff   FSR0L, SSIO_RxEndPtrL       ;save new EndPointer low byte
;
;test if buffer is full
;
        movf    SSIO_RxStartPtrH, W         ;get start pointer
        cpfseq  SSIO_RxEndPtrH              ;and compare with end pointer
        bra     SSIO_PutByteRxBuffer2       ;skip low bytes if high bytes not equal
;
        movf    SSIO_RxStartPtrL, W         ;get start pointer
        cpfseq  SSIO_RxEndPtrL              ;and compare with end pointer
        bra     SSIO_PutByteRxBuffer2
;
        bsf     SSIO_Flags, SSIO_RxBufFull  ;if same then indicate buffer full
;
SSIO_PutByteRxBuffer2
        bcf     SSIO_Flags, SSIO_RxBufEmpty ;Rx buffer cannot be empty
        return
;
;error because attempting to store new data and the buffer is full
;can do special error handling here - this code simply ignores the byte
;
SSIO_PutByteRxBuffer_BufFull
        return                              ;no save of data because buffer is full
;
;*******************************************************************************
;
;   Remove and return (in WREG) the byte at the start of the transmit buffer.
;
        GLOBAL  SSIO_GetByteTxBuffer
SSIO_GetByteTxBuffer
;   
        banksel SSIO_Flags
        btfsc   SSIO_Flags, SSIO_TxBufEmpty             ;check if transmit buffer empty
        bra     SSIO_GetByteTxBuffer_BufEmpty           ;go handle error if empty
;
        movff   SSIO_TxStartPtrH, FSR0H                 ;put StartPointer into FSR0
        movff   SSIO_TxStartPtrL, FSR0L                 ;put StartPointer into FSR0
        movff   POSTINC0, SSIO_TempTxData               ;save data from buffer
;
;test if buffer pointer needs to wrap around to beginning of buffer memory

        movlw   HIGH (SSIO_TxBuffer+SSIO_TX_BUF_LEN)    ;get last address of buffer
        cpfseq  FSR0H                                   ;and compare with start pointer
        bra     SSIO_GetByteTxBuffer1                   ;skip low bytes if high bytes not equal
;
        movlw   LOW (SSIO_TxBuffer+SSIO_TX_BUF_LEN)     ;get last address of buffer
        cpfseq  FSR0L                                   ;and compare with start pointer
        bra     SSIO_GetByteTxBuffer1                   ;go save new pointer if at end
;
        lfsr    0, SSIO_TxBuffer                        ;point to beginning of buffer if at end
;
SSIO_GetByteTxBuffer1
        movff   FSR0H,SSIO_TxStartPtrH                  ;save new StartPointer value
        movff   FSR0L, SSIO_TxStartPtrL                 ;save new StartPointer value
;
;test if buffer is now empty
;
        movf    SSIO_TxEndPtrH, W               ;get end pointer
        cpfseq  SSIO_TxStartPtrH                ;and compare with start pointer
        bra     SSIO_GetByteTxBuffer2           ;skip low bytes if high bytes not equal
;
        movf    SSIO_TxEndPtrL, W               ;get end pointer
        cpfseq  SSIO_TxStartPtrL                ;and compare with start pointer
        bra     SSIO_GetByteTxBuffer2
;
        bsf     SSIO_Flags, SSIO_TxBufEmpty     ;if same then indicate buffer empty
;
SSIO_GetByteTxBuffer2
        bcf     SSIO_Flags, SSIO_TxBufFull      ;Tx buffer cannot be full
        movf    SSIO_TempTxData, W              ;restore data from buffer
        return
;
;error because attempting to read data from an empty buffer
;can do special error handling here - this code simply returns zero
;
SSIO_GetByteTxBuffer_BufEmpty
        retlw   0       ;buffer empty, return zero
;
;*******************************************************************************
;
;Remove and return (in WREG) the byte at the start of the receive buffer.
;
        GLOBAL  SSIO_GetByteRxBuffer
SSIO_GetByteRxBuffer
;
        banksel SSIO_Flags
        bcf     PIE1, RCIE                      ;disable Rx interrupt to avoid conflict
        btfsc   SSIO_Flags, SSIO_RxBufEmpty     ;check if receive buffer empty
        bra     SSIO_GetByteRxBuffer_BufEmpty   ;go handle error if empty
;
        movff   SSIO_RxStartPtrH, FSR0H         ;put StartPointer into FSR0
        movff   SSIO_RxStartPtrL, FSR0L         ;put StartPointer into FSR0
        movff   POSTINC0, SSIO_TempRxData       ;save data from buffer
;
;test if buffer pointer needs to wrap around to beginning of buffer memory
;
        movlw   HIGH (SSIO_RxBuffer+SSIO_RX_BUF_LEN)    ;get last address of buffer
        cpfseq  FSR0H                                   ;and compare with start pointer
        bra     SSIO_GetByteRxBuffer1                   ;skip low bytes if high bytes not equal
;
        movlw   LOW (SSIO_RxBuffer+SSIO_RX_BUF_LEN)     ;get last address of buffer
        cpfseq  FSR0L                                   ;and compare with start pointer
        bra     SSIO_GetByteRxBuffer1                   ;go save new pointer if at end
;
        lfsr    0, SSIO_RxBuffer                        ;point to beginning of buffer if at end
;
SSIO_GetByteRxBuffer1
        movff   FSR0H, SSIO_RxStartPtrH     ;save new StartPointer value
        movff   FSR0L, SSIO_RxStartPtrL     ;save new StartPointer value
;
;test if buffer is now empty
;
        movf    SSIO_RxEndPtrH, W           ;get end pointer
        cpfseq  SSIO_RxStartPtrH            ;and compare with start pointer
        bra     SSIO_GetByteRxBuffer2       ;skip low bytes if high bytes not equal
;
        movf    SSIO_RxEndPtrL, W           ;get end pointer
        cpfseq  SSIO_RxStartPtrL            ; and compare with start pointer
        bra     SSIO_GetByteRxBuffer2
;
        bsf     SSIO_Flags, SSIO_RxBufEmpty ;if same then indicate buffer empty
;
SSIO_GetByteRxBuffer2
        bcf     SSIO_Flags,SSIO_RxBufFull   ;Rx buffer cannot be full
        movf    SSIO_TempRxData, W          ;restore data from buffer
        bsf     PIE1, RCIE                  ;enable receive interrupt
        return
;
;error because attempting to read data from an empty buffer
;can do special error handling here - this code simply returns zero
;
SSIO_GetByteRxBuffer_BufEmpty
        bsf     PIE1, RCIE                  ;enable receive interrupt
        retlw   0                           ;buffer empty, return zero
        end