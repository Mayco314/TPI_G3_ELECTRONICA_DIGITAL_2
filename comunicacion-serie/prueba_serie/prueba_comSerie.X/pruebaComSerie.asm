;*******************************************************************************
; @brief PRUEBA DE COMUNICACIÓN SERIE - FIRMWARE DE PRUEBA.
;
; @brief Programa de prueba a escala reducida de la comunicación serie entre
; el PIC16F887 y la interfaz en la PC.
;
; ; @details Contiene las bases de lo que se integrará a mayor escala en el
; firmware final:
; - Configuración de la EUSART en modo asíncrono (9600 baudios, 8N1).
; - Transmisión periódica, cada 1 s (base de tiempo del TMR0), de un dato fijo
;   en ASCII: centena, decena y unidad, seguidas de CR y LF.
; - Recepción por interrupción de los comandos de movimiento. Cada comando
;   válido (en esta prueba, W y S, en mayúscula) actualiza el estado de
;   movimiento (ESTADO_MOVIMIENTO), que el lazo principal refleja en los LEDs
;   RD2 y RD3 (en el firmware final, en los motores).
; - Timeout de comandos: si pasan 300 ms sin recibir un comando válido, el
;   estado vuelve a "quieto". El movimiento dura mientras la interfaz repite el
;   comando (tecla mantenida) y se detiene al soltarla o si se pierde la
;   comunicación.
; Permite verificar que la comunicación serie funciona de acuerdo al protocolo
; documentado en el README de comunicacion-serie y con la interfaz básica.
;
; @author G3- Grupo Bomb-bit
;
; @date 11/2026
;
; @version 1.0
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
    
;Valor constante para el offset del TMR0 para 10ms con cristal de 4MHz
;TMR0 = 256-[((t_timerOverflow*fclk)/(4*PS))-(2/PS)]
;TMR0 = 256-[((10ms*4MHz)/(4*256))-(2/256)] = 217
VALUE_OFFSET_TMR0 EQU .217
;Valor constante para el límite de desbordes
;N_timerOverflow = t_delay/t_timerOverflow
;N_timerOverflow = 1s/10ms = 100
VALUE_COUNTER_MAX_TMR0 EQU .100

 ;Valor constante para el límite de desbordes para timeout de movimiento 
;N_timerOverflow = t_delay/t_timerOverflow
;N_timerOverflow = 300ms/10ms = 30
VALUE_COUNTER_MAX_TIMEOUT EQU .30

;===============================================================================
; DEFINICIÓN DE VARIABLES
;===============================================================================
CBLOCK 0x70
    W_TEMP ;0x70
    STATUS_TEMP ;0x71
 ENDC

 CBLOCK 0x20
    COUNTER_TMR0	;Contador para detectar N desbordes del TMR0
    COUNTER_MAX_TMR0	;Cantidad máxima de desbordes del TMR0
    OFFSET_TMR0		;Valor de Offset del TMR0
    COUNTER_TIMEOUT	;Ticks de 10 ms desde el último comando válido.
    COUNTER_MAX_TIMEOUT ;Cantidad máxima de desbordes para Timeout
    
    REG_RX		;guarda el byte recibido
    
    VALUE_CEN_SENSOR1	;Valor sensado en centena, decena y unidad
    VALUE_DEC_SENSOR1
    VALUE_UNI_SENSOR1
    
    ESTADO_MOVIMIENTO  ;Valor con el que se decide como se mueven los motores(en este caso encendido de leds)
 ENDC
;===============================================================================
; DECLARACIÓN DE MACROS PARA CONFIGURACIÓN DE REGISTROS
;===============================================================================
 
CFG_LEDS MACRO
    BANKSEL TRISD
    BCF TRISD,TRISD2 ;RD2 Salida Digital
    BCF TRISD,TRISD3 ;RD3 Salida Digital
    BANKSEL PORTD
    CLRF PORTD	     ;Leds apagados 
    
    CLRF ESTADO_MOVIMIENTO ;iniciar en estado movimiento nulo (leds apagados)
 ENDM
    
LOAD_VALUES_SENSOR1 MACRO
    CLRF VALUE_CEN_SENSOR1     ;Asignación de valor sensado (000) de ejemplo a las variables unidad, decena y centena
    CLRF VALUE_DEC_SENSOR1
    CLRF VALUE_UNI_SENSOR1
ENDM 
    
