;*******************************************************************************
; @brief       ANEXO B - FIRMWARE DEL SEP.
;
; @brief       Descripción general del funcionamiento del firmware del SEP.
;
; @details     Descripción especifica del funcionamiento del firmware del SEP.
;	       Se hace referencia a los SSE y a los periféricos del MCU.
; 
; @author      Gx_TPI_ED2
;
; @date        DIA/MES/AÑO
;
; @version     1.0
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
 ;Buzzer y Led conectados a sensor de temperatura
 #DEFINE LB_TEMP	PORTB,RB4
 ;Variables de displays
 #DEFINE CTRL_DSPL_UNI	PORTC,RC0
 #DEFINE CTRL_DSPL_DEC	PORTC,RC1
 #DEFINE CTRL_DSPL_CEN	PORTC,RC2
 ;Variables asociadas al TMR0 - Retardo 1s
 VALUE_OFFSET_TMR0	EQU .60	    ;Offset para 50 ms
 VALUE_COUNTER_MAX_TMR0 EQU .20	    ;1s/0.05s = 20 -> 20 desbordes para 1s
 ;Variables asociadas al TMR1 - Retardo 2.5ms
 VALUE_OFFSET_TMR1H	EQU 0xFE
 VALUE_OFFSET_TMR1L	EQU 0xC7    ;2.5ms -> 65223 -> 0xFEC7
;===============================================================================
; DEFINICIÓN DE VARIABLES
;=============================================================================== 
CBLOCK	0x70
    ;Variables para guardado de contexto
    W_TEMP	;0x70
    STATUS_TEMP	;0x71
ENDC

CBLOCK	0x20
    ;Variables de CNV_BCD
    VAL_UNI		;0x20
    VAL_DEC		;0x21
    VAL_CEN		;0x22
    REG_BCD		;0x23
    ;Variables para alarma de temperatura alta
    VAL_TEMP_MEDIR	;0x24
    DELAY1_Init		;0x25
    DELAY2_Init		;0x26
    DELAY3_Init		;0x27
    DELAY1		;0x28
    DELAY2		;0x29
    DELAY3		;0x30
    ;Variables de TMR0
    COUNTER_TMR0	;0x31
    COUNTER_MAX_TMR0	;0x32
    OFFSET_TMR0		;0x33
    ;Variables de displays
    DATA_DSPL_UNI	;0x34
    DATA_DSPL_DEC	;0x35
    DATA_DSPL_CEN	;0x36
    COUNTER_DSPL	;0x37
ENDC
;===============================================================================
; DECLARACIÓN DE MACROS PARA CONFIGURACIÓN DE REGISTROS
;===============================================================================            
CFG_CH_LM35_SENSOR MACRO    ;Sensor LM35 de temperatura
    BANKSEL ANSEL
    BSF	    ANSEL,ANS0
    BANKSEL TRISA
    BSF	    TRISA,TRISA0    ;RA0: Entrada Analógica
ENDM
 
CFG_ADC MACRO		    ;ADC
    BANKSEL ADCON1
    BSF	    ADCON1,VCFG0    ;Vref+ = 2.56V
    BCF	    ADCON1,VCFG1    ;Vref- = VSS (0V)
    BCF	    ADCON1,ADFM	    ;Justificado a la izquierda (8b en ADRESH)
    BANKSEL ADCON0
    BCF	    ADCON0,ADCS1    
    BSF	    ADCON0,ADCS0    ;Fclk = Fosc/8 (4mhz/8)
    BCF	    ADCON0,CHS0	    ;Canal 0 --> ANS0
    BSF	    ADCON0,ADON	    ;Permite uso del ADC
ENDM
 
CFG_TMR0 MACRO			;TMR0 para Sensor
   BANKSEL  OPTION_REG
   MOVLW    b'00000111'
   MOVWF    OPTION_REG		;Prescaler TMR0, 1:256
   BANKSEL  TMR0
   MOVLW    VALUE_OFFSET_TMR0
   MOVWF    OFFSET_TMR0
   MOVWF    TMR0		;Cargamos TMR0 con offset de 50ms
   MOVLW    VALUE_COUNTER_MAX_TMR0
   MOVWF    COUNTER_MAX_TMR0	;Contador de 20 desbordes
ENDM
   
CFG_TMR1 MACRO			;TMR1 para displays
   BANKSEL  T1CON
   MOVLW    b'00110001'	    ;TMR1 = ON, Prescaler 1:8
   MOVWF    T1CON
   BANKSEL  TMR1H
    MOVLW    VALUE_OFFSET_TMR1H
    MOVWF    TMR1H
    MOVLW    VALUE_OFFSET_TMR1L	   ;Cargan offset de 2,5ms
    MOVWF    TMR1L
ENDM
  
