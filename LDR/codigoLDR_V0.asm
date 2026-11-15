;*******************************************************************************
; @brief        ANEXO B - FIRMWARE DEL SEP.
;
; @brief        Descripción general del funcionamiento del firmware del SEP.
;
; @details      Módulo Sensor de Luz (LDR) integrado con Timer0.
;               Mide la luminosidad ambiental cada 1 segundo (50 ms x 20)
;               utilizando el canal analógico AN1 (RA1) del PIC16F887.
; 
; @author       Gx_TPI_ED2
;
; @date         DIA/MES/AÑO
;
; @version      1.0
;*******************************************************************************
    
;===============================================================================
; DIRECTIVAS DE INCLUSIÓN
;===============================================================================  
LIST P=16F887
#include "p16f887.inc"
    
;===============================================================================
; CONFIGURACIÓN GENERAL DEL MCU
;===============================================================================
    __CONFIG _CONFIG1, _XT_OSC & _WDTE_OFF & _MCLRE_ON & _LVP_OFF
    
;===============================================================================
; DEFINICIÓN DE CONSTANTES
;===============================================================================                
VALUE_OFFSET_TMR0      EQU .60
VALUE_COUNTER_MAX_TMR0 EQU .20

;===============================================================================
; DEFINICIÓN DE VARIABLES
;=============================================================================== 
    CBLOCK 0x70
        W_TEMP          ; Guardado temporal de W en ISR
        STATUS_TEMP     ; Guardado temporal de STATUS en ISR
    ENDC

    CBLOCK 0x20
        OFFSET_TMR0         ; Valor de recarga para ~50 ms
        COUNTER_MAX_TMR0    ; Contador regresivo de desbordes (20 x 50 ms = 1 s)
        LDR_VAL             ; Almacena los 8 bits de lectura del LDR (ADRESH)
    ENDC

;===============================================================================
; DECLARACIÓN DE MACROS PARA CONFIGURACIÓN DE REGISTROS
;===============================================================================            
CFG_ADC_LDR MACRO
    BANKSEL ANSEL
    BSF     ANSEL, 1        ; Habilita AN1 (RA1) como Entrada Analógica (LDR)

    BANKSEL TRISA
    BSF     TRISA, 1        ; Configura pin RA1 estrictamente como Entrada

    ; ADCON1: Justificado a la izquierda (ADFM=0), Vref- = VSS, Vref+ = RA3 (2.54V)
    BANKSEL ADCON1
    MOVLW   b'00010000'
    MOVWF   ADCON1

    ; ADCON0: Clock Fosc/8, Selección Canal AN1 (CHS=0001), Módulo ADC Encendido (ADON=1)
    BANKSEL ADCON0
    MOVLW   b'01000101'
    MOVWF   ADCON0
ENDM

CFG_TMR0 MACRO             ; TMR0 para Sensor
    BANKSEL OPTION_REG
    MOVLW   b'00000111'
    MOVWF   OPTION_REG      ; Prescaler TMR0, 1:256
    
    BANKSEL TMR0
    MOVLW   VALUE_OFFSET_TMR0
    MOVWF   OFFSET_TMR0
    MOVWF   TMR0
    
    MOVLW   VALUE_COUNTER_MAX_TMR0
    MOVWF   COUNTER_MAX_TMR0
ENDM

CFG_ISR MACRO              ; Interrupciones
    BANKSEL PIR1
    BCF     PIR1, ADIF      ; Limpia bandera de interrupción por ADC
    BANKSEL INTCON
    BCF     INTCON, T0IF    ; Limpia bandera de interrupción por Timer0

    BANKSEL PIE1
    BSF     PIE1, ADIE      ; Habilita interrupción por ADC
    BSF     PIE1, TMR1IE    ; Habilita interrupción por TIMER1
    BANKSEL INTCON
    BSF     INTCON, T0IE    ; Habilita interrupción por TIMER0
    BSF     INTCON, PEIE    ; Habilita interrupción por periféricos
    BSF     INTCON, GIE     ; Habilita interrupciones globales
ENDM