CFG_TMR0 MACRO
    BANKSEL OPTION_REG
    MOVLW b'00000111'
    MOVWF OPTION_REG		    ;TMR0 Modo Temporizador y Preescaler de 1:256
    BANKSEL TMR0
    MOVLW VALUE_OFFSET_TMR0	    ;Desborde TMR0 cada 10 ms a 4 MHz
    MOVWF OFFSET_TMR0
    MOVWF TMR0
    MOVLW VALUE_COUNTER_MAX_TMR0
    MOVWF COUNTER_MAX_TMR0
    CLRF COUNTER_TMR0		    ;Iniciar cuenta de desbordes en 0
    
    MOVLW VALUE_COUNTER_MAX_TIMEOUT ;Cantidad máxima de ticks de 10 ms sin comando válido antes de frenar (300 ms)
    MOVWF COUNTER_MAX_TIMEOUT 
    CLRF COUNTER_TIMEOUT
    
 ENDM

CFG_UART_RX_TX MACRO
    BANKSEL TRISC
    BSF TRISC,TRISC7 ;RC7 Entrada Digital
    BCF TRISC,TRISC6 ;RC6 Salida Digital
    BANKSEL SPBRG
    MOVLW D'25' ;Transmisión Asíncrona de 8 bits a 9600 Bd
    MOVWF SPBRG
    BANKSEL TXSTA
    BCF TXSTA,SYNC ;Modo Asíncrono
    BSF TXSTA,BRGH ;Habilita Alta velocidad de Baud Rate
    BSF TXSTA,TXEN ;Habilita la Transmisión Serial
    BANKSEL RCSTA
    BSF RCSTA,CREN ;Habilita la Recepción Serial
    BSF RCSTA,SPEN ;Habilita el Puerto Serie
 ENDM

CFG_ISR MACRO
    BANKSEL INTCON
    BCF INTCON,T0IF ;Baja bandera Interrupción por Timer0
    BSF INTCON,T0IE ;Habilita Interrupción por Timer0
 
    BANKSEL PIE1
    BSF PIE1,RCIE ;Habilita Interrupción por Recepción de UART (RX)
    BANKSEL INTCON
    BSF INTCON,PEIE ;Habilita Interrupciones por Periféricos
    BSF INTCON,GIE ;Habilita Interrupciones Globales
 ENDM

;===============================================================================
; INICIALIZACIÓN DEL MCU (CÓDIGO ABSOLUTO)
;===============================================================================
    ORG 0x00            ;Vector de Reset
    GOTO INICIO         ;Salto al inicio del programa principal
    ORG 0x04            ;Vector de Interrupción
    GOTO ISR_INICIO     ;Salto al Rutina de Servicio de Interrupción
    ORG 0x05            ;Ubicación Programa Principal en la memoria

;===============================================================================
; INICIALIZACIÓN DE MACROS PARA CONFIGURACIÓN DE REGISTROS
;===============================================================================
INICIO	    ;-----Inicialización de Macros-------
	    CFG_LEDS
	    LOAD_VALUES_SENSOR1
	    CFG_TMR0
	    CFG_UART_RX_TX
	    CFG_ISR


;===============================================================================
; INICIO PROGRAMA PRINCIPAL
;===============================================================================
; @details Según el estado de movimiento, enciende los LEDs (1: RD2, 2: RD3,
; 0: ambos apagados).En el firmware final acá se accionan los motores.
;-------------------------------------------------------------------------------	    
MAIN_LOOP
    PRUEBO_ESTADO_MOVIMIENTO1			 
	MOVLW .1			 
	SUBWF ESTADO_MOVIMIENTO, W              
	BTFSS STATUS,Z				
	GOTO PRUEBO_ESTADO_MOVIMIENTO2
	BSF PORTD,RD2
	BCF PORTD,RD3
	GOTO MAIN_LOOP
    PRUEBO_ESTADO_MOVIMIENTO2
	MOVLW .2
	SUBWF ESTADO_MOVIMIENTO, W 
	BTFSS STATUS,Z
	GOTO ESTADO_MOVIMIENTO0
	BCF PORTD,RD2
	BSF PORTD,RD3
	GOTO MAIN_LOOP
    ESTADO_MOVIMIENTO0	
	BCF PORTD,RD2
	BCF PORTD,RD3
    GOTO MAIN_LOOP

;===============================================================================
; INICIALIZACIÓN DE RUTINAS DE SERVICIO DE INTERRUPCIÓN
;===============================================================================
ISR_INICIO
;----------Guardado de Contexto----------
    MOVWF W_TEMP
    SWAPF STATUS,W
    MOVWF STATUS_TEMP
;----------------------------------------
;-----Identificación de Interrupción-----
    BANKSEL INTCON		;Primero se verifica interrupción por TMR0,
    BTFSC INTCON,T0IF
    GOTO ISR_TMR0
    BANKSEL PIR1		;luego se verifica interrupción por RX.     
    BTFSC PIR1,RCIF		     
    GOTO ISR_UART_RX
    GOTO ISR_FIN

;----------------------------------------

;===============================================================================
; FINALIZACIÓN DE RUTINAS DE SERVICIO DE INTERRUPCIÓN
;===============================================================================
ISR_FIN
;--------Restauración de Contexto--------
    SWAPF STATUS_TEMP,W
    MOVWF STATUS
    SWAPF W_TEMP,F
    SWAPF W_TEMP,W
    RETFIE
