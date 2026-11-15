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
 ;Umbral para encender las luces (0-255)
 UMBRAL_LUZ		EQU .100
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
    ADC_BURST_STATE	;Variable para conversión ADC de los sensores (0x20)
    ;Variables de CNV_BCD
    VAL_UNI		;0x21
    VAL_DEC		;0x22
    VAL_CEN		;0x23
    REG_BCD		;0x24
    ;Variables para alarma de temperatura alta
    VAL_TEMP_MEDIR	;0x25
    DELAY1_Init		;0x26
    DELAY2_Init		;0x27
    DELAY3_Init		;0x28
    DELAY1		;0x29
    DELAY2		;0x30
    DELAY3		;0x31
    ;Variables para sensor de luminosidad LDR
    LDR_VAL             ; 8 bits crudos del LDR
    TEMP_ADC            ; Variable temporal para restas sucesivas
    BCD_CEN             ; Centenas (de LDR_VAL)
    BCD_DEC             ; Decenas (de LDR_VAL)
    BCD_UNI             ; Unidades (de LDR_VAL)
    ;Variables de TMR0
    COUNTER_TMR0	;0x31
    COUNTER_MAX_TMR0
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
CFG_SENSORES MACRO    ;Sensores LM35 y LDR
    BANKSEL ANSEL
    BSF	    ANSEL,ANS0
    BSF	    ANSEL,ANS1
    BANKSEL TRISA
    BSF	    TRISA,TRISA0    ;RA0: Entrada Analógica
    BSF	    TRISA,TRISA1    ;RA1: Entrada Analógica
ENDM
 
CFG_ADC MACRO		    ;ADC
    BANKSEL ADCON1
    BSF	    ADCON1,VCFG0    ;Vref+ = 2.56V
    BCF	    ADCON1,VCFG1    ;Vref- = VSS (0V)
    BCF	    ADCON1,ADFM	    ;Justificado a la izquierda (8b en ADRESH)
    BANKSEL ADCON0
    BCF	    ADCON0,ADCS1    
    BSF	    ADCON0,ADCS0    ;Fclk = Fosc/8 (4mhz/8)
    BCF	    ADCON0,CHS0	    ;Usa Canal 0 (AN0) por default
    BSF	    ADCON0,ADON	    ;Permite uso del ADC
    CLRF    DATA_DSPL_UNI
    CLRF    DATA_DSPL_DEC
    CLRF    DATA_DSPL_CEN   ;Pone en "0" las variables de displays
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
   CLRF	    COUNTER_TMR0	;Pone en "0" el contador de desbordes
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
 
CFG_LB MACRO		    ;Buzzer y Leds de Alarma
   BANKSEL	ANSELH
   BCF		ANSELH,ANS11
   BANKSEL	TRISB
   BCF		TRISB,TRISB4    ;Salida digital RB4
   BANKSEL	PORTB
   BCF		LB_TEMP		;Apaga leds y buzzer
ENDM
   
CFG_LUCES_AUTO MACRO	    ;Leds del sensor LDR
    BANKSEL TRISB
    BCF     TRISB,TRISB7        ; RB7 como salida digital (Luz Izquierda)
    BCF     TRISB,TRISB6        ; RB6 como salida digital (Luz Derecha)
    
    BANKSEL PORTB
    BCF     PORTB,RB7		;Arrancan los leds apagados
    BCF     PORTB,RB6
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
    CLRF	TRISC		;Puertos C y D como salidas digitales
    BANKSEL	PORTC
    MOVLW	b'11111111'
    MOVWF	PORTD		;Apaga segmentos
    MOVWF	PORTC		;Apaga displays
    MOVLW	.3
    MOVWF	COUNTER_DSPL	;Carga "3" al contador de displays
ENDM
    
DSPL_ALL_OFF MACRO	    ;Apaga todos los displays
    MOVLW   b'11111111'
    MOVWF   PORTD
    MOVWF   PORTC
ENDM
    
;===============================================================================
; INICIALIZACIÓN DEL MCU (CÓDIGO ABSOLUTO)
;===============================================================================    
    ORG     0x00	    ;Vector de Reset
    GOTO    INICIO	    ;Salto al inicio del programa principal
    ORG     0x04	    ;Vector de Interrupción
    GOTO    ISR_INICIO	    ;Salto al Rutina de Servicio de Interrupción
    ORG     0x05	    ;Ubicación Programa Principal en la memoria 

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
; INICIALIZACIÓN DE MACROS PARA CONFIGURACIÓN DE REGISTROS
;=============================================================================== 
INICIO      ;-----Inicialización de Macros-------
    CFG_SENSORES
    CFG_DSPL
    CFG_LB
    CFG_TMR0
    CFG_TMR1
    CFG_ADC
    CFG_ISR
    CFG_DELAY
    CFG_LUCES_AUTO

