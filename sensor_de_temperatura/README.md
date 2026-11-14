# Sensor de Temperatura



Descripción del funcionamiento del ADC que convertirá el valor obtenido del sensor de temperatura LM35, conectado a la PIC, realizando un chequeo periódico del voltaje enviado por este,  y visualizará el valor obtenido a través de 3 displays de 7 segmentos. Cuenta con un led y un buzzer que se encenderán en alarma cuando el sensor supere los 40°C.



1. #### COMPONENTES Y PINES UTILIZADOS
* Sensor de temperatura LM35			-> Pin AN0
* Voltaje de referencia+ 2.54V			-> Pin RA3
* Cristal de 4Mhz				-> Pines RA<7:6>
* 3 displays ánodo común de 7 segmentos	-> Pines RC<2:0>
* 7 segmentos de los displays			-> Pines RD<6:0>
* Buzzer y led conectados en paralelo		-> Pin RB4



#### 2\. FUNCIONAMIENTO DEL PROGRAMA

El programa funciona usando interrupciones por TIMER0 y TIMER1, para:

* Realizar una conversión periódica del voltaje enviado por el sensor de temperatura LM35 a un valor digital a través del ADC. Se usa un periodo de 1s de intermitencia con el TIMER0 para la conversión del ADC.
* Visualizar, a través de 3 displays ánodo común de 7 segmentos, el valor obtenido a través del sensor de temperatura, utilizando la multiplexación de los displays a través del puerto D. Se usa un periódo de 2.5ms de intermitencia con el TIMER1 para la multiplexación.
* Identificar si el valor de la temperatura obtenido supera los 40°C. En caso de hacerlo, encender un led y un buzzer, intermitentemente, conectados en forma paralela al pin RB4, que alarmen al usuario sobre el nivel alto de temperatura.



#### 3\. CONSTANTES, VARIABLES Y MACROS

###### 3.1 Constantes:

* LB\_TEMP			PORTB,RB4  	--> Led y Buzzer conectados en paralelo, encienden si el sensor de temperatura supera 40°C
* CTRL\_DSPL\_UNI		PORTC,RC0	--> Pin de control del DSPL\_UNI (Tercer display a la derecha)
* CTRL\_DSPL\_DEC		PORTC,RC1	--> Pin de control del DSPL\_DEC (Segundo display)
* CTRL\_DSPL\_CEN		PORTC,RC2	--> Pin de control del DSPL\_CEN (Primer display a la izquierda)
* VALUE\_OFFSET\_TMR0		EQU .60   	--> Offset del TMR0 que realiza un desbordamiento cada 50ms (Prescaler 1:256).
* VALUE\_COUNTER\_MAX\_TMR0	EQU .20  	--> Valor de máximos desbordamientos necesarios para alcanzar 1s de intermitencia. 50ms \* 20 = 1000ms = 1s
* VALUE\_OFFSET\_TMR1H		EQU 0xFE	--> Offset de TMR1H que realiza desbordamiento cada 2,5ms (Prescaler 1:8)
* VALUE\_OFFSET\_TMR1L		EQU 0x37	--> Offset de TMR1L que realiza desbordamiento cada 2,5ms (Prescaler 1:8)



###### 3.2 Variables:

* W\_TEMP --> 0x70 --> Variable general para guardado de contexto de W para interrupciones
* STATUS\_TEMP --> 0x71 --> Variable general para guardado de contexto de STATUS para interrupciones
* VAL\_UNI --> 0x20 --> Valor decimal de unidad convertida de binario natural proveniente del ADC.
* VAL\_DEC --> 0x21 --> Valor decimal de decena convertida de binario natural proveniente del ADC.
* VAL\_CEN --> 0x22 --> Valor decimal de centena convertida de binario natural proveniente del ADC.
* REG\_BCD --> 0x23 --> Registro usado para la conversión de binario natural a BCD del valor proveniente de ADC.
* VAL\_TEMP\_MEDIR --> 0x24 --> Variable utilizada para comprobar si la temperatura ha superado 40°C
* DELAY1\_Init --> 0x25 --> Dato del DELAY\_1 para el retardo por software de LB\_TEMP
* DELAY2\_Init --> 0x26 -->Dato del DELAY\_2 para el retardo por software de LB\_TEMP
* DELAY3\_Init --> 0x27 --> Dato del DELAY\_3 para el retardo por software de LB\_TEMP
* DELAY1 --> 0x28 --> DELAY\_1 para el retardo por software de LB\_TEMP
* DELAY2 --> 0x29 --> DELAY\_2 para el retardo por software de LB\_TEMP
* DELAY3 --> 0x30 --> DELAY\_3 para el retardo por software de LB\_TEMP
* COUNTER\_TMR0 --> 0x31 --> Contador de desbordes realizados
* COUNTER\_MAX\_TMR0 --> 0x32 --> Cantidad de desbordes necesarios
* OFFSET\_TMR0 --> 0x33 --> Offset en TMR0 para tiempo de desborde
* DATA\_DSPL\_UNI --> 0x34 --> Valor de número que deberá mostrar el DSPL\_UNI (Tercer display a la derecha)
* DATA\_DSPL\_DEC --> 0x35 --> Valor de número que deberá mostrar el DSPL\_DEC (Segundo display)
* DATA\_DSPL\_CEN --> 0x36 --> Valor de número que deberá mostrar el DSPL\_CEN (Primer display a la izquierda)
* COUNTER\_DSPL --> 0x37 --> Contador de displays multiplexados