CFG_ISR MACRO		    ;Interrupciones
   BANKSEL  PIE1
   BCF	    PIE1,ADIF
   BSF	    PIE1,ADIE	    ;habilita interrupciones por ADC
   BSF	    PIE1,TMR1IE	    ;habilita interrupciones por TIMER1
   BANKSEL  INTCON
   BCF	    INTCON,T0IF
   BSF	    INTCON,T0IE	    ;habilita interrupciones por TIMER0
   BSF	    INTCON,PEIE	    ;habilita interrupciones por periféricos
   BSF	    INTCON,GIE	    ;habilita interrupciones globales
ENDM
 
CFG_LB MACRO		    ;Buzzer y Leds
   BANKSEL	ANSELH
   BCF		ANSELH,ANS11
   BANKSEL	TRISB
   BCF		TRISB,TRISB4    ;Salida digital RB4
   BANKSEL	PORTB
   BCF		LB_TEMP		;Apaga leds y buzzer
ENDM
   
CFG_DELAY MACRO			;Delay 40ms para alarma
   MOVLW	D'255'
   MOVWF	DELAY1_Init
   MOVLW	D'10'
   MOVWF	DELAY2_Init
   MOVLW	D'4'
   MOVWF	DELAY3_Init
ENDM
 
CFG_DSPL MACRO		    ;Displays
    BANKSEL	TRISD
    CLRF	TRISD
    CLRF	TRISC	    ;Puertos C y D como salidas digitales
    BANKSEL	PORTC
    MOVLW	b'11111111'
    MOVWF	PORTD	    ;apaga segmentos
    MOVWF	PORTC	    ;apaga displays
ENDM
    
DSPL_ALL_OFF MACRO	    ;Apaga todos los displays
    MOVLW   b'11111111'
    MOVWF   PORTC
    MOVWF   PORTD
ENDM
    
;===============================================================================
; INICIALIZACIÓN DEL MCU (CÓDIGO ABSOLUTO)
;===============================================================================    
    ORG     0x00	    ;Vector de Reset
    GOTO    INICIO	    ;Salto al inicio del programa principal
    ORG     0x04	    ;Vector de Interrupción
    GOTO    ISR_INICIO	    ;Salto al Rutina de Servicio de Interrupción
    ORG     0x05	    ;Ubicación Programa Principal en la memoria 

;===============================================================================
; INICIALIZACIÓN DE MACROS PARA CONFIGURACIÓN DE REGISTROS
;=============================================================================== 
INICIO      ;-----Inicialización de Macros-------
    CFG_CH_LM35_SENSOR
    CFG_DSPL
    CFG_LB
    CFG_TMR0
    CFG_TMR1
    CFG_ADC
    CFG_ISR
    CFG_DELAY

;===============================================================================
; INICIO PROGRAMA PRINCIPAL
;===============================================================================        
MAIN_LOOP	    ;Gestiona alarma de temperatura alta
    ;-------Temperatura >= 40°?---------
    MOVLW   .4
    MOVWF   VAL_TEMP_MEDIR
    MOVF    VAL_DEC,W
    SUBWF   VAL_TEMP_MEDIR,W
    BTFSC   STATUS,Z
    GOTO    TEMP_ALTA	    ;Temperatura >= 40°C
    GOTO    TEMP_BAJA	    ;Temperatura < 40°C

    TEMP_BAJA
    BCF	    LB_TEMP	;Apaga alarma
    GOTO    MAIN_LOOP

    TEMP_ALTA
    CALL    DELAY_3LOOP	    ;Delay 40ms
    BSF	    LB_TEMP	    ;Enciende alarma
    CALL    DELAY_3LOOP
    BCF	    LB_TEMP	    ;Apaga alarma
    GOTO    MAIN_LOOP
  
;===============================================================================
; INICIALIZACIÓN DE RUTINAS DE SERVICIO DE INTERRUPCIÓN
;===============================================================================        
ISR_INICIO      
    ;----------Guardado de Contexto----------
    MOVWF   W_TEMP
    SWAPF   STATUS,W
    MOVWF   STATUS_TEMP
    ;----------------------------------------
    ;-----Identificación de Interrupción-----
    BANKSEL INTCON
    BTFSC   INTCON,T0IF
    GOTO    ISR_TMR0
    BANKSEL PIR1
    BTFSC   PIR1,TMR1IF
    GOTO    ISR_TMR1
    BTFSC   PIR1,ADIF
    GOTO    ISR_ADC
    GOTO    ISR_FIN
    ;----------------------------------------   
    
;===============================================================================
; FINALIZACIÓN DE RUTINAS DE SERVICIO DE INTERRUPCIÓN
;===============================================================================        
ISR_FIN     
    ;--------Restauración de Contexto--------   
    SWAPF   STATUS_TEMP,W
    MOVWF   STATUS
    SWAPF   W_TEMP,F
    SWAPF   W_TEMP,W
    RETFIE
    ;---------------------------------------- 
 