;===============================================================================
; INICIO PROGRAMA PRINCIPAL
;===============================================================================        
;*******************************************************************************
; @brief    Alarma (buzzer y led en paralelo) que avisa si la temperatura es
;	    igual o mayor a 40°C
;*******************************************************************************	    
MAIN_LOOP
    ;-------Temperatura >= 40°?---------
    MOVLW   .3
    MOVWF   VAL_TEMP_MEDIR
    MOVF    VAL_DEC,W
    SUBWF   VAL_TEMP_MEDIR,W
    BTFSS   STATUS,C
    GOTO    TEMP_ALTA	    ;Temperatura >= 40°C
    GOTO    TEMP_BAJA	    ;Temperatura < 40°C?

    TEMP_BAJA
    INCF    VAL_CEN
    DECFSZ  VAL_CEN	    ;Veo si VAL_CEN = 0
    GOTO    TEMP_ALTA	    ;VAL_CEN /= 0 --> Temperatura >= 100°C
    ;VALCEN = 0 --> Temperatura < 40°C
    BCF	    LB_TEMP	    ;Apaga alarma
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
	CLRF	ADC_BURST_STATE	;Resetea ADC_BURST_STATE
	BANKSEL	ADCON0
	BCF	ADCON0,CHS0	;Usa Canal 0 (AN0)
	BSF	ADCON0,GO	;Inicia conversión
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
    ;-------Verificación de Displays------
    MOVLW   .3			;¿Se multiplexó Display 3 (CEN)?
    SUBWF   COUNTER_DSPL,W
    BTFSC   STATUS,Z
    GOTO    UPDATE_DSPL_CEN
    MOVLW   .2			;¿Se multiplexó Display 2 (DEC)?
    SUBWF   COUNTER_DSPL,W
    BTFSC   STATUS,Z
    GOTO   UPDATE_DSPL_DEC
    MOVLW   .1			;¿Se multiplexó Display 1 (UNI)?
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
    GOTO    RELOAD_TMR1
    
    UPDATE_DSPL_DEC	;Actualiza display decena (Display 2)
    DSPL_ALL_OFF
    MOVF    DATA_DSPL_DEC,W
    CALL    TABLE_DECO_DSPL_AC
    MOVWF   PORTD
    MOVF    COUNTER_DSPL,W
    CALL    TABLE_CTRL_DSPL_AC
    MOVWF   PORTC
    CALL    DECF_COUNTER_DSPL
    GOTO    RELOAD_TMR1
    
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
   RST_COUNTER_DSPL		;Resetea contador de displays multiplexados
   MOVLW    .3
   MOVWF    COUNTER_DSPL
   RETURN
   
   DECF_COUNTER_DSPL		;Disminuye COUNTER_DSPL en 1
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
;	    a través de CNV_BCD (LM35)
;	    Actualiza displays con los datos obtenidos de LM35 (Temperatura)
;	    Convierte variable binaria recibida por AN1 a un BCD desempaquetado,
;	    a través de CNV_BCD (LDR)
;	    Enciende o apaga leds de LDR
;*******************************************************************************	  
   ISR_ADC
	MOVF	ADC_BURST_STATE,F
	BTFSC	STATUS,Z    
	GOTO	ACQ_LM35    ;ADC_BURST_STATE = 0? --> AN0 (LM35)
	GOTO	ACQ_LDR	    ;ADC_BURST_STATE = 1? --> AN1 (LDR)
;------------CONVERSIÓN DE VALOR OBTENIDO POR LM35--------------------	
	ACQ_LM35	    
	BSF	ADCON0,CHS0 ;Cambia a Canal 1 (AN1)
	MOVFW	ADRESH
	CLRF	REG_BCD
	MOVWF	REG_BCD	    ;Carga REG_BCD con valor obtenido por LM35
	CALL	CNV_BCD	    ;Conversión a BCD empaquetado de REG_BCD
;------ Actualiza variables de los displays con valor de temperatura --------
	MOVF	VAL_UNI,W
	MOVWF	DATA_DSPL_UNI
	MOVF	VAL_DEC,W
	MOVWF	DATA_DSPL_DEC
	MOVF	VAL_CEN,W
	MOVWF	DATA_DSPL_CEN
;------ Cambia al siguiente estado --------
	MOVLW	.1
	MOVWF	ADC_BURST_STATE
	BSF	ADCON0,GO	;Inicia conversión (en AN1)
	GOTO	CLR_FLAG_ADC	
;-----------CONVERSIÓN DE VALOR OBTENIDO POR LDR---------------------	
	ACQ_LDR			;Descompone valor obtenido por LDR
	MOVFW	ADRESH
	CLRF	LDR_VAL
	MOVWF	LDR_VAL		;Carga LDR_VAL con valor obtenido por LDR
	CALL	CONTROL_LUCES	;Chequea si encender luces
	CALL	BIN_A_BCD	;Conversión a BCD Empaquetado de LDR_VAL
	GOTO	CLR_FLAG_ADC
;----------------Control de leds de LDR----------------	
	CONTROL_LUCES
	BANKSEL LDR_VAL
	MOVLW   UMBRAL_LUZ
	SUBWF   LDR_VAL, W      ; W = LDR_VAL - 100
	BTFSS   STATUS, C       ; Si C=0, el resultado fue negativo (Poca luz)
	GOTO    PRENDER_LUCES
	;Hay luz suficiente (Apagar leds RC4 y RC5)
	BANKSEL PORTB
	BCF     PORTB,RB7
	BCF     PORTB,RB6
	RETURN

	PRENDER_LUCES	    ;Enciende luces de LDR
	BANKSEL PORTB
	BSF     PORTB,RB7
	BSF     PORTB,RB6
	RETURN
;------------BAJADA DE BANDERA DE INTERRUPCIÓN POR ADC----------	
	CLR_FLAG_ADC
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
; @brief    Conversión de valor de LM35 de binario natural a BCD Desempaquetado
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
; @brief    Conversión de valor de LDR de binario natural a BCD Desempaquetado
;           
; @details  Convierte un valor binario crudo, almacenado en LDR_VAL, en sus
;	    componentes posicionales de Centenas, Decenas y Unidades.
;	    Guarda los resultados en BCD_UNI, BCD_DEC y BCD_CEN
;*******************************************************************************
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

;======================================================