###### 3.3 Macros:

* CFG\_CH\_LM35\_SENSOR --> Configura bits relacionados al sensor de temperatura LM35
* CFG\_ADC --> Configura bits relacionados al ADC
* CFG\_TMR0 --> Configura bits relacionados al TMR0
* CFG\_TMR1 --> Configura bits relacionados al TMR1
* CFG\_ISR --> Configura bits relacionados al las ISRs
* CFG\_LB --> Configura bits relacionados al led y buzzer de alarma. Apaga led y buzzer.
* CFG\_DELAY --> Configura retardo por software de la alarma LB\_TEMP.
* CFG\_DSPL --> Configura bits relacionados a los displays. Apaga displays y segmentos
* DSPL\_ALL\_OFF --> Apaga displays y segmentos.



#### 4\. CÓDIGO EN EL MAIN LOOP

El programa utiliza el main loop para gestionar la alarma de temperatura alta. Si se comprueba que la temperatura ha igualado o superado los 40°C, se encenderán un led y un buzzer, conectados en paralelo, de forma intermitente, hasta que la temperatura descenda hasta por debajo de 40°C. Para su intermitencia, se utiliza un retardo por software de 3 bucles anidados.

* Se carga el valor decimal "3" a la variable VAL\_TEMP\_MEDIR.
* Comparamos si el valor que se encuentra en la variable VAL\_DEC (el dígito que mostrará el segundo display, es decir, la decena) es mayor o igual a 4. Para esto, usamos SUBWF para restar VAL\_DEC a VAL\_TEMP\_MEDIR (3 - VAL\_DEC).
* Chequemos el estado del bit C. Si no hay carry, significa que la temperatura es mayor o igual a 40°C. Por lo tanto, vamos a TEMP\_ALTA. Si hay carry, la temperatura es baja, por lo que vamos a TEMP\_BAJA.
* En TEMP\_ALTA, llamamos a la subrutina DELAY\_3LOOP, que realizará el retardo por software de 3 bucles anidados. Una vez terminado, encenderemos LB\_TEMP, y llamaremos nuevamente a DELAY\_3LOOP. Por último, apagaremos LB\_TEMP. De esta forma, se realiza la intermitencia de la alarma.
* En TEMP\_BAJA, apagamos LB\_TEMP. Al terminar cualquiera de los dos caminos, retornamos a MAIN\_LOOP.



#### 5\. DESCRIPCIÓN DE LAS INTERRUPCIONES

El programa cuenta con 3 rutinas de interrupción: ISR\_TMR0 (para el chequeo periódico del sensor LM35), ISR\_TMR1 (para la multiplexación de los displays), y ISR\_ADC (para la transformación del valor obtenido en ISR\_TMR0 en valores identificables por la computadora).



##### 5.1 Interrupción por TMR0 (ISR\_TMR0)

La rutina de interrupción consiste en, con un retardo de 1s de intermitencia por TMR0, convertir periódicamente los datos obtenidos a través del sensor de temperatura LM35 en datos digitales legibles por la PC, utilizando el ADC.

* Utiliza la variable COUNTER\_TMR0 para identificar si es necesario recargar el TMR0. La variable aumenta con cada interrupción.
* Usa SUBWF para saber si COUNTER\_TMR0 ha alcanzado el número máximo de desbordes necesarios, descritos en COUNTER\_MAX\_TMR0.
* Si no ha alcanzado la cantidad de desbordes necesarios, se recarga TMR0 y baja la bandera de interrupción, y se retorna a ISR\_FIN para recuperar contexto.
* Si ha alcanzado la cantidad de desbordes necesarios, significa que ha pasado 1s, por lo que limpiamos COUNTER\_TMR0 para futuras interrupciones e iniciamos la conversión por ADC con START\_CONVERSION.
* START\_CONVERSION coloca el bit GO/DONE del registro ADCON0 en 1, para iniciar la conversión analógica-digital de los datos obtenidos por el sensor LM35.
* Una vez terminada la conversión, recargamos TMR0 con RELOAD\_TMR0 y bajamos la bandera de interrupción por TMR0 con CLR\_FLAG\_TMR0.
* Vamos a ISR\_FIN para recuperar contexto y terminar el servicio de interrupción.