;===============================================================================
; SUBRUTINAS
;===============================================================================		 

;*******************************************************************************
; @brief    Rutina de servicio de interrupción de TIMER0
;           
; @details  Identifica interrupción por TMR0 y realiza conversión por ADC
;******************************************************************************* 
 
 ISR_TMR0
    INCF    COUNTER_TMR0
    MOVF    COUNTER_MAX_TMR0,W
    SUBWF   COUNTER_TMR0,W
    BTFSS   STATUS,Z		;Chequea si hay que recargar TMR0
    GOTO    RELOAD_TMR0
    CLRF    COUNTER_TMR0	;Reinicia contador de desbordes
    GOTO    START_CONVERSION
    
    RELOAD_TMR0			;Recarga TMR0
	MOVF	OFFSET_TMR0,W
	MOVWF	TMR0
	GOTO	CLR_FLAG_TMR0
	
    START_CONVERSION		;Realiza conversión analógica_digital en AN0
	BANKSEL	ADCON0
	BSF	ADCON0,GO
	GOTO	RELOAD_TMR0
    
    CLR_FLAG_TMR0		;Baja bandera de interrupción por TMR0
	BANKSEL	INTCON
	BCF	INTCON,T0IF
	GOTO	ISR_FIN

;*******************************************************************************
; @brief    Rutina de servicio de interrupción de TIMER1
;           
; @details  Identifica interrupción por TMR1 y realiza la multiplexación de los
;	    displays (DSPL_CEN,DSPL_DEC,DSPL_UNI)
;******************************************************************************* 
ISR_TMR1
    CALL    RST_COUNTER_DSPL	   ;Setea contador de displays en '3'
    ;-------Verificación de Displays------
    MOVLW   .3    ;Display 3 (CEN)
    SUBWF   COUNTER_DSPL,W
    BTFSC   STATUS,Z
    CALL    UPDATE_DSPL_CEN
    MOVLW   .2    ;Display 2 (DEC)
    SUBWF   COUNTER_DSPL,W
    BTFSC   STATUS,Z
    CALL   UPDATE_DSPL_DEC
    MOVLW   .1	  ;Display 3 (UNI)
    SUBWF   COUNTER_DSPL,W
    BTFSC   STATUS,Z
    CALL    UPDATE_DSPL_UNI
    CALL    RST_COUNTER_DSPL
    GOTO    RELOAD_TMR1
;-------Actualización de Displays------
    UPDATE_DSPL_CEN	;Actualiza display centena (Display 1)
    DSPL_ALL_OFF
    MOVF    DATA_DSPL_CEN,W
    CALL    TABLE_DECO_DSPL_AC
    MOVWF   PORTD
    MOVF    COUNTER_DSPL,W
    CALL    TABLE_CTRL_DSPL_AC
    MOVWF   PORTC
    CALL    DECF_COUNTER_DSPL
    RETURN
    
    UPDATE_DSPL_DEC	;Actualiza display decena (Display 2)
    DSPL_ALL_OFF
    MOVF    DATA_DSPL_DEC,W
    CALL    TABLE_DECO_DSPL_AC
    MOVWF   PORTD
    MOVF    COUNTER_DSPL,W
    CALL    TABLE_CTRL_DSPL_AC
    MOVWF   PORTC
    CALL    DECF_COUNTER_DSPL
    RETURN
    
    UPDATE_DSPL_UNI	;Actualiza display unidad (Display 3)
    DSPL_ALL_OFF
    MOVF    DATA_DSPL_UNI,W
    CALL    TABLE_DECO_DSPL_AC
    MOVWF   PORTD
    MOVF    COUNTER_DSPL,W
    CALL    TABLE_CTRL_DSPL_AC
    MOVWF   PORTC
    CALL    DECF_COUNTER_DSPL
    RETURN
;--------Subrutinas de Multiplexación-------
   RST_COUNTER_DSPL	;Resetea contador de displays multiplexados
   MOVLW    .3
   MOVWF    COUNTER_DSPL
   RETURN
   
   DECF_COUNTER_DSPL	;Disminuye COUNTER_DSPL en 1
   DECF	    COUNTER_DSPL,F
   RETURN
;-----------Recarga y bajada de bandera de TIMER1-----------
   RELOAD_TMR1
   BANKSEL  TMR1H
   MOVLW    VALUE_OFFSET_TMR1H
   MOVWF    TMR1H
   MOVLW    VALUE_OFFSET_TMR1L
   MOVWF    TMR1L
   GOTO	    CLR_FLAG_TMR1
   
   CLR_FLAG_TMR1
   BANKSEL  PIR1
   BCF	    PIR1,TMR1IF
   GOTO	    ISR_FIN
	