;----------------------------------------

;===============================================================================
; SUBRUTINAS
;===============================================================================
;*******************************************************************************
; @brief Rutina de servicio de interrupción para Interrupciones del Timer 0
;
; @details Se ejecuta cada 10 ms. 1) Controla el timeout de movimiento: cuenta ticks desde el último comando válido
;   al llegar a 300 ms, vuelve al estado quieto. 2) Cuenta desbordes y, cada 100 (1 s), transmite el valor sensado.
;  3) Recarga el TMR0 y baja T0IF.
;*******************************************************************************
ISR_TMR0
    MOVF ESTADO_MOVIMIENTO,F
    BTFSC STATUS,Z 
    GOTO DESBORDE_1S
    INCF COUNTER_TIMEOUT
    MOVFW COUNTER_MAX_TIMEOUT     ; disparo de frenado si se cumple cantidad de tick sin comando  
    SUBWF COUNTER_TIMEOUT,W
    BTFSS STATUS, Z 
    GOTO DESBORDE_1S
    CLRF ESTADO_MOVIMIENTO 
    
    DESBORDE_1S
    INCF COUNTER_TMR0
    MOVFW COUNTER_MAX_TMR0 ;Cantidad de Desbordes Necesarios
    SUBWF COUNTER_TMR0,W
    BTFSS STATUS,Z	   ;Verificacion desbordes del TMR0
    GOTO RELOAD_TMR0
    CLRF COUNTER_TMR0
    
 
    START_TX				;Transmisión del valor sensado en ASCII: centena, decena, unidad, CR y LF
    MOVFW VALUE_CEN_SENSOR1
    ADDLW D'48' ;Offset ASCII ('0')
    CALL UART_TX_BYTE
    
    MOVFW VALUE_DEC_SENSOR1
    ADDLW D'48' ;Offset ASCII ('0')
    CALL UART_TX_BYTE
    
    MOVFW VALUE_UNI_SENSOR1
    ADDLW D'48' ;Offset ASCII ('0')
    CALL UART_TX_BYTE
    
    MOVLW D'13' ;Retorno de carro CR (\r)
    CALL UART_TX_BYTE
    MOVLW D'10' ;Salto de línea LF (\n)
    CALL UART_TX_BYTE
    
    RELOAD_TMR0
	MOVFW OFFSET_TMR0
	MOVWF TMR0
    CLR_FLAG_TMR0
	BANKSEL INTCON
	BCF INTCON,T0IF
	GOTO ISR_FIN
	
;*******************************************************************************
; @brief Transmisión de un byte de datos a través del módulo EUSART.
;
; @details Realiza polling sobre el bit TRMT de TXSTA para verificar
; que el registro de desplazamiento se encuentre vacío.
;*******************************************************************************
UART_TX_BYTE
    BANKSEL TXSTA
    LOOP_TX
        BTFSS TXSTA,TRMT
	GOTO LOOP_TX
    BANKSEL TXREG
    MOVWF TXREG
    RETURN

;*******************************************************************************
; @brief Rutina de servicio de interrupción para el UART-RX
;
;@details Lee el byte recibido y, si es un comando válido (W o S), guarda el
;estado de movimiento y reinicia el contador del timeout. Un byte desconocido se ignora.
;*******************************************************************************
ISR_UART_RX
    BANKSEL RCREG
    MOVFW RCREG
    MOVWF REG_RX
    
    MOVLW 0X57			;Comprueba si el dato que llego es "W"
    SUBWF REG_RX,W
    BTFSC STATUS,Z
    GOTO  MOVIMIENTO_ADELANTE	;En caso de que sí, se configura para que motores realicen avance
    
    MOVLW 0X53			;Comprueba si el dato que llego es "S"
    SUBWF REG_RX,W
    BTFSC STATUS,Z
    GOTO  MOVIMIENTO_ATRAS	;En caso de que sí, se configura para que motores realicen retroceso 
    GOTO SALIR
    
    
    MOVIMIENTO_ADELANTE
	MOVLW .1
    	MOVWF ESTADO_MOVIMIENTO 
    	GOTO RESETEAR_CUENTA_TIMEOUT
	
    MOVIMIENTO_ATRAS
    	MOVLW .2
    	MOVWF ESTADO_MOVIMIENTO 
    	GOTO RESETEAR_CUENTA_TIMEOUT
    
    RESETEAR_CUENTA_TIMEOUT
    CLRF COUNTER_TIMEOUT
    SALIR
    ;BANKSEL PIR1
    ;BCF PIR1,RCIF
    ;The value in the RCREG needs to be read to clear the RCIF interrupt.
    	GOTO ISR_FIN
    
    
;===============================================================================
    END
;===============================================================================

;===============================================================================