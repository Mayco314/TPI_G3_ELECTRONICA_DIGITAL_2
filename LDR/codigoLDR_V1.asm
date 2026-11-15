;*******************************************************************************
; @brief        ANEXO B - FIRMWARE DEL SEP.
;
; @details      Módulo Sensor de Luz (LDR) + Timer0 + Luces Automáticas + BCD.
;               Pines asignados:
;               - LDR: AN1 (RA1)
;               - Luces: RC4 (Izquierda) y RC5 (Derecha)
;               - Vref+: RA3 (2.54V compartidos con Temp)
; 
; @author       Gx_TPI_ED2
; @version      2.0 (se agregan LEDS y conversion a BCD)
;*******************************************************************************
    
;===============================================================================
; DIRECTIVAS DE INCLUSIÓN
;===============================================================================  
    LIST P=16F887
    #include "p16f887.inc"
    
    __CONFIG _CONFIG1, _XT_OSC & _WDTE_OFF & _MCLRE_ON & _LVP_OFF
    
;===============================================================================
; DEFINICIÓN DE CONSTANTES
;===============================================================================                
VALUE_OFFSET_TMR0      EQU .60
VALUE_COUNTER_MAX_TMR0 EQU .20
UMBRAL_LUZ             EQU .100     ; Umbral para encender las luces (0-255)

;===============================================================================
; DEFINICIÓN DE VARIABLES
;=============================================================================== 
    CBLOCK 0x70
        W_TEMP          
        STATUS_TEMP     
    ENDC

    CBLOCK 0x20
        OFFSET_TMR0         
        COUNTER_MAX_TMR0    
        LDR_VAL             ; 8 bits crudos del LDR
        TEMP_ADC            ; Variable temporal para restas sucesivas
        BCD_CEN             ; Centenas (de LDR_VAL)
        BCD_DEC             ; Decenas (de LDR_VAL)
        BCD_UNI             ; Unidades (de LDR_VAL)
    ENDC

;===============================================================================
; DECLARACIÓN DE MACROS PARA CONFIGURACIÓN DE REGISTROS
;===============================================================================            
CFG_ADC_LDR MACRO
    BANKSEL ANSEL
    BSF     ANSEL, 1        ; Habilita AN1 (RA1) como Analógico

    BANKSEL TRISA
    BSF     TRISA, 1        ; TRISA1 = 1 (Entrada)

    ; ADCON1: Justificado a la izquierda, Vref- = VSS, Vref+ = RA3 (2.54V)
    BANKSEL ADCON1
    MOVLW   b'00010000'
    MOVWF   ADCON1

    ; ADCON0: Clock Fosc/8, Canal AN1, ADC Encendido
    BANKSEL ADCON0
    MOVLW   b'01000101'
    MOVWF   ADCON0
ENDM

CFG_LUCES_AUTO MACRO
    BANKSEL TRISC
    BCF     TRISC, 4        ; RC4 como salida (Luz Izquierda)
    BCF     TRISC, 5        ; RC5 como salida (Luz Derecha)
    
    BANKSEL PORTC
    BCF     PORTC, 4        ; Arrancan los leds apagados
    BCF     PORTC, 5
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
    BSF     PIE1, TMR1IE ; Habilita interrupción por TIMER1 (a modo preventivo)
    BANKSEL INTCON
    BSF     INTCON, T0IE    ; Habilita interrupción por TIMER0
    BSF     INTCON, PEIE    ; Habilita interrupción por periféricos
    BSF     INTCON, GIE     ; Habilita interrupciones globales
ENDM

;===============================================================================
; INICIALIZACIÓN DEL MCU (CÓDIGO ABSOLUTO)
;===============================================================================    
    ORG     0x00        ; Vector de Reset
    GOTO    INICIO       ; Salto al inicio del programa principal
    ORG     0x04        ; Vector de Interrupción
    GOTO    ISR_INICIO   ; Salto a Rutina de Servicio de Interrupción
    ORG     0x05        ; Ubicación Programa Principal en la memoria 
    
;===============================================================================
; INICIALIZACIÓN DE MACROS PARA CONFIGURACIÓN DE REGISTROS
;=============================================================================== 
INICIO      
    CFG_ADC_LDR
    CFG_LUCES_AUTO
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
    MOVWF   W_TEMP
    SWAPF   STATUS, W
    MOVWF   STATUS_TEMP

    BANKSEL INTCON
    BTFSC   INTCON, T0IF    ; Fue el Timer0?
    GOTO    ISR_TMR0

    BANKSEL PIR1
    BTFSC   PIR1, ADIF      ; Terminó el ADC?
    GOTO    ISR_ADC_LDR

    GOTO    ISR_FIN
    