;*******************************************************************************
; @brief    Rutina de servicio de interrupción para ADC
;           
; @details  Convierte variable binaria recibida por AN0 a un BCD desempaquetado,
;	    a través de CNV_BCD.
;	    Actualiza displays con los datos obtenidos. 
;*******************************************************************************	  
   ISR_ADC
	MOVF 	ADRESH,W
	MOVWF	REG_BCD	    ;REG_BCD = Valor obtenido en la conversión ADC
	CALL	CNV_BCD	    ;Conversión a BCD empaquetado de REG_BCD
	;Actualiza variables de los displays con valor de temperatura
	MOVF	VAL_UNI,W
	MOVWF	DATA_DSPL_UNI
	MOVF	VAL_DEC,W
	MOVWF	DATA_DSPL_DEC
	MOVF	VAL_CEN,W
	MOVWF	DATA_DSPL_CEN
	GOTO	CLR_FLAG_ADC
	
	CLR_FLAG_ADC	    ;Baja bandera de interrupción por ADC
	BANKSEL	PIR1
	BCF	PIR1,ADIF
	GOTO	ISR_FIN

;*******************************************************************************
; @brief    Delay 40ms para alarma de temperatura alta
;           
; @details  Gestiona delay de 40ms para la intermitencia de la alarma de
;	    temperatura alta
;*******************************************************************************
DELAY_3LOOP
	MOVFW   DELAY1_Init
	MOVWF   DELAY1
LOOP1	MOVFW   DELAY2_Init
	MOVWF   DELAY2
LOOP2	MOVFW   DELAY3_Init
	MOVWF   DELAY3
LOOP3	DECFSZ	DELAY3,F
	GOTO	LOOP3
	DECFSZ	DELAY2,F
	GOTO	LOOP2
	DECFSZ	DELAY1,F
	GOTO	LOOP1
	RETURN
	
;*******************************************************************************
; @brief    Conversión de binario natural a BCD Desempaquetado
;           
; @details  Convierte un valor binario crudo, almacenado en REG_BCD, en sus
;	    componentes posicionales de Centenas, Decenas y Unidades.
;	    Guarda los resultados en VAL_UNI, VAL_DEC y VAL_CEN
;*******************************************************************************	
CNV_BCD
    CLRF    VAL_UNI 	   
    CLRF    VAL_DEC
    CLRF    VAL_CEN
    TEST_CEN
		MOVLW   .100                
		SUBWF   REG_BCD,W   
		BTFSC   STATUS,C    
		GOTO    ADD_CEN     
		GOTO    TEST_DEC    
    TEST_DEC
		MOVLW   .10                                             
		SUBWF   REG_BCD,W   
		BTFSC   STATUS,C    
		GOTO    ADD_DEC    
		GOTO    TEST_UNI    
    TEST_UNI
		GOTO    ADD_UNI    
    ADD_CEN
		MOVWF   REG_BCD     
		INCF    VAL_CEN,F   
		GOTO    TEST_CEN                            
    ADD_DEC
		MOVWF   REG_BCD     
		INCF    VAL_DEC,F   
		GOTO    TEST_DEC    
    ADD_UNI
		MOVF    REG_BCD,W   
		MOVWF   VAL_UNI     
	RETURN   	

;*******************************************************************************
; @brief    Look_Up Tables (LUT) para control y decodificación de displays de 
;	    7 segmentos
;           
; @details  Enciende un display específico según el índice (1,2,3)
;	    Muestra un dígito específico en el display según el índice (0,1,...)
;*******************************************************************************	
TABLE_CTRL_DSPL_AC
    ADDWF   PCL,F
    RETLW   b'11111111'
    RETLW   b'11111110'	    ;Indice 1: Enciende DSPL_UNI
    RETLW   b'11111101'	    ;Indice 2: Enciende DSPL_DEC
    RETLW   b'11111011'	    ;Indice 3: Enciende DSPL_CEN
    
TABLE_DECO_DSPL_AC
    ADDWF   PCL,F
    RETLW   b'11000000'	    ;Indice 0: Número "0"
    RETLW   b'11111001'	    ;Indice 1: Número "1"
    RETLW   b'10100100'	    ;Indice 2: Número "2"
    RETLW   b'10110000'	    ;Indice 3: Número "3"
    RETLW   b'10011001'	    ;Indice 4: Número "4"
    RETLW   b'10010010'	    ;Indice 5: Número "5"
    RETLW   b'10000010'	    ;Indice 6: Número "6"
    RETLW   b'11111000'	    ;Indice 7: Número "7"
    RETLW   b'10000000'	    ;Indice 8: Número "8"
    RETLW   b'10011000'	    ;Indice 9: Número "9"
;===============================================================================        
    END
;===============================================================================

;======================================================