;===============================================================================
; INICIALIZACIÓN DEL MCU (CÓDIGO ABSOLUTO)
;===============================================================================    
    ORG     0x00        ; Vector de Reset
    GOTO    INICIO      ; Salto al inicio del programa principal
    ORG     0x04        ; Vector de Interrupción
    GOTO    ISR_INICIO  ; Salto a Rutina de Servicio de Interrupción
    ORG     0x05        ; Ubicación Programa Principal en la memoria 

;===============================================================================
; INICIALIZACIÓN DE MACROS PARA CONFIGURACIÓN DE REGISTROS
;=============================================================================== 
INICIO      ; -----Inicialización de Macros-------
    CFG_ADC_LDR
    CFG_TMR0
    CFG_ISR

;===============================================================================
; INICIO PROGRAMA PRINCIPAL
;===============================================================================        
MAIN_LOOP  
    GOTO    MAIN_LOOP
  
;===============================================================================
; INICIALIZACIÓN DE RUTINAS DE SERVICIO DE INTERRUPCIÓN
;===============================================================================        
ISR_INICIO      
    ;----------Guardado de Contexto----------
    MOVWF   W_TEMP
    SWAPF   STATUS, W
    MOVWF   STATUS_TEMP

    ;----------------------------------------
    ;-----Identificación de Interrupción----- 
    BANKSEL INTCON
    BTFSC   INTCON, T0IF    ; Fue el Timer0?
    GOTO    ISR_TMR0

    BANKSEL PIR1
    BTFSC   PIR1, ADIF      ; Fue la conversión del ADC finalizada?
    GOTO    ISR_ADC_LDR

    GOTO    ISR_FIN
    ;----------------------------------------   
    
;===============================================================================
; FINALIZACIÓN DE RUTINAS DE SERVICIO DE INTERRUPCIÓN
;===============================================================================        
ISR_FIN     
    ;--------Restauración de Contexto--------        
    SWAPF   STATUS_TEMP, W
    MOVWF   STATUS
    SWAPF   W_TEMP, F
    SWAPF   W_TEMP, W
    RETFIE
    ;---------------------------------------- 
 
;===============================================================================
; SUBRUTINAS
;===============================================================================        
;*******************************************************************************
; @brief    Rutina de Servicio de Interrupción para el Timer0.
;           
; @details  Recarga el registro TMR0 para mantener la base de 50 ms. Decrementa
;           el contador de desbordes. Al transcurrir 1 segundo completo (20 
;           desbordes), dispara la conversión analógico-digital (GO/DONE) del LDR.
;******************************************************************************* 
ISR_TMR0
    BANKSEL INTCON
    BCF     INTCON, T0IF    ; Limpia la bandera del Timer0

    BANKSEL TMR0
    MOVF    OFFSET_TMR0, W
    MOVWF   TMR0            ; Recarga TMR0 (.60)

    DECFSZ  COUNTER_MAX_TMR0, F ; ¿Transcurrió 1 segundo (20 desbordes)?
    GOTO    ISR_FIN         ; Si aún no, sale de la ISR

    ; Si pasó 1 segundo: reiniciar contador y disparar ADC del LDR
    MOVLW   VALUE_COUNTER_MAX_TMR0
    MOVWF   COUNTER_MAX_TMR0

    BANKSEL ADCON0
    BSF     ADCON0, GO      ; Disparador de inicio de conversión ADC
    GOTO    ISR_FIN

;*******************************************************************************
; @brief    Rutina de Servicio de Interrupción para el ADC (LDR).
;           
; @details  Se ejecuta automáticamente al finalizar la conversión analógico-digital.
;           Limpia la bandera ADIF y almacena los 8 bits más significativos 
;           del valor de luminosidad (registro ADRESH) en la variable LDR_VAL.
;******************************************************************************* 
ISR_ADC_LDR
    BANKSEL PIR1
    BCF     PIR1, ADIF      ; Limpia la bandera del ADC

    BANKSEL ADRESH
    MOVF    ADRESH, W
    MOVWF   LDR_VAL         ; Almacena los 8 bits de lectura del LDR

    GOTO    ISR_FIN

;===============================================================================        
    END
;===============================================================================