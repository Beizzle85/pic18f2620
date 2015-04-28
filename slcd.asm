        LIST
;*******************************************************************************
; tinyRTX Filename: slcd.asm (System Liquid Crystal Display services)
;
; Copyright 2014 Sycamore Software, Inc.  ** www.tinyRTX.com **
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
; Revision history:
;   23Oct03 SHiggins@tinyRTX.com Created from scratch.
;   29Jul14 SHiggins@tinyRTX.com Changed SLCD_ReadByte to macro to save stack.
;   13Aug14 SHiggins@tinyRTX.com Converted from PIC16877 to PIC18F452.
;   27Apr15 Stephen_Higgins@KairosAutonomi.com
;                                Build minimal slcd.asm to hold SLCD vars and defines.
;
;*******************************************************************************
;
        errorlevel -302 
        #include    <p18f2620.inc>
;
;*******************************************************************************
;
; SLCD defines.
;
#define     SLCD_BUFFER_LINE_SIZE   0x10
;
; SLCD service variables.
;
; System Liquid Crystal Display variables.
;
SLCD_UdataSec       UDATA
;
        GLOBAL  SLCD_BufferLine1
SLCD_BufferLine1    res     SLCD_BUFFER_LINE_SIZE
        GLOBAL  SLCD_BufferLine2
SLCD_BufferLine2    res     SLCD_BUFFER_LINE_SIZE
;
        end