##### 5.2 Interrupción por TMR1 (ISR\_TMR1)

La rutina de interrupción consiste en, usando un retardo de 2.5 ms de intermitencia por TMR1, realizar una multiplexación de 3 displays de cátodo común de 7 segmentos, mostrando los datos guardados en las variables DATA\_DSPL\_x correspondientes a cada display. Estas variables estarán cargadas con los datos obtenidos por el ADC de la temperatura identificada por el sensor LM35 (ver Sección 3.4). Usamos Look\_Up Tables o LUTs para el control y decodificación de cada display.

* Inicialmente, llamamos a la subrutina RST\_COUNTER\_DSPL, la cual setea el contador de displays en '3'.
* Verificamos si cada display ha sido multiplexado, utilizando SUBWF para chequear el valor actual de COUNTER\_DSPL. Con cada display siendo identificado por un número (3,2,1), será el turno de que un display sea multiplexado si COUNTER\_DSPL es igual a su número.
* Si sabemos que es hora de multiplexar un display, vamos a la subrutina UPDATE\_DSPL\_X, dependiendo del display que señala COUNTER\_DSPL.
* Cada subrutina UPDATE\_DSPL\_x inicia apagando todos los displays con DSPL\_ALL\_OFF. Introducimos el valor de la variable DATA\_DSPL\_x respectiva al display que esta siendo multiplexado en W.
* Llamamos TABLE\_DECO\_DSPL\_AC, la LUT que nos indicará, usando el registro PCL, que dígito mostrar en los segmentos del display que estamos multiplexando, dependiendo de su respectivo valor de DATA\_DSPL\_x. La tabla cuenta con índices de 0 a 9, indicando el conjunto de bits correspondientes a la visualización de tal número en los segmentos del display.
* Al retornar de TABLE\_DECO\_DSPL\_AC, cargamos a PORTD (el puerto conectado a los segmentos de los displays), el valor de W con los bits que mostraran el número que queremos en el display que estamos multiplexando.
* Cargamos COUNTER\_DSPL en W, para determinar el número de display que estamos multiplexando, y llamamos TABLE\_CTRL\_DSPL\_AC, la LUT que encenderá el pin específico al display que estamos multiplexando. Cuenta con índices del 0 al 3, sin utilizar el 0, y cada número indica el pin que encenderá el display correspondiente a tal índice.
* Regresando de TABLE\_CTRL\_DSPL\_AC, cargamos el valor de W con el pin de display a encender a PORTC (el puerto que controla los displays).
* Usamos la subrutina DECF\_COUNTER\_DSPL para disminuir en 1 el COUNTER\_DSPL, permitiéndonos multiplexar el siguiente display.
* Una vez terminada cada rutina UPDATE\_DSPL\_x, retornaremos a la línea de código siguiente a tal rutina en ISR\_TMR1. Una multiplexados los 3 displays (realizadas las 3 rutinas UPDATE\_DSPL\_x), usaremos RST\_COUNTER\_DSPL para colocar el contador de displays nuevamente en '3', y recargaremos TMR1 con RELOAD\_TMR1.
* Usaremos CLR\_FLAG\_TMR1 para bajar la bandera de interrupción por TMR1, y nos dirigimos a ISR\_FIN, recuperando contexto y terminando la ISR.



##### 5.3 Interrupción por ADC (ISR\_ADC)

La rutina de interrupción consistirá en convertir la variable binaria cruda recibida por el sensor de temperatura LM35, guardada en ADRESH, a BCD desempaquetado, dividiéndola en tres variables posicionales (VAL\_UNI, VAL\_DEC y VAL\_CEN). Actualizamos las variables DATA\_DSPL\_x respectivas a cada posición.

* Cargamos ADRESH, que incluye los 8 bits más significativos de la conversión a digital por el ADC, en la variable REG\_BCD.
* Llamamos la subrutina CNV\_BCD, que tomará el valor en REG\_BCD y lo convertirá en 3 componentes posicionales (VAL\_UNI, VAL\_DEC y VAL\_CEN), con cada valor en decimal. Al terminar la conversión, retornamos a donde nos quedamos en ISR\_ADC.
* Cargamos cada valor DATA\_DSPL\_x con su valor respectivo de VAL\_x, para saber que número deberá mostrar cada display.
* Vamos a ISR\_FIN para recuperar contexto y terminar la ISR.