;===============================================================================
; FINALIZACIÓN DE RUTINAS DE SERVICIO DE INTERRUPCIÓN
;===============================================================================    
ISR_FIN     
    SWAPF   STATUS_TEMP, W
    MOVWF   STATUS
    SWAPF   W_TEMP, F
    SWAPF   W_TEMP, W
    RETFIE
 
;===============================================================================
; SUBRUTINAS
;===============================================================================        
;*******************************************************************************
; @brief    Rutina de Servicio de Interrupción para el Timer0.
;           
; @details  Recarga el registro TMR0 para mantener la base de 50 ms. Decrementa
;           el contador de desbordes. Al transcurrir 1 segundo completo (20 
;        desbordes), dispara la conversión analógico-digital (GO/DONE) del LDR.
;******************************************************************************* 
ISR_TMR0
    BANKSEL INTCON
    BCF     INTCON, T0IF    ; Limpia bandera de Timer0

    BANKSEL TMR0
    MOVF    OFFSET_TMR0, W
    MOVWF   TMR0         ; Recarga TMR0 (.60)   

    DECFSZ  COUNTER_MAX_TMR0, F  ;Transcurrió 1 segundo (20 desbordes)?
    GOTO    ISR_FIN         ; Si aún no, sale de la ISR

    ; Si pasó 1 segundo: reiniciar contador y disparar ADC del LDR
    MOVLW   VALUE_COUNTER_MAX_TMR0
    MOVWF   COUNTER_MAX_TMR0

    BANKSEL ADCON0
    BSF     ADCON0, GO      ; Dispara conversión LDR
    GOTO    ISR_FIN

;*******************************************************************************
; @brief    Rutina de Servicio de Interrupción para el ADC (LDR).
;           
; @details  Se ejecuta automáticamente al finalizar la conversión.
;           Limpia la bandera ADIF y almacena los 8 bits más significativos 
;           del valor de luminosidad (registro ADRESH) en la variable LDR_VAL.
;*******************************************************************************    
ISR_ADC_LDR
    BANKSEL PIR1
    BCF     PIR1, ADIF      ; Limpia bandera del ADC

    BANKSEL ADRESH
    MOVF    ADRESH, W
    MOVWF   LDR_VAL        ; Guarda el valor crudo

    CALL    CONTROL_LUCES   ; Evalúa umbral de luz
    CALL    BIN_A_BCD     ; Convierte para la UART

    GOTO    ISR_FIN

;-------------------------------------------------------------------------------
; CONTROL DE LUCES
;-------------------------------------------------------------------------------
CONTROL_LUCES
    BANKSEL LDR_VAL
    MOVLW   UMBRAL_LUZ
    SUBWF   LDR_VAL, W      ; W = LDR_VAL - 100
    BTFSS   STATUS, C       ; Si C=0, el resultado fue negativo (Poca luz)
    GOTO    PRENDER_LUCES
    
    ; Hay luz suficiente (Apagar leds RC4 y RC5)
    BANKSEL PORTC
    BCF     PORTC, 4
    BCF     PORTC, 5
    RETURN

PRENDER_LUCES
    BANKSEL PORTC
    BSF     PORTC, 4
    BSF     PORTC, 5
    RETURN

;-------------------------------------------------------------------------------
; CONVERSIÓN BINARIO A BCD DESEMPAQUETADO
;-------------------------------------------------------------------------------
BIN_A_BCD
    BANKSEL BCD_CEN
    CLRF    BCD_CEN
    CLRF    BCD_DEC
    CLRF    BCD_UNI
    MOVF    LDR_VAL, W
    MOVWF   TEMP_ADC        ; Protegemos el valor original

CALCULA_CENTENAS
    MOVLW   d'100'
    SUBWF   TEMP_ADC, W     ; TEMP_ADC - 100
    BTFSS   STATUS, C       
    GOTO    CALCULA_DECENAS ; Dio negativo: ya no hay más centenas
    MOVWF   TEMP_ADC        ; Actualiza el sobrante
    INCF    BCD_CEN, F      ; Suma 1 a las centenas
    GOTO    CALCULA_CENTENAS

CALCULA_DECENAS
    MOVLW   d'10'
    SUBWF   TEMP_ADC, W     ; TEMP_ADC - 10
    BTFSS   STATUS, C       
    GOTO    CALCULA_UNIDADES; Dio negativo: pasamos a unidades
    MOVWF   TEMP_ADC        
    INCF    BCD_DEC, F      
    GOTO    CALCULA_DECENAS

CALCULA_UNIDADES
    MOVF    TEMP_ADC, W     ; El residuo final son las unidades
    MOVWF   BCD_UNI
    RETURN

;===============================================================================        
    END
;===============================================================================